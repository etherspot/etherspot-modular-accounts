# Credible Account Module

The CredibleAccountModule is a dual-purpose ERC-7579 module that functions as both a validator and hook for smart accounts, enabling secure session key management with resource locking and token balance validation.

## Overview

This module implements session-based authentication where users can create time-limited session keys with locked token amounts. It validates user operations against session parameters and ensures sufficient unlocked token balances through pre/post execution hooks.

## Key Features

- Session key management with time-based validity
- Token resource locking and claiming mechanisms
- Dual validator and hook functionality
- Role-based access control for session key management
- Batch operations for session key management
- Emergency controls for administrative actions
- Integration with HookMultiPlexer for execution validation

## Architecture

The module operates in two modes:

- **Validator Mode**: Validates user operations signed by session keys
- **Hook Mode**: Performs pre/post execution checks for token balance validation

## Core Concepts

### Session Keys

Temporary signing keys with restricted permissions and time limits that can execute specific token operations on behalf of the main account.

### Resource Locks

Token amounts locked when creating session keys, preventing double-spending and ensuring session key holders can only claim their allocated amounts.

### Token Claims

The process of using session keys to transfer locked tokens, with validation against the original resource lock parameters.

## Contract Methods

### Installation Methods

#### `onInstall(bytes calldata data)`

Installs the module for a smart account in either validator or hook mode.

**Parameters:**

- `data`: Encoded module type (validator or hook) and installation parameters

**Requirements:**

- For validator mode: HookMultiPlexer must be installed and configured
- Module type must be valid (validator or hook)

**Events:**

- `CredibleAccountModule_ModuleInstalled(address wallet)`

#### `onUninstall(bytes calldata data)`

Removes the module from a smart account.

**Requirements:**

- All session keys must be expired or fully claimed before uninstalling validator
- Hook cannot be uninstalled while validator is active

**Events:**

- `CredibleAccountModule_ModuleUninstalled(address wallet)`

### Session Key Management

#### `enableSessionKey(bytes calldata _resourceLock)`

Creates a new session key with specified resource locks and time constraints.

**Parameters:**

- `_resourceLock`: Encoded ResourceLock struct containing session parameters

**ResourceLock Structure:**

```solidity
struct ResourceLock {
    uint256 chainId; // The current chain id
    address smartWallet; // The address of the smart wallet
    address sessionKey; // The address of the session key
    uint48 validAfter; // The timestamp after which the session key is valid
    uint48 validUntil; // The timestamp until which the session key is valid
    bytes32 bidHash; // The hash of the bid
    TokenData[] tokenData; // The locked token amounts
}
```

**TokenData structure:**

```solidity
struct TokenData {
    address token; // The address of the token
    uint256 amount; // The amount of tokens locked
}
```

**Requirements:**

- Session key cannot be zero address
- Valid time range (validUntil > validAfter > 0)
- Sufficient token balance for locking

**Events:**

- `CredibleAccountModule_SessionKeyEnabled(address sessionKey, address wallet)`

#### `disableSessionKey(address _sessionKey)`

Disables a session key and cleans up associated data.

**Access Control:**

- Session key owner can disable their own keys
- Accounts with SESSION_KEY_DISABLER role can disable any key

**Requirements:**

- Session key must exist
- All locked tokens must be claimed or session must be expired

**Events:**

- `CredibleAccountModule_SessionKeyDisabled(address sessionKey, address caller)`

#### `batchDisableSessionKeys(address[] calldata _sessionKeys)`

Disables multiple session keys in a single transaction.

**Access Control:**

- Requires SESSION_KEY_DISABLER role

**Behavior:**

- Skips non-existent keys instead of reverting
- Only disables expired keys or keys with all tokens claimed

#### `emergencyDisableSessionKey(address _sessionKey)`

Emergency function to disable any session key regardless of claim status.

**Access Control:**

- Requires DEFAULT_ADMIN_ROLE

**Use Cases:**

- Security incidents
- Compromised session keys
- Administrative cleanup

### Validation Methods

#### `validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)`

Validates user operations signed by session keys.

**Process:**

1. Recovers signer from signature
2. Validates session key parameters against operation
3. Checks token amounts and targets
4. Returns packed validation data with time constraints

**Returns:**

- `VALIDATION_SUCCESS` with time bounds if valid
- `VALIDATION_FAILED` if invalid

#### `validateSessionKeyParams(address _sessionKey, PackedUserOperation calldata userOp)`

Validates that a user operation complies with session key restrictions.

**Validation Checks:**

- Session key is not fully claimed
- Operation targets allowed tokens
- Transfer amounts match locked amounts
- Sufficient wallet balance exists

**Supported Operations:**

- Single ERC20 transfers
- Batch ERC20 transfers

### Query Methods

#### `getSessionKeysByWallet()` / `getSessionKeysByWallet(address _wallet)`

Returns all session keys associated with a wallet.

#### `getSessionKeyData(address _sessionKey)`

Returns session data for a specific session key.

**Returns:**

```solidity
struct SessionData {
    address sessionKey;
    uint48 validAfter;
    uint48 validUntil;
    bool live;
}
```

#### `getLockedTokensForSessionKey(address _sessionKey)`

Returns locked token information for a session key.

**Returns:**

```solidity
struct LockedToken {
    address token;
    uint256 lockedAmount;
    uint256 claimedAmount;
}
```

#### `getLiveSessionKeysForWallet(address _wallet)`

Returns only active (non-expired, unclaimed) session keys.

#### `getExpiredSessionKeysForWallet(address _wallet)`

Returns expired or fully claimed session keys.

#### `tokenTotalLockedForWallet(address _token)`

Returns total locked amount for a specific token across all session keys.

#### `cumulativeLockedForWallet()`

Returns aggregated locked token data across all active session keys.

#### `isSessionClaimed(address _sessionKey)`

Checks if all tokens for a session key have been claimed.

### Hook Methods

#### `preCheck(address msgSender, uint256 msgValue, bytes calldata msgData)`

Pre-execution hook that captures current locked token state.

**Returns:**

- Encoded wallet address and current locked balances

#### `postCheck(bytes calldata hookData)`

Post-execution hook that validates sufficient unlocked balance remains.

**Validation:**

- Ensures wallet retains enough unlocked tokens after execution
- Prevents over-spending of locked resources

### Access Control Methods

#### `grantSessionKeyDisablerRole(address account)`

Grants SESSION_KEY_DISABLER role to an account.

**Access Control:**

- Requires DEFAULT_ADMIN_ROLE

#### `revokeSessionKeyDisablerRole(address account)`

Revokes SESSION_KEY_DISABLER role from an account.

#### `hasSessionKeyDisablerRole(address account)`

Checks if an account has the SESSION_KEY_DISABLER role.

#### `getSessionKeyDisablers()`

Returns all accounts with SESSION_KEY_DISABLER role.

## Data Structures

### ResourceLock

```solidity
struct ResourceLock {
    uint256 chainId;
    address smartWallet;
    address sessionKey;
    uint48 validAfter;
    uint48 validUntil;
    bytes32 bidHash;
    TokenData[] tokenData;
}
```

### TokenData

```solidity
struct TokenData {
    address token;
    uint256 amount;
}
```

### SessionData

```solidity
struct SessionData {
    address sessionKey;
    uint48 validAfter;
    uint48 validUntil;
    bool live;
}
```

### LockedToken

```solidity
struct LockedToken {
    address token;
    uint256 lockedAmount;
    uint256 claimedAmount;
}
```

## Events

- `CredibleAccountModule_ModuleInstalled(address wallet)`
- `CredibleAccountModule_ModuleUninstalled(address wallet)`
- `CredibleAccountModule_SessionKeyEnabled(address sessionKey, address wallet)`
- `CredibleAccountModule_SessionKeyDisabled(address sessionKey, address caller)`
- `SessionKeyDisablerRoleGranted(address account, address granter)`
- `SessionKeyDisablerRoleRevoked(address account, address revoker)`

## Error Conditions

- `CredibleAccountModule_ModuleAlreadyInstalled`: Module already installed
- `CredibleAccountModule_ModuleNotInstalled`: Module not installed for wallet
- `CredibleAccountModule_InvalidSessionKey`: Invalid session key address
- `CredibleAccountModule_InvalidValidAfter`: Invalid start timestamp
- `CredibleAccountModule_InvalidValidUntil`: Invalid end timestamp
- `CredibleAccountModule_SessionKeyDoesNotExist`: Session key not found
- `CredibleAccountModule_LockedTokensNotClaimed`: Tokens still locked
- `CredibleAccountModule_InvalidHookMultiPlexer`: Invalid hook multiplexer
- `CredibleAccountModule_HookMultiplexerIsNotInstalled`: Required hook not installed
- `CredibleAccountModule_NotAddedToHookMultiplexer`: Module not registered with hook
- `CredibleAccountModule_InsufficientUnlockedBalance`: Insufficient unlocked tokens
- `CredibleAccountModule_UnauthorizedDisabler`: Unauthorized session key disabler

## Security Considerations

### Access Control

- Role-based permissions for administrative functions
- Session key owners can only disable their own keys
- Emergency controls for security incidents

### Token Safety

- Pre/post execution hooks prevent over-spending
- Locked tokens cannot be double-spent
- Balance validation ensures sufficient unlocked funds

### Time-based Security

- Session keys have enforced expiration times
- Expired sessions are automatically invalidated
- Time bounds are included in validation data

### Integration Security

- Requires HookMultiPlexer for proper operation
- Validates hook installation before enabling
- Ensures proper module registration

## Integration Guide

### Basic Setup

1. **Install HookMultiPlexer**

   ```solidity
   // Install hook multiplexer on smart account
   account.installModule(MODULE_TYPE_HOOK, hookMultiplexer, "");
   ```

2. **Install CredibleAccountModule as Hook**

   ```solidity
   // Install as hook first
   account.installModule(MODULE_TYPE_HOOK, credibleModule, abi.encode(MODULE_TYPE_HOOK));
   ```

3. **Register with HookMultiPlexer**

   ```solidity
   // Add to hook multiplexer
   hookMultiplexer.addHook(credibleModule, HookType.GLOBAL);
   ```

4. **Install as Validator**

   ```solidity
   // Install as validator
   account.installModule(MODULE_TYPE_VALIDATOR, credibleModule, abi.encode(MODULE_TYPE_VALIDATOR));
   ```

## Troubleshooting Guide

### Common Installation Issues

**Module Installation Fails**

- Verify HookMultiPlexer is installed first
- Ensure module is registered with HookMultiPlexer
- Check module type parameter in installation data

**Hook Not Working**

- Confirm module installed as both hook and validator
- Verify HookMultiPlexer is active hook on account
- Check hook registration with correct HookType

### Session Key Issues

**Session Key Creation Fails**

- Verify sufficient token balance for locking
- Check timestamp validity (validUntil > validAfter > 0)
- Ensure session key address is not zero

**Validation Failures**

- Confirm session key hasn't expired
- Verify signature format and recovery
- Check token amounts match locked amounts exactly
- Ensure target token is in session's locked tokens

**Disable Failures**

- Check if tokens are fully claimed or session expired
- Verify caller has appropriate permissions
- For emergency disable, ensure DEFAULT_ADMIN_ROLE

### Balance Issues

**Insufficient Unlocked Balance**

- Check total locked vs wallet balance
- Verify hook is properly installed and active
- Monitor for concurrent session key usage

**Token Transfer Failures**

- Ensure exact amount matching between lock and transfer
- Verify token contract implements standard ERC20
- Check for token-specific transfer restrictions

### Known Limitations

1. **Single Transfer Only**: Only supports `transfer()` function, not `transferFrom()`
2. **Exact Amount Matching**: Transfer amounts must exactly match locked amounts
3. **No Partial Claims**: Session keys must be fully utilized or expire
4. **Hook Dependency**: Requires HookMultiPlexer for proper operation
5. **Gas Costs**: Complex operations can be gas-intensive