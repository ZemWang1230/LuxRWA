// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IdentityStorage
 * @dev Diamond Storage pattern for Identity contracts
 * @notice This library provides storage layout for ONCHAINID implementation
 */
library IdentityStorage {
    /**
     * @dev Key structure based on ERC734
     */
    struct Key {
        uint256[] purposes;  // Array of purposes for this key
        uint256 keyType;     // Key type (1 = ECDSA, 2 = RSA, etc.)
        bytes32 key;         // Key data (address hash or public key)
    }

    /**
     * @dev Claim structure based on ERC735
     */
    struct Claim {
        uint256 topic;       // Claim topic (1 = KYC, 2 = AML, etc.)
        uint256 scheme;      // Signature scheme
        address issuer;      // Claim issuer address
        bytes signature;     // Signature data
        bytes data;          // Claim data
        string uri;          // URI for additional claim data
        bool revocable;      // Whether the claim can be revoked
        bool revoked;        // Whether the claim has been revoked
    }

    /**
     * @dev Execution structure for multi-sig operations
     */
    struct Execution {
        address to;          // Target address
        uint256 value;       // ETH value to send
        bytes data;          // Call data
        bool executed;       // Whether executed
        uint256 approvalCount; // Number of approvals
        mapping(address => bool) approvals; // Approver => approved
    }

    /**
     * @dev Main storage structure
     */
    struct Layout {
        // Owner of the identity
        address owner;
        
        // Key management (ERC734)
        mapping(bytes32 => Key) keys;                    // keyHash => Key; keyHash = keccak256(abi.encodePacked(address))
        mapping(uint256 => bytes32[]) keysByPurpose;     // purpose => keyHashes[]
        bytes32[] allKeys;                               // All key hashes
        
        // Claim management (ERC735)
        mapping(bytes32 => Claim) claims;                // claimId => Claim; claimId = keccak256(abi.encodePacked(_issuer, _topic))
        mapping(uint256 => bytes32[]) claimsByTopic;     // topic => claimIds[]
        bytes32[] allClaims;                             // All claim IDs
        
        // Execution management
        mapping(uint256 => Execution) executions;        // executionId => Execution
        uint256 executionNonce;                          // Current execution nonce
        
        // Identity type
        bool isInvestor;     // true if investor identity
        bool isIssuer;       // true if issuer identity
        
        // Additional metadata
        string identityName; // Human-readable identity name
        uint256 createdAt;   // Creation timestamp
    }

    // Storage position calculation using Diamond Storage pattern
    bytes32 constant IDENTITY_STORAGE_POSITION = keccak256("luxrwa.identity.storage");
    
    /**
     * @dev Get storage layout
     * @return l Storage layout
     */
    function layout() internal pure returns (Layout storage l) {
        bytes32 position = IDENTITY_STORAGE_POSITION;
        assembly {
            l.slot := position
        }
    }

    /**
     * @dev Key purposes constants (ERC734)
     */
    uint256 constant MANAGEMENT_PURPOSE = 1;  // Can manage keys
    uint256 constant ACTION_PURPOSE = 2;      // Can approve executions
    uint256 constant CLAIM_PURPOSE = 3;       // Can add/remove claims

    /**
     * @dev Key types constants (ERC734)
     */
    uint256 constant ECDSA_KEY = 1;           // ECDSA key (Ethereum address)
    uint256 constant RSA_KEY = 2;             // RSA key

    /**
     * @dev Claim topics constants (ERC735)
     */
    uint256 constant KYC_CLAIM = 1;           // KYC verification claim
    uint256 constant AML_CLAIM = 2;           // AML verification claim
    uint256 constant ACCREDITATION_CLAIM = 3; // Accreditation claim
    uint256 constant COUNTRY_CLAIM = 4;       // Country/region claim

    /**
     * @dev Signature schemes constants (ERC735)
     */
    uint256 constant ECDSA_SCHEME = 1;        // ECDSA signature
    uint256 constant RSA_SCHEME = 2;          // RSA signature
}

