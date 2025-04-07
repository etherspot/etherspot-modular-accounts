// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {EnumerableSetLib} from "solady/src/utils/EnumerableSetLib.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IValidator} from "../../interfaces/base/IValidator.sol";
import {IERC7579Account} from "../../interfaces/base/IERC7579Account.sol";
import {IModuleManager} from "../../interfaces/core/IModuleManager.sol";
import {HookMultiPlexer} from "../hooks/HookMultiPlexer.sol";
import {CredibleAccountHook} from "../hooks/CredibleAccountHook.sol";
import {ExecutionLib} from "../../libraries/ExecutionLib.sol";
import {ModeLib} from "../../libraries/ModeLib.sol";
import {
    CALLTYPE_SINGLE,
    CALLTYPE_BATCH,
    ERC1271_INVALID,
    ERC1271_MAGIC_VALUE,
    MODULE_TYPE_VALIDATOR,
    SIG_VALIDATION_FAILED
} from "../../types/Constants.sol";
import {HookType} from "../../types/Enums.sol";
import {Execution, SessionData, ResourceLock, TokenData} from "../../types/Structs.sol";
import {CallType, ModeCode, packValidationData, ValidAfter, ValidUntil} from "../../types/Types.sol";

contract CredibleAccountValidator is IValidator, Ownable {
    using ExecutionLib for bytes;
    using EnumerableSetLib for EnumerableSetLib.AddressSet;

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/

    HookMultiPlexer public immutable hookMultiPlexer;
    CredibleAccountHook public caHook;
    uint256 internal constant EXEC_OFFSET = 100;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct CredibleAccountStorage {
        // Validator state
        bool initialized;
        // Wallet state
        EnumerableSetLib.AddressSet sessionKeys;
        mapping(address token => uint256) lockedAmounts;
        mapping(address token => uint256) claimedAmounts;
        EnumerableSetLib.AddressSet tokens;
        EnumerableSetLib.AddressSet activeTokens;
        // Session key configurations
        mapping(address sessionKey => SessionData) sessionConfigs;
        // Per-session token tracking
        mapping(address sessionKey => mapping(address token => uint256)) sessionLockedAmounts;
        mapping(address sessionKey => mapping(address token => uint256)) sessionClaimedAmounts;
        mapping(address sessionKey => EnumerableSetLib.AddressSet) sessionTokens;
    }

    /*//////////////////////////////////////////////////////////////
                               MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(address account => CredibleAccountStorage) private _credibleAccountStorage;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error CredibleAccountValidator_InvalidOwner();
    error CredibleAccountValidator_InvalidHookMultiPlexer();
    error CredibleAccountValidator_InvalidCredibleAccountHook();
    error CredibleAccountValidator_HookMultiplexerIsNotInstalled();
    error CredibleAccountValidator_NotAddedToHookMultiplexer();
    error CredibleAccountValidator_SessionKeyAlreadyExists(address sessionKey);
    error CredibleAccountValidator_SessionKeyDoesNotExist(address sessionKey);
    error CredibleAccountValidator_InvalidSessionKeyParameters(address sessionKey, uint48 validAfter, uint48 validUntil);
    error CredibleAccountValidator_NoTokenDataProvided();
    error CredibleAccountValidator_InvalidTokenData();
    error CredibleAccountValidator_LockedTokensNotClaimed(address sessionKey);
    error CredibleAccountValidator_SessionKeyNotInWalletList(address owner, address sessionKey);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CredibleAccountValidator_ModuleInstalled(address indexed wallet);
    event CredibleAccountValidator_ModuleUninstalled(address indexed wallet);
    event CredibleAccountValidator_SessionKeyEnabled(address indexed owner, address indexed sessionKey);
    event CredibleAccountValidator_SessionKeyDisabled(address indexed owner, address indexed sessionKey);
    event CredibleAccountValidator_TokenLocked(address indexed sessionKey, address indexed token, uint256 amount);
    event CredibleAccountValidator_TokenClaimed(
        address indexed sessionKey, address indexed wallet, address indexed token, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR/INIT
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, HookMultiPlexer _hookMultiPlexer) Ownable(_owner) {
        if (address(_hookMultiPlexer) == address(0)) {
            revert CredibleAccountValidator_InvalidHookMultiPlexer();
        }
        hookMultiPlexer = _hookMultiPlexer;
    }

    function initialize(CredibleAccountHook _caHook) external onlyOwner {
        if (address(_caHook) == address(0)) {
            revert CredibleAccountValidator_InvalidCredibleAccountHook();
        }
        caHook = _caHook;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC/EXTERNAL
    //////////////////////////////////////////////////////////////*/

    function onInstall(bytes calldata data) external override {
        CredibleAccountStorage storage store = _credibleAccountStorage[msg.sender];
        if (store.initialized) revert AlreadyInitialized(msg.sender);
        if (IModuleManager(msg.sender).getActiveHook() != address(hookMultiPlexer)) {
            revert CredibleAccountValidator_HookMultiplexerIsNotInstalled();
        }
        if (!hookMultiPlexer.hasHook(msg.sender, address(caHook), HookType.GLOBAL)) {
            revert CredibleAccountValidator_NotAddedToHookMultiplexer();
        }
        store.initialized = true;
        emit CredibleAccountValidator_ModuleInstalled(msg.sender);
    }

    function onUninstall(bytes calldata data) external override {
        CredibleAccountStorage storage store = _credibleAccountStorage[msg.sender];
        if (!store.initialized) revert NotInitialized(msg.sender);
        address[] memory sessionKeys = store.sessionKeys.values();
        for (uint256 i; i < sessionKeys.length; ++i) {
            if (!isSessionClaimed(sessionKeys[i], msg.sender)) {
                revert CredibleAccountValidator_LockedTokensNotClaimed(sessionKeys[i]);
            }
        }
        delete _credibleAccountStorage[msg.sender];
        emit CredibleAccountValidator_ModuleUninstalled(msg.sender);
    }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == MODULE_TYPE_VALIDATOR;
    }

    function isInitialized(address smartAccount) external view override returns (bool) {
        return _credibleAccountStorage[smartAccount].initialized;
    }

    function enableSessionKey(bytes calldata _data) external {
        ResourceLock memory rl = abi.decode(_data, (ResourceLock));
        CredibleAccountStorage storage store = _credibleAccountStorage[msg.sender];
        if (store.sessionKeys.contains(rl.sessionKey)) {
            revert CredibleAccountValidator_SessionKeyAlreadyExists(rl.sessionKey);
        }
        if (rl.sessionKey == address(0) || rl.validAfter == 0 || rl.validUntil == 0 || rl.validUntil <= rl.validAfter) {
            revert CredibleAccountValidator_InvalidSessionKeyParameters(rl.sessionKey, rl.validAfter, rl.validUntil);
        }
        if (rl.tokenData.length == 0) {
            revert CredibleAccountValidator_NoTokenDataProvided();
        }
        for (uint256 i; i < rl.tokenData.length; ++i) {
            if (rl.tokenData[i].token == address(0) || rl.tokenData[i].amount == 0) {
                revert CredibleAccountValidator_InvalidTokenData();
            }
        }
        store.sessionConfigs[rl.sessionKey] =
            SessionData({sessionKey: rl.sessionKey, validAfter: rl.validAfter, validUntil: rl.validUntil, live: true});
        store.sessionKeys.add(rl.sessionKey);
        for (uint256 i; i < rl.tokenData.length; ++i) {
            address token = rl.tokenData[i].token;
            uint256 amount = rl.tokenData[i].amount;
            store.sessionLockedAmounts[rl.sessionKey][token] = amount;
            store.sessionTokens[rl.sessionKey].add(token);
            store.lockedAmounts[token] += amount;
            store.tokens.add(token);
            store.activeTokens.add(token);
            emit CredibleAccountValidator_TokenLocked(rl.sessionKey, token, amount);
        }
        emit CredibleAccountValidator_SessionKeyEnabled(msg.sender, rl.sessionKey);
    }

    function disableSessionKey(address _sessionKey) external {
        CredibleAccountStorage storage store = _credibleAccountStorage[msg.sender];
        if (!store.sessionKeys.contains(_sessionKey)) {
            revert CredibleAccountValidator_SessionKeyNotInWalletList(msg.sender, _sessionKey);
        }
        if (store.sessionConfigs[_sessionKey].validUntil == 0) {
            revert CredibleAccountValidator_SessionKeyDoesNotExist(_sessionKey);
        }
        if (
            store.sessionConfigs[_sessionKey].validUntil >= block.timestamp
                && !isSessionClaimed(_sessionKey, msg.sender)
        ) {
            revert CredibleAccountValidator_LockedTokensNotClaimed(_sessionKey);
        }
        address[] memory tokens = store.sessionTokens[_sessionKey].values();
        for (uint256 i; i < tokens.length; ++i) {
            address token = tokens[i];
            uint256 lockedAmount = store.sessionLockedAmounts[_sessionKey][token];
            uint256 claimedAmount = store.sessionClaimedAmounts[_sessionKey][token];
            store.lockedAmounts[token] -= lockedAmount;
            store.claimedAmounts[token] -= claimedAmount;
            _updateTokenStatus(msg.sender, token);
            delete store.sessionLockedAmounts[_sessionKey][token];
            delete store.sessionClaimedAmounts[_sessionKey][token];
        }
        delete store.sessionConfigs[_sessionKey];
        delete store.sessionTokens[_sessionKey];
        store.sessionKeys.remove(_sessionKey);
        emit CredibleAccountValidator_SessionKeyDisabled(msg.sender, _sessionKey);
    }

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        override
        returns (uint256)
    {
        address recovered = ECDSA.recover(ECDSA.toEthSignedMessageHash(userOpHash), userOp.signature);
        if (!validateSessionKeyParams(recovered, userOp)) {
            return SIG_VALIDATION_FAILED;
        }
        CredibleAccountStorage storage store = _credibleAccountStorage[msg.sender];
        SessionData memory sessionConfig = store.sessionConfigs[recovered];
        return packValidationData(
            false, ValidUntil.wrap(sessionConfig.validUntil), ValidAfter.wrap(sessionConfig.validAfter)
        );
    }

    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4)
    {
        address recovered = ECDSA.recover(hash, signature);
        if (sender == recovered) {
            return ERC1271_MAGIC_VALUE;
        }
        bytes32 ethHash = ECDSA.toEthSignedMessageHash(hash);
        recovered = ECDSA.recover(ethHash, signature);
        if (sender == recovered) {
            return ERC1271_MAGIC_VALUE;
        }
        return ERC1271_INVALID;
    }

    function validateSessionKeyParams(address _sessionKey, PackedUserOperation calldata userOp) public returns (bool) {
        if (isSessionClaimed(_sessionKey, userOp.sender)) return false;
        bytes calldata callData = userOp.callData;
        if (bytes4(callData[:4]) == IERC7579Account.execute.selector) {
            ModeCode mode = ModeCode.wrap(bytes32(callData[4:36]));
            (CallType calltype,,,) = ModeLib.decode(mode);
            if (CallType.unwrap(calltype) == CallType.unwrap(CALLTYPE_SINGLE)) {
                return _validateSingleCall(callData, _sessionKey, userOp.sender);
            } else if (CallType.unwrap(calltype) == CallType.unwrap(CALLTYPE_BATCH)) {
                return _validateBatchCall(callData, _sessionKey, userOp.sender);
            }
        }

        return false;
    }

    function getSessionKeysByWallet() public view returns (address[] memory) {
        return _credibleAccountStorage[msg.sender].sessionKeys.values();
    }

    function getSessionKeysByWallet(address _wallet) public view returns (address[] memory) {
        return _credibleAccountStorage[_wallet].sessionKeys.values();
    }

    function hasSessionKey(address _wallet, address _sessionKey) public view returns (bool) {
        return _credibleAccountStorage[_wallet].sessionKeys.contains(_sessionKey);
    }

    function getSessionData(address _sessionKey, address _wallet) public view returns (SessionData memory) {
        return _credibleAccountStorage[_wallet].sessionConfigs[_sessionKey];
    }

    // Get locked balance for a specific token and session key
    function getSessionLockedBalance(address _wallet, address _sessionKey, address _token)
        public
        view
        returns (uint256)
    {
        CredibleAccountStorage storage store = _credibleAccountStorage[_wallet];
        return store.sessionLockedAmounts[_sessionKey][_token] - store.sessionClaimedAmounts[_sessionKey][_token];
    }

    // Get all locked token balances for a specific session key
    function getSessionLockedTokenBalances(address _wallet, address _sessionKey)
        public
        view
        returns (TokenData[] memory)
    {
        CredibleAccountStorage storage store = _credibleAccountStorage[_wallet];
        address[] memory tokens = store.sessionTokens[_sessionKey].values();
        TokenData[] memory result = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            address token = tokens[i];
            uint256 availableBalance =
                store.sessionLockedAmounts[_sessionKey][token] - store.sessionClaimedAmounts[_sessionKey][token];
            result[i] = TokenData(token, availableBalance);
        }
        return result;
    }

    // Get a specific locked token's available balance
    function getLockedBalance(address _wallet, address _token) public view returns (uint256) {
        CredibleAccountStorage storage store = _credibleAccountStorage[_wallet];
        return store.lockedAmounts[_token] - store.claimedAmounts[_token];
    }

    // Get locked token balances (only non-zero balances)
    function getLockedTokenBalances(address _wallet) public view returns (TokenData[] memory) {
        CredibleAccountStorage storage store = _credibleAccountStorage[_wallet];
        address[] memory activeTokens = store.activeTokens.values();
        TokenData[] memory result = new TokenData[](activeTokens.length);
        for (uint256 i; i < activeTokens.length; ++i) {
            address token = activeTokens[i];
            uint256 availableBalance = store.lockedAmounts[token] - store.claimedAmounts[token];
            result[i] = TokenData(token, availableBalance);
        }
        return result;
    }

    // Get available (unclaimed) balance for a specific token
    function getAvailableBalance(address _wallet, address _token) public view returns (uint256) {
        CredibleAccountStorage storage store = _credibleAccountStorage[_wallet];
        return store.lockedAmounts[_token] - store.claimedAmounts[_token];
    }

    function isSessionClaimed(address _sessionKey, address _wallet) public view returns (bool) {
        CredibleAccountStorage storage store = _credibleAccountStorage[_wallet];
        address[] memory tokens = store.sessionTokens[_sessionKey].values();
        for (uint256 i; i < tokens.length; ++i) {
            address token = tokens[i];
            if (store.sessionLockedAmounts[_sessionKey][token] > store.sessionClaimedAmounts[_sessionKey][token]) {
                return false;
            }
        }
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL/PRIVATE
    //////////////////////////////////////////////////////////////*/

    function _validateSingleCall(bytes calldata _callData, address _sessionKey, address _wallet)
        internal
        returns (bool)
    {
        (address target,, bytes calldata execData) = ExecutionLib.decodeSingle(_callData[EXEC_OFFSET:]);
        (bytes4 selector,,, uint256 amount) = _digestClaimTx(execData);
        if (!_isValidSelector(selector)) return false;
        return _validateTokenData(_sessionKey, _wallet, amount, target);
    }

    function _validateBatchCall(bytes calldata _callData, address _sessionKey, address _wallet)
        internal
        returns (bool)
    {
        Execution[] calldata execs = ExecutionLib.decodeBatch(_callData[EXEC_OFFSET:]);
        for (uint256 i; i < execs.length; ++i) {
            (bytes4 selector,,, uint256 amount) = _digestClaimTx(execs[i].callData);
            if (!_isValidSelector(selector) || !_validateTokenData(_sessionKey, _wallet, amount, execs[i].target)) {
                return false;
            }
        }
        return true;
    }

    function _validateTokenData(address _sessionKey, address _wallet, uint256 _amount, address _token)
        internal
        returns (bool)
    {
        CredibleAccountStorage storage store = _credibleAccountStorage[_wallet];
        if (!store.sessionTokens[_sessionKey].contains(_token)) return false;
        uint256 lockedAmount = store.sessionLockedAmounts[_sessionKey][_token];
        uint256 claimedAmount = store.sessionClaimedAmounts[_sessionKey][_token];
        if (_walletTokenBalance(_wallet, _token) >= _amount && _amount == lockedAmount && claimedAmount < lockedAmount)
        {
            uint256 newClaim = _amount - claimedAmount;
            store.sessionClaimedAmounts[_sessionKey][_token] += newClaim;
            store.claimedAmounts[_token] += newClaim;
            emit CredibleAccountValidator_TokenClaimed(_sessionKey, _wallet, _token, newClaim);
            _updateTokenStatus(_wallet, _token);
            return true;
        }
        return false;
    }

    function _updateTokenStatus(address _wallet, address _token) internal {
        CredibleAccountStorage storage store = _credibleAccountStorage[_wallet];
        uint256 availableBalance = store.lockedAmounts[_token] - store.claimedAmounts[_token];
        if (availableBalance == 0) {
            if (store.activeTokens.contains(_token)) {
                store.activeTokens.remove(_token);
            }
        } else {
            if (!store.activeTokens.contains(_token)) {
                store.activeTokens.add(_token);
            }
        }
    }

    function _digestClaimTx(bytes calldata _data) internal pure returns (bytes4, address, address, uint256) {
        bytes4 selector = bytes4(_data[0:4]);
        if (!_isValidSelector(selector)) {
            return (bytes4(0), address(0), address(0), 0);
        }
        address from = address(bytes20(_data[16:36]));
        address to = address(bytes20(_data[48:68]));
        uint256 amount = uint256(bytes32(_data[68:100]));

        return (selector, from, to, amount);
    }

    function _isValidSelector(bytes4 _selector) internal pure returns (bool) {
        return _selector == IERC20.transferFrom.selector;
    }

    function _walletTokenBalance(address _wallet, address _token) internal view returns (uint256) {
        return IERC20(_token).balanceOf(_wallet);
    }
}
