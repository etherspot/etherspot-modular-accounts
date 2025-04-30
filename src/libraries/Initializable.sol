// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {INIT_SLOT} from "../types/Constants.sol";

library Initializable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotInitializable();

    /*//////////////////////////////////////////////////////////////
                           INTERNAL/PRIVATE
    //////////////////////////////////////////////////////////////*/

    function _checkInitializable() internal view {
        bytes32 slot = INIT_SLOT;
        // Load the current value from the slot, revert if 0
        assembly {
            let isInitializable := tload(slot)
            if iszero(isInitializable) {
                mstore(0x0, 0xaed59595) // NotInitializable()
                revert(0x1c, 0x04)
            }
        }
    }

    function _setInitializable() internal {
        bytes32 slot = INIT_SLOT;
        assembly {
            tstore(slot, 0x01)
        }
    }
}
