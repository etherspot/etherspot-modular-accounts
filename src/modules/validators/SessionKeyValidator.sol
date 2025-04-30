// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC7579Account} from "../../interfaces/base/IERC7579Account.sol";
import {ExecutionLib} from "../../libraries/ExecutionLib.sol";
import {ModeLib} from "../../libraries/ModeLib.sol";
import {ISessionKeyValidator} from "../../interfaces/modules/ISessionKeyValidator.sol";
import {
    CALLTYPE_BATCH, CALLTYPE_SINGLE, MODULE_TYPE_VALIDATOR, SIG_VALIDATION_FAILED
} from "../../types/Constants.sol";
import {ComparisonRule} from "../../types/Enums.sol";
import {Execution, ExecutionValidation, ParamCondition, Permission, SessionData} from "../../types/Structs.sol";
import {CallType, ModeCode, packValidationData, ValidAfter, ValidUntil} from "../../types/Types.sol";

/// @title SessionKeyValidator
/// @author @cryptonoyaiba | Etherspot
/// @notice A validator module that supports session keys with fine-grained permissions
/// @dev Implements session key validation with permission controls and parameter conditions
contract SessionKeyValidator is ISessionKeyValidator {
    using ModeLib for ModeCode;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to install an already installed module
    error SKV_ModuleAlreadyInstalled();

    /// @notice Thrown when trying to use an uninstalled module
    error SKV_ModuleNotInstalled();

    /// @notice Thrown when session key data is invalid
    error SKV_InvalidSessionKeyData(address sessionKey, uint48 validAfter, uint48 validUntil);

    /// @notice Thrown when permission data is invalid
    error SKV_InvalidPermissionData(
        address sessionKey,
        address target,
        bytes4 selector,
        uint256 payableLimit,
        uint256 uses,
        ParamCondition[] conditions
    );

    /// @notice Thrown when a permission index is invalid
    error SKV_InvalidPermissionIndex();

    /// @notice Thrown when trying to add a session key that already exists
    error SKV_SessionKeyAlreadyExists(address sessionKey);

    /// @notice Thrown when trying to use a session key that doesn't exist
    error SKV_SessionKeyDoesNotExist(address sessionKey);

    /// @notice Thrown when a permission doesn't exist
    error SKV_PermissionDoesNotExist();

    /// @notice Thrown for unimplemented functions
    error NotImplemented();

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps smart account addresses to their initialization status
    mapping(address => bool) public initialized;

    /// @notice Maps wallet addresses to their session keys
    mapping(address wallet => address[] sessionKeys) public walletSessionKeys;

    /// @notice Maps session keys and wallet addresses to their session data
    mapping(address sessionKey => mapping(address wallet => SessionData)) public sessionData;

    /// @notice Maps session keys and wallet addresses to their permissions
    mapping(address sessionKey => mapping(address wallet => Permission[])) public permissions;

    /*//////////////////////////////////////////////////////////////
                            PUBLIC/EXTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Enables a session key with specified permissions
    /// @dev Creates a new session key with the given validity period and permissions
    /// @param _sessionData The session key data including key address and validity period
    /// @param _permissions Array of permissions to grant to the session key
    /// @custom:events Emits SKV_SessionKeyEnabled when a session key is successfully enabled
    /// @custom:errors Various errors if session key or permission data is invalid
    function enableSessionKey(SessionData memory _sessionData, Permission[] memory _permissions) public {
        if (_sessionData.sessionKey == address(0) || _sessionData.validAfter == 0 || _sessionData.validUntil == 0) {
            revert SKV_InvalidSessionKeyData(_sessionData.sessionKey, _sessionData.validAfter, _sessionData.validUntil);
        }
        if (sessionData[_sessionData.sessionKey][msg.sender].validUntil != 0) {
            revert SKV_SessionKeyAlreadyExists(_sessionData.sessionKey);
        }
        SessionData storage sd = sessionData[_sessionData.sessionKey][msg.sender];
        sd.sessionKey = _sessionData.sessionKey;
        sd.validAfter = _sessionData.validAfter;
        sd.validUntil = _sessionData.validUntil;
        sd.live = true;
        for (uint256 i; i < _permissions.length; ++i) {
            if (_permissions[i].target == address(0) || _permissions[i].uses == 0) {
                revert SKV_InvalidPermissionData(
                    _sessionData.sessionKey,
                    _permissions[i].target,
                    _permissions[i].selector,
                    _permissions[i].payableLimit,
                    _permissions[i].uses,
                    _permissions[i].paramConditions
                );
            }
            Permission storage newPermission = permissions[_sessionData.sessionKey][msg.sender].push();
            newPermission.target = _permissions[i].target;
            newPermission.selector = _permissions[i].selector;
            newPermission.payableLimit = _permissions[i].payableLimit;
            newPermission.uses = _permissions[i].uses;

            for (uint256 j; j < _permissions[i].paramConditions.length; ++j) {
                ParamCondition memory condition = _permissions[i].paramConditions[j];
                newPermission.paramConditions.push(
                    ParamCondition({offset: condition.offset, rule: condition.rule, value: condition.value})
                );
            }
        }
        walletSessionKeys[msg.sender].push(_sessionData.sessionKey);
        emit SKV_SessionKeyEnabled(_sessionData.sessionKey, msg.sender);
    }

    /// @notice Disables a session key
    /// @dev Removes a session key and all its permissions
    /// @param _sessionKey The address of the session key to disable
    /// @custom:events Emits SKV_SessionKeyDisabled when a session key is successfully disabled
    /// @custom:errors SKV_SessionKeyDoesNotExist if the session key doesn't exist
    function disableSessionKey(address _sessionKey) public {
        if (sessionData[_sessionKey][msg.sender].validUntil == 0) {
            revert SKV_SessionKeyDoesNotExist(_sessionKey);
        }
        delete sessionData[_sessionKey][msg.sender];
        delete permissions[_sessionKey][msg.sender];
        address[] storage keys = walletSessionKeys[msg.sender];
        for (uint256 i; i < keys.length; ++i) {
            if (keys[i] == _sessionKey) {
                keys[i] = keys[keys.length - 1];
                keys.pop();
                break;
            }
        }
        emit SKV_SessionKeyDisabled(_sessionKey, msg.sender);
    }

    /// @notice Rotates a session key by disabling the old one and enabling a new one
    /// @dev Combines disableSessionKey and enableSessionKey operations
    /// @param _oldSessionKey The address of the old session key to disable
    /// @param _newSessionData The session data for the new session key
    /// @param _newPermissions The permissions for the new session key
    /// @custom:events Emits events from disableSessionKey and enableSessionKey
    /// @custom:errors Various errors from disableSessionKey and enableSessionKey
    function rotateSessionKey(
        address _oldSessionKey,
        SessionData calldata _newSessionData,
        Permission[] calldata _newPermissions
    ) external {
        disableSessionKey(_oldSessionKey);
        enableSessionKey(_newSessionData, _newPermissions);
    }

    /// @notice Toggles the pause state of a session key
    /// @dev Flips the live status of a session key
    /// @param _sessionKey The address of the session key to toggle
    /// @custom:events Emits SKV_SessionKeyPauseToggled when a session key's pause state is toggled
    /// @custom:errors SKV_SessionKeyDoesNotExist if the session key doesn't exist
    function toggleSessionKeyPause(address _sessionKey) external {
        SessionData storage data = sessionData[_sessionKey][msg.sender];
        if (data.validUntil == 0) {
            revert SKV_SessionKeyDoesNotExist(_sessionKey);
        }
        bool newLiveStatus = !data.live;
        data.live = newLiveStatus;
        emit SKV_SessionKeyPauseToggled(_sessionKey, msg.sender, newLiveStatus);
    }

    /// @notice Gets all session keys for the calling wallet
    /// @return address[] Array of session key addresses
    function getSessionKeysByWallet() public view returns (address[] memory) {
        return walletSessionKeys[msg.sender];
    }

    /// @notice Gets session data for a specific session key
    /// @param _sessionKey The address of the session key
    /// @return SessionData The session data
    /// @custom:errors SKV_SessionKeyDoesNotExist if the session key doesn't exist
    function getSessionKeyData(address _sessionKey) external view returns (SessionData memory) {
        if (sessionData[_sessionKey][msg.sender].validUntil == 0) {
            revert SKV_SessionKeyDoesNotExist(_sessionKey);
        }
        return sessionData[_sessionKey][msg.sender];
    }

    /// @notice Gets permissions for a specific session key
    /// @param _sessionKey The address of the session key
    /// @return Permission[] Array of permissions
    /// @custom:errors SKV_SessionKeyDoesNotExist if the session key doesn't exist
    function getSessionKeyPermissions(address _sessionKey) external view returns (Permission[] memory) {
        if (sessionData[_sessionKey][msg.sender].validUntil == 0) {
            revert SKV_SessionKeyDoesNotExist(_sessionKey);
        }
        return permissions[_sessionKey][msg.sender];
    }

    /// @notice Checks if a session key is live (not paused)
    /// @param _sessionKey The address of the session key
    /// @return bool True if the session key is live, false otherwise
    function isSessionLive(address _sessionKey) public view returns (bool) {
        return sessionData[_sessionKey][msg.sender].live;
    }

    /// @notice Gets the number of uses left for a specific permission
    /// @param _sessionKey The address of the session key
    /// @param _permissionIndex The index of the permission
    /// @return uint256 The number of uses left
    function getUsesLeft(address _sessionKey, uint256 _permissionIndex) public view returns (uint256) {
        return permissions[_sessionKey][msg.sender][_permissionIndex].uses;
    }

    /// @notice Updates the number of uses for a specific permission
    /// @param _sessionKey The address of the session key
    /// @param _permissionIndex The index of the permission
    /// @param _newUses The new number of uses
    /// @custom:events Emits SKV_PermissionUsesUpdated when uses are updated
    /// @custom:errors SKV_SessionKeyDoesNotExist if the session key doesn't exist
    function updateUses(address _sessionKey, uint256 _permissionIndex, uint256 _newUses) external {
        if (sessionData[_sessionKey][msg.sender].validUntil == 0) {
            revert SKV_SessionKeyDoesNotExist(_sessionKey);
        }
        Permission storage permission = permissions[_sessionKey][msg.sender][_permissionIndex];
        uint256 previous = permission.uses;
        permission.uses = _newUses;
        emit SKV_PermissionUsesUpdated(_sessionKey, _permissionIndex, previous, _newUses);
    }

    /// @notice Updates the validUntil timestamp for a session key
    /// @param _sessionKey The address of the session key
    /// @param _newValidUntil The new validUntil timestamp
    /// @custom:events Emits SKV_SessionKeyValidUntilUpdated when validUntil is updated
    /// @custom:errors SKV_SessionKeyDoesNotExist if the session key doesn't exist
    function updateValidUntil(address _sessionKey, uint48 _newValidUntil) external {
        SessionData storage data = sessionData[_sessionKey][msg.sender];
        if (data.validUntil == 0) {
            revert SKV_SessionKeyDoesNotExist(_sessionKey);
        }
        data.validUntil = _newValidUntil;
        emit SKV_SessionKeyValidUntilUpdated(_sessionKey, msg.sender, _newValidUntil);
    }

    /// @notice Adds a new permission to a session key
    /// @param _sessionKey The address of the session key
    /// @param _permission The permission to add
    /// @custom:events Emits SKV_PermissionAdded when a permission is added
    /// @custom:errors Various errors if the session key doesn't exist or permission data is invalid
    function addPermission(address _sessionKey, Permission memory _permission) external {
        if (sessionData[_sessionKey][msg.sender].validUntil == 0) {
            revert SKV_SessionKeyDoesNotExist(_sessionKey);
        }
        if (
            _permission.target == address(0) || (_permission.selector == bytes4(0) && _permission.payableLimit == 0)
                || _permission.uses == 0
        ) {
            revert SKV_InvalidPermissionData(
                _sessionKey,
                _permission.target,
                _permission.selector,
                _permission.payableLimit,
                _permission.uses,
                _permission.paramConditions
            );
        }

        Permission storage newPermission = permissions[_sessionKey][msg.sender].push();
        newPermission.target = _permission.target;
        newPermission.selector = _permission.selector;
        newPermission.payableLimit = _permission.payableLimit;
        newPermission.uses = _permission.uses;
        for (uint256 i; i < _permission.paramConditions.length; ++i) {
            newPermission.paramConditions.push(_permission.paramConditions[i]);
        }
        emit SKV_PermissionAdded(
            _sessionKey,
            msg.sender,
            _permission.target,
            _permission.selector,
            _permission.payableLimit,
            _permission.uses,
            _permission.paramConditions
        );
    }

    /// @notice Removes a permission from a session key
    /// @param _sessionKey The address of the session key
    /// @param _permissionIndex The index of the permission to remove
    /// @custom:events Emits SKV_PermissionRemoved when a permission is removed
    /// @custom:errors Various errors if the session key doesn't exist or permission index is invalid
    function removePermission(address _sessionKey, uint256 _permissionIndex) external {
        if (sessionData[_sessionKey][msg.sender].validUntil == 0) {
            revert SKV_SessionKeyDoesNotExist(_sessionKey);
        }
        Permission[] storage perms = permissions[_sessionKey][msg.sender];
        if (_permissionIndex >= perms.length) {
            revert SKV_InvalidPermissionIndex();
        }
        perms[_permissionIndex] = perms[perms.length - 1];
        perms.pop();
        emit SKV_PermissionRemoved(_sessionKey, msg.sender, _permissionIndex);
    }

    /// @notice Modifies an existing permission
    /// @param _sessionKey The address of the session key
    /// @param _index The index of the permission to modify
    /// @param _target The new target address (or 0 to keep current)
    /// @param _selector The new function selector (or 0 to keep current)
    /// @param _payableLimit The new payable limit (or 0 to keep current)
    /// @param _uses The new number of uses (or 0 to keep current)
    /// @param _paramConditions The new parameter conditions (empty to keep current)
    /// @custom:events Emits SKV_PermissionModified when a permission is modified
    /// @custom:errors Various errors if the session key doesn't exist or permission index is invalid
    function modifyPermission(
        address _sessionKey,
        uint256 _index,
        address _target,
        bytes4 _selector,
        uint256 _payableLimit,
        uint256 _uses,
        ParamCondition[] calldata _paramConditions
    ) external {
        if (sessionData[_sessionKey][msg.sender].validUntil == 0) {
            revert SKV_SessionKeyDoesNotExist(_sessionKey);
        }
        if (_index >= permissions[_sessionKey][msg.sender].length) {
            revert SKV_InvalidPermissionIndex();
        }
        Permission storage permission = permissions[_sessionKey][msg.sender][_index];
        if (_target != address(0)) permission.target = _target;
        if (_selector != bytes4(0)) permission.selector = _selector;
        if (_payableLimit != 0) permission.payableLimit = _payableLimit;
        if (_uses != 0) permission.uses = _uses;
        if (_paramConditions.length > 0) {
            delete permission.paramConditions;
            for (uint256 i; i < _paramConditions.length; ++i) {
                permission.paramConditions.push(_paramConditions[i]);
            }
        }
        emit SKV_PermissionModified(
            _sessionKey,
            msg.sender,
            _index,
            permission.target,
            permission.selector,
            permission.payableLimit,
            permission.uses,
            _paramConditions
        );
    }

    /// @notice Validates a user operation signed by a session key
    /// @dev Implements the ERC-4337 validation interface for session keys
    /// @param userOp The packed user operation to validate
    /// @param userOpHash The hash of the user operation for signature verification
    /// @return uint256 Validation result with validity period
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        override
        returns (uint256)
    {
        (ExecutionValidation[] memory execVals, bytes32 r, bytes32 s, uint8 v) =
            _extractExecutionValidationAndSignature(userOp.signature);
        address sessionKeySigner = ECDSA.recover(ECDSA.toEthSignedMessageHash(userOpHash), v, r, s);
        (bool isValid, uint48 validAfter, uint48 validUntil) =
            _validateSessionKeyParams(sessionKeySigner, userOp, execVals);
        if (!isValid) return SIG_VALIDATION_FAILED;
        return packValidationData(false, ValidUntil.wrap(validUntil), ValidAfter.wrap(validAfter));
    }

    /// @notice Checks if this module supports the specified module type
    /// @param moduleTypeId The module type identifier to check
    /// @return bool True if this module is a validator module
    function isModuleType(uint256 moduleTypeId) external pure override returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }

    /// @notice Initializes the validator when installed in a smart account
    /// @param data The installation data (unused)
    /// @custom:events Emits SKV_ModuleInstalled when successfully installed
    function onInstall(bytes calldata data) external override {
        initialized[msg.sender] = true;
        emit SKV_ModuleInstalled(msg.sender);
    }

    /// @notice Cleans up validator data when uninstalled from a smart account
    /// @param data The uninstallation data (unused)
    /// @custom:events Emits SKV_ModuleUninstalled when successfully uninstalled
    /// @custom:errors SKV_ModuleNotInstalled if not initialized for the smart account
    function onUninstall(bytes calldata data) external override {
        if (!initialized[msg.sender]) revert SKV_ModuleNotInstalled();
        address[] memory sessionKeys = getSessionKeysByWallet();
        uint256 sessionKeysLength = sessionKeys.length;
        for (uint256 i; i < sessionKeysLength; ++i) {
            delete sessionData[sessionKeys[i]][msg.sender];
        }
        delete walletSessionKeys[msg.sender];
        initialized[msg.sender] = false;
        emit SKV_ModuleUninstalled(msg.sender);
    }

    /// @notice ERC-1271 signature validation (not implemented)
    /// @dev This function is not implemented and will revert
    /// @param sender The address of the sender requesting validation
    /// @param hash The hash of the data that was signed
    /// @param data The signature to validate
    /// @return bytes4 Magic value if signature is valid, error value otherwise
    /// @custom:errors NotImplemented always
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata data)
        external
        view
        returns (bytes4)
    {
        revert NotImplemented();
    }

    /// @notice Checks if the module is initialized for a specific smart account
    /// @param smartAccount Address of the smart account to check
    /// @return bool True if the module is initialized, false otherwise
    function isInitialized(address smartAccount) external view returns (bool) {
        return initialized[smartAccount];
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates session key parameters
    /// @param _sessionKey The address of the session key
    /// @param _userOp The user operation to validate
    /// @param _execVals Array of execution data
    /// @return success Whether the validation was successful
    /// @return validAfter The timestamp after which the operation is valid
    /// @return validUntil The timestamp until which the operation is valid
    function _validateSessionKeyParams(
        address _sessionKey,
        PackedUserOperation calldata _userOp,
        ExecutionValidation[] memory _execVals
    ) internal returns (bool success, uint48 validAfter, uint48 validUntil) {
        SessionData memory sd = sessionData[_sessionKey][msg.sender];
        if (!sd.live || bytes4(_userOp.callData[:4]) != IERC7579Account.execute.selector) return (false, 0, 0);
        (CallType calltype,,,) = ModeLib.decode(ModeCode.wrap(bytes32(_userOp.callData[4:36])));
        if (calltype == CALLTYPE_SINGLE) {
            return _validateSingleExecution(_userOp, sd, _execVals[0]);
        }
        if (calltype == CALLTYPE_BATCH) {
            return _validateBatchExecution(_userOp, sd, _execVals);
        }
        return (false, 0, 0);
    }

    /// @notice Validates a single execution
    /// @param _userOp The UserOperation
    /// @param _sd The session data
    /// @param _execVal The execution data
    /// @return bool Whether the validation was successful
    /// @return uint48 The timestamp after which the operation is valid
    /// @return uint48 The timestamp until which the operation is valid
    function _validateSingleExecution(
        PackedUserOperation calldata _userOp,
        SessionData memory _sd,
        ExecutionValidation memory _execVal
    ) internal returns (bool, uint48, uint48) {
        (address target, uint256 value, bytes calldata callData) = ExecutionLib.decodeSingle(_userOp.callData[100:]);
        if (_validatePermission(_userOp.sender, _sd, _execVal, target, value, callData)) {
            return (true, _execVal.validAfter, _execVal.validUntil);
        }
        return (false, 0, 0);
    }

    /// @notice Validates a batch execution
    /// @param _userOp UserOperation
    /// @param _sd The session data
    /// @param _execVals Array of ExecutionValidations
    /// @return bool Whether the validation was successful
    /// @return uint48 The earliest timestamp after which all operations are valid
    /// @return uint48 The latest timestamp until which the operations are valid
    function _validateBatchExecution(
        PackedUserOperation calldata _userOp,
        SessionData memory _sd,
        ExecutionValidation[] memory _execVals
    ) internal returns (bool, uint48, uint48) {
        uint48 earliestAfter = type(uint48).max;
        uint48 latestUntil;
        Execution[] calldata batchExecs = ExecutionLib.decodeBatch(_userOp.callData[100:]);
        for (uint256 i; i < batchExecs.length; ++i) {
            bool executionValid = false;
            if (
                _validatePermission(
                    _userOp.sender, _sd, _execVals[i], batchExecs[i].target, batchExecs[i].value, batchExecs[i].callData
                )
            ) {
                executionValid = true;
                earliestAfter = _execVals[i].validAfter < earliestAfter ? _execVals[i].validAfter : earliestAfter;
                latestUntil = _execVals[i].validUntil > latestUntil ? _execVals[i].validUntil : latestUntil;
            }
            if (!executionValid) return (false, 0, 0);
        }
        return (true, earliestAfter, latestUntil);
    }

    /// @notice Validates if a given execution is permitted based on the session data and permissions
    /// @dev This function checks if the execution matches any of the permissions in the session data
    /// @param _sender UserOperation.sender
    /// @param _sd The session data containing permissions and validity period
    /// @param _execVal The ExecutionValidation to be validated
    /// @param target The target address of the Execution
    /// @param value The value of the Execution
    /// @param callData The call data of the Execution
    /// @return bool Returns true if the execution is permitted, false otherwise
    function _validatePermission(
        address _sender,
        SessionData memory _sd,
        ExecutionValidation memory _execVal,
        address target,
        uint256 value,
        bytes calldata callData
    ) internal returns (bool) {
        Permission[] memory perms = permissions[_sd.sessionKey][_sender];
        for (uint256 i; i < perms.length; ++i) {
            Permission memory permission = perms[i];
            bool nativeTransfer = value > 0 && bytes4(callData) == bytes4(0);
            if (permission.target != target) continue;
            if (!nativeTransfer && permission.selector != (callData.length >= 4 ? bytes4(callData[:4]) : bytes4(0))) {
                continue;
            }
            if (nativeTransfer) {
                if (value > permission.payableLimit) continue;
            } else {
                bool allConditionsMet = true;
                for (uint256 j; j < permission.paramConditions.length; ++j) {
                    ParamCondition memory condition = permission.paramConditions[j];
                    bytes32 param = bytes32(callData[condition.offset:condition.offset + 32]);
                    if (!_checkCondition(param, condition.value, condition.rule)) {
                        allConditionsMet = false;
                        break;
                    }
                }
                if (!allConditionsMet) continue;
                if (value > 0 && value > permission.payableLimit) continue;
            }
            if (_sd.validAfter <= _execVal.validAfter && _sd.validUntil >= _execVal.validUntil && permission.uses > 0) {
                emit SKV_PermissionUsed(_sd.sessionKey, permission, permission.uses, permission.uses - 1);
                permissions[_sd.sessionKey][_sender][i].uses--;
                return true;
            }
        }
        return false;
    }

    /// @notice Extracts ExecutionValidation and signature from UserOperation signature
    /// @param _userOpSig The packed UserOperation signature
    /// @return execVals Array of ExecutionValidation
    /// @return r The r component of the signature
    /// @return s The s component of the signature
    /// @return v The v component of the signature
    function _extractExecutionValidationAndSignature(bytes calldata _userOpSig)
        internal
        pure
        returns (ExecutionValidation[] memory execVals, bytes32 r, bytes32 s, uint8 v)
    {
        assembly {
            r := calldataload(_userOpSig.offset)
            s := calldataload(add(_userOpSig.offset, 32))
            v := byte(0, calldataload(add(_userOpSig.offset, 64)))
        }
        (execVals) = abi.decode(_userOpSig[65:], (ExecutionValidation[]));
    }

    /// @notice Checks if a parameter meets a specified condition based on a comparison rule
    /// @dev This function is used to validate parameters against set conditions
    /// @param param The parameter value to be checked
    /// @param value The value to compare the parameter against
    /// @param rule The comparison rule to apply (EQUAL, GREATER_THAN, LESS_THAN, etc.)
    /// @return bool Returns true if the condition is met, false otherwise
    function _checkCondition(bytes32 param, bytes32 value, ComparisonRule rule) internal pure returns (bool) {
        if (rule == ComparisonRule.EQUAL && param != value) return false;
        if (rule == ComparisonRule.GREATER_THAN && param <= value) return false;
        if (rule == ComparisonRule.LESS_THAN && param >= value) return false;
        if (rule == ComparisonRule.GREATER_THAN_OR_EQUAL && param < value) {
            return false;
        }
        if (rule == ComparisonRule.LESS_THAN_OR_EQUAL && param > value) {
            return false;
        }
        if (rule == ComparisonRule.NOT_EQUAL && param == value) return false;
        return true;
    }
}
