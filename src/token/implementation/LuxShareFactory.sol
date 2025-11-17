// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/ILuxShareFactory.sol";
import "../interface/ILuxAssetNFT.sol";
import "../interface/ILuxShareToken.sol";
import "../storage/TokenStorage.sol";
import "../../compliance/interface/IModularCompliance.sol";
import "../../registry/interface/IIdentityRegistry.sol";
import "./LuxAssetNFT.sol";
import "./LuxShareToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LuxShareFactory
 * @dev Central factory for the LuxRWA token ecosystem
 * @notice Factory-centric architecture inspired by T-REX ERC-3643
 * @notice This contract:
 *         1. Deploys and manages AssetNFT contracts
 *         2. Creates ShareToken contracts for luxury assets
 *         3. Controls critical functions across the ecosystem
 *         4. Manages compliance and identity registry bindings
 */
contract LuxShareFactory is ILuxShareFactory, Ownable {
    using TokenStorage for TokenStorage.ShareFactoryLayout;

    // Events
    event AssetNFTDeployed(address indexed assetNFT, string name, string symbol);
    event ComplianceSet(address indexed compliance);
    event IdentityRegistrySet(address indexed identityRegistry);
    event OperatorAuthorized(address indexed operator, bool status);

    constructor() Ownable(msg.sender) {
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        s.initialized = true;
    }

    // ==================== Factory Initialization ====================

    /**
     * @dev Initialize factory with core components
     * @param identityRegistry_ The address of the identity registry
     * @param defaultCompliance_ The address of the default compliance module
     */
    function initialize(
        address identityRegistry_,
        address defaultCompliance_
    ) external onlyOwner {
        require(identityRegistry_ != address(0), "LuxShareFactory: invalid identity registry");
        require(defaultCompliance_ != address(0), "LuxShareFactory: invalid compliance");

        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        
        s.identityRegistry = IIdentityRegistry(identityRegistry_);
        s.defaultCompliance = IModularCompliance(defaultCompliance_);
        
        emit IdentityRegistrySet(identityRegistry_);
        emit ComplianceSet(defaultCompliance_);
    }

    // ==================== Asset NFT Management ====================

    /**
     * @dev Deploy a new AssetNFT contract
     * @param name_ The name of the NFT collection
     * @param symbol_ The symbol of the NFT collection
     * @return assetNFT The address of the deployed AssetNFT contract
     */
    function deployAssetNFT(
        string memory name_,
        string memory symbol_
    ) external onlyOwner returns (address assetNFT) {
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        // Deploy new AssetNFT
        LuxAssetNFT nft = new LuxAssetNFT(name_, symbol_, address(this), address(s.identityRegistry));
        assetNFT = address(nft);

        // Store AssetNFT address
        s.assetNFTContract = assetNFT;

        emit AssetNFTDeployed(assetNFT, name_, symbol_);
        
        return assetNFT;
    }

    /**
     * @dev Mint an asset NFT (called by factory)
     * @param assetNFT The address of the AssetNFT contract
     * @param to The user address to mint the NFT to
     * @param metadata The metadata of the asset
     * @return tokenId The ID of the minted token
     */
    function mintAssetNFT(
        address assetNFT,
        address to,
        TokenStorage.AssetMetadata calldata metadata
    ) external onlyOwner returns (uint256 tokenId) {
        require(_isValidAssetNFT(assetNFT), "LuxShareFactory: invalid asset NFT");
        require(to != address(0), "LuxShareFactory: mint to zero address");

        return ILuxAssetNFT(assetNFT).mintAsset(to, metadata);
    }

    /**
     * @dev Freeze an asset NFT
     * @param assetNFT The address of the AssetNFT contract
     * @param tokenId The ID of the asset to freeze
     */
    function freezeAssetNFT(address assetNFT, uint256 tokenId) external onlyOwner {
        require(_isValidAssetNFT(assetNFT), "LuxShareFactory: invalid asset NFT");
        ILuxAssetNFT(assetNFT).freeze(tokenId);
    }

    /**
     * @dev Unfreeze an asset NFT
     * @param assetNFT The address of the AssetNFT contract
     * @param tokenId The ID of the asset to unfreeze
     */
    function unfreezeAssetNFT(address assetNFT, uint256 tokenId) external onlyOwner {
        require(_isValidAssetNFT(assetNFT), "LuxShareFactory: invalid asset NFT");
        ILuxAssetNFT(assetNFT).unfreeze(tokenId);
    }

    /**
     * @dev Verify an asset NFT
     * @param assetNFT The address of the AssetNFT contract
     * @param tokenId The ID of the asset to verify
     */
    function verifyAssetNFT(address assetNFT, uint256 tokenId) external onlyOwner {
        require(_isValidAssetNFT(assetNFT), "LuxShareFactory: invalid asset NFT");
        ILuxAssetNFT(assetNFT).verifyAsset(tokenId);
    }

    // ==================== Share Token Creation ====================

    /**
     * @dev Create a new share token for an asset
     * @param assetNFT The address of the AssetNFT contract
     * @param assetId The ID of the asset
     * @param config The configuration for the share token
     * @return shareToken The address of the created share token
     */
    function createShareToken(
        address assetNFT,
        uint256 assetId,
        TokenStorage.ShareTokenConfig calldata config
    ) external onlyOwner returns (address shareToken) {
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        
        // Validate inputs
        require(_isValidAssetNFT(assetNFT), "LuxShareFactory: invalid asset NFT");
        require(config.issuer != address(0), "LuxShareFactory: invalid issuer");
        require(config.initialSupply > 0, "LuxShareFactory: initial supply must be greater than zero");
        require(bytes(config.name).length > 0, "LuxShareFactory: name cannot be empty");
        require(bytes(config.symbol).length > 0, "LuxShareFactory: symbol cannot be empty");
        require(s.identityRegistry.isVerified(config.issuer), "LuxShareFactory: issuer not verified");
        
        // Check asset exists and not already tokenized
        ILuxAssetNFT nftContract = ILuxAssetNFT(assetNFT);
        require(nftContract.ownerOf(assetId) != address(0), "LuxShareFactory: asset does not exist");
        require(nftContract.isVerified(assetId), "LuxShareFactory: asset not verified");
        require(s.assetIdToShareToken[assetId] == address(0), "LuxShareFactory: asset already tokenized");

        // Determine which compliance to use: custom or default
        address complianceToUse = config.compliance != address(0) ? config.compliance : address(s.defaultCompliance);
        require(complianceToUse != address(0), "LuxShareFactory: no compliance specified");

        // Deploy new LuxShareToken with factory as initial owner
        LuxShareToken token = new LuxShareToken(address(this));
        shareToken = address(token);
        
        // Initialize the token with specified compliance
        token.initialize(
            config.name,
            config.symbol,
            config.decimals,
            address(s.identityRegistry),
            complianceToUse
        );
        
        // Set underlying asset, share class, and redeemability
        token.setUnderlyingAsset(assetNFT, assetId, config.shareClass, config.redeemable);

        // Bind compliance to token
        IModularCompliance(complianceToUse).bindToken(shareToken);

        // Mint initial supply to issuer's identity
        token.mint(config.issuer, config.initialSupply);
        
        // Store mappings
        s.assetIdToShareToken[assetId] = shareToken;
        s.shareTokenToAssetId[shareToken] = assetId;
        s.isShareToken[shareToken] = true;
        s.tokenCompliance[shareToken] = IModularCompliance(complianceToUse);
        s.allShareTokens.push(shareToken);
        
        // Bind share token to asset NFT
        nftContract.setShareToken(assetId, shareToken);
        
        emit ShareTokenCreated(assetId, shareToken, config.issuer, config.initialSupply);
        
        return shareToken;
    }

    // ==================== Share Token Management ====================
    
    /**
     * @dev Mint share tokens (only factory can mint)
     * @param shareToken The address of the share token
     * @param to The user address to mint to
     * @param amount The amount to mint
     */
    function mintShareTokens(address shareToken, address to, uint256 amount) external onlyOwner {
        require(_isValidShareToken(shareToken), "LuxShareFactory: invalid share token");
        ILuxShareToken(shareToken).mint(to, amount);
    }
    
    /**
     * @dev Burn share tokens (only factory can burn)
     * @param shareToken The address of the share token
     * @param from The user address to burn from
     * @param amount The amount to burn
     */
    function burnShareTokens(address shareToken, address from, uint256 amount) external onlyOwner {
        require(_isValidShareToken(shareToken), "LuxShareFactory: invalid share token");
        ILuxShareToken(shareToken).burn(from, amount);
    }
    
    /**
     * @dev Pause a share token
     * @param shareToken The address of the share token
     */
    function pauseShareToken(address shareToken) external onlyOwner {
        require(_isValidShareToken(shareToken), "LuxShareFactory: invalid share token");
        ILuxShareToken(shareToken).pause();
    }
    
    /**
     * @dev Unpause a share token
     * @param shareToken The address of the share token
     */
    function unpauseShareToken(address shareToken) external onlyOwner {
        require(_isValidShareToken(shareToken), "LuxShareFactory: invalid share token");
        ILuxShareToken(shareToken).unpause();
    }
    
    /**
     * @dev Freeze an address on a share token
     * @param shareToken The address of the share token
     * @param addr The user address to freeze
     */
    function freezeAddress(address shareToken, address addr) external onlyOwner {
        require(_isValidShareToken(shareToken), "LuxShareFactory: invalid share token");
        ILuxShareToken(shareToken).freezeAddress(addr);
    }
    
    /**
     * @dev Unfreeze an address on a share token
     * @param shareToken The address of the share token
     * @param addr The user address to unfreeze
     */
    function unfreezeAddress(address shareToken, address addr) external onlyOwner {
        require(_isValidShareToken(shareToken), "LuxShareFactory: invalid share token");
        ILuxShareToken(shareToken).unfreezeAddress(addr);
    }
    
    /**
     * @dev Freeze partial tokens of an address
     * @param shareToken The address of the share token
     * @param addr The user address to freeze tokens for
     * @param amount The amount of tokens to freeze
     */
    function freezePartialTokens(address shareToken, address addr, uint256 amount) external onlyOwner {
        require(_isValidShareToken(shareToken), "LuxShareFactory: invalid share token");
        ILuxShareToken(shareToken).freezePartialTokens(addr, amount);
    }
    
    /**
     * @dev Unfreeze partial tokens of an address
     * @param shareToken The address of the share token
     * @param addr The user address to unfreeze tokens for
     * @param amount The amount of tokens to unfreeze
     */
    function unfreezePartialTokens(address shareToken, address addr, uint256 amount) external onlyOwner {
        require(_isValidShareToken(shareToken), "LuxShareFactory: invalid share token");
        ILuxShareToken(shareToken).unfreezePartialTokens(addr, amount);
    }
    
    /**
     * @dev Force transfer tokens between addresses
     * @param shareToken The address of the share token
     * @param from The user address to transfer from
     * @param to The user address to transfer to
     * @param amount The amount to transfer
     */
    function forcedTransfer(address shareToken, address from, address to, uint256 amount) external onlyOwner {
        require(_isValidShareToken(shareToken), "LuxShareFactory: invalid share token");
        ILuxShareToken(shareToken).forcedTransfer(from, to, amount);
    }
    
    /**
     * @dev Set compliance module for a share token
     * @param shareToken The address of the share token
     * @param compliance_ The address of the compliance module
     */
    function setTokenCompliance(address shareToken, address compliance_) external onlyOwner {
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        require(s.isShareToken[shareToken], "LuxShareFactory: invalid share token");
        require(compliance_ != address(0), "LuxShareFactory: invalid compliance address");
        
        // Unbind from old compliance if exists
        if (address(s.tokenCompliance[shareToken]) != address(0)) {
            s.tokenCompliance[shareToken].unbindToken(shareToken);
        }
        
        // Update storage mapping
        s.tokenCompliance[shareToken] = IModularCompliance(compliance_);
        
        // Bind to new compliance
        IModularCompliance(compliance_).bindToken(shareToken);
        
        // Update token's compliance reference
        ILuxShareToken(shareToken).setCompliance(compliance_);
    }
    
    /**
     * @dev Get the compliance contract for a specific share token
     * @param shareToken The address of the share token
     * @return The address of the compliance contract
     */
    function getTokenCompliance(address shareToken) external view returns (address) {
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        require(s.isShareToken[shareToken], "LuxShareFactory: invalid share token");
        return address(s.tokenCompliance[shareToken]);
    }
    
    /**
     * @dev Set identity registry for a share token
     * @param shareToken The address of the share token
     * @param identityRegistry_ The address of the identity registry
     */
    function setTokenIdentityRegistry(address shareToken, address identityRegistry_) external onlyOwner {
        require(_isValidShareToken(shareToken), "LuxShareFactory: invalid share token");
        ILuxShareToken(shareToken).setIdentityRegistry(identityRegistry_);
    }

    // ==================== Factory Configuration ====================

    /**
     * @dev Set the default compliance module
     * @param compliance_ The address of the compliance module
     */
    function setDefaultCompliance(address compliance_) external onlyOwner {
        require(compliance_ != address(0), "LuxShareFactory: invalid compliance");
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        s.defaultCompliance = IModularCompliance(compliance_);
        emit DefaultComplianceSet(compliance_);
    }

    /**
     * @dev Set the identity registry
     * @param identityRegistry_ The address of the identity registry
     */
    function setIdentityRegistry(address identityRegistry_) external onlyOwner {
        require(identityRegistry_ != address(0), "LuxShareFactory: invalid identity registry");
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        s.identityRegistry = IIdentityRegistry(identityRegistry_);
        emit IdentityRegistrySet(identityRegistry_);
    }

    // ==================== View Functions ====================

    /**
     * @dev Get share token by asset ID
     * @param assetId The ID of the asset
     * @return The address of the share token
     */
    function getShareTokenByAssetId(uint256 assetId) external view returns (address) {
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        return s.assetIdToShareToken[assetId];
    }

    /**
     * @dev Get asset ID by share token
     * @param shareToken The address of the share token
     * @return The ID of the asset
     */
    function getAssetIdByShareToken(address shareToken) external view returns (uint256) {
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        return s.shareTokenToAssetId[shareToken];
    }

    /**
     * @dev Get all deployed share tokens
     * @return The addresses of all deployed share tokens
     */
    function getAllShareTokens() external view returns (address[] memory) {
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        return s.allShareTokens;
    }

    /**
     * @dev Get the default asset NFT contract address
     * @return The address of the default asset NFT contract
     */
    function assetNFTContract() external view returns (address) {
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        return s.assetNFTContract;
    }

    /**
     * @dev Get the identity registry address
     * @return The address of the identity registry
     */
    function identityRegistry() external view returns (address) {
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        return address(s.identityRegistry);
    }

    /**
     * @dev Get the default compliance address
     * @return The address of the default compliance module
     */
    function defaultCompliance() external view returns (address) {
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        return address(s.defaultCompliance);
    }

    /**
     * @dev Check if a share token is valid
     * @param shareToken The address of the share token
     * @return Whether the share token is valid
     */
    function isShareToken(address shareToken) external view returns (bool) {
        return _isValidShareToken(shareToken);
    }

    // ==================== Internal Helper Functions ====================
    
    /**
     * @dev Check if a share token was created by this factory
     * @param shareToken The address of the share token
     * @return valid Whether the share token is valid
     */
    function _isValidShareToken(address shareToken) internal view returns (bool) {
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        return s.isShareToken[shareToken];
    }

    /**
     * @dev Check if an asset NFT was created by this factory
     * @param assetNFT The address of the asset NFT
     * @return valid Whether the asset NFT is valid
     */
    function _isValidAssetNFT(address assetNFT) internal view returns (bool) {
        TokenStorage.ShareFactoryLayout storage s = TokenStorage.shareFactoryLayout();
        return s.assetNFTContract == assetNFT;
    }
}
