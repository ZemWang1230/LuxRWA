// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/IIdentityRegistry.sol";
import "../interface/IClaimTopicsRegistry.sol";
import "../interface/ITrustedIssuersRegistry.sol";
import "../interface/IIdentityRegistryStorage.sol";
import "../storage/RegistryStorage.sol";
import "../../identity/interfaces/IIdentity.sol";
import "../../identity/interfaces/IClaimIssuer.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IdentityRegistry
 * @dev Implementation of IIdentityRegistry using Diamond Storage pattern
 * @notice Main registry for managing investor identities and verification
 */
contract IdentityRegistry is IIdentityRegistry, Ownable {
    using RegistryStorage for RegistryStorage.IdentityRegistryLayout;

    /**
     * @dev Modifier to restrict access to agents
     */
    modifier onlyAgent() {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        require(s.agents[msg.sender] || msg.sender == owner(), "IdentityRegistry: caller is not an agent");
        _;
    }

    /**
     * @dev Constructor
     * @param _trustedIssuersRegistry Address of the Trusted Issuers Registry
     * @param _claimTopicsRegistry Address of the Claim Topics Registry
     * @param _identityRegistryStorage Address of the Identity Registry Storage
     */
    constructor(
        address _trustedIssuersRegistry,
        address _claimTopicsRegistry,
        address _identityRegistryStorage
    ) Ownable(msg.sender) {
        require(_trustedIssuersRegistry != address(0), "IdentityRegistry: invalid trusted issuers registry");
        require(_claimTopicsRegistry != address(0), "IdentityRegistry: invalid claim topics registry");
        require(_identityRegistryStorage != address(0), "IdentityRegistry: invalid identity storage");

        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        
        s.trustedIssuersRegistry = _trustedIssuersRegistry;
        s.claimTopicsRegistry = _claimTopicsRegistry;
        s.identityRegistryStorage = _identityRegistryStorage;

        emit TrustedIssuersRegistrySet(_trustedIssuersRegistry);
        emit ClaimTopicsRegistrySet(_claimTopicsRegistry);
        emit IdentityStorageSet(_identityRegistryStorage);
    }

    /**
     * @dev Register an identity contract corresponding to a user address.
     * Requires that the user doesn't have an identity contract already registered.
     * This function can only be called by a wallet set as agent of the smart contract
     * @param _userAddress The address of the user
     * @param _identity The address of the user's identity contract
     * @param _country The country of the investor
     * emits `IdentityRegistered` event
     */
    function registerIdentity(
        address _userAddress,
        IIdentity _identity,
        uint16 _country
    ) external override onlyAgent {
        _registerIdentityInternal(_userAddress, _identity, _country);
    }

    function _registerIdentityInternal(
        address _userAddress,
        IIdentity _identity,
        uint16 _country
    ) internal {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();

        require(_userAddress != address(0), "IdentityRegistry: invalid user address");
        require(address(_identity) != address(0), "IdentityRegistry: invalid identity address");
        require(!contains(_userAddress), "IdentityRegistry: identity already registered");

        IIdentityRegistryStorage(s.identityRegistryStorage).addIdentityToStorage(
            _userAddress,
            _identity,
            _country
        );

        emit IdentityRegistered(_userAddress, _identity);
    }

    /**
     * @dev Removes an user from the identity registry.
     * Requires that the user have an identity contract already deployed that will be deleted.
     * This function can only be called by a wallet set as agent of the smart contract
     * @param _userAddress The address of the user to be removed
     * emits `IdentityRemoved` event
     */
    function deleteIdentity(address _userAddress) external override onlyAgent {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        
        require(contains(_userAddress), "IdentityRegistry: identity not registered");

        IIdentity userIdentity = IIdentityRegistryStorage(s.identityRegistryStorage).storedIdentity(_userAddress);
        
        IIdentityRegistryStorage(s.identityRegistryStorage).removeIdentityFromStorage(_userAddress);

        emit IdentityRemoved(_userAddress, userIdentity);
    }

    /**
     * @dev Replace the actual identityRegistryStorage contract with a new one.
     * This function can only be called by the wallet set as owner of the smart contract
     * @param _identityRegistryStorage The address of the new Identity Registry Storage
     * emits `IdentityStorageSet` event
     */
    function setIdentityRegistryStorage(address _identityRegistryStorage) external override onlyOwner {
        require(_identityRegistryStorage != address(0), "IdentityRegistry: invalid identity storage");
        
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        s.identityRegistryStorage = _identityRegistryStorage;

        emit IdentityStorageSet(_identityRegistryStorage);
    }

    /**
     * @dev Replace the actual claimTopicsRegistry contract with a new one.
     * This function can only be called by the wallet set as owner of the smart contract
     * @param _claimTopicsRegistry The address of the new claim Topics Registry
     * emits `ClaimTopicsRegistrySet` event
     */
    function setClaimTopicsRegistry(address _claimTopicsRegistry) external override onlyOwner {
        require(_claimTopicsRegistry != address(0), "IdentityRegistry: invalid claim topics registry");
        
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        s.claimTopicsRegistry = _claimTopicsRegistry;

        emit ClaimTopicsRegistrySet(_claimTopicsRegistry);
    }

    /**
     * @dev Replace the actual trustedIssuersRegistry contract with a new one.
     * This function can only be called by the wallet set as owner of the smart contract
     * @param _trustedIssuersRegistry The address of the new Trusted Issuers Registry
     * emits `TrustedIssuersRegistrySet` event
     */
    function setTrustedIssuersRegistry(address _trustedIssuersRegistry) external override onlyOwner {
        require(_trustedIssuersRegistry != address(0), "IdentityRegistry: invalid trusted issuers registry");
        
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        s.trustedIssuersRegistry = _trustedIssuersRegistry;

        emit TrustedIssuersRegistrySet(_trustedIssuersRegistry);
    }

    /**
     * @dev Updates the country corresponding to a user address.
     * Requires that the user should have an identity contract already deployed that will be replaced.
     * This function can only be called by a wallet set as agent of the smart contract
     * @param _userAddress The address of the user
     * @param _country The new country of the user
     * emits `CountryUpdated` event
     */
    function updateCountry(address _userAddress, uint16 _country) external override onlyAgent {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        
        require(contains(_userAddress), "IdentityRegistry: identity not registered");

        IIdentityRegistryStorage(s.identityRegistryStorage).modifyStoredInvestorCountry(_userAddress, _country);

        emit CountryUpdated(_userAddress, _country);
    }

    /**
     * @dev Updates an identity contract corresponding to a user address.
     * Requires that the user address should be the owner of the identity contract.
     * Requires that the user should have an identity contract already deployed that will be replaced.
     * This function can only be called by a wallet set as agent of the smart contract
     * @param _userAddress The address of the user
     * @param _identity The address of the user's new identity contract
     * emits `IdentityUpdated` event
     */
    function updateIdentity(address _userAddress, IIdentity _identity) external override onlyAgent {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        
        require(contains(_userAddress), "IdentityRegistry: identity not registered");
        require(address(_identity) != address(0), "IdentityRegistry: invalid identity address");

        IIdentity previousIdentity = IIdentityRegistryStorage(s.identityRegistryStorage).storedIdentity(_userAddress);
        
        IIdentityRegistryStorage(s.identityRegistryStorage).modifyStoredIdentity(_userAddress, _identity);

        emit IdentityUpdated(previousIdentity, _identity);
    }

    /**
     * @dev function allowing to register identities in batch
     * This function can only be called by a wallet set as agent of the smart contract
     * Requires that none of the users has an identity contract already registered.
     * IMPORTANT : THIS TRANSACTION COULD EXCEED GAS LIMIT IF `_userAddresses.length` IS TOO HIGH,
     * USE WITH CARE OR YOU COULD LOSE TX FEES WITH AN "OUT OF GAS" TRANSACTION
     * @param _userAddresses The addresses of the users
     * @param _identities The addresses of the corresponding identity contracts
     * @param _countries The countries of the corresponding investors
     * emits _userAddresses.length `IdentityRegistered` events
     */
    function batchRegisterIdentity(
        address[] calldata _userAddresses,
        IIdentity[] calldata _identities,
        uint16[] calldata _countries
    ) external override onlyAgent {
        require(
            _userAddresses.length == _identities.length &&
            _identities.length == _countries.length,
            "IdentityRegistry: array length mismatch"
        );

        for (uint256 i = 0; i < _userAddresses.length; i++) {
            _registerIdentityInternal(_userAddresses[i], _identities[i], _countries[i]);
        }
    }

    /**
     * @dev This functions checks whether a wallet has its Identity registered or not
     * in the Identity Registry.
     * @param _userAddress The address of the user to be checked.
     * @return 'True' if the address is contained in the Identity Registry, 'false' if not.
     */
    function contains(address _userAddress) public view override returns (bool) {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        
        IIdentity storedId = IIdentityRegistryStorage(s.identityRegistryStorage).storedIdentity(_userAddress);
        return address(storedId) != address(0);
    }

    /**
     * @dev This functions checks whether an identity contract
     * corresponding to the provided user address has the required claims or not based
     * on the data fetched from trusted issuers registry and from the claim topics registry
     * @param _userAddress The address of the user to be verified.
     * @return 'True' if the address is verified, 'false' if not.
     */
    function isVerified(address _userAddress) external view override returns (bool) {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        
        if (!contains(_userAddress)) {
            return false;
        }

        IIdentity userIdentity = IIdentityRegistryStorage(s.identityRegistryStorage).storedIdentity(_userAddress);
        uint256[] memory requiredClaimTopics = IClaimTopicsRegistry(s.claimTopicsRegistry).getClaimTopics();

        if (requiredClaimTopics.length == 0) {
            return true;
        }

        // Check each required claim topic
        for (uint256 i = 0; i < requiredClaimTopics.length; i++) {
            uint256 claimTopic = requiredClaimTopics[i];
            
            // Get all claim IDs for this topic from the identity
            bytes32[] memory claimIds = userIdentity.getClaimIdsByTopic(claimTopic);
            
            if (claimIds.length == 0) {
                return false; // No claims for this required topic
            }

            bool hasValidClaim = false;
            
            // Check if any claim for this topic is valid
            for (uint256 j = 0; j < claimIds.length; j++) {
                bytes32 claimId = claimIds[j];
                
                // Get claim details
                (
                    uint256 topic,
                    ,
                    address issuer,
                    ,
                    ,
                ) = userIdentity.getClaim(claimId);

                // Verify the claim is from a trusted issuer for this topic
                if (
                    topic == claimTopic &&
                    ITrustedIssuersRegistry(s.trustedIssuersRegistry).hasClaimTopic(issuer, claimTopic) &&
                    userIdentity.isClaimValid(claimId)
                ) {
                    hasValidClaim = true;
                    break;
                }
            }

            if (!hasValidClaim) {
                return false; // No valid claim found for this required topic
            }
        }

        return true; // All required claim topics have valid claims
    }

    /**
     * @dev Returns the onchainID of an investor.
     * @param _userAddress The wallet of the investor
     */
    function identity(address _userAddress) external view override returns (IIdentity) {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        return IIdentityRegistryStorage(s.identityRegistryStorage).storedIdentity(_userAddress);
    }

    /**
     * @dev Returns the country code of an investor.
     * @param _userAddress The wallet of the investor
     */
    function investorCountry(address _userAddress) external view override returns (uint16) {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        return IIdentityRegistryStorage(s.identityRegistryStorage).storedInvestorCountry(_userAddress);
    }

    /**
     * @dev Returns the IdentityRegistryStorage linked to the current IdentityRegistry.
     */
    function identityStorage() external view override returns (IIdentityRegistryStorage) {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        return IIdentityRegistryStorage(s.identityRegistryStorage);
    }

    /**
     * @dev Returns the TrustedIssuersRegistry linked to the current IdentityRegistry.
     */
    function issuersRegistry() external view override returns (ITrustedIssuersRegistry) {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        return ITrustedIssuersRegistry(s.trustedIssuersRegistry);
    }

    /**
     * @dev Returns the ClaimTopicsRegistry linked to the current IdentityRegistry.
     */
    function topicsRegistry() external view override returns (IClaimTopicsRegistry) {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        return IClaimTopicsRegistry(s.claimTopicsRegistry);
    }

    /**
     * @dev Add an agent to the registry
     * @param _agent The address of the agent to add
     */
    function addAgent(address _agent) external onlyOwner {
        require(_agent != address(0), "IdentityRegistry: invalid agent address");
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        s.agents[_agent] = true;
    }

    /**
     * @dev Remove an agent from the registry
     * @param _agent The address of the agent to remove
     */
    function removeAgent(address _agent) external onlyOwner {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        s.agents[_agent] = false;
    }

    /**
     * @dev Check if an address is an agent
     * @param _agent The address to check
     * @return Whether the address is an agent
     */
    function isAgent(address _agent) external view returns (bool) {
        RegistryStorage.IdentityRegistryLayout storage s = RegistryStorage.identityRegistryLayout();
        return s.agents[_agent] || _agent == owner();
    }
}

