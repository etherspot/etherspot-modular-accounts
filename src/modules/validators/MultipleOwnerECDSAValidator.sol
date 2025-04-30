// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IMultipleOwnerECDSAValidator} from "../../interfaces/modules/IMultipleOwnerECDSAValidator.sol";
import {
    ERC1271_INVALID,
    ERC1271_MAGIC_VALUE,
    MODULE_TYPE_VALIDATOR,
    SIG_VALIDATION_SUCCESS,
    SIG_VALIDATION_FAILED
} from "../../types/Constants.sol";

/// @title MultipleOwnerECDSAValidator
/// @author @cryptonoyaiba | Etherspot
/// @notice A validator module that supports multiple owners for a smart account
/// @dev Implements ECDSA signature validation for multiple owners
contract MultipleOwnerECDSAValidator is IMultipleOwnerECDSAValidator {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Storage structure for validator configuration
    /// @param owners Array of owner addresses for the smart account
    /// @param isOwner Mapping to quickly check if an address is an owner
    /// @param enabled Whether the validator is active
    struct ValidatorStorage {
        address[] owners;
        mapping(address => bool) isOwner; // For O(1) lookups
        bool enabled;
    }

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps smart account addresses to their validator configuration
    mapping(address => ValidatorStorage) public validatorStorage;

    /*//////////////////////////////////////////////////////////////
                        PUBLIC/EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the validator when installed in a smart account
    /// @dev Sets up initial owners for the smart account
    /// @param data The installation data containing owner addresses
    /// @custom:events Emits MOECDSA_ValidatorEnabled and MOECDSA_ValidatorOwnerAdded events
    /// @custom:errors Various errors if initialization parameters are invalid
    function onInstall(bytes calldata data) external override {
        if (validatorStorage[msg.sender].enabled) {
            revert MOECDSA_AlreadyInitialized(msg.sender);
        }
        address[] memory owners = abi.decode(data, (address[]));
        if (owners.length == 0) revert MOECDSA_InvalidOwnerData();
        for (uint256 i; i < owners.length; ++i) {
            address owner = owners[i];
            if (owner == address(0)) revert MOECDSA_AddingInvalidOwner(msg.sender, owner);
            validatorStorage[msg.sender].owners.push(owner);
            validatorStorage[msg.sender].isOwner[owner] = true;
            emit MOECDSA_ValidatorOwnerAdded(msg.sender, owner);
        }
        validatorStorage[msg.sender].enabled = true;
        emit MOECDSA_ValidatorEnabled(msg.sender);
    }

    /// @notice Cleans up validator data when uninstalled from a smart account
    /// @dev Removes all validator configuration for the calling smart account
    /// @param data Unused parameter (required by interface)
    /// @custom:events Emits MOECDSA_ValidatorDisabled when successfully uninstalled
    /// @custom:errors MOECDSA_NotInitialized if not initialized for the smart account
    function onUninstall(bytes calldata data) external override {
        if (!_isInitialized(msg.sender)) revert MOECDSA_NotInitialized(msg.sender);
        delete validatorStorage[msg.sender];
        emit MOECDSA_ValidatorDisabled(msg.sender);
    }

    /// @notice Checks if the module is initialized for a specific smart account
    /// @param smartAccount Address of the smart account to check
    /// @return bool True if the module is initialized, false otherwise
    function isInitialized(address smartAccount) external view override returns (bool) {
        return _isInitialized(smartAccount);
    }

    /// @notice Checks if this module supports the specified module type
    /// @param typeID The module type identifier to check
    /// @return bool True if this module is a validator module
    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == MODULE_TYPE_VALIDATOR;
    }

    /// @notice Checks if an address is an owner of the smart account
    /// @param smartAccount The address of the smart account
    /// @param owner The address to check
    /// @return bool True if the address is an owner, false otherwise
    function isOwner(address smartAccount, address owner) external view returns (bool) {
        return _isOwner(smartAccount, owner);
    }

    /// @notice Adds a new owner to the smart account
    /// @dev Can only be called by the wallet itself or an existing owner
    /// @param _scw The address of the smart account
    /// @param _newOwner The address of the new owner to add
    /// @custom:events Emits MOECDSA_ValidatorOwnerAdded when an owner is successfully added
    /// @custom:errors Various errors if the owner is invalid or caller is unauthorized
    function addOwner(address _scw, address _newOwner) external {
        if (msg.sender != _scw && !_isOwner(_scw, msg.sender)) revert MOECDSA_NotOwner(msg.sender);
        if (_newOwner == address(0) || _isOwner(_scw, _newOwner)) revert MOECDSA_AddingInvalidOwner(_scw, _newOwner);
        validatorStorage[_scw].owners.push(_newOwner);
        validatorStorage[_scw].isOwner[_newOwner] = true;
        emit MOECDSA_ValidatorOwnerAdded(_scw, _newOwner);
    }

    /// @notice Removes an owner from the smart account
    /// @dev Can only be called by the wallet itself or an existing owner
    /// @param _scw The address of the smart account
    /// @param _owner The address of the owner to remove
    /// @custom:events Emits MOECDSA_ValidatorOwnerRemoved when an owner is successfully removed
    /// @custom:errors Various errors if the owner is invalid or caller is unauthorized
    function removeOwner(address _scw, address _owner) external {
        if (msg.sender != _scw && !_isOwner(_scw, msg.sender)) revert MOECDSA_NotOwner(msg.sender);
        if (validatorStorage[_scw].owners.length == 1) revert MOECDSA_CannotRemoveLastOwner(_scw);
        if (!_isOwner(_scw, _owner)) revert MOECDSA_RemovingInvalidOwner(_scw, _owner);
        validatorStorage[_scw].isOwner[_owner] = false;
        address[] storage owners = validatorStorage[_scw].owners;
        uint256 idx = owners.length;
        for (uint256 i; i < owners.length; ++i) {
            if (owners[i] == _owner) {
                idx = i;
                break;
            }
        }
        if (idx < owners.length) {
            owners[idx] = owners[owners.length - 1];
            owners.pop();
            emit MOECDSA_ValidatorOwnerRemoved(_scw, _owner);
        }
    }

    /// @notice Validates a user operation signed by an owner
    /// @dev Implements the ERC-4337 validation interface
    /// @param userOp The packed user operation to validate
    /// @param userOpHash The hash of the user operation for signature verification
    /// @return uint256 Validation result (success or failure)
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        override
        returns (uint256)
    {
        bytes calldata sig = userOp.signature;
        address recovered = ECDSA.recover(userOpHash, sig);
        if (recovered == address(0) || !_isOwner(msg.sender, recovered)) {
            bytes32 ethHash = userOpHash.toEthSignedMessageHash();
            recovered = ECDSA.recover(ethHash, sig);
            if (recovered == address(0) || !_isOwner(msg.sender, recovered)) {
                return SIG_VALIDATION_FAILED;
            }
        }
        return SIG_VALIDATION_SUCCESS;
    }

    /// @notice ERC-1271 signature validation
    /// @dev Implements the ERC-1271 validation interface
    /// @param sender The address of the sender requesting validation (unused)
    /// @param hash The hash of the data that was signed
    /// @param signature The signature to validate
    /// @return bytes4 Magic value if signature is valid, error value otherwise
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        override
        returns (bytes4)
    {
        address recovered = ECDSA.recover(hash, signature);
        if (_isOwner(msg.sender, recovered)) {
            return ERC1271_MAGIC_VALUE;
        }
        bytes32 ethHash = ECDSA.toEthSignedMessageHash(hash);
        recovered = ECDSA.recover(ethHash, signature);
        if (_isOwner(msg.sender, recovered)) {
            return ERC1271_MAGIC_VALUE;
        }
        return ERC1271_INVALID; // Invalid signature
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL/PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if the validator is initialized for a smart account
    /// @param _scw The address of the smart account
    /// @return bool True if initialized, false otherwise
    function _isInitialized(address _scw) internal view returns (bool) {
        return validatorStorage[_scw].enabled;
    }

    /// @notice Checks if an address is an owner of the smart account
    /// @param _scw The address of the smart account
    /// @param _owner The address to check
    /// @return bool True if the address is an owner, false otherwise
    function _isOwner(address _scw, address _owner) internal view returns (bool) {
        return validatorStorage[_scw].enabled && validatorStorage[_scw].isOwner[_owner];
    }
}
