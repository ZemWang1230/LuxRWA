// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./BaseFixture.sol";
import "../src/token/implementation/LuxAssetNFT.sol";
import "../src/compliance/implementation/ModularCompliance.sol";
import "../src/compliance/modules/CountryAllowModule.sol";
import "../src/token/implementation/LuxShareFactory.sol";
import "../src/token/storage/TokenStorage.sol";

contract LuxRWATokenTest is BaseFixture {
    // Test contracts
    LuxShareFactory public factory;
    LuxAssetNFT public assetNFT;
    ModularCompliance public compliance;
    CountryAllowModule public countryAllowModule;

    // Test asset data
    TokenStorage.AssetMetadata public testAssetMetadata;
    TokenStorage.ShareTokenConfig public testShareConfig;

    function setUp() public {
        // Setup base environment
        ONCHAINIDSetUp();
        IdentityRegistrySetUp();
        InvestorRegistrationSetUp();

        // Setup test environment
        _setupTestEnvironment();
    }

    function _setupTestEnvironment() internal {
        // Deploy compliance and modules
        vm.startPrank(admin);
        compliance = new ModularCompliance();
        countryAllowModule = new CountryAllowModule();

        // Bind country allow module to compliance (only allow US - country code 840)
        compliance.addModule(address(countryAllowModule));

        // Use callModuleFunction to configure the module
        uint16[] memory allowedCountries = new uint16[](1);
        allowedCountries[0] = 840; // US country code
        bytes memory callData = abi.encodeWithSelector(
            CountryAllowModule.batchAllowCountries.selector,
            allowedCountries
        );
        compliance.callModuleFunction(callData, address(countryAllowModule));

        // Deploy factory
        factory = new LuxShareFactory();
        factory.initialize(address(identityRegistry), address(compliance));

        // Set factory address in compliance contract
        compliance.setFactory(address(factory));

        // Deploy AssetNFT
        address assetNFTAddress = factory.deployAssetNFT("Luxury Asset NFT", "LANFT");
        assetNFT = LuxAssetNFT(assetNFTAddress);
        vm.stopPrank();

        // Setup test asset metadata
        testAssetMetadata = TokenStorage.AssetMetadata({
            assetType: 1, // watch
            brand: "Rolex",
            model: "Submariner",
            serialHash: keccak256(abi.encodePacked("RLX001")),
            custodyInfo: "Secure vault in Zurich",
            appraisalHash: keccak256(abi.encodePacked("AppraisalCert001")),
            insuranceHash: keccak256(abi.encodePacked("InsuranceCert001")),
            nfcTagHash: keccak256(abi.encodePacked("NFCTag001")),
            appraisalAuthority: issuerA,
            metadataURI: "ipfs://QmTestAsset001",
            timestamp: block.timestamp,
            verified: true
        });

        // Setup test share token config
        testShareConfig = TokenStorage.ShareTokenConfig({
            name: "Rolex Submariner Share",
            symbol: "RLXSHARE",
            decimals: 18,
            initialSupply: 10000 * 10**18, // 10,000 shares
            issuer: issuerA, // issuer address, not identity contract
            shareClass: "Common",
            redeemable: true,
            compliance: address(compliance)
        });
    }

    function test_AssetNFT_Mint_Freeze_Unfreeze() public {
        // Admin mints an asset NFT for issuer A
        vm.startPrank(admin);
        uint256 tokenId = factory.mintAssetNFT(address(assetNFT), issuerA, testAssetMetadata);
        vm.stopPrank();

        // Verify NFT was minted correctly
        assertEq(assetNFT.ownerOf(tokenId), identityIssuerA);
        assertEq(assetNFT.balanceOf(issuerA), 1);

        // Verify asset is not verified initially
        assertFalse(assetNFT.isVerified(tokenId));
        vm.startPrank(admin);
        factory.verifyAssetNFT(address(assetNFT), tokenId);
        vm.stopPrank();
        assertTrue(assetNFT.isVerified(tokenId));

        // Check asset metadata
        TokenStorage.AssetMetadata memory metadata = assetNFT.getAssetMetadata(tokenId);

        assertEq(metadata.assetType, testAssetMetadata.assetType);
        assertEq(metadata.brand, testAssetMetadata.brand);
        assertEq(metadata.model, testAssetMetadata.model);

        // Verify token is not frozen initially
        assertFalse(assetNFT.isFrozen(tokenId));

        // Test freeze function
        vm.startPrank(admin);
        factory.freezeAssetNFT(address(assetNFT), tokenId);
        vm.stopPrank();

        // Verify token is frozen
        assertTrue(assetNFT.isFrozen(tokenId));

        // Test unfreeze function
        vm.startPrank(admin);
        factory.unfreezeAssetNFT(address(assetNFT), tokenId);
        vm.stopPrank();

        // Verify token is unfrozen
        assertFalse(assetNFT.isFrozen(tokenId));

        // Test double freeze should fail
        vm.startPrank(admin);
        factory.freezeAssetNFT(address(assetNFT), tokenId);
        vm.expectRevert("LuxAssetNFT: token already frozen");
        factory.freezeAssetNFT(address(assetNFT), tokenId);
        vm.stopPrank();

        // Test double unfreeze should fail
        vm.startPrank(admin);
        factory.unfreezeAssetNFT(address(assetNFT), tokenId);
        vm.expectRevert("LuxAssetNFT: token not frozen");
        factory.unfreezeAssetNFT(address(assetNFT), tokenId);
        vm.stopPrank();

        // Test freeze/unfreeze non-existent token should fail
        vm.startPrank(admin);
        vm.expectRevert("LuxAssetNFT: token does not exist");
        factory.freezeAssetNFT(address(assetNFT), tokenId + 1);
        vm.stopPrank();

        console.log("Asset NFT mint, freeze, and unfreeze tests passed!");
    }

    function test_ShareToken_Creation_And_Transfers() public {
        // First, admin mints an asset NFT for issuer A
        vm.startPrank(admin);
        uint256 tokenId = factory.mintAssetNFT(address(assetNFT), issuerA, testAssetMetadata);
        factory.verifyAssetNFT(address(assetNFT), tokenId);
        vm.stopPrank();

        // Verify NFT was minted
        assertEq(assetNFT.ownerOf(tokenId), identityIssuerA);
        // Admin creates share token for the asset
        vm.startPrank(admin);
        address shareTokenAddress = factory.createShareToken(address(assetNFT), tokenId, testShareConfig);
        vm.stopPrank();

        // Get the share token contract
        LuxShareToken shareToken = LuxShareToken(shareTokenAddress);

        // Verify share token was created and configured correctly
        assertEq(shareToken.totalSupply(), testShareConfig.initialSupply);
        assertEq(shareToken.balanceOf(issuerA), testShareConfig.initialSupply);

        // Verify asset-token binding
        (address underlyingAsset, uint256 assetId) = shareToken.getUnderlyingAsset();
        assertEq(underlyingAsset, address(assetNFT));
        assertEq(assetId, tokenId);

        // Verify NFT has share token binding
        address boundShareToken = assetNFT.getShareToken(tokenId);
        assertEq(boundShareToken, shareTokenAddress);

        console.log("Share token created and bound successfully!");

        // Now test transfers to investors
        uint256 transferAmount = 1000 * 10**18; // 1000 shares each

        // Transfer to AIA (should succeed - US investor with KYC + AML)
        vm.startPrank(issuerA);
        // We need to use the investorAIA address here, not the identityIssuerA address
        shareToken.transfer(investorAIA, transferAmount);
        vm.stopPrank();
        // token is transferred to identityAIA, not investorAIA
        assertEq(shareToken.balanceOf(investorAIA), transferAmount);

        // Transfer to AIB (should succeed - US investor with KYC + AML)
        vm.startPrank(issuerA);
        shareToken.transfer(investorAIB, transferAmount);
        vm.stopPrank();
        assertEq(shareToken.balanceOf(investorAIB), transferAmount);

        // Transfer to AIC (should fail - China investor, not allowed by country module)
        vm.startPrank(issuerA);
        vm.expectRevert("LuxShareToken: transfer not compliant");
        shareToken.transfer(investorAIC, transferAmount);
        vm.stopPrank();
        assertEq(shareToken.balanceOf(investorAIC), 0);

        // Transfer to AID (should fail - US investor but only KYC, no AML, not verified)
        vm.startPrank(issuerA);
        vm.expectRevert("LuxShareToken: recipient not verified");
        shareToken.transfer(investorAID, transferAmount);
        vm.stopPrank();
        assertEq(shareToken.balanceOf(investorAID), 0);

        console.log("Share token transfers tested successfully!");
    }

    function test_Additional_ShareToken_Features() public {
        // Setup: Create asset NFT and share token first
        vm.startPrank(admin);
        uint256 tokenId = factory.mintAssetNFT(address(assetNFT), issuerA, testAssetMetadata);
        factory.verifyAssetNFT(address(assetNFT), tokenId);
        address shareTokenAddress = factory.createShareToken(address(assetNFT), tokenId, testShareConfig);
        vm.stopPrank();

        LuxShareToken shareToken = LuxShareToken(shareTokenAddress);

        // Test pause functionality
        console.log("Testing pause functionality...");

        // Initially not paused
        assertFalse(shareToken.paused());

        // Transfer should work when not paused
        // AIA=100, AIB=0
        vm.startPrank(issuerA);
        shareToken.transfer(investorAIA, 100 * 10**18);
        vm.stopPrank();
        assertEq(shareToken.balanceOf(investorAIA), 100 * 10**18);

        // Pause the token
        vm.startPrank(admin);
        factory.pauseShareToken(shareTokenAddress);
        vm.stopPrank();
        assertTrue(shareToken.paused());

        // Transfer should fail when paused
        // AIA=100, AIB=0
        vm.startPrank(issuerA);
        vm.expectRevert("LuxShareToken: token is paused");
        shareToken.transfer(investorAIB, 100 * 10**18);
        vm.stopPrank();

        // Unpause the token
        vm.startPrank(admin);
        factory.unpauseShareToken(shareTokenAddress);
        vm.stopPrank();
        assertFalse(shareToken.paused());

        // Transfer should work again
        // AIA=100, AIB=100
        vm.startPrank(issuerA);
        shareToken.transfer(investorAIB, 100 * 10**18);
        vm.stopPrank();
        assertEq(shareToken.balanceOf(investorAIB), 100 * 10**18);

        console.log("Pause functionality tested successfully!");

        // Test address freezing
        console.log("Testing address freezing...");

        // Freeze AIA's address
        vm.startPrank(admin);
        factory.freezeAddress(shareTokenAddress, investorAIA);
        vm.stopPrank();

        // Transfer from frozen address should fail
        // AIA=100, AIB=100
        vm.startPrank(investorAIA);
        vm.expectRevert("LuxShareToken: sender is frozen");
        shareToken.transfer(investorAIB, 50 * 10**18);
        vm.stopPrank();

        // Unfreeze AIA's address
        vm.startPrank(admin);
        factory.unfreezeAddress(shareTokenAddress, investorAIA);
        vm.stopPrank();

        // Transfer should work again
        // AIA=50, AIB=150
        vm.startPrank(investorAIA);
        shareToken.transfer(investorAIB, 50 * 10**18);
        vm.stopPrank();
        assertEq(shareToken.balanceOf(investorAIA), 50 * 10**18);
        assertEq(shareToken.balanceOf(investorAIB), 150 * 10**18);

        console.log("Address freezing tested successfully!");

        // Test partial token freezing
        console.log("Testing partial token freezing...");

        uint256 freezeAmount = 2 * 10**18;
        vm.startPrank(admin);
        // AIA=50(2 frozen), AIB=150
        factory.freezePartialTokens(shareTokenAddress, investorAIA, freezeAmount);
        vm.stopPrank();

        // Check frozen tokens
        assertEq(shareToken.getFrozenTokens(investorAIA), freezeAmount);

        // Transfer more than available (considering frozen tokens) should fail
        // AIA=50(2 frozen), AIB=150
        uint256 availableBalance = shareToken.balanceOf(investorAIA) - freezeAmount;
        vm.startPrank(investorAIA);
        vm.expectRevert("LuxShareToken: transfer amount exceeds available balance");
        shareToken.transfer(investorAIB, availableBalance + 1);
        vm.stopPrank();

        // Transfer within available balance should work
        // AIA=24(2 frozen), AIB=174
        vm.startPrank(investorAIA);
        shareToken.transfer(investorAIB, availableBalance / 2);
        vm.stopPrank();
        assertEq(shareToken.balanceOf(investorAIA), 26 * 10**18); // 24 + 2
        assertEq(shareToken.balanceOf(investorAIB), 174 * 10**18); // 150 + 24

        // Unfreeze partial tokens
        // AIA=26, AIB=174
        vm.startPrank(admin);
        factory.unfreezePartialTokens(shareTokenAddress, investorAIA, freezeAmount);
        vm.stopPrank();
        assertEq(shareToken.getFrozenTokens(investorAIA), 0);

        console.log("Partial token freezing tested successfully!");

        // Test forced transfer
        console.log("Testing forced transfer...");

        // Give some tokens to AIA first
        // AIA=126, AIB=174
        vm.startPrank(issuerA);
        shareToken.transfer(investorAIA, 100 * 10**18);
        vm.stopPrank();

        // Force transfer from AIA to issuer (even if frozen)
        vm.startPrank(admin);
        factory.freezeAddress(shareTokenAddress, investorAIA); // Freeze AIA
        factory.forcedTransfer(shareTokenAddress, investorAIA, investorAIB, 100 * 10**18);
        factory.unfreezeAddress(shareTokenAddress, investorAIA);
        vm.stopPrank();
        assertEq(shareToken.balanceOf(investorAIA), 26 * 10**18); // 126 - 100
        assertEq(shareToken.balanceOf(investorAIB), 274 * 10**18); // 174 + 100

        console.log("Forced transfer tested successfully!");

        // Test approvals
        console.log("Testing approvals...");

        // Approve AIB to spend on behalf of AIA
        // AIA=26, AIB=274
        vm.startPrank(investorAIA);
        shareToken.approve(investorAIB, 10 * 10**18);
        vm.stopPrank();

        assertEq(shareToken.allowance(investorAIA, investorAIB), 10 * 10**18);

        // AIB transfers from AIA using transferFrom
        vm.startPrank(investorAIB);
        shareToken.transferFrom(investorAIA, investorAIB, 5 * 10**18);
        vm.stopPrank();

        assertEq(shareToken.balanceOf(investorAIA), 21 * 10**18); // 26 - 5
        assertEq(shareToken.balanceOf(investorAIB), 279 * 10**18); // 274 + 5
        assertEq(shareToken.allowance(investorAIA, investorAIB), 5 * 10**18); // 10 - 5

        console.log("Approvals tested successfully!");
        console.log("All additional share token features tested!");
    }

    function test_ShareToken_Multiple_Tokens() public {
        // Setup: Create asset NFT and share token first
        vm.startPrank(admin);

        // Deploy compliance2
        ModularCompliance compliance2 = new ModularCompliance();
        compliance2.setFactory(address(factory));

        TokenStorage.AssetMetadata memory tAMetadata2 = TokenStorage.AssetMetadata({
            assetType: 2, // jewelry
            brand: "Cartier",
            model: "Santos",
            serialHash: keccak256(abi.encodePacked("CTS001")),
            custodyInfo: "Secure vault in Paris",
            appraisalHash: keccak256(abi.encodePacked("AppraisalCert002")),
            insuranceHash: keccak256(abi.encodePacked("InsuranceCert002")),
            nfcTagHash: keccak256(abi.encodePacked("NFCTag002")),
            appraisalAuthority: issuerA,
            metadataURI: "ipfs://QmTestAsset002",
            timestamp: block.timestamp,
            verified: true
        });

        TokenStorage.ShareTokenConfig memory tShareConfig2 = TokenStorage.ShareTokenConfig({
            name: "Cartier Santos Share",
            symbol: "CTSSHARE",
            decimals: 18,
            initialSupply: 10000 * 10**18, // 10,000 shares
            issuer: issuerA, // issuer address, not identity contract
            shareClass: "Common",
            redeemable: true,
            compliance: address(compliance2)
        });
        
        uint256 tokenId = factory.mintAssetNFT(address(assetNFT), issuerA, testAssetMetadata);
        factory.verifyAssetNFT(address(assetNFT), tokenId);
        address shareTokenAddress = factory.createShareToken(address(assetNFT), tokenId, testShareConfig);
        uint256 tokenId2 = factory.mintAssetNFT(address(assetNFT), issuerA, tAMetadata2);
        factory.verifyAssetNFT(address(assetNFT), tokenId2);
        address shareTokenAddress2 = factory.createShareToken(address(assetNFT), tokenId2, tShareConfig2);
        vm.stopPrank();

        LuxShareToken shareToken = LuxShareToken(shareTokenAddress);
        LuxShareToken shareToken2 = LuxShareToken(shareTokenAddress2);
        assertEq(address(shareToken.compliance()), address(compliance));
        assertEq(address(shareToken2.compliance()), address(compliance2));
    }
}