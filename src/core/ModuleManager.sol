// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ExcessivelySafeCall} from "excessively-safe-call/src/ExcessivelySafeCall.sol";
import {EIP712} from "solady/src/utils/EIP712.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IModuleManager} from "../interfaces/core/IModuleManager.sol";
import {IExecutionHelper} from "../interfaces/core/IExecutionHelper.sol";
import {IHook} from "../interfaces/base/IHook.sol";
import {IModule} from "../interfaces/base/IModule.sol";
import {IPreValidationHookERC1271, IPreValidationHookERC4337} from "../interfaces/base/IPreValidationHook.sol";
import {IExecutor} from "../interfaces/base/IExecutor.sol";
import {IFallback} from "../interfaces/base/IFallback.sol";
import {IValidator} from "../interfaces/base/IValidator.sol";
import {AccountStorage} from "./AccountStorage.sol";
import {ERC7779Adapter} from "./ERC7779Adapter.sol";
import {SentinelListLib, SENTINEL} from "../libraries/SentinelList.sol";
import {
    CALLTYPE_DELEGATECALL,
    CALLTYPE_SINGLE,
    CALLTYPE_STATIC,
    EIP7702_PREFIX,
    ETHERSPOT_STORAGE_SLOT,
    MODULE_TYPE_PREVALIDATION_HOOK_ERC1271,
    MODULE_TYPE_PREVALIDATION_HOOK_ERC4337
} from "../types/Constants.sol";
import {CallType} from "../types/Types.sol";

/// @title ModuleManager
/// @author @cryptonoyaiba | Etherspot
/// @notice Manages modules for Etherspot Modular Accounts including validators, executors, hooks, and fallbacks
/// @dev This contract manages Validator, Executor, Hook and Fallback modules for Etherspot Modular Accounts
///      It uses SentinelList to manage the linked list of modules and implements ERC-7201 storage
///      Based on ERC7579 implementation standard with modifications
abstract contract ModuleManager is IModuleManager, EIP712, AccountStorage, ERC7779Adapter {
    using SentinelListLib for SentinelListLib.SentinelList;
    using ExcessivelySafeCall for address;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Ensures the message sender is a registered executor module
    /// @dev Reverts if the sender is not an installed executor
    modifier onlyExecutorModule() {
        if (!_isExecutorInstalled(msg.sender)) revert InvalidModule(msg.sender);
        _;
    }

    /// @notice Executes pre-checks and post-checks using the installed hook
    /// @dev If no hook is installed, executes the function directly

    modifier withHook() {
        address hook = _getHook();
        if (hook == address(0)) {
            _;
        } else {
            bytes memory hookData = IHook(hook).preCheck(msg.sender, msg.value, msg.data);
            _;
            IHook(hook).postCheck(hookData);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the module manager
    /// @dev Sets up the linked lists for validators and executors
    function _initModuleManager() internal virtual {
        AccountStorage storage accountStorage = _getAccountStorage();
        accountStorage.validators.init();
        accountStorage.executors.init();
        accountStorage.initialized = true;

        if (_isEIP7702Account()) {
            _addStorageBase(ETHERSPOT_STORAGE_SLOT);
        }
    }

    /*//////////////////////////////////////////////////////////////
                               EIP7702
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if the account was deployed using EIP7702
    /// @dev Compares the code hash against the EIP7702 prefix
    /// @return True if the account was deployed using EIP7702, false otherwise
    function _isEIP7702Account() internal view returns (bool) {
        bytes32 codeHash;
        assembly {
            codeHash := extcodehash(address())
        }
        return codeHash == keccak256(abi.encodePacked(EIP7702_PREFIX));
    }

    /*//////////////////////////////////////////////////////////////
                        VALIDATOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Installs a validator module
    /// @dev Adds the validator to the linked list and calls its onInstall function
    /// @param _validator Address of the validator module
    /// @param _data Initialization data for the validator
    function _installValidator(address _validator, bytes calldata _data) internal virtual {
        if (_validator == address(0)) revert ModuleAddressCannotBeZero();
        AccountStorage storage accountStorage = _getAccountStorage();
        accountStorage.validators.push(_validator);
        IValidator(_validator).onInstall(_data);
    }

    /// @notice Uninstalls a validator module
    /// @dev Removes the validator from the linked list and calls its onUninstall function
    /// @param _validator Address of the validator module
    /// @param _data De-initialization data for the validator
    function _uninstallValidator(address _validator, bytes calldata _data) internal {
        // Check if it's the last validator
        if (_hasOnlyOneValidator()) {
            revert CannotRemoveLastValidator();
        }
        (address prev, bytes memory disableModuleData) = abi.decode(_data, (address, bytes));
        _getAccountStorage().validators.pop(prev, _validator);
        // Use ExcessivelySafeCall for safer external calls
        (bool success,) = _validator.excessivelySafeCall(
            gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, disableModuleData)
        );
        if (!success) {
            revert ValidatorUninstallFailed(_validator, disableModuleData);
        }
    }

    /// @notice Attempts to uninstall all validators
    /// @dev Used during account recovery or migration
    function _tryUninstallValidators() internal {
        SentinelListLib.SentinelList storage validators = _getAccountStorage().validators;
        address validator = validators.getNext(SENTINEL);
        while (validator != SENTINEL) {
            (bool success,) =
                validator.excessivelySafeCall(gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, ""));
            if (!success) {
                revert ValidatorUninstallFailed(validator, "");
            }
            validator = validators.getNext(validator);
        }
        validators.popAll();
    }

    /// @notice Checks if a validator is installed
    /// @param _validator Address of the validator
    /// @return True if the validator is installed
    function isValidatorInstalled(address _validator) public view returns (bool) {
        return _isValidatorInstalled(_validator);
    }

    /// @notice Checks if a validator is installed
    /// @param _validator Address of the validator
    /// @return True if the validator is installed
    function _isValidatorInstalled(address _validator) internal view virtual returns (bool) {
        return _getAccountStorage().validators.contains(_validator);
    }

    /// @notice Gets paginated list of validators
    /// @param _cursor Starting point for pagination
    /// @param _size Number of items to return
    /// @return array Array of validator addresses
    /// @return next Next cursor position
    function getValidatorsPaginated(address _cursor, uint256 _size)
        external
        view
        virtual
        returns (address[] memory array, address next)
    {
        return _getAccountStorage().validators.getEntriesPaginated(_cursor, _size);
    }

    /// @notice Checks if there is only one validator installed
    /// @return True if there is only one validator
    function _hasOnlyOneValidator() internal view virtual returns (bool) {
        SentinelListLib.SentinelList storage validators = _getAccountStorage().validators;
        address firstValidator = validators.getNext(SENTINEL);
        return firstValidator != SENTINEL && validators.getNext(firstValidator) == SENTINEL;
    }

    /*//////////////////////////////////////////////////////////////
                        EXECUTOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Installs an executor module
    /// @dev Adds the executor to the linked list and calls its onInstall function
    /// @param _executor Address of the executor module
    /// @param _data Initialization data for the executor
    function _installExecutor(address _executor, bytes calldata _data) internal {
        if (_executor == address(0)) revert ModuleAddressCannotBeZero();
        AccountStorage storage accountStorage = _getAccountStorage();
        accountStorage.executors.push(_executor);
        IExecutor(_executor).onInstall(_data);
    }

    /// @notice Uninstalls an executor module
    /// @dev Removes the executor from the linked list and calls its onUninstall function
    /// @param _executor Address of the executor module
    /// @param _data De-initialization data for the executor
    function _uninstallExecutor(address _executor, bytes calldata _data) internal {
        (address prev, bytes memory disableModuleData) = abi.decode(_data, (address, bytes));
        _getAccountStorage().executors.pop(prev, _executor);
        (bool success,) = _executor.excessivelySafeCall(
            gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, disableModuleData)
        );
        if (!success) {
            revert ExecutorUninstallFailed(_executor, disableModuleData);
        }
    }

    /// @notice Attempts to uninstall all executors
    /// @dev Used during account recovery or migration
    function _tryUninstallExecutors() internal {
        SentinelListLib.SentinelList storage executors = _getAccountStorage().executors;
        address executor = executors.getNext(SENTINEL);
        while (executor != SENTINEL) {
            (bool success,) =
                executor.excessivelySafeCall(gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, ""));
            if (!success) {
                revert ExecutorUninstallFailed(executor, "");
            }
            executor = executors.getNext(executor);
        }
        executors.popAll();
    }

    /// @notice Checks if an executor is installed
    /// @param _executor Address of the executor
    /// @return True if the executor is installed
    function isExecutorInstalled(address _executor) public view returns (bool) {
        return _isExecutorInstalled(_executor);
    }

    /// @notice Checks if an executor is installed
    /// @param _executor Address of the executor
    /// @return True if the executor is installed
    function _isExecutorInstalled(address _executor) internal view virtual returns (bool) {
        return _getAccountStorage().executors.contains(_executor);
    }

    /// @notice Gets paginated list of executors
    /// @param _cursor Starting point for pagination
    /// @param _size Number of items to return
    /// @return array Array of executor addresses
    /// @return next Next cursor position
    function getExecutorsPaginated(address _cursor, uint256 _size)
        external
        view
        virtual
        returns (address[] memory array, address next)
    {
        return _getAccountStorage().executors.getEntriesPaginated(_cursor, _size);
    }

    /*//////////////////////////////////////////////////////////////
                           HOOK MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Installs a hook module
    /// @dev Sets the hook and calls its onInstall function
    /// @param _hook Address of the hook module
    /// @param _data Initialization data for the hook
    function _installHook(address _hook, bytes calldata _data) internal virtual {
        if (_hook == address(0)) revert ModuleAddressCannotBeZero();
        address currentHook = _getHook();
        if (currentHook != address(0)) revert HookAlreadyInstalled(currentHook);
        _setHook(_hook);
        IHook(_hook).onInstall(_data);
    }

    /// @notice Uninstalls a hook module
    /// @dev Removes the hook and calls its onUninstall function
    /// @param _hook Address of the hook module
    /// @param _data De-initialization data for the hook
    function _uninstallHook(address _hook, bytes calldata _data) internal virtual {
        if (_hook != address(0)) {
            _setHook(address(0));
            (bool success,) =
                _hook.excessivelySafeCall(gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, _data));
            if (!success) {
                emit HookUninstallFailed(_hook, _data);
            }
        }
    }

    /// @notice Attempts to uninstall a hook module safely
    /// @dev Calls the hook's onUninstall function and catches any errors to prevent transaction failure
    /// If the hook's onUninstall function fails, it emits a HookUninstallFailed event
    /// Always sets the hook to address(0) regardless of success or failure
    function _tryUninstallHook() internal virtual {
        address hook = _getHook();
        if (hook != address(0)) {
            try IHook(hook).onUninstall("") {}
            catch (bytes memory reason) {
                emit HookUninstallFailed(hook, reason);
            }
            _setHook(address(0));
        }
    }

    /// @notice Sets the hook module
    /// @param _hook Address of the hook module
    function _setHook(address _hook) internal virtual {
        _getAccountStorage().hook = IHook(_hook);
    }

    /// @notice Gets the current hook module
    /// @return Address of the installed hook
    function _getHook() internal view virtual returns (address) {
        return address(_getAccountStorage().hook);
    }

    /// @notice Checks if a hook is installed
    /// @param _hook Address of the hook
    /// @return True if the hook is installed
    function _isHookInstalled(address _hook) internal view virtual returns (bool) {
        return _getHook() == _hook;
    }

    /// @notice Gets the active hook
    /// @return Address of the active hook
    function getActiveHook() external view returns (address) {
        return _getHook();
    }

    /*//////////////////////////////////////////////////////////////
                    PRE VALIDATION HOOK MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets the ERC-4337 pre-validation hook.
    /// @return hook The address of the pre-validation hook for ERC-4337.
    function getActivePreValidationHookERC4337() public view returns (address) {
        return address(_getAccountStorage().preValidationHookERC4337);
    }

    /// @notice Fetches the EIP-1271 pre-validation hook.
    /// @return hook The address of the pre-validation hook for EIP-1271.
    function getActivePreValidationHookERC1271() public view returns (address) {
        return address(_getAccountStorage().preValidationHookERC1271);
    }

    /// @dev Installs a pre-validation hook module.
    /// @param _pvHookType The module type of the pre-validation hook (ERC-4337/ERC-1271).
    /// @param _pvHook The address of the pre-validation hook to be installed.
    /// @param _data Init data to configure hook upon installation.
    function _installPreValidationHook(uint256 _pvHookType, address _pvHook, bytes calldata _data) internal virtual {
        address activePVHook;
        if (_pvHookType == MODULE_TYPE_PREVALIDATION_HOOK_ERC1271) {
            activePVHook = getActivePreValidationHookERC1271();
        } else if (_pvHookType == MODULE_TYPE_PREVALIDATION_HOOK_ERC4337) {
            activePVHook = getActivePreValidationHookERC4337();
        } else {
            revert InvalidHookType();
        }
        require(activePVHook == address(0), PreValidationHookAlreadyInstalled(activePVHook));
        _setPreValidationHook(_pvHookType, _pvHook);
        IModule(_pvHook).onInstall(_data);
    }

    /// @dev Uninstalls a pre-validation hook module
    /// @param _pvHook The address of the pre-validation hook to be uninstalled.
    /// @param _hookType The type of the pre-validation hook (ERC-4337/ERC-1271).
    /// @param _data De-init data to configure the hook when uninstalling.
    function _uninstallPreValidationHook(address _pvHook, uint256 _hookType, bytes calldata _data) internal virtual {
        _setPreValidationHook(_hookType, address(0));
        _pvHook.excessivelySafeCall(gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, _data));
    }

    /// @notice Attempts to uninstall pre-validation hooks module safely
    /// @dev Calls the pre-validation hook's onUninstall function and catches any errors to prevent transaction failure
    /// If the pre-validation hook's onUninstall function fails, it emits a PreValidationHookUninstallFailed event
    /// Always sets the hook to address(0) regardless of success or failure
    function _tryUninstallPreValidationHooks() internal virtual {
        address hook = address(_getAccountStorage().preValidationHookERC1271);
        if (hook != address(0)) {
            try IPreValidationHookERC1271(hook).onUninstall("") {}
            catch (bytes memory reason) {
                emit PreValidationHookUninstallFailed(hook, reason);
            }
        }
        _setPreValidationHook(MODULE_TYPE_PREVALIDATION_HOOK_ERC1271, address(0));
        hook = address(_getAccountStorage().preValidationHookERC4337);
        if (hook != address(0)) {
            try IPreValidationHookERC4337(hook).onUninstall("") {}
            catch (bytes memory reason) {
                emit PreValidationHookUninstallFailed(hook, reason);
            }
            _setPreValidationHook(MODULE_TYPE_PREVALIDATION_HOOK_ERC4337, address(0));
        }
    }

    /// @dev Sets the current pre-validation hook in the storage to the specified address, based on the hook type.
    /// @param _hookType The type of the pre-validation hook (ERC-4337/ERC-1271).
    /// @param _pvHook The new hook address.
    function _setPreValidationHook(uint256 _hookType, address _pvHook) internal virtual {
        if (_hookType == MODULE_TYPE_PREVALIDATION_HOOK_ERC1271) {
            _getAccountStorage().preValidationHookERC1271 = IPreValidationHookERC1271(_pvHook);
        } else if (_hookType == MODULE_TYPE_PREVALIDATION_HOOK_ERC4337) {
            _getAccountStorage().preValidationHookERC4337 = IPreValidationHookERC4337(_pvHook);
        } else {
            revert InvalidHookType();
        }
    }

    /// @dev Calls the pre-validation hook for ERC-1271.
    /// @param _hash The hash of the user operation.
    /// @param _sig The signature to validate.
    /// @return postHash The updated hash after the pre-validation hook.
    /// @return postSig The updated signature after the pre-validation hook.
    function _withPreValidationHook(bytes32 _hash, bytes calldata _sig)
        internal
        view
        virtual
        returns (bytes32 postHash, bytes memory postSig)
    {
        // Get the pre-validation hook for ERC-1271
        address pvHook = getActivePreValidationHookERC1271();
        // If no pre-validation hook is installed, return the original hash and signature
        if (pvHook == address(0)) return (_hash, _sig);
        // Otherwise, call the pre-validation hook and return the updated hash and signature
        else return IPreValidationHookERC1271(pvHook).preValidationHookERC1271(msg.sender, _hash, _sig);
    }

    /// @dev Calls the pre-validation hook for ERC-4337.
    /// @param _hash The hash of the user operation.
    /// @param _userOp The user operation data.
    /// @param _missingAccountFunds The amount of missing account funds.
    /// @return postHash The updated hash after the pre-validation hook.
    /// @return postSig The updated signature after the pre-validation hook.
    function _withPreValidationHook(bytes32 _hash, PackedUserOperation memory _userOp, uint256 _missingAccountFunds)
        internal
        virtual
        returns (bytes32 postHash, bytes memory postSig)
    {
        // Get the pre-validation hook for ERC-4337
        address pvHook = getActivePreValidationHookERC4337();
        // If no pre-validation hook is installed, return the original hash and signature
        if (pvHook == address(0)) return (_hash, _userOp.signature);
        // Otherwise, call the pre-validation hook and return the updated hash and signature
        else return IPreValidationHookERC4337(pvHook).preValidationHookERC4337(_userOp, _missingAccountFunds, _hash);
    }

    /*//////////////////////////////////////////////////////////////
                         FALLBACK MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @dev Fallback function to manage incoming calls using designated handlers based on the call type.
    fallback(bytes calldata _callData) external payable withHook returns (bytes memory) {
        return _fallback(_callData);
    }

    /// @dev Receive function to handle plain ETH transfers
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// @notice Installs a fallback handler
    /// @dev Registers a handler for a specific function selector
    /// @param _handler Address of the fallback handler
    /// @param _params Initialization parameters including selector and call type
    function _installFallbackHandler(address _handler, bytes calldata _params) internal virtual {
        if (_handler == address(0)) revert ModuleAddressCannotBeZero();
        // Extract selector and call type from params
        bytes4 selector = bytes4(_params[0:4]);
        CallType calltype = CallType.wrap(bytes1(_params[4]));
        // Extract allowed callers array
        uint256 allowedCallersOffset = 5;
        uint256 allowedCallersLength = uint256(bytes32(_params[allowedCallersOffset:allowedCallersOffset + 32]));
        address[] memory allowedCallers = new address[](allowedCallersLength);
        for (uint256 i; i < allowedCallersLength; ++i) {
            uint256 callerOffset = allowedCallersOffset + 32 + (i * 32);
            allowedCallers[i] = address(bytes20(_params[callerOffset:callerOffset + 20]));
        }
        // Extract initialization data
        uint256 initDataOffset = allowedCallersOffset + 32 + (allowedCallersLength * 32);
        bytes memory initData = _params[initDataOffset:];
        // Validate call type
        if (calltype == CALLTYPE_DELEGATECALL) revert FallbackInvalidCallType();
        // Check if fallback is already installed
        if (_isFallbackHandlerInstalled(selector)) {
            revert FallbackSelectorAlreadyUsed(selector);
        }
        // Store fallback handler
        _getAccountStorage().fallbacks[selector] = FallbackHandler(_handler, calltype, allowedCallers);
        // Initialize fallback handler
        IFallback(_handler).onInstall(initData);
    }

    /// @notice Uninstalls a fallback handler
    /// @dev Removes a handler for a specific function selector
    /// @param _handler Address of the fallback handler
    /// @param _data De-initialization data including the selector
    function _uninstallFallbackHandler(address _handler, bytes calldata _data) internal virtual {
        bytes4 selector = bytes4(_data[0:4]);
        bytes memory deInitData = _data[4:];
        if (!_isFallbackHandlerInstalled(selector)) {
            revert FunctionSelectorNotUsed(selector);
        }
        FallbackHandler memory fb = _getAccountStorage().fallbacks[selector];
        if (fb.handler != _handler) {
            revert FunctionSelectorNotUsedByHandler(selector, _handler);
        }
        // Reset fallback handler
        address[] memory emptyArray = new address[](0);
        _getAccountStorage().fallbacks[selector] = FallbackHandler(address(0), CallType.wrap(0x00), emptyArray);
        // De-initialize fallback handler
        _handler.excessivelySafeCall(gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, deInitData));
    }

    /// @notice Internal implementation of fallback handling
    /// @dev Processes fallback calls based on registered handlers
    /// @param _callData The calldata of the transaction
    function _fallback(bytes calldata _callData) internal returns (bytes memory result) {
        bool success;
        FallbackHandler storage $fallbackHandler = _getAccountStorage().fallbacks[msg.sig];
        address handler = $fallbackHandler.handler;
        CallType calltype = $fallbackHandler.calltype;
        address[] memory allowedCallers = $fallbackHandler.allowedCallers;
        if (handler != address(0)) {
            /// Check if caller is allowed
            if (allowedCallers.length > 0) {
                bool callerAllowed = false;
                for (uint256 i; i < allowedCallers.length; ++i) {
                    if (allowedCallers[i] == msg.sender) {
                        callerAllowed = true;
                        break;
                    }
                }
                if (!callerAllowed) {
                    revert InvalidFallbackCaller(msg.sender);
                }
            }
            /// Apply hook if available
            address hook = _getHook();
            bytes memory hookData;
            if (hook != address(0)) {
                hookData = IHook(hook).preCheck(msg.sender, msg.value, msg.data);
            }
            /// Execute the fallback handler
            if (calltype == CALLTYPE_STATIC) {
                (success, result) = handler.staticcall(_callData);
            } else if (calltype == CALLTYPE_SINGLE) {
                (success, result) = handler.call{value: msg.value}(_callData);
            } else {
                revert IExecutionHelper.UnsupportedCallType(calltype);
            }
            /// Use revert message from fallback handler if the call was not successful
            if (!success) {
                assembly {
                    revert(add(result, 0x20), mload(result))
                }
            }
            /// Apply post-hook if available
            if (hook != address(0)) {
                IHook(hook).postCheck(hookData);
            }
            emit FallbackCalled(msg.sig, msg.sender, success);
            assembly {
                return(add(result, 0x20), mload(result))
            }
        }
        /// If there's no handler, check if it's an ERC token reception call
        bytes4 selector = msg.sig;
        /// Handle standard token reception interfaces
        if (
            // 0x150b7a02: `onERC721Received(address,address,uint256,bytes)`.
            // 0xf23a6e61: `onERC1155Received(address,address,uint256,uint256,bytes)`.
            // 0xbc197c81: `onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)`.
            selector == 0x150b7a02 || selector == 0xf23a6e61 || selector == 0xbc197c81
        ) {
            assembly {
                mstore(0x20, selector)
                return(0x3c, 0x20)
            }
        }
        /// If we get here, there's no handler and it's not a token reception call
        revert NoFallbackHandler(selector);
    }

    /// @notice Checks if a fallback handler is installed for a selector
    /// @param selector Function selector
    /// @return True if a fallback handler is installed
    function _isFallbackHandlerInstalled(bytes4 selector) internal view virtual returns (bool) {
        return _getAccountStorage().fallbacks[selector].handler != address(0);
    }

    /// @notice Checks if a specific fallback handler is installed for a selector
    /// @param _selector Function selector
    /// @param _handler Expected handler address
    /// @return True if the expected handler is installed
    function _isFallbackHandlerInstalled(bytes4 _selector, address _handler) internal view virtual returns (bool) {
        return _getAccountStorage().fallbacks[_selector].handler == _handler;
    }

    /// @notice Gets fallback handler for a selector
    /// @param _selector Function selector
    /// @return callType Type of call
    /// @return handler Address of the handler
    /// @return allowedCallers Array of addresses allowed to call this fallback
    function getFallbackHandler(bytes4 _selector)
        external
        view
        returns (CallType callType, address handler, address[] memory allowedCallers)
    {
        FallbackHandler memory fallbackHandler = _getAccountStorage().fallbacks[_selector];
        return (fallbackHandler.calltype, fallbackHandler.handler, fallbackHandler.allowedCallers);
    }
}
