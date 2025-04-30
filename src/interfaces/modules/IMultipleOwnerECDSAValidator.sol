// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IValidator} from "../base/IValidator.sol";

/// @title IMultipleOwnerECDSAValidator
/// @author @cryptonoyaiba | Etherspot
/// @notice Interface for a validator module that supports multiple owners for a smart account
/// @dev Defines functions for managing multiple owners and signature validation
interface IMultipleOwnerECDSAValidator is IValidator {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a non-owner tries to perform an owner-only action
    error MOECDSA_NotOwner(address caller);

    /// @notice Thrown when trying to initialize an already initialized validator
    error MOECDSA_AlreadyInitialized(address scw);

    /// @notice Thrown when trying to use an uninitialized validator
    error MOECDSA_NotInitialized(address scw);

    /// @notice Thrown when the provided owner data is invalid
    error MOECDSA_InvalidOwnerData();

    /// @notice Thrown when trying to add an invalid owner
    error MOECDSA_AddingInvalidOwner(address scw, address owner);

    /// @notice Thrown when trying to remove an invalid owner
    error MOECDSA_RemovingInvalidOwner(address scw, address owner);

    /// @notice Thrown when trying to remove the last owner
    error MOECDSA_CannotRemoveLastOwner(address scw);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the validator is enabled for a smart account
    event MOECDSA_ValidatorEnabled(address indexed scw);

    /// @notice Emitted when the validator is disabled for a smart account
    event MOECDSA_ValidatorDisabled(address indexed scw);

    /// @notice Emitted when an owner is added to a smart account
    event MOECDSA_ValidatorOwnerAdded(address indexed scw, address indexed owner);

    /// @notice Emitted when an owner is removed from a smart account
    event MOECDSA_ValidatorOwnerRemoved(address indexed scw, address indexed owner);

    /*//////////////////////////////////////////////////////////////
                        PUBLIC/EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if an address is an owner of the smart account
    /// @param smartAccount The address of the smart account
    /// @param owner The address to check
    /// @return bool True if the address is an owner, false otherwise
    function isOwner(address smartAccount, address owner) external view returns (bool);

    /// @notice Adds a new owner to the smart account
    /// @dev Can only be called by the wallet itself or an existing owner
    /// @param _scw The address of the smart account
    /// @param _newOwner The address of the new owner to add
    function addOwner(address _scw, address _newOwner) external;

    /// @notice Removes an owner from the smart account
    /// @dev Can only be called by the wallet itself or an existing owner
    /// @param _scw The address of the smart account
    /// @param _owner The address of the owner to remove
    function removeOwner(address _scw, address _owner) external;

    /// @notice ERC-1271 signature validation
    /// @dev Implements the ERC-1271 validation interface
    /// @param sender The address of the sender requesting validation (unused)
    /// @param hash The hash of the data that was signed
    /// @param signature The signature to validate
    /// @return bytes4 Magic value if signature is valid, error value otherwise
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4);
}
