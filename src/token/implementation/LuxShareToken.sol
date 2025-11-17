// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/ILuxShareToken.sol";
import "../storage/TokenStorage.sol";
import "../../compliance/interface/IModularCompliance.sol";
import "../../registry/interface/IIdentityRegistry.sol";

/**
 * @title LuxShareToken
 * @dev Implementation of ERC3643-compliant security token using Diamond Storage
 * @notice Security token representing fractional ownership of luxury assets
 * @notice Factory-centric design: critical functions can only be called by factory
 * @notice Reference: T-REX ERC-3643 standard
 */
contract LuxShareToken is ILuxShareToken {
    using TokenStorage for TokenStorage.ShareTokenLayout;

    // ERC20 events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    modifier onlyFactory() {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        require(msg.sender == s.factory, "LuxShareToken: caller is not the factory");
        _;
    }

    /**
     * @dev Constructor sets the factory address
     * @param factory_ The address of the factory contract
     */
    constructor(address factory_) {
        require(factory_ != address(0), "LuxShareToken: invalid factory address");
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        s.factory = factory_;
    }

    // ==================== Initialization (Factory-Only) ====================

    /**
     * @dev Initialize the share token (can only be called once by factory)
     * @param name_ The name of the token
     * @param symbol_ The symbol of the token
     * @param decimals_ The decimals of the token
     * @param identityRegistry_ The address of the identity registry
     * @param compliance_ The address of the compliance module
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address identityRegistry_,
        address compliance_
    ) external override onlyFactory {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        require(!s.initialized, "LuxShareToken: already initialized");
        require(identityRegistry_ != address(0), "LuxShareToken: invalid identity registry");
        require(compliance_ != address(0), "LuxShareToken: invalid compliance");

        s.name = name_;
        s.symbol = symbol_;
        s.decimals = decimals_;
        s.identityRegistry = IIdentityRegistry(identityRegistry_);
        s.compliance = IModularCompliance(compliance_);
        s.paused = false;
        s.initialized = true;
    }

    // ==================== Factory-Only Configuration ====================

    /**
     * @dev Set underlying asset information (can only be called once by factory)
     * @param assetNFTContract_ The address of the asset NFT contract
     * @param assetId_ The ID of the asset
     * @param shareClass_ The class of shares
     * @param redeemable_ Whether the shares are redeemable
     */
    function setUnderlyingAsset(
        address assetNFTContract_, 
        uint256 assetId_,
        string memory shareClass_,
        bool redeemable_
    ) external onlyFactory {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        require(s.assetNFTContract == address(0), "LuxShareToken: underlying asset already set");
        s.assetNFTContract = assetNFTContract_;
        s.underlyingAssetId = assetId_;
        s.shareClass = shareClass_;
        s.redeemable = redeemable_;
    }

    /**
     * @dev Set the compliance module (only factory can set)
     * @param compliance_ The address of the compliance module
     */
    function setCompliance(address compliance_) external override onlyFactory {
        require(compliance_ != address(0), "LuxShareToken: invalid compliance");
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        s.compliance = IModularCompliance(compliance_);
        emit ComplianceSet(compliance_);
    }

    /**
     * @dev Set the identity registry (only factory can set)
     * @param identityRegistry_ The address of the identity registry
     */
    function setIdentityRegistry(address identityRegistry_) external override onlyFactory {
        require(identityRegistry_ != address(0), "LuxShareToken: invalid identity registry");
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        s.identityRegistry = IIdentityRegistry(identityRegistry_);
        emit IdentityRegistrySet(identityRegistry_);
    }

    // ==================== Factory-Only Token Management ====================

    /**
     * @dev Mint tokens (only factory can mint)
     * @param to The user address to mint the tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external override onlyFactory {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        address toIdentity = address(s.identityRegistry.identity(to));
        require(toIdentity != address(0), "LuxShareToken: recipient not found");

        require(!s.paused, "LuxShareToken: token is paused");
        require(s.identityRegistry.isVerified(to), "LuxShareToken: recipient not verified");

        s.totalSupply += amount;
        s.balances[toIdentity] += amount;

        // Notify compliance
        if (address(s.compliance) != address(0)) {
            s.compliance.created(toIdentity, amount);
        }

        emit Transfer(address(0), toIdentity, amount);
    }

    /**
     * @dev Burn tokens (only factory can burn)
     * @param from The user address to burn the tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) external override onlyFactory {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        address fromIdentity = address(s.identityRegistry.identity(from));
        require(fromIdentity != address(0), "LuxShareToken: sender not found");
        
        require(s.balances[fromIdentity] >= amount, "LuxShareToken: burn amount exceeds balance");

        s.balances[fromIdentity] -= amount;
        s.totalSupply -= amount;

        // Notify compliance
        if (address(s.compliance) != address(0)) {
            s.compliance.destroyed(fromIdentity, amount);
        }

        emit Transfer(fromIdentity, address(0), amount);
    }

    /**
     * @dev Pause all token transfers (only factory can pause)
     */
    function pause() external override onlyFactory {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        require(!s.paused, "LuxShareToken: already paused");
        s.paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev Unpause token transfers (only factory can unpause)
     */
    function unpause() external override onlyFactory {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        require(s.paused, "LuxShareToken: not paused");
        s.paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @dev Freeze an address (only factory can freeze)
     * @param addr The user address to freeze
     */
    function freezeAddress(address addr) external override onlyFactory {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        address addrIdentity = address(s.identityRegistry.identity(addr));
        require(addrIdentity != address(0), "LuxShareToken: address not found");
        require(!s.frozen[addrIdentity], "LuxShareToken: address already frozen");
        
        s.frozen[addrIdentity] = true;
        emit AddressFrozen(addrIdentity, true, msg.sender);
    }

    /**
     * @dev Unfreeze an address (only factory can unfreeze)
     * @param addr The user address to unfreeze
    */
    function unfreezeAddress(address addr) external override onlyFactory {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        address addrIdentity = address(s.identityRegistry.identity(addr));
        require(addrIdentity != address(0), "LuxShareToken: address not found");
        require(s.frozen[addrIdentity], "LuxShareToken: address not frozen");
        
        s.frozen[addrIdentity] = false;
        emit AddressFrozen(addrIdentity, false, msg.sender);
    }

    /**
     * @dev Freeze partial tokens of an address (only factory can freeze)
     * @param addr The user address to freeze
     * @param amount The amount of tokens to freeze
     */
    function freezePartialTokens(address addr, uint256 amount) external override onlyFactory {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        address addrIdentity = address(s.identityRegistry.identity(addr));
        require(addrIdentity != address(0), "LuxShareToken: address not found");
        require(s.balances[addrIdentity] >= s.frozenTokens[addrIdentity] + amount, "LuxShareToken: insufficient balance to freeze");
        
        s.frozenTokens[addrIdentity] += amount;
        emit TokensFrozen(addrIdentity, amount);
    }

    /**
     * @dev Unfreeze partial tokens of an address (only factory can unfreeze)
     * @param addr The user address to unfreeze
     * @param amount The amount of tokens to unfreeze
     */
    function unfreezePartialTokens(address addr, uint256 amount) external override onlyFactory {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        address addrIdentity = address(s.identityRegistry.identity(addr));
        require(addrIdentity != address(0), "LuxShareToken: address not found");
        require(s.frozenTokens[addrIdentity] >= amount, "LuxShareToken: insufficient frozen tokens");
        
        s.frozenTokens[addrIdentity] -= amount;
        emit TokensUnfrozen(addrIdentity, amount);
    }

    /**
     * @dev Force a transfer of tokens between 2 addresses (only factory can force transfer)
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @param amount The amount of tokens to transfer
     * @return success Whether the transfer was successful
     */
    function forcedTransfer(address from, address to, uint256 amount) external override onlyFactory returns (bool) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        address fromIdentity = address(s.identityRegistry.identity(from));
        address toIdentity = address(s.identityRegistry.identity(to));
        require(fromIdentity != address(0), "LuxShareToken: sender not found");
        require(toIdentity != address(0), "LuxShareToken: recipient not found");
        require(amount > 0, "LuxShareToken: transfer amount is zero");
        require(s.balances[fromIdentity] >= amount, "LuxShareToken: transfer amount exceeds balance");
        
        // For forced transfer, we can unfreeze tokens if needed
        uint256 availableBalance = s.balances[fromIdentity] - s.frozenTokens[fromIdentity];
        if (availableBalance < amount) {
            uint256 tokensToUnfreeze = amount - availableBalance;
            s.frozenTokens[fromIdentity] -= tokensToUnfreeze;
            emit TokensUnfrozen(fromIdentity, tokensToUnfreeze);
        }
        
        // Verify recipient identity
        require(s.identityRegistry.isVerified(to), "LuxShareToken: recipient not verified");
        
        // Perform transfer
        s.balances[fromIdentity] -= amount;
        s.balances[toIdentity] += amount;
        
        // Notify compliance
        s.compliance.transferred(fromIdentity, toIdentity, amount);
        
        emit Transfer(fromIdentity, toIdentity, amount);
        return true;
    }

    // ==================== View Functions ====================

    /**
     * @dev Get underlying asset information
     * @return assetContract The address of the asset NFT contract
     * @return tokenId The ID of the asset
     */
    function getUnderlyingAsset() external view override returns (address assetContract, uint256 tokenId) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        return (s.assetNFTContract, s.underlyingAssetId);
    }

    /**
     * @dev Check if contract is paused
     * @return paused Whether the contract is paused
     */
    function paused() external view override returns (bool) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        return s.paused;
    }

    /**
     * @dev Check if an address is frozen
     * @param addr The user address to check
     * @return frozen Whether the address is frozen
     */
    function isFrozen(address addr) public view override returns (bool) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        address addrIdentity = address(s.identityRegistry.identity(addr));
        return s.frozen[addrIdentity];
    }

    /**
     * @dev Get frozen token amount of an address
     * @param addr The user address to check
     * @return amount The amount of frozen tokens
     */
    function getFrozenTokens(address addr) external view override returns (uint256) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        address addrIdentity = address(s.identityRegistry.identity(addr));
        return s.frozenTokens[addrIdentity];
    }

    /**
     * @dev Get the compliance module
     * @return compliance The compliance module
     */
    function compliance() external view override returns (IModularCompliance) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        return s.compliance;
    }

    /**
     * @dev Get the identity registry
     * @return identityRegistry The identity registry
     */
    function identityRegistry() external view override returns (IIdentityRegistry) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        return s.identityRegistry;
    }

    /**
     * @dev Get the factory address
     * @return factory The factory address
     */
    function factory() external view returns (address) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        return s.factory;
    }

    /**
     * @dev Get share class
     * @return shareClass The share class
     */
    function shareClass() external view returns (string memory) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        return s.shareClass;
    }

    /**
     * @dev Check if shares are redeemable
     * @return redeemable Whether shares are redeemable
     */
    function isRedeemable() external view returns (bool) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        return s.redeemable;
    }

    // ==================== ERC20 Standard Implementation ====================

    /**
     * @dev Get the name of the token
     * @return name The name of the token
     */
    function name() external view override returns (string memory) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        return s.name;
    }

    /**
     * @dev Get the symbol of the token
     * @return symbol The symbol of the token
     */
    function symbol() external view override returns (string memory) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        return s.symbol;
    }

    /**
     * @dev Get the decimals of the token
     * @return decimals The decimals of the token
     */
    function decimals() external view override returns (uint8) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        return s.decimals;
    }

    /**
     * @dev Get the total supply of the token
     * @return totalSupply The total supply of the token
     */
    function totalSupply() external view override returns (uint256) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        return s.totalSupply;
    }

    /**
     * @dev Get the balance of an address
     * @param account The user address to get the balance of
     * @return balance The balance of the address
     */
    function balanceOf(address account) external view override returns (uint256) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        address accountIdentity = address(s.identityRegistry.identity(account));
        return s.balances[accountIdentity];
    }

    /**
     * @dev Transfer tokens to an address
     * @param to The user address to transfer to
     * @param amount The amount of tokens to transfer
     * @return success Whether the transfer was successful
     */
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @dev Get the allowance of an address
     * @param owner_ The user address to get the allowance of
     * @param spender The user address to get the allowance of
     * @return allowance The allowance of the address
     */
    function allowance(address owner_, address spender) external view override returns (uint256) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        address ownerIdentity = address(s.identityRegistry.identity(owner_));
        address spenderIdentity = address(s.identityRegistry.identity(spender));
        return s.allowances[ownerIdentity][spenderIdentity];
    }

    /**
     * @dev Approve an address to spend tokens
     * @param spender The user address to approve
     * @param amount The amount of tokens to approve
     * @return success Whether the approval was successful
     */
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev Transfer tokens from one address to another
     * @param from The user address to transfer from
     * @param to The user address to transfer to
     * @param amount The amount of tokens to transfer
     * @return success Whether the transfer was successful
     */
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        
        address fromIdentity = address(s.identityRegistry.identity(from));
        address msgSenderIdentity = address(s.identityRegistry.identity(msg.sender));
        uint256 currentAllowance = s.allowances[fromIdentity][msgSenderIdentity];
        require(currentAllowance >= amount, "LuxShareToken: insufficient allowance");
        
        unchecked {
            _approve(from, msg.sender, currentAllowance - amount);
        }
        
        _transfer(from, to, amount);
        return true;
    }

    // ==================== Internal Functions ====================

    /**
     * @dev Transfer tokens from one address to another
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @param amount The amount of tokens to transfer
     */
    function _transfer(address from, address to, uint256 amount) internal {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        address fromIdentity = address(s.identityRegistry.identity(from));
        address toIdentity = address(s.identityRegistry.identity(to));
        require(fromIdentity != address(0), "LuxShareToken: sender not found");
        require(toIdentity != address(0), "LuxShareToken: recipient not found");

        // Check pause status
        require(!s.paused, "LuxShareToken: token is paused");
        
        // Check frozen status
        require(!s.frozen[fromIdentity], "LuxShareToken: sender is frozen");
        require(!s.frozen[toIdentity], "LuxShareToken: recipient is frozen");
        
        // Check balance and frozen tokens
        uint256 availableBalance = s.balances[fromIdentity] - s.frozenTokens[fromIdentity];
        require(availableBalance >= amount, "LuxShareToken: transfer amount exceeds available balance");

        // Compliance checks
        require(s.identityRegistry.isVerified(to), "LuxShareToken: recipient not verified");
        require(s.compliance.canTransfer(from, to, amount), "LuxShareToken: transfer not compliant");

        // Perform transfer
        s.balances[fromIdentity] -= amount;
        s.balances[toIdentity] += amount;

        // Notify compliance
        s.compliance.transferred(fromIdentity, toIdentity, amount);

        emit Transfer(fromIdentity, toIdentity, amount);
    }

    /**
     * @dev Approve an address to spend tokens
     * @param owner_ The user address to approve from
     * @param spender The user address to approve
     * @param amount The amount of tokens to approve
     */
    function _approve(address owner_, address spender, uint256 amount) internal {
        TokenStorage.ShareTokenLayout storage s = TokenStorage.shareTokenLayout();
        address ownerIdentity = address(s.identityRegistry.identity(owner_));
        address spenderIdentity = address(s.identityRegistry.identity(spender));

        require(ownerIdentity != address(0), "LuxShareToken: approve from not found");
        require(spenderIdentity != address(0), "LuxShareToken: approve to not found");

        s.allowances[ownerIdentity][spenderIdentity] = amount;
        
        emit Approval(ownerIdentity, spenderIdentity, amount);
    }
}
