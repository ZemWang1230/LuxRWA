[📖 中文版 / Chinese Version](README_CN.md)

## LuxRWA: On-chain Securitization Protocol for Luxury Physical Assets

LuxRWA is a set of on-chain securitization infrastructure for luxury physical assets, transforming traditionally non-standard, illiquid, and difficult-to-audit luxury assets into divisible, compliant tradable, automatically dividend-paying, and redeemable physical on-chain securitized assets through unified ERC721 physical certification and ERC3643-style share tokens (ShareToken).

The entire system is designed around the complete lifecycle of "**Physical Certification → Share Issuance → Compliant Trading → Revenue Distribution → Physical Redemption**", and is deeply compatible with the OnChainID / T-REX identity and compliance system.

---

## Project Features

- **Unified Physical Certification**: All luxury goods are certified through a single `LuxAssetNFT` contract, with each physical item mapped to a `tokenId`, unified metadata structure, and strong scalability.
- **ERC3643-style Securitized Tokens**: Each luxury item corresponds to an independent `LuxShareToken`, compatible with ERC20 interface and mandatory identity and compliance checks before transfers.
- **Modular Compliance Engine**: Based on `ModularCompliance` + multiple compliance modules (country restrictions, whitelists, lockups, etc.), each `LuxShareToken` has its own compliance center but can reuse modules.
- **Complete Identity System Reuse**: Issuers and investors are managed through OnChainID-style `Identity` / `InvestorIdentity`, with unified compliance checks reusing `IdentityRegistry`.
- **Primary and Secondary Market Closed Loop**: Through `PrimaryOffering` (primary subscription) and `P2PTrading` (secondary P2P order book) to achieve a complete market closed loop from initial subscription to free trading.
- **Revenue Distribution and Snapshot Mechanism**: `RevenueDistribution` uses snapshot mechanism to record holdings at a certain moment, automatically calculates revenue by share, can be claimed on demand and re-runs compliance when claiming.
- **Physical Redemption Closed Loop**: `Redemption` contract executes share lockup and destruction when investors hold all shares, and transfers the corresponding `LuxAssetNFT` from issuer to investor, completing the closed-loop delivery from on-chain to physical.

---

## System Roles

- **Admin (Platform Administrator)**
  - Deploy and initialize core contracts such as identity/compliance/token factory/market/revenue/redemption.
  - Configure required claim lists, trusted issuers, and issuable claim types.
  - As the highest authority role in each contract, responsible for binding modules, setting agents, etc.

- **Issuer (Issuer)**
  - Create on-chain identities for themselves and investors (through `IdentityFactory`).
  - Add `CLAIM` permissions to themselves and issue relevant compliance claims.
  - Issue KYC/AML/qualified investor claims to their investors and register investors in `IdentityRegistry`.
  - Hold the corresponding luxury item's `LuxAssetNFT` and all initial `LuxShareToken` shares.
  - Create subscription orders in the primary market, register revenues in the revenue distribution contract, and register assets that support redemption.

- **Investor (Investor)**
  - Have on-chain identities created by issuers and add the corresponding issuer address as an issuer with `CLAIM` permissions.
  - Receive KYC/AML/investor type claims issued by issuers and be registered in `IdentityRegistry`.
  - Subscribe to `LuxShareToken` in the primary market, conduct P2P trading in the secondary market, receive revenues by share, and initiate redemption when holding all shares.

---

## Contract and Module Architecture

### Identity and Compliance Foundation Layer

- **Core Contracts**
  - `Identity` / `InvestorIdentity` / `ClaimIssuer`
  - `ClaimTopicsRegistry` / `TrustedIssuersRegistry`
  - `IdentityRegistry` / `IdentityRegistryStorage`
- **Features**
  - Provide extensible identity system based on ERC734/735.
  - Define platform-level required claims through `ClaimTopicsRegistry` (such as KYC, AML).
  - `TrustedIssuersRegistry` records trusted issuers and their issuable topics.
  - `IdentityRegistry` checks if addresses have necessary claims before each transfer and records investor countries.

### Compliance Rules Module Layer

- **Core Contracts**
  - `IModularCompliance` / `IModule`
  - `ModularCompliance`
  - Module contracts: `CountryAllowModule`, `CountryRestrictModule`, etc.
- **Features**
  - Deploy a `ModularCompliance` instance for each `LuxShareToken` as the "compliance management center" for that token.
  - Different modules can be combined in stacks: regional restrictions, black/whitelists, lockup periods, holding limits, etc.
  - Call compliance center in `LuxShareToken`'s transfer hook, transfers that fail checks are rejected.

### Physical Certification Layer

- **Core Contracts**
  - `LuxAssetNFT` (implementation) / `ILuxAssetNFT` (interface)
- **Features**
  - Single ERC721 contract manages all luxury goods within the platform, each physical item corresponds to a `tokenId`.
  - Stores key metadata such as brand, model, serial number hash, custody information, insurance information, appraisal report hash, NFC binding, etc.
  - Supports freeze/unfreeze (such as redemption or abnormal risk control scenarios).
  - Records `tokenId → LuxShareToken` binding relationship.

### Securitized Tokens and Factory Layer

- **Core Contracts**
  - `LuxShareToken` / `ILuxShareToken`
  - `LuxShareFactory` / `ILuxShareFactory`
  - `TokenStorage`
- **Features**
  - `LuxShareToken` represents shares of a single luxury asset (similar to ERC3643), one-to-one correspondence with `LuxAssetNFT`.
  - Internally associates `IdentityRegistry` and corresponding `ModularCompliance`, performs compliance verification in `_beforeTokenTransfer`.
  - `LuxShareFactory` is responsible for:
    - Receiving an already certified `LuxAssetNFT` `tokenId`;
    - Deploying and initializing the corresponding `LuxShareToken`;
    - Minting all initial shares to the issuer's on-chain identity address;
    - Recording asset and token mappings for market/redemption/revenue contracts to query.

### Market Layer (Primary and Secondary Markets)

- **Core Contracts**
  - Primary market: `PrimaryOffering` / `IPrimaryOffering`
  - Secondary market: `P2PTrading` / `IP2PTrading`
  - General storage: `MarketStorage`
- **Primary Market (PrimaryOffering)**
  - Manages subscription periods: issuance price, subscription time window, sellable shares, payment tokens, etc.
  - Issuers create subscription orders here, qualified investors subscribe using specified ERC20 tokens.
  - Investors' paid ERC20 assets are stored in the primary market contract, issuers can extract them later.
  - After successful subscription, `LuxShareToken` is directly transferred from issuer identity address to subscriber identity address.
- **Secondary Market (P2PTrading)**
  - Provides peer-to-peer order book: sellers publish sell orders, specifying price and quantity.
  - Buyers can use specified ERC20 tokens to buy all or partial orders (for example, order has 1000 shares, buyer can buy only 100).
  - Still checks both parties' identities through `LuxShareToken`'s compliance checks during trading.
  - ERC20 tokens are transferred directly from buyer to seller, `LuxShareToken` is transferred directly from seller identity address to buyer identity address.

### Revenue Recording and Distribution Layer

- **Core Contracts**
  - `RevenueDistribution` / `IRevenueDistribution`
- **Features**
  - After issuers confirm revenues offline, transfer corresponding stablecoin and other revenue assets into `RevenueDistribution`.
  - Contract records holdings at a certain moment based on `LuxShareToken`'s snapshot mechanism (such as through `snapshot()` and `balanceOfAt()`).
  - Each revenue distribution generates a `distributionId`, recording:
    - Corresponding `shareToken`
    - `snapshotId`
    - Total reward amount `totalReward`
    - Total supply at snapshot `totalSharesAtSnapshot`
  - Investors can call `claim` at any time before expiration to receive their share of the current distribution:
    - Re-check current identity and compliance status before claiming.
    - Calculate claimable amount based on balance at snapshot moment.

### Redemption and Delivery Layer

- **Core Contracts**
  - `Redemption` / `IRedemption`
  - `RedemptionStorage`
- **Features**
  - Manages the complete redemption process from holding all `LuxShareToken` to obtaining `LuxAssetNFT`.
  - Supports issuers pre-registering certain assets into the redemption system (for direct redemption later).
  - After confirming investor holds all shares and identity is compliant:
    - Transfer all `LuxShareToken` to issuer or redemption contract address;
    - Check if shares equal `totalSupply` and execute `burn`;
    - Transfer corresponding `LuxAssetNFT` from issuer address to investor address;
    - Record redemption event to form on-chain audit trail.

---

## Complete Business Process (From 0 to 1)

### 1. Identity and Compliance Initialization (Admin + Issuer)

- **Admin**
  - Deploy and initialize:
    - `ClaimTopicsRegistry`
    - `TrustedIssuersRegistry`
    - `IdentityRegistryStorage`
    - `IdentityRegistry`
  - Configure required claim lists (such as KYC, AML, investor types, etc.).
  - Add offline audited issuer addresses to `TrustedIssuersRegistry` and configure their issuable claim types.
  - Add these issuers as system agents so they can add investors to the system.

- **Issuer**
  - Use `IdentityFactory` to create their own `Identity` / `InvestorIdentity`.
  - Add `CLAIM` permissions to themselves and issue required claims (such as "compliant asset issuance institution", etc.).
  - Create on-chain identities for their investors and require investors to add the issuer address as an issuer with `CLAIM` permissions in their own identities.
  - Issue KYC/AML/qualified investor claims to investors and register investor addresses and their country information in `IdentityRegistry`.

### 2. Compliance Center and Token Factory Deployment (Admin)

- Deploy `ModularCompliance` and various modules (`CountryAllowModule`, etc.), and bind modules to compliance center.
- Deploy `LuxAssetNFT`, `LuxShareFactory` and other token-related contracts.
- Associate corresponding `ModularCompliance` instances for each subsequent `LuxShareToken` (each Token has its own compliance center but can reuse module implementations).

### 3. Luxury Goods Registration and Securitization (Admin + Issuer)

- **Offline**: Issuer registers a luxury item with the system, completes authenticity, valuation, and other offline audits.
- **On-chain (executed by Admin through factory)**:
  - Use `LuxAssetNFT` to mint NFT for the luxury item, `tokenId` generated by the system, NFT sent directly to issuer's on-chain identity address.
  - Create corresponding `LuxShareToken` for the `tokenId` through `LuxShareFactory`:
    - Initialize properties such as name, symbol, total shares, redeemable or not;
    - Bind corresponding `IdentityRegistry` and `ModularCompliance`;
    - Mint all initial shares to issuer's on-chain identity address.
  - Register the asset into the redemption contract (`Redemption`) so investors can initiate redemption for this asset later.

### 4. Primary Market Subscription Process (Issuer + Investor)

- **Admin**
  - Deploy primary market contract `PrimaryOffering` and secondary market contract `P2PTrading`.
  - Associate them with core contracts such as `IdentityRegistry`, `LuxShareFactory`.
  - Add market contract addresses as agents in `LuxShareFactory` so they can operate relevant assets when needed.

- **Issuer creates subscription in primary market**
  - Select target `LuxShareToken`, configure subscription parameters:
    - Total sellable shares
    - Price per share (corresponding to some ERC20 payment token)
    - Subscription start/end time
  - `PrimaryOffering` validates issuer permissions and asset ownership, then creates subscription order.

- **Investor participates in subscription**
  - Ensure they have passed KYC/AML and are registered in `IdentityRegistry`.
  - Authorize payment amount to `PrimaryOffering` using the specified ERC20 token.
  - Call subscription function (such as `subscribe`):
    - Contract checks if they are qualified investors through `IdentityRegistry` / `ModularCompliance`.
    - Receives ERC20 tokens and records (funds stay in primary market contract, issuer extracts later).
    - Transfers corresponding amount of `LuxShareToken` from issuer identity address to subscriber identity address.

### 5. Secondary Market Free Trading (Investor ↔ Investor)

- Investors who have completed subscription and hold `LuxShareToken` can in `P2PTrading`:
  - As seller: publish sell orders, specifying sell quantity and accepted ERC20 token and price.
  - As buyer: eat orders as needed, all or partial (for example, order has 1000 shares, buy only 100 shares).
- Each trade will:
  - Check that both buyer and seller pass `IdentityRegistry` and compliance center checks.
  - Transfer ERC20 tokens directly from buyer to seller.
  - Transfer corresponding amount of `LuxShareToken` from seller identity address to buyer identity address.

### 6. Revenue Recording and Distribution

- **Issuer**
  - Corresponding luxury item generates revenue in the real world (rental, operating profits, insurance payouts, etc.).
  - After completing audit/confirmation offline, call `RevenueDistribution` on-chain:
    - Transfer the revenue amount in stablecoins into the revenue contract.
    - Specify corresponding `LuxShareToken` and revenue description (such as IPFS audit report hash).
    - Contract triggers `LuxShareToken` snapshot, records current holdings distribution.

- **Investor**
  - Can call `claim` at any time within the revenue distribution validity period:
    - Contract first checks current identity and compliance status;
    - Calculates claimable amount based on snapshot moment balance;
    - Transfers corresponding stablecoins to investor.

### 7. Physical Redemption Process

- Condition: A certain investor holds **all shares** of a certain `LuxShareToken` at a certain moment (usually meaning buyout or long-term collection).
- **Redemption Process Overview**
  - Investor initiates redemption application to `Redemption` contract;
  - Transfer all `LuxShareToken` (total supply) to specified address (usually issuer or redemption contract itself);
  - Check:
    - Whether held shares equal `totalSupply`;
    - Whether investor identity and country allow physical redemption;
  - After meeting conditions:
    - Execute `burn` to destroy all `LuxShareToken` shares;
    - Transfer corresponding `LuxAssetNFT` from issuer identity address to investor identity address;
    - Trigger redemption completion event for offline custody institutions to complete physical delivery accordingly.

---

## Project Structure Overview

(Only core directories listed, refer to source code for details)

- **`src/identity`**: Identity-related implementations and storage
  - `Identity.sol` / `InvestorIdentity.sol` / `ClaimIssuer.sol`
  - `IdentityFactory.sol`
  - `IdentityStorage.sol` and interfaces
- **`src/registry`**: Identity registration and trusted issuer management
  - `ClaimTopicsRegistry.sol`
  - `TrustedIssuersRegistry.sol`
  - `IdentityRegistry.sol` / `IdentityRegistryStorage.sol`
- **`src/compliance`**: Modular compliance center
  - `IModularCompliance.sol` / `IModule.sol`
  - `ModularCompliance.sol`
  - Modules: `CountryAllowModule.sol`, `CountryRestrictModule.sol`, etc.
- **`src/token`**: Physical NFT and share tokens
  - `LuxAssetNFT.sol` / `ILuxAssetNFT.sol`
  - `LuxShareToken.sol` / `ILuxShareToken.sol`
  - `LuxShareFactory.sol` / `ILuxShareFactory.sol`
  - `TokenStorage.sol`
- **`src/market`**: Markets, revenues and redemptions
  - `PrimaryOffering.sol` / `P2PTrading.sol`
  - `RevenueDistribution.sol`
  - `Redemption.sol`
  - Corresponding interfaces and `MarketStorage.sol` / `RedemptionStorage.sol`
- **`test`**: Foundry unit tests
  - `BaseFixture.sol`, `LuxRWAToken.t.sol`, `MarketTest.t.sol`
  - `Redemption.t.sol`, `RevenueDistribution.t.sol`, etc.

---

## Environment Preparation and Dependencies

- **Runtime Environment**
  - Solidity compiler version follows `foundry.toml`.
  - Latest version of Foundry toolchain recommended (`forge` / `cast` / `anvil`).
- **Install Foundry**
  - Refer to Foundry official documentation: [Foundry Book](https://book.getfoundry.sh/)
  - Brief installation commands (subject to official):

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

---

## Compilation and Testing

### Compile Contracts

```bash
forge build
```

### Run Tests

- Run all tests:

```bash
forge test
```

- Run only a single test file (such as market-related):

```bash
forge test --match-path test/MarketTest.t.sol
```