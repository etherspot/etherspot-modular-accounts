// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {ModularTestBase} from "../../../ModularTestBase.sol";
import "../../../../src/common/Constants.sol";

contract ModularEtherspotWalletTestUtils is ModularTestBase {
    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier validatorInstalled() {
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_VALIDATOR,
            address(moecdsav),
            ""
        );
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _addGuardians(ModularEtherspotWallet _scw) internal {
        _scw.addGuardian(guardian1.pub);
        _scw.addGuardian(guardian2.pub);
        _scw.addGuardian(guardian3.pub);
    }
}
