// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/IModularCompliance.sol";
import "../interface/IModule.sol";
import "../storage/ModularComplianceStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ModularCompliance
 * @dev Implementation of modular compliance using Diamond Storage
 * @notice Manages compliance modules for security tokens
 */
contract ModularCompliance is IModularCompliance, Ownable {
    using ModularComplianceStorage for ModularComplianceStorage.Layout;

    uint256 private constant MAX_MODULES = 25;
    
    // Factory address for authorized operations
    address public factory;

    modifier onlyToken() {
        ModularComplianceStorage.Layout storage s = ModularComplianceStorage.layout();
        require(msg.sender == s.tokenBound, "ModularCompliance: caller is not the bound token");
        _;
    }
    
    modifier onlyFactory() {
        require(msg.sender == factory, "ModularCompliance: caller is not the factory");
        _;
    }
    
    modifier onlyOwnerOrFactory() {
        require(msg.sender == owner() || msg.sender == factory, "ModularCompliance: caller is not owner or factory");
        _;
    }

    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Set factory address (can only be called once by owner)
     * @param factory_ The address of the factory
     */
    function setFactory(address factory_) external onlyOwner {
        require(factory == address(0), "ModularCompliance: factory already set");
        require(factory_ != address(0), "ModularCompliance: invalid factory address");
        factory = factory_;
    }

    /**
     * @dev Bind a token to the compliance contract
     * @param _token The address of the token to bind
     */
    function bindToken(address _token) external override onlyOwnerOrFactory {
        require(_token != address(0), "ModularCompliance: invalid token address");
        
        ModularComplianceStorage.Layout storage s = ModularComplianceStorage.layout();
        require(s.tokenBound == address(0), "ModularCompliance: token already bound");
        
        s.tokenBound = _token;
        emit TokenBound(_token);
    }

    /**
     * @dev Unbind a token from the compliance contract
     * @param _token The address of the token to unbind
     */
    function unbindToken(address _token) external override onlyOwner {
        ModularComplianceStorage.Layout storage s = ModularComplianceStorage.layout();
        require(s.tokenBound == _token, "ModularCompliance: token not bound");
        
        s.tokenBound = address(0);
        emit TokenUnbound(_token);
    }

    /**
     * @dev Add a module to the compliance contract
     * @param _module The address of the module to add
     */
    function addModule(address _module) external override onlyOwner {
        require(_module != address(0), "ModularCompliance: invalid module address");
        
        ModularComplianceStorage.Layout storage s = ModularComplianceStorage.layout();
        require(s.modules.length < MAX_MODULES, "ModularCompliance: max modules reached");
        require(!s.moduleBound[_module], "ModularCompliance: module already bound");
        
        // Check if module can be bound
        require(IModule(_module).canComplianceBind(address(this)), "ModularCompliance: module cannot bind");
        
        s.modules.push(_module);
        s.moduleBound[_module] = true;
        
        // Bind compliance to module
        IModule(_module).bindCompliance(address(this));
        
        emit ModuleAdded(_module);
    }

    /**
     * @dev Remove a module from the compliance contract
     * @param _module The address of the module to remove
     */
    function removeModule(address _module) external override onlyOwner {
        ModularComplianceStorage.Layout storage s = ModularComplianceStorage.layout();
        require(s.moduleBound[_module], "ModularCompliance: module not bound");
        
        // Remove from modules array
        for (uint256 i = 0; i < s.modules.length; i++) {
            if (s.modules[i] == _module) {
                s.modules[i] = s.modules[s.modules.length - 1];
                s.modules.pop();
                break;
            }
        }
        
        s.moduleBound[_module] = false;
        
        // Unbind compliance from module
        IModule(_module).unbindCompliance(address(this));
        
        emit ModuleRemoved(_module);
    }

    /**
     * @dev Call a function on a module
     * @param callData The data to call the function on
     * @param _module The address of the module to call the function on
     */
    function callModuleFunction(bytes calldata callData, address _module) external override onlyOwner {
        ModularComplianceStorage.Layout storage s = ModularComplianceStorage.layout();
        require(s.moduleBound[_module], "ModularCompliance: module not bound");
        
        // NOTE: Use assembly to call the interaction instead of a low level
        // call for two reasons:
        // - We don't want to copy the return data, since we discard it for
        // interactions.
        // - Solidity will under certain conditions generate code to copy input
        // calldata twice to memory (the second being a "memcopy loop").
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let freeMemoryPointer := mload(0x40)
            calldatacopy(freeMemoryPointer, callData.offset, callData.length)
            if iszero(
            call(
            gas(),
            _module,
            0,
            freeMemoryPointer,
            callData.length,
            0,
            0
            ))
            {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
        
        emit ModuleInteraction(_module, _selector(callData));
    }

    /**
     * @dev Called when tokens are transferred
     * @param _from The address of the sender
     * @param _to The address of the recipient
     * @param _amount The amount of tokens transferred
     */
    function transferred(
        address _from,
        address _to,
        uint256 _amount
    ) external override onlyToken {
        ModularComplianceStorage.Layout storage s = ModularComplianceStorage.layout();
        
        // Call moduleTransferAction on each module
        for (uint256 i = 0; i < s.modules.length; i++) {
            IModule(s.modules[i]).moduleTransferAction(_from, _to, _amount);
        }
    }

    /**
     * @dev Called when tokens are minted
     * @param _to The address of the recipient
     * @param _amount The amount of tokens minted
     */
    function created(address _to, uint256 _amount) external override onlyToken {
        ModularComplianceStorage.Layout storage s = ModularComplianceStorage.layout();
        
        // Call moduleMintAction on each module
        for (uint256 i = 0; i < s.modules.length; i++) {
            IModule(s.modules[i]).moduleMintAction(_to, _amount);
        }
    }

    /**
     * @dev Called when tokens are burned
     * @param _from The address of the sender
     * @param _amount The amount of tokens burned
     */
    function destroyed(address _from, uint256 _amount) external override onlyToken {
        ModularComplianceStorage.Layout storage s = ModularComplianceStorage.layout();
        
        // Call moduleBurnAction on each module
        for (uint256 i = 0; i < s.modules.length; i++) {
            IModule(s.modules[i]).moduleBurnAction(_from, _amount);
        }
    }

    /**
     * @dev Check if a transfer is compliant
     * @param _from The address of the sender
     * @param _to The address of the recipient
     * @param _amount The amount of tokens transferred
     * @return true if the transfer is compliant, false otherwise
     */
    function canTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) external view override returns (bool) {
        ModularComplianceStorage.Layout storage s = ModularComplianceStorage.layout();
        
        // Check each module
        for (uint256 i = 0; i < s.modules.length; i++) {
            if (!IModule(s.modules[i]).moduleCheck(_from, _to, _amount, address(this))) {
                return false;
            }
        }
        
        return true;
    }

    /**
     * @dev Get all modules
     * @return The addresses of all modules
     */
    function getModules() external view override returns (address[] memory) {
        ModularComplianceStorage.Layout storage s = ModularComplianceStorage.layout();
        return s.modules;
    }

    /**
     * @dev Get the bound token
     * @return The address of the bound token
     */
    function getTokenBound() external view override returns (address) {
        ModularComplianceStorage.Layout storage s = ModularComplianceStorage.layout();
        return s.tokenBound;
    }

    /**
     * @dev Check if a module is bound
     * @param _module The address of the module to check
     * @return true if the module is bound, false otherwise
     */
    function isModuleBound(address _module) external view override returns (bool) {
        ModularComplianceStorage.Layout storage s = ModularComplianceStorage.layout();
        return s.moduleBound[_module];
    }

    /**
     * @dev Extracts the Solidity ABI selector for the specified interaction.
     * @param callData Interaction data.
     * @return result The 4 byte function selector of the call encoded in
     * this interaction.
     */
    function _selector(bytes calldata callData) internal pure returns (bytes4 result) {
        if (callData.length >= 4) {
            // NOTE: Read the first word of the interaction's calldata. The
            // value does not need to be shifted since `bytesN` values are left
            // aligned, and the value does not need to be masked since masking
            // occurs when the value is accessed and not stored:
            // <https://docs.soliditylang.org/en/v0.7.6/abi-spec.html#encoding-of-indexed-event-parameters>
            // <https://docs.soliditylang.org/en/v0.7.6/assembly.html#access-to-external-variables-functions-and-libraries>
            // solhint-disable-next-line no-inline-assembly
            assembly {
                result := calldataload(callData.offset)
            }
        }
    }
}
