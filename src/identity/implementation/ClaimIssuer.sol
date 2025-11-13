// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Identity.sol";
import "../interfaces/IClaimIssuer.sol";

/**
 * @title ClaimIssuer
 * @dev Implementation of IClaimIssuer interface
 * @notice Extends Identity with claim issuance capabilities
 * Reference: https://github.com/onchain-id/solidity
 */
contract ClaimIssuer is Identity, IClaimIssuer {
    using IdentityStorage for IdentityStorage.Layout;

    // Storage for tracking issued claims
    // identityAddress => claimIds[]
    mapping(address => bytes32[]) private issuedClaims;
    
    // claimId => identityAddress
    mapping(bytes32 => address) private claimToIdentity;
    
    // claimId => isIssued
    mapping(bytes32 => bool) private issuedClaimStatus;

    /**
     * @dev Initialize claim issuer
     * @param _owner The owner address
     * @param _issuerName Name of the issuer
     */
    function initializeIssuer(address _owner, string memory _issuerName) public {
        initialize(_owner, _issuerName, false, true);
    }

    /**
     * @dev Issue a claim to an identity
     * @param _identity The identity address to issue the claim to
     * @param _topic The topic of the claim
     * @param _data The data of the claim
     * @param _uri The URI of the claim
     * @param _signature The signature of the claim
     * @return claimId The ID of the issued claim
     */
    function issueClaim(
        address _identity,
        uint256 _topic,
        bytes calldata _data,
        string calldata _uri,
        bytes calldata _signature
    ) external virtual override onlyKeyPurpose(IdentityStorage.CLAIM_PURPOSE) returns (bytes32 claimId) {
        require(_identity != address(0), "ClaimIssuer: invalid identity address");

        // Generate claim ID
        claimId = getClaimId(_identity, _topic);
        
        require(!issuedClaimStatus[claimId], "ClaimIssuer: claim already issued");

        // Add claim to the target identity
        IIdentity targetIdentity = IIdentity(_identity);
        bytes32 actualClaimId = targetIdentity.addClaim(
            _topic,
            IdentityStorage.ECDSA_SCHEME,
            address(this),
            _signature,
            _data,
            _uri
        );

        // Track issued claim
        issuedClaimStatus[actualClaimId] = true;
        issuedClaims[_identity].push(actualClaimId);
        claimToIdentity[actualClaimId] = _identity;

        emit ClaimIssued(actualClaimId, _identity, _topic, _signature, _data, _uri);

        return actualClaimId;
    }

    /**
     * @dev Revoke a previously issued claim
     * @param _claimId The ID of the claim to revoke
     * @return success Whether the revocation was successful
     */
    function revokeClaim(bytes32 _claimId) 
        external 
        virtual
        override 
        onlyKeyPurpose(IdentityStorage.CLAIM_PURPOSE) 
        returns (bool success) 
    {
        require(issuedClaimStatus[_claimId], "ClaimIssuer: claim not issued by this issuer");

        address identityAddress = claimToIdentity[_claimId];
        require(identityAddress != address(0), "ClaimIssuer: identity not found");

        // Remove the claim from the target identity
        // Since we are the issuer (identity contract), we need CLAIM_PURPOSE in the target
        IIdentity targetIdentity = IIdentity(identityAddress);
        targetIdentity.removeClaim(_claimId);

        // Update our tracking
        issuedClaimStatus[_claimId] = false;

        emit ClaimRevoked(_claimId, identityAddress);

        return true;
    }

    /**
     * @dev Get claim ID for an identity and topic
     * @param _identity The identity address
     * @param _topic The topic of the claim
     * @return claimId The claim ID
     */
    function getClaimId(address _identity, uint256 _topic) 
        public 
        pure 
        override 
        returns (bytes32 claimId) 
    {
        return keccak256(abi.encodePacked(_identity, _topic));
    }

    /**
     * @dev Check if a claim is issued
     * @param _claimId The ID of the claim
     * @return status The status of the claim
     */
    function isClaimIssued(bytes32 _claimId)
        external
        view
        override
        returns (bool status)
    {
        return (issuedClaimStatus[_claimId]);
    }

    /**
     * @dev Check if a claim is valid for an identity
     * @param _identity The identity address
     * @param _claimId The claim ID
     * @return valid Whether the claim is valid
     */
    function isClaimValid(address _identity, bytes32 _claimId) 
        external 
        view 
        override 
        returns (bool valid) 
    {
        if (!issuedClaimStatus[_claimId]) {
            return false;
        }

        if (claimToIdentity[_claimId] != _identity) {
            return false;
        }

        // Check if claim exists in the identity contract
        try IIdentity(_identity).isClaimValid(_claimId) returns (bool isValid) {
            return isValid;
        } catch {
            return false;
        }
    }

    /**
     * @dev Get all claims issued to an identity
     * @param _identity The identity address
     * @return claimIds The IDs of the claims issued to the identity
     */
    function getIssuedClaims(address _identity) 
        external 
        view 
        override 
        returns (bytes32[] memory claimIds) 
    {
        return issuedClaims[_identity];
    }

    /**
     * @dev Batch issue claims to multiple identities
     * @param _identities Array of identity addresses
     * @param _topics Array of claim topics
     * @param _dataArray Array of claim data
     * @param _uris Array of claim URIs
     * @param _signatures Array of claim signatures
     * @return claimIds Array of issued claim IDs
     */
    function batchIssueClaims(
        address[] calldata _identities,
        uint256[] calldata _topics,
        bytes[] calldata _dataArray,
        string[] calldata _uris,
        bytes[] calldata _signatures
    ) external onlyKeyPurpose(IdentityStorage.CLAIM_PURPOSE) returns (bytes32[] memory claimIds) {
        require(
            _identities.length == _topics.length &&
            _topics.length == _dataArray.length &&
            _dataArray.length == _uris.length &&
            _uris.length == _signatures.length,
            "ClaimIssuer: array length mismatch"
        );

        claimIds = new bytes32[](_identities.length);

        for (uint256 i = 0; i < _identities.length; i++) {
            address identity = _identities[i];
            uint256 topic = _topics[i];
            bytes calldata data = _dataArray[i];
            string calldata uri = _uris[i];
            bytes calldata signature = _signatures[i];
            require(identity != address(0), "ClaimIssuer: invalid identity address");

            bytes32 claimId = getClaimId(identity, topic);
            require(!issuedClaimStatus[claimId], "ClaimIssuer: claim already issued");

            IIdentity targetIdentity = IIdentity(identity);
            bytes32 actualClaimId = targetIdentity.addClaim(
                topic,
                IdentityStorage.ECDSA_SCHEME,
                address(this),
                signature,
                data,
                uri
            );

            issuedClaimStatus[actualClaimId] = true;
            issuedClaims[identity].push(actualClaimId);
            claimToIdentity[actualClaimId] = identity;

            emit ClaimIssued(actualClaimId, identity, topic, signature, data, uri);

            claimIds[i] = actualClaimId;
        }

        return claimIds;
    }

    /**
     * @dev Check interface support
     * @param interfaceId The interface ID to check
     * @return supported Whether the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IClaimIssuer).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}

