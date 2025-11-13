// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/factory/IdentityFactory.sol";
import "../src/identity/implementation/InvestorIdentity.sol";
import "../src/identity/implementation/ClaimIssuer.sol";
import "../src/identity/storage/IdentityStorage.sol";

contract IdentitySystemIntegrationTest is Test {
    IdentityFactory public factory;
    
    // User accounts
    address public deployer;
    address public investorA;
    address public investorB;
    address public issuerC;
    address public issuerD;
    
    // Private keys for signing
    uint256 public investorAKey;
    uint256 public investorBKey;
    uint256 public issuerCKey;
    uint256 public issuerDKey;
    
    // Identity contracts
    address payable public identityA;
    address payable public identityB;
    address payable public identityC;
    address payable public identityD;
    
    function setUp() public {
        // Setup accounts with private keys
        deployer = address(this);
        
        investorAKey = 0xA0A0;
        investorBKey = 0xB0B0;
        issuerCKey = 0xC0C0;
        issuerDKey = 0xD0D0;
        
        investorA = vm.addr(investorAKey);
        investorB = vm.addr(investorBKey);
        issuerC = vm.addr(issuerCKey);
        issuerD = vm.addr(issuerDKey);
        
        // Label addresses for better trace output
        vm.label(investorA, "InvestorA");
        vm.label(investorB, "InvestorB");
        vm.label(issuerC, "IssuerC");
        vm.label(issuerD, "IssuerD");
        
        // Deploy factory
        factory = new IdentityFactory();
    }
    
    function test_CompleteWorkflow() public {
        // ============ Step 1: Create identities ============
        console.log("=== Step 1: Creating Identities ===");
        
        // Create investor A identity
        identityA = payable(factory.createInvestorIdentity(investorA, "Investor Alice"));
        console.log("Created identity for Investor A:", identityA);
        
        // Create investor B identity
        identityB = payable(factory.createInvestorIdentity(investorB, "Investor Bob"));
        console.log("Created identity for Investor B:", identityB);
        
        // Create issuer C identity
        identityC = payable(factory.createIssuerIdentity(issuerC, "KYC Provider Charlie"));
        console.log("Created identity for Issuer C:", identityC);
        
        // Create issuer D identity
        identityD = payable(factory.createIssuerIdentity(issuerD, "AML Provider David"));
        console.log("Created identity for Issuer D:", identityD);
        
        // Verify identities are created correctly
        assertEq(factory.getIdentity(investorA), identityA);
        assertEq(factory.getIdentity(investorB), identityB);
        assertEq(factory.getIdentity(issuerC), identityC);
        assertEq(factory.getIdentity(issuerD), identityD);
        
        // ============ Step 2: Issuers add CLAIM purpose to themselves ============
        console.log("\n=== Step 2: Issuers Adding CLAIM Purpose ===");
        
        // Issuer C adds CLAIM purpose to itself
        vm.startPrank(issuerC);
        bytes32 issuerCKeyHash = keccak256(abi.encodePacked(issuerC));
        ClaimIssuer(identityC).addKey(
            issuerCKeyHash,
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();
        console.log("Issuer C added CLAIM purpose to itself");
        
        // Issuer D adds CLAIM purpose to itself
        vm.startPrank(issuerD);
        bytes32 issuerDKeyHash = keccak256(abi.encodePacked(issuerD));
        ClaimIssuer(identityD).addKey(
            issuerDKeyHash,
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();
        console.log("Issuer D added CLAIM purpose to itself");
        
        // Verify CLAIM purposes are added
        assertTrue(ClaimIssuer(identityC).keyHasPurpose(issuerCKeyHash, IdentityStorage.CLAIM_PURPOSE));
        assertTrue(ClaimIssuer(identityD).keyHasPurpose(issuerDKeyHash, IdentityStorage.CLAIM_PURPOSE));
        
        // ============ Step 3: Investors grant CLAIM permissions to issuer identity contracts ============
        console.log("\n=== Step 3: Investors Granting CLAIM Permissions ===");
        
        // Investor A grants CLAIM permission to identity contracts of C and D (not EOA addresses!)
        bytes32 identityCKeyHash = keccak256(abi.encodePacked(identityC));
        bytes32 identityDKeyHash = keccak256(abi.encodePacked(identityD));
        
        vm.startPrank(investorA);
        InvestorIdentity(identityA).addKey(
            identityCKeyHash,
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        InvestorIdentity(identityA).addKey(
            identityDKeyHash,
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();
        console.log("Investor A granted CLAIM permissions to identity contracts C and D");
        
        // Investor B grants CLAIM permission to identity contract D only
        vm.startPrank(investorB);
        InvestorIdentity(identityB).addKey(
            identityDKeyHash,
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();
        console.log("Investor B granted CLAIM permission to identity contract D");
        
        // Verify permissions
        assertTrue(InvestorIdentity(identityA).keyHasPurpose(identityCKeyHash, IdentityStorage.CLAIM_PURPOSE));
        assertTrue(InvestorIdentity(identityA).keyHasPurpose(identityDKeyHash, IdentityStorage.CLAIM_PURPOSE));
        assertTrue(InvestorIdentity(identityB).keyHasPurpose(identityDKeyHash, IdentityStorage.CLAIM_PURPOSE));
        assertFalse(InvestorIdentity(identityB).keyHasPurpose(identityCKeyHash, IdentityStorage.CLAIM_PURPOSE));
        
        // ============ Step 4: Issue claims (successful cases) ============
        console.log("\n=== Step 4: Issuing Claims (Success) ===");
        
        // C issues KYC claim to A
        bytes memory kycDataA = abi.encode("US", "1999-01-01", true);
        bytes32 claimIdCA = keccak256(abi.encodePacked(identityC, IdentityStorage.KYC_CLAIM));
        bytes memory signatureCA = _signClaim(issuerCKey, claimIdCA, IdentityStorage.KYC_CLAIM, kycDataA);
        
        vm.prank(issuerC);
        bytes32 issuedClaimCA = ClaimIssuer(identityC).issueClaim(
            identityA,
            IdentityStorage.KYC_CLAIM,
            kycDataA,
            "ipfs://kycA",
            signatureCA
        );
        console.log("C issued KYC claim to A");
        
        // D issues AML claim to B
        bytes memory amlDataB = abi.encode("UK", "PASSED", block.timestamp);
        bytes32 claimIdDB = keccak256(abi.encodePacked(identityD, IdentityStorage.AML_CLAIM));
        bytes memory signatureDB = _signClaim(issuerDKey, claimIdDB, IdentityStorage.AML_CLAIM, amlDataB);
        
        vm.prank(issuerD);
        bytes32 issuedClaimDB = ClaimIssuer(identityD).issueClaim(
            identityB,
            IdentityStorage.AML_CLAIM,
            amlDataB,
            "ipfs://amlB",
            signatureDB
        );
        console.log("D issued AML claim to B");
        
        // D issues AML claim to A
        bytes memory amlDataA = abi.encode("US", "PASSED", block.timestamp);
        bytes32 claimIdDA = keccak256(abi.encodePacked(identityD, IdentityStorage.AML_CLAIM));
        bytes memory signatureDA = _signClaim(issuerDKey, claimIdDA, IdentityStorage.AML_CLAIM, amlDataA);
        
        vm.prank(issuerD);
        bytes32 issuedClaimDA = ClaimIssuer(identityD).issueClaim(
            identityA,
            IdentityStorage.AML_CLAIM,
            amlDataA,
            "ipfs://amlA",
            signatureDA
        );
        console.log("D issued AML claim to A");
        
        // ============ Step 5: Verify claims are valid ============
        console.log("\n=== Step 5: Verifying Claims ===");
        
        // Verify claim C->A
        assertTrue(InvestorIdentity(identityA).isClaimValid(issuedClaimCA), "Claim C->A should be valid");
        console.log("Claim C->A is valid");
        
        // Verify claim D->B
        assertTrue(InvestorIdentity(identityB).isClaimValid(issuedClaimDB), "Claim D->B should be valid");
        console.log("Claim D->B is valid");
        
        // Verify claim D->A
        assertTrue(InvestorIdentity(identityA).isClaimValid(issuedClaimDA), "Claim D->A should be valid");
        console.log("Claim D->A is valid");
        
        // Verify claim details
        (uint256 topic, uint256 scheme, address issuer, , , string memory uri) = 
            InvestorIdentity(identityA).getClaim(issuedClaimCA);
        
        assertEq(topic, IdentityStorage.KYC_CLAIM);
        assertEq(scheme, IdentityStorage.ECDSA_SCHEME);
        assertEq(issuer, identityC);
        assertEq(uri, "ipfs://kycA");
        
        // ============ Step 6: Try to issue claim without permission (should fail) ============
        console.log("\n=== Step 6: Testing Unauthorized Claim Issuance ===");
        
        bytes memory kycDataB = abi.encode("UK", "2000-01-01", true);
        bytes32 claimIdCB = keccak256(abi.encodePacked(identityC, IdentityStorage.KYC_CLAIM));
        bytes memory signatureCB = _signClaim(issuerCKey, claimIdCB, IdentityStorage.KYC_CLAIM, kycDataB);
        
        vm.prank(issuerC);
        vm.expectRevert("Identity: key does not have purpose");
        ClaimIssuer(identityC).issueClaim(
            identityB,
            IdentityStorage.KYC_CLAIM,
            kycDataB,
            "ipfs://kycB",
            signatureCB
        );
        console.log("C correctly failed to issue claim to B (no permission)");
        
        console.log("\n=== All Tests Passed ===");
    }
    
    function test_InvestorVerificationStatus() public {
        // Create identities
        identityA = payable(factory.createInvestorIdentity(investorA, "Investor Alice"));
        identityC = payable(factory.createIssuerIdentity(issuerC, "KYC Provider"));
        identityD = payable(factory.createIssuerIdentity(issuerD, "AML Provider"));
        
        // Setup permissions
        vm.prank(issuerC);
        ClaimIssuer(identityC).addKey(
            keccak256(abi.encodePacked(issuerC)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        
        vm.prank(issuerD);
        ClaimIssuer(identityD).addKey(
            keccak256(abi.encodePacked(issuerD)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        
        vm.startPrank(investorA);
        InvestorIdentity(identityA).addKey(
            keccak256(abi.encodePacked(identityC)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        InvestorIdentity(identityA).addKey(
            keccak256(abi.encodePacked(identityD)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();
        
        // Initially not verified
        assertFalse(InvestorIdentity(identityA).hasKYCClaim());
        assertFalse(InvestorIdentity(identityA).hasAMLClaim());
        
        // Issue KYC claim
        bytes memory kycData = abi.encode("US", "1999-01-01", true);
        bytes32 kycClaimId = keccak256(abi.encodePacked(identityC, IdentityStorage.KYC_CLAIM));
        bytes memory kycSignature = _signClaim(issuerCKey, kycClaimId, IdentityStorage.KYC_CLAIM, kycData);
        
        vm.prank(issuerC);
        ClaimIssuer(identityC).issueClaim(
            identityA,
            IdentityStorage.KYC_CLAIM,
            kycData,
            "ipfs://kyc",
            kycSignature
        );
        
        // Has KYC but not fully verified yet
        assertTrue(InvestorIdentity(identityA).hasKYCClaim());
        assertFalse(InvestorIdentity(identityA).hasAMLClaim());
        
        // Issue AML claim
        bytes memory amlData = abi.encode("US", "PASSED", block.timestamp);
        bytes32 amlClaimId = keccak256(abi.encodePacked(identityD, IdentityStorage.AML_CLAIM));
        bytes memory amlSignature = _signClaim(issuerDKey, amlClaimId, IdentityStorage.AML_CLAIM, amlData);
        
        vm.prank(issuerD);
        ClaimIssuer(identityD).issueClaim(
            identityA,
            IdentityStorage.AML_CLAIM,
            amlData,
            "ipfs://aml",
            amlSignature
        );
        
        // Now fully verified
        assertTrue(InvestorIdentity(identityA).hasKYCClaim());
        assertTrue(InvestorIdentity(identityA).hasAMLClaim());
        assertTrue(InvestorIdentity(identityA).isFullyVerified());
        
        // Check verification status
        (bool kycValid, bool amlValid, bool accreditationValid) = 
            InvestorIdentity(identityA).getVerificationStatus();
        
        assertTrue(kycValid);
        assertTrue(amlValid);
        assertFalse(accreditationValid);
    }
    
    function test_ClaimRevocation() public {
        // Setup identities and permissions
        identityA = payable(factory.createInvestorIdentity(investorA, "Investor Alice"));
        identityC = payable(factory.createIssuerIdentity(issuerC, "KYC Provider"));
        
        vm.prank(issuerC);
        ClaimIssuer(identityC).addKey(
            keccak256(abi.encodePacked(issuerC)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        
        vm.prank(investorA);
        InvestorIdentity(identityA).addKey(
            keccak256(abi.encodePacked(identityC)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        
        // Issue claim
        bytes memory kycData = abi.encode("US", "1999-01-01", true);
        bytes32 claimId = keccak256(abi.encodePacked(identityC, IdentityStorage.KYC_CLAIM));
        bytes memory signature = _signClaim(issuerCKey, claimId, IdentityStorage.KYC_CLAIM, kycData);
        
        vm.prank(issuerC);
        bytes32 issuedClaimId = ClaimIssuer(identityC).issueClaim(
            identityA,
            IdentityStorage.KYC_CLAIM,
            kycData,
            "ipfs://kyc",
            signature
        );
        
        // Claim should be valid
        assertTrue(InvestorIdentity(identityA).isClaimValid(issuedClaimId));
        assertTrue(InvestorIdentity(identityA).hasKYCClaim());
        assertTrue(ClaimIssuer(identityC).isClaimIssued(issuedClaimId));

        // Revoke claim
        vm.prank(issuerC);
        bool success = ClaimIssuer(identityC).revokeClaim(issuedClaimId);
        assertTrue(success);
        
        // Claim should no longer be valid
        assertFalse(InvestorIdentity(identityA).isClaimValid(issuedClaimId));
        assertFalse(InvestorIdentity(identityA).hasKYCClaim());
        assertFalse(ClaimIssuer(identityC).isClaimIssued(issuedClaimId));
    }
    
    function test_KeyManagement() public {
        identityA = payable(factory.createInvestorIdentity(investorA, "Investor Alice"));
        
        // Create new management key
        address newManager = makeAddr("newManager");
        bytes32 newKey = keccak256(abi.encodePacked(newManager));
        
        // Add new key with MANAGEMENT purpose
        vm.prank(investorA);
        InvestorIdentity(identityA).addKey(
            newKey,
            IdentityStorage.MANAGEMENT_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        
        assertTrue(InvestorIdentity(identityA).keyHasPurpose(newKey, IdentityStorage.MANAGEMENT_PURPOSE));
        
        // New manager can add another key
        address anotherKey = makeAddr("anotherKey");
        bytes32 anotherKeyHash = keccak256(abi.encodePacked(anotherKey));
        
        vm.prank(newManager);
        InvestorIdentity(identityA).addKey(
            anotherKeyHash,
            IdentityStorage.ACTION_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        
        assertTrue(InvestorIdentity(identityA).keyHasPurpose(anotherKeyHash, IdentityStorage.ACTION_PURPOSE));
        
        // Remove key
        vm.prank(investorA);
        InvestorIdentity(identityA).removeKey(newKey, IdentityStorage.MANAGEMENT_PURPOSE);
        
        assertFalse(InvestorIdentity(identityA).keyHasPurpose(newKey, IdentityStorage.MANAGEMENT_PURPOSE));
    }
    
    function test_MultipleClaimsByTopic() public {
        // Setup
        identityA = payable(factory.createInvestorIdentity(investorA, "Investor Alice"));
        identityC = payable(factory.createIssuerIdentity(issuerC, "KYC Provider 1"));
        identityD = payable(factory.createIssuerIdentity(issuerD, "KYC Provider 2"));
        
        // Setup permissions
        vm.prank(issuerC);
        ClaimIssuer(identityC).addKey(
            keccak256(abi.encodePacked(issuerC)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        
        vm.prank(issuerD);
        ClaimIssuer(identityD).addKey(
            keccak256(abi.encodePacked(issuerD)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        
        vm.startPrank(investorA);
        InvestorIdentity(identityA).addKey(
            keccak256(abi.encodePacked(identityC)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        InvestorIdentity(identityA).addKey(
            keccak256(abi.encodePacked(identityD)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();
        
        // Issue KYC claim from C
        bytes memory kycDataC = abi.encode("US", "1999-01-01", true);
        bytes32 claimIdC = keccak256(abi.encodePacked(identityC, IdentityStorage.KYC_CLAIM));
        bytes memory signatureC = _signClaim(issuerCKey, claimIdC, IdentityStorage.KYC_CLAIM, kycDataC);
        
        vm.prank(issuerC);
        ClaimIssuer(identityC).issueClaim(
            identityA,
            IdentityStorage.KYC_CLAIM,
            kycDataC,
            "ipfs://kycC",
            signatureC
        );
        
        // Issue KYC claim from D
        bytes memory kycDataD = abi.encode("US", "1999-01-02", true);
        bytes32 claimIdD = keccak256(abi.encodePacked(identityD, IdentityStorage.KYC_CLAIM));
        bytes memory signatureD = _signClaim(issuerDKey, claimIdD, IdentityStorage.KYC_CLAIM, kycDataD);
        
        vm.prank(issuerD);
        ClaimIssuer(identityD).issueClaim(
            identityA,
            IdentityStorage.KYC_CLAIM,
            kycDataD,
            "ipfs://kycD",
            signatureD
        );
        
        // Should have 2 KYC claims
        bytes32[] memory kycClaims = InvestorIdentity(identityA).getClaimIdsByTopic(IdentityStorage.KYC_CLAIM);
        assertEq(kycClaims.length, 2);
        
        // Both should be valid
        assertTrue(InvestorIdentity(identityA).isClaimValid(kycClaims[0]));
        assertTrue(InvestorIdentity(identityA).isClaimValid(kycClaims[1]));
    }
    
    function test_FactoryQueries() public {
        // Create identities
        identityA = payable(factory.createInvestorIdentity(investorA, "Investor Alice"));
        identityB = payable(factory.createInvestorIdentity(investorB, "Investor Bob"));
        identityC = payable(factory.createIssuerIdentity(issuerC, "KYC Provider"));
        
        // Test getIdentity
        assertEq(factory.getIdentity(investorA), identityA);
        assertEq(factory.getIdentity(investorB), identityB);
        assertEq(factory.getIdentity(issuerC), identityC);
        
        // Test getIdentityOwner
        assertEq(factory.getIdentityOwner(identityA), investorA);
        assertEq(factory.getIdentityOwner(identityB), investorB);
        assertEq(factory.getIdentityOwner(identityC), issuerC);
        
        // Test identity counts
        (uint256 investorCount, uint256 issuerCount) = factory.getIdentityCount();
        assertEq(investorCount, 2);
        assertEq(issuerCount, 1);
        
        // Test get all investors
        address[] memory investors = factory.getInvestorIdentities();
        assertEq(investors.length, 2);
        
        // Test get all issuers
        address[] memory issuers = factory.getIssuerIdentities();
        assertEq(issuers.length, 1);
        assertEq(issuers[0], identityC);
    }
    
    function test_BatchOperations() public {
        // Setup
        identityC = payable(factory.createIssuerIdentity(issuerC, "KYC Provider"));
        
        vm.prank(issuerC);
        ClaimIssuer(identityC).addKey(
            keccak256(abi.encodePacked(issuerC)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        
        // Create multiple investors
        address[] memory investors = new address[](3);
        string[] memory names = new string[](3);
        
        address investor1 = makeAddr("investor1");
        address investor2 = makeAddr("investor2");
        address investor3 = makeAddr("investor3");
        
        investors[0] = investor1;
        investors[1] = investor2;
        investors[2] = investor3;
        names[0] = "Investor 1";
        names[1] = "Investor 2";
        names[2] = "Investor 3";
        
        // Factory owner must call batch create since it requires owner permission
        address[] memory identities = factory.batchCreateInvestorIdentities(investors, names);
        
        assertEq(identities.length, 3);
        assertEq(factory.getIdentity(investor1), identities[0]);
        assertEq(factory.getIdentity(investor2), identities[1]);
        assertEq(factory.getIdentity(investor3), identities[2]);
        
        // Grant permissions to all investors (using identity contract address, not EOA)
        for (uint256 i = 0; i < identities.length; i++) {
            vm.prank(investors[i]);
            InvestorIdentity(payable(identities[i])).addKey(
                keccak256(abi.encodePacked(identityC)),
                IdentityStorage.CLAIM_PURPOSE,
                IdentityStorage.ECDSA_KEY
            );
        }
        
        // Batch issue claims
        address[] memory batchIdentities = new address[](3);
        uint256[] memory topics = new uint256[](3);
        bytes[] memory dataArray = new bytes[](3);
        string[] memory uris = new string[](3);
        bytes[] memory signatures = new bytes[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            batchIdentities[i] = identities[i];
            topics[i] = IdentityStorage.KYC_CLAIM;
            dataArray[i] = abi.encode("US", "1999-01-01", true);
            uris[i] = string(abi.encodePacked("ipfs://kyc", i));
            
            bytes32 claimId = keccak256(abi.encodePacked(identityC, IdentityStorage.KYC_CLAIM));
            signatures[i] = _signClaim(issuerCKey, claimId, IdentityStorage.KYC_CLAIM, dataArray[i]);
        }
        
        vm.prank(issuerC);
        bytes32[] memory claimIds = ClaimIssuer(identityC).batchIssueClaims(
            batchIdentities,
            topics,
            dataArray,
            uris,
            signatures
        );
        
        assertEq(claimIds.length, 3);
        
        // Verify all claims are valid
        for (uint256 i = 0; i < 3; i++) {
            assertTrue(InvestorIdentity(payable(identities[i])).hasKYCClaim());
        }
    }
    
    function test_ClaimRemoval() public {
        // Setup
        identityA = payable(factory.createInvestorIdentity(investorA, "Investor Alice"));
        identityC = payable(factory.createIssuerIdentity(issuerC, "KYC Provider"));
        
        vm.prank(issuerC);
        ClaimIssuer(identityC).addKey(
            keccak256(abi.encodePacked(issuerC)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        
        vm.prank(investorA);
        InvestorIdentity(identityA).addKey(
            keccak256(abi.encodePacked(identityC)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        
        // Issue claim
        bytes memory kycData = abi.encode("US", "1999-01-01", true);
        bytes32 claimId = keccak256(abi.encodePacked(identityC, IdentityStorage.KYC_CLAIM));
        bytes memory signature = _signClaim(issuerCKey, claimId, IdentityStorage.KYC_CLAIM, kycData);
        
        vm.prank(issuerC);
        bytes32 issuedClaimId = ClaimIssuer(identityC).issueClaim(
            identityA,
            IdentityStorage.KYC_CLAIM,
            kycData,
            "ipfs://kyc",
            signature
        );
        
        assertTrue(InvestorIdentity(identityA).hasKYCClaim());
        assertTrue(ClaimIssuer(identityC).isClaimIssued(issuedClaimId));
        
        // Remove claim through issuer (issuer can revoke/remove claims it issued)
        vm.prank(issuerC);
        ClaimIssuer(identityC).revokeClaim(issuedClaimId);
        
        // Claim should not exist anymore
        assertFalse(InvestorIdentity(identityA).hasKYCClaim());
        assertFalse(ClaimIssuer(identityC).isClaimIssued(issuedClaimId));
        
        // Getting the claim should revert
        vm.expectRevert("Identity: claim does not exist");
        InvestorIdentity(identityA).getClaim(issuedClaimId);
    }
    
    // Helper function to sign a claim
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

