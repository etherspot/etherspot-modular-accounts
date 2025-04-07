// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IHook} from "../../interfaces/base/IHook.sol";
import {MODULE_TYPE_HOOK} from "../../types/Constants.sol";
import {ModeSelector} from "../../types/Types.sol";

contract MockHook is IHook {
    function onInstall(bytes calldata data) external override {}

    function onUninstall(bytes calldata data) external override {}

    function preCheck(address msgSender, uint256 msgValue, bytes calldata msgData)
        external
        override
        returns (bytes memory hookData)
    {
        ModeSelector mode = ModeSelector.wrap(bytes4(msgData[10:14]));

        if (mode == ModeSelector.wrap(bytes4(keccak256(abi.encode("revert"))))) {
            revert("revert");
        } else if (mode == ModeSelector.wrap(bytes4(keccak256(abi.encode("revertPost"))))) {
            hookData = abi.encode("revertPost");
        } else {
            hookData = abi.encode("success");
        }
    }

    function postCheck(bytes calldata hookData) external override {
        if (keccak256(hookData) == keccak256(abi.encode("revertPost"))) {
            revert("revertPost");
        }
    }

    function isInitialized(address smartAccount) external pure returns (bool) {
        return false;
    }

    function isModuleType(uint256 typeID) external pure returns (bool) {
        return typeID == MODULE_TYPE_HOOK;
    }
}
