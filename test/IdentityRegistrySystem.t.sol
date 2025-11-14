// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/factory/IdentityFactory.sol";
import "../src/identity/implementation/InvestorIdentity.sol";
import "../src/identity/implementation/ClaimIssuer.sol";
import "../src/identity/storage/IdentityStorage.sol";
import "../src/registry/implementation/ClaimTopicsRegistry.sol";
import "../src/registry/implementation/TrustedIssuersRegistry.sol";
import "../src/registry/implementation/IdentityRegistryStorage.sol";
import "../src/registry/implementation/IdentityRegistry.sol";

contract IdentityRegistrySystemTest is Test {
    // ============ Test Accounts ============
    address public admin; // System administrator
    address public issuerA; // Issuer A (trusted)
    address public issuerB; // Issuer B (not trusted)
    address public investorAIA; // Investor's investor AIA (has KYC + AML)
    address public investorAIB; // Investor's investor AIB (has only KYC)
    address public investorBIA; // Issuer B's investor BIA (has KYC + AML but issuer not trusted)

    // Private keys for signing
    uint256 public adminKey;
    uint256 public issuerAKey;
    uint256 public issuerBKey;
    uint256 public investorAIAKey;
    uint256 public investorAIBKey;
    uint256 public investorBIAKey;

    // ============ Identity Contracts ============
    IdentityFactory public factoryA;
    IdentityFactory public factoryB;

    // Issuer A and their identities
    address payable public identityIssuerA; // Issuer A's identity
    address payable public identityAIA; // Investor AIA's identity
    address payable public identityAIB; // Investor AIB's identity

    // Issuer B and their identities
    address payable public identityIssuerB; // Issuer B's identity
    address payable public identityBIA; // Investor BIA's identity

    // ============ Registry System ============
    ClaimTopicsRegistry public claimTopicsRegistry;
    TrustedIssuersRegistry public trustedIssuersRegistry;
    IdentityRegistryStorage public identityRegistryStorage;
    IdentityRegistry public identityRegistry;

    function setUp() public {
        // Setup accounts with private keys
        adminKey = 0xADAD;
        issuerAKey = 0xAAAA;
        issuerBKey = 0xBBBB;
        investorAIAKey = 0xA1A1;
        investorAIBKey = 0xA1B1;
        investorBIAKey = 0xB1A1;

        admin = vm.addr(adminKey);
        issuerA = vm.addr(issuerAKey);
        issuerB = vm.addr(issuerBKey);
        investorAIA = vm.addr(investorAIAKey);
        investorAIB = vm.addr(investorAIBKey);
        investorBIA = vm.addr(investorBIAKey);

        // Label addresses for better trace output
        vm.label(admin, "Admin");
        vm.label(issuerA, "IssuerA");
        vm.label(issuerB, "IssuerB");
        vm.label(investorAIA, "InvestorAIA");
        vm.label(investorAIB, "InvestorAIB");
        vm.label(investorBIA, "InvestorBIA");
    }

    // ============ Complete Workflow Test ============
    function test_CompleteIdentityRegistryWorkflow() public {
        console.log("=== Starting Complete Identity Registry Workflow ===");

        // ============ Phase 1: External Identity Creation ============
        console.log("\n=== Phase 1: External Identity Creation ===");

        // Step 1: Issuer A creates factory and identities
        console.log("Step 1: Issuer A creates factory and identities");
        vm.startPrank(issuerA);
        factoryA = new IdentityFactory();

        // Issuer A creates identity for themselves (ClaimIssuer type)
        identityIssuerA = payable(factoryA.createIssuerIdentity(issuerA, "Issuer A"));

        // Issuer A creates identities for their investors
        identityAIA = payable(factoryA.createInvestorIdentity(investorAIA, "Investor AIA"));
        identityAIB = payable(factoryA.createInvestorIdentity(investorAIB, "Investor AIB"));
        vm.stopPrank();

        console.log("Issuer A created identities for self and investors");

        // Step 2: Issuer A sets up CLAIM purpose for themselves
        vm.startPrank(issuerA);
        ClaimIssuer(identityIssuerA).addKey(
            keccak256(abi.encodePacked(issuerA)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();
        console.log("Issuer A set up CLAIM purpose");

        // Step 3: Investors grant CLAIM permissions to Issuer A
        vm.startPrank(investorAIA);
        InvestorIdentity(identityAIA).addKey(
            keccak256(abi.encodePacked(identityIssuerA)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();

        vm.startPrank(investorAIB);
        InvestorIdentity(identityAIB).addKey(
            keccak256(abi.encodePacked(identityIssuerA)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();
        console.log("Investors AIA and AIB granted CLAIM permissions to Issuer A");

        // Step 4: Issuer A issues claims
        // AIA gets both KYC and AML
        _issueClaimToIdentity(identityIssuerA, identityAIA, IdentityStorage.KYC_CLAIM, "KYC data for AIA", issuerAKey);
        _issueClaimToIdentity(identityIssuerA, identityAIA, IdentityStorage.AML_CLAIM, "AML data for AIA", issuerAKey);
        console.log("Issuer A issued KYC and AML claims to AIA");

        // AIB gets only KYC
        _issueClaimToIdentity(identityIssuerA, identityAIB, IdentityStorage.KYC_CLAIM, "KYC data for AIB", issuerAKey);
        console.log("Issuer A issued KYC claim to AIB (no AML)");

        // Step 5: Issuer B creates factory and identities
        vm.startPrank(issuerB);
        factoryB = new IdentityFactory();

        // Issuer B creates identity for themselves (ClaimIssuer type)
        identityIssuerB = payable(factoryB.createIssuerIdentity(issuerB, "Issuer B"));

        // Issuer B creates identity for their investor
        identityBIA = payable(factoryB.createInvestorIdentity(investorBIA, "Investor BIA"));
        vm.stopPrank();
        console.log("Issuer B created factory and identities");

        // Step 6: Issuer B sets up CLAIM purpose and issues claims to BIA (both KYC and AML)
        vm.startPrank(issuerB);
        ClaimIssuer(identityIssuerB).addKey(
            keccak256(abi.encodePacked(issuerB)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );

        // BIA grants permission to Issuer B
        vm.stopPrank();
        vm.startPrank(investorBIA);
        InvestorIdentity(identityBIA).addKey(
            keccak256(abi.encodePacked(identityIssuerB)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();

        // Issuer B issues both KYC and AML to BIA
        _issueClaimToIdentity(identityIssuerB, identityBIA, IdentityStorage.KYC_CLAIM, "KYC data for BIA", issuerBKey);
        _issueClaimToIdentity(identityIssuerB, identityBIA, IdentityStorage.AML_CLAIM, "AML data for BIA", issuerBKey);
        console.log("Issuer B issued KYC and AML claims to BIA");

        // ============ Phase 2: Registry System Deployment ============
        console.log("\n=== Phase 2: Registry System Deployment ===");

        // Step 7: Admin deploys registry system
        vm.startPrank(admin);
        claimTopicsRegistry = new ClaimTopicsRegistry();
        trustedIssuersRegistry = new TrustedIssuersRegistry();
        identityRegistryStorage = new IdentityRegistryStorage();
        identityRegistry = new IdentityRegistry(
            address(trustedIssuersRegistry),
            address(claimTopicsRegistry),
            address(identityRegistryStorage)
        );

        // Bind the identity registry to storage
        identityRegistryStorage.bindIdentityRegistry(address(identityRegistry));
        vm.stopPrank();
        console.log("Admin deployed and configured registry system");

        // ============ Phase 3: System Configuration ============
        console.log("\n=== Phase 3: System Configuration ===");

        // Step 8: Admin adds required claim topics (KYC and AML)
        vm.startPrank(admin);
        claimTopicsRegistry.addClaimTopic(IdentityStorage.KYC_CLAIM);
        claimTopicsRegistry.addClaimTopic(IdentityStorage.AML_CLAIM);
        vm.stopPrank();
        console.log("Admin added KYC and AML claim topics");

        // Step 9: Admin adds trusted issuers (only Issuer A)
        vm.startPrank(admin);
        uint256[] memory claimTopicsA = new uint256[](2);
        claimTopicsA[0] = IdentityStorage.KYC_CLAIM;
        claimTopicsA[1] = IdentityStorage.AML_CLAIM;
        trustedIssuersRegistry.addTrustedIssuer(IClaimIssuer(identityIssuerA), claimTopicsA);
        vm.stopPrank();
        console.log("Admin added Issuer A as trusted issuer with KYC and AML topics");

        // Step 10: Admin binds Issuer A and adds as agent
        vm.startPrank(admin);
        identityRegistry.addAgent(issuerA);
        vm.stopPrank();
        console.log("Admin added Issuer A as agent");

        // ============ Phase 4: Investor Registration ============
        console.log("\n=== Phase 4: Investor Registration ===");

        // Step 11: Issuer A registers their investors
        vm.startPrank(issuerA);
        identityRegistry.registerIdentity(investorAIA, IIdentity(identityAIA), 840); // US country code
        identityRegistry.registerIdentity(investorAIB, IIdentity(identityAIB), 156); // China country code
        vm.stopPrank();
        console.log("Issuer A registered investors AIA and AIB");

        // ============ Phase 5: Verification Checks ============
        console.log("\n=== Phase 5: Verification Checks ===");

        // Step 12: Check verification status
        bool aiaVerified = identityRegistry.isVerified(investorAIA);
        bool aibVerified = identityRegistry.isVerified(investorAIB);

        console.log("AIA verified:", aiaVerified);
        console.log("AIB verified:", aibVerified);

        // AIA should be verified (has both KYC and AML from trusted issuer)
        assertTrue(aiaVerified, "AIA should be verified");

        // AIB should NOT be verified (only has KYC, missing AML)
        assertFalse(aibVerified, "AIB should not be verified");

        // ============ Phase 6: Untrusted Issuer Attempts ============
        console.log("\n=== Phase 6: Untrusted Issuer Attempts ===");

        // Step 13: Issuer B tries to register their investor (should fail)
        vm.startPrank(issuerB);
        vm.expectRevert("IdentityRegistry: caller is not an agent");
        identityRegistry.registerIdentity(investorBIA, IIdentity(identityBIA), 840);
        vm.stopPrank();
        console.log("Issuer B correctly failed to register investor (not an agent)");

        // Step 14: Even if somehow registered, BIA should not be verified
        // (Let's test this by having admin register BIA temporarily)
        vm.startPrank(admin);
        identityRegistry.registerIdentity(investorBIA, IIdentity(identityBIA), 840);
        vm.stopPrank();

        bool biaVerified = identityRegistry.isVerified(investorBIA);
        console.log("BIA verified (even with claims):", biaVerified);
        assertFalse(biaVerified, "BIA should not be verified (issuer not trusted)");

        console.log("\n=== Complete Workflow Test Passed ===");
    }

    // ============ Additional Function Tests ============
    function test_ClaimTopicsRegistryFunctions() public {
        vm.startPrank(admin);
        claimTopicsRegistry = new ClaimTopicsRegistry();

        // Test adding topics
        claimTopicsRegistry.addClaimTopic(1);
        claimTopicsRegistry.addClaimTopic(2);
        claimTopicsRegistry.addClaimTopic(3);

        uint256[] memory topics = claimTopicsRegistry.getClaimTopics();
        assertEq(topics.length, 3);
        assertEq(topics[0], 1);
        assertEq(topics[1], 2);
        assertEq(topics[2], 3);

        // Test removing topic
        claimTopicsRegistry.removeClaimTopic(2);
        topics = claimTopicsRegistry.getClaimTopics();
        assertEq(topics.length, 2);
        assertEq(topics[0], 1);
        assertEq(topics[1], 3);

        // Test adding more than 15 topics should fail
        for (uint256 i = 4; i <= 16; i++) {
            claimTopicsRegistry.addClaimTopic(i);
        }

        vm.expectRevert("ClaimTopicsRegistry: cannot add more than 15 topics");
        claimTopicsRegistry.addClaimTopic(17);
        vm.stopPrank();
    }

    function test_TrustedIssuersRegistryFunctions() public {
        vm.startPrank(admin);
        trustedIssuersRegistry = new TrustedIssuersRegistry();

        // Create mock issuer
        address mockIssuer = makeAddr("mockIssuer");
        uint256[] memory topics = new uint256[](2);
        topics[0] = 1;
        topics[1] = 2;

        // Test adding trusted issuer
        trustedIssuersRegistry.addTrustedIssuer(IClaimIssuer(mockIssuer), topics);

        // Test queries
        IClaimIssuer[] memory issuers = trustedIssuersRegistry.getTrustedIssuers();
        assertEq(issuers.length, 1);
        assertEq(address(issuers[0]), mockIssuer);

        IClaimIssuer[] memory issuersForTopic1 = trustedIssuersRegistry.getTrustedIssuersForClaimTopic(1);
        assertEq(issuersForTopic1.length, 1);
        assertEq(address(issuersForTopic1[0]), mockIssuer);

        assertTrue(trustedIssuersRegistry.isTrustedIssuer(mockIssuer));
        assertTrue(trustedIssuersRegistry.hasClaimTopic(mockIssuer, 1));
        assertTrue(trustedIssuersRegistry.hasClaimTopic(mockIssuer, 2));
        assertFalse(trustedIssuersRegistry.hasClaimTopic(mockIssuer, 3));

        uint256[] memory issuerTopics = trustedIssuersRegistry.getTrustedIssuerClaimTopics(IClaimIssuer(mockIssuer));
        assertEq(issuerTopics.length, 2);
        assertEq(issuerTopics[0], 1);
        assertEq(issuerTopics[1], 2);

        // Test removing issuer
        trustedIssuersRegistry.removeTrustedIssuer(IClaimIssuer(mockIssuer));
        assertFalse(trustedIssuersRegistry.isTrustedIssuer(mockIssuer));

        vm.stopPrank();
    }

    function test_IdentityRegistryStorageFunctions() public {
        vm.startPrank(admin);
        identityRegistryStorage = new IdentityRegistryStorage();

        // Create mock registry and bind it
        address mockRegistry = makeAddr("mockRegistry");
        identityRegistryStorage.bindIdentityRegistry(mockRegistry);

        vm.stopPrank();

        // Now use the mock registry to call storage functions
        vm.startPrank(mockRegistry);

        // Create mock identities
        address mockUser = makeAddr("mockUser");
        address mockIdentity = makeAddr("mockIdentity");

        // Test adding identity to storage
        identityRegistryStorage.addIdentityToStorage(mockUser, IIdentity(mockIdentity), 840);

        assertEq(address(identityRegistryStorage.storedIdentity(mockUser)), mockIdentity);
        assertEq(identityRegistryStorage.storedInvestorCountry(mockUser), 840);
        assertTrue(identityRegistryStorage.storedIdentity(mockUser) != IIdentity(address(0)));

        // Test modifying country
        identityRegistryStorage.modifyStoredInvestorCountry(mockUser, 826); // UK
        assertEq(identityRegistryStorage.storedInvestorCountry(mockUser), 826);

        vm.stopPrank();
    }

    function test_IdentityRegistryFunctions() public {
        // Setup registry system
        vm.startPrank(admin);
        claimTopicsRegistry = new ClaimTopicsRegistry();
        trustedIssuersRegistry = new TrustedIssuersRegistry();
        identityRegistryStorage = new IdentityRegistryStorage();
        identityRegistry = new IdentityRegistry(
            address(trustedIssuersRegistry),
            address(claimTopicsRegistry),
            address(identityRegistryStorage)
        );
        identityRegistryStorage.bindIdentityRegistry(address(identityRegistry));
        vm.stopPrank();

        // Create test identity
        address testUser = makeAddr("testUser");
        address testIdentity = makeAddr("testIdentity");

        // Add as agent and register
        vm.startPrank(admin);
        identityRegistry.addAgent(admin);
        identityRegistry.registerIdentity(testUser, IIdentity(testIdentity), 840);
        vm.stopPrank();

        // Test basic functions
        assertTrue(identityRegistry.contains(testUser));
        assertEq(address(identityRegistry.identity(testUser)), testIdentity);
        assertEq(identityRegistry.investorCountry(testUser), 840);

        // Test agent management
        assertTrue(identityRegistry.isAgent(admin));
        address newAgent = makeAddr("newAgent");
        vm.startPrank(admin);
        identityRegistry.addAgent(newAgent);
        assertTrue(identityRegistry.isAgent(newAgent));
        identityRegistry.removeAgent(newAgent);
        assertFalse(identityRegistry.isAgent(newAgent));
        vm.stopPrank();
    }

    function test_BatchRegistration() public {
        // Setup registry system
        vm.startPrank(admin);
        claimTopicsRegistry = new ClaimTopicsRegistry();
        trustedIssuersRegistry = new TrustedIssuersRegistry();
        identityRegistryStorage = new IdentityRegistryStorage();
        identityRegistry = new IdentityRegistry(
            address(trustedIssuersRegistry),
            address(claimTopicsRegistry),
            address(identityRegistryStorage)
        );
        identityRegistryStorage.bindIdentityRegistry(address(identityRegistry));
        identityRegistry.addAgent(admin);
        vm.stopPrank();

        // Create test data
        address[] memory users = new address[](3);
        IIdentity[] memory identities = new IIdentity[](3);
        uint16[] memory countries = new uint16[](3);

        for (uint256 i = 0; i < 3; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            identities[i] = IIdentity(makeAddr(string(abi.encodePacked("identity", i))));
            countries[i] = 840;
        }

        // Test batch registration (admin is already an agent from setup)
        vm.startPrank(admin);
        identityRegistry.batchRegisterIdentity(users, identities, countries);
        vm.stopPrank();

        // Verify all registrations
        for (uint256 i = 0; i < 3; i++) {
            assertTrue(identityRegistry.contains(users[i]));
            assertEq(address(identityRegistry.identity(users[i])), address(identities[i]));
            assertEq(identityRegistry.investorCountry(users[i]), countries[i]);
        }
    }

    function test_RegistryConfiguration() public {
        // Setup initial registry
        vm.startPrank(admin);
        claimTopicsRegistry = new ClaimTopicsRegistry();
        trustedIssuersRegistry = new TrustedIssuersRegistry();
        identityRegistryStorage = new IdentityRegistryStorage();
        identityRegistry = new IdentityRegistry(
            address(trustedIssuersRegistry),
            address(claimTopicsRegistry),
            address(identityRegistryStorage)
        );

        // Test setting new registries
        ClaimTopicsRegistry newTopicsRegistry = new ClaimTopicsRegistry();
        TrustedIssuersRegistry newIssuersRegistry = new TrustedIssuersRegistry();
        IdentityRegistryStorage newStorage = new IdentityRegistryStorage();

        identityRegistry.setClaimTopicsRegistry(address(newTopicsRegistry));
        identityRegistry.setTrustedIssuersRegistry(address(newIssuersRegistry));
        identityRegistry.setIdentityRegistryStorage(address(newStorage));

        assertEq(address(identityRegistry.topicsRegistry()), address(newTopicsRegistry));
        assertEq(address(identityRegistry.issuersRegistry()), address(newIssuersRegistry));
        assertEq(address(identityRegistry.identityStorage()), address(newStorage));

        vm.stopPrank();
    }

    // ============ Helper Functions ============
    function _issueClaim(
        address _issuerIdentity,
        address _targetIdentity,
        uint256 _topic,
        string memory _data,
        uint256 _issuerKey
    ) internal {
        bytes memory data = abi.encode(_data);
        bytes32 claimId = keccak256(abi.encodePacked(_issuerIdentity, _topic));
        bytes memory signature = _signClaim(_issuerKey, claimId, _topic, data);

        vm.prank(vm.addr(_issuerKey));
        ClaimIssuer(payable(_issuerIdentity)).issueClaim(
            _targetIdentity,
            _topic,
            data,
            string(abi.encodePacked("ipfs://claim/", _data)),
            signature
        );
    }

    function _issueClaimToIdentity(
        address _issuerIdentity,
        address _targetIdentity,
        uint256 _topic,
        string memory _data,
        uint256 _issuerKey
    ) internal {
        bytes memory data = abi.encode(_data);
        bytes32 claimId = keccak256(abi.encodePacked(_issuerIdentity, _topic));
        bytes memory signature = _signClaim(_issuerKey, claimId, _topic, data);

        vm.prank(vm.addr(_issuerKey));
        ClaimIssuer(payable(_issuerIdentity)).issueClaim(
            _targetIdentity,
            _topic,
            data,
            string(abi.encodePacked("ipfs://claim/", _data)),
            signature
        );
    }

    function _signClaim(
        uint256 _privateKey,
        bytes32 _claimId,
        uint256 _topic,
        bytes memory _data
    ) internal pure returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(_claimId, _topic, _data));
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, prefixedHash);

        return abi.encodePacked(r, s, v);
    }
}
