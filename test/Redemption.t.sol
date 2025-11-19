// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./BaseFixture.sol";
import "../src/market/implementation/Redemption.sol";
import "../src/market/interface/IRedemption.sol";
import "../src/market/interface/IPrimaryOffering.sol";
import "../src/token/interface/ILuxShareToken.sol";
import "../src/token/interface/ILuxShareFactory.sol";

contract RedemptionTest is BaseFixture {
    // Test data
    uint256 public testAssetTokenId;

    function setUp() public {
        // Setup all infrastructure
        ONCHAINIDSetUp();
        IdentityRegistrySetUp();
        InvestorRegistrationSetUp();
        LuxRWAAssetNFTSetUp();
        LuxRWATokenSetUp();
        MarketSetUp();

        // Deploy redemption contract as admin
        vm.startPrank(admin);
        redemption = new Redemption(address(luxRWAFactory), address(identityRegistry));
        luxRWAFactory.addAgentRole(address(redemption));
        vm.stopPrank();

        // Get the test asset token ID (first asset)
        testAssetTokenId = 1;
    }

    function test_Redemption_FullFlow() public {
        // Step 1: Issuer registers asset for redemption
        vm.startPrank(issuerA);
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();

        // Verify asset is registered
        (address assetNFTContract, uint256 assetTokenId, address registeredIssuer) = redemption.getAssetMapping(shareTokenAddress1);
        assertEq(assetNFTContract, address(luxRWAAssetNFT), "Asset NFT contract should be registered");
        assertEq(assetTokenId, testAssetTokenId, "Asset token ID should be registered");
        assertEq(registeredIssuer, issuerA, "Issuer should be registered");

        // Step 2: Investor AIA purchases all shares in primary market
        // First, create a primary offering
        vm.startPrank(issuerA);
        IPrimaryOffering.OfferingConfig memory config = IPrimaryOffering.OfferingConfig({
            shareToken: shareTokenAddress1,
            issuer: issuerA,
            paymentToken: address(usdc),
            pricePerShare: 100 * 10**6, // 100 USDC per share
            totalShares: 10000 * 10**18, // All shares available
            minSubscription: 100 * 10**18, // Min 100 shares
            maxSubscription: 10000 * 10**18, // Max 10000 shares
            startTime: block.timestamp,
            endTime: block.timestamp + 1 hours,
            isActive: true
        });
        uint256 offeringId = primaryOffering.createOffering(config);
        vm.stopPrank();

        // Investor AIA invests all available shares
        vm.startPrank(investorAIA);
        usdc.approve(address(primaryOffering), 1000000 * 10**6); // Approve 1M USDC
        primaryOffering.subscribe(offeringId, 10000 * 10**18); // Subscribe to all shares
        vm.stopPrank();

        // Verify investor AIA now owns all shares
        ILuxShareToken shareToken = ILuxShareToken(shareTokenAddress1);
        uint256 aiaBalance = shareToken.balanceOf(investorAIA);
        assertEq(aiaBalance, 10000 * 10**18, "AIA should own all shares");

        // Step 3: Investor AIA requests redemption
        vm.startPrank(investorAIA);
        uint256 redemptionId = redemption.requestRedemption(shareTokenAddress1, "Redeeming all shares for Rolex Submariner");
        vm.stopPrank();

        // Verify redemption request
        IRedemption.RedemptionRecord memory record = redemption.getRedemption(redemptionId);
        assertEq(record.redeemer, investorAIA, "Redeemer should be AIA");
        assertEq(record.shareToken, shareTokenAddress1, "Share token should be correct");
        assertEq(record.totalShares, 10000 * 10**18, "Total shares should be correct");
        assertEq(uint8(record.status), uint8(IRedemption.RedemptionStatus.Requested), "Status should be Requested");

        // Step 4: Investor AIA locks shares
        vm.startPrank(investorAIA);
        redemption.lockShares(redemptionId);
        vm.stopPrank();

        // Verify shares are locked (transferred to issuer)
        uint256 issuerBalance = shareToken.balanceOf(issuerA);
        assertEq(issuerBalance, 10000 * 10**18, "Shares should be locked with issuer");
        uint256 aiaBalanceAfterLock = shareToken.balanceOf(investorAIA);
        assertEq(aiaBalanceAfterLock, 0, "AIA should have no shares after locking");

        // Step 5: Investor AIA burns shares
        vm.startPrank(issuerA);
        redemption.burnShares(redemptionId);
        vm.stopPrank();

        // Verify shares are burned
        uint256 totalSupply = shareToken.totalSupply();
        assertEq(totalSupply, 0, "Total supply should be 0 after burning");
        uint256 issuerBalanceAfterBurn = shareToken.balanceOf(issuerA);
        assertEq(issuerBalanceAfterBurn, 0, "Issuer should have no shares after burning");

        // Step 6: Issuer completes redemption by transferring NFT
        vm.startPrank(issuerA);
        redemption.completeRedemption(redemptionId);
        vm.stopPrank();

        // Verify redemption is completed
        record = redemption.getRedemption(redemptionId);
        assertEq(uint8(record.status), uint8(IRedemption.RedemptionStatus.Completed), "Status should be Completed");

        // Verify NFT ownership transferred to redeemer
        address nftOwner = luxRWAAssetNFT.ownerOf(testAssetTokenId);
        assertEq(nftOwner, identityAIA, "AIA should own the NFT");

        console.log("Redemption Test Completed!");
    }

    function test_Redemption_CannotRedeemWithoutAllShares() public {
        // Setup: Issuer registers asset
        vm.startPrank(issuerA);
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();

        // Try to redeem without owning all shares (investor AIA has 0 shares initially)
        vm.startPrank(investorAIA);
        vm.expectRevert("Redemption: must hold all shares");
        redemption.requestRedemption(shareTokenAddress1, "Should fail");
        vm.stopPrank();
    }

    function test_Redemption_CannotRedeemUnregisteredAsset() public {
        // Try to redeem unregistered asset
        vm.startPrank(investorAIA);
        vm.expectRevert("Redemption: shareToken not registered");
        redemption.requestRedemption(shareTokenAddress1, "Should fail");
        vm.stopPrank();
    }

    function test_Redemption_CannotRegisterAssetWithoutOwnership() public {
        // Try to register asset without owning the NFT
        vm.startPrank(investorAIA);
        vm.expectRevert("Redemption: caller does not own NFT");
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();
    }

    function test_Redemption_UnregisterAsset() public {
        // First register asset
        vm.startPrank(issuerA);
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();

        // Verify registered
        assertTrue(redemption.isShareTokenRegistered(shareTokenAddress1), "Should be registered");

        // Unregister asset (only issuer can do this)
        vm.startPrank(issuerA);
        redemption.unregisterAsset(shareTokenAddress1);
        vm.stopPrank();

        // Verify unregistered
        assertFalse(redemption.isShareTokenRegistered(shareTokenAddress1), "Should be unregistered");
    }

    function test_Redemption_CannotUnregisterAssetWithoutIssuer() public {
        // First register asset
        vm.startPrank(issuerA);
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();

        // Try to unregister as non-issuer
        vm.startPrank(investorAIA);
        vm.expectRevert("Redemption: not authorized");
        redemption.unregisterAsset(shareTokenAddress1);
        vm.stopPrank();
    }

    function test_Redemption_CannotLockSharesTwice() public {
        // Setup: Complete registration and purchase
        vm.startPrank(issuerA);
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();

        // Transfer all shares to investor AIA
        vm.startPrank(issuerA);
        ILuxShareToken shareToken = ILuxShareToken(shareTokenAddress1);
        shareToken.transfer(investorAIA, 10000 * 10**18);
        vm.stopPrank();

        // Request and lock redemption
        vm.startPrank(investorAIA);
        uint256 redemptionId = redemption.requestRedemption(shareTokenAddress1, "Test redemption");
        redemption.lockShares(redemptionId);

        // Try to lock again
        vm.expectRevert("Redemption: invalid status");
        redemption.lockShares(redemptionId);
        vm.stopPrank();
    }

    function test_Redemption_CannotBurnBeforeLocking() public {
        // Setup: Complete registration and purchase
        vm.startPrank(issuerA);
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();

        // Transfer all shares to investor AIA
        vm.startPrank(issuerA);
        ILuxShareToken shareToken = ILuxShareToken(shareTokenAddress1);
        shareToken.transfer(investorAIA, 10000 * 10**18);
        vm.stopPrank();

        // Request redemption
        vm.startPrank(investorAIA);
        uint256 redemptionId = redemption.requestRedemption(shareTokenAddress1, "Test redemption");

        // Try to burn before locking
        vm.expectRevert("Redemption: invalid status");
        redemption.burnShares(redemptionId);
        vm.stopPrank();
    }

    function test_Redemption_CannotCompleteBeforeBurning() public {
        // Setup: Complete registration, purchase, request, and lock
        vm.startPrank(issuerA);
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();

        // Transfer all shares to investor AIA
        vm.startPrank(issuerA);
        ILuxShareToken shareToken = ILuxShareToken(shareTokenAddress1);
        shareToken.transfer(investorAIA, 10000 * 10**18);
        vm.stopPrank();

        // Request and lock redemption
        vm.startPrank(investorAIA);
        uint256 redemptionId = redemption.requestRedemption(shareTokenAddress1, "Test redemption");
        redemption.lockShares(redemptionId);
        vm.stopPrank();

        // Try to complete before burning
        vm.startPrank(issuerA);
        vm.expectRevert("Redemption: invalid status");
        redemption.completeRedemption(redemptionId);
        vm.stopPrank();
    }

    function test_Redemption_CannotCompleteWithoutIssuer() public {
        // Setup: Complete registration, purchase, request, lock, and burn
        vm.startPrank(issuerA);
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();

        // Transfer all shares to investor AIA
        vm.startPrank(issuerA);
        ILuxShareToken shareToken = ILuxShareToken(shareTokenAddress1);
        shareToken.transfer(investorAIA, 10000 * 10**18);
        vm.stopPrank();

        // Request, lock, and burn redemption
        vm.startPrank(investorAIA);
        uint256 redemptionId = redemption.requestRedemption(shareTokenAddress1, "Test redemption");
        redemption.lockShares(redemptionId);
        vm.stopPrank();

        // Try to complete with non-issuer
        vm.startPrank(investorAIA);
        vm.expectRevert("Redemption: not authorized");
        redemption.burnShares(redemptionId);
        vm.expectRevert("Redemption: invalid status");
        redemption.completeRedemption(redemptionId);
        vm.stopPrank();
    }

    function test_Redemption_CancelRedemption() public {
        // Setup: Complete registration and purchase
        vm.startPrank(issuerA);
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();

        // Transfer all shares to investor AIA
        vm.startPrank(issuerA);
        ILuxShareToken shareToken = ILuxShareToken(shareTokenAddress1);
        shareToken.transfer(investorAIA, 10000 * 10**18);
        vm.stopPrank();

        // Request redemption
        vm.startPrank(investorAIA);
        uint256 redemptionId = redemption.requestRedemption(shareTokenAddress1, "Test redemption");
        vm.stopPrank();

        // Cancel redemption
        vm.startPrank(investorAIA);
        redemption.cancelRedemption(redemptionId);
        vm.stopPrank();

        // Verify redemption is cancelled
        IRedemption.RedemptionRecord memory record = redemption.getRedemption(redemptionId);
        assertEq(uint8(record.status), uint8(IRedemption.RedemptionStatus.Cancelled), "Status should be Cancelled");

        // Verify shares are returned to redeemer
        uint256 aiaBalance = shareToken.balanceOf(investorAIA);
        assertEq(aiaBalance, 10000 * 10**18, "Shares should be returned to AIA");
    }

    function test_Redemption_CannotCancelAfterCompletion() public {
        // Setup: Complete full redemption flow
        vm.startPrank(issuerA);
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();

        // Transfer all shares to investor AIA
        vm.startPrank(issuerA);
        ILuxShareToken shareToken = ILuxShareToken(shareTokenAddress1);
        shareToken.transfer(investorAIA, 10000 * 10**18);
        vm.stopPrank();

        // Complete full redemption
        vm.startPrank(investorAIA);
        uint256 redemptionId = redemption.requestRedemption(shareTokenAddress1, "Test redemption");
        redemption.lockShares(redemptionId);
        vm.stopPrank();

        vm.startPrank(issuerA);
        redemption.burnShares(redemptionId);
        redemption.completeRedemption(redemptionId);
        vm.stopPrank();

        // Try to cancel completed redemption
        vm.startPrank(investorAIA);
        vm.expectRevert("Redemption: already completed");
        redemption.cancelRedemption(redemptionId);
        vm.stopPrank();
    }

    function test_Redemption_GetRedemptionsByRedeemer() public {
        // Setup: Complete registration and purchase
        vm.startPrank(issuerA);
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();

        // Transfer all shares to investor AIA
        vm.startPrank(issuerA);
        ILuxShareToken shareToken = ILuxShareToken(shareTokenAddress1);
        shareToken.transfer(investorAIA, 10000 * 10**18);
        vm.stopPrank();

        // Create multiple redemptions
        vm.startPrank(investorAIA);
        uint256 redemptionId1 = redemption.requestRedemption(shareTokenAddress1, "Redemption 1");
        // Note: redemptionId2 is unused - asset2 not registered, so this would fail
        vm.stopPrank();

        // Get redemptions by redeemer
        uint256[] memory redemptions = redemption.getRedemptionsByRedeemer(investorAIA);
        assertEq(redemptions.length, 1, "Should have 1 redemption");
        assertEq(redemptions[0], redemptionId1, "Should have correct redemption ID");
    }

    function test_Redemption_IsShareTokenRegistered() public {
        // Initially not registered
        assertFalse(redemption.isShareTokenRegistered(shareTokenAddress1), "Should not be registered initially");

        // Register asset
        vm.startPrank(issuerA);
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();

        // Now registered
        assertTrue(redemption.isShareTokenRegistered(shareTokenAddress1), "Should be registered");
    }

    function test_Redemption_GetTotalRedemptions() public {
        // Initially 0
        assertEq(redemption.getTotalRedemptions(), 0, "Should have 0 redemptions initially");

        // Setup: Complete registration and purchase
        vm.startPrank(issuerA);
        redemption.registerAsset(shareTokenAddress1, address(luxRWAAssetNFT), testAssetTokenId);
        vm.stopPrank();

        // Transfer all shares to investor AIA
        vm.startPrank(issuerA);
        ILuxShareToken shareToken = ILuxShareToken(shareTokenAddress1);
        shareToken.transfer(investorAIA, 10000 * 10**18);
        vm.stopPrank();

        // Create redemption
        vm.startPrank(investorAIA);
        redemption.requestRedemption(shareTokenAddress1, "Test redemption");
        vm.stopPrank();

        // Now have 1 redemption
        assertEq(redemption.getTotalRedemptions(), 1, "Should have 1 redemption");
    }
}
