// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/factory/IdentityFactory.sol";
import "../src/registry/implementation/ClaimTopicsRegistry.sol";
import "../src/registry/implementation/TrustedIssuersRegistry.sol";
import "../src/registry/implementation/IdentityRegistryStorage.sol";
import "../src/registry/implementation/IdentityRegistry.sol";
import "../src/compliance/implementation/ModularCompliance.sol";
import "../src/compliance/modules/CountryAllowModule.sol";
import "../src/token/implementation/LuxShareFactory.sol";
import "../src/token/implementation/LuxAssetNFT.sol";
import "../src/token/storage/TokenStorage.sol";

import "../src/market/implementation/PrimaryOffering.sol";
import "../src/market/implementation/P2PTrading.sol";
import "../src/market/implementation/Redemption.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock USDC contract for testing
contract MockUSDC is ERC20 {
    uint8 constant _decimals = 6;

    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

abstract contract BaseFixture is Test {
    // ============ Test Accounts ============
    address public admin; // System administrator
    address public issuerA; // Issuer A (trusted)
    address public issuerB; // Issuer B (not trusted)
    address public investorAIA; // Investor's investor AIA (has KYC + AML), country code: 840(US)
    address public investorAIB; // Investor's investor AIB (has KYC + AML), country code: 840(US)
    address public investorAIC; // Investor's investor AIC (has KYC + AML), country code: 156(China)
    address public investorAID; // Investor's investor AID (has KYC), country code: 840(US)
    address public investorBIA; // Issuer B's investor BIA (has KYC + AML but issuer not trusted), country code: 840(US)

    // Private keys for signing
    uint256 public adminKey; // System administrator's private key
    uint256 public issuerAKey; // Issuer A's private key
    uint256 public issuerBKey; // Issuer B's private key
    uint256 public investorAIAKey; // Investor AIA's private key
    uint256 public investorAIBKey; // Investor AIB's private key
    uint256 public investorAICKey; // Investor AIC's private key
    uint256 public investorAIDKey; // Investor AID's private key
    uint256 public investorBIAKey; // Investor BIA's private key

    // ============ Identity Contracts ============
    IdentityFactory public factoryA; // Factory for Issuer A
    IdentityFactory public factoryB; // Factory for Issuer B

    // Issuer A and their identities
    address payable public identityIssuerA; // Issuer A's identity
    address payable public identityAIA; // Investor AIA's identity
    address payable public identityAIB; // Investor AIB's identity
    address payable public identityAIC; // Investor AIC's identity
    address payable public identityAID; // Investor AID's identity

    // Issuer B and their identities
    address payable public identityIssuerB; // Issuer B's identity
    address payable public identityBIA; // Investor BIA's identity

    // ============ Registry System ============
    ClaimTopicsRegistry public claimTopicsRegistry;
    TrustedIssuersRegistry public trustedIssuersRegistry;
    IdentityRegistryStorage public identityRegistryStorage;
    IdentityRegistry public identityRegistry;

    // ============ Compliance System ============
    ModularCompliance public modularCompliance1;
    ModularCompliance public modularCompliance2;
    // more compliance modules can be added here

    // ============ Token System ============
    LuxShareFactory public luxRWAFactory;
    LuxAssetNFT public luxRWAAssetNFT;
    address public shareTokenAddress1;
    address public shareTokenAddress2;

    // Test asset data
    TokenStorage.AssetMetadata public testAssetMetadata1;
    TokenStorage.AssetMetadata public testAssetMetadata2;
    TokenStorage.ShareTokenConfig public testShareConfig1;
    TokenStorage.ShareTokenConfig public testShareConfig2;

    // ============ USDC System ============
    MockUSDC public usdc;

    // ============ Market System ============
    PrimaryOffering public primaryOffering;
    P2PTrading public p2pTrading;

    // ============ Redemption System ============
    Redemption public redemption;

    function ONCHAINIDSetUp() public virtual {
        // ============ Setup Accounts ============
        // Setup accounts with private keys
        issuerAKey = 0xAAAA;
        issuerBKey = 0xBBBB;
        investorAIAKey = 0xA1A1;
        investorAIBKey = 0xA1B1;
        investorAICKey = 0xA1C1;
        investorAIDKey = 0xA1D1;
        investorBIAKey = 0xB1A1;

        issuerA = vm.addr(issuerAKey);
        issuerB = vm.addr(issuerBKey);
        investorAIA = vm.addr(investorAIAKey);
        investorAIB = vm.addr(investorAIBKey);
        investorAIC = vm.addr(investorAICKey);
        investorAID = vm.addr(investorAIDKey);
        investorBIA = vm.addr(investorBIAKey);

        // Label addresses for better trace output
        vm.label(issuerA, "IssuerA");
        vm.label(issuerB, "IssuerB");
        vm.label(investorAIA, "InvestorAIA");
        vm.label(investorAIB, "InvestorAIB");
        vm.label(investorAIC, "InvestorAIC");
        vm.label(investorAID, "InvestorAID");
        vm.label(investorBIA, "InvestorBIA");

        // ============ Deploy Factories ============
        // Issuer A deploys factory
        vm.startPrank(issuerA);
        factoryA = new IdentityFactory();
        vm.stopPrank();

        // Issuer B deploys factory
        vm.startPrank(issuerB);
        factoryB = new IdentityFactory();
        vm.stopPrank();

        // ============ Create Identities ============
        // Issuer A creates identity for themselves (ClaimIssuer type)
        vm.startPrank(issuerA);
        identityIssuerA = payable(factoryA.createIssuerIdentity(issuerA, "Issuer A"));

        // Issuer A creates identities for their investors
        identityAIA = payable(factoryA.createInvestorIdentity(investorAIA, "Investor AIA"));
        identityAIB = payable(factoryA.createInvestorIdentity(investorAIB, "Investor AIB"));
        identityAIC = payable(factoryA.createInvestorIdentity(investorAIC, "Investor AIC"));
        identityAID = payable(factoryA.createInvestorIdentity(investorAID, "Investor AID"));
        vm.stopPrank();

        // Issuer B creates identity for themselves (ClaimIssuer type)
        vm.startPrank(issuerB);
        identityIssuerB = payable(factoryB.createIssuerIdentity(issuerB, "Issuer B"));

        // Issuer B creates identities for their investors
        identityBIA = payable(factoryB.createInvestorIdentity(investorBIA, "Investor BIA"));
        vm.stopPrank();

        // ============ Issuer Set up CLAIM purposes and issues claims for themselves ============
        // Issuer A sets up CLAIM purpose and issues claims for themselves
        vm.startPrank(issuerA);
        ClaimIssuer(identityIssuerA).addKey(
            keccak256(abi.encodePacked(issuerA)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        ClaimIssuer(identityIssuerA).addKey(
            keccak256(abi.encodePacked(identityIssuerA)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();

        // Issuer A issues claims for themselves
        _issueClaimToIdentity(identityIssuerA, identityIssuerA, IdentityStorage.KYC_CLAIM, "KYC data for Issuer A", issuerAKey);
        _issueClaimToIdentity(identityIssuerA, identityIssuerA, IdentityStorage.AML_CLAIM, "AML data for Issuer A", issuerAKey);
        _issueClaimToIdentity(identityIssuerA, identityIssuerA, IdentityStorage.ACCREDITATION_CLAIM, "Accreditation data for Issuer A", issuerAKey);
        _issueClaimToIdentity(identityIssuerA, identityIssuerA, IdentityStorage.COUNTRY_CLAIM, "Country data for Issuer A", issuerAKey);

        // Issuer B sets up CLAIM purpose for themselves
        vm.startPrank(issuerB);
        ClaimIssuer(identityIssuerB).addKey(
            keccak256(abi.encodePacked(issuerB)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        ClaimIssuer(identityIssuerB).addKey(
            keccak256(abi.encodePacked(identityIssuerB)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();

        // Issuer B issues claims for themselves
        _issueClaimToIdentity(identityIssuerB, identityIssuerB, IdentityStorage.KYC_CLAIM, "KYC data for Issuer B", issuerBKey);
        _issueClaimToIdentity(identityIssuerB, identityIssuerB, IdentityStorage.AML_CLAIM, "AML data for Issuer B", issuerBKey);
        _issueClaimToIdentity(identityIssuerB, identityIssuerB, IdentityStorage.ACCREDITATION_CLAIM, "Accreditation data for Issuer B", issuerBKey);
        _issueClaimToIdentity(identityIssuerB, identityIssuerB, IdentityStorage.COUNTRY_CLAIM, "Country data for Issuer B", issuerBKey);

        // ============ Investors grant CLAIM permissions to their Issuer ============
        
        // Investor AIA grants CLAIM permissions to Issuer A
        vm.startPrank(investorAIA);
        InvestorIdentity(identityAIA).addKey(
            keccak256(abi.encodePacked(identityIssuerA)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();

        // Investor AIB grants CLAIM permissions to Issuer A
        vm.startPrank(investorAIB);
        InvestorIdentity(identityAIB).addKey(
            keccak256(abi.encodePacked(identityIssuerA)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();

        // Investor AIC grants CLAIM permissions to Issuer A
        vm.startPrank(investorAIC);
        InvestorIdentity(identityAIC).addKey(
            keccak256(abi.encodePacked(identityIssuerA)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();

        // Investor AID grants CLAIM permissions to Issuer A
        vm.startPrank(investorAID);
        InvestorIdentity(identityAID).addKey(
            keccak256(abi.encodePacked(identityIssuerA)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();

        // Investor BIA grants CLAIM permissions to Issuer B
        vm.startPrank(investorBIA);
        InvestorIdentity(identityBIA).addKey(
            keccak256(abi.encodePacked(identityIssuerB)),
            IdentityStorage.CLAIM_PURPOSE,
            IdentityStorage.ECDSA_KEY
        );
        vm.stopPrank();

        // ============ Issuer issues claims to their investors ============
        // AIA gets both KYC and AML
        _issueClaimToIdentity(identityIssuerA, identityAIA, IdentityStorage.KYC_CLAIM, "KYC data for AIA", issuerAKey);
        _issueClaimToIdentity(identityIssuerA, identityAIA, IdentityStorage.AML_CLAIM, "AML data for AIA", issuerAKey);
        // AIB gets both KYC and AML
        _issueClaimToIdentity(identityIssuerA, identityAIB, IdentityStorage.KYC_CLAIM, "KYC data for AIB", issuerAKey);
        _issueClaimToIdentity(identityIssuerA, identityAIB, IdentityStorage.AML_CLAIM, "AML data for AIB", issuerAKey);
        // AIC gets both KYC and AML
        _issueClaimToIdentity(identityIssuerA, identityAIC, IdentityStorage.KYC_CLAIM, "KYC data for AIC", issuerAKey);
        _issueClaimToIdentity(identityIssuerA, identityAIC, IdentityStorage.AML_CLAIM, "AML data for AIC", issuerAKey);
        // AID gets only KYC
        _issueClaimToIdentity(identityIssuerA, identityAID, IdentityStorage.KYC_CLAIM, "KYC data for AID", issuerAKey);
        // BIA gets both KYC and AML
        _issueClaimToIdentity(identityIssuerB, identityBIA, IdentityStorage.KYC_CLAIM, "KYC data for BIA", issuerBKey);
        console.log("ONCHAINIDSetUp completed!");
    }

    function IdentityRegistrySetUp() public virtual {
        // ============ Setup Accounts ============
        adminKey = 0xADAD;
        admin = vm.addr(adminKey);
        vm.label(admin, "Admin");

        // ============ Deploy Registry System ============
        vm.startPrank(admin);
        claimTopicsRegistry = new ClaimTopicsRegistry();
        trustedIssuersRegistry = new TrustedIssuersRegistry();
        identityRegistryStorage = new IdentityRegistryStorage();
        identityRegistry = new IdentityRegistry(
            address(trustedIssuersRegistry),
            address(claimTopicsRegistry),
            address(identityRegistryStorage)
        );

        // ============ Bind the identity registry to storage ============
        identityRegistryStorage.bindIdentityRegistry(address(identityRegistry));

        // ============ Add required claim topics (KYC and AML) ============
        claimTopicsRegistry.addClaimTopic(IdentityStorage.KYC_CLAIM);
        claimTopicsRegistry.addClaimTopic(IdentityStorage.AML_CLAIM);

        // ============ Add trusted issuers (only Issuer A) ============
        uint256[] memory claimTopicsA = new uint256[](4);
        claimTopicsA[0] = IdentityStorage.KYC_CLAIM;
        claimTopicsA[1] = IdentityStorage.AML_CLAIM;
        claimTopicsA[2] = IdentityStorage.ACCREDITATION_CLAIM;
        claimTopicsA[3] = IdentityStorage.COUNTRY_CLAIM;
        trustedIssuersRegistry.addTrustedIssuer(IClaimIssuer(identityIssuerA), claimTopicsA);

        // ============ Add Issuer A as agent ============
        identityRegistry.addAgent(issuerA);

        vm.stopPrank();
        console.log("IdentityRegistrySetUp completed!");
    }

    function InvestorRegistrationSetUp() public virtual {
        // ============ Investor Registration ============
        vm.startPrank(issuerA);
        // Issuer A registers themselves, has KYC and AML and accreditation and country claims, country code: 840(US)
        identityRegistry.registerIdentity(issuerA, IIdentity(identityIssuerA), 840);
        // AIA gets both KYC and AML, country code: 840(US)
        identityRegistry.registerIdentity(investorAIA, IIdentity(identityAIA), 840);
        // AIB gets both KYC and AML, country code: 840(US)
        identityRegistry.registerIdentity(investorAIB, IIdentity(identityAIB), 840);
        // AIC gets both KYC and AML, country code: 156(China)
        identityRegistry.registerIdentity(investorAIC, IIdentity(identityAIC), 156);
        // AID gets only KYC, country code: 840(US)
        identityRegistry.registerIdentity(investorAID, IIdentity(identityAID), 840);
        vm.stopPrank();

        bool aiaVerified = identityRegistry.isVerified(investorAIA);
        bool aibVerified = identityRegistry.isVerified(investorAIB);
        bool aicVerified = identityRegistry.isVerified(investorAIC);
        bool aidVerified = identityRegistry.isVerified(investorAID);

        bool issuerAVerified = identityRegistry.isVerified(issuerA);

        assertTrue(aiaVerified, "AIA should be verified");
        assertTrue(aibVerified, "AIB should be verified");
        assertTrue(aicVerified, "AIC should be verified");
        assertFalse(aidVerified, "AID should be verified");
        assertTrue(issuerAVerified, "Issuer A should be verified");
        console.log("InvestorRegistrationSetUp completed!");
    }

    function LuxRWAAssetNFTSetUp() public virtual {
        vm.startPrank(admin);
        // ============ Deploy compliance and modules ============
        modularCompliance1 = new ModularCompliance();
        modularCompliance2 = new ModularCompliance();
        // deploy country allow module
        CountryAllowModule countryAllowModule = new CountryAllowModule();

        // ============ Bind modules to compliance ============
        // Bind country allow module to compliance (only allow US - country code 840)
        modularCompliance1.addModule(address(countryAllowModule));
        modularCompliance2.addModule(address(countryAllowModule));

        // Use callModuleFunction to configure the module
        uint16[] memory allowedCountries = new uint16[](1);
        allowedCountries[0] = 840; // US country code
        bytes memory callData = abi.encodeWithSelector(
            CountryAllowModule.batchAllowCountries.selector,
            allowedCountries
        );
        modularCompliance1.callModuleFunction(callData, address(countryAllowModule));
        modularCompliance2.callModuleFunction(callData, address(countryAllowModule));

        // ============ Deploy factory ============
        luxRWAFactory = new LuxShareFactory();
        luxRWAFactory.initialize(address(identityRegistry), address(modularCompliance1));

        // Set factory address in compliance contract
        modularCompliance1.setFactory(address(luxRWAFactory));
        modularCompliance2.setFactory(address(luxRWAFactory));
        
        // ============ Deploy AssetNFT ============
        address assetNFTAddress = luxRWAFactory.deployAssetNFT("Luxury Asset NFT", "LANFT");
        luxRWAAssetNFT = LuxAssetNFT(assetNFTAddress);
        vm.stopPrank();
        console.log("LuxRWAAssetNFTSetUp completed!");
    }

    function LuxRWATokenSetUp() public virtual {
        testAssetMetadata1 = TokenStorage.AssetMetadata({
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
        testShareConfig1 = TokenStorage.ShareTokenConfig({
            name: "Rolex Submariner Share",
            symbol: "RLXSHARE",
            decimals: 18,
            initialSupply: 10000 * 10**18, // 10,000 shares
            issuer: issuerA, // issuer address, not identity contract
            shareClass: "Common",
            redeemable: true,
            compliance: address(modularCompliance1)
        });
        testAssetMetadata2 = TokenStorage.AssetMetadata({
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
        testShareConfig2 = TokenStorage.ShareTokenConfig({
            name: "Cartier Santos Share",
            symbol: "CTSSHARE",
            decimals: 18,
            initialSupply: 10000 * 10**18, // 10,000 shares
            issuer: issuerA, // issuer address, not identity contract
            shareClass: "Common",
            redeemable: true,
            compliance: address(modularCompliance2)
        });
        
        // ============ Mint AssetNFT ============
        vm.startPrank(admin);
        uint256 tokenId1 = luxRWAFactory.mintAssetNFT(address(luxRWAAssetNFT), issuerA, testAssetMetadata1);
        luxRWAFactory.verifyAssetNFT(address(luxRWAAssetNFT), tokenId1);
        uint256 tokenId2 = luxRWAFactory.mintAssetNFT(address(luxRWAAssetNFT), issuerA, testAssetMetadata2);
        luxRWAFactory.verifyAssetNFT(address(luxRWAAssetNFT), tokenId2);

        // ============ Create Share Tokens ============
        shareTokenAddress1 = luxRWAFactory.createShareToken(address(luxRWAAssetNFT), tokenId1, testShareConfig1);
        shareTokenAddress2 = luxRWAFactory.createShareToken(address(luxRWAAssetNFT), tokenId2, testShareConfig2);
        vm.stopPrank();
        console.log("LuxRWATokenSetUp completed:issuerA has 10000 shares of Rolex Submariner and 10000 shares of Cartier Santos!");
    }

    function MarketSetUp() public virtual {
        vm.startPrank(admin);
        primaryOffering = new PrimaryOffering(address(luxRWAFactory), address(identityRegistry));
        p2pTrading = new P2PTrading(address(luxRWAFactory), address(identityRegistry));

        luxRWAFactory.addAgentRole(address(primaryOffering));
        luxRWAFactory.addAgentRole(address(p2pTrading));

        vm.stopPrank();
        console.log("MarketSetUp completed!");

        // Deploy USDC mock
        usdc = new MockUSDC();
        usdc.mint(investorAIA, 1000000 * 10**6); // 1M USDC
        usdc.mint(investorAIB, 1000000 * 10**6); // 1M USDC
        usdc.mint(investorAIC, 1000000 * 10**6); // 1M USDC
        usdc.mint(investorAID, 1000000 * 10**6); // 1M USDC
        usdc.mint(investorBIA, 1000000 * 10**6); // 1M USDC

        console.log("USDC minted to investors");
    }

    function RedemptionSetUp() public virtual {
        vm.startPrank(admin);
        redemption = new Redemption(address(luxRWAFactory), address(identityRegistry));
        luxRWAFactory.addAgentRole(address(redemption));
        vm.stopPrank();
        console.log("RedemptionSetUp completed!");
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