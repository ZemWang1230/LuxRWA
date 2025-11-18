// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/IPrimaryOffering.sol";
import "../interface/IP2PTrading.sol";
import "../interface/IRevenueDistribution.sol";

/**
 * @title MarketStorage
 * @dev Diamond storage for market contracts
 */
library MarketStorage {
    
    // ==================== Primary Offering Storage ====================
    
    struct PrimaryOfferingLayout {
        // Offering ID counter
        uint256 nextOfferingId;
        
        // Offering ID => Offering Config
        mapping(uint256 => IPrimaryOffering.OfferingConfig) offerings;
        
        // Offering ID => shares sold
        mapping(uint256 => uint256) sharesSold;
        
        // Offering ID => investor => subscription
        mapping(uint256 => mapping(address => IPrimaryOffering.Subscription)) subscriptions;
        
        // Offering ID => total payment collected
        mapping(uint256 => uint256) totalPaymentCollected;
        
        // Offering ID => payment withdrawn
        mapping(uint256 => uint256) paymentWithdrawn;
        
        // ShareToken => offering IDs
        mapping(address => uint256[]) shareTokenOfferings;
        
        // Factory address
        address factory;
        
        // Identity Registry address
        address identityRegistry;
        
        // Initialized flag
        bool initialized;
    }
    
    // Storage position
    bytes32 constant PRIMARY_OFFERING_STORAGE_POSITION = keccak256("luxrwa.storage.primary.offering");
    
    /**
     * @dev Returns the primary offering storage layout
     */
    function primaryOfferingLayout() internal pure returns (PrimaryOfferingLayout storage s) {
        bytes32 position = PRIMARY_OFFERING_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
    
    // ==================== P2P Trading Storage ====================
    
    struct P2PTradingLayout {
        // Order ID counter
        uint256 nextOrderId;
        
        // Order ID => Trade Order
        mapping(uint256 => IP2PTrading.TradeOrder) orders;
        
        // ShareToken => order IDs
        mapping(address => uint256[]) shareTokenOrders;
        
        // Maker => order IDs
        mapping(address => uint256[]) makerOrders;
        
        // Factory address
        address factory;
        
        // Identity Registry address
        address identityRegistry;
        
        // Initialized flag
        bool initialized;
    }
    
    // Storage position
    bytes32 constant P2P_TRADING_STORAGE_POSITION = keccak256("luxrwa.storage.p2p.trading");
    
    /**
     * @dev Returns the P2P trading storage layout
     */
    function p2pTradingLayout() internal pure returns (P2PTradingLayout storage s) {
        bytes32 position = P2P_TRADING_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
    
    // ==================== Revenue Distribution Storage ====================
    
    struct RevenueDistributionLayout {
        // Distribution ID counter
        uint256 nextDistributionId;
        
        // Distribution ID => Distribution
        mapping(uint256 => IRevenueDistribution.Distribution) distributions;
        
        // Distribution ID => investor => claimed amount
        mapping(uint256 => mapping(address => uint256)) claimedAmounts;
        
        // ShareToken => distribution IDs
        mapping(address => uint256[]) shareTokenDistributions;
        
        // Issuer => distribution IDs
        mapping(address => uint256[]) issuerDistributions;
        
        // Factory address
        address factory;
        
        // Identity Registry address
        address identityRegistry;
        
        // Initialized flag
        bool initialized;
    }
    
    // Storage position
    bytes32 constant REVENUE_DISTRIBUTION_STORAGE_POSITION = keccak256("luxrwa.storage.revenue.distribution");
    
    /**
     * @dev Returns the revenue distribution storage layout
     */
    function revenueDistributionLayout() internal pure returns (RevenueDistributionLayout storage s) {
        bytes32 position = REVENUE_DISTRIBUTION_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}

