// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/IRedemption.sol";
import "../storage/RedemptionStorage.sol";
import "../../token/interface/ILuxShareToken.sol";
import "../../token/interface/ILuxShareFactory.sol";
import "../../registry/interface/IIdentityRegistry.sol";
import "../../compliance/interface/IModularCompliance.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Redemption
 * @dev Implementation of redemption contract using Diamond Storage
 * @notice Handles the redemption process for ShareTokens to underlying Asset NFTs
 * @notice Integrates with compliance system to ensure only eligible investors can redeem
 */
contract Redemption is IRedemption, Ownable {
    using RedemptionStorage for RedemptionStorage.Layout;

    /// Constructor
    
    constructor(address factory_, address identityRegistry_) Ownable(msg.sender) {
        require(factory_ != address(0), "Redemption: invalid factory");
        require(identityRegistry_ != address(0), "Redemption: invalid identity registry");
        
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        s.factory = factory_;
        s.identityRegistry = IIdentityRegistry(identityRegistry_);
    }
    
    /// External Functions
    
    /**
     * @dev Register an asset mapping (ShareToken -> AssetNFT), only NFT holder(issuer) can call this function
     * @param shareToken The address of the share token
     * @param assetNFTContract The address of the asset NFT contract
     * @param assetTokenId The ID of the asset NFT
     */
    function registerAsset(
        address shareToken,
        address assetNFTContract,
        uint256 assetTokenId
    ) external override {
        require(shareToken != address(0), "Redemption: invalid shareToken");
        require(assetNFTContract != address(0), "Redemption: invalid NFT contract");
        
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        
        // Check if already registered
        require(!s.assetMappings[shareToken].registered, "Redemption: already registered");
        
        // Verify the issuer owns the NFT
        require(
            IERC721(assetNFTContract).ownerOf(assetTokenId) == address(s.identityRegistry.identity(msg.sender)),
            "Redemption: caller does not own NFT"
        );
        
        // Register the mapping
        s.assetMappings[shareToken] = RedemptionStorage.AssetMapping({
            assetNFTContract: assetNFTContract,
            assetTokenId: assetTokenId,
            issuer: msg.sender,
            registered: true
        });
        
        emit AssetRegistered(shareToken, assetNFTContract, assetTokenId, msg.sender);
    }
    
    /**
     * @dev Unregister an asset mapping
     * @param shareToken The address of the share token
     */
    function unregisterAsset(address shareToken) external override {
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        
        require(
            msg.sender == s.assetMappings[shareToken].issuer,
            "Redemption: not authorized"
        );
        require(s.assetMappings[shareToken].registered, "Redemption: not registered");
        require(!s.hasActiveRedemption[shareToken], "Redemption: has active redemption");
        
        delete s.assetMappings[shareToken];
        
        emit AssetUnregistered(shareToken);
    }
    
    /**
     * @dev Request redemption of ShareToken for underlying Asset NFT, only redeemer can call this function
     * @param shareToken The address of the share token
     * @param memo The memo for the redemption
     * @return redemptionId The ID of the created redemption request
     */
    function requestRedemption(
        address shareToken,
        string calldata memo
    ) external override returns (uint256 redemptionId) {
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        
        // Check asset is registered
        require(s.assetMappings[shareToken].registered, "Redemption: shareToken not registered");
        
        // Check no active redemption for this shareToken
        require(!s.hasActiveRedemption[shareToken], "Redemption: active redemption exists");
        
        // Get asset mapping
        RedemptionStorage.AssetMapping memory assetMapping = s.assetMappings[shareToken];
        
        ILuxShareToken shareTokenContract = ILuxShareToken(shareToken);
        
        // Check caller holds ALL shares
        uint256 totalSupply = shareTokenContract.totalSupply();
        uint256 callerBalance = shareTokenContract.balanceOf(msg.sender);
        
        require(totalSupply > 0, "Redemption: no shares exist");
        require(callerBalance == totalSupply, "Redemption: must hold all shares");
        
        // Compliance check: verify redeemer is eligible
        _checkCompliance(shareToken, msg.sender);
        
        // Verify issuer still owns the NFT
        require(
            IERC721(assetMapping.assetNFTContract).ownerOf(assetMapping.assetTokenId) == address(s.identityRegistry.identity(assetMapping.issuer)),
            "Redemption: issuer no longer owns NFT"
        );
        
        // Create redemption record
        redemptionId = ++s.redemptionCounter;
        
        s.redemptions[redemptionId] = RedemptionRecord({
            redemptionId: redemptionId,
            shareToken: shareToken,
            redeemer: msg.sender,
            totalShares: totalSupply,
            assetNFTContract: assetMapping.assetNFTContract,
            assetTokenId: assetMapping.assetTokenId,
            issuer: assetMapping.issuer,
            status: RedemptionStatus.Requested,
            requestTimestamp: block.timestamp,
            completedTimestamp: 0,
            memo: memo
        });
        
        // Track redemptions
        s.userRedemptions[msg.sender].push(redemptionId);
        s.shareTokenRedemptions[shareToken].push(redemptionId);
        s.hasActiveRedemption[shareToken] = true;
        s.activeRedemptionId[shareToken] = redemptionId;
        
        emit RedemptionRequested(
            redemptionId,
            shareToken,
            msg.sender,
            totalSupply,
            block.timestamp
        );
    }
    
    /**
     * @dev Lock the shares, only redeemer can call this function
     * @param redemptionId The ID of the redemption
     */
    function lockShares(uint256 redemptionId) external override {
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        
        RedemptionRecord storage redemption = s.redemptions[redemptionId];
        
        // Verify redemption exists and is in correct state
        require(redemption.redeemer != address(0), "Redemption: does not exist");
        require(redemption.status == RedemptionStatus.Requested, "Redemption: invalid status");
        require(msg.sender == redemption.redeemer, "Redemption: not redeemer");
        
        ILuxShareToken shareToken = ILuxShareToken(redemption.shareToken);
        
        // Verify redeemer still holds all shares
        uint256 currentBalance = shareToken.balanceOf(redemption.redeemer);
        uint256 currentTotalSupply = shareToken.totalSupply();
        
        require(currentBalance == currentTotalSupply, "Redemption: balance changed");
        require(currentTotalSupply == redemption.totalShares, "Redemption: supply changed");
        
        // Compliance check again
        _checkCompliance(redemption.shareToken, redemption.redeemer);

        // Verify not have frozen tokens
        require(shareToken.getFrozenTokens(redemption.redeemer) == 0, "Redemption: has frozen tokens");

        // Force transfer all shares to issuer identity
        ILuxShareFactory factoryContract = ILuxShareFactory(s.factory);
        factoryContract.forcedTransfer(redemption.shareToken, redemption.redeemer, redemption.issuer, redemption.totalShares);
        
        // Update status
        redemption.status = RedemptionStatus.SharesLocked;
        
        emit SharesLocked(
            redemptionId,
            redemption.shareToken,
            redemption.totalShares,
            block.timestamp
        );
    }
    
    /**
     * @dev Burn the shares, only issuer can call this function
     * @param redemptionId The ID of the redemption
     */
    function burnShares(uint256 redemptionId) external override {
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        
        RedemptionRecord storage redemption = s.redemptions[redemptionId];
        
        // Verify redemption exists and is in correct state
        require(redemption.redeemer != address(0), "Redemption: does not exist");
        require(redemption.status == RedemptionStatus.SharesLocked, "Redemption: invalid status");
        
        // Can be called by issuer
        require(msg.sender == redemption.issuer, "Redemption: not authorized");
        
        ILuxShareToken shareToken = ILuxShareToken(redemption.shareToken);
        
        // Verify this contract holds the shares
        uint256 issuerBalance = shareToken.balanceOf(redemption.issuer);
        require(issuerBalance >= redemption.totalShares, "Redemption: insufficient balance");
        
        // Burn the shares through factory
        ILuxShareFactory factoryContract = ILuxShareFactory(s.factory);
        factoryContract.burnShareTokens(redemption.shareToken, redemption.issuer, redemption.totalShares);
        
        // Verify total supply is now 0
        require(shareToken.totalSupply() == 0, "Redemption: supply not zero");
        
        // Update status
        redemption.status = RedemptionStatus.SharesBurned;
        
        emit SharesBurned(
            redemptionId,
            redemption.shareToken,
            redemption.totalShares,
            block.timestamp
        );
    }
    
    /**
     * @dev Complete the redemption, only issuer can call this function
     * @param redemptionId The ID of the redemption
     */
    function completeRedemption(uint256 redemptionId) external override {
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        
        RedemptionRecord storage redemption = s.redemptions[redemptionId];
        
        // Verify redemption exists and is in correct state
        require(redemption.redeemer != address(0), "Redemption: does not exist");
        require(redemption.status == RedemptionStatus.SharesBurned, "Redemption: invalid status");
        
        // Can be called by issuer
        require(msg.sender == redemption.issuer, "Redemption: not authorized");
        
        // Final compliance check
        _checkCompliance(redemption.shareToken, redemption.redeemer);
        
        // Transfer NFT from issuer to redeemer
        ILuxShareFactory factoryContract = ILuxShareFactory(s.factory);
        factoryContract.transferAssetNFT(redemption.assetNFTContract, redemption.issuer, redemption.redeemer, redemption.assetTokenId);
        
        // Update status
        redemption.status = RedemptionStatus.Completed;
        redemption.completedTimestamp = block.timestamp;
        
        // Clear active redemption flag
        s.hasActiveRedemption[redemption.shareToken] = false;
        delete s.activeRedemptionId[redemption.shareToken];
        
        emit RedemptionCompleted(
            redemptionId,
            redemption.shareToken,
            redemption.redeemer,
            redemption.assetNFTContract,
            redemption.assetTokenId,
            block.timestamp
        );
    }
    
    /**
     * @dev Cancel the redemption
     * @param redemptionId The ID of the redemption
     */
    function cancelRedemption(uint256 redemptionId) external override {
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        
        RedemptionRecord storage redemption = s.redemptions[redemptionId];
        
        // Verify redemption exists and is in correct state
        require(redemption.redeemer != address(0), "Redemption: does not exist");
        // Can only cancel if not yet completed
        require(redemption.status != RedemptionStatus.Completed, "Redemption: already completed");
        // Can only be cancelled by redeemer
        require(msg.sender == redemption.redeemer, "Redemption: not authorized");
        
        // If shares are locked, return them to redeemer
        if (redemption.status == RedemptionStatus.SharesLocked) {
            ILuxShareFactory factoryContract = ILuxShareFactory(s.factory);
            factoryContract.forcedTransfer(redemption.shareToken, redemption.redeemer, redemption.issuer, redemption.totalShares);
        }
        
        // Update status
        RedemptionStatus oldStatus = redemption.status;
        redemption.status = RedemptionStatus.Cancelled;
        
        // Clear active redemption flag if it was active
        if (oldStatus != RedemptionStatus.Cancelled) {
            s.hasActiveRedemption[redemption.shareToken] = false;
            delete s.activeRedemptionId[redemption.shareToken];
        }
        
        emit RedemptionCancelled(
            redemptionId,
            redemption.shareToken,
            redemption.redeemer,
            block.timestamp
        );
    }
    
    /// View Functions
    
    /**
     * @dev Get the redemption record
     * @param redemptionId The ID of the redemption
     * @return record The redemption record
     */
    function getRedemption(uint256 redemptionId) 
        external 
        view 
        override 
        returns (RedemptionRecord memory record) 
    {
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        return s.redemptions[redemptionId];
    }
    
    /**
     * @dev Get the asset mapping
     * @param shareToken The address of the share token
     * @return assetNFTContract The address of the asset NFT contract
     * @return assetTokenId The ID of the asset NFT
     * @return issuer The address of the issuer who holds the NFT
     */
    function getAssetMapping(address shareToken) 
        external 
        view 
        override 
        returns (
            address assetNFTContract,
            uint256 assetTokenId,
            address issuer
        ) 
    {
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        RedemptionStorage.AssetMapping memory assetMap = s.assetMappings[shareToken];
        
        require(assetMap.registered, "Redemption: not registered");
        
        return (
            assetMap.assetNFTContract,
            assetMap.assetTokenId,
            assetMap.issuer
        );
    }
    
    /**
     * @dev Get the redemptions by redeemer
     * @param redeemer The address of the redeemer
     * @return redemptionIds The IDs of the redemptions
     */
    function getRedemptionsByRedeemer(address redeemer) 
        external 
        view 
        override 
        returns (uint256[] memory redemptionIds) 
    {
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        return s.userRedemptions[redeemer];
    }
    
    /**
     * @dev Get the redemptions by share token
     * @param shareToken The address of the share token
     * @return redemptionIds The IDs of the redemptions
     */
    function getRedemptionsByShareToken(address shareToken) 
        external 
        view 
        override 
        returns (uint256[] memory redemptionIds) 
    {
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        return s.shareTokenRedemptions[shareToken];
    }
    
    /**
     * @dev Is the share token registered
     * @param shareToken The address of the share token
     * @return registered Whether the share token is registered
     */
    function isShareTokenRegistered(address shareToken) 
        external 
        view 
        override 
        returns (bool registered) 
    {
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        return s.assetMappings[shareToken].registered;
    }
    
    /**
     * @dev Get the total redemptions
     * @return count The total number of redemptions
     */
    function getTotalRedemptions() 
        external 
        view 
        override 
        returns (uint256 count) 
    {
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        return s.redemptionCounter;
    }
    
    /// Internal Functions
    
    /**
     * @dev Check compliance for redemption
     * @param shareToken The address of the share token
     * @param investor The address of the investor to check
     */
    function _checkCompliance(address shareToken, address investor) internal view {
        RedemptionStorage.Layout storage s = RedemptionStorage.layout();
        
        // Check identity exists
        require(
            s.identityRegistry.isVerified(investor),
            "Redemption: investor not verified"
        );
        
        // Get compliance module from share token
        ILuxShareToken shareTokenContract = ILuxShareToken(shareToken);
        IModularCompliance compliance = shareTokenContract.compliance();
        
        // Check compliance for redemption (use canTransfer as proxy for compliance check)
        require(
            compliance.canTransfer(investor, investor, 0),
            "Redemption: compliance check failed"
        );
    }
}

