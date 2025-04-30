// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../../../../src/test/dependencies/EntryPoint.sol";
import "../../../../src/libraries/BootstrapLib.sol";
import {ModularEtherspotWalletFactory} from "../../../../src/factory/ModularEtherspotWalletFactory.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {ModularTestBase} from "../../../ModularTestBase.sol";

contract ModularEtherspotWalletFactory_Concrete_Test is ModularTestBase {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ModularAccountDeployed(address indexed account, address indexed owner);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testInit();
    }

    function test_setUpState() public {
        assertEq(address(IMPLEMENTATION), FACTORY.implementation());
    }

    function test_createAccount_ReturnsAddressIfAlreadyCreated() public {
        // setup account init config
        BootstrapConfig[] memory validators = BootstrapLib._buildArrayConfig(address(MOCK_VALIDATOR), hex"");
        BootstrapConfig[] memory executors = BootstrapLib._buildArrayConfig(address(MOCK_EXECUTOR), hex"");
        BootstrapConfig memory hook = BootstrapLib._buildEmptySingleConfig();
        BootstrapConfig[] memory fallbacks = BootstrapLib._buildEmptyArrayConfig();
        bytes memory initCode = abi.encode(
            address(BOOTSTRAP),
            abi.encodeCall(BOOTSTRAP.initializeModularAccount, (validators, executors, hook, fallbacks))
        );
        vm.startPrank(eoa.pub);
        // create account
        SCW = ModularEtherspotWallet(
            payable(FACTORY.createAccount({_owner: eoa.pub, _salt: TEST_SALT, _initCode: initCode}))
        );
        // re run to return created address
        ModularEtherspotWallet dupe = ModularEtherspotWallet(
            payable(FACTORY.createAccount({_owner: eoa.pub, _salt: TEST_SALT, _initCode: initCode}))
        );
        assertEq(address(SCW), address(dupe));
        vm.stopPrank();
    }

    function test_createAccount_EnsureTwoAddressesNotSame() public {
        ModularEtherspotWallet anotherSCW;
        BootstrapConfig[] memory validators = BootstrapLib._buildArrayConfig(address(MOCK_VALIDATOR), hex"");
        BootstrapConfig[] memory executors = BootstrapLib._buildArrayConfig(address(MOCK_EXECUTOR), hex"");
        BootstrapConfig memory hook = BootstrapLib._buildEmptySingleConfig();
        BootstrapConfig[] memory fallbacks = BootstrapLib._buildEmptyArrayConfig();
        bytes memory initCode = abi.encode(
            address(BOOTSTRAP),
            abi.encodeCall(BOOTSTRAP.initializeModularAccount, (validators, executors, hook, fallbacks))
        );
        vm.startPrank(eoa.pub);
        // create account
        SCW = ModularEtherspotWallet(
            payable(FACTORY.createAccount({_owner: eoa.pub, _salt: TEST_SALT, _initCode: initCode}))
        );
        vm.stopPrank();
        vm.startPrank(alice.pub);
        initCode = abi.encode(
            address(BOOTSTRAP),
            abi.encodeCall(BOOTSTRAP.initializeModularAccount, (validators, executors, hook, fallbacks))
        );
        // create 2nd account
        anotherSCW = ModularEtherspotWallet(
            payable(FACTORY.createAccount({_owner: alice.pub, _salt: bytes32("random.salt"), _initCode: initCode}))
        );
        vm.stopPrank();
        assertFalse(address(SCW) == address(anotherSCW));
    }

    function test_createAccount_EmitsEventOnlyOnNewCreation() public {
        // setup account init config
        BootstrapConfig[] memory validators = BootstrapLib._buildArrayConfig(address(MOCK_VALIDATOR), hex"");
        BootstrapConfig[] memory executors = BootstrapLib._buildArrayConfig(address(MOCK_EXECUTOR), hex"");
        BootstrapConfig memory hook = BootstrapLib._buildEmptySingleConfig();
        BootstrapConfig[] memory fallbacks = BootstrapLib._buildEmptyArrayConfig();
        bytes memory initCode = abi.encode(
            address(BOOTSTRAP),
            abi.encodeCall(BOOTSTRAP.initializeModularAccount, (validators, executors, hook, fallbacks))
        );
        vm.startPrank(eoa.pub);
        address expectedAddr = FACTORY.getAddress({_salt: TEST_SALT, _initcode: initCode});
        // Should emit event as newly created SCW
        vm.expectEmit(true, true, true, true);
        emit ModularAccountDeployed(expectedAddr, eoa.pub);
        // create account
        SCW = ModularEtherspotWallet(
            payable(FACTORY.createAccount({_owner: eoa.pub, _salt: TEST_SALT, _initCode: initCode}))
        );
        assertEq(address(SCW), expectedAddr, "Computed wallet address should always equal wallet address created");
        // Should not emit event if address already exists
        // - Checked using -vvvv stack trace
        SCW = ModularEtherspotWallet(
            payable(FACTORY.createAccount({_owner: eoa.pub, _salt: TEST_SALT, _initCode: initCode}))
        );
        vm.stopPrank();
    }
}
