// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IAccountStorage} from "../interfaces/core/IAccountStorage.sol";
import {ETHERSPOT_STORAGE_SLOT} from "../types/Constants.sol";

/// @title AccountStorage
/// @author @cryptonoyaiba | Etherspot
/// @notice Implements ERC-7201 namespaced storage pattern for Etherspot Modular Smart Accounts
/// @dev Provides isolated storage spaces to prevent storage collisions between different components
contract AccountStorage is IAccountStorage {
    /*//////////////////////////////////////////////////////////////
                           INTERNAL/PRIVATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the storage pointer for the account's module data
    /// @dev Uses assembly to access the specific storage slot defined by ERC-7201
    /// @return $ A reference to the AccountStorage struct at the namespaced location
    function _getAccountStorage() internal pure returns (AccountStorage storage $) {
        assembly {
            $.slot := ETHERSPOT_STORAGE_SLOT
        }
    }

    /// @notice Checks if the storage has been initialized
    /// @dev This can be used to prevent re-initialization of the account
    /// @return True if the storage has been initialized
    function isStorageInitialized() internal view returns (bool) {
        return _getAccountStorage().initialized;
    }

    /// @notice Marks the storage as initialized
    /// @dev Should be called during account initialization
    function _markStorageInitialized() internal {
        _getAccountStorage().initialized = true;
    }
}
