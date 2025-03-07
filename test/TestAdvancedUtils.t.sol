// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {LibSort} from "solady/src/utils/LibSort.sol";
import {Solarray} from "solarray/Solarray.sol";
import {IERC20 as IERC20Interface} from "forge-std/interfaces/IERC20.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {Bootstrap} from "ERC7579/utils/Bootstrap.sol";
import {BootstrapUtil, BootstrapConfig} from "ERC7579/test/Bootstrap.t.sol";
import {MockValidator} from "ERC7579/test/mocks/MockValidator.sol";
import {MockExecutor} from "ERC7579/test/mocks/MockExecutor.sol";
import {MockTarget} from "ERC7579/test/mocks/MockTarget.sol";
import {MockFallback} from "ERC7579/test/mocks/MockFallbackHandler.sol";
import {ExecutionLib} from "ERC7579/libs/ExecutionLib.sol";
import {ModeLib, ModeCode, CallType, ExecType, ModeSelector, ModePayload, CALLTYPE_STATIC, EXECTYPE_DEFAULT, MODE_DEFAULT} from "ERC7579/libs/ModeLib.sol";
import "ERC7579/test/dependencies/EntryPoint.sol";
import {ModularEtherspotWallet} from "../src/wallet/ModularEtherspotWallet.sol";
import {ModularEtherspotWalletFactory} from "../src/wallet/ModularEtherspotWalletFactory.sol";
import {MultipleOwnerECDSAValidator} from "../src/modules/validators/MultipleOwnerECDSAValidator.sol";
import {ERC20SessionKeyValidator} from "../src/modules/validators/ERC20SessionKeyValidator.sol";
import {SessionKeyValidator} from "../src/modules/validators/SessionKeyValidator.sol";
import {ProofVerifier} from "../src/utils/ProofVerifier.sol";
import {CredibleAccountModule} from "../src/modules/validators/CredibleAccountModule.sol";
import {HookMultiPlexer, SigHookInit} from "../src/modules/hooks/HookMultiPlexer.sol";
import {MockHook} from "../src/test/mocks/MockHook.sol";
import {MockRegistry} from "../src/test/mocks/MockRegistry.sol";
import {TestExecutor} from "../src/test/TestExecutor.sol";

contract TestAdvancedUtils is BootstrapUtil, Test {
    using LibSort for address[];

    // singletons
    ModularEtherspotWallet implementation;
    ModularEtherspotWalletFactory factory;
    IEntryPoint entrypoint = IEntryPoint(ENTRYPOINT_ADDR);
    bytes public constant DUMMY_PROOF = hex"1234567890abcdef";

    MockValidator defaultValidator;
    MockExecutor defaultExecutor;
    MockFallback fallbackHandler;
    MultipleOwnerECDSAValidator ecdsaValidator;
    ERC20SessionKeyValidator erc20SessionKeyValidator;
    SessionKeyValidator sessionKeyValidator;
    CredibleAccountModule credibleAccountModule;
    ProofVerifier proofVerifier;
    HookMultiPlexer hookMultiPlexer;
    ModularEtherspotWallet mewAccount;
    MockTarget target;
    MockRegistry registry;
    TestExecutor executor;

    MockHook internal subHook1;
    MockHook internal subHook2;
    MockHook internal subHook3;
    MockHook internal subHook4;
    MockHook internal subHook5;
    MockHook internal subHook6;
    MockHook internal subHook7;
    MockHook internal subHook8;

    address owner1;
    uint256 owner1Key;

    uint256 mainnetFork;
    uint256 constant EXEC_SPEND_CAP = 10 ether;

    function setUp() public virtual {
        // Set up accounts
        (owner1, owner1Key) = makeAddrAndKey("owner1");
        // Set up EntryPoint
        etchEntrypoint();
        vm.startPrank(owner1);
        // Set up MSA and Factory
        implementation = new ModularEtherspotWallet();
        factory = new ModularEtherspotWalletFactory(
            address(implementation),
            owner1
        );
        // Set up default modules
        defaultExecutor = new MockExecutor();
        defaultValidator = new MockValidator();
        fallbackHandler = new MockFallback();
        registry = new MockRegistry();
        // Setup multiple mock hooks
        subHook1 = new MockHook();
        subHook2 = new MockHook();
        subHook3 = new MockHook();
        subHook4 = new MockHook();
        subHook5 = new MockHook();
        subHook6 = new MockHook();
        subHook7 = new MockHook();
        subHook8 = new MockHook();
        // MultipleOwnerECDSAValidator for MEW
        ecdsaValidator = new MultipleOwnerECDSAValidator();
        // ERC20SessionKeyValidtor for MEW
        erc20SessionKeyValidator = new ERC20SessionKeyValidator();
        // SessionKeyValidator for MEW
        sessionKeyValidator = new SessionKeyValidator();
        // Proof Verifier for CredibleAccountValidator
        proofVerifier = new ProofVerifier();
        // HookMultiplexer for MEW
        hookMultiPlexer = new HookMultiPlexer(registry);
        // CredibleAccountModule for MEW
        credibleAccountModule = new CredibleAccountModule(
            address(proofVerifier),
            address(hookMultiPlexer)
        );
        // Set up Target for testing
        target = new MockTarget();
        vm.stopPrank();
    }

    function getAccountAndInitCode()
        internal
        returns (address account, bytes memory initCode)
    {
        // Create config for initial modules
        BootstrapConfig[] memory validators = makeBootstrapConfig(
            address(defaultValidator),
            ""
        );
        BootstrapConfig[] memory executors = makeBootstrapConfig(
            address(defaultExecutor),
            ""
        );
        BootstrapConfig memory hook = _makeBootstrapConfig(address(0), "");
        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(
            address(0),
            ""
        );

        // Create initcode and salt to be sent to Factory
        bytes memory _initCode = bootstrapSingleton._getInitMSACalldata(
            validators,
            executors,
            hook,
            fallbacks
        );

        bytes32 salt = keccak256("1");
        // Get address of new account
        account = factory.getAddress(salt, _initCode);

        // Pack the initcode to include in the userOp
        initCode = abi.encodePacked(
            address(factory),
            abi.encodeWithSelector(
                factory.createAccount.selector,
                salt,
                _initCode
            )
        );

        // Deal 100 ether to the account
        vm.deal(account, 100 ether);
    }

    function getNonce(
        address account,
        address validator
    ) internal view returns (uint256 nonce) {
        uint192 key = uint192(bytes24(bytes20(validator)));
        nonce = entrypoint.getNonce(address(account), key);
    }

    function getDefaultUserOp()
        internal
        pure
        returns (PackedUserOperation memory userOp)
    {
        userOp = PackedUserOperation({
            sender: address(0),
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(
                abi.encodePacked(uint128(2e6), uint128(2e6))
            ),
            preVerificationGas: 2e6,
            gasFees: bytes32(abi.encodePacked(uint128(2e6), uint128(2e6))),
            paymasterAndData: bytes(""),
            signature: abi.encodePacked(hex"41414141")
        });
    }

    function getMEWAndInitCode()
        internal
        returns (address account, bytes memory initCode)
    {
        // Create config for initial modules
        BootstrapConfig[] memory validators = makeBootstrapConfig(
            address(ecdsaValidator),
            abi.encodePacked(owner1)
        );
        BootstrapConfig[] memory executors = makeBootstrapConfig(
            address(defaultExecutor),
            ""
        );
        BootstrapConfig memory hook = _makeBootstrapConfig(address(0), "");
        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(
            address(0),
            ""
        );

        // Create owner
        (owner1, owner1Key) = makeAddrAndKey("owner1");

        // Create initcode and salt to be sent to Factory
        bytes memory _initCode = abi.encode(
            owner1,
            address(bootstrapSingleton),
            abi.encodeCall(
                bootstrapSingleton.initMSA,
                (validators, executors, hook, fallbacks)
            )
        );
        bytes32 salt = keccak256("1");

        // Get address of new account
        account = factory.getAddress(salt, _initCode);

        // Pack the initcode to include in the userOp
        initCode = abi.encodePacked(
            address(factory),
            abi.encodeWithSelector(
                factory.createAccount.selector,
                salt,
                _initCode
            )
        );

        // Deal 100 ether to the account
        vm.deal(account, 100 ether);
    }

    function setupMEW() internal returns (ModularEtherspotWallet mew) {
        // Create config for initial modules
        BootstrapConfig[] memory validators = makeBootstrapConfig(
            address(ecdsaValidator),
            abi.encodePacked(owner1)
        );
        BootstrapConfig[] memory executors = makeBootstrapConfig(
            address(defaultExecutor),
            ""
        );
        BootstrapConfig memory hook = _makeBootstrapConfig(address(0), "");
        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(
            address(0),
            ""
        );

        // Create owner
        (owner1, owner1Key) = makeAddrAndKey("owner1");

        // Create initcode and salt to be sent to Factory
        bytes memory _initCode = abi.encode(
            owner1,
            address(bootstrapSingleton),
            abi.encodeCall(
                bootstrapSingleton.initMSA,
                (validators, executors, hook, fallbacks)
            )
        );
        bytes32 salt = keccak256("1");

        vm.startPrank(owner1);
        // create account
        mewAccount = ModularEtherspotWallet(
            payable(factory.createAccount({salt: salt, initCode: _initCode}))
        );
        vm.deal(address(mewAccount), 100 ether);
        vm.stopPrank();
        return mewAccount;
    }

    function setupMEWWithERC20SessionKeys()
        internal
        returns (ModularEtherspotWallet mew)
    {
        // Create config for initial modules
        BootstrapConfig[] memory validators = new BootstrapConfig[](2);
        validators[0] = _makeBootstrapConfig(address(ecdsaValidator), "");
        validators[1] = _makeBootstrapConfig(
            address(erc20SessionKeyValidator),
            ""
        );
        BootstrapConfig[] memory executors = makeBootstrapConfig(
            address(defaultExecutor),
            ""
        );
        BootstrapConfig memory hook = _makeBootstrapConfig(address(0), "");
        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(
            address(0),
            ""
        );

        // Create owner
        (owner1, owner1Key) = makeAddrAndKey("owner1");
        vm.deal(owner1, 100 ether);

        // Create initcode and salt to be sent to Factory
        bytes memory _initCode = abi.encode(
            owner1,
            address(bootstrapSingleton),
            abi.encodeCall(
                bootstrapSingleton.initMSA,
                (validators, executors, hook, fallbacks)
            )
        );
        bytes32 salt = keccak256("1");

        vm.startPrank(owner1);
        // create account
        mewAccount = ModularEtherspotWallet(
            payable(factory.createAccount({salt: salt, initCode: _initCode}))
        );
        vm.deal(address(mewAccount), 100 ether);
        vm.stopPrank();
        return mewAccount;
    }

    function setupMEWWithSessionKeys()
        internal
        returns (ModularEtherspotWallet mew)
    {
        // Create config for initial modules
        BootstrapConfig[] memory validators = new BootstrapConfig[](2);
        validators[0] = _makeBootstrapConfig(address(ecdsaValidator), "");
        validators[1] = _makeBootstrapConfig(address(sessionKeyValidator), "");
        BootstrapConfig[] memory executors = makeBootstrapConfig(
            address(defaultExecutor),
            ""
        );
        BootstrapConfig memory hook = _makeBootstrapConfig(address(0), "");
        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(
            address(0),
            ""
        );

        // Create owner
        (owner1, owner1Key) = makeAddrAndKey("owner1");
        vm.deal(owner1, 100 ether);

        // Create initcode and salt to be sent to Factory
        bytes memory _initCode = abi.encode(
            owner1,
            address(bootstrapSingleton),
            abi.encodeCall(
                bootstrapSingleton.initMSA,
                (validators, executors, hook, fallbacks)
            )
        );
        bytes32 salt = keccak256("1");

        vm.startPrank(owner1);
        // create account
        mewAccount = ModularEtherspotWallet(
            payable(factory.createAccount({salt: salt, initCode: _initCode}))
        );
        vm.deal(address(mewAccount), 100 ether);
        vm.stopPrank();
        return mewAccount;
    }

    function setupMainnetForkDeployementAndCreateAccount()
        public
        returns (ModularEtherspotWallet mew)
    {
        // // start fork
        // vm.selectFork(mainnetFork);
        // Set up MSA and Factory
        implementation = new ModularEtherspotWallet();
        factory = new ModularEtherspotWalletFactory(
            address(implementation),
            owner1
        );
        bootstrapSingleton = new Bootstrap();

        // Set up Modules
        executor = new TestExecutor();
        defaultValidator = new MockValidator();
        fallbackHandler = new MockFallback();

        // MultipleOwnerECDSAValidator for MEW
        ecdsaValidator = new MultipleOwnerECDSAValidator();

        // ERC20SessionKeyValidtor for MEW
        erc20SessionKeyValidator = new ERC20SessionKeyValidator();

        // SessionKeyValidator for MEW
        sessionKeyValidator = new SessionKeyValidator();
        console2.log(
            "address(sessionKeyValidator) - from test utils: ",
            address(sessionKeyValidator)
        );
        // Create config for initial modules
        BootstrapConfig[] memory validators = new BootstrapConfig[](2);
        validators[0] = _makeBootstrapConfig(address(ecdsaValidator), "");
        validators[1] = _makeBootstrapConfig(address(sessionKeyValidator), "");
        BootstrapConfig[] memory executors = makeBootstrapConfig(
            address(executor),
            ""
        );
        BootstrapConfig memory hook = _makeBootstrapConfig(address(0), "");
        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(
            address(0),
            ""
        );

        // Create owner
        (owner1, owner1Key) = makeAddrAndKey("owner1");
        vm.deal(owner1, 100 ether);

        // Create initcode and salt to be sent to Factory
        bytes memory _initCode = abi.encode(
            owner1,
            address(bootstrapSingleton),
            abi.encodeCall(
                bootstrapSingleton.initMSA,
                (validators, executors, hook, fallbacks)
            )
        );
        bytes32 salt = keccak256("1");

        vm.startPrank(owner1);
        // create account
        mewAccount = ModularEtherspotWallet(
            payable(factory.createAccount({salt: salt, initCode: _initCode}))
        );
        vm.deal(address(mewAccount), 100 ether);
        vm.stopPrank();
        return mewAccount;
    }

    function setupMEWWithHookMultiplexerAndCredibleAccountModule()
        public
        returns (ModularEtherspotWallet)
    {
        // Create config for initial modules
        BootstrapConfig[] memory validators = new BootstrapConfig[](1);
        validators[0] = _makeBootstrapConfig(address(ecdsaValidator), "");

        BootstrapConfig[] memory executors = makeBootstrapConfig(
            address(defaultExecutor),
            ""
        );

        bytes
            memory hookMultiplexerInitData = _getHookMultiPlexerInitDataWithCredibleAccountModule();

        BootstrapConfig memory hook = _makeBootstrapConfig(
            address(hookMultiPlexer),
            hookMultiplexerInitData
        );

        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(
            address(0),
            ""
        );

        // Create owner
        (owner1, owner1Key) = makeAddrAndKey("owner1");
        vm.deal(owner1, 100 ether);

        // Create initcode and salt to be sent to Factory
        bytes memory _initCode = abi.encode(
            owner1,
            address(bootstrapSingleton),
            abi.encodeCall(
                bootstrapSingleton.initMSA,
                (validators, executors, hook, fallbacks)
            )
        );
        bytes32 salt = keccak256("1");

        vm.startPrank(owner1);
        // create account
        mewAccount = ModularEtherspotWallet(
            payable(factory.createAccount({salt: salt, initCode: _initCode}))
        );
        vm.deal(address(mewAccount), 100 ether);
        vm.stopPrank();
        return mewAccount;
    }

    function setupMEWWithEmptyHookMultiplexer()
        public
        returns (ModularEtherspotWallet)
    {
        // Create config for initial modules
        BootstrapConfig[] memory validators = new BootstrapConfig[](1);
        validators[0] = _makeBootstrapConfig(address(ecdsaValidator), "");

        BootstrapConfig[] memory executors = makeBootstrapConfig(
            address(defaultExecutor),
            ""
        );

        bytes
            memory hookMultiplexerInitData = _getHookMultiPlexerInitDataWithNoSubHooks();

        BootstrapConfig memory hook = _makeBootstrapConfig(
            address(hookMultiPlexer),
            hookMultiplexerInitData
        );

        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(
            address(0),
            ""
        );

        // Create owner
        (owner1, owner1Key) = makeAddrAndKey("owner1");
        vm.deal(owner1, 100 ether);

        // Create initcode and salt to be sent to Factory
        bytes memory _initCode = abi.encode(
            owner1,
            address(bootstrapSingleton),
            abi.encodeCall(
                bootstrapSingleton.initMSA,
                (validators, executors, hook, fallbacks)
            )
        );
        bytes32 salt = keccak256("1");

        vm.startPrank(owner1);
        // create account
        mewAccount = ModularEtherspotWallet(
            payable(factory.createAccount({salt: salt, initCode: _initCode}))
        );
        vm.deal(address(mewAccount), 100 ether);
        vm.stopPrank();
        return mewAccount;
    }

    function _getHookMultiPlexerInitDataWithAllHookTypes()
        internal
        returns (bytes memory)
    {
        address[] memory globalHooks = new address[](1);
        globalHooks[0] = address(credibleAccountModule);

        address[] memory allHooks = _getHooks(true);

        address[] memory valueHooks = new address[](1);
        valueHooks[0] = address(allHooks[1]);
        vm.label((allHooks[1]), "valueHooks");
        address[] memory delegatecallHooks = new address[](1);
        delegatecallHooks[0] = address(allHooks[2]);
        vm.label((allHooks[2]), "delegatecallHooks");

        address[] memory _sigHooks = new address[](2);
        _sigHooks[0] = address(allHooks[3]);
        vm.label((allHooks[3]), "sigHooks1 index 3");

        _sigHooks[1] = address(allHooks[4]);
        vm.label((allHooks[4]), "sigHooks2 index 4");

        SigHookInit[] memory sigHooks = new SigHookInit[](1);
        sigHooks[0] = SigHookInit({
            sig: IERC7579Account.installModule.selector,
            subHooks: _sigHooks
        });

        address[] memory _targetSigHooks = new address[](2);
        _targetSigHooks[0] = address(allHooks[5]);
        vm.label((allHooks[5]), "targetSigHook1 index 5");
        _targetSigHooks[1] = address(allHooks[6]);
        vm.label((allHooks[6]), "targetSigHook2 index 6");

        SigHookInit[] memory targetSigHooks = new SigHookInit[](1);
        targetSigHooks[0] = SigHookInit({
            sig: IERC20Interface.transfer.selector,
            subHooks: _targetSigHooks
        });

        return
            abi.encode(
                globalHooks,
                valueHooks,
                delegatecallHooks,
                sigHooks,
                targetSigHooks
            );
    }

    function _getHookMultiPlexerInitDataWithCredibleAccountModule()
        internal
        view
        returns (bytes memory)
    {
        address[] memory globalHooks = new address[](1);
        globalHooks[0] = address(credibleAccountModule);
        address[] memory valueHooks = new address[](0);
        address[] memory delegatecallHooks = new address[](0);
        SigHookInit[] memory sigHooks = new SigHookInit[](0);
        SigHookInit[] memory targetSigHooks = new SigHookInit[](0);
        return
            abi.encode(
                globalHooks,
                valueHooks,
                delegatecallHooks,
                sigHooks,
                targetSigHooks
            );
    }

    function _getHookMultiPlexerInitDataWithNoSubHooks()
        internal
        pure
        returns (bytes memory)
    {
        address[] memory globalHooks = new address[](0);
        address[] memory valueHooks = new address[](0);
        address[] memory delegatecallHooks = new address[](0);
        SigHookInit[] memory sigHooks = new SigHookInit[](0);
        SigHookInit[] memory targetSigHooks = new SigHookInit[](0);
        return
            abi.encode(
                globalHooks,
                valueHooks,
                delegatecallHooks,
                sigHooks,
                targetSigHooks
            );
    }

    function _getHooks(
        bool sort
    ) internal view returns (address[] memory allHooks) {
        allHooks = Solarray.addresses(
            address(subHook1),
            address(subHook2),
            address(subHook3),
            address(subHook4),
            address(subHook5),
            address(subHook7),
            address(subHook6)
        );
        if (sort) {
            allHooks.sort();
        }
    }
}
