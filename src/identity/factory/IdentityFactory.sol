// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../implementation/InvestorIdentity.sol";
import "../implementation/ClaimIssuer.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

/**
 * @title IdentityFactory
 * @dev Factory contract for creating investor and issuer identities
 * @notice Manages the deployment and registration of identity contracts
 */
contract IdentityFactory is Ownable {
    /**
     * @dev Emitted when an investor identity is created
     */
    event InvestorIdentityCreated(
        address indexed identity,
        address indexed owner,
        string name
    );

    /**
     * @dev Emitted when an issuer identity is created
     */
    event IssuerIdentityCreated(
        address indexed identity,
        address indexed owner,
        string name
    );

    // User address => their identity contract
    mapping(address => address) public userToIdentity;
    
    // Identity contract => user address
    mapping(address => address) public identityToUser;
    
    // Arrays for tracking
    address[] public investorIdentities;
    address[] public issuerIdentities;

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Create investor identity
     * @param _owner Owner address for the identity
     * @param _name Name of the investor
     * @return investorIdentity Address of created investor identity
     */
    function createInvestorIdentity(address _owner, string calldata _name)
        external
        payable
        returns (address investorIdentity)
    {
        require(_owner != address(0), "IdentityFactory: invalid owner");
        require(userToIdentity[_owner] == address(0), "IdentityFactory: user already has identity");

        // Compute salt and bytecode for the investor identity
        bytes32 salt = keccak256(abi.encodePacked("LuxRWA", _owner, _name, block.timestamp));
        bytes memory bytecode = type(InvestorIdentity).creationCode;
        // Deploy new InvestorIdentity
        investorIdentity = Create2.deploy(0, salt, bytecode);

        // Initialize the investor identity
        InvestorIdentity(payable(investorIdentity)).initializeInvestor(_owner, _name);

        // Register the investor identity
        investorIdentities.push(investorIdentity);
        userToIdentity[_owner] = investorIdentity;
        identityToUser[investorIdentity] = _owner;

        emit InvestorIdentityCreated(investorIdentity, _owner, _name);
    }

    /**
     * @dev Create issuer identity
     * @param _owner Owner address for the identity
     * @param _name Name of the issuer
     * @return issuerIdentity Address of created issuer identity
     */
    function createIssuerIdentity(address _owner, string calldata _name)
        external
        payable
        onlyOwner
        returns (address issuerIdentity)
    {
        require(_owner != address(0), "IdentityFactory: invalid owner");
        require(userToIdentity[_owner] == address(0), "IdentityFactory: user already has identity");

        bytes32 salt = keccak256(abi.encodePacked("LuxRWA", _owner, _name, block.timestamp));
        bytes memory bytecode = type(ClaimIssuer).creationCode;
        // Deploy new ClaimIssuer
        issuerIdentity = Create2.deploy(0, salt, bytecode);

        // Initialize the issuer identity
        ClaimIssuer(payable(issuerIdentity)).initializeIssuer(_owner, _name);

        // Register the issuer identity
        issuerIdentities.push(issuerIdentity);
        userToIdentity[_owner] = issuerIdentity;
        identityToUser[issuerIdentity] = _owner;

        emit IssuerIdentityCreated(issuerIdentity, _owner, _name);
    }

    /**
     * @dev Batch create investor identities
     * @param _owners Array of owner addresses
     * @param _names Array of investor names
     * @return identities Array of created identity addresses
     */
    function batchCreateInvestorIdentities(
        address[] calldata _owners,
        string[] calldata _names
    ) external returns (address[] memory identities) {
        require(_owners.length == _names.length, "IdentityFactory: array length mismatch");

        identities = new address[](_owners.length);

        for (uint256 i = 0; i < _owners.length; i++) {
            identities[i] = this.createInvestorIdentity(_owners[i], _names[i]);
        }

        return identities;
    }

    /**
     * @dev Get identity for a user
     * @param _user User address
     * @return identity Identity contract address
     */
    function getIdentity(address _user) external view returns (address identity) {
        return userToIdentity[_user];
    }

    /**
     * @dev Get owner of an identity
     * @param _identity Identity contract address
     * @return owner Owner address
     */
    function getIdentityOwner(address _identity) external view returns (address owner) {
        return identityToUser[_identity];
    }

    /**
     * @dev Get all investor identities
     * @return identities Array of investor identity addresses
     */
    function getInvestorIdentities() external view returns (address[] memory identities) {
        return investorIdentities;
    }

    /**
     * @dev Get all issuer identities
     * @return identities Array of issuer identity addresses
     */
    function getIssuerIdentities() external view returns (address[] memory identities) {
        return issuerIdentities;
    }

    /**
     * @dev Get identity count
     * @return investorCount Investor identity count
     * @return issuerCount Issuer identity count
     */
    function getIdentityCount()
        external
        view
        returns (
            uint256 investorCount,
            uint256 issuerCount
        )
    {
        return (investorIdentities.length, issuerIdentities.length);
    }
}

