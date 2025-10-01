// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IValidator} from "ERC7579/interfaces/IERC7579Module.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";

/// @title IResourceLockValidator
/// @notice Interface for the ResourceLockValidator module that enables secure session key management
///         through resource locking mechanisms and merkle proofs for batched authorizations
/// @dev This validator implements dual-mode signature verification supporting both direct ECDSA
///      signatures and merkle proof-based validations for efficient batch authorization
interface IResourceLockValidator is IValidator {
    ///////////////////////////////////////////////////////////////
    //                           EVENTS
    ///////////////////////////////////////////////////////////////

    /// @notice Emitted when the validator is enabled for a smart contract wallet
    /// @param scw The smart contract wallet address
    /// @param owner The owner address of the validator
    event RLV_ValidatorEnabled(address indexed scw, address indexed owner);

    /// @notice Emitted when the validator is disabled for a smart contract wallet
    /// @param scw The smart contract wallet address
    event RLV_ValidatorDisabled(address indexed scw);

    ///////////////////////////////////////////////////////////////
    //                         FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Gets the address of the credible account module
    /// @return The address of the credible account module
    function getCredibleAccountModule() external view returns (address);

    /// @notice Sets the credible account module address (only callable by owner)
    /// @param _credibleAccountModule The address of the credible account module
    function setCredibleAccountModule(address _credibleAccountModule) external;

    /// @notice Checks if a bid hash has been consumed for a specific wallet
    /// @param _wallet The wallet address to check
    /// @param _bidHash The bid hash to check
    /// @return True if the bid hash has been consumed, false otherwise
    function isConsumedBidHash(address _wallet, bytes32 _bidHash) external view returns (bool);

    /// @notice Checks if a session key is authorized for a specific smart contract wallet
    /// @param _scw The smart contract wallet address
    /// @param _sessionKey The session key address to check
    /// @return True if the session key is authorized, false otherwise
    function isSessionKeyAuthorized(address _scw, address _sessionKey) external view returns (bool);

    /// @notice Removes authorization for a specific session key
    /// @dev Only callable by the credible account module or owner
    /// @param _scw The smart contract wallet address
    /// @param _sessionKey The session key address to remove authorization for
    function removeSessionKeyAuthorization(address _scw, address _sessionKey) external;

    /// @notice Gets all authorized session keys for a specific smart contract wallet
    /// @param _scw The smart contract wallet address
    /// @return Array of authorized session key addresses
    function getAuthorizedSessionKeys(address _scw) external view returns (address[] memory);

    /// @notice Validates a user operation with resource lock constraints
    /// @param userOp The packed user operation to validate
    /// @param userOpHash The hash of the user operation
    /// @return Validation result (0 for success, 1 for signature failure, >1 for time-based validation)
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) external returns (uint256);

    /// @notice Validates a signature with sender context for ERC-1271 compatibility
    /// @param sender The sender address
    /// @param hash The hash to validate
    /// @param signature The signature data including merkle proofs
    /// @return Magic value for valid signature, invalid value otherwise
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4);

    /// @notice Checks if the module type matches the validator module type.
    /// @param moduleTypeId The module type ID to check.
    /// @return True if the module type matches the validator module type, false otherwise.
    function isModuleType(uint256 moduleTypeId) external pure returns (bool);

    /// @notice Function for module installation.
    /// @param data The data to pass during installation.
    function onInstall(bytes calldata data) external;

    /// @notice Function for module uninstallation.
    /// @param data The data to pass during uninstallation.
    function onUninstall(bytes calldata data) external;

    /// @notice Checks if the module is initialized for a smart account
    /// @param smartAccount The address of the smart account.
    /// @return True if the smart account is initialized, false otherwise.
    function isInitialized(address smartAccount) external view returns (bool);
}
