// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../../compliance/interface/IModularCompliance.sol";
import "../../registry/interface/IIdentityRegistry.sol";

/**
 * @title TokenStorage
 * @dev Diamond Storage implementation for LuxRWA Token System
 * @notice Uses Diamond Storage pattern to avoid storage collisions
 * @notice Reference: T-REX ERC-3643 architecture with factory-centric design
 */
library TokenStorage {
    // ==================== Asset NFT Storage ====================
    
    bytes32 constant ASSET_NFT_STORAGE_POSITION = keccak256("luxrwa.storage.asset.nft");

    /**
     * @dev Metadata structure for luxury assets
     */
    struct AssetMetadata {
        uint256 assetType;           // Type of luxury asset (watch=1, jewelry=2, art=3, etc.)
        string brand;                // Brand name
        string model;                // Model/Series
        bytes32 serialHash;          // Hash of serial number (for privacy)
        string custodyInfo;          // Custody/warehouse information
        bytes32 appraisalHash;       // Hash of appraisal certificate
        bytes32 insuranceHash;       // Hash of insurance certificate
        bytes32 nfcTagHash;          // Hash of NFC tag data (for physical verification)
        address appraisalAuthority;  // Address of appraisal authority
        string metadataURI;          // IPFS URI for detailed metadata
        uint256 timestamp;           // Timestamp of asset creation
        bool verified;               // Whether the asset has been verified
    }

    /**
     * @dev Diamond Storage layout for Asset NFT
     */
    struct AssetNFTLayout {
        // Factory address (central controller)
        address factory;

        // Identity registry
        IIdentityRegistry identityRegistry;
        
        // Token name and symbol
        string name;
        string symbol;
        
        // Token counter
        uint256 currentTokenId;
        
        // ERC721 standard mappings
        mapping(uint256 => address) owners;
        mapping(address => uint256) balances;
        
        // Asset metadata
        mapping(uint256 => AssetMetadata) assetMetadata;
        
        // Asset to ShareToken binding
        mapping(uint256 => address) assetToShareToken;
        
        // Frozen tokens (for redemption process or compliance)
        mapping(uint256 => bool) frozenTokens;
    }

    function assetNFTLayout() internal pure returns (AssetNFTLayout storage s) {
        bytes32 position = ASSET_NFT_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    // ==================== Share Token Storage ====================
    
    bytes32 constant SHARE_TOKEN_STORAGE_POSITION = keccak256("luxrwa.storage.share.token");

    /**
     * @dev Diamond Storage layout for Share Token
     */
    struct ShareTokenLayout {
        // Factory address (central controller)
        address factory;
        
        // Initialization flag
        bool initialized;
        
        // ERC20 basics
        string name;
        string symbol;
        uint8 decimals;
        uint256 totalSupply;
        
        mapping(address => uint256) balances;
        mapping(address => mapping(address => uint256)) allowances;
        
        // Compliance and Identity (T-REX standard)
        IModularCompliance compliance;
        IIdentityRegistry identityRegistry;
        
        // Asset binding
        address assetNFTContract;
        uint256 underlyingAssetId;
        
        // Security token attributes
        string shareClass;          // Class of shares (A, B, C, etc.)
        bool redeemable;            // Whether shares can be redeemed
        bool paused;                // Emergency pause flag
        
        // Frozen wallets (compliance enforcement)
        mapping(address => bool) frozen;              // Fully frozen addresses
        mapping(address => uint256) frozenTokens;     // Partially frozen token amounts
    }

    function shareTokenLayout() internal pure returns (ShareTokenLayout storage s) {
        bytes32 position = SHARE_TOKEN_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    // ==================== Share Factory Storage ====================
    
    bytes32 constant SHARE_FACTORY_STORAGE_POSITION = keccak256("luxrwa.storage.factory");

    /**
     * @dev Configuration for creating a new share token
     */
    struct ShareTokenConfig {
        string name;                // Token name
        string symbol;              // Token symbol
        uint8 decimals;             // Token decimals
        uint256 initialSupply;      // Initial supply to mint
        address issuer;             // Address to receive initial supply
        string shareClass;          // Class of shares
        bool redeemable;            // Whether shares can be redeemed
        address compliance;         // Compliance module for this token (if address(0), use default)
    }

    /**
     * @dev Diamond Storage layout for Share Factory
     */
    struct ShareFactoryLayout {
        // Initialization flag
        bool initialized;
        
        // Registry references
        IIdentityRegistry identityRegistry;
        IModularCompliance defaultCompliance;
        
        // Asset NFT contract
        address assetNFTContract;
        
        // Token mappings
        mapping(uint256 => address) assetIdToShareToken;    // Asset ID -> Share Token
        mapping(address => uint256) shareTokenToAssetId;    // Share Token -> Asset ID
        mapping(address => bool) isShareToken;              // Quick lookup for validation
        
        // All deployed tokens
        address[] allShareTokens;
        
        // Multi-compliance support (different compliance for different token types)
        mapping(address => IModularCompliance) tokenCompliance;  // Token -> Custom Compliance

        // Agent roles
        mapping(address => bool) agentRoles;
    }

    function shareFactoryLayout() internal pure returns (ShareFactoryLayout storage s) {
        bytes32 position = SHARE_FACTORY_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}

