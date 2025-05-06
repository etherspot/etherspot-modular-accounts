// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "solady/src/auth/Ownable.sol";
import "ERC7579/test/dependencies/EntryPoint.sol";
import "ERC7579/test/Bootstrap.t.sol";
import {MockValidator} from "ERC7579/test/mocks/MockValidator.sol";
import {MockExecutor} from "ERC7579/test/mocks/MockExecutor.sol";
import {MockTarget} from "ERC7579/test/mocks/MockTarget.sol";
import {ModularEtherspotWalletFactory} from "../../src/wallet/ModularEtherspotWalletFactory.sol";
import {ModularEtherspotWallet} from "../../src/wallet/ModularEtherspotWallet.sol";

contract ModularEtherspotWalletFactoryTest is BootstrapUtil, Test {
    bytes32 immutable SALT = bytes32("TestSALT");
    // singletons
    ModularEtherspotWallet implementation;
    ModularEtherspotWalletFactory factory;
    IEntryPoint entrypoint = IEntryPoint(ENTRYPOINT_ADDR);
    MockValidator defaultValidator;
    MockExecutor defaultExecutor;
    MockTarget target;
    ModularEtherspotWallet account;

    address owner1;
    uint256 owner1Key;
    address invalid;
    uint256 invalidKey;

    event ModularAccountDeployed(address indexed account, address indexed owner);

    function setUp() public virtual {
        (owner1, owner1Key) = makeAddrAndKey("owner1");
        (invalid, invalidKey) = makeAddrAndKey("invalid");

        vm.startPrank(owner1);
        etchEntrypoint();
        implementation = new ModularEtherspotWallet();
        factory = new ModularEtherspotWalletFactory(address(implementation), owner1);
        vm.stopPrank();

        // setup module singletons
        defaultExecutor = new MockExecutor();
        defaultValidator = new MockValidator();
        target = new MockTarget();
    }

    function test_setUpState() public {
        assertEq(address(implementation), factory.implementation());
    }

    function testFuzz_createAccount(address _eoa) public {
        // setup account init config
        BootstrapConfig[] memory validators = makeBootstrapConfig(address(defaultValidator), "");
        BootstrapConfig[] memory executors = makeBootstrapConfig(address(defaultExecutor), "");
        BootstrapConfig memory hook = _makeBootstrapConfig(address(0), "");
        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(address(0), "");

        bytes memory initCode = abi.encode(
            _eoa,
            address(bootstrapSingleton),
            abi.encodeCall(Bootstrap.initMSA, (validators, executors, hook, fallbacks))
        );

        vm.startPrank(_eoa);
        // create account
        account = ModularEtherspotWallet(payable(factory.createAccount({salt: SALT, initCode: initCode})));
        address expectedAddress = factory.getAddress({salt: SALT, initcode: initCode});
        assertEq(
            address(account), expectedAddress, "Computed wallet address should always equal wallet address created"
        );
        vm.stopPrank();
    }

    function test_createAccount_returnsAddressIfAlreadyCreated() public {
        // setup account init config
        BootstrapConfig[] memory validators = makeBootstrapConfig(address(defaultValidator), "");
        BootstrapConfig[] memory executors = makeBootstrapConfig(address(defaultExecutor), "");
        BootstrapConfig memory hook = _makeBootstrapConfig(address(0), "");
        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(address(0), "");

        bytes memory initCode = abi.encode(
            owner1,
            address(bootstrapSingleton),
            abi.encodeCall(Bootstrap.initMSA, (validators, executors, hook, fallbacks))
        );

        vm.startPrank(owner1);
        // create account
        account = ModularEtherspotWallet(payable(factory.createAccount({salt: SALT, initCode: initCode})));
        // re run to return created address
        ModularEtherspotWallet accountDuplicate =
            ModularEtherspotWallet(payable(factory.createAccount({salt: SALT, initCode: initCode})));

        assertEq(address(account), address(accountDuplicate));
        vm.stopPrank();
    }

    function test_ensureTwoAddressesNotSame() public {
        ModularEtherspotWallet account2;

        address owner2;
        uint256 owner2Key;
        (owner2, owner2Key) = makeAddrAndKey("owner2");

        BootstrapConfig[] memory validators = makeBootstrapConfig(address(defaultValidator), "");
        BootstrapConfig[] memory executors = makeBootstrapConfig(address(defaultExecutor), "");
        BootstrapConfig memory hook = _makeBootstrapConfig(address(0), "");
        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(address(0), "");

        bytes memory initCode = abi.encode(
            owner1,
            address(bootstrapSingleton),
            abi.encodeCall(Bootstrap.initMSA, (validators, executors, hook, fallbacks))
        );

        vm.startPrank(owner1);
        // create account
        account = ModularEtherspotWallet(payable(factory.createAccount({salt: SALT, initCode: initCode})));
        vm.stopPrank();
        vm.startPrank(owner2);

        initCode = abi.encode(
            owner2,
            address(bootstrapSingleton),
            abi.encodeCall(Bootstrap.initMSA, (validators, executors, hook, fallbacks))
        );

        // create 2nd account
        account2 =
            ModularEtherspotWallet(payable(factory.createAccount({salt: bytes32("TestSALT1"), initCode: initCode})));
        vm.stopPrank();
        assertFalse(address(account) == address(account2));
    }

    function test_emitEvent_createAccount() public {
        // setup account init config
        BootstrapConfig[] memory validators = makeBootstrapConfig(address(defaultValidator), "");
        BootstrapConfig[] memory executors = makeBootstrapConfig(address(defaultExecutor), "");
        BootstrapConfig memory hook = _makeBootstrapConfig(address(0), "");
        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(address(0), "");

        bytes memory initCode = abi.encode(
            owner1,
            address(bootstrapSingleton),
            abi.encodeCall(Bootstrap.initMSA, (validators, executors, hook, fallbacks))
        );

        vm.startPrank(owner1);
        address expectedAddress = factory.getAddress({salt: SALT, initcode: initCode});

        // emit event
        vm.expectEmit(true, true, true, true);
        emit ModularAccountDeployed(expectedAddress, owner1);
        // create account
        account = ModularEtherspotWallet(payable(factory.createAccount({salt: SALT, initCode: initCode})));
        assertEq(
            address(account), expectedAddress, "Computed wallet address should always equal wallet address created"
        );
        // should not emit event if address already exists
        // checked using -vvvv stack trace
        account = ModularEtherspotWallet(payable(factory.createAccount({salt: SALT, initCode: initCode})));

        vm.stopPrank();
    }

    function test_setImplementation() public {
        assertEq(address(implementation), factory.implementation());
        vm.startPrank(owner1);
        factory.setImplementation(address(0xdeadbeef));
        assertEq(address(0xdeadbeef), factory.implementation());
    }

    function test_setImplementation_RevertWhen_NotOwner() public {
        assertEq(address(implementation), factory.implementation());
        vm.startPrank(invalid);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        factory.setImplementation(address(0xdeadbeef));
    }
}
