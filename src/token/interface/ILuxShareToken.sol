// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../../compliance/interface/IModularCompliance.sol";
import "../../registry/interface/IIdentityRegistry.sol";

/**
 * @title ILuxShareToken
 * @dev Interface for luxury asset security token (ERC3643 compliant)
 * @notice Security token representing fractional ownership of luxury assets
 */
interface ILuxShareToken {
    /// Events
    
    event ComplianceSet(address indexed compliance);
    event IdentityRegistrySet(address indexed identityRegistry);
    
    event AddressFrozen(address indexed addr, bool isFrozen, address indexed owner);
    event TokensFrozen(address indexed addr, uint256 amount);
    event TokensUnfrozen(address indexed addr, uint256 amount);
    
    event Paused(address indexed owner);
    event Unpaused(address indexed owner);
    
    /// Functions
    
    /**
     * @dev Initialize the share token
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param decimals_ Token decimals
     * @param identityRegistry_ Identity registry address
     * @param compliance_ Compliance module address
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address identityRegistry_,
        address compliance_
    ) external;
    
    /**
     * @dev Set the compliance module
     * @param compliance_ New compliance module address
     */
    function setCompliance(address compliance_) external;
    
    /**
     * @dev Set the identity registry
     * @param identityRegistry_ New identity registry address
     */
    function setIdentityRegistry(address identityRegistry_) external;
    
    /**
     * @dev Get underlying asset information
     * @return assetContract The asset NFT contract address
     * @return tokenId The asset token ID
     */
    function getUnderlyingAsset() external view returns (address assetContract, uint256 tokenId);
    
    /**
     * @dev Mint tokens (only for initial issuance)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external;
    
    /**
     * @dev Burn tokens
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external;
    
    /**
     * @dev Pause all token transfers
     */
    function pause() external;
    
    /**
     * @dev Unpause token transfers
     */
    function unpause() external;
    
    /**
     * @dev Check if contract is paused
     * @return paused Whether the contract is paused
     */
    function paused() external view returns (bool paused);
    
    /**
     * @dev Freeze an address
     * @param addr Address to freeze
     */
    function freezeAddress(address addr) external;
    
    /**
     * @dev Unfreeze an address
     * @param addr Address to unfreeze
     */
    function unfreezeAddress(address addr) external;
    
    /**
     * @dev Check if an address is frozen
     * @param addr Address to check
     * @return frozen Whether the address is frozen
     */
    function isFrozen(address addr) external view returns (bool frozen);
    
    /**
     * @dev Freeze partial tokens of an address
     * @param addr Address whose tokens to freeze
     * @param amount Amount to freeze
     */
    function freezePartialTokens(address addr, uint256 amount) external;
    
    /**
     * @dev Unfreeze partial tokens of an address
     * @param addr Address whose tokens to unfreeze
     * @param amount Amount to unfreeze
     */
    function unfreezePartialTokens(address addr, uint256 amount) external;
    
    /**
     * @dev Get frozen token amount of an address
     * @param addr Address to check
     * @return amount Frozen token amount
     */
    function getFrozenTokens(address addr) external view returns (uint256 amount);

    /**
     *  @dev force a transfer of tokens between 2 whitelisted wallets
     *  In case the `from` address has not enough free tokens (unfrozen tokens)
     *  but has a total balance higher or equal to the `amount`
     *  the amount of frozen tokens is reduced in order to have enough free tokens
     *  to proceed the transfer, in such a case, the remaining balance on the `from`
     *  account is 100% composed of frozen tokens post-transfer.
     *  Require that the `to` address is a verified address,
     *  @param _from The address of the sender
     *  @param _to The address of the receiver
     *  @param _amount The number of tokens to transfer
     *  @return `true` if successful and revert if unsuccessful
     *  This function can only be called by a wallet set as agent of the token
     *  emits a `TokensUnfrozen` event if `_amount` is higher than the free balance of `_from`
     *  emits a `Transfer` event
     */
    function forcedTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) external returns (bool);
    
    // ERC20 Standard Functions
    
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    
    // Compliance related views
    
    function compliance() external view returns (IModularCompliance);
    function identityRegistry() external view returns (IIdentityRegistry);
}

