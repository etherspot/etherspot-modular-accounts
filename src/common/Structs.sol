// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../common/Enums.sol";

/// @title ExecutionValidation
/// @notice Struct containing data for validating an execution
/// @dev Used to pass ValidationData to the validation function
struct ExecutionValidation {
    uint48 validAfter; // Timestamp after which the execution becomes valid
    uint48 validUntil; // Timestamp until which the execution remains valid
}

struct ParamCondition {
    uint256 offset; // The offset of the amount to check value against
    ComparisonRule rule; // The comparison rule to be applied
    bytes32 value; // The maximum value allowed in this operation
}

/// @title Permission
/// @notice Struct defining the permission granted to a session key
/// @dev Used to specify and validate allowed actions for a session key
struct Permission {
    address target; // The contract address for which the permission is granted
    bytes4 selector; // The function selector of the permitted method
    uint256 payableLimit; // call payable limit for the execution
    uint256 uses; // Remaining number of times the Permission can be used
    ParamCondition[] paramConditions; // Array of specific conditions for this permission
}

/// @title SessionData
/// @notice Struct containing all data related to a session key
/// @dev Used to manage and validate session keys
struct SessionData {
    address sessionKey; // The address of the session key
    uint48 validAfter; // The timestamp after which the session key is valid
    uint48 validUntil; // The timestamp until which the session key is valid
    bool live; // Flag indicating whether the session key is active or paused
}

/// @title TokenData
/// @notice Struct containing basic token information
/// @dev Used to store token addresses and corresponding amounts
struct TokenData {
    address token;
    uint256 amount;
}

// CredibleAccountModule
struct ResourceLock {
    uint256 chainId;
    address smartWallet;
    address sessionKey;
    uint48 validAfter;
    uint48 validUntil;
    bytes32 bidHash;
    TokenData[] tokenData;
}

// HookMultiplexer
struct SigHookInit {
    bytes4 sig;
    address[] subHooks;
}

struct HookAndContext {
    address hook;
    bytes context;
}

struct SignatureHooks {
    bytes4[] allSigs;
    mapping(bytes4 => address[]) sigHooks;
}

struct Config {
    bool initialized;
    mapping(HookType hookType => address[]) hooks;
    mapping(HookType hookType => SignatureHooks) sigHooks;
}
