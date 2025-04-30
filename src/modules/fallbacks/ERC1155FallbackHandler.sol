// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IFallback} from "../../interfaces/base/IFallback.sol";
import {MODULE_TYPE_FALLBACK} from "../../types/Constants.sol";

/// @title ERC1155FallbackHandler
/// @author @cryptonoyaiba | Etherspot
/// @notice Fallback handler for ERC1155 token reception in modular smart contract wallets
/// @dev Implements the ERC1155 token receiver interface as a fallback module
contract ERC1155FallbackHandler is IFallback {
    /*//////////////////////////////////////////////////////////////
                               MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Tracks which accounts have initialized this module
    mapping(address => bool) private _initialized;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the fallback handler is installed for an account
    /// @param account The address of the account where the handler is installed
    event ERC1155FallbackHandlerInstalled(address account);

    /// @notice Emitted when the fallback handler is uninstalled from an account
    /// @param account The address of the account where the handler is uninstalled
    event ERC1155FallbackHandlerUninstalled(address account);

    /// @notice Emitted when a single ERC1155 token is received
    /// @param operator The address which initiated the transfer
    /// @param from The address which previously owned the token
    /// @param id The ID of the token being transferred
    /// @param value The amount of tokens being transferred
    /// @param data Additional data with no specified format
    event ERC1155Received(address operator, address from, uint256 id, uint256 value, bytes data);

    /// @notice Emitted when multiple ERC1155 tokens are received
    /// @param operator The address which initiated the transfer
    /// @param from The address which previously owned the tokens
    /// @param ids An array of token IDs being transferred
    /// @param values An array of amounts of tokens being transferred
    /// @param data Additional data with no specified format
    event ERC1155BatchReceived(address operator, address from, uint256[] ids, uint256[] values, bytes data);

    /*//////////////////////////////////////////////////////////////
                               EXTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Handle the receipt of a single ERC1155 token type
    /// @dev Emits an event and returns the function selector to confirm reception
    /// @param operator The address which initiated the transfer
    /// @param from The address which previously owned the token
    /// @param id The ID of the token being transferred
    /// @param value The amount of tokens being transferred
    /// @param data Additional data with no specified format
    /// @return bytes4 The function selector
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        returns (bytes4)
    {
        emit ERC1155Received(operator, from, id, value, data);
        return this.onERC1155Received.selector;
    }

    /// @notice Handle the receipt of multiple ERC1155 token types
    /// @dev Emits an event and returns the function selector to confirm reception
    /// @param operator The address which initiated the transfer
    /// @param from The address which previously owned the tokens
    /// @param ids An array of token IDs being transferred
    /// @param values An array of amounts of tokens being transferred
    /// @param data Additional data with no specified format
    /// @return bytes4 The function selector
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4) {
        emit ERC1155BatchReceived(operator, from, ids, values, data);
        return this.onERC1155BatchReceived.selector;
    }

    /// @notice Called when the module is installed
    /// @dev Sets the initialization flag and emits an event
    /// @param data Installation data (unused)
    function onInstall(bytes calldata data) external {
        emit ERC1155FallbackHandlerInstalled(msg.sender);
        _initialized[msg.sender] = true;
    }

    /// @notice Called when the module is uninstalled
    /// @dev Clears the initialization flag and emits an event
    /// @param data Uninstallation data (unused)
    function onUninstall(bytes calldata data) external {
        emit ERC1155FallbackHandlerUninstalled(msg.sender);
        _initialized[msg.sender] = false;
    }

    /// @notice Checks if this module is of the specified type
    /// @param moduleTypeId The module type ID to check against
    /// @return bool True if this module is of the specified type
    function isModuleType(uint256 moduleTypeId) external view returns (bool) {
        return moduleTypeId == MODULE_TYPE_FALLBACK;
    }

    /// @notice Checks if this module is initialized for a specific account
    /// @param smartAccount The account to check initialization status for
    /// @return bool True if the module is initialized for the account
    function isInitialized(address smartAccount) external view returns (bool) {
        return _initialized[msg.sender];
    }
}
