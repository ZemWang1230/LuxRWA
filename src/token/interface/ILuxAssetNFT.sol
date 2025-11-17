// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../storage/TokenStorage.sol";

/**
 * @title ILuxAssetNFT
 * @dev Interface for luxury asset NFT
 * @notice ERC721-compatible interface for representing real-world luxury assets
 */
interface ILuxAssetNFT {
    /// Events
    
    event AssetMinted(
        uint256 indexed tokenId,
        address indexed to,
        uint256 assetType,
        string brand,
        string model
    );
    
    event AssetFrozen(uint256 indexed tokenId);
    event AssetUnfrozen(uint256 indexed tokenId);
    
    event ShareTokenBound(uint256 indexed tokenId, address indexed shareToken);
    
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    
    /// Functions
    
    /**
     * @dev Mint a new asset NFT
     * @param to Address to mint the NFT to
     * @param metadata Asset metadata
     * @return tokenId The ID of the minted token
     */
    function mintAsset(
        address to,
        TokenStorage.AssetMetadata calldata metadata
    ) external returns (uint256 tokenId);
    
    /**
     * @dev Get asset metadata
     * @param tokenId The token ID
     * @return metadata The asset metadata
     */
    function getAssetMetadata(uint256 tokenId) 
        external 
        view 
        returns (TokenStorage.AssetMetadata memory metadata);
    
    /**
     * @dev Bind a ShareToken to an asset
     * @param tokenId The asset token ID
     * @param shareToken The ShareToken address
     */
    function setShareToken(uint256 tokenId, address shareToken) external;
    
    /**
     * @dev Get the ShareToken bound to an asset
     * @param tokenId The asset token ID
     * @return shareToken The ShareToken address
     */
    function getShareToken(uint256 tokenId) external view returns (address shareToken);
    
    /**
     * @dev Freeze an asset (prevent transfers)
     * @param tokenId The token ID to freeze
     */
    function freeze(uint256 tokenId) external;
    
    /**
     * @dev Unfreeze an asset
     * @param tokenId The token ID to unfreeze
     */
    function unfreeze(uint256 tokenId) external;

    /**
     * @dev Verify an asset
     * @param tokenId The token ID to verify
     */
    function verifyAsset(uint256 tokenId) external;
    
    /**
     * @dev Check if an asset is frozen
     * @param tokenId The token ID
     * @return frozen Whether the asset is frozen
     */
    function isFrozen(uint256 tokenId) external view returns (bool frozen);

    /**
     * @dev Check if an asset is verified
     * @param tokenId The token ID
     * @return verified Whether the asset is verified
     */
    function isVerified(uint256 tokenId) external view returns (bool verified);
    
    // ERC721 Standard Functions
    function transfer(address to, uint256 tokenId) external;
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

