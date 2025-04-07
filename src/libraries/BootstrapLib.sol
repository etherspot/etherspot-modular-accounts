// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BootstrapConfig} from "../utils/Bootstrap.sol";
import {IModule} from "../interfaces/base/IModule.sol";

/// @title BootstrapLib
/// @author @cryptonoyaiba | Etherspot
/// @notice Library for creating bootstrap configurations for module installations
/// @dev Used to prepare initialization data for ERC7579 modular accounts
library BootstrapLib {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when module address is invalid (zero address)
    error InvalidModuleAddress();
    /// @notice Thrown when module and data arrays have different lengths
    error LengthMismatch();

    /*//////////////////////////////////////////////////////////////
                           INTERNAL/PRIVATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a single BootstrapConfig
    /// @param _module Address of the module to install
    /// @param _data Initialization data for the module
    /// @return config BootstrapConfig with the module and encoded installation data
    function _buildSingleConfig(address _module, bytes memory _data)
        internal
        pure
        returns (BootstrapConfig memory config)
    {
        if (_module == address(0)) revert InvalidModuleAddress();
        config.module = _module;
        config.data = abi.encodeCall(IModule.onInstall, _data);
    }

    /// @notice Creates an array with a single BootstrapConfig.
    /// @param _module The address of the module.
    /// @param _data The initialization data for the module.
    /// @return config An array containing a single BootstrapConfig.
    function _buildArrayConfig(address _module, bytes memory _data)
        internal
        pure
        returns (BootstrapConfig[] memory config)
    {
        if (_module == address(0)) revert InvalidModuleAddress();
        config = new BootstrapConfig[](1);
        config[0].module = _module;
        config[0].data = abi.encodeCall(IModule.onInstall, _data);
    }

    /// @notice Create an array of BootstrapConfigs
    /// @param _modules Array of module addresses
    /// @param _datas Array of initialization data for each module
    /// @return configs Array of BootstrapConfigs
    function _buildMultipleConfigs(address[] memory _modules, bytes[] memory _datas)
        internal
        pure
        returns (BootstrapConfig[] memory configs)
    {
        if (_modules.length != _datas.length) revert LengthMismatch();
        configs = new BootstrapConfig[](_modules.length);
        for (uint256 i; i < _modules.length; ++i) {
            configs[i] = _buildSingleConfig(_modules[i], _datas[i]);
        }
    }

    /// @notice Create an empty BootstrapConfig
    /// @return config Empty BootstrapConfig

    function _buildEmptySingleConfig() internal pure returns (BootstrapConfig memory config) {
        return BootstrapConfig({module: address(0), data: ""});
    }

    /// @notice Create an empty BootstrapConfig array
    /// @return configs Empty BootstrapConfig array
    function _buildEmptyArrayConfig() internal pure returns (BootstrapConfig[] memory configs) {
        return new BootstrapConfig[](0);
    }
}
