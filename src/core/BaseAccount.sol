// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";

/// @title BaseAccount
/// @author @cryptonoyaiba | Etherspot
/// @notice Base contract for ERC-4337 compatible smart contract wallets
/// @dev Provides basic functionality for interacting with the EntryPoint contract
contract BaseAccount {
    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The EntryPoint contract reference
    /// @dev This is immutable to save gas and prevent changes to the EntryPoint
    IEntryPoint internal immutable ENTRYPOINT;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a function is called by an unauthorized address
    error InvalidCaller();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Ensures the function can only be called by the EntryPoint
    /// @dev Reverts with InvalidCaller if called by any other address
    modifier onlyEntryPoint() virtual {
        if (msg.sender != address(ENTRYPOINT)) {
            revert InvalidCaller();
        }
        _;
    }

    /// @notice Ensures the function can only be called by the EntryPoint or the account itself
    /// @dev Reverts with InvalidCaller if called by any other address
    /// @dev Used for functions that can be called either via UserOperation or directly by the account
    modifier onlyEntryPointOrSelf() virtual {
        if (!(msg.sender == address(ENTRYPOINT) || msg.sender == address(this))) {
            revert InvalidCaller();
        }
        _;
    }

    /// @notice Sends to the EntryPoint the missing funds for this transaction
    /// @dev Subclass MAY override this modifier for better funds management
    /// @dev (e.g. send to the EntryPoint more than the minimum required, so that in future transactions
    /// it will not be required to send again)
    ///
    /// @param _missingAccountFunds The minimum value this modifier should send the EntryPoint,
    /// which MAY be zero, in case there is enough deposit, or the userOp has a paymaster
    modifier payPrefund(uint256 _missingAccountFunds) virtual {
        _;
        /// @solidity memory-safe-assembly
        assembly {
            if _missingAccountFunds {
                // Ignore failure (it's EntryPoint's job to verify, not the account's)
                pop(call(gas(), caller(), _missingAccountFunds, codesize(), 0x00, codesize(), 0x00))
            }
        }
    }
}
