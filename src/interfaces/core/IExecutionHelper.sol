// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ExecType, CallType} from "../../types/Types.sol";

/// @title IExecutionHelper
/// @author @cryptonoyaiba | Etherspot
/// @notice Interface for execution capabilities in smart contract wallets
/// @dev Defines events and errors for execution management
interface IExecutionHelper {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an execution completes successfully
    /// @param target The address that was called
    /// @param value The amount of ETH sent with the call
    /// @param result The data returned from the call
    event ExecutionCompleted(address target, uint256 value, bytes result);

    /// @notice Emitted when an execution fails
    /// @param target The address that was called
    /// @param value The amount of ETH sent with the call
    /// @param reason The revert reason from the failed call
    event ExecutionFailed(address indexed target, uint256 value, bytes reason);

    /// @notice Emitted when a batch execution item fails
    /// @param index The index of the failed execution in the batch
    /// @param reason The revert reason from the failed call
    event BatchItemFailed(uint256 indexed index, bytes reason);

    /// @notice Emitted when a delegate call fails
    /// @param delegate The address that was delegate-called
    /// @param reason The revert reason from the failed delegate call
    event DelegateCallFailed(address indexed delegate, bytes reason);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an unsupported call type is used
    /// @param callType The unsupported call type
    error UnsupportedCallType(CallType callType);

    /// @notice Thrown when an unsupported execution type is used
    /// @param execType The unsupported execution type
    error UnsupportedExecType(ExecType execType);

    /// @notice Thrown when an invalid delegate target is provided
    /// @param delegate The invalid delegate target address
    error InvalidDelegateTarget(address delegate);

    /// @notice Thrown when an invalid call target is provided
    /// @param target The invalid call target address
    error InvalidCallTarget(address target);

    /// @notice Thrown when an empty batch execution is attempted
    error EmptyBatchExecution();

    /// @notice Thrown when an invalid target is provided in a batch execution
    /// @param index The index of the invalid target in the batch
    /// @param target The invalid target address
    error InvalidBatchTarget(uint256 index, address target);

    /// @notice Thrown when a self-call is attempted but not allowed
    /// @param index The index of the self-call in the batch
    error SelfCallNotAllowed(uint256 index);

    /// @notice Thrown when an unauthorized call is attempted
    /// @param target The unauthorized target address
    error UnauthorizedCall(address target);
}
