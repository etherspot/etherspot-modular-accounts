// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IModule} from "ERC7579/interfaces/IERC7579Module.sol";

contract MockModule is IModule {
    function isModuleType(uint256) external view returns (bool) {
        return true;
    }

    function onInstall(bytes calldata) external {}

    function onUninstall(bytes calldata) external {}

    function isInitialized(address smartAccount) external view returns (bool) {
        return false;
    }

    receive() external payable {}
}
