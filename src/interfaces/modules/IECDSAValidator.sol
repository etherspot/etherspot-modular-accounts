// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IValidator} from "../base/IValidator.sol";

/// @title IECDSAValidator
/// @author @cryptonoyaiba | Etherspot
/// @notice Interface for ECDSA signature validation in ERC-7579 smart accounts
/// @dev Defines functions for owner management and signature validation
interface IECDSAValidator is IValidator {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an unauthorized address attempts to perform an owner-only action
    error ECDSA_NotOwner(address caller);

    /// @notice Thrown when trying to initialize an already initialized validator
    error ECDSA_AlreadyInitialized(address scw);

    /// @notice Thrown when trying to use an uninitialized validator
    error ECDSA_NotInitialized(address scw);

    /// @notice Thrown when the provided owner data is invalid
    error ECDSA_InvalidOwnerData();

    /// @notice Thrown when trying to set an invalid owner address (e.g., zero address)
    error ECDSA_InvalidOwner(address scw, address owner);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the validator is enabled for a smart account
    /// @param scw The smart account address
    /// @param owner The initial owner address
    event ECDSA_ValidatorEnabled(address indexed scw, address indexed owner);

    /// @notice Emitted when the validator is disabled for a smart account
    /// @param scw The smart account address
    event ECDSA_ValidatorDisabled(address indexed scw);

    /// @notice Emitted when the owner of a smart account is changed
    /// @param scw The smart account address
    /// @param newOwner The new owner address
    event ECDSA_OwnerChanged(address indexed scw, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                        PUBLIC/EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if an address is the owner of a smart account
    /// @param smartAccount The address of the smart account to check
    /// @param owner The address to check ownership for
    /// @return bool True if the address is the owner, false otherwise
    function isOwner(address smartAccount, address owner) external view returns (bool);

    /// @notice Changes the owner of a smart account
    /// @dev Can be called by the current owner or the smart account itself
    /// @param _scw The address of the smart account
    /// @param _newOwner The address of the new owner
    function changeOwner(address _scw, address _newOwner) external;

    /// @notice ERC-1271 signature validation implementation
    /// @dev Supports both standard ECDSA signatures and EIP-191 personal signatures
    /// @param sender The address of the sender (unused in this implementation)
    /// @param hash The hash of the data that was signed
    /// @param signature The signature to validate
    /// @return bytes4 ERC1271_MAGIC_VALUE if valid, ERC1271_INVALID otherwise
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4);
}
