## LuxRWA：奢侈品实物资产链上证券化协议

LuxRWA 是一套面向奢侈品实物资产的链上证券化基础设施，通过统一的 ERC721 实物确权与 ERC3643 风格的份额代币（ShareToken），将传统上非标准、非流动、难以审计的奢侈品资产转化为可分割、可合规交易、可自动分红并可赎回实物的链上证券化资产。

整个系统围绕「**实物确权 → 份额发行 → 合规交易 → 收益分配 → 实物赎回**」这一完整生命周期设计，并与 OnChainID / T-REX 身份与合规体系深度兼容。

---

## 项目特点

- **统一实物确权**：所有奢侈品通过单一的 `LuxAssetNFT` 合约确权，每件实物映射为一个 `tokenId`，元数据结构统一，可扩展性强。
- **ERC3643 风格证券化代币**：每件奢侈品对应一个独立的 `LuxShareToken`，兼容 ERC20 接口并在转账前强制进行身份与合规检查。
- **模块化合规引擎**：基于 `ModularCompliance` + 多个合规模块（国家限制、白名单、锁仓等），每个 `LuxShareToken` 拥有自己的合规中心但可以复用模块。
- **完整身份体系复用**：发行商与投资者均通过 OnChainID 风格的 `Identity` / `InvestorIdentity` 管理，合规检查统一复用 `IdentityRegistry`。
- **一、二级市场闭环**：通过 `PrimaryOffering`（一级认购）和 `P2PTrading`（二级 P2P 订单簿）实现从初始认购到自由交易的完整市场闭环。
- **收益分配与快照机制**：`RevenueDistribution` 使用快照机制记录某一时刻持仓，并按份额自动计算收益，可按需领取且领取时重跑合规。
- **实物赎回闭环**：`Redemption` 合约在投资者持有全部份额时，执行份额锁定与销毁，并将对应 `LuxAssetNFT` 从发行商转移给投资者，完成链上到实物的闭环交割。

---

## 系统角色

- **Admin（平台管理员）**
  - 部署并初始化身份/合规/代币工厂/市场/收益/赎回等核心合约。
  - 配置必需的 claim 列表、可信发行商、可颁发的 claim 类型。
  - 作为各合约的最高权限角色，负责绑定模块、设置 agent 等。

- **Issuer（发行商）**
  - 为自己和投资者创建链上身份（通过 `IdentityFactory`）。
  - 自行添加 `CLAIM` 权限，并给自己颁发合规相关的 claim。
  - 为其投资者颁发 KYC/AML/合格投资者等 claim，并将投资者注册进 `IdentityRegistry`。
  - 持有对应奢侈品的 `LuxAssetNFT` 与初始全部 `LuxShareToken` 份额。
  - 在一级市场创建认购订单，在收益分配合约中登记收益，并注册支持赎回的资产。

- **Investor（投资者）**
  - 由发行商为其创建链上身份，并将对应发行商地址添加为具有 `CLAIM` 权限的 issuer。
  - 接收发行商颁发的 KYC/AML/投资者类型等 claim，并被注册进 `IdentityRegistry`。
  - 在一级市场认购 `LuxShareToken`，在二级市场进行 P2P 交易，按份额领取收益，并在持有全部份额时发起赎回。

---

## 合约与模块架构

### 身份与合规基础层

- **核心合约**
  - `Identity` / `InvestorIdentity` / `ClaimIssuer`
  - `ClaimTopicsRegistry` / `TrustedIssuersRegistry`
  - `IdentityRegistry` / `IdentityRegistryStorage`
- **特点**
  - 提供基于 ERC734/735 的可扩展身份系统。
  - 通过 `ClaimTopicsRegistry` 定义平台级必需 claim（如 KYC、AML）。
  - `TrustedIssuersRegistry` 记录可信发行商与其可颁发的 topic。
  - `IdentityRegistry` 在每次转账前检查地址是否拥有必要 claim，并记录投资者国家。

### 合规规则模块层

- **核心合约**
  - `IModularCompliance` / `IModule`
  - `ModularCompliance`
  - 模块合约：`CountryAllowModule`、`CountryRestrictModule` 等
- **特点**
  - 为每个 `LuxShareToken` 部署一个 `ModularCompliance` 实例，作为该 Token 的“合规管理中心”。
  - 不同的模块可叠加组合：地域限制、黑/白名单、锁定期、持仓上限等。
  - 在 `LuxShareToken` 的转账钩子中调用合规中心，未通过检查的转账会被拒绝。

### 实物确权层

- **核心合约**
  - `LuxAssetNFT`（实现） / `ILuxAssetNFT`（接口）
- **特点**
  - 单一 ERC721 合约管理平台内所有奢侈品，每件实物对应一个 `tokenId`。
  - 存储品牌、型号、序列号哈希、托管信息、保险信息、鉴定报告哈希、NFC 绑定等关键元数据。
  - 支持冻结/解冻（如赎回或异常风控场景）。
  - 记录 `tokenId → LuxShareToken` 绑定关系。

### 证券化代币与工厂层

- **核心合约**
  - `LuxShareToken` / `ILuxShareToken`
  - `LuxShareFactory` / `ILuxShareFactory`
  - `TokenStorage`
- **特点**
  - `LuxShareToken` 代表单一奢侈品资产的份额（类似 ERC3643），与 `LuxAssetNFT` 一一对应。
  - 内部关联 `IdentityRegistry` 与对应的 `ModularCompliance`，在 `_beforeTokenTransfer` 中执行合规校验。
  - `LuxShareFactory` 负责：
    - 接收一个已确权的 `LuxAssetNFT` `tokenId`；
    - 部署并初始化对应的 `LuxShareToken`；
    - 将全部初始份额铸造给发行商的链上身份地址；
    - 记录资产与 Token 的映射，供市场/赎回/收益等合约查询。

### 市场层（一二级市场）

- **核心合约**
  - 一级市场：`PrimaryOffering` / `IPrimaryOffering`
  - 二级市场：`P2PTrading` / `IP2PTrading`
  - 通用存储：`MarketStorage`
- **一级市场（PrimaryOffering）**
  - 管理认购档期：发行价格、认购时间窗、可售份额、支付代币等。
  - 发行商在此创建认购订单，合格投资者使用指定 ERC20 代币认购。
  - 投资者支付的 ERC20 资产存放在一级市场合约中，发行商可后续提取。
  - 认购成功后，`LuxShareToken` 直接从发行商身份地址转给认购者身份地址。
- **二级市场（P2PTrading）**
  - 提供点对点订单簿：卖方发布出售订单，指定价格与数量。
  - 买方可以使用指定 ERC20 代币按订单购买全部或部分份额（例如订单 1000 份，可只买 100）。
  - 交易时仍通过 `LuxShareToken` 的合规检查，确保双方身份合规。
  - 付款的 ERC20 直接从买方转到卖方，`LuxShareToken` 直接从卖方身份地址转到买方身份地址。

### 收益记录与分配层

- **核心合约**
  - `RevenueDistribution` / `IRevenueDistribution`
- **特点**
  - 发行商在链下确认收益后，将对应稳定币等收益资产转入 `RevenueDistribution`。
  - 合约基于 `LuxShareToken` 的快照机制记录某一时刻持仓（如通过 `snapshot()` 与 `balanceOfAt()`）。
  - 每次收益分配生成一个 `distributionId`，记录：
    - 对应的 `shareToken`
    - `snapshotId`
    - 总收益金额 `totalReward`
    - 快照时总供应 `totalSharesAtSnapshot`
  - 投资者可在到期前任何时间调用 `claim` 领取当前分配中属于自己的收益：
    - 领取前再次通过 `IdentityRegistry` / `ModularCompliance` 检查当前合规状态。

### 赎回与交付层

- **核心合约**
  - `Redemption` / `IRedemption`
  - `RedemptionStorage`
- **特点**
  - 管理从持有全部 `LuxShareToken` 到获得 `LuxAssetNFT` 的完整赎回流程。
  - 支持发行商预先将某些资产注册进赎回系统（以便后续直接赎回）。
  - 在确认投资者持有全部份额且身份合规后：
    - 将全部 `LuxShareToken` 转移到发行商或赎回合约地址；
    - 检查是否为全部份额并执行 `burn`；
    - 将对应的 `LuxAssetNFT` 从发行商地址转给投资者；
    - 记录赎回事件，形成链上审计轨迹。

---

## 完整业务流程（从 0 到 1）

### 1. 身份与合规初始化（Admin + Issuer）

- **Admin**
  - 部署并初始化：
    - `ClaimTopicsRegistry`
    - `TrustedIssuersRegistry`
    - `IdentityRegistryStorage`
    - `IdentityRegistry`
  - 配置必需 claim 列表（如 KYC、AML、投资者类型等）。
  - 将线下已审核的发行商地址添加到 `TrustedIssuersRegistry` 中，并配置其可颁发的 claim 类型。
  - 将这些发行商添加为系统 agent，以便它们能将投资者加入系统。

- **Issuer**
  - 使用 `IdentityFactory` 创建自身的 `Identity` / `InvestorIdentity`。
  - 为自身添加 `CLAIM` 权限，并给自己颁发所需 claim（如“合规资产发行机构”等）。
  - 为其投资者创建链上身份，并要求投资者在自己的身份中将该发行商地址添加为具有 `CLAIM` 权限的 issuer。
  - 向投资者颁发 KYC/AML/投资者类型等 claim，并在 `IdentityRegistry` 中注册投资者地址及其国家信息。

### 2. 合规中心与代币工厂部署（Admin）

- 部署 `ModularCompliance` 与各类模块（`CountryAllowModule` 等），并将模块绑定到合规中心。
- 部署 `LuxAssetNFT`、`LuxShareFactory` 等代币相关合约。
- 为后续每个 `LuxShareToken` 关联对应的 `ModularCompliance` 实例（每个 Token 有自己的合规中心，但可以复用模块实现）。

### 3. 奢侈品登记与证券化（Admin + Issuer）

- **线下**：发行商向系统登记一件奢侈品，完成真实性、估值等线下审核。
- **链上（由 Admin 通过工厂执行）**：
  - 使用 `LuxAssetNFT` 为该奢侈品铸造 NFT，`tokenId` 由系统生成，NFT 直接发送到发行商的链上身份地址。
  - 通过 `LuxShareFactory` 为该 `tokenId` 创建对应的 `LuxShareToken`：
    - 初始化名称、符号、总份额、是否可赎回等属性；
    - 绑定对应 `IdentityRegistry` 和 `ModularCompliance`；
    - 将全部初始份额铸造到发行商的链上身份地址。
  - 将该资产注册进赎回合约（`Redemption`），以便后续投资者可以对该资产发起赎回。

### 4. 一级市场认购流程（Issuer + Investor）

- **Admin**
  - 部署一级市场合约 `PrimaryOffering` 与二级市场合约 `P2PTrading`。
  - 将其与 `IdentityRegistry`、`LuxShareFactory` 等核心合约关联。
  - 在 `LuxShareFactory` 中将市场合约地址添加为 agent，使其在需要时能操作相关资产。

- **Issuer 在一级市场创建认购**
  - 选择目标 `LuxShareToken`，配置认购参数：
    - 可售总份额
    - 每份价格（对应某种 ERC20 支付代币）
    - 认购开始/结束时间
  - `PrimaryOffering` 验证发行商权限与资产所有权后，创建认购订单。

- **Investor 参与认购**
  - 确保自身已通过 KYC/AML，并在 `IdentityRegistry` 中注册。
  - 使用被指定的 ERC20 代币，对 `PrimaryOffering` 授权支付额度。
  - 调用认购函数（如 `subscribe`）：
    - 合约通过 `IdentityRegistry` / `ModularCompliance` 检查其是否为合格投资者。
    - 接收 ERC20 代币并记账（资金留存在一级市场合约中，发行商后续提取）。
    - 将对应数量的 `LuxShareToken` 从发行商身份地址直接转移给投资者身份地址。

### 5. 二级市场自由交易（Investor ↔ Investor）

- 已完成认购并持有 `LuxShareToken` 的投资者可以在 `P2PTrading` 中：
  - 作为卖方：发布出售订单，指定出售数量和接受的 ERC20 代币与价格。
  - 作为买方：按需部分/全部吃单（例如订单 1000 份，只买 100 份）。
- 每笔交易会：
  - 检查买卖双方是否通过 `IdentityRegistry` 与合规中心的检查。
  - 将 ERC20 代币从买方直接转到卖方。
  - 将对应数量的 `LuxShareToken` 从卖方身份地址直接转到买方身份地址。

### 6. 收益记录与分配

- **Issuer**
  - 对应奢侈品在现实世界产生收益（租赁、经营利润、保险赔付等）。
  - 在线下完成审计/确认后，在链上调用 `RevenueDistribution`：
    - 将本次收益金额的稳定币转入收益合约。
    - 指定对应的 `LuxShareToken` 及收益说明（如 IPFS 审计报告哈希）。
    - 合约触发 `LuxShareToken` 快照，记录此时的持仓分布。

- **Investor**
  - 在收益分配有效期内，可随时调用 `claim`：
    - 合约先检查当前身份与合规状态；
    - 依据快照时刻余额计算本次可领取金额；
    - 将相应稳定币转给投资者。

### 7. 实物赎回流程

- 条件：某一投资者在某一时刻持有某 `LuxShareToken` 的**全部份额**（通常意味着 buyout 或长期收集）。
- **赎回步骤概览**
  - 投资者向 `Redemption` 合约发起赎回申请；
  - 将全部 `LuxShareToken`（总供应）转移到指定地址（通常为发行商或赎回合约本身）；
  - 检查：
    - 持有份额是否等于 `totalSupply`；
    - 投资者身份与国家是否允许实物赎回；
  - 满足条件后：
    - 执行 `burn`，销毁全部 `LuxShareToken` 份额；
    - 将对应的 `LuxAssetNFT` 从发行商身份地址转移到投资者身份地址；
    - 触发赎回完成事件，用于链下托管机构据此完成实物交付。

---

## 项目结构概览

（仅列出核心目录，详细请参考源码）

- **`src/identity`**：身份相关实现与存储
  - `Identity.sol` / `InvestorIdentity.sol` / `ClaimIssuer.sol`
  - `IdentityFactory.sol`
  - `IdentityStorage.sol` 及接口
- **`src/registry`**：身份注册与可信发行商管理
  - `ClaimTopicsRegistry.sol`
  - `TrustedIssuersRegistry.sol`
  - `IdentityRegistry.sol` / `IdentityRegistryStorage.sol`
- **`src/compliance`**：模块化合规中心
  - `IModularCompliance.sol` / `IModule.sol`
  - `ModularCompliance.sol`
  - 模块：`CountryAllowModule.sol`、`CountryRestrictModule.sol` 等
- **`src/token`**：实物 NFT 与份额 Token
  - `LuxAssetNFT.sol` / `ILuxAssetNFT.sol`
  - `LuxShareToken.sol` / `ILuxShareToken.sol`
  - `LuxShareFactory.sol` / `ILuxShareFactory.sol`
  - `TokenStorage.sol`
- **`src/market`**：市场、收益与赎回
  - `PrimaryOffering.sol` / `P2PTrading.sol`
  - `RevenueDistribution.sol`
  - `Redemption.sol`
  - 对应接口与 `MarketStorage.sol` / `RedemptionStorage.sol`
- **`test`**：Foundry 单元测试
  - `BaseFixture.sol`、`LuxRWAToken.t.sol`、`MarketTest.t.sol`
  - `Redemption.t.sol`、`RevenueDistribution.t.sol` 等

---

## 环境准备与依赖

- **运行环境**
  - Solidity 编译器版本以 `foundry.toml` 为准。
  - 推荐使用最新版 Foundry 工具链（`forge` / `cast` / `anvil`）。
- **安装 Foundry**
  - 参考 Foundry 官方文档：[Foundry Book](https://book.getfoundry.sh/)
  - 简要安装命令（以官方为准）：

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

---

## 编译与测试

### 编译合约

```bash
forge build
```

### 运行测试

- 运行全部测试：

```bash
forge test
```

- 仅运行单个测试文件（例如市场相关）：

```bash
forge test --match-path test/MarketTest.t.sol
```