// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IECDSAValidator} from "../../interfaces/modules/IECDSAValidator.sol";
import {
    ERC1271_INVALID,
    ERC1271_MAGIC_VALUE,
    MODULE_TYPE_VALIDATOR,
    SIG_VALIDATION_SUCCESS,
    SIG_VALIDATION_FAILED
} from "../../types/Constants.sol";
import {ValidatorStorage} from "../../types/Structs.sol";

/// @title ECDSAValidator
/// @author @cryptonoyaiba | Etherspot
/// @notice A validator module for ERC-7579 smart accounts that uses ECDSA signatures for authentication
/// @dev Implements single-owner validation with support for both standard and EIP-191 signatures
contract ECDSAValidator is IECDSAValidator {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps smart account addresses to their validator configuration
    /// @dev Each smart account can have one owner address
    mapping(address => ValidatorStorage) public validatorStorage;

    /*//////////////////////////////////////////////////////////////
                        PUBLIC/EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the validator when installed in a smart account
    /// @dev Extracts the owner address from the installation data
    /// @param data The installation data containing the owner address
    /// @custom:events Emits ECDSA_ValidatorEnabled when successfully installed
    /// @custom:errors ECDSA_AlreadyInitialized if already initialized for the smart account
    /// @custom:errors ECDSA_InvalidOwnerData if the data format is invalid
    /// @custom:errors ECDSA_InvalidOwner if the owner address is zero
    function onInstall(bytes calldata data) external override {
        if (validatorStorage[msg.sender].owner != address(0)) {
            revert ECDSA_AlreadyInitialized(msg.sender);
        }
        address owner;
        // Standard case: data is exactly 32 bytes (abi.encode(address))
        if (data.length == 32) {
            // Extract the address from the last 20 bytes of the 32-byte value
            owner = address(bytes20(data[12:32]));
        }
        // Bootstrap case
        else if (data.length > 32) {
            // Try to extract from standard position in abi.encode(address)
            if (data.length >= 32) {
                owner = address(bytes20(data[12:32]));
            }
            // If that doesn't work, try bootstrap offset
            if (owner == address(0) && data.length >= 100) {
                owner = address(bytes20(data[80:100]));
            }
        } else {
            revert ECDSA_InvalidOwnerData();
        }
        if (owner == address(0)) revert ECDSA_InvalidOwner(msg.sender, owner);
        validatorStorage[msg.sender].owner = owner;
        emit ECDSA_ValidatorEnabled(msg.sender, owner);
    }

    /// @notice Cleans up validator data when uninstalled from a smart account
    /// @dev Removes the validator configuration for the calling smart account
    /// @param data Unused parameter (required by interface)
    /// @custom:events Emits ECDSA_ValidatorDisabled when successfully uninstalled
    /// @custom:errors ECDSA_NotInitialized if not initialized for the smart account
    function onUninstall(bytes calldata data) external override {
        if (validatorStorage[msg.sender].owner == address(0)) revert ECDSA_NotInitialized(msg.sender);
        delete validatorStorage[msg.sender];
        emit ECDSA_ValidatorDisabled(msg.sender);
    }

    /// @notice Checks if the validator is initialized for a specific smart account
    /// @param smartAccount The address of the smart account to check
    /// @return bool True if the validator is initialized, false otherwise
    function isInitialized(address smartAccount) external view override returns (bool) {
        return validatorStorage[smartAccount].owner != address(0);
    }

    /// @notice Checks if this module supports the specified module type
    /// @dev Implements the ERC7579 module type identification interface
    /// @param typeID The module type identifier to check
    /// @return bool True if this module is a validator module
    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == MODULE_TYPE_VALIDATOR;
    }

    /// @notice Checks if an address is the owner of a smart account
    /// @param smartAccount The address of the smart account to check
    /// @param owner The address to check ownership for
    /// @return bool True if the address is the owner, false otherwise
    function isOwner(address smartAccount, address owner) external view returns (bool) {
        return _isOwner(smartAccount, owner);
    }

    /// @notice Changes the owner of a smart account
    /// @dev Can be called by the current owner or the smart account itself
    /// @param _scw The address of the smart account
    /// @param _newOwner The address of the new owner
    /// @custom:events Emits ECDSA_OwnerChanged when the owner is successfully changed
    /// @custom:errors ECDSA_NotOwner if caller is not authorized
    /// @custom:errors ECDSA_InvalidOwner if the new owner address is zero
    function changeOwner(address _scw, address _newOwner) external {
        if (msg.sender != _scw && !_isOwner(_scw, msg.sender)) revert ECDSA_NotOwner(msg.sender);
        if (_newOwner == address(0)) revert ECDSA_InvalidOwner(_scw, _newOwner);
        validatorStorage[_scw].owner = _newOwner;
        emit ECDSA_OwnerChanged(_scw, _newOwner);
    }

    /// @notice Validates a user operation by verifying the signature
    /// @dev Supports both standard ECDSA signatures and EIP-191 personal signatures
    /// @param userOp The user operation to validate
    /// @param userOpHash The hash of the user operation for signature verification
    /// @return uint256 SIG_VALIDATION_SUCCESS if valid, SIG_VALIDATION_FAILED otherwise
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

    /// @notice ERC-1271 signature validation implementation
    /// @dev Supports both standard ECDSA signatures and EIP-191 personal signatures
    /// @param hash The hash of the data that was signed
    /// @param signature The signature to validate
    /// @return bytes4 ERC1271_MAGIC_VALUE if valid, ERC1271_INVALID otherwise
    function isValidSignatureWithSender(address, bytes32 hash, bytes calldata signature)
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
        return ERC1271_INVALID;
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL/PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if an address is the owner of a smart account
    /// @param _scw The address of the smart account to check
    /// @param _owner The address to check ownership for
    /// @return bool True if the address is the owner and the validator is enabled
    function _isOwner(address _scw, address _owner) internal view returns (bool) {
        return validatorStorage[_scw].owner == _owner;
    }
}
