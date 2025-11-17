// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/IModule.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AbstractModule
 * @dev Base implementation for compliance modules
 * @notice Provides common functionality for all modules
 */
abstract contract AbstractModule is IModule, Ownable {
    // Mapping of compliance contracts that have bound this module
    mapping(address => bool) private _complianceBound;

    /**
     * @dev Modifier to check if caller is bound compliance
     * @param _compliance The address of the compliance to check
     */
    modifier onlyBoundCompliance(address _compliance) {
        require(_complianceBound[_compliance], "AbstractModule: compliance not bound");
        _;
    }

    /**
     * @dev Modifier to check if caller is bound compliance
     */
    modifier onlyComplianceCall() {
        require(_complianceBound[msg.sender], "only bound compliance can call");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Bind compliance to module
     * @param _compliance The address of the compliance to bind
     */
    function bindCompliance(address _compliance) external override {
        require(_compliance != address(0), "AbstractModule: invalid compliance address");
        require(msg.sender == _compliance, "AbstractModule: only compliance can bind");
        require(!_complianceBound[_compliance], "AbstractModule: compliance already bound");
        
        _complianceBound[_compliance] = true;
        emit ComplianceBound(_compliance);
    }

    /**
     * @dev Unbind compliance from module
     * @param _compliance The address of the compliance to unbind
     */
    function unbindCompliance(address _compliance) external override {
        require(msg.sender == _compliance, "AbstractModule: only compliance can unbind");
        require(_complianceBound[_compliance], "AbstractModule: compliance not bound");
        
        _complianceBound[_compliance] = false;
        emit ComplianceUnbound(_compliance);
    }

    /**
     * @dev Check if compliance is bound
     */
    function isComplianceBound(address _compliance) external view override returns (bool) {
        return _complianceBound[_compliance];
    }
}

