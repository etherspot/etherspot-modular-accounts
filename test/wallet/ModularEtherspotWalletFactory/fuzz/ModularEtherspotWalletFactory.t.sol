// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../../../../src/test/dependencies/EntryPoint.sol";
import "../../../../src/libraries/BootstrapLib.sol";
import {MockValidator} from "../../../../src/test/mocks/MockValidator.sol";
import {MockExecutor} from "../../../../src/test/mocks/MockExecutor.sol";
import {MockTarget} from "../../../../src/test/mocks/MockTarget.sol";
import {ModularEtherspotWalletFactory} from "../../../../src/factory/ModularEtherspotWalletFactory.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {ModularTestBase} from "../../../ModularTestBase.sol";

contract ModularEtherspotWalletFactory_Fuzz_Test is ModularTestBase {
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testInit();
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    function test_createAccount(User memory _eoa) public {
        // setup account init config
        BootstrapConfig[] memory validators = BootstrapLib._buildArrayConfig(address(MOCK_VALIDATOR), hex"");
        BootstrapConfig[] memory executors = BootstrapLib._buildArrayConfig(address(MOCK_EXECUTOR), hex"");
        BootstrapConfig memory hook = BootstrapLib._buildEmptySingleConfig();
        BootstrapConfig[] memory fallbacks = BootstrapLib._buildEmptyArrayConfig();
        bytes memory initCode = abi.encode(
            address(BOOTSTRAP),
            abi.encodeCall(BOOTSTRAP.initializeModularAccount, (validators, executors, hook, fallbacks))
        );
        vm.startPrank(_eoa.pub);
        // create account
        SCW = ModularEtherspotWallet(
            payable(FACTORY.createAccount({_owner: _eoa.pub, _salt: TEST_SALT, _initCode: initCode}))
        );
        address expectedAddress = FACTORY.getAddress({_salt: TEST_SALT, _initcode: initCode});
        assertEq(address(SCW), expectedAddress, "Computed wallet address should always equal wallet address created");
        vm.stopPrank();
    }
}
