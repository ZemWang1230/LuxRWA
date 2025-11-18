// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/**
 * @title IPrimaryOffering
 * @dev Interface for primary market offering contract
 * @notice Manages subscription (primary sale) of ShareTokens from issuers to qualified investors
 */
interface IPrimaryOffering {
    
    // ==================== Structs ====================
    
    /**
     * @dev Structure representing an offering configuration
     */
    struct OfferingConfig {
        address shareToken;           // ShareToken being offered
        address issuer;               // Issuer address (must be verified)
        address paymentToken;         // Payment token address (e.g., USDC)
        uint256 pricePerShare;        // Price per share in payment token
        uint256 totalShares;          // Total shares available for subscription
        uint256 minSubscription;      // Minimum subscription amount (in shares)
        uint256 maxSubscription;      // Maximum subscription amount (in shares, 0 = no limit)
        uint256 startTime;            // Offering start timestamp
        uint256 endTime;              // Offering end timestamp
        bool isActive;                // Whether the offering is active
    }
    
    /**
     * @dev Structure representing a subscription record
     */
    struct Subscription {
        address investor;             // Investor address
        uint256 shareAmount;          // Amount of shares subscribed
        uint256 paymentAmount;        // Amount of payment token paid
        uint256 timestamp;            // Subscription timestamp
        bool settled;                 // Whether the subscription has been settled
    }
    
    // ==================== Events ====================
    
    /**
     * @dev Emitted when a new offering is created
     */
    event OfferingCreated(
        uint256 indexed offeringId,
        address indexed shareToken,
        address indexed issuer,
        uint256 totalShares,
        uint256 pricePerShare
    );
    
    /**
     * @dev Emitted when an offering is updated
     */
    event OfferingUpdated(
        uint256 indexed offeringId,
        uint256 totalShares,
        uint256 pricePerShare
    );
    
    /**
     * @dev Emitted when an offering is activated
     */
    event OfferingActivated(uint256 indexed offeringId);
    
    /**
     * @dev Emitted when an offering is deactivated
     */
    event OfferingDeactivated(uint256 indexed offeringId);
    
    /**
     * @dev Emitted when an offering is closed
     */
    event OfferingClosed(uint256 indexed offeringId, uint256 sharesSold);
    
    /**
     * @dev Emitted when an investor subscribes to shares
     */
    event SharesSubscribed(
        uint256 indexed offeringId,
        address indexed investor,
        uint256 shareAmount,
        uint256 paymentAmount
    );
    
    /**
     * @dev Emitted when payment is withdrawn by issuer
     */
    event PaymentWithdrawn(
        uint256 indexed offeringId,
        address indexed issuer,
        uint256 amount
    );
    
    // ==================== Functions ====================
    
    /**
     * @dev Create a new offering
     * @param config The offering configuration
     * @return offeringId The ID of the created offering
     */
    function createOffering(OfferingConfig calldata config) external returns (uint256 offeringId);
    
    /**
     * @dev Update an existing offering (before it starts)
     * @param offeringId The ID of the offering
     * @param config The updated offering configuration
     */
    function updateOffering(uint256 offeringId, OfferingConfig calldata config) external;
    
    /**
     * @dev Activate an offering
     * @param offeringId The ID of the offering
     */
    function activateOffering(uint256 offeringId) external;
    
    /**
     * @dev Deactivate an offering
     * @param offeringId The ID of the offering
     */
    function deactivateOffering(uint256 offeringId) external;
    
    /**
     * @dev Close an offering
     * @param offeringId The ID of the offering
     */
    function closeOffering(uint256 offeringId) external;
    
    /**
     * @dev Subscribe to shares in an offering
     * @param offeringId The ID of the offering
     * @param shareAmount The amount of shares to subscribe
     */
    function subscribe(uint256 offeringId, uint256 shareAmount) external;
    
    /**
     * @dev Withdraw payment tokens collected from subscriptions
     * @param offeringId The ID of the offering
     */
    function withdrawPayment(uint256 offeringId) external;
    
    // ==================== View Functions ====================
    
    /**
     * @dev Get offering details
     * @param offeringId The ID of the offering
     * @return config The offering configuration
     */
    function getOffering(uint256 offeringId) external view returns (OfferingConfig memory config);
    
    /**
     * @dev Get remaining shares in an offering
     * @param offeringId The ID of the offering
     * @return remaining The remaining shares available
     */
    function getRemainingShares(uint256 offeringId) external view returns (uint256 remaining);
    
    /**
     * @dev Get total shares sold in an offering
     * @param offeringId The ID of the offering
     * @return sold The total shares sold
     */
    function getSharesSold(uint256 offeringId) external view returns (uint256 sold);
    
    /**
     * @dev Get investor's subscription for an offering
     * @param offeringId The ID of the offering
     * @param investor The investor address
     * @return subscription The subscription details
     */
    function getSubscription(uint256 offeringId, address investor) 
        external 
        view 
        returns (Subscription memory subscription);
    
    /**
     * @dev Get total payment amount collected for an offering
     * @param offeringId The ID of the offering
     * @return amount The total payment collected
     */
    function getTotalPaymentCollected(uint256 offeringId) external view returns (uint256 amount);
    
    /**
     * @dev Get withdrawn payment amount for an offering
     * @param offeringId The ID of the offering
     * @return amount The payment amount withdrawn
     */
    function getWithdrawnPayment(uint256 offeringId) external view returns (uint256 amount);
    
    /**
     * @dev Check if an offering is active and accepting subscriptions
     * @param offeringId The ID of the offering
     * @return active Whether the offering is active
     */
    function isOfferingActive(uint256 offeringId) external view returns (bool active);
    
    /**
     * @dev Get all offerings for a share token
     * @param shareToken The address of the share token
     * @return offeringIds Array of offering IDs
     */
    function getOfferingsByShareToken(address shareToken) external view returns (uint256[] memory offeringIds);
}

