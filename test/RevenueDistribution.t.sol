// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./BaseFixture.sol";
import "../src/market/implementation/RevenueDistribution.sol";
import "../src/market/interface/IRevenueDistribution.sol";
import "../src/market/interface/IPrimaryOffering.sol";
import "../src/token/interface/ILuxShareToken.sol";

contract RevenueDistributionTest is BaseFixture {
    RevenueDistribution public revenueDistribution;

    // Test scenario variables
    uint256 public offeringId;
    uint256 public distributionId;

    function setUp() public {
        // Setup base infrastructure
        ONCHAINIDSetUp();
        IdentityRegistrySetUp();
        InvestorRegistrationSetUp();
        LuxRWAAssetNFTSetUp();
        LuxRWATokenSetUp();
        MarketSetUp();

        // Deploy RevenueDistribution contract
        vm.startPrank(admin);
        revenueDistribution = new RevenueDistribution(address(luxRWAFactory), address(identityRegistry));
        luxRWAFactory.addAgentRole(address(revenueDistribution));
        vm.stopPrank();
    }

    function testRevenueDistributionFullScenario() public {
        // ============ Phase 1: Create Primary Offering ============
        vm.startPrank(issuerA);

        // Create offering configuration
        IPrimaryOffering.OfferingConfig memory config = IPrimaryOffering.OfferingConfig({
            shareToken: shareTokenAddress1,
            issuer: issuerA,
            paymentToken: address(usdc),
            pricePerShare: 100 * 10**6, // 100 USDC per share (considering USDC has 6 decimals)
            totalShares: 10000 * 10**18, // 10,000 shares total
            minSubscription: 1000 * 10**18, // Minimum 1000 shares
            maxSubscription: 0, // No maximum
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            isActive: false
        });

        // Create the offering
        offeringId = primaryOffering.createOffering(config);

        // Activate the offering
        primaryOffering.activateOffering(offeringId);

        vm.stopPrank();

        // ============ Phase 2: Investors Subscribe to Shares ============
        // AIA subscribes to 8000 shares
        vm.startPrank(investorAIA);
        usdc.approve(address(primaryOffering), 8000 * 100 * 10**6); // 8000 shares * 100 USDC * 10^6
        primaryOffering.subscribe(offeringId, 8000 * 10**18);
        vm.stopPrank();

        // AIB subscribes to 2000 shares
        vm.startPrank(investorAIB);
        usdc.approve(address(primaryOffering), 2000 * 100 * 10**6); // 2000 shares * 100 USDC * 10^6
        primaryOffering.subscribe(offeringId, 2000 * 10**18);
        vm.stopPrank();

        // Verify subscriptions
        assertEq(primaryOffering.getSharesSold(offeringId), 10000 * 10**18, "Total shares sold should be 10000");

        IPrimaryOffering.Subscription memory aiaSub = primaryOffering.getSubscription(offeringId, investorAIA);
        IPrimaryOffering.Subscription memory aibSub = primaryOffering.getSubscription(offeringId, investorAIB);

        assertEq(aiaSub.shareAmount, 8000 * 10**18, "AIA should have 8000 shares");
        assertEq(aibSub.shareAmount, 2000 * 10**18, "AIB should have 2000 shares");

        // ============ Phase 3: Time Passes (Hold for 1 Day) ============
        vm.warp(block.timestamp + 1 days);

        // ============ Phase 4: Create Revenue Distribution ============
        vm.startPrank(issuerA);

        // Mint 100 USDC to issuer for distribution
        usdc.mint(issuerA, 100 * 10**6);

        // Approve RevenueDistribution to spend USDC
        usdc.approve(address(revenueDistribution), 100 * 10**6);

        // Create distribution with 1 day expiration
        distributionId = revenueDistribution.createDistribution(
            shareTokenAddress1,
            address(usdc),
            100 * 10**6, // 100 USDC total reward
            block.timestamp + 2 days, // Expires in 2 day, since tx is in the same block, so +1 days will same as block.timestamp
            "Daily rental income distribution"
        );

        vm.stopPrank();

        // Verify distribution creation
        IRevenueDistribution.Distribution memory dist = revenueDistribution.getDistribution(distributionId);
        assertEq(dist.shareToken, shareTokenAddress1, "Distribution share token should match");
        assertEq(dist.rewardToken, address(usdc), "Distribution reward token should be USDC");
        assertEq(dist.totalReward, 100 * 10**6, "Total reward should be 100 USDC");
        assertEq(dist.totalSharesAtSnapshot, 10000 * 10**18, "Total shares at snapshot should be 10000");

        // ============ Phase 5: Claim Rewards ============
        // Check claimable amounts
        uint256 aiaClaimable = revenueDistribution.getClaimableAmount(distributionId, investorAIA);

        // AIA should get 80% (8000/10000) = 80 USDC
        assertEq(aiaClaimable, 80 * 10**6, "AIA should be able to claim 80 USDC");

        // AIB should get 20% (2000/10000) = 20 USDC
        uint256 aibClaimableTotal = revenueDistribution.getClaimableAmount(distributionId, investorAIB);
        assertEq(aibClaimableTotal, 20 * 10**6, "AIB should be able to claim 20 USDC");

        // AIA claims all at once (80 USDC)
        vm.startPrank(investorAIA);
        uint256 aiaClaimed = revenueDistribution.claim(distributionId);
        assertEq(aiaClaimed, 80 * 10**6, "AIA should claim 80 USDC");
        vm.stopPrank();

        // AIB claims all at once (20 USDC)
        vm.startPrank(investorAIB);
        uint256 aibClaimed = revenueDistribution.claim(distributionId);
        assertEq(aibClaimed, 20 * 10**6, "AIB should claim 20 USDC");
        vm.stopPrank();

        // Verify final balances
        assertEq(usdc.balanceOf(investorAIA), 1000000 * 10**6 - 8000 * 100 * 10**6 + 80 * 10**6, "AIA should have received 80 USDC reward");
        assertEq(usdc.balanceOf(investorAIB), 1000000 * 10**6 - 2000 * 100 * 10**6 + 20 * 10**6, "AIB should have received 20 USDC reward");

        // Check distribution state
        dist = revenueDistribution.getDistribution(distributionId);
        assertEq(dist.totalClaimed, 100 * 10**6, "Total claimed should be 100 USDC");
        assertEq(revenueDistribution.getRemainingRewards(distributionId), 0, "No rewards should remain");
    }

    function testRevenueDistributionCancellation() public {
        // ============ Setup Similar to Full Scenario ============
        // Create offering and subscriptions (similar to above)
        vm.startPrank(issuerA);

        IPrimaryOffering.OfferingConfig memory config = IPrimaryOffering.OfferingConfig({
            shareToken: shareTokenAddress1,
            issuer: issuerA,
            paymentToken: address(usdc),
            pricePerShare: 100 * 10**6,
            totalShares: 10000 * 10**18,
            minSubscription: 1000 * 10**18,
            maxSubscription: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            isActive: false
        });

        offeringId = primaryOffering.createOffering(config);
        primaryOffering.activateOffering(offeringId);
        vm.stopPrank();

        // Subscriptions
        vm.startPrank(investorAIA);
        usdc.approve(address(primaryOffering), 8000 * 100 * 10**6);
        primaryOffering.subscribe(offeringId, 8000 * 10**18);
        vm.stopPrank();

        vm.startPrank(investorAIB);
        usdc.approve(address(primaryOffering), 2000 * 100 * 10**6);
        primaryOffering.subscribe(offeringId, 2000 * 10**18);
        vm.stopPrank();

        // Time passes
        vm.warp(block.timestamp + 1 days);

        // Create distribution
        vm.startPrank(issuerA);
        usdc.mint(issuerA, 100 * 10**6);
        usdc.approve(address(revenueDistribution), 100 * 10**6);

        distributionId = revenueDistribution.createDistribution(
            shareTokenAddress1,
            address(usdc),
            100 * 10**6,
            block.timestamp + 7 days,
            "Daily rental income distribution"
        );
        vm.stopPrank();

        // ============ AIA Claims All ============
        vm.startPrank(investorAIA);
        uint256 aiaClaimed = revenueDistribution.claim(distributionId);
        assertEq(aiaClaimed, 80 * 10**6, "AIA should claim 80 USDC");
        vm.stopPrank();

        // ============ Issuer Cancels Distribution ============
        vm.startPrank(issuerA);
        revenueDistribution.cancelDistribution(distributionId);
        vm.stopPrank();

        // Verify distribution is cancelled
        IRevenueDistribution.Distribution memory dist = revenueDistribution.getDistribution(distributionId);
        assertFalse(dist.active, "Distribution should be inactive");

        // Check remaining funds returned to issuer
        // AIA claimed 80 USDC, so 20 USDC should be returned (AIB didn't claim)
        assertEq(usdc.balanceOf(issuerA), 20 * 10**6, "Issuer should receive 20 USDC back");

        // Try to claim after cancellation - should fail
        vm.startPrank(investorAIB);
        vm.expectRevert("RevenueDistribution: distribution not active");
        revenueDistribution.claim(distributionId);
        vm.stopPrank();
    }

    function testRevenueDistributionExpiration() public {
        // ============ Setup Similar to Full Scenario ============
        vm.startPrank(issuerA);

        IPrimaryOffering.OfferingConfig memory config = IPrimaryOffering.OfferingConfig({
            shareToken: shareTokenAddress1,
            issuer: issuerA,
            paymentToken: address(usdc),
            pricePerShare: 100 * 10**6,
            totalShares: 10000 * 10**18,
            minSubscription: 1000 * 10**18,
            maxSubscription: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            isActive: false
        });

        offeringId = primaryOffering.createOffering(config);
        primaryOffering.activateOffering(offeringId);
        vm.stopPrank();

        // Subscriptions
        vm.startPrank(investorAIA);
        usdc.approve(address(primaryOffering), 8000 * 100 * 10**6);
        primaryOffering.subscribe(offeringId, 8000 * 10**18);
        vm.stopPrank();

        // Time passes
        vm.warp(block.timestamp + 1 days);

        // Create distribution with short expiration
        vm.startPrank(issuerA);
        usdc.mint(issuerA, 100 * 10**6);
        usdc.approve(address(revenueDistribution), 100 * 10**6);

        distributionId = revenueDistribution.createDistribution(
            shareTokenAddress1,
            address(usdc),
            100 * 10**6,
            block.timestamp + 1 hours, // Expires in 1 hour
            "Daily rental income distribution"
        );
        vm.stopPrank();

        // Time passes beyond expiration
        vm.warp(block.timestamp + 2 hours);

        // Try to claim after expiration - should fail
        vm.startPrank(investorAIA);
        vm.expectRevert("RevenueDistribution: distribution expired");
        revenueDistribution.claim(distributionId);
        vm.stopPrank();

        // Check if distribution is expired
        assertTrue(revenueDistribution.isExpired(distributionId), "Distribution should be expired");
    }

    function testSnapshotBalanceOfAt() public {
        // ============ Setup Similar to Full Scenario ============
        vm.startPrank(issuerA);

        IPrimaryOffering.OfferingConfig memory config = IPrimaryOffering.OfferingConfig({
            shareToken: shareTokenAddress1,
            issuer: issuerA,
            paymentToken: address(usdc),
            pricePerShare: 100 * 10**6,
            totalShares: 10000 * 10**18,
            minSubscription: 1000 * 10**18,
            maxSubscription: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            isActive: false
        });

        offeringId = primaryOffering.createOffering(config);
        primaryOffering.activateOffering(offeringId);
        vm.stopPrank();

        // Subscriptions
        vm.startPrank(investorAIA);
        usdc.approve(address(primaryOffering), 8000 * 100 * 10**6);
        primaryOffering.subscribe(offeringId, 8000 * 10**18);
        vm.stopPrank();

        vm.startPrank(investorAIB);
        usdc.approve(address(primaryOffering), 2000 * 100 * 10**6);
        primaryOffering.subscribe(offeringId, 2000 * 10**18);
        vm.stopPrank();

        // Check current balances
        ILuxShareToken shareToken = ILuxShareToken(shareTokenAddress1);
        assertEq(shareToken.balanceOf(investorAIA), 8000 * 10**18, "AIA should have 8000 shares");
        assertEq(shareToken.balanceOf(investorAIB), 2000 * 10**18, "AIB should have 2000 shares");

        // Create snapshot
        vm.startPrank(admin);
        uint256 snapshotId = luxRWAFactory.createSnapshot(shareTokenAddress1);
        vm.stopPrank();

        // Check balances at snapshot
        assertEq(shareToken.balanceOfAt(investorAIA, snapshotId), 8000 * 10**18, "AIA should have 8000 shares at snapshot");
        assertEq(shareToken.balanceOfAt(investorAIB, snapshotId), 2000 * 10**18, "AIB should have 2000 shares at snapshot");
        assertEq(shareToken.totalSupplyAt(snapshotId), 10000 * 10**18, "Total supply at snapshot should be 10000");
    }

    function testBatchClaim() public {
        // ============ Setup Multiple Distributions ============
        vm.startPrank(issuerA);

        IPrimaryOffering.OfferingConfig memory config = IPrimaryOffering.OfferingConfig({
            shareToken: shareTokenAddress1,
            issuer: issuerA,
            paymentToken: address(usdc),
            pricePerShare: 100 * 10**6,
            totalShares: 10000 * 10**18,
            minSubscription: 1000 * 10**18,
            maxSubscription: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            isActive: false
        });

        offeringId = primaryOffering.createOffering(config);
        primaryOffering.activateOffering(offeringId);
        vm.stopPrank();

        // Subscriptions
        vm.startPrank(investorAIA);
        usdc.approve(address(primaryOffering), 8000 * 100 * 10**6);
        primaryOffering.subscribe(offeringId, 8000 * 10**18);
        vm.stopPrank();

        vm.startPrank(investorAIB);
        usdc.approve(address(primaryOffering), 2000 * 100 * 10**6);
        primaryOffering.subscribe(offeringId, 2000 * 10**18);
        vm.stopPrank();

        // Create multiple distributions
        vm.startPrank(issuerA);

        // Distribution 1: 50 USDC
        usdc.mint(issuerA, 50 * 10**6);
        usdc.approve(address(revenueDistribution), 50 * 10**6);
        uint256 distId1 = revenueDistribution.createDistribution(
            shareTokenAddress1,
            address(usdc),
            50 * 10**6,
            block.timestamp + 7 days,
            "Distribution 1"
        );

        // Distribution 2: 30 USDC
        usdc.mint(issuerA, 30 * 10**6);
        usdc.approve(address(revenueDistribution), 30 * 10**6);
        uint256 distId2 = revenueDistribution.createDistribution(
            shareTokenAddress1,
            address(usdc),
            30 * 10**6,
            block.timestamp + 7 days,
            "Distribution 2"
        );

        vm.stopPrank();

        // Batch claim both distributions
        uint256[] memory distributionIds = new uint256[](2);
        distributionIds[0] = distId1;
        distributionIds[1] = distId2;

        vm.startPrank(investorAIA);
        uint256 totalClaimed = revenueDistribution.batchClaim(distributionIds);
        // AIA should get 80% of 50 + 80% of 30 = 40 + 24 = 64 USDC
        assertEq(totalClaimed, 64 * 10**6, "AIA should claim total 64 USDC from batch");
        vm.stopPrank();

        // Check individual claims
        assertEq(revenueDistribution.getClaimedAmount(distId1, investorAIA), 40 * 10**6, "AIA claimed 40 from dist1");
        assertEq(revenueDistribution.getClaimedAmount(distId2, investorAIA), 24 * 10**6, "AIA claimed 24 from dist2");
    }

    function testComplianceCheckOnClaim() public {
        // ============ Setup Similar to Full Scenario ============
        vm.startPrank(issuerA);

        IPrimaryOffering.OfferingConfig memory config = IPrimaryOffering.OfferingConfig({
            shareToken: shareTokenAddress1,
            issuer: issuerA,
            paymentToken: address(usdc),
            pricePerShare: 100 * 10**6,
            totalShares: 10000 * 10**18,
            minSubscription: 1000 * 10**18,
            maxSubscription: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            isActive: false
        });

        offeringId = primaryOffering.createOffering(config);
        primaryOffering.activateOffering(offeringId);
        vm.stopPrank();

        // Subscriptions
        vm.startPrank(investorAIA);
        usdc.approve(address(primaryOffering), 8000 * 100 * 10**6);
        primaryOffering.subscribe(offeringId, 8000 * 10**18);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        // Create distribution
        vm.startPrank(issuerA);
        usdc.mint(issuerA, 100 * 10**6);
        usdc.approve(address(revenueDistribution), 100 * 10**6);

        distributionId = revenueDistribution.createDistribution(
            shareTokenAddress1,
            address(usdc),
            100 * 10**6,
            block.timestamp + 7 days,
            "Daily rental income distribution"
        );
        vm.stopPrank();

        // Try to claim with AIC (who has KYC and AML but is in China - may not be compliant)
        vm.startPrank(investorAIC);
        vm.expectRevert("RevenueDistribution: not compliant");
        revenueDistribution.claim(distributionId);
        vm.stopPrank();

        // AIA should be able to claim (fully compliant)
        vm.startPrank(investorAIA);
        uint256 claimed = revenueDistribution.claim(distributionId);
        assertEq(claimed, 80 * 10**6, "AIA should be able to claim");
        vm.stopPrank();
    }
}