// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {UUPSUpgradeable} from "solady/src/utils/UUPSUpgradeable.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IModule} from "../interfaces/base/IModule.sol";
import {IValidator} from "../interfaces/base/IValidator.sol";
import {IModularEtherspotWallet} from "../interfaces/wallet/IModularEtherspotWallet.sol";
import {BaseAccount} from "../core/BaseAccount.sol";
import {ModuleManager} from "../core/ModuleManager.sol";
import {RegistryAdapter} from "../core/RegistryAdapter.sol";
import {ExecutionHelper} from "../core/ExecutionHelper.sol";
import {ExecutionLib} from "../libraries/ExecutionLib.sol";
import {Initializable} from "../libraries/Initializable.sol";
import {ModeLib} from "../libraries/ModeLib.sol";
import {SentinelListLib} from "../libraries/SentinelList.sol";
import {
    CALLTYPE_BATCH,
    CALLTYPE_DELEGATECALL,
    CALLTYPE_SINGLE,
    EIP7702_PREFIX,
    ERC1271_MAGIC_VALUE,
    EXECTYPE_DEFAULT,
    EXECTYPE_TRY,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_FALLBACK,
    MODULE_TYPE_HOOK,
    MODULE_TYPE_PREVALIDATION_HOOK_ERC1271,
    MODULE_TYPE_PREVALIDATION_HOOK_ERC4337,
    MODULE_TYPE_VALIDATOR,
    SIG_VALIDATION_FAILED,
    SIG_VALIDATION_SUCCESS
} from "../types/Constants.sol";
import {CallType, ExecType, ModeCode} from "../types/Types.sol";

/// @title ModularEtherspotWallet
/// @author @cryptonoyaiba | Etherspot
/// @notice Implementation of a modular smart contract wallet supporting ERC7579, EIP4337, and EIP7702
/// @dev This contract serves as the implementation for modular smart wallets with a
/// flexible architecture that allows installing and using different types of modules
contract ModularEtherspotWallet is
    IModularEtherspotWallet,
    BaseAccount,
    ExecutionHelper,
    ModuleManager,
    RegistryAdapter,
    UUPSUpgradeable
{
    using ExecutionLib for bytes;
    using ModeLib for ModeCode;
    using ECDSA for bytes32;
    using SentinelListLib for SentinelListLib.SentinelList;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when EIP7702 validation is successful
    /// @param signer The address that signed the message
    /// @param userOpHash The hash of the user operation that was validated
    event EIP7702ValidationSuccess(address indexed signer, bytes32 userOpHash);

    /// @notice Emitted when EIP7702 validation fails
    /// @param signer The address that signed the message
    /// @param userOpHash The hash of the user operation that failed validation
    event EIP7702ValidationFailed(address indexed signer, bytes32 userOpHash);

    /// @notice Emitted when a user operation is successfully executed
    /// @param userOp The user operation that was executed
    /// @param returnData The data returned from execution
    event UserOpExecuted(PackedUserOperation userOp, bytes returnData);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Error thrown when calldata is invalid or insufficient
    error InvalidCallData();

    /// @notice Error thrown when initialization data is invalid or insufficient
    error InvalidInitializationData();

    /// @notice Error thrown when bootstrap address is invalid (zero address)
    error InvalidBootstrapAddress();

    /// @notice Error thrown when a user operation execution fails
    error UserOpExecutionFailed();

    error InvalidImplementationAddress();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(IEntryPoint _entrypoint) {
        ENTRYPOINT = _entrypoint;
        _initModuleManager();
    }

    /*//////////////////////////////////////////////////////////////
                           PUBLIC/EXTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute transactions from the EntryPoint or the account itself
    /// @dev Enforces that caller is entry point or the account, and triggers hook execution
    /// @param _mode The execution mode (call type, execution type, etc.)
    /// @param _executionCalldata The calldata for execution
    function execute(ModeCode _mode, bytes calldata _executionCalldata)
        external
        payable
        onlyEntryPointOrSelf
        withHook
    {
        (CallType callType, ExecType execType,,) = _mode.decode();
        _processExecution(callType, execType, _executionCalldata, false);
    }

    /// @notice Execute transactions from a registered executor module
    /// @dev Enforces that caller is an executor module, and triggers hook execution
    /// @param _mode The execution mode (call type, execution type, etc.)
    /// @param _executionCalldata The calldata for execution
    /// @return returnData The data returned from the execution
    function executeFromExecutor(ModeCode _mode, bytes calldata _executionCalldata)
        external
        payable
        onlyExecutorModule
        withHook
        returns (bytes[] memory returnData)
    {
        (CallType callType, ExecType execType,,) = _mode.decode();
        return _processExecution(callType, execType, _executionCalldata, true);
    }

    /// @notice Executes a user operation from the EntryPoint
    /// @dev Required by ERC4337, extracts calldata from the userOp and executes it via delegatecall
    /// @param _userOp The user operation to execute
    /// @param _userOpHash The hash of the user operation (unused parameter but required by interface)
    function executeUserOp(PackedUserOperation calldata _userOp, bytes32 _userOpHash) external payable onlyEntryPoint {
        if (_userOp.callData.length < 4) revert InvalidCallData();
        bytes calldata callData = _userOp.callData[4:];
        (bool success, bytes memory returnData) = address(this).delegatecall(callData);
        if (success) {
            emit UserOpExecuted(_userOp, returnData);
        } else {
            // Extract revert reason if available
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            }
            revert UserOpExecutionFailed();
        }
    }

    /// @notice Validates a user operation before execution
    /// @dev Required by ERC4337, handles payment of prefund and signature validation
    /// @param _userOp The user operation to validate
    /// @param _userOpHash The hash of the user operation
    /// @param _missingAccountFunds The amount of funds needed for prefund
    /// @return validSignature The validation result (SIG_VALIDATION_SUCCESS or SIG_VALIDATION_FAILED)
    function validateUserOp(PackedUserOperation memory _userOp, bytes32 _userOpHash, uint256 _missingAccountFunds)
        external
        payable
        virtual
        onlyEntryPoint
        payPrefund(_missingAccountFunds)
        returns (uint256 validSignature)
    {
        address validator;
        uint256 nonce = _userOp.nonce;
        assembly {
            validator := shr(96, nonce)
        }
        // Check if validator is enabled. If not, terminate the validation phase.
        if (!_isValidatorInstalled(validator)) {
            if (!isStorageInitialized()) {
                // EIP-7702 validation logic
                address signer = ECDSA.recover(_userOpHash.toEthSignedMessageHash(), _userOp.signature);
                if (signer != address(this)) {
                    emit EIP7702ValidationFailed(signer, _userOpHash);
                    return SIG_VALIDATION_FAILED;
                }
                emit EIP7702ValidationSuccess(signer, _userOpHash);
                return SIG_VALIDATION_SUCCESS;
            }
            return SIG_VALIDATION_FAILED;
        } else {
            // Normal validation flow with pre-validation hooks
            (_userOpHash, _userOp.signature) = _withPreValidationHook(_userOpHash, _userOp, _missingAccountFunds);
            validSignature = IValidator(validator).validateUserOp(_userOp, _userOpHash);
        }
    }

    /// @notice Validates a signature according to ERC1271
    /// @dev Determines which validator module to use and delegates validation
    /// @param _hash The hash of the message that was signed
    /// @param _data The signature data (first 20 bytes are validator address, rest is signature)
    /// @return ERC1271_MAGIC_VALUE if valid, ERC1271_INVALID if invalid
    function isValidSignature(bytes32 _hash, bytes calldata _data) external view virtual override returns (bytes4) {
        address validator = address(bytes20(_data[0:20]));
        if (!_isValidatorInstalled(validator)) {
            if (!isStorageInitialized()) {
                address signer = ECDSA.recover(_hash.toEthSignedMessageHash(), _data);
                if (signer == address(this)) {
                    return ERC1271_MAGIC_VALUE;
                }
            }
            revert InvalidModule(validator);
        }
        bytes memory sig;
        (_hash, sig) = _withPreValidationHook(_hash, _data[20:]);
        return IValidator(validator).isValidSignatureWithSender(msg.sender, _hash, sig);
    }

    /// @notice Installs a module to the account
    /// @dev Only callable by EntryPoint or the account itself, validates against registry
    /// @param _moduleTypeId The type ID of the module
    /// @param _module The address of the module to install
    /// @param _initData Initialization data for the module
    function installModule(uint256 _moduleTypeId, address _module, bytes calldata _initData)
        external
        payable
        onlyEntryPointOrSelf
        withHook
        withRegistry(_module, _moduleTypeId)
    {
        if (!IModule(_module).isModuleType(_moduleTypeId)) revert MismatchModuleTypeId(_moduleTypeId);
        _installModuleByType(_moduleTypeId, _module, _initData);
        emit ModuleInstalled(_moduleTypeId, _module);
    }

    /// @notice Uninstalls a module from the account
    /// @dev Only callable by EntryPoint or the account itself
    /// @param _moduleTypeId The type ID of the module
    /// @param _module The address of the module to uninstall
    /// @param _deInitData De-initialization data for the module
    function uninstallModule(uint256 _moduleTypeId, address _module, bytes calldata _deInitData)
        external
        payable
        onlyEntryPointOrSelf
        withHook
    {
        if (_moduleTypeId == MODULE_TYPE_VALIDATOR) {
            _uninstallValidator(_module, _deInitData);
        } else if (_moduleTypeId == MODULE_TYPE_EXECUTOR) {
            _uninstallExecutor(_module, _deInitData);
        } else if (_moduleTypeId == MODULE_TYPE_FALLBACK) {
            _uninstallFallbackHandler(_module, _deInitData);
        } else if (_moduleTypeId == MODULE_TYPE_HOOK) {
            _uninstallHook(_module, _deInitData);
        } else if (
            _moduleTypeId == MODULE_TYPE_PREVALIDATION_HOOK_ERC1271
                || _moduleTypeId == MODULE_TYPE_PREVALIDATION_HOOK_ERC4337
        ) {
            _uninstallPreValidationHook(_module, _moduleTypeId, _deInitData);
        } else {
            revert UnsupportedModuleType(_moduleTypeId);
        }
        emit ModuleUninstalled(_moduleTypeId, _module);
    }

    /// @notice Checks if a module is installed in the account
    /// @param _moduleTypeId The type ID of the module to check
    /// @param _module The address of the module to check
    /// @param _additionalContext Additional context for specialized module checks
    /// @return True if the module is installed, false otherwise
    function isModuleInstalled(uint256 _moduleTypeId, address _module, bytes calldata _additionalContext)
        external
        view
        override
        returns (bool)
    {
        if (_moduleTypeId == MODULE_TYPE_VALIDATOR) {
            return _isValidatorInstalled(_module);
        } else if (_moduleTypeId == MODULE_TYPE_EXECUTOR) {
            return _isExecutorInstalled(_module);
        } else if (_moduleTypeId == MODULE_TYPE_FALLBACK) {
            return _isFallbackHandlerInstalled(abi.decode(_additionalContext, (bytes4)), _module);
        } else if (_moduleTypeId == MODULE_TYPE_HOOK) {
            return _isHookInstalled(_module);
        } else if (_moduleTypeId == MODULE_TYPE_PREVALIDATION_HOOK_ERC1271) {
            return getActivePreValidationHookERC1271() == _module;
        } else if (_moduleTypeId == MODULE_TYPE_PREVALIDATION_HOOK_ERC4337) {
            return getActivePreValidationHookERC4337() == _module;
        } else {
            return false;
        }
    }

    /// @notice Returns the account identifier
    /// @dev Used for tracking account standard and version
    /// @return A string identifier for the account
    function accountId() external view virtual override returns (string memory) {
        return "etherspot.modular.v2.0.0";
    }

    /// @notice Checks if the account supports a specific execution mode
    /// @param _mode The execution mode to check support for
    /// @return True if the execution mode is supported, false otherwise
    function supportsExecutionMode(ModeCode _mode) external view virtual override returns (bool) {
        (CallType callType, ExecType execType,,) = _mode.decode();
        bool isCallTypeSupported =
            callType == CALLTYPE_BATCH || callType == CALLTYPE_SINGLE || callType == CALLTYPE_DELEGATECALL;
        bool isExecTypeSupported = execType == EXECTYPE_DEFAULT || execType == EXECTYPE_TRY;
        return isCallTypeSupported && isExecTypeSupported;
    }

    /// @notice Checks if the account supports a specific module type
    /// @param _moduleTypeId The module type ID to check support for
    /// @return True if the module type is supported, false otherwise
    function supportsModule(uint256 _moduleTypeId) external view virtual override returns (bool) {
        return _moduleTypeId == MODULE_TYPE_VALIDATOR || _moduleTypeId == MODULE_TYPE_EXECUTOR
            || _moduleTypeId == MODULE_TYPE_FALLBACK || _moduleTypeId == MODULE_TYPE_HOOK
            || _moduleTypeId == MODULE_TYPE_PREVALIDATION_HOOK_ERC1271
            || _moduleTypeId == MODULE_TYPE_PREVALIDATION_HOOK_ERC4337;
    }

    /// @notice Initializes the account with necessary modules and configuration
    /// @dev Can only be called once, handles both standard initialization and EIP7702 initialization
    /// @param _data The initialization data (bootstrap address and call)
    function initializeAccount(bytes calldata _data) public payable virtual {
        // protect this function to only be callable when used with the proxy factory or when
        // account calls itself
        if (msg.sender != address(this)) {
            Initializable._checkInitializable();
        }
        // checks if already initialized and reverts before setting the state to initialized
        _initModuleManager();
        if (_data.length < 40) revert InvalidInitializationData(); // Minimal length for address + empty bytes
        (address bootstrap, bytes memory bootstrapCall) = abi.decode(_data, (address, bytes));
        if (bootstrap == address(0)) revert InvalidBootstrapAddress();
        _initAccount(bootstrap, bootstrapCall);
    }

    /// @notice Checks if the account has been initialized
    /// @dev Returns true if the account's core initialization has been completed
    /// @return True if the account has been initialized, false otherwise
    function isAccountInitialised() external view virtual returns (bool) {
        return isStorageInitialized();
    }

    function getImplementation() external view returns (address impl) {
        assembly {
            impl := sload(_ERC1967_IMPLEMENTATION_SLOT)
        }
        if (impl == address(0)) {
            assembly {
                impl := sload(address())
            }
        }
    }

    function upgradeToAndCall(address _newImpl, bytes calldata _data) public payable virtual override withHook {
        require(_newImpl != address(0), InvalidImplementationAddress());
        bool res;
        assembly {
            res := gt(extcodesize(_newImpl), 0)
        }
        require(res, InvalidImplementationAddress());
        // update the address() storage slot as well.
        assembly {
            sstore(address(), _newImpl)
        }
        UUPSUpgradeable.upgradeToAndCall(_newImpl, _data);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL/PRIVATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Performs the actual account initialization by delegatecalling to the bootstrap contract
    /// @dev Executes the bootstrap call and handles any errors that may occur
    /// @param _bootstrap The address of the bootstrap contract
    /// @param _bootstrapCall The calldata to execute on the bootstrap contract
    function _initAccount(address _bootstrap, bytes memory _bootstrapCall) private {
        (bool success, bytes memory returnData) = _bootstrap.delegatecall(_bootstrapCall);
        if (!success) {
            // Extract revert reason if available
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            }
            revert AccountInitializationFailed();
        }
    }

    /// @notice Handles cleanup during redelegation
    /// @dev Called when the account is being upgraded or reinitialized, uninstalls all modules
    function _onRedelegation() internal override {
        _tryUninstallValidators();
        _tryUninstallExecutors();
        _tryUninstallHook();
        _tryUninstallPreValidationHooks();
        _initModuleManager();
    }

    /// @notice Installs a module based on its type
    /// @dev Internal function that handles all module type-specific installation logic
    /// @param _id The module type ID
    /// @param _module The address of the module to install
    /// @param _initData The initialization data for the module
    function _installModuleByType(uint256 _id, address _module, bytes calldata _initData) internal {
        if (_id == MODULE_TYPE_VALIDATOR) {
            _installValidator(_module, _initData);
        } else if (_id == MODULE_TYPE_EXECUTOR) {
            _installExecutor(_module, _initData);
        } else if (_id == MODULE_TYPE_FALLBACK) {
            _installFallbackHandler(_module, _initData);
        } else if (_id == MODULE_TYPE_HOOK) {
            _installHook(_module, _initData);
        } else if (_id == MODULE_TYPE_PREVALIDATION_HOOK_ERC1271 || _id == MODULE_TYPE_PREVALIDATION_HOOK_ERC4337) {
            _installPreValidationHook(_id, _module, _initData);
        } else {
            revert UnsupportedModuleType(_id);
        }
    }

    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "ModularEtherspotWallet";
        version = "2.0.0";
    }

    /// @dev Ensures that only authorized callers can upgrade the smart contract implementation.
    /// This is part of the UUPS (Universal Upgradeable Proxy Standard) pattern.
    /// @param _newImpl The address of the new implementation to upgrade to.
    function _authorizeUpgrade(address _newImpl) internal virtual override(UUPSUpgradeable) onlyEntryPointOrSelf {}
}
