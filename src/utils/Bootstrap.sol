// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ModuleManager} from "../core/ModuleManager.sol";
import {IModule} from "../interfaces/base/IModule.sol";

struct BootstrapConfig {
    address module;
    bytes data;
}

/// @title Bootstrap
/// @author @cryptonoyaiba | Etherspot
/// @notice Contract for initializing modular smart accounts with various modules
/// @dev This contract is meant to be delegatecalled by a smart account during initialization
contract Bootstrap is ModuleManager {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidModuleAddress();

    /*//////////////////////////////////////////////////////////////
                           PUBLIC/EXTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes an account with a single validator module
    /// @param _validator The validator module to install
    /// @param _data Initialization data for the validator
    function initializeWithSingleValidator(IModule _validator, bytes calldata _data) external {
        if (address(_validator) == address(0)) revert InvalidModuleAddress();

        _installValidator(address(_validator), _data);
    }

    /// @notice Initializes an account with multiple modules
    /// @dev This function is intended to be called by the account with a delegatecall
    /// @param _validators Array of validator modules to install
    /// @param _executors Array of executor modules to install
    /// @param _hook Hook module to install
    /// @param _fallbacks Array of fallback handler modules to install
    function initializeModularAccount(
        BootstrapConfig[] calldata _validators,
        BootstrapConfig[] calldata _executors,
        BootstrapConfig calldata _hook,
        BootstrapConfig[] calldata _fallbacks
    ) external {
        // Init validators
        for (uint256 i; i < _validators.length; ++i) {
            _installValidator(_validators[i].module, _validators[i].data);
        }
        // Init executors
        for (uint256 i; i < _executors.length; ++i) {
            if (_executors[i].module == address(0)) continue;
            _installExecutor(_executors[i].module, _executors[i].data);
        }
        // Init hook
        if (_hook.module != address(0)) {
            _installHook(_hook.module, _hook.data);
        }
        // Init fallback
        for (uint256 i; i < _fallbacks.length; ++i) {
            if (_fallbacks[i].module == address(0)) continue;
            _installFallbackHandler(_fallbacks[i].module, _fallbacks[i].data);
        }
    }

    /// @notice Generates the calldata needed to initialize an account
    /// @param _validators Array of validator modules to install
    /// @param _executors Array of executor modules to install
    /// @param _hook Hook module to install
    /// @param _fallbacks Array of fallback handler modules to install
    /// @return init The encoded initialization calldata
    function getInitializationCalldata(
        BootstrapConfig[] calldata _validators,
        BootstrapConfig[] calldata _executors,
        BootstrapConfig calldata _hook,
        BootstrapConfig[] calldata _fallbacks
    ) external view returns (bytes memory init) {
        init = abi.encode(
            address(this), abi.encodeCall(this.initializeModularAccount, (_validators, _executors, _hook, _fallbacks))
        );
    }

    /// @notice Required to override for import
    function _onRedelegation() internal override {
        // only required for import
    }

    /// @dev EIP712 domain name and version.
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "Bootstrap";
        version = "1.0.0";
    }
}
