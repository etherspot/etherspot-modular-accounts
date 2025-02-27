// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "ERC7579/test/dependencies/EntryPoint.sol";
import "ERC7579/test/Bootstrap.t.sol";
import {ModularEtherspotWalletFactory} from "../../../../src/wallet/ModularEtherspotWalletFactory.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {ModularTestBase} from "../../../ModularTestBase.sol";

contract ModularEtherspotWalletFactory_Concrete_Test is ModularTestBase {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ModularAccountDeployed(
        address indexed account,
        address indexed owner
    );

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testInit();
    }

    function test_setUpState() public {
        assertEq(address(impl), factory.implementation());
    }

    function test_createAccount_ReturnsAddressIfAlreadyCreated() public {
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
            eoa.pub,
            address(bootstrapSingleton),
            abi.encodeCall(
                Bootstrap.initMSA,
                (validators, executors, hook, fallbacks)
            )
        );
        vm.startPrank(eoa.pub);
        // create account
        scw = ModularEtherspotWallet(
            payable(
                factory.createAccount({salt: TEST_SALT, initCode: initCode})
            )
        );
        // re run to return created address
        ModularEtherspotWallet dupe = ModularEtherspotWallet(
            payable(
                factory.createAccount({salt: TEST_SALT, initCode: initCode})
            )
        );
        assertEq(address(scw), address(dupe));
        vm.stopPrank();
    }

    function test_createAccount_EnsureTwoAddressesNotSame() public {
        ModularEtherspotWallet anotherSCW;
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
            eoa.pub,
            address(bootstrapSingleton),
            abi.encodeCall(
                Bootstrap.initMSA,
                (validators, executors, hook, fallbacks)
            )
        );
        vm.startPrank(eoa.pub);
        // create account
        scw = ModularEtherspotWallet(
            payable(
                factory.createAccount({salt: TEST_SALT, initCode: initCode})
            )
        );
        vm.stopPrank();
        vm.startPrank(alice.pub);
        initCode = abi.encode(
            alice.pub,
            address(bootstrapSingleton),
            abi.encodeCall(
                Bootstrap.initMSA,
                (validators, executors, hook, fallbacks)
            )
        );
        // create 2nd account
        anotherSCW = ModularEtherspotWallet(
            payable(
                factory.createAccount({
                    salt: bytes32("random.salt"),
                    initCode: initCode
                })
            )
        );
        vm.stopPrank();
        assertFalse(address(scw) == address(anotherSCW));
    }

    function test_createAccount_EmitsEventOnlyOnNewCreation() public {
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
            eoa.pub,
            address(bootstrapSingleton),
            abi.encodeCall(
                Bootstrap.initMSA,
                (validators, executors, hook, fallbacks)
            )
        );
        vm.startPrank(eoa.pub);
        address expectedAddr = factory.getAddress({
            salt: TEST_SALT,
            initcode: initCode
        });
        // Should emit event as newly created scw
        vm.expectEmit(true, true, true, true);
        emit ModularAccountDeployed(expectedAddr, eoa.pub);
        // create account
        scw = ModularEtherspotWallet(
            payable(
                factory.createAccount({salt: TEST_SALT, initCode: initCode})
            )
        );
        assertEq(
            address(scw),
            expectedAddr,
            "Computed wallet address should always equal wallet address created"
        );
        // Should not emit event if address already exists
        // - Checked using -vvvv stack trace
        scw = ModularEtherspotWallet(
            payable(
                factory.createAccount({salt: TEST_SALT, initCode: initCode})
            )
        );
        vm.stopPrank();
    }
}
