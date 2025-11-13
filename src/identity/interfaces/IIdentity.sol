// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC734.sol";
import "./IERC735.sol";

/**
 * @title IIdentity
 * @dev Base interface for blockchain identity
 * @notice Combines ERC734 (Key Management) and ERC735 (Claim Holder) with additional identity features
 * Reference: https://github.com/onchain-id/solidity
 */
interface IIdentity is IERC734, IERC735 {
    /**
     * @dev Emitted when the identity is created
     */
    event IdentityCreated(address indexed owner, string identityName);

    /**
     * @dev Emitted when ownership is transferred
     */
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Get the owner of the identity
     * @return owner The address of the owner
     */
    function owner() external view returns (address);

    /**
     * @dev Execute an action on behalf of the identity
     * @param _to Destination address
     * @param _value Amount of ETH to send
     * @param _data Call data
     * @return executionId The ID of the execution request
     */
    function execute(address _to, uint256 _value, bytes calldata _data) external payable returns (uint256 executionId);

    /**
     * @dev Approve an execution request
     * @param _id Execution ID
     * @param _approve Whether to approve or reject
     * @return success Whether the approval was successful
     */
    function approve(uint256 _id, bool _approve) external returns (bool success);

    /**
     * @dev Check if a claim is valid (exists and not revoked)
     * @param _claimId The claim ID
     * @return valid Whether the claim is valid
     */
    function isClaimValid(bytes32 _claimId) external view returns (bool valid);

    /**
     * @dev Get version of the identity contract
     * @return version The version string
     */
    function version() external pure returns (string memory);
}

