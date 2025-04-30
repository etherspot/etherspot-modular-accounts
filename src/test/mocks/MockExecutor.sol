// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IExecutor} from "../../interfaces/base/IExecutor.sol";
import {IERC7579Account} from "../../interfaces/base/IERC7579Account.sol";
import {ExecutionLib} from "../../libraries/ExecutionLib.sol";
import {ModeLib} from "../../libraries/ModeLib.sol";
import {CALLTYPE_DELEGATECALL, EXECTYPE_DEFAULT, MODE_DEFAULT, MODULE_TYPE_EXECUTOR} from "../../types/Constants.sol";
import {Execution} from "../../types/Structs.sol";
import {ModePayload} from "../../types/Types.sol";

contract MockExecutor is IExecutor {
    function onInstall(bytes calldata data) external override {}

    function onUninstall(bytes calldata data) external override {}

    function executeViaAccount(IERC7579Account account, address target, uint256 value, bytes calldata callData)
        external
        returns (bytes[] memory returnData)
    {
        return account.executeFromExecutor(
            ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(target, value, callData)
        );
    }

    function execBatch(IERC7579Account account, Execution[] calldata execs)
        external
        returns (bytes[] memory returnData)
    {
        return account.executeFromExecutor(ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(execs));
    }

    function execDelegatecall(IERC7579Account account, bytes calldata callData)
        external
        returns (bytes[] memory returnData)
    {
        return account.executeFromExecutor(
            ModeLib.encode(CALLTYPE_DELEGATECALL, EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00)), callData
        );
    }

    function isModuleType(uint256 moduleTypeId) external view returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR;
    }

    function isInitialized(address smartAccount) external view returns (bool) {
        return false;
    }
}
