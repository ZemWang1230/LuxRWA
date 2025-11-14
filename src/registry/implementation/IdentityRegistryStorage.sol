// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/IIdentityRegistryStorage.sol";
import "../storage/RegistryStorage.sol";
import "../../identity/interfaces/IIdentity.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IdentityRegistryStorage
 * @dev Implementation of IIdentityRegistryStorage using Diamond Storage pattern
 * @notice Stores investor identities and their country information
 */
contract IdentityRegistryStorage is IIdentityRegistryStorage, Ownable {
    using RegistryStorage for RegistryStorage.IdentityRegistryStorageLayout;

    /**
     * @dev Modifier to restrict access to bound identity registries
     */
    modifier onlyBoundRegistry() {
        RegistryStorage.IdentityRegistryStorageLayout storage s = RegistryStorage.identityRegistryStorageLayout();
        require(s.isRegistryBound[msg.sender], "IdentityRegistryStorage: caller is not a bound registry");
        _;
    }

    /**
     * @dev Constructor
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev adds an identity contract corresponding to a user address in the storage.
     * Requires that the user doesn't have an identity contract already registered.
     * This function can only be called by a bound identity registry
     * @param _userAddress The address of the user
     * @param _identity The address of the user's identity contract
     * @param _country The country of the investor
     * emits `IdentityStored` event
     */
    function addIdentityToStorage(
        address _userAddress,
        IIdentity _identity,
        uint16 _country
    ) external override onlyBoundRegistry {
        RegistryStorage.IdentityRegistryStorageLayout storage s = RegistryStorage.identityRegistryStorageLayout();
        
        require(_userAddress != address(0), "IdentityRegistryStorage: invalid user address");
        require(address(_identity) != address(0), "IdentityRegistryStorage: invalid identity address");
        require(!s.identityStored[_userAddress], "IdentityRegistryStorage: identity already stored");

        s.identities[_userAddress] = _identity;
        s.investorCountries[_userAddress] = _country;
        s.identityStored[_userAddress] = true;

        emit IdentityStored(_userAddress, _identity);
    }

    /**
     * @dev Removes an user from the storage.
     * Requires that the user have an identity contract already deployed that will be deleted.
     * This function can only be called by a bound identity registry
     * @param _userAddress The address of the user to be removed
     * emits `IdentityUnstored` event
     */
    function removeIdentityFromStorage(address _userAddress) external override onlyBoundRegistry {
        RegistryStorage.IdentityRegistryStorageLayout storage s = RegistryStorage.identityRegistryStorageLayout();
        
        require(s.identityStored[_userAddress], "IdentityRegistryStorage: identity not stored");

        IIdentity identity = s.identities[_userAddress];
        
        delete s.identities[_userAddress];
        delete s.investorCountries[_userAddress];
        delete s.identityStored[_userAddress];

        emit IdentityUnstored(_userAddress, identity);
    }

    /**
     * @dev Updates the country corresponding to a user address.
     * Requires that the user should have an identity contract already deployed that will be replaced.
     * This function can only be called by a bound identity registry
     * @param _userAddress The address of the user
     * @param _country The new country of the user
     * emits `CountryModified` event
     */
    function modifyStoredInvestorCountry(address _userAddress, uint16 _country) 
        external 
        override 
        onlyBoundRegistry 
    {
        RegistryStorage.IdentityRegistryStorageLayout storage s = RegistryStorage.identityRegistryStorageLayout();
        
        require(s.identityStored[_userAddress], "IdentityRegistryStorage: identity not stored");

        s.investorCountries[_userAddress] = _country;

        emit CountryModified(_userAddress, _country);
    }

    /**
     * @dev Updates an identity contract corresponding to a user address.
     * Requires that the user address should be the owner of the identity contract.
     * Requires that the user should have an identity contract already deployed that will be replaced.
     * This function can only be called by a bound identity registry
     * @param _userAddress The address of the user
     * @param _identity The address of the user's new identity contract
     * emits `IdentityModified` event
     */
    function modifyStoredIdentity(address _userAddress, IIdentity _identity) 
        external 
        override 
        onlyBoundRegistry 
    {
        RegistryStorage.IdentityRegistryStorageLayout storage s = RegistryStorage.identityRegistryStorageLayout();
        
        require(s.identityStored[_userAddress], "IdentityRegistryStorage: identity not stored");
        require(address(_identity) != address(0), "IdentityRegistryStorage: invalid identity address");
        require(_identity.owner() == _userAddress, "IdentityRegistryStorage: user is not identity owner");

        IIdentity oldIdentity = s.identities[_userAddress];
        s.identities[_userAddress] = _identity;

        emit IdentityModified(oldIdentity, _identity);
    }

    /**
     * @notice Adds an identity registry as agent of the Identity Registry Storage Contract.
     * This function can only be called by the wallet set as owner of the smart contract
     * This function adds the identity registry to the list of identityRegistries linked to the storage contract
     * cannot bind more than 300 IR to 1 IRS
     * @param _identityRegistry The identity registry address to add.
     */
    function bindIdentityRegistry(address _identityRegistry) external override onlyOwner {
        RegistryStorage.IdentityRegistryStorageLayout storage s = RegistryStorage.identityRegistryStorageLayout();
        
        require(_identityRegistry != address(0), "IdentityRegistryStorage: invalid registry address");
        require(!s.isRegistryBound[_identityRegistry], "IdentityRegistryStorage: registry already bound");
        require(s.identityRegistries.length < 300, "IdentityRegistryStorage: cannot bind more than 300 registries");

        s.identityRegistries.push(_identityRegistry);
        s.isRegistryBound[_identityRegistry] = true;

        emit IdentityRegistryBound(_identityRegistry);
    }

    /**
     * @notice Removes an identity registry from being agent of the Identity Registry Storage Contract.
     * This function can only be called by the wallet set as owner of the smart contract
     * This function removes the identity registry from the list of identityRegistries linked to the storage contract
     * @param _identityRegistry The identity registry address to remove.
     */
    function unbindIdentityRegistry(address _identityRegistry) external override onlyOwner {
        RegistryStorage.IdentityRegistryStorageLayout storage s = RegistryStorage.identityRegistryStorageLayout();
        
        require(s.isRegistryBound[_identityRegistry], "IdentityRegistryStorage: registry not bound");

        // Find and remove the registry from the array
        uint256 length = s.identityRegistries.length;
        for (uint256 i = 0; i < length; i++) {
            if (s.identityRegistries[i] == _identityRegistry) {
                s.identityRegistries[i] = s.identityRegistries[length - 1];
                s.identityRegistries.pop();
                break;
            }
        }

        delete s.isRegistryBound[_identityRegistry];

        emit IdentityRegistryUnbound(_identityRegistry);
    }

    /**
     * @dev Returns the identity registries linked to the storage contract
     */
    function linkedIdentityRegistries() external view override returns (address[] memory) {
        return RegistryStorage.identityRegistryStorageLayout().identityRegistries;
    }

    /**
     * @dev Returns the onchainID of an investor.
     * @param _userAddress The wallet of the investor
     */
    function storedIdentity(address _userAddress) external view override returns (IIdentity) {
        return RegistryStorage.identityRegistryStorageLayout().identities[_userAddress];
    }

    /**
     * @dev Returns the country code of an investor.
     * @param _userAddress The wallet of the investor
     */
    function storedInvestorCountry(address _userAddress) external view override returns (uint16) {
        return RegistryStorage.identityRegistryStorageLayout().investorCountries[_userAddress];
    }
}

