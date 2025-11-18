// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/IRevenueDistribution.sol";
import "../storage/MarketStorage.sol";
import "../../token/interface/ILuxShareToken.sol";
import "../../token/interface/ILuxShareFactory.sol";
import "../../registry/interface/IIdentityRegistry.sol";
import "../../compliance/interface/IModularCompliance.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
/**
 * @title RevenueDistribution
 * @dev Revenue distribution contract for ShareToken holders
 * @notice Manages revenue distribution using snapshot mechanism
 * @notice All claims require compliance checks
 */
contract RevenueDistribution is IRevenueDistribution, Ownable {
    using MarketStorage for MarketStorage.RevenueDistributionLayout;
    
    // ==================== Modifiers ====================
    
    modifier onlyValidDistribution(uint256 distributionId) {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        require(distributionId < s.nextDistributionId, "RevenueDistribution: invalid distribution ID");
        _;
    }
    
    modifier onlyIssuer(uint256 distributionId) {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        require(
            msg.sender == s.distributions[distributionId].issuer,
            "RevenueDistribution: caller is not the issuer"
        );
        _;
    }
    
    // ==================== Constructor ====================
    
    constructor(address factory_, address identityRegistry_) Ownable(msg.sender) {
        require(factory_ != address(0), "RevenueDistribution: invalid factory");
        require(identityRegistry_ != address(0), "RevenueDistribution: invalid identity registry");
        
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        s.factory = factory_;
        s.identityRegistry = identityRegistry_;
        s.nextDistributionId = 0;
        s.initialized = true;
    }
    
    // ==================== External Functions ====================
    
    /**
     * @dev Create a new revenue distribution
     * @param shareToken The address of the share token
     * @param rewardToken The address of the reward token (e.g., USDC)
     * @param totalReward The total amount of reward tokens to distribute
     * @param expiresAt Expiration timestamp (0 for no expiration)
     * @param memo Optional memo/description
     * @return distributionId The ID of the created distribution
     */
    function createDistribution(
        address shareToken,
        address rewardToken,
        uint256 totalReward,
        uint256 expiresAt,
        string calldata memo
    ) external override returns (uint256 distributionId) {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        
        // Validate inputs
        require(shareToken != address(0), "RevenueDistribution: invalid share token");
        require(rewardToken != address(0), "RevenueDistribution: invalid reward token");
        require(totalReward > 0, "RevenueDistribution: invalid total reward");
        
        if (expiresAt > 0) {
            require(expiresAt > block.timestamp, "RevenueDistribution: expiration in the past");
        }
        
        // Verify share token is valid (from factory)
        ILuxShareFactory factoryContract = ILuxShareFactory(s.factory);
        require(factoryContract.isShareToken(shareToken), "RevenueDistribution: invalid share token from factory");
        
        // Verify msg.sender is the issuer
        ILuxShareToken shareTokenContract = ILuxShareToken(shareToken);
        require(msg.sender == shareTokenContract.issuer(), "RevenueDistribution: caller is not the issuer");

        // Verify issuer is registered and verified
        IIdentityRegistry idRegistry = IIdentityRegistry(s.identityRegistry);
        require(idRegistry.contains(msg.sender), "RevenueDistribution: issuer not registered");
        require(idRegistry.isVerified(msg.sender), "RevenueDistribution: issuer not verified");
        
        // Create snapshot
        uint256 snapshotId = factoryContract.createSnapshot(shareToken);
        uint256 totalSharesAtSnapshot = shareTokenContract.totalSupplyAt(snapshotId);
        
        require(totalSharesAtSnapshot > 0, "RevenueDistribution: no shares at snapshot");
        
        // Transfer reward tokens to this contract
        IERC20 rewardTokenContract = IERC20(rewardToken);
        require(
            rewardTokenContract.transferFrom(msg.sender, address(this), totalReward),
            "RevenueDistribution: reward transfer failed"
        );
        
        // Get distribution ID and increment
        distributionId = s.nextDistributionId++;
        
        // Store distribution
        Distribution storage distribution = s.distributions[distributionId];
        distribution.shareToken = shareToken;
        distribution.rewardToken = rewardToken;
        distribution.issuer = msg.sender;
        distribution.totalReward = totalReward;
        distribution.snapshotId = snapshotId;
        distribution.totalSharesAtSnapshot = totalSharesAtSnapshot;
        distribution.totalClaimed = 0;
        distribution.createdAt = block.timestamp;
        distribution.expiresAt = expiresAt;
        distribution.active = true;
        distribution.memo = memo;
        
        // Add to indexes
        s.shareTokenDistributions[shareToken].push(distributionId);
        s.issuerDistributions[msg.sender].push(distributionId);
        
        emit DistributionCreated(
            distributionId,
            shareToken,
            rewardToken,
            totalReward,
            snapshotId,
            msg.sender
        );
        
        return distributionId;
    }
    
    /**
     * @dev Claim rewards for a specific distribution
     * @param distributionId The ID of the distribution
     * @return amount The amount of rewards claimed
     */
    function claim(uint256 distributionId) external override onlyValidDistribution(distributionId) returns (uint256 amount) {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        Distribution storage distribution = s.distributions[distributionId];
        
        // Check distribution is active
        require(distribution.active, "RevenueDistribution: distribution not active");
        
        // Check not expired
        if (distribution.expiresAt > 0) {
            require(block.timestamp <= distribution.expiresAt, "RevenueDistribution: distribution expired");
        }
        
        // Perform compliance checks
        _checkCompliance(distribution.shareToken, msg.sender);
        
        // Calculate claimable amount
        amount = _calculateClaimable(distributionId, msg.sender);
        require(amount > 0, "RevenueDistribution: no claimable rewards");
        
        // Update claimed amount
        s.claimedAmounts[distributionId][msg.sender] += amount;
        distribution.totalClaimed += amount;
        
        // Transfer rewards
        IERC20 rewardToken = IERC20(distribution.rewardToken);
        require(
            rewardToken.transfer(msg.sender, amount),
            "RevenueDistribution: reward transfer failed"
        );
        
        emit RewardClaimed(distributionId, msg.sender, amount);
        
        return amount;
    }
    
    /**
     * @dev Batch claim rewards for multiple distributions
     * @param distributionIds Array of distribution IDs
     * @return totalAmount The total amount of rewards claimed
     */
    function batchClaim(uint256[] calldata distributionIds) external override returns (uint256 totalAmount) {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        
        for (uint256 i = 0; i < distributionIds.length; i++) {
            uint256 distributionId = distributionIds[i];
            
            // Validate distribution ID
            require(distributionId < s.nextDistributionId, "RevenueDistribution: invalid distribution ID");
            
            Distribution storage distribution = s.distributions[distributionId];
            
            // Skip inactive or expired distributions
            if (!distribution.active) continue;
            if (distribution.expiresAt > 0 && block.timestamp > distribution.expiresAt) continue;
            
            // Perform compliance checks (will revert if not compliant)
            _checkCompliance(distribution.shareToken, msg.sender);
            
            // Calculate claimable amount
            uint256 amount = _calculateClaimable(distributionId, msg.sender);
            if (amount == 0) continue;
            
            // Update claimed amount
            s.claimedAmounts[distributionId][msg.sender] += amount;
            distribution.totalClaimed += amount;
            
            // Transfer rewards
            IERC20 rewardToken = IERC20(distribution.rewardToken);
            require(
                rewardToken.transfer(msg.sender, amount),
                "RevenueDistribution: reward transfer failed"
            );
            
            totalAmount += amount;
            
            emit RewardClaimed(distributionId, msg.sender, amount);
        }
        
        require(totalAmount > 0, "RevenueDistribution: no claimable rewards");
        
        return totalAmount;
    }
    
    /**
     * @dev Cancel a distribution and return unclaimed tokens to issuer
     * @param distributionId The ID of the distribution
     */
    function cancelDistribution(uint256 distributionId) 
        external 
        override 
        onlyValidDistribution(distributionId)
        onlyIssuer(distributionId)
    {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        Distribution storage distribution = s.distributions[distributionId];
        
        require(distribution.active, "RevenueDistribution: distribution not active");
        
        // Mark as inactive
        distribution.active = false;
        
        // Calculate and return unclaimed tokens
        uint256 unclaimed = distribution.totalReward - distribution.totalClaimed;
        if (unclaimed > 0) {
            IERC20 rewardToken = IERC20(distribution.rewardToken);
            require(
                rewardToken.transfer(distribution.issuer, unclaimed),
                "RevenueDistribution: refund transfer failed"
            );
        }
        
        emit DistributionCancelled(distributionId);
    }
    
    // ==================== View Functions ====================
    
    /**
     * @dev Get distribution details
     * @param distributionId The ID of the distribution
     * @return distribution The distribution details
     */
    function getDistribution(uint256 distributionId) 
        external 
        view 
        override 
        onlyValidDistribution(distributionId)
        returns (Distribution memory distribution) 
    {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        return s.distributions[distributionId];
    }
    
    /**
     * @dev Calculate claimable amount for an investor
     * @param distributionId The ID of the distribution
     * @param investor The address of the investor
     * @return claimable The claimable amount
     */
    function getClaimableAmount(uint256 distributionId, address investor) 
        external 
        view 
        override 
        onlyValidDistribution(distributionId)
        returns (uint256 claimable) 
    {
        return _calculateClaimable(distributionId, investor);
    }
    
    /**
     * @dev Get claimed amount for an investor
     * @param distributionId The ID of the distribution
     * @param investor The address of the investor
     * @return claimed The amount already claimed
     */
    function getClaimedAmount(uint256 distributionId, address investor) 
        external 
        view 
        override 
        onlyValidDistribution(distributionId)
        returns (uint256 claimed) 
    {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        return s.claimedAmounts[distributionId][investor];
    }
    
    /**
     * @dev Get all distributions for a share token
     * @param shareToken The address of the share token
     * @return distributionIds Array of distribution IDs
     */
    function getDistributionsByShareToken(address shareToken) 
        external 
        view 
        override 
        returns (uint256[] memory distributionIds) 
    {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        return s.shareTokenDistributions[shareToken];
    }
    
    /**
     * @dev Get all distributions created by an issuer
     * @param issuer The address of the issuer
     * @return distributionIds Array of distribution IDs
     */
    function getDistributionsByIssuer(address issuer) 
        external 
        view 
        override 
        returns (uint256[] memory distributionIds) 
    {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        return s.issuerDistributions[issuer];
    }
    
    /**
     * @dev Get remaining unclaimed rewards for a distribution
     * @param distributionId The ID of the distribution
     * @return remaining The remaining unclaimed amount
     */
    function getRemainingRewards(uint256 distributionId) 
        external 
        view 
        override 
        onlyValidDistribution(distributionId)
        returns (uint256 remaining) 
    {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        Distribution storage distribution = s.distributions[distributionId];
        return distribution.totalReward - distribution.totalClaimed;
    }
    
    /**
     * @dev Check if a distribution has expired
     * @param distributionId The ID of the distribution
     * @return expired Whether the distribution has expired
     */
    function isExpired(uint256 distributionId) 
        external 
        view 
        override 
        onlyValidDistribution(distributionId)
        returns (bool expired) 
    {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        Distribution storage distribution = s.distributions[distributionId];
        
        if (distribution.expiresAt == 0) {
            return false;
        }
        
        return block.timestamp > distribution.expiresAt;
    }
    
    /**
     * @dev Get factory address
     * @return The factory address
     */
    function factory() external view override returns (address) {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        return s.factory;
    }
    
    /**
     * @dev Get identity registry address
     * @return The identity registry address
     */
    function identityRegistry() external view override returns (address) {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        return s.identityRegistry;
    }
    
    // ==================== Internal Functions ====================
    
    /**
     * @dev Calculate claimable amount for an investor
     * @param distributionId The ID of the distribution
     * @param investor The address of the investor
     * @return claimable The claimable amount
     */
    function _calculateClaimable(uint256 distributionId, address investor) internal view returns (uint256 claimable) {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        Distribution storage distribution = s.distributions[distributionId];
        
        // Get investor's balance at snapshot
        ILuxShareToken shareToken = ILuxShareToken(distribution.shareToken);
        uint256 investorShares = shareToken.balanceOfAt(investor, distribution.snapshotId);
        
        if (investorShares == 0) {
            return 0;
        }
        
        // Calculate total claimable: (investorShares * totalReward) / totalSharesAtSnapshot
        uint256 totalClaimable = Math.mulDiv(
            investorShares, 
            distribution.totalReward, 
            distribution.totalSharesAtSnapshot,
            Math.Rounding.Floor
        );
        
        // Subtract already claimed amount
        uint256 alreadyClaimed = s.claimedAmounts[distributionId][investor];
        
        if (totalClaimable <= alreadyClaimed) {
            return 0;
        }
        
        return totalClaimable - alreadyClaimed;
    }
    
    /**
     * @dev Check compliance for claiming rewards
     * @param shareToken The share token address
     * @param investor The investor address
     */
    function _checkCompliance(address shareToken, address investor) internal view {
        MarketStorage.RevenueDistributionLayout storage s = MarketStorage.revenueDistributionLayout();
        
        // Check investor is registered and verified
        IIdentityRegistry idRegistry = IIdentityRegistry(s.identityRegistry);
        require(idRegistry.contains(investor), "RevenueDistribution: investor not registered");
        require(idRegistry.isVerified(investor), "RevenueDistribution: investor not verified");
        
        // Check compliance for holding this share token
        ILuxShareToken shareTokenContract = ILuxShareToken(shareToken);
        IModularCompliance compliance = shareTokenContract.compliance();
        
        // We check if a transfer to themselves would be compliant
        // This ensures they meet all the holding requirements
        require(
            compliance.canTransfer(investor, investor, 0),
            "RevenueDistribution: not compliant"
        );
    }
}

