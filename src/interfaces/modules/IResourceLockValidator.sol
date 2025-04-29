// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IValidator} from "../base/IValidator.sol";

/// @title IResourceLockValidator
/// @author @cryptonoyaiba | Etherspot
/// @notice Interface for a validator module that handles resource locking functionality
/// @dev Extends the standard IValidator interface with resource lock specific events
interface IResourceLockValidator is IValidator {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the resource lock validator is enabled for a smart contract wallet
    /// @param scw The address of the smart contract wallet
    /// @param owner The address of the wallet owner
    event RLV_ValidatorEnabled(address indexed scw, address indexed owner);

    /// @notice Emitted when the resource lock validator is disabled for a smart contract wallet
    /// @param scw The address of the smart contract wallet
    event RLV_ValidatorDisabled(address indexed scw);

    /// @notice Emitted when the resource lock validator is disabled for a smart contract wallet
    /// @param scw The address of the smart contract wallet
    /// @param newNonce The new nonce value
    event RLV_NonceUpdated(address indexed scw, uint256 newNonce);
}
