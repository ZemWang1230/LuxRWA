// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IIdentity.sol";
import "../storage/IdentityStorage.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title Identity
 * @dev Implementation of IIdentity interface using Diamond Storage pattern
 * @notice Base identity contract implementing ERC734 and ERC735
 * Reference: https://github.com/onchain-id/solidity
 */
contract Identity is IIdentity, ERC165 {
    using IdentityStorage for IdentityStorage.Layout;

    /**
     * @dev Modifier to restrict access to owner only
     */
    modifier onlyOwner() {
        IdentityStorage.Layout storage s = IdentityStorage.layout();
        require(msg.sender == s.owner, "Identity: caller is not the owner");
        _;
    }

    /**
     * @dev Modifier to check if key has specific purpose
     */
    modifier onlyKeyPurpose(uint256 _purpose) {
        require(keyHasPurpose(keccak256(abi.encodePacked(msg.sender)), _purpose), "Identity: key does not have purpose");
        _;
    }

    /**
     * @dev Initialize the identity
     * @param _owner The owner address
     * @param _identityName Name of the identity
     */
    function initialize(address _owner, string memory _identityName, bool _isInvestor, bool _isIssuer) public {
        IdentityStorage.Layout storage s = IdentityStorage.layout();
        require((_isInvestor || _isIssuer) && !(_isInvestor && _isIssuer), "Identity: invalid identity type");
        require(s.owner == address(0), "Identity: already initialized");
        require(_owner != address(0), "Identity: invalid owner");

        s.owner = _owner;
        s.identityName = _identityName;
        s.createdAt = block.timestamp;
        s.isInvestor = _isInvestor;
        s.isIssuer = _isIssuer;

        // Add owner key with all purposes
        bytes32 ownerKey = keccak256(abi.encodePacked(_owner));
        _addKey(ownerKey, IdentityStorage.MANAGEMENT_PURPOSE, IdentityStorage.ECDSA_KEY);
        _addKey(ownerKey, IdentityStorage.ACTION_PURPOSE, IdentityStorage.ECDSA_KEY);

        emit IdentityCreated(_owner, _identityName);
    }

    /**
     * @dev Get the owner of the identity
     */
    function owner() public view override returns (address) {
        return IdentityStorage.layout().owner;
    }

    /**
     * @dev Get version
     */
    function version() public pure override returns (string memory) {
        return "1.0.0";
    }

    // ==================== ERC734 Implementation ====================

    /**
     * @dev Add a key to the identity
     * @param _key The key to add
     * @param _purpose The purpose of the key
     * @param _keyType The type of the key
     * @return success Whether the key was added successfully
     */
    function addKey(bytes32 _key, uint256 _purpose, uint256 _keyType)
        public
        override
        onlyKeyPurpose(IdentityStorage.MANAGEMENT_PURPOSE)
        returns (bool success)
    {
        _addKey(_key, _purpose, _keyType);
        return true;
    }

    /**
     * @dev Remove a key from the identity
     * @param _key The key to remove
     * @param _purpose The purpose of the key
     * @return success Whether the key was removed successfully
     */
    function removeKey(bytes32 _key, uint256 _purpose)
        public
        override
        onlyKeyPurpose(IdentityStorage.MANAGEMENT_PURPOSE)
        returns (bool success)
    {
        IdentityStorage.Layout storage s = IdentityStorage.layout();
        
        require(s.keys[_key].key != bytes32(0), "Identity: key does not exist");

        // Remove purpose from key
        uint256[] storage purposes = s.keys[_key].purposes;
        for (uint256 i = 0; i < purposes.length; i++) {
            if (purposes[i] == _purpose) {
                purposes[i] = purposes[purposes.length - 1];
                purposes.pop();
                break;
            }
        }

        // Remove key from purpose mapping
        bytes32[] storage keysForPurpose = s.keysByPurpose[_purpose];
        for (uint256 i = 0; i < keysForPurpose.length; i++) {
            if (keysForPurpose[i] == _key) {
                keysForPurpose[i] = keysForPurpose[keysForPurpose.length - 1];
                keysForPurpose.pop();
                break;
            }
        }

        // If key has no more purposes, delete it completely
        if (purposes.length == 0) {
            delete s.keys[_key];
            
            // Remove from allKeys
            for (uint256 i = 0; i < s.allKeys.length; i++) {
                if (s.allKeys[i] == _key) {
                    s.allKeys[i] = s.allKeys[s.allKeys.length - 1];
                    s.allKeys.pop();
                    break;
                }
            }
        }

        emit KeyRemoved(_key, _purpose, s.keys[_key].keyType);
        return true;
    }

    /**
     * @dev Get a key by its hash
     * @param _key The key to get
     * @return purposes The purposes of the key
     * @return keyType The type of the key
     * @return key The key
     */
    function getKey(bytes32 _key)
        public
        view
        override
        returns (uint256[] memory purposes, uint256 keyType, bytes32 key)
    {
        IdentityStorage.Layout storage s = IdentityStorage.layout();
        IdentityStorage.Key storage keyData = s.keys[_key];
        
        return (keyData.purposes, keyData.keyType, keyData.key);
    }

    /**
     * @dev Check if a key has a specific purpose
     * @param _key The key to check
     * @param _purpose The purpose to check
     * @return exists Whether the key has the purpose
     */
    function keyHasPurpose(bytes32 _key, uint256 _purpose) public view override returns (bool exists) {
        IdentityStorage.Layout storage s = IdentityStorage.layout();
        uint256[] memory purposes = s.keys[_key].purposes;
        
        for (uint256 i = 0; i < purposes.length; i++) {
            if (purposes[i] == _purpose) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Get keys by purpose
     * @param _purpose The purpose to get keys for
     * @return keys The keys with the purpose
     */
    function getKeysByPurpose(uint256 _purpose) public view override returns (bytes32[] memory keys) {
        return IdentityStorage.layout().keysByPurpose[_purpose];
    }

    /**
     * @dev Get key purposes
     * @param _key The key to get purposes for
     * @return _purposes The purposes of the key
     */
    function getKeyPurposes(bytes32 _key) external view override returns (uint256[] memory _purposes) {
        return IdentityStorage.layout().keys[_key].purposes;
    }

    // ==================== ERC735 Implementation ====================

    /**
     * @dev Add a claim to the identity
     * @param _topic The topic of the claim
     * @param _scheme The scheme of the claim
     * @param _issuer The issuer of the claim
     * @param _signature The signature of the claim
     * @param _data The data of the claim
     * @param _uri The URI of the claim
     * @return claimRequestId The ID of the claim
     */
    function addClaim(
        uint256 _topic,
        uint256 _scheme,
        address _issuer,
        bytes calldata _signature,
        bytes calldata _data,
        string calldata _uri
    ) public override onlyKeyPurpose(IdentityStorage.CLAIM_PURPOSE) returns (bytes32 claimRequestId) {
        IdentityStorage.Layout storage s = IdentityStorage.layout();

        claimRequestId = keccak256(abi.encodePacked(_issuer, _topic));
        
        require(s.claims[claimRequestId].issuer == address(0), "Identity: claim already exists");

        s.claims[claimRequestId] = IdentityStorage.Claim({
            topic: _topic,
            scheme: _scheme,
            issuer: _issuer,
            signature: _signature,
            data: _data,
            uri: _uri,
            revocable: true,
            revoked: false
        });

        s.claimsByTopic[_topic].push(claimRequestId);
        s.allClaims.push(claimRequestId);

        emit ClaimAdded(claimRequestId, _topic, _scheme, _issuer, _signature, _data, _uri);
        return claimRequestId;
    }

    /**
     * @dev Remove a claim from the identity
     * @param _claimId The ID of the claim to remove
     * @return success Whether the claim was removed successfully
     */
    function removeClaim(bytes32 _claimId)
        public
        override
        onlyKeyPurpose(IdentityStorage.CLAIM_PURPOSE)
        returns (bool success)
    {
        IdentityStorage.Layout storage s = IdentityStorage.layout();
        
        require(s.claims[_claimId].issuer != address(0), "Identity: claim does not exist");

        uint256 topic = s.claims[_claimId].topic;

        // Remove from claimsByTopic
        bytes32[] storage claimsForTopic = s.claimsByTopic[topic];
        for (uint256 i = 0; i < claimsForTopic.length; i++) {
            if (claimsForTopic[i] == _claimId) {
                claimsForTopic[i] = claimsForTopic[claimsForTopic.length - 1];
                claimsForTopic.pop();
                break;
            }
        }

        // Remove from allClaims
        for (uint256 i = 0; i < s.allClaims.length; i++) {
            if (s.allClaims[i] == _claimId) {
                s.allClaims[i] = s.allClaims[s.allClaims.length - 1];
                s.allClaims.pop();
                break;
            }
        }

        emit ClaimRemoved(
            _claimId,
            topic,
            s.claims[_claimId].scheme,
            s.claims[_claimId].issuer,
            s.claims[_claimId].signature,
            s.claims[_claimId].data,
            s.claims[_claimId].uri
        );

        delete s.claims[_claimId];
        return true;
    }

    /**
     * @dev Get a claim by its ID
     * @param _claimId The ID of the claim to get
     * @return topic The topic of the claim
     * @return scheme The scheme of the claim
     * @return issuer The issuer of the claim
     * @return signature The signature of the claim
     * @return data The data of the claim
     * @return uri The URI of the claim
     */
    function getClaim(bytes32 _claimId)
        public
        view
        override
        returns (
            uint256 topic,
            uint256 scheme,
            address issuer,
            bytes memory signature,
            bytes memory data,
            string memory uri
        )
    {
        IdentityStorage.Layout storage s = IdentityStorage.layout();
        IdentityStorage.Claim storage claim = s.claims[_claimId];
        
        require(claim.issuer != address(0), "Identity: claim does not exist");

        return (claim.topic, claim.scheme, claim.issuer, claim.signature, claim.data, claim.uri);
    }

    /**
     * @dev Get claim IDs by topic
     * @param _topic The topic to get claim IDs for
     * @return claimIds The IDs of the claims with the topic
     */
    function getClaimIdsByTopic(uint256 _topic) public view override returns (bytes32[] memory claimIds) {
        return IdentityStorage.layout().claimsByTopic[_topic];
    }

    /**
     * @dev Check if a claim is valid
     * @param _claimId The ID of the claim to check
     * @return valid Whether the claim is valid
     */
    function isClaimValid(bytes32 _claimId) public view override returns (bool valid) {
        IdentityStorage.Layout storage s = IdentityStorage.layout();
        IdentityStorage.Claim storage claim = s.claims[_claimId];

        if (claim.issuer == address(0) || claim.revoked) {
            return false;
        }

        // Verify signature is from the issuer's owner (EOA)
        bytes32 messageHash = keccak256(abi.encodePacked(_claimId, claim.topic, claim.data));
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        address recovered = _getRecoveredAddress(claim.signature, prefixedHash);
        
        // Get the owner of the issuer identity
        try IIdentity(claim.issuer).owner() returns (address issuerOwner) {
            return recovered == issuerOwner;
        } catch {
            // If issuer is not an identity contract, check if recovered == issuer
            return recovered == claim.issuer;
        }
    }

    // ==================== Execution Management ====================

    /**
     * @dev Execute an action on behalf of the identity
     * @param _to The address to execute the action on
     * @param _value The value to send with the action
     * @param _data The data to execute the action with
     * @return executionId The ID of the execution
     */
    function execute(address _to, uint256 _value, bytes calldata _data)
        public
        payable
        override
        onlyKeyPurpose(IdentityStorage.ACTION_PURPOSE)
        returns (uint256 executionId)
    {
        IdentityStorage.Layout storage s = IdentityStorage.layout();
        
        executionId = s.executionNonce;
        s.executionNonce++;

        IdentityStorage.Execution storage execution = s.executions[executionId];
        execution.to = _to;
        execution.value = _value;
        execution.data = _data;
        execution.executed = false;
        execution.approvalCount = 0;

        emit ExecutionRequested(executionId, _to, _value, _data);

        // Auto-approve and execute if caller has ACTION purpose
        if (keyHasPurpose(keccak256(abi.encodePacked(msg.sender)), IdentityStorage.ACTION_PURPOSE)) {
            approve(executionId, true);
        }

        return executionId;
    }

    /**
     * @dev Approve an execution
     * @param _id The ID of the execution to approve
     * @param _approve Whether to approve or reject the execution
     * @return success Whether the approval was successful
     */
    function approve(uint256 _id, bool _approve)
        public
        override
        onlyKeyPurpose(IdentityStorage.ACTION_PURPOSE)
        returns (bool success)
    {
        IdentityStorage.Layout storage s = IdentityStorage.layout();
        IdentityStorage.Execution storage execution = s.executions[_id];

        require(!execution.executed, "Identity: already executed");

        if (_approve && !execution.approvals[msg.sender]) {
            execution.approvals[msg.sender] = true;
            execution.approvalCount++;
        } else if (!_approve && execution.approvals[msg.sender]) {
            execution.approvals[msg.sender] = false;
            execution.approvalCount--;
        }

        emit Approved(_id, _approve);

        // Execute if approved
        if (_approve && !execution.executed && _isExecuteApproved(_id)) {
            execution.executed = true;
            
            (bool execSuccess, ) = execution.to.call{value: execution.value}(execution.data);
            
            if (execSuccess) {
                emit Executed(_id, execution.to, execution.value, execution.data);
            }
            
            return execSuccess;
        }

        return true;
    }

    // ==================== Internal Functions ====================

    /**
     * @dev Internal function to add a key
     * @param _key The key to add
     * @param _purpose The purpose of the key
     * @param _keyType The type of the key
     */
    function _addKey(bytes32 _key, uint256 _purpose, uint256 _keyType) internal {
        IdentityStorage.Layout storage s = IdentityStorage.layout();

        if (s.keys[_key].key == bytes32(0)) {
            s.keys[_key].key = _key;
            s.keys[_key].keyType = _keyType;
            s.allKeys.push(_key);
        }

        // Check if purpose already exists
        uint256[] storage purposes = s.keys[_key].purposes;
        for (uint256 i = 0; i < purposes.length; i++) {
            if (purposes[i] == _purpose) {
                return; // Purpose already exists
            }
        }

        purposes.push(_purpose);
        s.keysByPurpose[_purpose].push(_key);

        emit KeyAdded(_key, _purpose, _keyType);
    }

    /**
     * @dev Internal function to check if an execution is approved
     * @param _id The ID of the execution to check
     * @return approved Whether the execution is approved
     */
    function _isExecuteApproved(uint256 _id) internal view returns (bool) {
        IdentityStorage.Layout storage s = IdentityStorage.layout();
        IdentityStorage.Execution storage execution = s.executions[_id];
        // Simplified implementation: any key with ACTION purpose can approve the execution
        return execution.approvalCount >= 1;
    }

    /**
     * @dev returns the address that signed the given data
     * @param sig the signature of the data
     * @param dataHash the data that was signed
     * returns the address that signed dataHash and created the signature sig
     */
    function _getRecoveredAddress(bytes memory sig, bytes32 dataHash)
    internal
    pure
    returns (address)
    {
        bytes32 ra;
        bytes32 sa;
        uint8 va;

        // Check the signature length
        if (sig.length != 65) {
            return address(0);
        }

        // Divide the signature in r, s and v variables
        // solhint-disable-next-line no-inline-assembly
        assembly {
            ra := mload(add(sig, 32))
            sa := mload(add(sig, 64))
            va := byte(0, mload(add(sig, 96)))
        }

        if (va < 27) {
            va += 27;
        }

        address recoveredAddress = ecrecover(dataHash, va, ra, sa);

        return (recoveredAddress);
    }

    // ==================== ERC165 Support ====================

    /**
     * @dev Check interface support
     * @param interfaceId The interface ID to check
     * @return supported Whether the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC734).interfaceId ||
            interfaceId == type(IERC735).interfaceId ||
            interfaceId == type(IIdentity).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Receive function to accept ETH
     * @dev This function is used to accept ETH
     */
    receive() external payable {}
}

