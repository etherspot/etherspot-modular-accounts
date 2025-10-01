// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../../src/ERC7579/core/ModuleManager.sol";
import "../../src/ERC7579/core/HookManager.sol";
import "../../src/ERC7579/interfaces/IERC7579Module.sol";

struct BootstrapConfig {
    address module;
    bytes data;
}

contract Bootstrap is ModuleManager, HookManager {
    function singleInitMSA(IModule validator, bytes calldata data) external {
        // init validator
        _installValidator(address(validator), data);
    }

    /**
     * This function is intended to be called by the MSA with a delegatecall.
     * Make sure that the MSA already initialized the linked lists in the ModuleManager prior to
     * calling this function
     */
    function initMSA(
        BootstrapConfig[] calldata $validators,
        BootstrapConfig[] calldata $executors,
        BootstrapConfig calldata _hook,
        BootstrapConfig[] calldata _fallbacks
    ) external {
        // init hook
        if (_hook.module != address(0)) _installHook(_hook.module, _hook.data);
        // init validators
        for (uint256 i; i < $validators.length; i++) {
            _installValidator($validators[i].module, $validators[i].data);
        }
        // init executors
        for (uint256 i; i < $executors.length; i++) {
            if ($executors[i].module == address(0)) continue;
            _installExecutor($executors[i].module, $executors[i].data);
        }
        // init fallback
        for (uint256 i; i < _fallbacks.length; i++) {
            if (_fallbacks[i].module == address(0)) continue;
            _installFallbackHandler(_fallbacks[i].module, _fallbacks[i].data);
        }
    }

    function _getInitMSACalldata(
        BootstrapConfig[] calldata $validators,
        BootstrapConfig[] calldata $executors,
        BootstrapConfig calldata _hook,
        BootstrapConfig[] calldata _fallbacks
    ) external view returns (bytes memory init) {
        init = abi.encode(address(this), abi.encodeCall(this.initMSA, ($validators, $executors, _hook, _fallbacks)));
    }
}

contract BootstrapUtil {
    Bootstrap bootstrap;

    constructor() {
        bootstrap = new Bootstrap();
    }

    function _makeBootstrapConfig(address module, bytes memory data)
        public
        pure
        returns (BootstrapConfig memory config)
    {
        config.module = module;
        config.data = abi.encodeCall(IModule.onInstall, data);
    }

    function makeBootstrapConfig(address module, bytes memory data)
        public
        pure
        returns (BootstrapConfig[] memory config)
    {
        config = new BootstrapConfig[](1);
        config[0].module = module;
        config[0].data = abi.encodeCall(IModule.onInstall, data);
    }

    function makeBootstrapConfig(address[] memory modules, bytes[] memory datas)
        public
        pure
        returns (BootstrapConfig[] memory configs)
    {
        configs = new BootstrapConfig[](modules.length);
        for (uint256 i; i < modules.length; i++) {
            configs[i] = _makeBootstrapConfig(modules[i], datas[i]);
        }
    }
}
