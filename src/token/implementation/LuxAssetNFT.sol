// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/ILuxAssetNFT.sol";
import "../storage/TokenStorage.sol";

/**
 * @title LuxAssetNFT
 * @dev Implementation of luxury asset NFT using Diamond Storage
 * @notice Unified ERC721 contract for all luxury assets on the platform
 * @notice Factory-centric design: critical functions can only be called by factory
 * @notice Only the factory can mint, bind, freeze, unfreeze, verify, update metadata
 * @notice Only can transfer, no approval needed, no approval mapping
 */
contract LuxAssetNFT is ILuxAssetNFT {
    using TokenStorage for TokenStorage.AssetNFTLayout;

    // ERC721 events
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    
    modifier onlyFactory() {
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        require(msg.sender == s.factory, "LuxAssetNFT: caller is not the factory");
        _;
    }

    /**
     * @dev Constructor sets up the NFT with factory address
     * @param name_ The name of the NFT collection
     * @param symbol_ The symbol of the NFT collection
     * @param factory_ The address of the factory contract
     * @param identityRegistry_ The address of the identity registry contract
     */
    constructor(string memory name_, string memory symbol_, address factory_, address identityRegistry_) {
        require(factory_ != address(0), "LuxAssetNFT: invalid factory address");
        require(identityRegistry_ != address(0), "LuxAssetNFT: invalid identity registry address");
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        s.name = name_;
        s.symbol = symbol_;
        s.currentTokenId = 0;
        s.factory = factory_;
        s.identityRegistry = IIdentityRegistry(identityRegistry_);
    }

    // ==================== Factory-Only Functions ====================

    /**
     * @dev Mint a new asset NFT (only factory can mint)
     * @param to The user address to mint the NFT to
     * @param metadata The metadata of the asset
     * @return tokenId The ID of the minted token
     */
    function mintAsset(
        address to,
        TokenStorage.AssetMetadata calldata metadata
    ) external override onlyFactory returns (uint256 tokenId) {
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        address toIdentity = address(s.identityRegistry.identity(to));
        require(toIdentity != address(0), "LuxAssetNFT: mint to not found");

        tokenId = s.currentTokenId;
        s.currentTokenId++;

        s.owners[tokenId] = toIdentity;
        s.balances[toIdentity]++;
        
        // Store metadata with timestamp
        TokenStorage.AssetMetadata memory fullMetadata = metadata;
        fullMetadata.timestamp = block.timestamp;
        fullMetadata.verified = false; // Initially not verified
        s.assetMetadata[tokenId] = fullMetadata;

        emit Transfer(address(0), toIdentity, tokenId);
        emit AssetMinted(tokenId, toIdentity, metadata.assetType, metadata.brand, metadata.model);

        return tokenId;
    }

    /**
     * @dev Bind a ShareToken to an asset (only factory can bind)
     * @param tokenId The ID of the asset
     * @param shareToken The address of the ShareToken
     */
    function setShareToken(uint256 tokenId, address shareToken) external override onlyFactory {
        require(_exists(tokenId), "LuxAssetNFT: token does not exist");
        require(shareToken != address(0), "LuxAssetNFT: invalid share token address");
        
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        require(s.assetToShareToken[tokenId] == address(0), "LuxAssetNFT: share token already bound");
        
        s.assetToShareToken[tokenId] = shareToken;
        emit ShareTokenBound(tokenId, shareToken);
    }

    /**
     * @dev Freeze an asset (only factory can freeze)
     * @param tokenId The ID of the asset
     */
    function freeze(uint256 tokenId) external override onlyFactory {
        require(_exists(tokenId), "LuxAssetNFT: token does not exist");
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        require(!s.frozenTokens[tokenId], "LuxAssetNFT: token already frozen");
        
        s.frozenTokens[tokenId] = true;
        emit AssetFrozen(tokenId);
    }

    /**
     * @dev Unfreeze an asset (only factory can unfreeze)
     * @param tokenId The ID of the asset
     */
    function unfreeze(uint256 tokenId) external override onlyFactory {
        require(_exists(tokenId), "LuxAssetNFT: token does not exist");
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        require(s.frozenTokens[tokenId], "LuxAssetNFT: token not frozen");
        
        s.frozenTokens[tokenId] = false;
        emit AssetUnfrozen(tokenId);
    }

    /**
     * @dev Verify an asset (only factory can verify)
     * @param tokenId The ID of the asset
     */
    function verifyAsset(uint256 tokenId) external override onlyFactory {
        require(_exists(tokenId), "LuxAssetNFT: token does not exist");
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        require(!s.assetMetadata[tokenId].verified, "LuxAssetNFT: already verified");
        
        s.assetMetadata[tokenId].verified = true;
    }

    /**
     * @dev Update asset metadata (only factory can update)
     * @param tokenId The ID of the asset
     * @param metadata The new metadata
     */
    function updateAssetMetadata(
        uint256 tokenId,
        TokenStorage.AssetMetadata calldata metadata
    ) external onlyFactory {
        require(_exists(tokenId), "LuxAssetNFT: token does not exist");
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        
        // Preserve existing timestamp and verified status
        TokenStorage.AssetMetadata memory updatedMetadata = metadata;
        updatedMetadata.timestamp = s.assetMetadata[tokenId].timestamp;
        updatedMetadata.verified = s.assetMetadata[tokenId].verified;
        
        s.assetMetadata[tokenId] = updatedMetadata;
    }

    // ==================== View Functions ====================

    /**
     * @dev Get asset metadata
     * @param tokenId The ID of the asset
     * @return metadata The metadata of the asset
     */
    function getAssetMetadata(uint256 tokenId) 
        external 
        view 
        override 
        returns (TokenStorage.AssetMetadata memory metadata) 
    {
        require(_exists(tokenId), "LuxAssetNFT: token does not exist");
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        return s.assetMetadata[tokenId];
    }

    /**
     * @dev Get the ShareToken bound to an asset
     * @param tokenId The ID of the asset
     * @return shareToken The address of the ShareToken
     */
    function getShareToken(uint256 tokenId) external view override returns (address shareToken) {
        require(_exists(tokenId), "LuxAssetNFT: token does not exist");
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        return s.assetToShareToken[tokenId];
    }

    /**
     * @dev Check if an asset is frozen
     * @param tokenId The ID of the asset
     * @return frozen Whether the asset is frozen
     */
    function isFrozen(uint256 tokenId) external view override returns (bool frozen) {
        require(_exists(tokenId), "LuxAssetNFT: token does not exist");
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        return s.frozenTokens[tokenId];
    }

    /**
     * @dev Check if an asset is verified
     * @param tokenId The ID of the asset
     * @return verified Whether the asset is verified
     */
    function isVerified(uint256 tokenId) external view override returns (bool verified) {
        require(_exists(tokenId), "LuxAssetNFT: token does not exist");
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        return s.assetMetadata[tokenId].verified;
    }
    
    /**
     * @dev Get factory address
     * @return factory The address of the factory
     */
    function factory() external view returns (address) {
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        return s.factory;
    }

    /**
     * @dev Get the identity registry address
     * @return identityRegistry The address of the identity registry
     */
    function identityRegistry() external view returns (address) {
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        return address(s.identityRegistry);
    }

    // ==================== ERC721 Standard Implementation ====================

    /**
     * @dev Get the name of the collection
     * @return name The name of the collection
     */
    function name() external view returns (string memory) {
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        return s.name;
    }

    /**
     * @dev Get the symbol of the collection
     * @return symbol The symbol of the collection
     */
    function symbol() external view returns (string memory) {
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        return s.symbol;
    }

    /**
     * @dev Get the balance of an address
     * @param owner_ The user address to get the balance of
     * @return balance The balance of the address
     */
    function balanceOf(address owner_) external view override returns (uint256) {
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        address ownerIdentity = address(s.identityRegistry.identity(owner_));
        require(ownerIdentity != address(0), "LuxAssetNFT: owner not found");
        return s.balances[ownerIdentity];
    }

    /**
     * @dev Get the owner of a token
     * @param tokenId The ID of the token
     * @return owner The owner of the token
     */
    function ownerOf(uint256 tokenId) public view override returns (address) {
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        address ownerIdentity = s.owners[tokenId];
        require(ownerIdentity != address(0), "LuxAssetNFT: owner not found");
        return ownerIdentity;
    }

    /**
     * @dev Transfer a token from one address to another
     * @param to The user address to transfer to
     * @param tokenId The ID of the token
     */
    function transfer(address to, uint256 tokenId) external override {
        _transfer(msg.sender, to, tokenId);
        emit Transfer(msg.sender, to, tokenId);
    }

    // ==================== Internal Functions ====================

    /**
     * @dev Check if a token exists
     * @param tokenId The ID of the token
     * @return exists Whether the token exists
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @dev Get the owner of a token
     * @param tokenId The ID of the token
     * @return owner The owner of the token
     */
    function _ownerOf(uint256 tokenId) internal view returns (address) {
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        return s.owners[tokenId];
    }

    /**
     * @dev Transfer a token from one address to another
     * @param from The user address to transfer from
     * @param to The user address to transfer to
     * @param tokenId The ID of the token
     */
    function _transfer(address from, address to, uint256 tokenId) internal {
        TokenStorage.AssetNFTLayout storage s = TokenStorage.assetNFTLayout();
        address fromIdentity = address(s.identityRegistry.identity(from));
        address toIdentity = address(s.identityRegistry.identity(to));

        require(fromIdentity != address(0), "LuxAssetNFT: from not found");
        require(toIdentity != address(0), "LuxAssetNFT: to not found");
        
        require(ownerOf(tokenId) == fromIdentity, "LuxAssetNFT: transfer from incorrect owner");
        
        require(!s.frozenTokens[tokenId], "LuxAssetNFT: token is frozen");

        // Update balances and ownership
        s.balances[fromIdentity]--;
        s.balances[toIdentity]++;
        s.owners[tokenId] = toIdentity;

        emit Transfer(fromIdentity, toIdentity, tokenId);
    }
}
