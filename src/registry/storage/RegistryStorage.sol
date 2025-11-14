// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../../identity/interfaces/IIdentity.sol";
import "../../identity/interfaces/IClaimIssuer.sol";

/**
 * @title RegistryStorage
 * @dev Diamond Storage pattern for Registry contracts
 * @notice Provides storage layout for all registry contracts
 */
library RegistryStorage {
    /**
     * @dev ClaimTopicsRegistry Storage
     * @notice This storage layout is used to store the claim topics registry
     */
    struct ClaimTopicsRegistryLayout {
        uint256[] claimTopics;  // Array of claim topics
        mapping(uint256 => bool) claimTopicExists; // Mapping of claim topic exists
    }

    /**
     * @dev TrustedIssuersRegistry Storage
     * @notice This storage layout is used to store the trusted issuers registry
     */
    struct TrustedIssuersRegistryLayout {
        IClaimIssuer[] trustedIssuers;  // Array of trusted issuers
        mapping(address => bool) isTrusted; // Mapping of trusted issuer exists
        mapping(address => uint256) issuerIndex; // Mapping of issuer index
        mapping(address => uint256[]) issuerClaimTopics; // Mapping of issuer claim topics
        mapping(address => mapping(uint256 => bool)) issuerHasTopic; // Mapping of issuer has topic
    }

    /**
     * @dev IdentityRegistryStorage Layout
     * @notice This storage layout is used to store the identity registry storage
     */
    struct IdentityRegistryStorageLayout {
        mapping(address => IIdentity) identities; // Mapping of identity exists
        mapping(address => uint16) investorCountries; // Mapping of investor countries
        mapping(address => bool) identityStored; // Mapping of identity stored
        address[] identityRegistries; // Array of identity registries
        mapping(address => bool) isRegistryBound; // Mapping of is registry bound
    }

    /**
     * @dev IdentityRegistry Layout
     * @notice This storage layout is used to store the identity registry
     */
    struct IdentityRegistryLayout {
        address claimTopicsRegistry; // Address of claim topics registry
        address trustedIssuersRegistry; // Address of trusted issuers registry
        address identityRegistryStorage; // Address of identity registry storage
        mapping(address => bool) agents; // Mapping of agents
    }

    // Storage positions using Diamond Storage pattern
    bytes32 constant CLAIM_TOPICS_REGISTRY_POSITION = 
        keccak256("luxrwa.registry.claimtopics.storage");
    
    bytes32 constant TRUSTED_ISSUERS_REGISTRY_POSITION = 
        keccak256("luxrwa.registry.trustedissuers.storage");
    
    bytes32 constant IDENTITY_REGISTRY_STORAGE_POSITION = 
        keccak256("luxrwa.registry.identitystorage.storage");
    
    bytes32 constant IDENTITY_REGISTRY_POSITION = 
        keccak256("luxrwa.registry.identityregistry.storage");

    /**
     * @dev Get ClaimTopicsRegistry storage layout
     * @notice This function is used to get the claim topics registry storage layout
     */
    function claimTopicsLayout() internal pure returns (ClaimTopicsRegistryLayout storage l) {
        bytes32 position = CLAIM_TOPICS_REGISTRY_POSITION;
        assembly {
            l.slot := position
        }
    }

    /**
     * @dev Get TrustedIssuersRegistry storage layout
     * @notice This function is used to get the trusted issuers registry storage layout
     */
    function trustedIssuersLayout() internal pure returns (TrustedIssuersRegistryLayout storage l) {
        bytes32 position = TRUSTED_ISSUERS_REGISTRY_POSITION;
        assembly {
            l.slot := position
        }
    }

    /**
     * @dev Get IdentityRegistryStorage layout
     * @notice This function is used to get the identity registry storage layout
     */
    function identityRegistryStorageLayout() internal pure returns (IdentityRegistryStorageLayout storage l) {
        bytes32 position = IDENTITY_REGISTRY_STORAGE_POSITION;
        assembly {
            l.slot := position
        }
    }

    /**
     * @dev Get IdentityRegistry layout
     * @notice This function is used to get the identity registry layout
     */
    function identityRegistryLayout() internal pure returns (IdentityRegistryLayout storage l) {
        bytes32 position = IDENTITY_REGISTRY_POSITION;
        assembly {
            l.slot := position
        }
    }
}

