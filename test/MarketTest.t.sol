// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./BaseFixture.sol";
import "../src/market/implementation/PrimaryOffering.sol";
import "../src/market/implementation/P2PTrading.sol";
import "../src/token/implementation/LuxShareToken.sol";

contract MarketTest is BaseFixture {
    // Test variables
    uint256 public offeringId;
    address public shareToken;
    uint256 public totalShares = 10000 * 10**18; // 10,000 shares
    uint256 public pricePerShare = 100 * 10**6; // 100 USDC per share (6 decimals)

    function setUp() public {
        // Setup base environment
        ONCHAINIDSetUp();
        IdentityRegistrySetUp();
        InvestorRegistrationSetUp();
        LuxRWAAssetNFTSetUp();
        LuxRWATokenSetUp();

        // Setup market contracts
        MarketSetUp();

        // Setup test data
        shareToken = shareTokenAddress1;
    }

    // ==================== Test Primary Offering ====================

    function test_PrimaryOffering_CreateOffering() public {
        vm.startPrank(issuerA);

        // Create offering configuration
        IPrimaryOffering.OfferingConfig memory config = IPrimaryOffering.OfferingConfig({
            shareToken: shareToken,
            issuer: issuerA,
            paymentToken: address(usdc),
            pricePerShare: pricePerShare,
            totalShares: totalShares,
            minSubscription: 10 * 10**18, // Min 10 shares
            maxSubscription: 5000 * 10**18, // Max 5000 shares
            startTime: block.timestamp,
            endTime: block.timestamp + 30 days,
            isActive: false
        });

        // Create offering
        offeringId = primaryOffering.createOffering(config);

        // Verify offering was created
        IPrimaryOffering.OfferingConfig memory retrievedConfig = primaryOffering.getOffering(offeringId);
        assertEq(retrievedConfig.shareToken, shareToken);
        assertEq(retrievedConfig.issuer, issuerA);
        assertEq(retrievedConfig.paymentToken, address(usdc));
        assertEq(retrievedConfig.pricePerShare, pricePerShare);
        assertEq(retrievedConfig.totalShares, totalShares);

        vm.stopPrank();
        console.log("Offering created");
    }

    function test_PrimaryOffering_ActivateAndSubscribe() public {
        // First create offering
        test_PrimaryOffering_CreateOffering();

        // Issuer activates the offering
        vm.startPrank(issuerA);
        primaryOffering.activateOffering(offeringId);
        vm.stopPrank();

        // Verify offering is active
        assertTrue(primaryOffering.isOfferingActive(offeringId));

        // Investor AIA subscribes to half the shares (5000 shares)
        uint256 sharesToBuyAIA = 5000 * 10**18;
        uint256 paymentAmountAIA = sharesToBuyAIA * pricePerShare / 10**LuxShareToken(shareToken).decimals();

        vm.startPrank(investorAIA);
        usdc.approve(address(primaryOffering), paymentAmountAIA);
        primaryOffering.subscribe(offeringId, sharesToBuyAIA);
        vm.stopPrank();

        // Verify subscription
        IPrimaryOffering.Subscription memory subAIA = primaryOffering.getSubscription(offeringId, investorAIA);
        assertEq(subAIA.shareAmount, sharesToBuyAIA);
        assertEq(subAIA.paymentAmount, paymentAmountAIA);

        // Verify shares were transferred
        assertEq(LuxShareToken(shareToken).balanceOf(investorAIA), sharesToBuyAIA);

        console.log("Investor AIA subscribed 5000 shares");

        // Investor AIB subscribes to the other half (5000 shares)
        // payment = 5000 * 100 * 10**6 = 500000 * 10**6
        uint256 sharesToBuyAIB = 5000 * 10**18;
        uint256 paymentAmountAIB = sharesToBuyAIB * pricePerShare / 10**LuxShareToken(shareToken).decimals();

        vm.startPrank(investorAIB);
        usdc.approve(address(primaryOffering), paymentAmountAIB);
        primaryOffering.subscribe(offeringId, sharesToBuyAIB);
        vm.stopPrank();

        // Verify subscription
        IPrimaryOffering.Subscription memory subAIB = primaryOffering.getSubscription(offeringId, investorAIB);
        assertEq(subAIB.shareAmount, sharesToBuyAIB);
        assertEq(subAIB.paymentAmount, paymentAmountAIB);

        // Verify shares were transferred
        assertEq(LuxShareToken(shareToken).balanceOf(investorAIB), sharesToBuyAIB);

        // Verify total shares sold
        assertEq(primaryOffering.getSharesSold(offeringId), totalShares);
        assertEq(primaryOffering.getRemainingShares(offeringId), 0);

        console.log("Investor AIB subscribed 5000 shares");
    }

    function test_PrimaryOffering_IssuerWithdraw() public {
        // First complete subscription
        test_PrimaryOffering_ActivateAndSubscribe();

        uint256 totalPayment = primaryOffering.getTotalPaymentCollected(offeringId);
        // totalPayment is in USDC smallest units (6 decimals), should be 10000 * 100 * 10**6 = 1e12

        vm.startPrank(issuerA);
        uint256 issuerBalanceBefore = usdc.balanceOf(issuerA);
        primaryOffering.withdrawPayment(offeringId);
        uint256 issuerBalanceAfter = usdc.balanceOf(issuerA);
        vm.stopPrank();

        // Verify payment was withdrawn from contract to issuer
        assertEq(issuerBalanceAfter - issuerBalanceBefore, totalPayment);
        assertEq(primaryOffering.getWithdrawnPayment(offeringId), totalPayment);

        console.log("Issuer withdrew payment");
    }

    // ==================== Test P2P Trading ====================

    function test_P2PTrading_CreateSellOrder() public {
        // Setup: AIA has 5000 shares
        test_PrimaryOffering_ActivateAndSubscribe();

        uint256 orderId = _createSellOrder(investorAIA, 1000 * 10**18, 120 * 10**6); // 1000 shares at 120 USDC each

        // Verify order was created
        IP2PTrading.TradeOrder memory order = p2pTrading.getOrder(orderId);
        assertEq(order.maker, investorAIA);
        assertEq(order.shareToken, shareToken);
        assertEq(order.shareAmount, 1000 * 10**18);
        assertEq(order.pricePerShare, 120 * 10**6);
        assertEq(uint256(order.status), uint256(IP2PTrading.OrderStatus.Active));

        // Verify shares were frozen
        uint256 frozenTokens = LuxShareToken(shareToken).getFrozenTokens(investorAIA);
        assertEq(frozenTokens, 1000 * 10**18);

        console.log("Investor AIA created sell order, 1000 shares at 120 USDC each");
    }

    function test_P2PTrading_FillOrder() public {
        // Setup: Create sell order
        test_P2PTrading_CreateSellOrder();
        uint256 orderId = 0; // First order

        IP2PTrading.TradeOrder memory orderBefore = p2pTrading.getOrder(orderId);
        uint256 fillAmount = 800 * 10**18; // Fill 800 shares
        // payment = 800 * 120 * 10**6 / 10**6 = 96000 * 10**6
        uint256 paymentAmount = (fillAmount * orderBefore.pricePerShare) / 10**LuxShareToken(shareToken).decimals();

        // AIB fills the order
        vm.startPrank(investorAIB);
        usdc.approve(address(p2pTrading), paymentAmount);
        p2pTrading.fillOrder(orderId, fillAmount);
        vm.stopPrank();

        // Verify order was partially filled
        IP2PTrading.TradeOrder memory orderAfter = p2pTrading.getOrder(orderId);
        assertEq(orderAfter.filledAmount, fillAmount);
        assertEq(uint256(orderAfter.status), uint256(IP2PTrading.OrderStatus.Active));

        // Verify shares were transferred
        assertEq(LuxShareToken(shareToken).balanceOf(investorAIB), 5000 * 10**18 + fillAmount);
        assertEq(LuxShareToken(shareToken).balanceOf(investorAIA), 5000 * 10**18 - fillAmount);

        // Verify frozen tokens were reduced
        uint256 frozenTokens = LuxShareToken(shareToken).getFrozenTokens(investorAIA);
        assertEq(frozenTokens, orderBefore.shareAmount - fillAmount);

        // Verify updated usdc balance
        assertEq(usdc.balanceOf(investorAIB), 500000 * 10**6 - paymentAmount);
        assertEq(usdc.balanceOf(investorAIA), 500000 * 10**6 + paymentAmount);

        console.log("Investor AIB filled 800 shares at 120 USDC each");
    }

    function test_P2PTrading_CancelOrder() public {
        // Setup: Create sell order and partially fill it
        test_P2PTrading_FillOrder();

        uint256 orderId = 0;
        IP2PTrading.TradeOrder memory orderBefore = p2pTrading.getOrder(orderId);
        uint256 remainingAmount = orderBefore.shareAmount - orderBefore.filledAmount;

        // AIA cancels the remaining order
        vm.prank(investorAIA);
        p2pTrading.cancelOrder(orderId);

        // Verify order was cancelled
        IP2PTrading.TradeOrder memory orderAfter = p2pTrading.getOrder(orderId);
        assertEq(uint256(orderAfter.status), uint256(IP2PTrading.OrderStatus.Cancelled));

        // Verify frozen tokens were unfrozen
        uint256 frozenTokens = LuxShareToken(shareToken).getFrozenTokens(investorAIA);
        assertEq(frozenTokens, 0);

        assertEq(LuxShareToken(shareToken).balanceOf(investorAIA), 4000 * 10**18 + remainingAmount);

        console.log("Investor AIA cancelled the remaining order");
    }

    // ==================== Test Edge Cases and Error Handling ====================

    function test_PrimaryOffering_InvalidSubscription() public {
        // Setup offering
        test_PrimaryOffering_CreateOffering();
        vm.prank(issuerA);
        primaryOffering.activateOffering(offeringId);

        // Try to subscribe with insufficient approval
        vm.startPrank(investorAIA);
        uint256 shareAmount = 100 * 10**18;
        usdc.approve(address(primaryOffering), 1 * 10**6); // Insufficient approval

        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientAllowance(address,uint256,uint256)",
                address(primaryOffering),
                1 * 10**6,
                10_000 * 10**6
            )
        );
        primaryOffering.subscribe(offeringId, shareAmount);
        vm.stopPrank();

        console.log("Investor AIA tried to subscribe with insufficient approval");

        vm.startPrank(investorAIA);
        usdc.transfer(investorAIB, 99_9999 * 10**6);
        assertEq(usdc.balanceOf(investorAIA), 1 * 10**6);
        usdc.approve(address(primaryOffering), 10_000 * 10**6);
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientBalance(address,uint256,uint256)",
                address(investorAIA),
                1 * 10**6,
                10_000 * 10**6
            )
        );
        primaryOffering.subscribe(offeringId, shareAmount);
        vm.stopPrank();

        console.log("Investor AIA tried to subscribe with insufficient balance");
    }

    function test_P2PTrading_ExpiredOrder() public {
        // Create order with short expiry
        test_PrimaryOffering_ActivateAndSubscribe();

        vm.startPrank(investorAIA);
        uint256 orderId = p2pTrading.createSellOrder(
            shareToken,
            1000 * 10**18,
            address(usdc),
            120 * 10**6,
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        // Try to fill expired order
        vm.startPrank(investorAIB);
        usdc.approve(address(p2pTrading), 50_0000 * 10**6);
        vm.warp(block.timestamp + 30 minutes);
        p2pTrading.fillOrder(orderId, 500 * 10**18);
        console.log("Investor AIB filled 500 shares at 120 USDC each before expiry");
        vm.warp(block.timestamp + 30 minutes + 1 seconds);
        vm.expectRevert("P2PTrading: order expired");
        p2pTrading.fillOrder(orderId, 500 * 10**18);
        vm.stopPrank();
        console.log("Investor AIB tried to fill expired order");
    }

    // ==================== Helper Functions ====================

    function _createSellOrder(
        address maker,
        uint256 shareAmount,
        uint256 pricePerShare_
    ) internal returns (uint256 orderId) {
        vm.startPrank(maker);

        orderId = p2pTrading.createSellOrder(
            shareToken,
            shareAmount,
            address(usdc),
            pricePerShare_,
            block.timestamp + 1 days
        );

        vm.stopPrank();
    }
}
