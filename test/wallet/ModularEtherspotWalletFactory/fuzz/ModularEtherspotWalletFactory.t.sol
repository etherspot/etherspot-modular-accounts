// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "ERC7579/test/dependencies/EntryPoint.sol";
import "ERC7579/test/Bootstrap.t.sol";
import {MockValidator} from "ERC7579/test/mocks/MockValidator.sol";
import {MockExecutor} from "ERC7579/test/mocks/MockExecutor.sol";
import {MockTarget} from "ERC7579/test/mocks/MockTarget.sol";
import {ModularEtherspotWalletFactory} from "../../../../src/wallet/ModularEtherspotWalletFactory.sol";
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
        BootstrapConfig[] memory validators = makeBootstrapConfig(
            address(mockVal),
            hex""
        );
        BootstrapConfig[] memory executors = makeBootstrapConfig(
            address(mockExec),
            hex""
        );
        BootstrapConfig memory hook = _makeBootstrapConfig(address(0), hex"");
        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(
            address(0),
            hex""
        );
        bytes memory initCode = abi.encode(
            _eoa.pub,
            address(bootstrapSingleton),
            abi.encodeCall(
                Bootstrap.initMSA,
                (validators, executors, hook, fallbacks)
            )
        );
        vm.startPrank(_eoa.pub);
        // create account
        scw = ModularEtherspotWallet(
            payable(
                factory.createAccount({salt: TEST_SALT, initCode: initCode})
            )
        );
        address expectedAddress = factory.getAddress({
            salt: TEST_SALT,
            initcode: initCode
        });
        assertEq(
            address(scw),
            expectedAddress,
            "Computed wallet address should always equal wallet address created"
        );
        vm.stopPrank();
    }
}
