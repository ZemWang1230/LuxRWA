// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./BaseFixture.sol";
import "../src/compliance/implementation/ModularCompliance.sol";
import "../src/compliance/modules/CountryAllowModule.sol";
import "../src/compliance/modules/CountryRestrictModule.sol";
import "../src/token/implementation/LuxShareToken.sol";
import "../src/token/storage/TokenStorage.sol";

contract ModularComplianceTest is BaseFixture {
    // Test contracts for this suite
    ModularCompliance public testCompliance;
    LuxShareToken public testToken;

    // Test token config
    TokenStorage.ShareTokenConfig public testTokenConfig;

    function setUp() public {
        // Setup base environment
        ONCHAINIDSetUp();
        IdentityRegistrySetUp();
        InvestorRegistrationSetUp();

        // Initialize test token config
        testTokenConfig = TokenStorage.ShareTokenConfig({
            name: "Test Token",
            symbol: "TEST",
            decimals: 18,
            initialSupply: 1000000 * 10**18,
            issuer: issuerA,
            shareClass: "Common",
            redeemable: true,
            compliance: address(0) // Will be set per test
        });
    }

    /**
     * @dev Setup factory environment for testing
     */
    function _setupFactoryEnvironment() internal {
        if (address(luxRWAFactory) == address(0)) {
            vm.startPrank(admin);
            // Deploy factory first
            luxRWAFactory = new LuxShareFactory();

            // Deploy a dummy compliance for initialization
            ModularCompliance dummyCompliance = new ModularCompliance();
            dummyCompliance.setFactory(address(luxRWAFactory)); // Set factory

            // Initialize factory with dummy compliance
            luxRWAFactory.initialize(address(identityRegistry), address(dummyCompliance));

            // Deploy AssetNFT
            address assetNFTAddress = luxRWAFactory.deployAssetNFT("Test Asset NFT", "TANFT");
            luxRWAAssetNFT = LuxAssetNFT(assetNFTAddress);
            vm.stopPrank();
        }
    }

    /**
     * @dev Helper function to create a test token with specific compliance
     */
    function _createTestToken(address complianceAddr) internal returns (LuxShareToken) {
        // Ensure factory environment is setup
        _setupFactoryEnvironment();

        // Create test asset metadata
        TokenStorage.AssetMetadata memory assetMetadata = TokenStorage.AssetMetadata({
            assetType: 99, // test asset
            brand: "Test Brand",
            model: "Test Model",
            serialHash: keccak256(abi.encodePacked("TEST001")),
            custodyInfo: "Test custody",
            appraisalHash: keccak256(abi.encodePacked("Test appraisal")),
            insuranceHash: keccak256(abi.encodePacked("Test insurance")),
            nfcTagHash: keccak256(abi.encodePacked("Test NFC")),
            appraisalAuthority: issuerA,
            metadataURI: "ipfs://test",
            timestamp: block.timestamp,
            verified: true
        });

        // Update token config with compliance
        TokenStorage.ShareTokenConfig memory tokenConfig = testTokenConfig;
        tokenConfig.compliance = complianceAddr;

        // Mint asset NFT
        vm.startPrank(admin);
        uint256 tokenId = luxRWAFactory.mintAssetNFT(address(luxRWAAssetNFT), issuerA, assetMetadata);
        luxRWAFactory.verifyAssetNFT(address(luxRWAAssetNFT), tokenId);

        // Create share token through factory
        address tokenAddr = luxRWAFactory.createShareToken(address(luxRWAAssetNFT), tokenId, tokenConfig);
        vm.stopPrank();

        testToken = LuxShareToken(tokenAddr);
        return testToken;
    }

    /**
     * @dev Test module removal and addition
     */
    function test_ModuleManagement() public {
        vm.startPrank(admin);
        testCompliance = new ModularCompliance();
        CountryAllowModule countryAllowModule = new CountryAllowModule();

        // Add module
        testCompliance.addModule(address(countryAllowModule));
        address[] memory modules = testCompliance.getModules();
        assertEq(modules.length, 1);
        assertEq(modules[0], address(countryAllowModule));

        // Try to add same module again - should fail
        vm.expectRevert("ModularCompliance: module already bound");
        testCompliance.addModule(address(countryAllowModule));

        // Remove module
        testCompliance.removeModule(address(countryAllowModule));
        modules = testCompliance.getModules();
        assertEq(modules.length, 0);

        // Try to remove non-existent module - should fail
        vm.expectRevert("ModularCompliance: module not bound");
        testCompliance.removeModule(address(countryAllowModule));

        vm.stopPrank();

        console.log("Module Management tests passed!");
    }

    /**
     * @dev Test multiple modules working together
     * Test combining CountryAllowModule and CountryRestrictModule
     */
    function test_MultipleModulesCombination() public {
        // First setup the factory environment
        _setupFactoryEnvironment();

        // Deploy compliance and modules
        vm.startPrank(admin);
        testCompliance = new ModularCompliance();
        CountryAllowModule countryAllowModule = new CountryAllowModule();
        CountryRestrictModule countryRestrictModule = new CountryRestrictModule();

        // Set factory for compliance before using it
        testCompliance.setFactory(address(luxRWAFactory));

        // Add both modules to compliance
        testCompliance.addModule(address(countryAllowModule));
        testCompliance.addModule(address(countryRestrictModule));

        // Configure CountryAllowModule: only allow US (840)
        uint16[] memory allowedCountries = new uint16[](1);
        allowedCountries[0] = 840; // US
        bytes memory allowCallData = abi.encodeWithSelector(
            CountryAllowModule.batchAllowCountries.selector,
            allowedCountries
        );
        testCompliance.callModuleFunction(allowCallData, address(countryAllowModule));

        // Configure CountryRestrictModule: restrict US (840) - this should override allow
        uint16[] memory restrictedCountries = new uint16[](1);
        restrictedCountries[0] = 840; // US
        bytes memory restrictCallData = abi.encodeWithSelector(
            CountryRestrictModule.batchRestrictCountries.selector,
            restrictedCountries
        );
        testCompliance.callModuleFunction(restrictCallData, address(countryRestrictModule));
        vm.stopPrank();

        // Create token with this compliance
        testToken = _createTestToken(address(testCompliance));

        console.log("Testing Multiple Modules Combination...");

        // Test: Even though US is allowed by CountryAllowModule, it's restricted by CountryRestrictModule
        // So US investor should NOT be able to receive tokens
        vm.startPrank(issuerA);
        vm.expectRevert("LuxShareToken: transfer not compliant");
        testToken.transfer(investorAIA, 1000 * 10**18);
        vm.stopPrank();
        assertEq(testToken.balanceOf(investorAIA), 0);

        // Test: Remove US from restricted list, now it should work (allowed by first module)
        vm.startPrank(admin);
        uint16[] memory unrestrictedCountries = new uint16[](1);
        unrestrictedCountries[0] = 840; // US
        bytes memory unrestrictCallData = abi.encodeWithSelector(
            CountryRestrictModule.batchUnrestrictCountries.selector,
            unrestrictedCountries
        );
        testCompliance.callModuleFunction(unrestrictCallData, address(countryRestrictModule));
        vm.stopPrank();

        // Now US investor should be able to receive tokens
        vm.startPrank(issuerA);
        testToken.transfer(investorAIA, 1000 * 10**18);
        vm.stopPrank();
        assertEq(testToken.balanceOf(investorAIA), 1000 * 10**18);

        console.log("Multiple Modules Combination tests passed!");
    }

    /**
     * @dev Test CountryAllowModule functionality
     * Module allows only specific countries to hold/receive tokens (whitelist approach)
     */
    function test_CountryAllowModule() public {
        // First setup the factory environment
        _setupFactoryEnvironment();

        // Deploy compliance and module
        vm.startPrank(admin);
        testCompliance = new ModularCompliance();
        CountryAllowModule countryAllowModule = new CountryAllowModule();

        // Set factory for compliance before using it
        testCompliance.setFactory(address(luxRWAFactory));

        // Add module to compliance
        testCompliance.addModule(address(countryAllowModule));

        // Configure module to only allow US (country code 840)
        uint16[] memory allowedCountries = new uint16[](1);
        allowedCountries[0] = 840; // US
        bytes memory callData = abi.encodeWithSelector(
            CountryAllowModule.batchAllowCountries.selector,
            allowedCountries
        );
        testCompliance.callModuleFunction(callData, address(countryAllowModule));
        vm.stopPrank();

        // Create token with this compliance
        testToken = _createTestToken(address(testCompliance));

        console.log("Testing CountryAllowModule...");

        // Test 1: US investor (AIA) should be able to receive tokens
        vm.startPrank(issuerA);
        testToken.transfer(investorAIA, 1000 * 10**18);
        vm.stopPrank();
        assertEq(testToken.balanceOf(investorAIA), 1000 * 10**18);

        // Test 2: China investor (AIC) should NOT be able to receive tokens
        vm.startPrank(issuerA);
        vm.expectRevert("LuxShareToken: transfer not compliant");
        testToken.transfer(investorAIC, 1000 * 10**18);
        vm.stopPrank();
        assertEq(testToken.balanceOf(investorAIC), 0);

        // Test 3: Add China to allowed countries
        vm.startPrank(admin);
        uint16[] memory newAllowedCountries = new uint16[](1);
        newAllowedCountries[0] = 156; // China
        callData = abi.encodeWithSelector(
            CountryAllowModule.batchAllowCountries.selector,
            newAllowedCountries
        );
        testCompliance.callModuleFunction(callData, address(countryAllowModule));
        vm.stopPrank();

        // Now China investor should be able to receive tokens
        vm.startPrank(issuerA);
        testToken.transfer(investorAIC, 1000 * 10**18);
        vm.stopPrank();
        assertEq(testToken.balanceOf(investorAIC), 1000 * 10**18);

        console.log("CountryAllowModule tests passed!");
    }

    /**
     * @dev Test CountryRestrictModule functionality
     * Module restricts specific countries from holding/receiving tokens (blacklist approach)
     */
    function test_CountryRestrictModule() public {
        // First setup the factory environment
        _setupFactoryEnvironment();

        // Deploy compliance and module
        vm.startPrank(admin);
        testCompliance = new ModularCompliance();
        CountryRestrictModule countryRestrictModule = new CountryRestrictModule();

        // Set factory for compliance before using it
        testCompliance.setFactory(address(luxRWAFactory));

        // Add module to compliance
        testCompliance.addModule(address(countryRestrictModule));

        // Configure module to restrict China (country code 156)
        uint16[] memory restrictedCountries = new uint16[](1);
        restrictedCountries[0] = 156; // China
        bytes memory callData = abi.encodeWithSelector(
            CountryRestrictModule.batchRestrictCountries.selector,
            restrictedCountries
        );
        testCompliance.callModuleFunction(callData, address(countryRestrictModule));
        vm.stopPrank();

        // Create token with this compliance
        testToken = _createTestToken(address(testCompliance));

        console.log("Testing CountryRestrictModule...");

        // Test 1: US investor (AIA) should be able to receive tokens (not restricted)
        vm.startPrank(issuerA);
        testToken.transfer(investorAIA, 1000 * 10**18);
        vm.stopPrank();
        assertEq(testToken.balanceOf(investorAIA), 1000 * 10**18);

        // Test 2: China investor (AIC) should NOT be able to receive tokens (restricted)
        vm.startPrank(issuerA);
        vm.expectRevert("LuxShareToken: transfer not compliant");
        testToken.transfer(investorAIC, 1000 * 10**18);
        vm.stopPrank();
        assertEq(testToken.balanceOf(investorAIC), 0);

        // Test 3: Remove China from restricted countries
        vm.startPrank(admin);
        uint16[] memory unrestrictedCountries = new uint16[](1);
        unrestrictedCountries[0] = 156; // China
        callData = abi.encodeWithSelector(
            CountryRestrictModule.batchUnrestrictCountries.selector,
            unrestrictedCountries
        );
        testCompliance.callModuleFunction(callData, address(countryRestrictModule));
        vm.stopPrank();

        // Now China investor should be able to receive tokens
        vm.startPrank(issuerA);
        testToken.transfer(investorAIC, 1000 * 10**18);
        vm.stopPrank();
        assertEq(testToken.balanceOf(investorAIC), 1000 * 10**18);

        console.log("CountryRestrictModule tests passed!");
    }
}
