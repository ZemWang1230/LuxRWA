// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IIdentity.sol";

/**
 * @title IClaimIssuer
 * @dev Interface for claim issuers
 * @notice Extends IIdentity with claim issuance capabilities
 * @dev Claim issuers can issue and revoke claims to other identities
 */
interface IClaimIssuer is IIdentity {
    /**
     * @dev Emitted when a claim is issued to an identity
     */
    event ClaimIssued(
        bytes32 indexed claimId,
        address indexed identity,
        uint256 indexed topic,
        bytes signature,
        bytes data,
        string uri
    );

    /**
     * @dev Emitted when an issued claim is revoked
     */
    event ClaimRevoked(bytes32 indexed claimId, address indexed identity);

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
    ) external returns (bytes32 claimId);

    /**
     * @dev Revoke a claim that was previously issued
     * @param _claimId The ID of the claim to revoke
     * @return success Whether the revocation was successful
     */
    function revokeClaim(bytes32 _claimId) external returns (bool success);

    /**
     * @dev Get the claim ID for a specific identity and topic
     * @param _identity The identity address
     * @param _topic The claim topic
     * @return claimId The claim ID
     */
    function getClaimId(address _identity, uint256 _topic) external pure returns (bytes32 claimId);

    /**
     * @dev Check if a claim is still valid
     * @param _identity The identity address
     * @param _claimId The claim ID
     * @return valid Whether the claim is valid
     */
    function isClaimValid(address _identity, bytes32 _claimId) external view returns (bool valid);

    /**
     * @dev Get all claims issued to a specific identity
     * @param _identity The identity address
     * @return claimIds Array of claim IDs
     */
    function getIssuedClaims(address _identity) external view returns (bytes32[] memory claimIds);

    /**
     * @dev Get the status of a claim
     * @param _claimId The ID of the claim
     * @return status The status of the claim
     */
    function isClaimIssued(bytes32 _claimId) external view returns (bool status);
}

