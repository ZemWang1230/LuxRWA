// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/IP2PTrading.sol";
import "../storage/MarketStorage.sol";
import "../../token/interface/ILuxShareToken.sol";
import "../../token/interface/ILuxShareFactory.sol";
import "../../registry/interface/IIdentityRegistry.sol";
import "../../compliance/interface/IModularCompliance.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title P2PTrading
 * @dev Peer-to-peer trading contract for ShareTokens
 * @notice Facilitates direct bilateral trades between qualified investors
 * @notice All trades are subject to KYC and compliance checks
 * @notice This is the secondary market implementation
 * @notice Uses token freezing mechanism instead of escrow to lock seller's shares
 */
contract P2PTrading is IP2PTrading {
    using MarketStorage for MarketStorage.P2PTradingLayout;
    
    // ==================== Modifiers ====================
    
    modifier onlyValidOrder(uint256 orderId) {
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        require(orderId < s.nextOrderId, "P2PTrading: invalid order ID");
        _;
    }
    
    modifier onlyMaker(uint256 orderId) {
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        require(
            msg.sender == s.orders[orderId].maker,
            "P2PTrading: caller is not the maker"
        );
        _;
    }
    
    // ==================== Constructor ====================
    
    constructor(address factory_, address identityRegistry_) {
        require(factory_ != address(0), "P2PTrading: invalid factory");
        require(identityRegistry_ != address(0), "P2PTrading: invalid identity registry");
        
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        s.factory = factory_;
        s.identityRegistry = identityRegistry_;
        s.nextOrderId = 0;
        s.initialized = true;
    }
    
    // ==================== External Functions ====================
    
    /**
     * @dev Create a sell order
     * @param shareToken The address of the share token
     * @param shareAmount The amount of shares to sell
     * @param paymentToken The payment token address
     * @param pricePerShare The price per share
     * @param expiryTime The expiry timestamp
     * @return orderId The ID of the created order
     */
    function createSellOrder(
        address shareToken,
        uint256 shareAmount,
        address paymentToken,
        uint256 pricePerShare,
        uint256 expiryTime
    ) external override returns (uint256 orderId) {
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        
        // Validate inputs
        require(shareToken != address(0), "P2PTrading: invalid share token");
        require(shareAmount > 0, "P2PTrading: invalid share amount");
        require(paymentToken != address(0), "P2PTrading: invalid payment token");
        require(pricePerShare > 0, "P2PTrading: invalid price");
        require(expiryTime > block.timestamp, "P2PTrading: invalid expiry time");
        
        // Check maker is verified
        IIdentityRegistry idRegistry = IIdentityRegistry(s.identityRegistry);
        require(idRegistry.contains(msg.sender), "P2PTrading: maker not registered");
        require(idRegistry.isVerified(msg.sender), "P2PTrading: maker not verified");
        
        // Check maker has sufficient balance
        ILuxShareToken token = ILuxShareToken(shareToken);
        uint256 makerBalance = token.balanceOf(msg.sender);
        uint256 frozenTokens = token.getFrozenTokens(msg.sender);
        uint256 availableBalance = makerBalance - frozenTokens;
        require(availableBalance >= shareAmount, "P2PTrading: insufficient available balance");
        
        // Freeze shares on maker's address via factory
        ILuxShareFactory factoryContract = ILuxShareFactory(s.factory);
        factoryContract.freezePartialTokens(shareToken, msg.sender, shareAmount);
        
        // Create order
        orderId = s.nextOrderId++;
        
        TradeOrder storage order = s.orders[orderId];
        order.maker = msg.sender;
        order.shareToken = shareToken;
        order.shareAmount = shareAmount;
        order.paymentToken = paymentToken;
        order.pricePerShare = pricePerShare;
        order.expiryTime = expiryTime;
        order.status = OrderStatus.Active;
        order.filledAmount = 0;
        
        // Index order
        s.shareTokenOrders[shareToken].push(orderId);
        s.makerOrders[msg.sender].push(orderId);
        
        emit OrderCreated(orderId, msg.sender, shareToken, shareAmount, pricePerShare);
        
        return orderId;
    }
    
    /**
     * @dev Fill a sell order (buy shares)
     * @param orderId The ID of the order
     * @param shareAmount The amount of shares to buy
     */
    function fillOrder(uint256 orderId, uint256 shareAmount) 
        external 
        override 
        onlyValidOrder(orderId) 
    {
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        TradeOrder storage order = s.orders[orderId];
        
        // Validate order status
        require(order.status == OrderStatus.Active, "P2PTrading: order not active");
        require(block.timestamp <= order.expiryTime, "P2PTrading: order expired");
        
        // Validate fill amount
        require(shareAmount > 0, "P2PTrading: invalid fill amount");
        uint256 remainingAmount = order.shareAmount - order.filledAmount;
        require(shareAmount <= remainingAmount, "P2PTrading: exceeds remaining amount");
        
        // Check taker is verified
        IIdentityRegistry idRegistry = IIdentityRegistry(s.identityRegistry);
        require(idRegistry.contains(msg.sender), "P2PTrading: taker not registered");
        require(idRegistry.isVerified(msg.sender), "P2PTrading: taker not verified");
        
        // Check compliance for this transfer
        ILuxShareToken shareToken = ILuxShareToken(order.shareToken);
        IModularCompliance compliance = shareToken.compliance();
        require(
            compliance.canTransfer(order.maker, msg.sender, shareAmount),
            "P2PTrading: transfer not compliant"
        );
        
        // Calculate payment amount
        uint256 paymentAmount = (shareAmount * order.pricePerShare) / 10**ILuxShareToken(order.shareToken).decimals();
        
        // Transfer payment from taker to maker
        IERC20 paymentToken = IERC20(order.paymentToken);
        require(
            paymentToken.transferFrom(msg.sender, order.maker, paymentAmount),
            "P2PTrading: payment transfer failed"
        );
        
        // Unfreeze and transfer shares from maker to taker via factory
        ILuxShareFactory factoryContract = ILuxShareFactory(s.factory);
        factoryContract.unfreezePartialTokens(order.shareToken, order.maker, shareAmount);
        
        // Transfer shares from maker to taker using factory's forcedTransfer
        // This bypasses the need for maker to approve this contract
        // Shares go directly from maker to taker without touching this contract
        factoryContract.forcedTransfer(order.shareToken, order.maker, msg.sender, shareAmount);
        
        // Update order state
        order.filledAmount += shareAmount;
        
        // Check if order is fully filled
        if (order.filledAmount == order.shareAmount) {
            order.status = OrderStatus.Filled;
            emit OrderFilled(orderId, msg.sender, shareAmount, paymentAmount);
        } else {
            emit OrderPartiallyFilled(
                orderId, 
                msg.sender, 
                shareAmount, 
                paymentAmount,
                order.shareAmount - order.filledAmount
            );
        }
    }
    
    /**
     * @dev Cancel an order
     * @param orderId The ID of the order
     */
    function cancelOrder(uint256 orderId) 
        external 
        override 
        onlyValidOrder(orderId)
        onlyMaker(orderId) 
    {
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        TradeOrder storage order = s.orders[orderId];
        
        require(order.status == OrderStatus.Active, "P2PTrading: order not active");
        
        // Calculate remaining shares to unfreeze
        uint256 remainingShares = order.shareAmount - order.filledAmount;
        
        // Update order status
        order.status = OrderStatus.Cancelled;
        
        // Unfreeze remaining shares on maker's address
        if (remainingShares > 0) {
            ILuxShareFactory factoryContract = ILuxShareFactory(s.factory);
            factoryContract.unfreezePartialTokens(order.shareToken, order.maker, remainingShares);
        }
        
        emit OrderCancelled(orderId);
    }
    
    // ==================== View Functions ====================
    
    /**
     * @dev Get order details
     * @param orderId The ID of the order
     * @return order The order details
     */
    function getOrder(uint256 orderId) 
        external 
        view 
        override 
        onlyValidOrder(orderId)
        returns (TradeOrder memory order) 
    {
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        return s.orders[orderId];
    }
    
    /**
     * @dev Get remaining amount in an order
     * @param orderId The ID of the order
     * @return remaining The remaining shares available
     */
    function getRemainingAmount(uint256 orderId) 
        external 
        view 
        override 
        onlyValidOrder(orderId)
        returns (uint256 remaining) 
    {
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        TradeOrder storage order = s.orders[orderId];
        return order.shareAmount - order.filledAmount;
    }
    
    /**
     * @dev Check if an order is active
     * @param orderId The ID of the order
     * @return active Whether the order is active
     */
    function isOrderActive(uint256 orderId) 
        external 
        view 
        override 
        onlyValidOrder(orderId)
        returns (bool active) 
    {
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        TradeOrder storage order = s.orders[orderId];
        
        return order.status == OrderStatus.Active && block.timestamp <= order.expiryTime;
    }
    
    /**
     * @dev Get all orders for a share token
     * @param shareToken The address of the share token
     * @return orderIds Array of order IDs
     */
    function getOrdersByShareToken(address shareToken) 
        external 
        view 
        override 
        returns (uint256[] memory orderIds) 
    {
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        return s.shareTokenOrders[shareToken];
    }
    
    /**
     * @dev Get all orders created by a maker
     * @param maker The maker address
     * @return orderIds Array of order IDs
     */
    function getOrdersByMaker(address maker) 
        external 
        view 
        override 
        returns (uint256[] memory orderIds) 
    {
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        return s.makerOrders[maker];
    }
    
    /**
     * @dev Get identity registry address
     * @return identityRegistry The identity registry address
     */
    function identityRegistry() external view returns (address) {
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        return s.identityRegistry;
    }
    
    /**
     * @dev Clean up expired orders and unfreeze tokens
     * @param orderId The ID of the expired order
     */
    function cleanupExpiredOrder(uint256 orderId) external onlyValidOrder(orderId) {
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        TradeOrder storage order = s.orders[orderId];
        
        require(order.status == OrderStatus.Active, "P2PTrading: order not active");
        require(block.timestamp > order.expiryTime, "P2PTrading: order not expired yet");
        
        // Calculate remaining shares to unfreeze
        uint256 remainingShares = order.shareAmount - order.filledAmount;
        
        // Update order status
        order.status = OrderStatus.Expired;
        
        // Unfreeze remaining shares on maker's address
        if (remainingShares > 0) {
            ILuxShareFactory factoryContract = ILuxShareFactory(s.factory);
            factoryContract.unfreezePartialTokens(order.shareToken, order.maker, remainingShares);
        }
    }
    
    /**
     * @dev Get factory address
     * @return factory The factory address
     */
    function factory() external view returns (address) {
        MarketStorage.P2PTradingLayout storage s = MarketStorage.p2pTradingLayout();
        return s.factory;
    }
}

