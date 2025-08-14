// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {MODULE_TYPE_VALIDATOR, MODULE_TYPE_HOOK, VALIDATION_FAILED} from "ERC7579/interfaces/IERC7579Module.sol";
import "ERC4337/core/Helpers.sol";
import "ERC7579/libs/ModeLib.sol";
import "ERC7579/libs/ExecutionLib.sol";
import {ICredibleAccountModule} from "../../interfaces/ICredibleAccountModule.sol";
import {IResourceLockValidator} from "../../interfaces/IResourceLockValidator.sol";
import {IHookMultiPlexer} from "../../interfaces/IHookMultiPlexer.sol";
import {IInvoiceManager} from "../../interfaces/IInvoiceManager.sol";
import "../../common/Structs.sol";

contract CredibleAccountModule is ICredibleAccountModule, AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ModeLib for ModeCode;
    using ExecutionLib for bytes;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error CredibleAccountModule_ModuleNotInstalled(address wallet);
    error CredibleAccountModule_InvalidResourceLockValidator();
    error CredibleAccountModule_InvalidOwner();
    error CredibleAccountModule_InvalidInvoiceManager();
    error CredibleAccountModule_ResourceLockValidatorNotSet();
    error CredibleAccountModule_MaxSessionKeysReached(address wallet);
    error CredibleAccountModule_InvalidWallet(address wallet, address caller);
    error CredibleAccountModule_InvalidSessionKey();
    error CredibleAccountModule_InvalidSolver();
    error CredibleAccountModule_SessionKeyAlreadyExists(address sessionKey);
    error CredibleAccountModule_InvalidValidAfter();
    error CredibleAccountModule_InvalidValidUntil(uint48 validUntil);
    error CredibleAccountModule_InvalidChainId(uint256 chainId);
    error CredibleAccountModule_SessionKeyDoesNotExist(address session);
    error CredibleAccountModule_SessionKeyNotAuthorized();
    error CredibleAccountModule_InvoiceNotCreated();
    error CredibleAccountModule_LockedTokensNotClaimed(address sessionKey);
    error CredibleAccountModule_InvalidHookMultiPlexer();
    error CredibleAccountModule_InvalidOnInstallData(address wallet);
    error CredibleAccountModule_InvalidOnUnInstallData(address wallet);
    error CredibleAccountModule_InvalidModuleType();
    error CredibleAccountModule_InsufficientUnlockedBalance(address token);
    error CredibleAccountModule_UnauthorizedDisabler(address caller);
    error CredibleAccountModule_SenderMismatch(address sender, address caller);
    error CredibleAccountModule_HookNotInitialized(address sender);
    error CredibleAccountModule_HookShouldBeInstalledFirst();
    error CredibleAccountModule_ValidatorMustBeUninstalledFirst();
    error CredibleAccountModule_MaxLockedTokensReached(address sessionKey);
    error CredibleAccountModule_InvalidCaller();
    error CredibleAccountModule_InvalidSessionKeyParams();
    error CredibleAccountModule_InvalidAmount();
    error CredibleAccountModule_TokenNotFoundForSession(address sessionKey, address token);
    error CredibleAccountModule_TokenAlreadyClaimed(address sessionKey, address token);

    /*//////////////////////////////////////////////////////////////
                               MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(address wallet => Initialization) public moduleInitialized;
    mapping(address wallet => address[] keys) public walletSessionKeys;
    mapping(address sessionKey => address wallet) public sessionKeyToWallet;
    mapping(address wallet => mapping(address sessionKey => SessionData)) public sessionData;
    mapping(address sessionKey => LockedToken[]) public lockedTokens;

    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    IHookMultiPlexer public immutable hookMultiPlexer;
    address public resourceLockValidator;
    address public invoiceManager;
    uint256 public constant MAX_SESSION_KEYS = 10;
    uint256 public constant MAX_LOCKED_TOKENS = 5;
    uint256 public constant DISABLE_SESSION_KEY_TIME_BUFFER = 30 seconds;
    uint256 constant EXEC_OFFSET = 100;
    bytes32 public constant SESSION_KEY_DISABLER = keccak256("SESSION_KEY_DISABLER");

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _hookMultiPlexer) {
        if (_hookMultiPlexer == address(0)) {
            revert CredibleAccountModule_InvalidHookMultiPlexer();
        }
        hookMultiPlexer = IHookMultiPlexer(_hookMultiPlexer);
        if (_owner == address(0)) revert CredibleAccountModule_InvalidOwner();
        // Grant the deployer the default admin role
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        // Grant SESSION_KEY_DISABLER role to deployer
        _grantRole(SESSION_KEY_DISABLER, _owner);
    }

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function configure(address _resourceLockValidator, address _invoiceManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_resourceLockValidator == address(0)) {
            revert CredibleAccountModule_InvalidResourceLockValidator();
        }
        if (_invoiceManager == address(0)) {
            revert CredibleAccountModule_InvalidInvoiceManager();
        }
        resourceLockValidator = _resourceLockValidator;
        invoiceManager = _invoiceManager;
    }

    function setInvoiceManager(address _invoiceManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_invoiceManager == address(0)) {
            revert CredibleAccountModule_InvalidInvoiceManager();
        }
        address current = invoiceManager;
        invoiceManager = _invoiceManager;
        emit CredibleAccountModule_InvoiceManagerUpdated(current, _invoiceManager);
    }

    /*//////////////////////////////////////////////////////////////
                       ACCESS CONTROL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc ICredibleAccountModule
    function grantSessionKeyDisablerRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(SESSION_KEY_DISABLER, account);
    }

    // @inheritdoc ICredibleAccountModule
    function revokeSessionKeyDisablerRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(SESSION_KEY_DISABLER, account);
    }

    // @inheritdoc ICredibleAccountModule
    function hasSessionKeyDisablerRole(address account) external view returns (bool) {
        return hasRole(SESSION_KEY_DISABLER, account);
    }

    // @inheritdoc ICredibleAccountModule
    function getSessionKeyDisablers() external view returns (address[] memory addresses) {
        uint256 count = getRoleMemberCount(SESSION_KEY_DISABLER);
        addresses = new address[](count);
        for (uint256 i; i < count; ++i) {
            addresses[i] = getRoleMember(SESSION_KEY_DISABLER, i);
        }
    }

    /*//////////////////////////////////////////////////////////////
                      VALIDATOR PUBLIC/EXTERNAL
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc ICredibleAccountModule
    function enableSessionKey(bytes calldata _resourceLock) external {
        if (resourceLockValidator == address(0)) {
            revert CredibleAccountModule_ResourceLockValidatorNotSet();
        }
        ResourceLock memory rl = abi.decode(_resourceLock, (ResourceLock));
        if (rl.smartWallet != msg.sender) {
            revert CredibleAccountModule_InvalidWallet(rl.smartWallet, msg.sender);
        }
        if (rl.sessionKey == address(0)) {
            revert CredibleAccountModule_InvalidSessionKey();
        }
        if (sessionKeyToWallet[rl.sessionKey] != address(0)) {
            revert CredibleAccountModule_SessionKeyAlreadyExists(rl.sessionKey);
        }
        if (rl.solver == address(0)) {
            revert CredibleAccountModule_InvalidSolver();
        }
        if (rl.validAfter == 0) {
            revert CredibleAccountModule_InvalidValidAfter();
        }
        if (rl.validUntil <= rl.validAfter || rl.validUntil < block.timestamp) {
            revert CredibleAccountModule_InvalidValidUntil(rl.validUntil);
        }
        if (rl.chainId != 0 && rl.chainId != block.chainid) {
            revert CredibleAccountModule_InvalidChainId(rl.chainId);
        }
        if (!IResourceLockValidator(resourceLockValidator).isSessionKeyAuthorized(msg.sender, rl.sessionKey)) {
            revert CredibleAccountModule_SessionKeyNotAuthorized();
        }
        if (walletSessionKeys[msg.sender].length >= MAX_SESSION_KEYS) {
            revert CredibleAccountModule_MaxSessionKeysReached(msg.sender);
        }
        sessionData[msg.sender][rl.sessionKey] =
            SessionData({sessionKey: rl.sessionKey, validAfter: rl.validAfter, validUntil: rl.validUntil, live: true});
        if (rl.tokenData.length > MAX_LOCKED_TOKENS) {
            revert CredibleAccountModule_MaxLockedTokensReached(rl.sessionKey);
        }
        for (uint256 i; i < rl.tokenData.length; ++i) {
            lockedTokens[rl.sessionKey].push(
                LockedToken({token: rl.tokenData[i].token, lockedAmount: rl.tokenData[i].amount, claimedAmount: 0})
            );
        }
        walletSessionKeys[msg.sender].push(rl.sessionKey);
        sessionKeyToWallet[rl.sessionKey] = msg.sender;
        IResourceLockValidator(resourceLockValidator).removeSessionKeyAuthorization(msg.sender, rl.sessionKey);
        bytes memory invoiceData =
            abi.encode(rl.smartWallet, rl.sessionKey, rl.solver, rl.bidHash, rl.chainId, rl.tokenData);
        address key = IInvoiceManager(invoiceManager).createInvoice(invoiceData);
        if (key != rl.sessionKey) revert CredibleAccountModule_InvoiceNotCreated();
        emit CredibleAccountModule_SessionKeyEnabled(rl.sessionKey, msg.sender);
    }

    // @inheritdoc ICredibleAccountModule
    function disableSessionKey(address _sessionKey) external {
        address sessionOwner = sessionKeyToWallet[_sessionKey];
        if (!hasRole(SESSION_KEY_DISABLER, msg.sender) && msg.sender != sessionOwner) {
            revert CredibleAccountModule_UnauthorizedDisabler(msg.sender);
        }
        address targetWallet = sessionOwner != address(0) ? sessionOwner : msg.sender;
        if (sessionData[targetWallet][_sessionKey].validUntil == 0) {
            revert CredibleAccountModule_SessionKeyDoesNotExist(_sessionKey);
        }
        if (
            sessionData[targetWallet][_sessionKey].validUntil >= block.timestamp + DISABLE_SESSION_KEY_TIME_BUFFER
                && !isSessionClaimed(_sessionKey)
        ) {
            revert CredibleAccountModule_LockedTokensNotClaimed(_sessionKey);
        }
        _removeSessionKey(_sessionKey, targetWallet);
        emit CredibleAccountModule_SessionKeyDisabled(_sessionKey, targetWallet);
    }

    // @inheritdoc ICredibleAccountModule
    function batchDisableSessionKeys(address[] calldata _sessionKeys) external onlyRole(SESSION_KEY_DISABLER) {
        for (uint256 i; i < _sessionKeys.length; i++) {
            address sessionKey = _sessionKeys[i];
            address targetWallet = sessionKeyToWallet[sessionKey];
            if (targetWallet == address(0) || sessionData[targetWallet][sessionKey].validUntil == 0) {
                continue; // Skip non-existent keys instead of reverting
            }
            // Check if session has expired or all tokens are claimed
            bool isExpired =
                block.timestamp > sessionData[targetWallet][sessionKey].validUntil - DISABLE_SESSION_KEY_TIME_BUFFER;
            bool allTokensClaimed = isSessionClaimed(sessionKey);

            if (isExpired || allTokensClaimed) {
                _removeSessionKey(sessionKey, targetWallet);
                emit CredibleAccountModule_SessionKeyDisabled(sessionKey, targetWallet);
            }
        }
    }

    // @inheritdoc ICredibleAccountModule
    function emergencyDisableSessionKey(address _sessionKey) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address targetWallet = sessionKeyToWallet[_sessionKey];
        if (targetWallet == address(0) || sessionData[targetWallet][_sessionKey].validUntil == 0) {
            revert CredibleAccountModule_SessionKeyDoesNotExist(_sessionKey);
        }
        _removeSessionKey(_sessionKey, targetWallet);
        emit CredibleAccountModule_SessionKeyDisabled(_sessionKey, targetWallet);
    }

    // @inheritdoc ICredibleAccountModule
    function _validateCallStructure(PackedUserOperation calldata userOp) internal view returns (bool) {
        bytes calldata callData = userOp.callData;
        if (bytes4(callData[:4]) == IERC7579Account.execute.selector) {
            ModeCode mode = ModeCode.wrap(bytes32(callData[4:36]));
            (CallType calltype,,,) = ModeLib.decode(mode);
            if (calltype == CALLTYPE_SINGLE) {
                return _validateSingleCall(callData);
            } else if (calltype == CALLTYPE_BATCH) {
                return _validateBatchCall(callData);
            }
        }
        return false;
    }

    // @inheritdoc ICredibleAccountModule
    function getSessionKeysByWallet() public view returns (address[] memory) {
        return walletSessionKeys[msg.sender];
    }

    // @inheritdoc ICredibleAccountModule
    function getSessionKeysByWallet(address _wallet) public view returns (address[] memory) {
        return walletSessionKeys[_wallet];
    }

    // @inheritdoc ICredibleAccountModule
    function getSessionKeyData(address _sessionKey) external view returns (SessionData memory) {
        return sessionData[msg.sender][_sessionKey];
    }

    // @inheritdoc ICredibleAccountModule
    function getLockedTokensForSessionKey(address _sessionKey) external view returns (LockedToken[] memory) {
        return lockedTokens[_sessionKey];
    }

    // @inheritdoc ICredibleAccountModule
    function tokenTotalLockedForWallet(address _token) external returns (uint256) {
        return _retrieveLockedBalance(msg.sender, _token);
    }

    // @inheritdoc ICredibleAccountModule
    function cumulativeLockedForWallet() external returns (TokenData[] memory) {
        return _cumulativeLockedForWallet(msg.sender);
    }

    // @inheritdoc ICredibleAccountModule
    function getLiveSessionKeysForWallet(address _wallet) external view returns (address[] memory) {
        return _getSessionKeysByStatus(_wallet, true);
    }

    // @inheritdoc ICredibleAccountModule
    function getExpiredSessionKeysForWallet(address _wallet) external view returns (address[] memory) {
        return _getSessionKeysByStatus(_wallet, false);
    }

    // @inheritdoc ICredibleAccountModule
    function isSessionClaimed(address _sessionKey) public view returns (bool) {
        LockedToken[] memory tokens = lockedTokens[_sessionKey];
        for (uint256 i; i < tokens.length; ++i) {
            if (tokens[i].lockedAmount != tokens[i].claimedAmount) return false;
        }
        return true;
    }

    // @inheritdoc ICredibleAccountModule
    function isSessionExpired(address _sessionKey, address _wallet) public returns (bool) {
        return _isSessionKeyExpired(_sessionKey, _wallet);
    }

    // @inheritdoc ICredibleAccountModule
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        override
        returns (uint256)
    {
        // To account for wallets with hook module installed but not validator
        if (!moduleInitialized[msg.sender].validatorInitialized) {
            revert CredibleAccountModule_ModuleNotInstalled(msg.sender);
        }
        if (msg.sender != userOp.sender) {
            revert CredibleAccountModule_InvalidCaller();
        }
        if (userOp.signature.length != 65) return VALIDATION_FAILED;
        if (!_validateCallStructure(userOp)) {
            return VALIDATION_FAILED;
        }
        bytes memory sig = _digestSignature(userOp.signature);
        address sessionKeySigner = ECDSA.recover(ECDSA.toEthSignedMessageHash(userOpHash), sig);
        SessionData memory sd = sessionData[msg.sender][sessionKeySigner];
        if (sd.sessionKey != sessionKeySigner) return VALIDATION_FAILED;
        return _packValidationData(false, sd.validUntil, sd.validAfter);
    }

    // @inheritdoc ICredibleAccountModule
    function isModuleType(uint256 moduleTypeId) external pure override returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR || moduleTypeId == MODULE_TYPE_HOOK;
    }

    // @inheritdoc ICredibleAccountModule
    function onInstall(bytes calldata data) external override {
        if (data.length < 4) {
            revert CredibleAccountModule_InvalidOnInstallData(msg.sender);
        }
        uint256 moduleType;
        address sender;
        // Check if data starts with a function selector (first 4 bytes)
        // If data length is exactly 32, it's likely just abi.encode(uint256)
        // If data length is longer, it might include function selector
        if (data.length == 32) {
            // Direct abi.encode(uint256)
            moduleType = abi.decode(data, (uint256));
        } else if (data.length == 64) {
            // Direct abi.encode(uint256, address) - used by HookMultiPlexer
            moduleType = abi.decode(data[0:32], (uint256));
            sender = abi.decode(data[32:64], (address));
        } else {
            // Data includes function selector - skip first 4 bytes
            moduleType = abi.decode(data[68:], (uint256));
        }
        if (moduleType == MODULE_TYPE_VALIDATOR) {
            if (!moduleInitialized[msg.sender].hookInitialized) {
                revert CredibleAccountModule_HookShouldBeInstalledFirst();
            }
            moduleInitialized[msg.sender].validatorInitialized = true;
            emit CredibleAccountModule_ModuleInstalled(msg.sender);
        } else if (moduleType == MODULE_TYPE_HOOK) {
            if (msg.sender != address(hookMultiPlexer)) revert CredibleAccountModule_InvalidCaller();
            moduleInitialized[sender].hookInitialized = true;
        } else {
            revert CredibleAccountModule_InvalidModuleType();
        }
    }

    // @inheritdoc ICredibleAccountModule
    function onUninstall(bytes calldata data) external override {
        if (data.length < 64) {
            revert CredibleAccountModule_InvalidOnUnInstallData(msg.sender);
        }
        uint256 moduleType;
        address sender;
        assembly {
            moduleType := calldataload(data.offset)
            sender := calldataload(add(data.offset, 32))
        }
        if (sender != msg.sender && msg.sender != address(hookMultiPlexer)) {
            revert CredibleAccountModule_SenderMismatch(sender, msg.sender);
        }
        if (moduleType == MODULE_TYPE_VALIDATOR) {
            // Check session keys are claimed/expired
            address[] memory sessionKeys = walletSessionKeys[sender];
            for (uint256 i; i < sessionKeys.length; ++i) {
                if (!isSessionClaimed(sessionKeys[i]) && !isSessionExpired(sessionKeys[i], sender)) {
                    revert CredibleAccountModule_LockedTokensNotClaimed(sessionKeys[i]);
                }
            }
            // Clean up validator and session data
            moduleInitialized[sender].validatorInitialized = false;
            for (uint256 i; i < sessionKeys.length; ++i) {
                address sessionKey = sessionKeys[i];
                delete sessionData[sender][sessionKey];
                delete lockedTokens[sessionKey];
                delete sessionKeyToWallet[sessionKey];
            }
            delete walletSessionKeys[sender];
            emit CredibleAccountModule_ModuleUninstalled(sender);
        } else if (moduleType == MODULE_TYPE_HOOK) {
            // Hook can only be uninstalled if validator is already uninstalled
            if (moduleInitialized[sender].validatorInitialized) {
                revert CredibleAccountModule_ValidatorMustBeUninstalledFirst();
            }
            // Clean up hook state
            moduleInitialized[sender].hookInitialized = false;
        } else {
            revert CredibleAccountModule_InvalidModuleType();
        }
    }

    // @inheritdoc ICredibleAccountModule
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata data)
        external
        view
        returns (bytes4)
    {
        if (data.length < 65) return 0xffffffff;
        bytes memory ecdsaSig = data[0:65];
        address sessionKeySigner = ECDSA.recover(ECDSA.toEthSignedMessageHash(hash), ecdsaSig);
        if (sessionKeySigner != sender) return 0xffffffff;
        return 0x1626ba7e;
    }

    // @inheritdoc ICredibleAccountModule
    function isInitialized(address smartAccount) external view returns (bool) {
        return moduleInitialized[smartAccount].validatorInitialized && moduleInitialized[smartAccount].hookInitialized;
    }

    /*//////////////////////////////////////////////////////////////
                          VALIDATOR INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Removes a session key and cleans up all associated data mappings
    /// @dev Deletes session data, locked tokens, and session key to wallet mappings
    /// @param _sessionKey The session key address to remove
    /// @param _wallet The wallet address associated with the session key
    function _removeSessionKey(address _sessionKey, address _wallet) internal {
        delete sessionData[_wallet][_sessionKey];
        delete lockedTokens[_sessionKey];
        delete sessionKeyToWallet[_sessionKey];
        address[] storage keys = walletSessionKeys[_wallet];
        for (uint256 i; i < keys.length; ++i) {
            if (keys[i] == _sessionKey) {
                keys[i] = keys[keys.length - 1];
                keys.pop();
                break;
            }
        }
    }

    /// @notice Retrieves session keys for a wallet filtered by their live or expired status
    /// @dev A key is considered live if sd.live == true AND sd.validUntil >= block.timestamp
    /// @param _wallet The wallet address to get session keys for
    /// @param _getLiveKeys True to return only live/active keys, false to return only expired/inactive keys
    /// @return address[] Array of session key addresses matching the requested status
    function _getSessionKeysByStatus(address _wallet, bool _getLiveKeys) internal view returns (address[] memory) {
        address[] memory allSessionKeys = walletSessionKeys[_wallet];
        address[] memory tempKeys = new address[](allSessionKeys.length);
        uint256 count;
        for (uint256 i; i < allSessionKeys.length; ++i) {
            SessionData memory sd = sessionData[_wallet][allSessionKeys[i]];
            bool isLive = sd.live && sd.validUntil >= block.timestamp;
            // If _getLiveKeys is true, add live keys; if false, add expired keys
            if ((_getLiveKeys && isLive) || (!_getLiveKeys && !isLive)) {
                tempKeys[count] = allSessionKeys[i];
                count++;
            }
        }
        // Create properly sized array
        address[] memory resultKeys = new address[](count);
        for (uint256 i; i < count; ++i) {
            resultKeys[i] = tempKeys[i];
        }
        return resultKeys;
    }
    /// @notice Checks if a session key has expired for a specific wallet
    /// @dev This function also updates the 'live' status of a session key if it has expired
    /// @param _sessionKey The address of the session key to check
    /// @param _wallet The address of the wallet associated with the session key
    /// @return bool Returns true if the session key is expired or not live, false otherwise

    function _isSessionKeyExpired(address _sessionKey, address _wallet) internal returns (bool) {
        SessionData storage sd = sessionData[_wallet][_sessionKey];
        if (!sd.live) {
            return true;
        } else if (sd.validUntil < block.timestamp && sd.live) {
            sd.live = false;
            return true;
        } else {
            return false;
        }
    }

    /// @notice Extracts signature components and proof from the provided data
    /// @dev Decodes the signature
    /// @param _signature The combined signature, proof data
    /// @return The extracted signature (r, s, v)
    function _digestSignature(bytes calldata _signature) internal pure returns (bytes memory) {
        bytes32 r = bytes32(_signature[0:32]);
        bytes32 s = bytes32(_signature[32:64]);
        uint8 v = uint8(_signature[64]);
        bytes memory signature = abi.encodePacked(r, s, v);
        return (signature);
    }

    /*//////////////////////////////////////////////////////////////
                         HOOK PUBLIC/EXTERNAL
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc ICredibleAccountModule
    function preCheck(address msgSender, uint256 msgValue, bytes calldata msgData)
        external
        override
        returns (bytes memory hookData)
    {
        if (msg.sender != address(hookMultiPlexer)) revert CredibleAccountModule_InvalidCaller();
        (address sender,) = abi.decode(msgData, (address, bytes));
        if (!moduleInitialized[sender].hookInitialized) {
            revert CredibleAccountModule_HookNotInitialized(sender);
        }
        return abi.encode(sender, _cumulativeLockedForWallet(sender));
    }

    // @inheritdoc ICredibleAccountModule
    function postCheck(bytes calldata hookData) external {
        if (hookData.length == 0) return;
        if (msg.sender != address(hookMultiPlexer)) revert CredibleAccountModule_InvalidCaller();
        (address sender, TokenData[] memory preCheckBalances) = abi.decode(hookData, (address, TokenData[]));
        if (!moduleInitialized[sender].hookInitialized) {
            revert CredibleAccountModule_HookNotInitialized(sender);
        }
        for (uint256 i; i < preCheckBalances.length; ++i) {
            address token = preCheckBalances[i].token;
            uint256 preCheckLocked = preCheckBalances[i].amount;
            uint256 walletBalance = _walletTokenBalance(sender, token);
            uint256 postCheckLocked = _retrieveLockedBalance(sender, token);
            if (walletBalance < preCheckLocked && walletBalance < postCheckLocked && walletBalance != 0) {
                revert CredibleAccountModule_InsufficientUnlockedBalance(token);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the total locked balance for a specific token across all non-expired session keys
    /// @dev Iterates through all session keys and their locked tokens to calculate the total locked balance
    /// @param _wallet The address of the wallet to check the locked balance for
    /// @param _token The address of the token to check the locked balance for
    /// @return The total locked balance of the specified token across all session keys
    function _retrieveLockedBalance(address _wallet, address _token) internal returns (uint256) {
        address[] memory sessionKeys = getSessionKeysByWallet(_wallet);
        uint256 totalLocked;
        uint256 sessionKeysLength = sessionKeys.length;
        for (uint256 i; i < sessionKeysLength;) {
            // Skip expired session keys
            if (!_isSessionKeyExpired(sessionKeys[i], _wallet)) {
                LockedToken[] memory tokens = lockedTokens[sessionKeys[i]];
                uint256 tokensLength = tokens.length;
                for (uint256 j; j < tokensLength;) {
                    LockedToken memory lockedToken = tokens[j];
                    if (lockedToken.token == _token) {
                        totalLocked += (lockedToken.lockedAmount - lockedToken.claimedAmount);
                    }
                    unchecked {
                        ++j;
                    }
                }
            }
            unchecked {
                ++i;
            }
        }
        return totalLocked;
    }

    /// @notice Gets the cumulative locked state of all tokens across all non-expired session keys
    /// @dev Aggregates locked token balances for all session keys, combining balances for the same token
    /// @return Array of TokenData structures representing the initial locked state
    function _cumulativeLockedForWallet(address _wallet) internal returns (TokenData[] memory) {
        address[] memory sessionKeys = getSessionKeysByWallet(_wallet);
        TokenData[] memory tokenData = new TokenData[](0);
        uint256 unique;
        for (uint256 i; i < sessionKeys.length; ++i) {
            // Skip expired session keys
            if (!_isSessionKeyExpired(sessionKeys[i], _wallet)) {
                LockedToken[] memory locks = lockedTokens[sessionKeys[i]];
                for (uint256 j; j < locks.length; ++j) {
                    address token = locks[j].token;
                    bool found = false;
                    for (uint256 k; k < unique; ++k) {
                        if (tokenData[k].token == token) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        TokenData[] memory newTokenData = new TokenData[](unique + 1);
                        for (uint256 m; m < unique; ++m) {
                            newTokenData[m] = tokenData[m];
                        }
                        uint256 totalLocked = _retrieveLockedBalance(_wallet, token);
                        newTokenData[unique] = TokenData(token, totalLocked);
                        tokenData = newTokenData;
                        unique++;
                    }
                }
            }
        }
        return tokenData;
    }

    /// @notice Gets the token balance of a wallet for a specific ERC20 token
    /// @dev Simple wrapper around IERC20.balanceOf for internal use
    /// @param _wallet The wallet address to check balance for
    /// @param _token The ERC20 token contract address
    /// @return uint256 The token balance of the wallet
    function _walletTokenBalance(address _wallet, address _token) internal view returns (uint256) {
        return IERC20(_token).balanceOf(_wallet);
    }

    /// @notice Validates if a function selector is allowed for token operations
    /// @dev Currently only allows ERC20 transfer function selector
    /// @param _selector The 4-byte function selector to validate
    /// @return bool Returns true if the selector is valid, false otherwise
    // function _isValidSelector(bytes4 _selector) internal pure returns (bool) {
    //     return _selector == IERC20.transfer.selector;
    // }

    /*//////////////////////////////////////////////////////////////
                          INTERFACE SUPPORT
    //////////////////////////////////////////////////////////////*/

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Grants a role to an account and emits custom events for specific roles
    /// @dev Overrides AccessControl's _grantRole to add custom event emission
    /// @dev Emits SessionKeyDisablerRoleGranted event when SESSION_KEY_DISABLER role is granted
    /// @param role The role identifier to grant
    /// @param account The address to grant the role to
    /// @return bool Returns true if the role was successfully granted
    function _grantRole(bytes32 role, address account) internal virtual override returns (bool) {
        bool result = super._grantRole(role, account);
        if (result && role == SESSION_KEY_DISABLER) {
            emit SessionKeyDisablerRoleGranted(account, msg.sender);
        }
        return result;
    }

    /// @notice Revokes a role from an account and emits custom events for specific roles
    /// @dev Overrides AccessControl's _revokeRole to add custom event emission
    /// @dev Emits SessionKeyDisablerRoleRevoked event when SESSION_KEY_DISABLER role is revoked
    /// @param role The role identifier to revoke
    /// @param account The address to revoke the role from
    /// @return bool Returns true if the role was successfully revoked
    function _revokeRole(bytes32 role, address account) internal virtual override returns (bool) {
        bool result = super._revokeRole(role, account);
        if (result && role == SESSION_KEY_DISABLER) {
            emit SessionKeyDisablerRoleRevoked(account, msg.sender);
        }
        return result;
    }

    /*//////////////////////////////////////////////////////////////
                        V2 CLAIMING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims tokens for a specific session key and token address
    /// @dev This function should be called in the execution phase, not validation
    /// @dev Updates the claimed amount for the specified token in the session
    /// @param _sessionKey The session key to claim tokens for
    /// @param _token The token address to claim
    /// @param _amount The amount to claim
    /// @return bool Returns true if claim was successful
    function claim(address _sessionKey, address _token, uint256 _amount) external nonReentrant returns (bool) {
        address wallet = sessionKeyToWallet[_sessionKey];
        if (wallet != msg.sender) revert CredibleAccountModule_InvalidWallet(wallet, msg.sender);
        if (_amount == 0) revert CredibleAccountModule_InvalidAmount();
        if (invoiceManager == address(0)) revert CredibleAccountModule_InvalidInvoiceManager();

        SessionData memory sd = sessionData[wallet][_sessionKey];
        if (sd.sessionKey != _sessionKey) revert CredibleAccountModule_InvalidSessionKey();
        if (!sd.live || block.timestamp < sd.validAfter || block.timestamp > sd.validUntil) {
            revert CredibleAccountModule_SessionKeyDoesNotExist(_sessionKey);
        }

        LockedToken[] storage tokens = lockedTokens[_sessionKey];
        uint256 tokenLength = tokens.length;

        for (uint256 i; i < tokenLength;) {
            if (tokens[i].token == _token) {
                if (tokens[i].claimedAmount != 0) revert CredibleAccountModule_TokenAlreadyClaimed(_sessionKey, _token);
                if (_amount != tokens[i].lockedAmount) revert CredibleAccountModule_InvalidAmount();
                if (_walletTokenBalance(wallet, _token) < _amount) {
                    revert CredibleAccountModule_InsufficientUnlockedBalance(_token);
                }
                tokens[i].claimedAmount = tokens[i].lockedAmount; // Exact assignment
                emit CredibleAccountModule_TokensClaimed(_sessionKey, _token, _amount);
                IERC20(_token).safeTransferFrom(wallet, invoiceManager, _amount);
                IInvoiceManager(invoiceManager).creditTokensToInvoice(_sessionKey, _token, _amount);
                return true;
            }
            unchecked {
                ++i;
            }
        }

        revert CredibleAccountModule_TokenNotFoundForSession(_sessionKey, _token); // Reusing for "token not found"
    }

    /**
     * @notice Validates that a function selector is allowed for execution
     * @dev Only allows the claim() or IERC20.approve function selector to be executed through this module
     * @param _selector The function selector to validate
     * @return bytes4 returns a valid selector or bytes4(0)
     */
    function _validateSelector(bytes4 _selector) internal pure returns (bytes4) {
        return (_selector == this.claim.selector || _selector == IERC20.approve.selector) ? _selector : bytes4(0);
    }

    /**
     * @notice Validates a single execution call against session key constraints
     * @dev Ensures the call targets this contract, uses valid selector
     * @param _callData The complete execution calldata including target and data
     * @return bool True if the single call is valid, false otherwise
     */
    function _validateSingleCall(bytes calldata _callData) internal view returns (bool) {
        (address target,, bytes calldata execData) = ExecutionLib.decodeSingle(_callData[EXEC_OFFSET:]);
        bytes4 selector = _validateSelector(bytes4(execData[0:4]));
        if (selector == bytes4(0)) return false;
        if (selector == IERC20.approve.selector) return true;
        if (target != address(this)) return false; // If not approve call must call this contract
        return true;
    }

    /**
     * @notice Validates a batch of execution calls against session key constraints
     * @dev Iterates through all executions in the batch, ensuring each call targets
     *      this contract, uses valid selectors
     * @param _callData The complete batch execution calldata
     * @return bool True if all batch calls are valid, false if any call fails validation
     */
    function _validateBatchCall(bytes calldata _callData) internal view returns (bool) {
        Execution[] calldata execs = ExecutionLib.decodeBatch(_callData[EXEC_OFFSET:]);
        for (uint256 i; i < execs.length; ++i) {
            bytes4 selector = _validateSelector(bytes4(execs[i].callData[0:4]));
            if (selector == bytes4(0)) return false;
            if (selector == IERC20.approve.selector) continue;
            if (execs[i].target != address(this)) return false; // If not approve call must call this contract
        }
        return true;
    }
}
