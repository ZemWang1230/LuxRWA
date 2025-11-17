// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/**
 * @title ModularComplianceStorage
 * @dev Diamond Storage implementation for ModularCompliance
 * @notice Uses Diamond Storage pattern to avoid storage collisions
 */
library ModularComplianceStorage {
    bytes32 constant MODULAR_COMPLIANCE_STORAGE_POSITION = keccak256("luxrwa.modular.compliance.storage");

    struct Layout {
        // Token that is bound to this compliance
        address tokenBound;
        
        // Array of module addresses
        address[] modules;
        
        // Mapping to check if a module is bound
        mapping(address => bool) moduleBound;
    }

    function layout() internal pure returns (Layout storage s) {
        bytes32 position = MODULAR_COMPLIANCE_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
