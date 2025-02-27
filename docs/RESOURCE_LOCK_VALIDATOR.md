# Resource Lock Validator

The ResourceLockValidator is a validator module for ERC-7579 smart accounts that enables secure session key management through resource locking mechanisms and merkle proofs.

## Overview

This validator implements signature verification for both direct ECDSA signatures and merkle proof-based validations. It supports standard ethereum signatures as well as merkle proof verification for batched resource lock authorizations.

## Key Features

- ECDSA signature validation
- Merkle proof verification
- Resource lock management
- ERC-1271 compatible signature verification
- Support for both direct and eth-signed message recovery

## Contract Methods

### Installation Methods

#### `onInstall(bytes calldata _data)`

Installs the validator for a smart account, setting the owner from the provided data.

- Reverts if already installed
- Emits `RLV_ValidatorEnabled` event

#### `onUninstall(bytes calldata)`

Removes the validator from a smart account.

- Reverts if not installed
- Emits `RLV_ValidatorDisabled` event

### Validation Methods

#### `validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)`

Validates user operations through either direct signatures or merkle proofs.

- Returns validation success/failure status
- Handles both standard 65-byte signatures and merkle proof packed signatures

#### `isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)`

ERC-1271 compatible signature verification method.

- Returns ERC-1271 magic value for valid signatures
- Supports both direct signatures and merkle proof verification

### Utility Methods

#### `isModuleType(uint256 typeID)`

Checks if the module is a validator type.

#### `isInitialized(address smartAccount)`

Checks if the validator is initialized for a given smart account.

## Resource Lock Structure

Resource locks contain the following parameters:

- Chain ID
- Smart wallet address
- Session key address
- Valid after timestamp
- Valid until timestamp
- Token data array
- Nonce

## Token Data Structure

Each token data entry contains:

- Token address
- Amount

## Events

- `RLV_ValidatorEnabled(address smartAccount, address owner)`
- `RLV_ValidatorDisabled(address smartAccount)`

## Error Conditions

- `RLV_AlreadyInstalled`: Validator already installed for account
- `RLV_NotInstalled`: Validator not installed for account
- `RLV_ResourceLockHashNotInProof`: Resource lock hash not found in merkle proof
- `RLV_OnlyCallTypeSingle`: Only single call type operations supported

## Security Considerations

- Merkle proofs must be properly validated
- Signature recovery includes both standard and eth-signed message formats
- Resource lock parameters should be carefully validated
- Nonce management is critical for replay protection

## Integration Guide

1. Install validator on smart account
2. Generate resource lock with desired parameters
3. Create merkle tree if batching multiple locks
4. Sign either directly or through merkle root
5. Submit user operation with appropriate signature format

## Dependencies

- Solady ECDSA
- Solady MerkleProofLib
