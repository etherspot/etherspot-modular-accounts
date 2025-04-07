// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CallType} from "../../types/Types.sol";

/// @title IModuleManager
/// @author @cryptonoyaiba | Etherspot
/// @notice Interface for managing modules in Etherspot Modular Accounts
/// @dev Defines functions for managing validators, executors, hooks, and fallbacks
interface IModuleManager {
    /// @notice Thrown when an invalid module address is provided
    /// @param module The invalid module address
    error InvalidModule(address module);

    /// @notice Thrown when no fallback handler is available for a function selector
    /// @param selector The function selector that has no handler
    error NoFallbackHandler(bytes4 selector);

    /// @notice Thrown when attempting to remove the last validator
    error CannotRemoveLastValidator();

    /// @notice Thrown when an invalid call type is used for fallback
    error FallbackInvalidCallType();

    /// @notice Thrown when an unauthorized caller tries to use a fallback function
    /// @param caller The unauthorized caller address
    error InvalidFallbackCaller(address caller);

    /// @notice Thrown when attempting to install a hook when one is already installed
    /// @param currentHook The address of the currently installed hook
    error HookAlreadyInstalled(address currentHook);

    /// @notice Thrown when attempting to install a pre validation hook when one is already installed
    /// @param currentHook The address of the currently installed hook
    error PreValidationHookAlreadyInstalled(address currentHook);

    /// @notice Thrown when attempting use an invalid hook type
    error InvalidHookType();

    /// @notice Thrown when a module address is zero
    error ModuleAddressCannotBeZero();

    /// @notice Thrown when a fallback selector is already in use
    /// @param selector The function selector that is already used
    error FallbackSelectorAlreadyUsed(bytes4 selector);

    /// @notice Thrown when a function selector is not used by any fallback handler
    /// @param selector The function selector that is not used
    error FunctionSelectorNotUsed(bytes4 selector);

    /// @notice Thrown when a function selector is not used by the specified handler
    /// @param selector The function selector
    /// @param handler The handler address that doesn't use the selector
    error FunctionSelectorNotUsedByHandler(bytes4 selector, address handler);

    /// @notice Thrown when validator uninstallation fails
    /// @param validator The validator address that failed to uninstall
    /// @param data The data passed to the uninstall function
    error ValidatorUninstallFailed(address validator, bytes data);

    /// @notice Thrown when executor uninstallation fails
    /// @param executor The executor address that failed to uninstall
    /// @param data The data passed to the uninstall function
    error ExecutorUninstallFailed(address executor, bytes data);

    /// @notice Emitted when a fallback function is called
    /// @param selector The function selector that was called
    /// @param caller The address that called the fallback function
    /// @param success Whether the fallback call was successful
    event FallbackCalled(bytes4 selector, address caller, bool success);

    /// @notice Emitted when hook uninstallation fails
    /// @param hook The hook address that failed to uninstall
    /// @param data The data passed to the uninstall function
    event HookUninstallFailed(address hook, bytes data);

    /// @notice Emitted when a uninstallation fails of a pre validation hook
    /// @param hook The hook address that failed to uninstall
    /// @param data The data passed to the uninstall function
    event PreValidationHookUninstallFailed(address hook, bytes data);

    /// @notice Emitted when receive function triggered
    /// @param sender The address that triggered the receive function
    /// @param value The amount of Ether sent
    event Received(address sender, uint256 value);

    /// @notice Gets paginated list of validators
    /// @param _cursor Starting point for pagination
    /// @param _size Number of items to return
    /// @return array Array of validator addresses
    /// @return next Next cursor position
    function getValidatorsPaginated(address _cursor, uint256 _size)
        external
        view
        returns (address[] memory array, address next);

    /// @notice Checks if a validator is installed
    /// @param _validator Address of the validator
    /// @return True if the validator is installed
    function isValidatorInstalled(address _validator) external view returns (bool);

    /// @notice Gets paginated list of executors
    /// @param _cursor Starting point for pagination
    /// @param _size Number of items to return
    /// @return array Array of executor addresses
    /// @return next Next cursor position
    function getExecutorsPaginated(address _cursor, uint256 _size)
        external
        view
        returns (address[] memory array, address next);

    /// @notice Checks if an executor is installed
    /// @param _executor Address of the executor
    /// @return True if the executor is installed
    function isExecutorInstalled(address _executor) external view returns (bool);

    /// @notice Gets the active hook
    /// @return Address of the active hook
    function getActiveHook() external view returns (address);

    /// @notice Gets the ERC-4337 pre-validation hook
    /// @return hook The address of the pre-validation hook for ERC-4337
    function getActivePreValidationHookERC4337() external view returns (address);

    /// @notice Fetches the EIP-1271 pre-validation hook
    /// @return hook The address of the pre-validation hook for EIP-1271
    function getActivePreValidationHookERC1271() external view returns (address);

    /// @notice Gets fallback handler for a selector
    /// @param _selector Function selector
    /// @return callType Type of call
    /// @return handler Address of the handler
    /// @return allowedCallers Array of addresses allowed to call this fallback
    function getFallbackHandler(bytes4 _selector)
        external
        view
        returns (CallType callType, address handler, address[] memory allowedCallers);
}
