// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/IRedemption.sol";
import "../../registry/interface/IIdentityRegistry.sol";

/**
 * @title RedemptionStorage
 * @dev Diamond Storage implementation for Redemption contract
 * @notice Uses Diamond Storage pattern to avoid storage collisions
 */
library RedemptionStorage {
    bytes32 constant REDEMPTION_STORAGE_POSITION = keccak256("luxrwa.storage.redemption");
    
    /**
     * @dev Asset mapping structure
     * Maps ShareToken to its underlying Asset NFT
     */
    struct AssetMapping {
        address assetNFTContract;       // Asset NFT contract address
        uint256 assetTokenId;           // Asset NFT token ID
        address issuer;                 // Issuer address who holds the NFT
        bool registered;                // Whether this mapping is active
    }
    
    /**
     * @dev Diamond Storage layout for Redemption
     */
    struct Layout {
        // Factory address (for privileged operations)
        address factory;
        
        // Identity registry for compliance checks
        IIdentityRegistry identityRegistry;
        
        // Redemption counter
        uint256 redemptionCounter;
        
        // Asset mappings: ShareToken => AssetMapping
        mapping(address => AssetMapping) assetMappings;
        
        // Redemption records: redemptionId => RedemptionRecord
        mapping(uint256 => IRedemption.RedemptionRecord) redemptions;
        
        // User redemptions: redeemer address => redemption IDs
        mapping(address => uint256[]) userRedemptions;
        
        // ShareToken redemptions: shareToken => redemption IDs
        mapping(address => uint256[]) shareTokenRedemptions;
        
        // Active redemption check: shareToken => has active redemption
        mapping(address => bool) hasActiveRedemption;
        
        // Active redemption ID: shareToken => redemptionId
        mapping(address => uint256) activeRedemptionId;
    }
    
    function layout() internal pure returns (Layout storage s) {
        bytes32 position = REDEMPTION_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}

