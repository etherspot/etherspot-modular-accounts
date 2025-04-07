// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC7579Account} from "../../interfaces/base/IERC7579Account.sol";
import {IERC20SessionKeyValidator} from "../../interfaces/modules/IERC20SessionKeyValidator.sol";
import {ArrayLib} from "../../libraries/ArrayLib.sol";
import {ModeLib} from "../../libraries/ModeLib.sol";
import {ExecutionLib} from "../../libraries/ExecutionLib.sol";
import {
    CALLTYPE_BATCH, CALLTYPE_SINGLE, MODULE_TYPE_VALIDATOR, SIG_VALIDATION_FAILED
} from "../../types/Constants.sol";
import {Execution} from "../../types/Structs.sol";
import {CallType, ModeCode, packValidationData, ValidAfter, ValidUntil} from "../../types/Types.sol";

/// @title ERC20SessionKeyValidator
/// @author @cryptonoyaiba | Etherspot
/// @notice A validator module that enables session keys with specific ERC20 token permissions
/// @dev Allows smart accounts to create session keys with limited token spending capabilities
contract ERC20SessionKeyValidator is IERC20SessionKeyValidator {
    using ModeLib for ModeCode;
    using ExecutionLib for bytes;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Name of the validator module
    string constant NAME = "ERC20SessionKeyValidator";

    /// @notice Version of the validator module
    string constant VERSION = "1.0.0";

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to install the module on an account where it's already installed
    error ERC20SKV_ModuleAlreadyInstalled();

    /// @notice Thrown when trying to use the module on an account where it's not installed
    error ERC20SKV_ModuleNotInstalled();

    /// @notice Thrown when trying to use an invalid session key (e.g., zero address)
    error ERC20SKV_InvalidSessionKey();

    /// @notice Thrown when trying to use an invalid token address (e.g., zero address)
    error ERC20SKV_InvalidToken();

    /// @notice Thrown when trying to use an invalid function selector
    error ERC20SKV_InvalidFunctionSelector();

    /// @notice Thrown when trying to set an invalid spending limit (e.g., zero)
    error ERC20SKV_InvalidSpendingLimit();

    /// @notice Thrown when trying to set an invalid validAfter timestamp
    error ERC20SKV_InvalidValidAfter(uint48 validAfter);

    /// @notice Thrown when trying to set an invalid validUntil timestamp
    error ERC20SKV_InvalidValidUntil(uint48 validUntil);

    /// @notice Thrown when trying to enable a session key that already exists
    error ERC20SKV_SessionKeyAlreadyExists(address sessionKey);

    /// @notice Thrown when trying to use a session key that doesn't exist
    error ERC20SKV_SessionKeyDoesNotExist(address session);

    /// @notice Thrown when trying to use a session key that is paused
    error ERC20SKV_SessionPaused(address sessionKey);

    /// @notice Thrown when calling a function that is not implemented
    error NotImplemented();

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Tracks which smart accounts have initialized this module
    mapping(address => bool) public initialized;

    /// @notice Maps wallet addresses to their associated session keys
    mapping(address wallet => address[] assocSessionKeys) public walletSessionKeys;

    /// @notice Maps session keys to their configuration data for each wallet
    mapping(address sessionKey => mapping(address wallet => SessionData)) public sessionData;

    /*//////////////////////////////////////////////////////////////
                            PUBLIC/EXTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Enables a new session key with specific token permissions
    /// @dev Creates a new session key with token, function selector, spending limit, and validity period
    /// @param _sessionData Encoded session key configuration data
    /// @custom:events Emits ERC20SKV_SessionKeyEnabled when a session key is successfully enabled
    /// @custom:errors Various errors if session key parameters are invalid
    function enableSessionKey(bytes calldata _sessionData) public {
        address sessionKey = address(bytes20(_sessionData[0:20]));
        if (sessionKey == address(0)) revert ERC20SKV_InvalidSessionKey();
        if (
            sessionData[sessionKey][msg.sender].validUntil != 0
                && ArrayLib._contains(getAssociatedSessionKeys(), sessionKey)
        ) revert ERC20SKV_SessionKeyAlreadyExists(sessionKey);
        address token = address(bytes20(_sessionData[20:40]));
        if (token == address(0)) revert ERC20SKV_InvalidToken();
        bytes4 funcSelector = bytes4(_sessionData[40:44]);
        if (funcSelector == bytes4(0)) {
            revert ERC20SKV_InvalidFunctionSelector();
        }
        uint256 spendingLimit = uint256(bytes32(_sessionData[44:76]));
        if (spendingLimit == 0) revert ERC20SKV_InvalidSpendingLimit();
        uint48 validAfter = uint48(bytes6(_sessionData[76:82]));
        if (validAfter == 0) revert ERC20SKV_InvalidValidAfter(validAfter);
        uint48 validUntil = uint48(bytes6(_sessionData[82:88]));
        if (validUntil == 0) revert ERC20SKV_InvalidValidUntil(validUntil);
        sessionData[sessionKey][msg.sender] =
            SessionData(token, funcSelector, spendingLimit, validAfter, validUntil, true);
        walletSessionKeys[msg.sender].push(sessionKey);
        emit ERC20SKV_SessionKeyEnabled(sessionKey, msg.sender);
    }

    /// @notice Disables an existing session key
    /// @dev Removes the session key and its associated data
    /// @param _session Address of the session key to disable
    /// @custom:events Emits ERC20SKV_SessionKeyDisabled when a session key is successfully disabled
    /// @custom:errors ERC20SKV_SessionKeyDoesNotExist if the session key doesn't exist
    function disableSessionKey(address _session) public {
        if (sessionData[_session][msg.sender].validUntil == 0) {
            revert ERC20SKV_SessionKeyDoesNotExist(_session);
        }
        delete sessionData[_session][msg.sender];
        walletSessionKeys[msg.sender] = ArrayLib._removeElement(getAssociatedSessionKeys(), _session);
        emit ERC20SKV_SessionKeyDisabled(_session, msg.sender);
    }

    /// @notice Replaces an existing session key with a new one
    /// @dev Disables the old session key and enables a new one in a single transaction
    /// @param _oldSessionKey Address of the session key to replace
    /// @param _newSessionData Encoded configuration data for the new session key
    function rotateSessionKey(address _oldSessionKey, bytes calldata _newSessionData) external {
        disableSessionKey(_oldSessionKey);
        enableSessionKey(_newSessionData);
    }

    /// @notice Toggles the active state of a session key
    /// @dev Pauses or unpauses a session key without removing it
    /// @param _sessionKey Address of the session key to toggle
    /// @custom:events Emits ERC20SKV_SessionKeyPaused or ERC20SKV_SessionKeyUnpaused
    /// @custom:errors ERC20SKV_SessionKeyDoesNotExist if the session key doesn't exist
    function toggleSessionKeyPause(address _sessionKey) external {
        SessionData storage sd = sessionData[_sessionKey][msg.sender];
        if (sd.validUntil == 0) {
            revert ERC20SKV_SessionKeyDoesNotExist(_sessionKey);
        }
        if (sd.live) {
            sd.live = false;
            emit ERC20SKV_SessionKeyPaused(_sessionKey, msg.sender);
        } else {
            sd.live = true;
            emit ERC20SKV_SessionKeyUnpaused(_sessionKey, msg.sender);
        }
    }

    /// @notice Checks if a session key is currently active
    /// @param _sessionKey Address of the session key to check
    /// @return bool True if the session key is active, false otherwise
    function isSessionKeyLive(address _sessionKey) public view returns (bool) {
        return sessionData[_sessionKey][msg.sender].live;
    }

    /// @notice Validates if a user operation can be executed with the given session key
    /// @dev Checks if the operation matches the token permissions and spending limits
    /// @param _sessionKey Address of the session key to validate
    /// @param userOp The packed user operation containing execution data to validate
    /// @return bool True if the session key can execute the operation, false otherwise
    function validateSessionKeyParams(address _sessionKey, PackedUserOperation calldata userOp)
        public
        view
        returns (bool)
    {
        SessionData memory sd = sessionData[_sessionKey][msg.sender];
        if (isSessionKeyLive(_sessionKey) == false) {
            return false;
        }
        address target;
        bytes calldata callData = userOp.callData;
        bytes4 sel = bytes4(callData[:4]);
        if (sel == IERC7579Account.execute.selector) {
            ModeCode mode = ModeCode.wrap(bytes32(callData[4:36]));
            (CallType calltype,,,) = ModeLib.decode(mode);
            if (calltype == CALLTYPE_SINGLE) {
                bytes calldata execData;
                // 0x00 ~ 0x04 : selector
                // 0x04 ~ 0x24 : mode code
                // 0x24 ~ 0x44 : execution target
                // 0x44 ~0x64 : execution value
                // 0x64 ~ : execution calldata
                (target,, execData) = ExecutionLib.decodeSingle(callData[100:]);
                (bytes4 selector, address from, address to, uint256 amount) = _digest(execData);
                if (target != sd.token) return false;
                if (selector != sd.funcSelector) return false;
                if (amount > sd.spendingLimit) return false;
                return true;
            }
            if (calltype == CALLTYPE_BATCH) {
                Execution[] calldata execs = ExecutionLib.decodeBatch(callData[100:]);
                for (uint256 i; i < execs.length; ++i) {
                    target = execs[i].target;
                    (bytes4 selector, address from, address to, uint256 amount) = _digest(execs[i].callData);
                    if (target != sd.token) return false;
                    if (selector != sd.funcSelector) return false;
                    if (amount > sd.spendingLimit) return false;
                }
                return true;
            } else {
                return false;
            }
        } else {
            return false;
        }
    }

    /// @notice Retrieves all session keys associated with the calling wallet
    /// @return Array of session key addresses enabled for the calling wallet
    function getAssociatedSessionKeys() public view returns (address[] memory) {
        return walletSessionKeys[msg.sender];
    }

    /// @notice Gets the session data for a specific session key
    /// @param _sessionKey Address of the session key to query
    /// @return SessionData struct containing token permissions and validity period
    function getSessionKeyData(address _sessionKey) public view returns (SessionData memory) {
        return sessionData[_sessionKey][msg.sender];
    }

    /// @notice Validates a user operation signed by a session key
    /// @dev Verifies the signature and token permissions for the operation
    /// @param userOp The packed user operation to validate
    /// @param userOpHash The hash of the user operation for signature verification
    /// @return uint256 Validation result with time constraints encoded if successful, or SIG_VALIDATION_FAILED
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        override
        returns (uint256)
    {
        address sessionKeySigner = ECDSA.recover(ECDSA.toEthSignedMessageHash(userOpHash), userOp.signature);
        if (!validateSessionKeyParams(sessionKeySigner, userOp)) {
            return SIG_VALIDATION_FAILED;
        }
        SessionData memory sd = sessionData[sessionKeySigner][msg.sender];
        return packValidationData(false, ValidUntil.wrap(sd.validUntil), ValidAfter.wrap(sd.validAfter));
    }

    /// @notice Checks if this module supports the specified module type
    /// @dev Implements the ERC7579 module type identification interface
    /// @param moduleTypeId The module type identifier to check
    /// @return bool True if this module is a validator module
    function isModuleType(uint256 moduleTypeId) external pure override returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }

    /// @notice Initializes the module when installed in a smart account
    /// @dev Sets the initialized flag for the calling smart account
    /// @param data Installation data (unused in this implementation)
    /// @custom:events Emits ERC20SKV_ModuleInstalled when successfully installed
    /// @custom:errors ERC20SKV_ModuleAlreadyInstalled if already initialized for the smart account
    function onInstall(bytes calldata data) external override {
        if (initialized[msg.sender] == true) {
            revert ERC20SKV_ModuleAlreadyInstalled();
        }
        initialized[msg.sender] = true;
        emit ERC20SKV_ModuleInstalled(msg.sender);
    }

    /// @notice Cleans up module data when uninstalled from a smart account
    /// @dev Removes all session keys and their data for the calling smart account
    /// @param data Uninstallation data (unused in this implementation)
    /// @custom:events Emits ERC20SKV_ModuleUninstalled when successfully uninstalled
    /// @custom:errors ERC20SKV_ModuleNotInstalled if not initialized for the smart account
    function onUninstall(bytes calldata data) external override {
        if (initialized[msg.sender] == false) {
            revert ERC20SKV_ModuleNotInstalled();
        }
        address[] memory sessionKeys = getAssociatedSessionKeys();
        uint256 sessionKeysLength = sessionKeys.length;
        for (uint256 i; i < sessionKeysLength; ++i) {
            delete sessionData[sessionKeys[i]][msg.sender];
        }
        delete walletSessionKeys[msg.sender];
        initialized[msg.sender] = false;
        emit ERC20SKV_ModuleUninstalled(msg.sender);
    }

    /// @notice ERC-1271 signature validation with sender context
    /// @dev Currently not implemented and will revert
    /// @param sender The address of the sender requesting signature validation
    /// @param hash The hash of the data that was signed
    /// @param data The signature data to validate
    /// @return bytes4 Magic value if signature is valid, error value otherwise
    /// @custom:errors NotImplemented as this function is not yet implemented
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata data)
        external
        view
        returns (bytes4)
    {
        revert NotImplemented();
    }

    /// @notice Checks if the module is initialized for a specific smart account
    /// @dev Returns true if the module is initialized for the account
    /// @param smartAccount Address of the smart account to check
    /// @return bool True if the module is initialized, false otherwise
    function isInitialized(address smartAccount) external view returns (bool) {
        return initialized[smartAccount];
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL/PRIVATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Extracts and decodes relevant information from ERC20 function call data
    /// @dev Supports transfer, approve, and transferFrom functions of ERC20 tokens
    /// @param _data The calldata of the ERC20 function call
    /// @return selector The function selector (4 bytes)
    /// @return from The address tokens are transferred from (for transferFrom)
    /// @return to The address tokens are transferred to or approved for
    /// @return amount The amount of tokens involved in the transaction
    function _digest(bytes calldata _data)
        internal
        pure
        returns (bytes4 selector, address from, address to, uint256 amount)
    {
        selector = bytes4(_data[0:4]);
        if (selector == IERC20.approve.selector || selector == IERC20.transfer.selector) {
            to = address(bytes20(_data[16:36]));
            amount = uint256(bytes32(_data[36:68]));
            return (selector, address(0), to, amount);
        } else if (selector == IERC20.transferFrom.selector) {
            from = address(bytes20(_data[16:36]));
            to = address(bytes20(_data[48:68]));
            amount = uint256(bytes32(_data[68:100]));
            return (selector, from, to, amount);
        } else {
            return (bytes4(0), address(0), address(0), 0);
        }
    }
}
