// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/IPrimaryOffering.sol";
import "../storage/MarketStorage.sol";
import "../../token/interface/ILuxShareToken.sol";
import "../../token/interface/ILuxShareFactory.sol";
import "../../registry/interface/IIdentityRegistry.sol";
import "../../compliance/interface/IModularCompliance.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PrimaryOffering
 * @dev Primary market offering contract for ShareToken subscriptions
 * @notice Manages the initial sale of ShareTokens from issuers to qualified investors
 * @notice All subscriptions require KYC/compliance checks
 */
contract PrimaryOffering is IPrimaryOffering, Ownable {
    using MarketStorage for MarketStorage.PrimaryOfferingLayout;
    
    // ==================== Modifiers ====================
    
    modifier onlyValidOffering(uint256 offeringId) {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        require(offeringId < s.nextOfferingId, "PrimaryOffering: invalid offering ID");
        _;
    }
    
    modifier onlyIssuer(uint256 offeringId) {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        require(
            msg.sender == s.offerings[offeringId].issuer,
            "PrimaryOffering: caller is not the issuer"
        );
        _;
    }
    
    // ==================== Constructor ====================
    
    constructor(address factory_, address identityRegistry_) Ownable(msg.sender) {
        require(factory_ != address(0), "PrimaryOffering: invalid factory");
        require(identityRegistry_ != address(0), "PrimaryOffering: invalid identity registry");
        
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        s.factory = factory_;
        s.identityRegistry = identityRegistry_;
        s.nextOfferingId = 0;
        s.initialized = true;
    }
    
    // ==================== External Functions ====================
    
    /**
     * @dev Create a new offering
     * @param config The offering configuration
     * @return offeringId The ID of the created offering
     */
    function createOffering(OfferingConfig calldata config) 
        external 
        override 
        returns (uint256 offeringId) 
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        
        // Validate configuration
        _validateOfferingConfig(config);
        
        // Check caller is the issuer
        require(msg.sender == config.issuer, "PrimaryOffering: caller is not the issuer");
        
        // Check issuer owns the ShareToken and has approved this contract
        ILuxShareToken shareToken = ILuxShareToken(config.shareToken);
        
        uint256 issuerBalance = shareToken.balanceOf(config.issuer);
        require(issuerBalance == config.totalShares, "PrimaryOffering: issuer does not own the total shares");
        
        // Get offering ID and increment
        offeringId = s.nextOfferingId++;
        
        // Store offering configuration
        s.offerings[offeringId] = config;
        s.shareTokenOfferings[config.shareToken].push(offeringId);
        
        emit OfferingCreated(
            offeringId,
            config.shareToken,
            config.issuer,
            config.totalShares,
            config.pricePerShare
        );
        
        return offeringId;
    }
    
    /**
     * @dev Update an existing offering (only before start time or if not active)
     * @param offeringId The ID of the offering
     * @param config The updated offering configuration
     */
    function updateOffering(uint256 offeringId, OfferingConfig calldata config) 
        external 
        override 
        onlyValidOffering(offeringId)
        onlyIssuer(offeringId)
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        OfferingConfig storage offering = s.offerings[offeringId];
        
        // Can only update before start or if not active
        require(
            block.timestamp < offering.startTime || !offering.isActive,
            "PrimaryOffering: offering already started or active"
        );
        
        // Cannot change core identifiers
        require(config.shareToken == offering.shareToken, "PrimaryOffering: cannot change share token");
        require(config.issuer == offering.issuer, "PrimaryOffering: cannot change issuer");
        
        // Validate new configuration
        _validateOfferingConfig(config);
        
        // Update offering
        s.offerings[offeringId] = config;
        
        emit OfferingUpdated(offeringId, config.totalShares, config.pricePerShare);
    }
    
    /**
     * @dev Activate an offering
     * @param offeringId The ID of the offering
     */
    function activateOffering(uint256 offeringId) 
        external 
        override 
        onlyValidOffering(offeringId)
        onlyIssuer(offeringId)
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        OfferingConfig storage offering = s.offerings[offeringId];
        
        require(!offering.isActive, "PrimaryOffering: offering already active");
        require(block.timestamp >= offering.startTime, "PrimaryOffering: offering not started yet");
        require(block.timestamp < offering.endTime, "PrimaryOffering: offering already ended");
        
        offering.isActive = true;
        
        emit OfferingActivated(offeringId);
    }
    
    /**
     * @dev Deactivate an offering
     * @param offeringId The ID of the offering
     */
    function deactivateOffering(uint256 offeringId) 
        external 
        override 
        onlyValidOffering(offeringId)
        onlyIssuer(offeringId)
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        OfferingConfig storage offering = s.offerings[offeringId];
        
        require(offering.isActive, "PrimaryOffering: offering not active");
        
        offering.isActive = false;
        
        emit OfferingDeactivated(offeringId);
    }
    
    /**
     * @dev Close an offering
     * @param offeringId The ID of the offering
     */
    function closeOffering(uint256 offeringId) 
        external 
        override 
        onlyValidOffering(offeringId)
        onlyIssuer(offeringId)
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        OfferingConfig storage offering = s.offerings[offeringId];
        
        offering.isActive = false;
        offering.endTime = block.timestamp;
        
        emit OfferingClosed(offeringId, s.sharesSold[offeringId]);
    }
    
    /**
     * @dev Subscribe to shares in an offering
     * @param offeringId The ID of the offering
     * @param shareAmount The amount of shares to subscribe
     */
    function subscribe(uint256 offeringId, uint256 shareAmount) 
        external 
        override 
        onlyValidOffering(offeringId)
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        OfferingConfig storage offering = s.offerings[offeringId];
        
        // Check offering is active and within time window
        require(offering.isActive, "PrimaryOffering: offering not active");
        require(block.timestamp >= offering.startTime, "PrimaryOffering: offering not started");
        require(block.timestamp <= offering.endTime, "PrimaryOffering: offering ended");
        
        // Validate subscription amount
        require(shareAmount >= offering.minSubscription, "PrimaryOffering: below minimum");
        if (offering.maxSubscription > 0) {
            require(shareAmount <= offering.maxSubscription, "PrimaryOffering: exceeds maximum");
        }
        
        // Check available shares
        uint256 remainingShares = offering.totalShares - s.sharesSold[offeringId];
        require(shareAmount <= remainingShares, "PrimaryOffering: insufficient shares available");
        
        // Perform KYC and compliance checks
        IIdentityRegistry idRegistry = IIdentityRegistry(s.identityRegistry);
        require(idRegistry.contains(msg.sender), "PrimaryOffering: investor not registered");
        require(idRegistry.isVerified(msg.sender), "PrimaryOffering: investor not verified");
        
        // Check compliance for this transfer
        ILuxShareToken shareToken = ILuxShareToken(offering.shareToken);
        IModularCompliance compliance = shareToken.compliance();
        require(
            compliance.canTransfer(offering.issuer, msg.sender, shareAmount),
            "PrimaryOffering: transfer not compliant"
        );
        
        // Calculate payment amount
        uint256 paymentAmount = (shareAmount * offering.pricePerShare) / 10**ILuxShareToken(offering.shareToken).decimals();
        
        // Transfer payment token from investor to this contract
        IERC20 paymentToken = IERC20(offering.paymentToken);
        require(
            paymentToken.transferFrom(msg.sender, address(this), paymentAmount),
            "PrimaryOffering: payment transfer failed"
        );
        
        // Transfer shares from issuer to investor using factory's forcedTransfer
        // This bypasses the need for issuer to approve this contract
        // Shares go directly from issuer to investor without touching this contract
        ILuxShareFactory factoryContract = ILuxShareFactory(s.factory);
        factoryContract.forcedTransfer(offering.shareToken, offering.issuer, msg.sender, shareAmount);
        
        // Update state
        s.sharesSold[offeringId] += shareAmount;
        s.totalPaymentCollected[offeringId] += paymentAmount;
        
        // Record subscription
        Subscription storage subscription = s.subscriptions[offeringId][msg.sender];
        subscription.investor = msg.sender;
        subscription.shareAmount += shareAmount;
        subscription.paymentAmount += paymentAmount;
        subscription.timestamp = block.timestamp;
        subscription.settled = true;
        
        emit SharesSubscribed(offeringId, msg.sender, shareAmount, paymentAmount);
    }
    
    /**
     * @dev Withdraw payment tokens collected from subscriptions
     * @param offeringId The ID of the offering
     */
    function withdrawPayment(uint256 offeringId) 
        external 
        override 
        onlyValidOffering(offeringId)
        onlyIssuer(offeringId)
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        OfferingConfig storage offering = s.offerings[offeringId];
        
        uint256 availablePayment = s.totalPaymentCollected[offeringId] - s.paymentWithdrawn[offeringId];
        require(availablePayment > 0, "PrimaryOffering: no payment to withdraw");
        
        // Update state
        s.paymentWithdrawn[offeringId] += availablePayment;
        
        // Transfer payment to issuer
        IERC20 paymentToken = IERC20(offering.paymentToken);
        require(
            paymentToken.transfer(offering.issuer, availablePayment),
            "PrimaryOffering: payment withdrawal failed"
        );
        
        emit PaymentWithdrawn(offeringId, offering.issuer, availablePayment);
    }
    
    // ==================== View Functions ====================
    
    /**
     * @dev Get offering details
     * @param offeringId The ID of the offering
     * @return config The offering configuration
     */
    function getOffering(uint256 offeringId) 
        external 
        view 
        override 
        onlyValidOffering(offeringId)
        returns (OfferingConfig memory config) 
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        return s.offerings[offeringId];
    }
    
    /**
     * @dev Get remaining shares in an offering
     * @param offeringId The ID of the offering
     * @return remaining The remaining shares available
     */
    function getRemainingShares(uint256 offeringId) 
        external 
        view 
        override 
        onlyValidOffering(offeringId)
        returns (uint256 remaining) 
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        return s.offerings[offeringId].totalShares - s.sharesSold[offeringId];
    }
    
    /**
     * @dev Get total shares sold in an offering
     * @param offeringId The ID of the offering
     * @return sold The total shares sold
     */
    function getSharesSold(uint256 offeringId) 
        external 
        view 
        override 
        onlyValidOffering(offeringId)
        returns (uint256 sold) 
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        return s.sharesSold[offeringId];
    }
    
    /**
     * @dev Get investor's subscription for an offering
     * @param offeringId The ID of the offering
     * @param investor The investor user address
     * @return subscription The subscription details
     */
    function getSubscription(uint256 offeringId, address investor) 
        external 
        view 
        override 
        onlyValidOffering(offeringId)
        returns (Subscription memory subscription) 
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        return s.subscriptions[offeringId][investor];
    }
    
    /**
     * @dev Get total payment amount collected for an offering
     * @param offeringId The ID of the offering
     * @return amount The total payment collected
     */
    function getTotalPaymentCollected(uint256 offeringId) 
        external 
        view 
        override 
        onlyValidOffering(offeringId)
        returns (uint256 amount) 
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        return s.totalPaymentCollected[offeringId];
    }
    
    /**
     * @dev Get withdrawn payment amount for an offering
     * @param offeringId The ID of the offering
     * @return amount The payment amount withdrawn
     */
    function getWithdrawnPayment(uint256 offeringId) 
        external 
        view 
        override 
        onlyValidOffering(offeringId)
        returns (uint256 amount) 
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        return s.paymentWithdrawn[offeringId];
    }
    
    /**
     * @dev Check if an offering is active and accepting subscriptions
     * @param offeringId The ID of the offering
     * @return active Whether the offering is active
     */
    function isOfferingActive(uint256 offeringId) 
        external 
        view 
        override 
        onlyValidOffering(offeringId)
        returns (bool active) 
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        OfferingConfig storage offering = s.offerings[offeringId];
        
        return offering.isActive 
            && block.timestamp >= offering.startTime 
            && block.timestamp <= offering.endTime;
    }
    
    /**
     * @dev Get all offerings for a share token
     * @param shareToken The address of the share token
     * @return offeringIds Array of offering IDs
     */
    function getOfferingsByShareToken(address shareToken) 
        external 
        view 
        override 
        returns (uint256[] memory offeringIds) 
    {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        return s.shareTokenOfferings[shareToken];
    }
    
    /**
     * @dev Get factory address
     * @return factory The factory address
     */
    function factory() external view returns (address) {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        return s.factory;
    }
    
    /**
     * @dev Get identity registry address
     * @return identityRegistry The identity registry address
     */
    function identityRegistry() external view returns (address) {
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        return s.identityRegistry;
    }
    
    // ==================== Internal Functions ====================
    
    /**
     * @dev Validate offering configuration
     * @param config The offering configuration to validate
     */
    function _validateOfferingConfig(OfferingConfig calldata config) internal view {
        require(config.shareToken != address(0), "PrimaryOffering: invalid share token");
        require(config.issuer != address(0), "PrimaryOffering: invalid issuer");
        require(config.paymentToken != address(0), "PrimaryOffering: invalid payment token");
        require(config.pricePerShare > 0, "PrimaryOffering: invalid price");
        require(config.totalShares > 0, "PrimaryOffering: invalid total shares");
        require(config.startTime < config.endTime, "PrimaryOffering: invalid time window");
        require(config.minSubscription > 0, "PrimaryOffering: invalid minimum subscription");
        
        if (config.maxSubscription > 0) {
            require(
                config.maxSubscription >= config.minSubscription,
                "PrimaryOffering: max less than min"
            );
            require(
                config.maxSubscription <= config.totalShares,
                "PrimaryOffering: max exceeds total"
            );
        }
        
        // Verify issuer is registered and verified
        MarketStorage.PrimaryOfferingLayout storage s = MarketStorage.primaryOfferingLayout();
        IIdentityRegistry idRegistry = IIdentityRegistry(s.identityRegistry);
        require(idRegistry.contains(config.issuer), "PrimaryOffering: issuer not registered");
        require(idRegistry.isVerified(config.issuer), "PrimaryOffering: issuer not verified");
        
        // Verify share token is valid (from factory)
        ILuxShareFactory factoryContract = ILuxShareFactory(s.factory);
        require(factoryContract.isShareToken(config.shareToken), "PrimaryOffering: invalid share token from factory");
    }
}

