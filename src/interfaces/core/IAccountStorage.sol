// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SentinelListLib} from "../../libraries/SentinelList.sol";
import {IHook} from "../base/IHook.sol";
import {IPreValidationHookERC1271, IPreValidationHookERC4337} from "../base/IPreValidationHook.sol";
import {CallType} from "../../types/Types.sol";

/// @title IAccountStorage
/// @author @cryptonoyaiba | Etherspot
/// @notice Interface defining the storage structure for Etherspot Modular Smart Accounts
/// @dev Implements ERC-7201 namespaced storage pattern
interface IAccountStorage {
    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Structure for fallback handler configuration
    /// @param handler The address of the fallback handler contract
    /// @param calltype The type of call to execute (SINGLE or STATIC)
    /// @param allowedCallers An array of addresses allowed to call the fallback handler
    struct FallbackHandler {
        address handler;
        CallType calltype;
        address[] allowedCallers;
    }

    /// @notice Main storage structure for account modules and configuration
    /// @dev Uses SentinelList for efficient module management
    struct AccountStorage {
        /// Linked list of validator modules
        SentinelListLib.SentinelList validators;
        /// Linked list of executor modules
        SentinelListLib.SentinelList executors;
        /// Mapping of function selectors to fallback handlers
        mapping(bytes4 selector => FallbackHandler fallbackHandler) fallbacks;
        /// Single hook module (can be address(0) if not set)
        IHook hook;
        /// PreValidation hook for validateUserOp
        IPreValidationHookERC4337 preValidationHookERC4337;
        /// PreValidation hook for isValidSignature
        IPreValidationHookERC1271 preValidationHookERC1271;
        /// Flag to track if storage has been initialized
        bool initialized;
    }
}
