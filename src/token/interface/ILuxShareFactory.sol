// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/**
 * @title ILuxShareFactory
 * @dev Interface for LuxShareFactory
 * @notice Factory for deploying and managing LuxRWA token ecosystem
 * @notice Factory-centric architecture inspired by T-REX ERC-3643
 */
interface ILuxShareFactory {
    /// Events
    
    event ShareTokenCreated(
        uint256 indexed assetId,
        address indexed shareToken,
        address indexed issuer,
        uint256 initialSupply
    );
    
    event DefaultComplianceSet(address indexed compliance);
    
    /// Functions
    
    /**
     * @dev Set the default compliance module
     * @param compliance Address of the compliance module
     */
    function setDefaultCompliance(address compliance) external;
    
    /**
     * @dev Get share token by asset ID
     * @param assetId The asset token ID
     * @return shareToken The share token address
     */
    function getShareTokenByAssetId(uint256 assetId) external view returns (address shareToken);
    
    /**
     * @dev Get asset ID by share token
     * @param shareToken The share token address
     * @return assetId The asset token ID
     */
    function getAssetIdByShareToken(address shareToken) external view returns (uint256 assetId);
    
    /**
     * @dev Get all deployed share tokens
     * @return tokens Array of share token addresses
     */
    function getAllShareTokens() external view returns (address[] memory tokens);
    
    /**
     * @dev Get the default asset NFT contract address
     * @return assetNFT The asset NFT contract address
     */
    function assetNFTContract() external view returns (address assetNFT);
    
    /**
     * @dev Get the identity registry address
     * @return identityRegistry The identity registry address
     */
    function identityRegistry() external view returns (address identityRegistry);
    
    /**
     * @dev Get the default compliance address
     * @return compliance The default compliance address
     */
    function defaultCompliance() external view returns (address compliance);
    
    /**
     * @dev Get the compliance contract for a specific share token
     * @param shareToken The address of the share token
     * @return compliance The address of the compliance contract
     */
    function getTokenCompliance(address shareToken) external view returns (address compliance);
    
    /**
     * @dev Set custom compliance for a share token
     * @param shareToken The address of the share token
     * @param compliance The address of the new compliance contract
     */
    function setTokenCompliance(address shareToken, address compliance) external;
}

