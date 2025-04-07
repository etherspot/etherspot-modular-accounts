// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IERC7579Account} from "../base/IERC7579Account.sol";
import {IERC4337Account} from "../base/IERC4337Account.sol";
import {IERC7779} from "../ercs/IERC7779.sol";

/// @title IModularEtherspotWallet
/// @author @cryptonoyaiba | Etherspot
/// @notice Interface for Etherspot's modular smart contract wallet implementation
/// @dev Combines ERC-7579 (modular accounts), ERC-4337 (account abstraction), and ERC-7779 standards
interface IModularEtherspotWallet is IERC7579Account, IERC4337Account, IERC7779 {
    /// @notice Thrown when an unsupported module type is requested
    /// @param moduleTypeId The ID of the unsupported module type
    error UnsupportedModuleType(uint256 moduleTypeId);

    /// @notice Thrown when account initialization fails
    error AccountInitializationFailed();

    /// @notice Thrown when account installs/uninstalls module with mismatched input moduleTypeId
    /// @param moduleTypeId The ID of the mismatched module type
    error MismatchModuleTypeId(uint256 moduleTypeId);

    /// @notice Initializes the account
    /// @dev Function might be called directly, or by a Factory
    /// @param _data Encoded data that can be used during the initialization phase
    function initializeAccount(bytes calldata _data) external payable;
}
