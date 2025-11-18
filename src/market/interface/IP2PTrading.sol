// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/**
 * @title IP2PTrading
 * @dev Interface for P2P (over-the-counter) trading of ShareTokens
 * @notice Facilitates direct bilateral trades between qualified investors
 * @notice All trades are subject to compliance checks
 */
interface IP2PTrading {
    
    // ==================== Enums ====================
    
    enum OrderStatus {
        Active,      // Order is active and can be filled
        Filled,      // Order has been completely filled
        Cancelled,   // Order has been cancelled by maker
        Expired      // Order has expired
    }
    
    // ==================== Structs ====================
    
    /**
     * @dev Structure representing a trade order
     */
    struct TradeOrder {
        address maker;           // Order creator
        address shareToken;      // ShareToken being traded
        uint256 shareAmount;     // Amount of shares
        address paymentToken;    // Payment token (e.g., USDC)
        uint256 pricePerShare;   // Price per share in payment token
        uint256 expiryTime;      // Expiry timestamp
        OrderStatus status;      // Order status
        uint256 filledAmount;    // Amount of shares filled
    }
    
    // ==================== Events ====================
    
    /**
     * @dev Emitted when a new trade order is created
     */
    event OrderCreated(
        uint256 indexed orderId,
        address indexed maker,
        address indexed shareToken,
        uint256 shareAmount,
        uint256 pricePerShare
    );
    
    /**
     * @dev Emitted when an order is filled
     */
    event OrderFilled(
        uint256 indexed orderId,
        address indexed taker,
        uint256 shareAmount,
        uint256 paymentAmount
    );
    
    /**
     * @dev Emitted when an order is cancelled
     */
    event OrderCancelled(uint256 indexed orderId);
    
    /**
     * @dev Emitted when an order is partially filled
     */
    event OrderPartiallyFilled(
        uint256 indexed orderId,
        address indexed taker,
        uint256 shareAmount,
        uint256 paymentAmount,
        uint256 remainingAmount
    );
    
    // ==================== Functions ====================
    
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
    ) external returns (uint256 orderId);
    
    /**
     * @dev Fill a sell order (buy shares)
     * @param orderId The ID of the order
     * @param shareAmount The amount of shares to buy
     */
    function fillOrder(uint256 orderId, uint256 shareAmount) external;
    
    /**
     * @dev Cancel an order
     * @param orderId The ID of the order
     */
    function cancelOrder(uint256 orderId) external;
    
    // ==================== View Functions ====================
    
    /**
     * @dev Get order details
     * @param orderId The ID of the order
     * @return order The order details
     */
    function getOrder(uint256 orderId) external view returns (TradeOrder memory order);
    
    /**
     * @dev Get remaining amount in an order
     * @param orderId The ID of the order
     * @return remaining The remaining shares available
     */
    function getRemainingAmount(uint256 orderId) external view returns (uint256 remaining);
    
    /**
     * @dev Check if an order is active
     * @param orderId The ID of the order
     * @return active Whether the order is active
     */
    function isOrderActive(uint256 orderId) external view returns (bool active);
    
    /**
     * @dev Get all orders for a share token
     * @param shareToken The address of the share token
     * @return orderIds Array of order IDs
     */
    function getOrdersByShareToken(address shareToken) external view returns (uint256[] memory orderIds);
    
    /**
     * @dev Get all orders created by a maker
     * @param maker The maker address
     * @return orderIds Array of order IDs
     */
    function getOrdersByMaker(address maker) external view returns (uint256[] memory orderIds);
}

