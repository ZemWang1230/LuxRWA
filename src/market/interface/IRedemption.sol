// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/**
 * @title IRedemption
 * @dev Interface for redemption contract
 * @notice Handles redemption of ShareTokens for underlying Asset NFTs
 */
interface IRedemption {
    /// Enums
    
    /**
     * @dev Redemption status enum
     * Requested: Redemption request has been initiated
     * SharesLocked: All shares have been transferred to redemption contract
     * SharesBurned: Shares have been burned
     * Completed: NFT has been transferred to redeemer
     * Cancelled: Redemption has been cancelled
     */
    enum RedemptionStatus {
        Requested,
        SharesLocked,
        SharesBurned,
        Completed,
        Cancelled
    }
    
    /// Structs
    
    /**
     * @dev Redemption record structure
     */
    struct RedemptionRecord {
        uint256 redemptionId;           // Unique redemption ID
        address shareToken;             // ShareToken address being redeemed
        address redeemer;               // Address of the redeemer
        uint256 totalShares;            // Total shares amount at redemption
        address assetNFTContract;       // Asset NFT contract address
        uint256 assetTokenId;           // Asset NFT token ID
        address issuer;                 // Original issuer address
        RedemptionStatus status;        // Current status
        uint256 requestTimestamp;       // When redemption was requested
        uint256 completedTimestamp;     // When redemption was completed
        string memo;                    // Optional memo/notes
    }
    
    /// Events
    
    event AssetRegistered(
        address indexed shareToken,
        address indexed assetNFTContract,
        uint256 indexed assetTokenId,
        address issuer
    );
    
    event AssetUnregistered(
        address indexed shareToken
    );
    
    event RedemptionRequested(
        uint256 indexed redemptionId,
        address indexed shareToken,
        address indexed redeemer,
        uint256 totalShares,
        uint256 timestamp
    );
    
    event SharesLocked(
        uint256 indexed redemptionId,
        address indexed shareToken,
        uint256 amount,
        uint256 timestamp
    );
    
    event SharesBurned(
        uint256 indexed redemptionId,
        address indexed shareToken,
        uint256 amount,
        uint256 timestamp
    );
    
    event RedemptionCompleted(
        uint256 indexed redemptionId,
        address indexed shareToken,
        address indexed redeemer,
        address assetNFTContract,
        uint256 assetTokenId,
        uint256 timestamp
    );
    
    event RedemptionCancelled(
        uint256 indexed redemptionId,
        address indexed shareToken,
        address indexed redeemer,
        uint256 timestamp
    );
    
    /// Functions
    
    /**
     * @dev Register asset mapping (ShareToken -> AssetNFT)
     * @param shareToken Share token address
     * @param assetNFTContract Asset NFT contract address
     * @param assetTokenId Asset token ID
     */
    function registerAsset(
        address shareToken,
        address assetNFTContract,
        uint256 assetTokenId
    ) external;
    
    /**
     * @dev Unregister asset mapping
     * @param shareToken Share token address
     */
    function unregisterAsset(address shareToken) external;
    
    /**
     * @dev Request redemption of ShareToken for underlying Asset NFT
     * @param shareToken Share token address to redeem
     * @param memo Optional memo/notes for the redemption
     * @return redemptionId The ID of the created redemption request
     */
    function requestRedemption(
        address shareToken,
        string calldata memo
    ) external returns (uint256 redemptionId);
    
    /**
     * @dev Lock shares by transferring them to redemption contract
     * @param redemptionId The redemption ID
     */
    function lockShares(uint256 redemptionId) external;
    
    /**
     * @dev Burn the locked shares
     * @param redemptionId The redemption ID
     */
    function burnShares(uint256 redemptionId) external;
    
    /**
     * @dev Complete redemption by transferring NFT to redeemer
     * @param redemptionId The redemption ID
     */
    function completeRedemption(uint256 redemptionId) external;
    
    /**
     * @dev Cancel a redemption request
     * @param redemptionId The redemption ID
     */
    function cancelRedemption(uint256 redemptionId) external;
    
    /**
     * @dev Get redemption record by ID
     * @param redemptionId The redemption ID
     * @return record The redemption record
     */
    function getRedemption(uint256 redemptionId) external view returns (RedemptionRecord memory record);
    
    /**
     * @dev Get asset mapping for a share token
     * @param shareToken Share token address
     * @return assetNFTContract Asset NFT contract address
     * @return assetTokenId Asset token ID
     * @return issuer Issuer address
     */
    function getAssetMapping(address shareToken) external view returns (
        address assetNFTContract,
        uint256 assetTokenId,
        address issuer
    );
    
    /**
     * @dev Get redemptions by redeemer address
     * @param redeemer Redeemer address
     * @return redemptionIds Array of redemption IDs
     */
    function getRedemptionsByRedeemer(address redeemer) external view returns (uint256[] memory redemptionIds);
    
    /**
     * @dev Get redemptions by share token
     * @param shareToken Share token address
     * @return redemptionIds Array of redemption IDs
     */
    function getRedemptionsByShareToken(address shareToken) external view returns (uint256[] memory redemptionIds);
    
    /**
     * @dev Check if a share token is registered
     * @param shareToken Share token address
     * @return registered Whether the share token is registered
     */
    function isShareTokenRegistered(address shareToken) external view returns (bool registered);
    
    /**
     * @dev Get total number of redemptions
     * @return count Total redemption count
     */
    function getTotalRedemptions() external view returns (uint256 count);
}

