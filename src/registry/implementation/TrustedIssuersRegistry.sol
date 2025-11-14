// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/ITrustedIssuersRegistry.sol";
import "../storage/RegistryStorage.sol";
import "../../identity/interfaces/IClaimIssuer.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TrustedIssuersRegistry
 * @dev Implementation of ITrustedIssuersRegistry using Diamond Storage pattern
 * @notice Manages trusted claim issuers and their allowed claim topics
 */
contract TrustedIssuersRegistry is ITrustedIssuersRegistry, Ownable {
    using RegistryStorage for RegistryStorage.TrustedIssuersRegistryLayout;

    /**
     * @dev Constructor
     * @notice This constructor is used to initialize the TrustedIssuersRegistry
     * Set the owner of the TrustedIssuersRegistry to the msg.sender
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev registers a ClaimIssuer contract as trusted claim issuer.
     * Requires that a ClaimIssuer contract doesn't already exist
     * Requires that the claimTopics set is not empty
     * Requires that there is no more than 15 claimTopics
     * Requires that there is no more than 50 Trusted issuers
     * @param _trustedIssuer The ClaimIssuer contract address of the trusted claim issuer.
     * @param _claimTopics the set of claim topics that the trusted issuer is allowed to emit
     * This function can only be called by the owner of the Trusted Issuers Registry contract
     * emits a `TrustedIssuerAdded` event
     */
    function addTrustedIssuer(IClaimIssuer _trustedIssuer, uint256[] calldata _claimTopics) 
        external 
        override 
        onlyOwner 
    {
        RegistryStorage.TrustedIssuersRegistryLayout storage s = RegistryStorage.trustedIssuersLayout();
        
        require(address(_trustedIssuer) != address(0), "TrustedIssuersRegistry: invalid issuer address");
        require(!s.isTrusted[address(_trustedIssuer)], "TrustedIssuersRegistry: issuer already exists");
        require(_claimTopics.length > 0, "TrustedIssuersRegistry: claim topics cannot be empty");
        require(_claimTopics.length <= 15, "TrustedIssuersRegistry: cannot have more than 15 claim topics");
        require(s.trustedIssuers.length < 50, "TrustedIssuersRegistry: cannot have more than 50 trusted issuers");

        s.trustedIssuers.push(_trustedIssuer);
        s.isTrusted[address(_trustedIssuer)] = true;
        s.issuerIndex[address(_trustedIssuer)] = s.trustedIssuers.length - 1;

        // Store claim topics
        for (uint256 i = 0; i < _claimTopics.length; i++) {
            s.issuerClaimTopics[address(_trustedIssuer)].push(_claimTopics[i]);
            s.issuerHasTopic[address(_trustedIssuer)][_claimTopics[i]] = true;
        }

        emit TrustedIssuerAdded(_trustedIssuer, _claimTopics);
    }

    /**
     * @dev Removes the ClaimIssuer contract of a trusted claim issuer.
     * Requires that the claim issuer contract to be registered first
     * @param _trustedIssuer the claim issuer to remove.
     * This function can only be called by the owner of the Trusted Issuers Registry contract
     * emits a `TrustedIssuerRemoved` event
     */
    function removeTrustedIssuer(IClaimIssuer _trustedIssuer) external override onlyOwner {
        RegistryStorage.TrustedIssuersRegistryLayout storage s = RegistryStorage.trustedIssuersLayout();
        
        require(s.isTrusted[address(_trustedIssuer)], "TrustedIssuersRegistry: issuer does not exist");

        uint256 index = s.issuerIndex[address(_trustedIssuer)];
        uint256 lastIndex = s.trustedIssuers.length - 1;

        // Move the last element to the deleted position
        if (index != lastIndex) {
            IClaimIssuer lastIssuer = s.trustedIssuers[lastIndex];
            s.trustedIssuers[index] = lastIssuer;
            s.issuerIndex[address(lastIssuer)] = index;
        }

        s.trustedIssuers.pop();
        delete s.isTrusted[address(_trustedIssuer)];
        delete s.issuerIndex[address(_trustedIssuer)];
        delete s.issuerClaimTopics[address(_trustedIssuer)];

        // Clean up topic mappings
        uint256[] memory topics = s.issuerClaimTopics[address(_trustedIssuer)];
        for (uint256 i = 0; i < topics.length; i++) {
            delete s.issuerHasTopic[address(_trustedIssuer)][topics[i]];
        }

        emit TrustedIssuerRemoved(_trustedIssuer);
    }

    /**
     * @dev Updates the set of claim topics that a trusted issuer is allowed to emit.
     * Requires that this ClaimIssuer contract already exists in the registry
     * Requires that the provided claimTopics set is not empty
     * Requires that there is no more than 15 claimTopics
     * @param _trustedIssuer the claim issuer to update.
     * @param _claimTopics the set of claim topics that the trusted issuer is allowed to emit
     * This function can only be called by the owner of the Trusted Issuers Registry contract
     * emits a `ClaimTopicsUpdated` event
     */
    function updateIssuerClaimTopics(IClaimIssuer _trustedIssuer, uint256[] calldata _claimTopics) 
        external 
        override 
        onlyOwner 
    {
        RegistryStorage.TrustedIssuersRegistryLayout storage s = RegistryStorage.trustedIssuersLayout();
        
        require(s.isTrusted[address(_trustedIssuer)], "TrustedIssuersRegistry: issuer does not exist");
        require(_claimTopics.length > 0, "TrustedIssuersRegistry: claim topics cannot be empty");
        require(_claimTopics.length <= 15, "TrustedIssuersRegistry: cannot have more than 15 claim topics");

        // Clear old topics
        uint256[] memory oldTopics = s.issuerClaimTopics[address(_trustedIssuer)];
        for (uint256 i = 0; i < oldTopics.length; i++) {
            delete s.issuerHasTopic[address(_trustedIssuer)][oldTopics[i]];
        }
        delete s.issuerClaimTopics[address(_trustedIssuer)];

        // Set new topics
        for (uint256 i = 0; i < _claimTopics.length; i++) {
            s.issuerClaimTopics[address(_trustedIssuer)].push(_claimTopics[i]);
            s.issuerHasTopic[address(_trustedIssuer)][_claimTopics[i]] = true;
        }

        emit ClaimTopicsUpdated(_trustedIssuer, _claimTopics);
    }

    /**
     * @dev Function for getting all the trusted claim issuers stored.
     * @return array of all claim issuers registered.
     */
    function getTrustedIssuers() external view override returns (IClaimIssuer[] memory) {
        return RegistryStorage.trustedIssuersLayout().trustedIssuers;
    }

    /**
     * @dev Function for getting all the trusted issuer allowed for a given claim topic.
     * @param claimTopic the claim topic to get the trusted issuers for.
     * @return array of all claim issuer addresses that are allowed for the given claim topic.
     */
    function getTrustedIssuersForClaimTopic(uint256 claimTopic) 
        external 
        view 
        override 
        returns (IClaimIssuer[] memory) 
    {
        RegistryStorage.TrustedIssuersRegistryLayout storage s = RegistryStorage.trustedIssuersLayout();
        
        // First pass: count matching issuers
        uint256 count = 0;
        for (uint256 i = 0; i < s.trustedIssuers.length; i++) {
            address issuerAddr = address(s.trustedIssuers[i]);
            if (s.issuerHasTopic[issuerAddr][claimTopic]) {
                count++;
            }
        }

        // Second pass: fill array
        IClaimIssuer[] memory issuers = new IClaimIssuer[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < s.trustedIssuers.length; i++) {
            address issuerAddr = address(s.trustedIssuers[i]);
            if (s.issuerHasTopic[issuerAddr][claimTopic]) {
                issuers[index] = s.trustedIssuers[i];
                index++;
            }
        }

        return issuers;
    }

    /**
     * @dev Checks if the ClaimIssuer contract is trusted
     * @param _issuer the address of the ClaimIssuer contract
     * @return true if the issuer is trusted, false otherwise.
     */
    function isTrustedIssuer(address _issuer) external view override returns (bool) {
        return RegistryStorage.trustedIssuersLayout().isTrusted[_issuer];
    }

    /**
     * @dev Function for getting all the claim topic of trusted claim issuer
     * Requires the provided ClaimIssuer contract to be registered in the trusted issuers registry.
     * @param _trustedIssuer the trusted issuer concerned.
     * @return The set of claim topics that the trusted issuer is allowed to emit
     */
    function getTrustedIssuerClaimTopics(IClaimIssuer _trustedIssuer) 
        external 
        view 
        override 
        returns (uint256[] memory) 
    {
        RegistryStorage.TrustedIssuersRegistryLayout storage s = RegistryStorage.trustedIssuersLayout();
        require(s.isTrusted[address(_trustedIssuer)], "TrustedIssuersRegistry: issuer does not exist");
        return s.issuerClaimTopics[address(_trustedIssuer)];
    }

    /**
     * @dev Function for checking if the trusted claim issuer is allowed
     * to emit a certain claim topic
     * @param _issuer the address of the trusted issuer's ClaimIssuer contract
     * @param _claimTopic the Claim Topic that has to be checked to know if the `issuer` is allowed to emit it
     * @return true if the issuer is trusted for this claim topic.
     */
    function hasClaimTopic(address _issuer, uint256 _claimTopic) external view override returns (bool) {
        RegistryStorage.TrustedIssuersRegistryLayout storage s = RegistryStorage.trustedIssuersLayout();
        return s.isTrusted[_issuer] && s.issuerHasTopic[_issuer][_claimTopic];
    }
}

