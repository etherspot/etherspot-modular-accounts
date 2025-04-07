// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IExecutionHelper} from "../interfaces/core/IExecutionHelper.sol";
import {ExecutionLib} from "../libraries/ExecutionLib.sol";
import {
    EXECTYPE_DEFAULT,
    EXECTYPE_TRY,
    CALLTYPE_SINGLE,
    CALLTYPE_BATCH,
    CALLTYPE_DELEGATECALL
} from "../types/Constants.sol";
import {Execution} from "../types/Structs.sol";
import {ExecType, CallType} from "../types/Types.sol";

/// @title ExecutionHelper
/// @author @cryptonoyaiba | Etherspot
/// @notice Provides execution capabilities for smart contract wallets
/// @dev Enhanced execution management for Etherspot Modular Accounts
///      Based on ERC7579 implementation standard with modifications
contract ExecutionHelper is IExecutionHelper {
    using ExecutionLib for bytes;

    /*//////////////////////////////////////////////////////////////
                          EXECUTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Process execution based on call type and execution type
    /// @dev Routes the execution to the appropriate handler based on call and execution types
    /// @param _callType The type of call (batch, single, delegatecall)
    /// @param _execType The type of execution (default, try)
    /// @param _executionCalldata The calldata for the execution
    /// @param _returnOutput Whether to return output data
    /// @return returnData The return data from the execution (only used when returnOutput is true)
    function _processExecution(
        CallType _callType,
        ExecType _execType,
        bytes calldata _executionCalldata,
        bool _returnOutput
    ) internal returns (bytes[] memory returnData) {
        if (_callType == CALLTYPE_BATCH) {
            return _processBatchCall(_execType, _executionCalldata, _returnOutput);
        } else if (_callType == CALLTYPE_SINGLE) {
            return _processSingleCall(_execType, _executionCalldata, _returnOutput);
        } else if (_callType == CALLTYPE_DELEGATECALL) {
            return _processDelegateCall(_execType, _executionCalldata, _returnOutput);
        } else {
            revert UnsupportedCallType(_callType);
        }
    }

    /// @notice Process a batch call
    /// @dev Handles batch execution with different execution types
    /// @param _execType The type of execution (default, try)
    /// @param _executionCalldata The calldata containing the batch of executions
    /// @param _returnOutput Whether to return output data
    /// @return returnData The return data from the batch execution
    function _processBatchCall(ExecType _execType, bytes calldata _executionCalldata, bool _returnOutput)
        internal
        returns (bytes[] memory returnData)
    {
        Execution[] calldata executions = _executionCalldata.decodeBatch();
        uint256 length = executions.length;
        if (!_returnOutput) {
            if (_execType == EXECTYPE_DEFAULT) {
                _executeBatchWithoutReturn(executions);
            } else if (_execType == EXECTYPE_TRY) {
                _tryExecuteBatchWithoutReturn(executions);
            } else {
                revert UnsupportedExecType(_execType);
            }
            return new bytes[](0);
        }
        returnData = new bytes[](length);
        if (_execType == EXECTYPE_DEFAULT) {
            for (uint256 i; i < length; ++i) {
                Execution calldata execution = executions[i];
                returnData[i] = _execute(execution.target, execution.value, execution.callData);
            }
        } else if (_execType == EXECTYPE_TRY) {
            for (uint256 i; i < length; ++i) {
                Execution calldata execution = executions[i];
                bool success;
                (success, returnData[i]) = _tryExecute(execution.target, execution.value, execution.callData);
                if (!success) {
                    emit BatchItemFailed(i, returnData[i]);
                }
            }
        } else {
            revert UnsupportedExecType(_execType);
        }
        return returnData;
    }

    /// @notice Process a single call
    /// @dev Handles single execution with different execution types
    /// @param _execType The type of execution (default, try)
    /// @param _executionCalldata The calldata containing the single execution
    /// @param _returnOutput Whether to return output data
    /// @return returnData The return data from the single execution
    function _processSingleCall(ExecType _execType, bytes calldata _executionCalldata, bool _returnOutput)
        internal
        returns (bytes[] memory returnData)
    {
        (address target, uint256 value, bytes calldata callData) = _executionCalldata.decodeSingle();
        if (!_returnOutput) {
            if (_execType == EXECTYPE_DEFAULT) {
                _executeWithoutReturn(target, value, callData);
            } else if (_execType == EXECTYPE_TRY) {
                bool success;
                bytes memory result;
                (success, result) = _tryExecute(target, value, callData);
                if (!success) {
                    emit ExecutionFailed(target, value, result);
                }
            } else {
                revert UnsupportedExecType(_execType);
            }
            return new bytes[](0);
        }
        returnData = new bytes[](1);
        if (_execType == EXECTYPE_DEFAULT) {
            returnData[0] = _execute(target, value, callData);
        } else if (_execType == EXECTYPE_TRY) {
            bool success;
            (success, returnData[0]) = _tryExecute(target, value, callData);
            if (!success) {
                emit ExecutionFailed(target, value, returnData[0]);
            }
        } else {
            revert UnsupportedExecType(_execType);
        }
        return returnData;
    }

    /// @notice Process a delegate call
    /// @dev Handles delegate call execution with different execution types
    /// @param _execType The type of execution (default, try)
    /// @param _executionCalldata The calldata containing the delegate call data
    /// @param _returnOutput Whether to return output data
    /// @return returnData The return data from the delegate call
    function _processDelegateCall(ExecType _execType, bytes calldata _executionCalldata, bool _returnOutput)
        internal
        returns (bytes[] memory returnData)
    {
        address delegate = address(uint160(bytes20(_executionCalldata[0:20])));
        bytes calldata callData = _executionCalldata[20:];
        if (!_returnOutput) {
            if (_execType == EXECTYPE_DEFAULT) {
                _executeDelegatecallWithoutReturn(delegate, callData);
            } else if (_execType == EXECTYPE_TRY) {
                bool success;
                bytes memory result;
                (success, result) = _tryExecuteDelegatecall(delegate, callData);
                if (!success) {
                    emit DelegateCallFailed(delegate, result);
                }
            } else {
                revert UnsupportedExecType(_execType);
            }
            return new bytes[](0);
        }
        returnData = new bytes[](1);
        if (_execType == EXECTYPE_DEFAULT) {
            returnData[0] = _executeDelegatecall(delegate, callData);
        } else if (_execType == EXECTYPE_TRY) {
            bool success;
            (success, returnData[0]) = _tryExecuteDelegatecall(delegate, callData);
            if (!success) {
                emit DelegateCallFailed(delegate, returnData[0]);
            }
        } else {
            revert UnsupportedExecType(_execType);
        }
        return returnData;
    }

    /*//////////////////////////////////////////////////////////////
                      OPTIMIZED EXECUTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute a call without capturing return data for gas efficiency
    /// @dev Uses assembly for optimal gas usage
    /// @param _target The address to call
    /// @param _value The amount of ETH to send
    /// @param _callData The calldata to send
    function _executeWithoutReturn(address _target, uint256 _value, bytes calldata _callData) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let result := mload(0x40)
            calldatacopy(result, _callData.offset, _callData.length)
            if iszero(call(gas(), _target, _value, result, _callData.length, 0, 0)) {
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            // No need to allocate memory for return data
        }
    }

    /// @notice Execute a batch without capturing return data for gas efficiency
    /// @dev Optimized for gas by not capturing return data
    /// @param _executions Array of Execution structs to execute
    function _executeBatchWithoutReturn(Execution[] calldata _executions) internal {
        uint256 length = _executions.length;
        for (uint256 i; i < length; ++i) {
            Execution calldata execution = _executions[i];
            _executeWithoutReturn(execution.target, execution.value, execution.callData);
        }
    }

    /// @notice Try to execute a batch without capturing return data for gas efficiency
    /// @dev Continues execution even if individual items fail
    /// @param _executions Array of Execution structs to try executing
    function _tryExecuteBatchWithoutReturn(Execution[] calldata _executions) internal {
        uint256 length = _executions.length;
        for (uint256 i; i < length; ++i) {
            Execution calldata execution = _executions[i];
            bool success;
            bytes memory result;
            (success, result) = _tryExecute(execution.target, execution.value, execution.callData);
            if (!success) {
                emit BatchItemFailed(i, result);
            }
        }
    }

    /// @notice Execute a delegatecall without capturing return data for gas efficiency
    /// @dev Uses assembly for optimal gas usage
    /// @param _delegate The address to delegatecall
    /// @param _callData The calldata to send
    function _executeDelegatecallWithoutReturn(address _delegate, bytes calldata _callData) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let result := mload(0x40)
            calldatacopy(result, _callData.offset, _callData.length)
            if iszero(delegatecall(gas(), _delegate, result, _callData.length, 0, 0)) {
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            // No need to allocate memory for return data
        }
    }

    /*//////////////////////////////////////////////////////////////
                      STANDARD EXECUTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Standard function to execute a call and return the result
    /// @dev Uses assembly for optimal handling of dynamic return data
    /// @param _target The address to call
    /// @param _value The amount of ETH to send
    /// @param _callData The calldata to send
    /// @return result The data returned from the call
    function _execute(address _target, uint256 _value, bytes calldata _callData)
        internal
        returns (bytes memory result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            calldatacopy(result, _callData.offset, _callData.length)
            if iszero(call(gas(), _target, _value, result, _callData.length, codesize(), 0x00)) {
                // Bubble up the revert if the call reverts.
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            mstore(result, returndatasize()) // Store the length.
            let o := add(result, 0x20)
            returndatacopy(o, 0x00, returndatasize()) // Copy the returndata.
            mstore(0x40, add(o, returndatasize())) // Allocate the memory.
        }
        emit ExecutionCompleted(_target, _value, result);
    }

    /// @notice Standard function to try executing a call and return the result
    /// @dev Doesn't revert if the call fails, instead returns success flag
    /// @param _target The address to call
    /// @param _value The amount of ETH to send
    /// @param _callData The calldata to send
    /// @return success Whether the call succeeded
    /// @return result The data returned from the call or error data if failed
    function _tryExecute(address _target, uint256 _value, bytes calldata _callData)
        internal
        returns (bool success, bytes memory result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            calldatacopy(result, _callData.offset, _callData.length)
            success := call(gas(), _target, _value, result, _callData.length, codesize(), 0x00)
            mstore(result, returndatasize()) // Store the length.
            let o := add(result, 0x20)
            returndatacopy(o, 0x00, returndatasize()) // Copy the returndata.
            mstore(0x40, add(o, returndatasize())) // Allocate the memory.
        }
    }

    /// @notice Standard function to execute a delegatecall and return the result
    /// @dev Uses assembly for optimal handling of dynamic return data
    /// @param _delegate The address to delegatecall
    /// @param _callData The calldata to send
    /// @return result The data returned from the delegatecall
    function _executeDelegatecall(address _delegate, bytes calldata _callData) internal returns (bytes memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            calldatacopy(result, _callData.offset, _callData.length)
            // Forwards the `data` to `delegate` via delegatecall.
            if iszero(delegatecall(gas(), _delegate, result, _callData.length, codesize(), 0x00)) {
                // Bubble up the revert if the call reverts.
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            mstore(result, returndatasize()) // Store the length.
            let o := add(result, 0x20)
            returndatacopy(o, 0x00, returndatasize()) // Copy the returndata.
            mstore(0x40, add(o, returndatasize())) // Allocate the memory.
        }
    }

    /// @notice Standard function to try executing a delegatecall and return the result
    /// @dev Doesn't revert if the delegatecall fails, instead returns success flag
    /// @param _delegate The address to delegatecall
    /// @param _callData The calldata to send
    /// @return success Whether the delegatecall succeeded
    /// @return result The data returned from the delegatecall or error data if failed
    function _tryExecuteDelegatecall(address _delegate, bytes calldata _callData)
        internal
        returns (bool success, bytes memory result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            calldatacopy(result, _callData.offset, _callData.length)
            // Forwards the `data` to `delegate` via delegatecall.
            success := delegatecall(gas(), _delegate, result, _callData.length, codesize(), 0x00)
            mstore(result, returndatasize()) // Store the length.
            let o := add(result, 0x20)
            returndatacopy(o, 0x00, returndatasize()) // Copy the returndata.
            mstore(0x40, add(o, returndatasize())) // Allocate the memory.
        }
    }

    /*//////////////////////////////////////////////////////////////
                          UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute a batch of calls and return results
    /// @dev Executes each call in the batch and collects results
    /// @param _executions Array of Execution structs
    /// @return result Array of results from each call
    function _execute(Execution[] calldata _executions) internal returns (bytes[] memory result) {
        uint256 length = _executions.length;
        result = new bytes[](length);
        for (uint256 i; i < length; ++i) {
            Execution calldata execution = _executions[i];
            result[i] = _execute(execution.target, execution.value, execution.callData);
        }
    }

    /// @notice Try to execute a batch of calls and return results
    /// @dev Attempts each call in the batch and continues even if some fail
    /// @param _executions Array of Execution structs
    /// @return result Array of results from each call (or error data for failed calls)
    function _tryExecute(Execution[] calldata _executions) internal returns (bytes[] memory result) {
        uint256 length = _executions.length;
        result = new bytes[](length);
        for (uint256 i; i < length; ++i) {
            Execution calldata execution = _executions[i];
            bool success;
            (success, result[i]) = _tryExecute(execution.target, execution.value, execution.callData);
            if (!success) {
                emit BatchItemFailed(i, result[i]);
            }
        }
    }
}
