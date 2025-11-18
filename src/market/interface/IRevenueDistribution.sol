// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/**
 * @title IRevenueDistribution
 * @dev Interface for revenue distribution contract
 * @notice Manages revenue distribution to ShareToken holders based on snapshots
 */
interface IRevenueDistribution {
    
    // ==================== Events ====================
    
    /**
     * @dev Emitted when a new distribution is created
     * @param distributionId The ID of the distribution
     * @param shareToken The address of the share token
     * @param rewardToken The address of the reward token
     * @param totalReward The total amount of reward tokens
     * @param snapshotId The snapshot ID used for this distribution
     * @param issuer The address of the issuer
     */
    event DistributionCreated(
        uint256 indexed distributionId,
        address indexed shareToken,
        address rewardToken,
        uint256 totalReward,
        uint256 snapshotId,
        address indexed issuer
    );
    
    /**
     * @dev Emitted when rewards are claimed
     * @param distributionId The ID of the distribution
     * @param investor The address of the investor
     * @param amount The amount claimed
     */
    event RewardClaimed(
        uint256 indexed distributionId,
        address indexed investor,
        uint256 amount
    );
    
    /**
     * @dev Emitted when a distribution is cancelled
     * @param distributionId The ID of the distribution
     */
    event DistributionCancelled(uint256 indexed distributionId);
    
    // ==================== Structs ====================
    
    /**
     * @dev Distribution configuration
     */
    struct Distribution {
        address shareToken;         // The share token for this distribution
        address rewardToken;        // The token used for rewards (e.g., USDC)
        address issuer;             // The issuer of this distribution
        uint256 totalReward;        // Total amount of reward tokens
        uint256 snapshotId;         // Snapshot ID for calculating shares
        uint256 totalSharesAtSnapshot;  // Total supply at snapshot time
        uint256 totalClaimed;       // Total amount claimed so far
        uint256 createdAt;          // Creation timestamp
        uint256 expiresAt;          // Expiration timestamp (0 = no expiration)
        bool active;                // Whether the distribution is active
        string memo;                // Optional memo/description
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
    ) external returns (uint256 distributionId);
    
    /**
     * @dev Claim rewards for a specific distribution
     * @param distributionId The ID of the distribution
     * @return amount The amount of rewards claimed
     */
    function claim(uint256 distributionId) external returns (uint256 amount);
    
    /**
     * @dev Batch claim rewards for multiple distributions
     * @param distributionIds Array of distribution IDs
     * @return totalAmount The total amount of rewards claimed
     */
    function batchClaim(uint256[] calldata distributionIds) external returns (uint256 totalAmount);
    
    /**
     * @dev Cancel a distribution and return unclaimed tokens to issuer
     * @param distributionId The ID of the distribution
     */
    function cancelDistribution(uint256 distributionId) external;
    
    // ==================== View Functions ====================
    
    /**
     * @dev Get distribution details
     * @param distributionId The ID of the distribution
     * @return distribution The distribution details
     */
    function getDistribution(uint256 distributionId) external view returns (Distribution memory distribution);
    
    /**
     * @dev Calculate claimable amount for an investor
     * @param distributionId The ID of the distribution
     * @param investor The address of the investor
     * @return claimable The claimable amount
     */
    function getClaimableAmount(uint256 distributionId, address investor) external view returns (uint256 claimable);
    
    /**
     * @dev Get claimed amount for an investor
     * @param distributionId The ID of the distribution
     * @param investor The address of the investor
     * @return claimed The amount already claimed
     */
    function getClaimedAmount(uint256 distributionId, address investor) external view returns (uint256 claimed);
    
    /**
     * @dev Get all distributions for a share token
     * @param shareToken The address of the share token
     * @return distributionIds Array of distribution IDs
     */
    function getDistributionsByShareToken(address shareToken) external view returns (uint256[] memory distributionIds);
    
    /**
     * @dev Get all distributions created by an issuer
     * @param issuer The address of the issuer
     * @return distributionIds Array of distribution IDs
     */
    function getDistributionsByIssuer(address issuer) external view returns (uint256[] memory distributionIds);
    
    /**
     * @dev Get remaining unclaimed rewards for a distribution
     * @param distributionId The ID of the distribution
     * @return remaining The remaining unclaimed amount
     */
    function getRemainingRewards(uint256 distributionId) external view returns (uint256 remaining);
    
    /**
     * @dev Check if a distribution has expired
     * @param distributionId The ID of the distribution
     * @return expired Whether the distribution has expired
     */
    function isExpired(uint256 distributionId) external view returns (bool expired);
    
    /**
     * @dev Get factory address
     * @return factory The factory address
     */
    function factory() external view returns (address);
    
    /**
     * @dev Get identity registry address
     * @return identityRegistry The identity registry address
     */
    function identityRegistry() external view returns (address);
}

