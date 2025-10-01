# Resource Lock Validator

The ResourceLockValidator is a validator module for ERC-7579 smart accounts that enables secure session key management through resource locking mechanisms and merkle proofs for batched authorizations.

## Overview

This validator implements dual-mode signature verification supporting both direct ECDSA signatures and merkle proof-based validations. It extracts resource lock data from user operation call data and validates operations against predefined resource constraints, enabling efficient batch authorization of multiple resource locks through merkle tree structures.

## Key Features

- ECDSA signature validation with eth-signed message support
- Merkle proof verification for batched resource locks
- Dynamic resource lock extraction from call data
- ERC-1271 compatible signature verification
- Support for both single and batch call operations
- Bid hash integration for auction/bidding systems
- Chain ID validation for cross-chain security

## Architecture

The validator operates in two validation modes:

- **Direct Mode**: Standard ECDSA signature validation (65-byte signatures)
- **Merkle Proof Mode**: Batch validation using merkle proofs for multiple resource locks (>65-byte signatures)

## Core Concepts

### Resource Locks

Structured authorizations extracted from user operation call data that define the parameters for session key usage, including time bounds, token permissions, and bid hash for auction integration.

### Dynamic Call Data Parsing

The validator dynamically extracts resource lock parameters from the user operation's call data, supporting both single and batch execution modes.

### Merkle Proof Validation

Enables efficient batch authorization where multiple resource locks can be validated against a single merkle root signature, reducing gas costs for bulk operations.

### Bid Hash Integration

Supports auction and bidding systems by including bid hash validation in resource locks.

## Contract Methods

### Installation Methods

#### `onInstall(bytes calldata _data)`

Installs the validator for a smart account, setting the owner from the provided data.

**Parameters:**

- `_data`: Encoded data with owner address in the last 20 bytes

**Process:**

1. Extracts owner address from the last 20 bytes of data
2. Checks if validator is already installed
3. Sets owner and enables validator
4. Emits installation event

**Requirements:**

- Validator must not already be installed for the account
- Owner address must be valid

**Events:**

- `RLV_ValidatorEnabled(address smartAccount, address owner)`

**Errors:**

- `RLV_AlreadyInstalled(address scw, address eoa)`: If validator is already installed

#### `onUninstall(bytes calldata)`

Removes the validator from a smart account and cleans up associated data.

**Process:**

1. Checks if validator is initialized
2. Deletes validator storage
3. Emits uninstall event

**Requirements:**

- Validator must be installed for the account

**Events:**

- `RLV_ValidatorDisabled(address smartAccount)`

**Errors:**

- `RLV_NotInstalled(address scw)`: If validator is not installed

### Validation Methods

#### `validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)`

Primary validation method that handles both direct signatures and merkle proof validations with dynamic resource lock extraction.

**Parameters:**

- `userOp`: The user operation to validate
- `userOpHash`: Hash of the user operation

**Process:**

1. Determines signature type based on length
2. For direct signatures (65 bytes):
   - Recovers signer using standard ECDSA
   - Falls back to eth-signed message recovery
3. For merkle proof signatures (>65 bytes):
   - Extracts resource lock from call data
   - Parses signature components (ECDSA + root + proof)
   - Validates merkle proof against resource lock hash
   - Verifies root signature

**Signature Format:**

- **Direct (65 bytes)**: `[r: 32][s: 32][v: 1]`
- **Merkle Proof (>97 bytes)**: `[r: 32][s: 32][v: 1][root: 32][proof: variable]`

**Returns:**

- `SIG_VALIDATION_SUCCESS` (0) if validation succeeds
- `SIG_VALIDATION_FAILED` (1) if validation fails

**Errors:**

- `RLV_ResourceLockHashNotInProof()`: Resource lock hash not found in merkle proof

#### `isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)`

ERC-1271 compatible signature verification method for external signature validation.

**Parameters:**

- `sender`: Address of the signature sender (unused in current implementation)
- `hash`: Hash to verify signature against
- `signature`: Signature data (direct or with merkle proof)

**Process:**

1. For direct signatures: Standard ECDSA recovery
2. For merkle proof signatures: Validates proof against provided hash
3. Compares recovered signer with validator owner

**Returns:**

- `0x1626ba7e`: ERC-1271 magic value for valid signatures
- `0xffffffff`: Invalid signature indicator

**Errors:**

- `RLV_ResourceLockHashNotInProof()`: Hash not found in merkle proof

### Utility Methods

#### `isModuleType(uint256 typeID)`

Checks if the module supports the specified module type.

**Parameters:**

- `typeID`: Module type identifier to check

**Returns:**

- `true` if module type is validator (`MODULE_TYPE_VALIDATOR`)
- `false` otherwise

#### `isInitialized(address smartAccount)`

Checks if the validator is initialized for a given smart account.

**Parameters:**

- `smartAccount`: Address of the smart account to check

**Returns:**

- `true` if validator is installed and enabled
- `false` otherwise

### Internal Methods

#### `_getResourceLock(bytes calldata _callData)`

Dynamically extracts resource lock data from user operation call data.

**Parameters:**

- `_callData`: The call data from the user operation

**Process:**

1. Validates call data starts with `execute` selector
2. Decodes execution mode (single or batch)
3. For single calls: Extracts resource lock from execution data
4. For batch calls: Searches for resource lock in batch executions
5. Parses token data array and constructs ResourceLock struct

**Supported Call Types:**

- `CALLTYPE_SINGLE`: Single execution with embedded resource lock
- `CALLTYPE_BATCH`: Batch execution with resource lock in one of the calls

**Returns:**

- `ResourceLock` struct with extracted parameters

**Errors:**

- `RLV_InvalidSelector()`: Invalid function selector in batch call
- `RLV_InvalidCallType()`: Unsupported call type

#### `_buildResourceLockHash(ResourceLock memory _lock)`

Builds a unique hash for a resource lock using all its parameters.

**Parameters:**

- `_lock`: The ResourceLock struct containing all lock parameters

**Hash Components:**

- Chain ID
- Smart wallet address
- Session key address
- Valid after timestamp
- Valid until timestamp
- Bid hash
- Encoded token data array

**Returns:**

- `bytes32`: The unique hash representing this resource lock

## Data Structures

### ValidatorStorage

```solidity
struct ValidatorStorage {
    address owner;    // Owner of the validator
    bool enabled;     // Whether validator is enabled
}
```

### ResourceLock

```solidity
struct ResourceLock {
    uint256 chainId;           // Target chain ID
    address smartWallet;       // Smart wallet address
    address sessionKey;        // Session key address
    uint48 validAfter;        // Start timestamp
    uint48 validUntil;        // End timestamp
    bytes32 bidHash;          // Bid hash for auction integration
    TokenData[] tokenData;    // Allowed token operations
}
```

### TokenData

```solidity
struct TokenData {
    address token;    // Token contract address
    uint256 amount;   // Token amount
}
```

## Events

### `RLV_ValidatorEnabled(address smartAccount, address owner)`

Emitted when validator is successfully installed for a smart account.

**Parameters:**

- `smartAccount`: Address of the smart account
- `owner`: Address of the validator owner

### `RLV_ValidatorDisabled(address smartAccount)`

Emitted when validator is uninstalled from a smart account.

**Parameters:**

- `smartAccount`: Address of the smart account

## Error Conditions

### Installation Errors

- `RLV_AlreadyInstalled(address scw, address eoa)`: Validator already installed for the account
- `RLV_NotInstalled(address scw)`: Validator not installed for the account

### Validation Errors

- `RLV_ResourceLockHashNotInProof()`: Resource lock hash not found in merkle proof
- `RLV_InvalidSelector()`: Invalid function selector in batch call
- `RLV_InvalidCallType()`: Unsupported call type (not single or batch)

## Integration Guide

### Basic Setup

1. **Deploy Validator**

   ```solidity
   ResourceLockValidator validator = new ResourceLockValidator();
   ```

2. **Install on Smart Account**

   ```solidity
   // Owner address in last 20 bytes
   bytes memory installData = abi.encodePacked(
       ownerAddress
   );
   account.installModule(MODULE_TYPE_VALIDATOR, address(validator), installData);
   ```

## Dependencies

- **Solady**: ECDSA signature validation and merkle proof verification
- **ERC-7579**: Smart account module interfaces and standards
- **ERC-4337**: Account abstraction user operation handling
- **OpenZeppelin**: Standard library utilities (if used in integration)

## License

This validator is released under the MIT License. See the LICENSE file for details.

