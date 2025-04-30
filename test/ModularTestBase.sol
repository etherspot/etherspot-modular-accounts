// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {IERC7579Account} from "../src/interfaces/base/IERC7579Account.sol";
import {Bootstrap, BootstrapConfig} from "../src/utils/Bootstrap.sol";
import {BootstrapLib} from "../src/libraries/BootstrapLib.sol";
import "../src/test/dependencies/EntryPoint.sol";
import {ModularEtherspotWallet} from "../src/wallet/ModularEtherspotWallet.sol";
import {ModularEtherspotWalletFactory} from "../src/factory/ModularEtherspotWalletFactory.sol";
import {ECDSAValidator} from "../src/modules/validators/ECDSAValidator.sol";
import {MultipleOwnerECDSAValidator} from "../src/modules/validators/MultipleOwnerECDSAValidator.sol";
import {GuardianRecoveryValidator} from "../src/modules/validators/GuardianRecoveryValidator.sol";
import {ERC20SessionKeyValidator} from "../src/modules/validators/ERC20SessionKeyValidator.sol";
import {SessionKeyValidator} from "../src/modules/validators/SessionKeyValidator.sol";
import {ERC1155FallbackHandler} from "../src/modules/fallbacks/ERC1155FallbackHandler.sol";
import {CredibleAccountValidator} from "../src/modules/validators/CredibleAccountValidator.sol";
import {CredibleAccountHook} from "../src/modules/hooks/CredibleAccountHook.sol";
import {HookMultiPlexer} from "../src/modules/hooks/HookMultiPlexer.sol";
import {ResourceLockValidator} from "../src/modules/validators/ResourceLockValidator.sol";
import {MODULE_TYPE_FALLBACK} from "../src/types/Constants.sol";
import {HookType} from "../src/types/Enums.sol";
import {SigHookInit} from "../src/types/Structs.sol";
import {MockValidator} from "../src/test/mocks/MockValidator.sol";
import {MockExecutor} from "../src/test/mocks/MockExecutor.sol";
import {MockFallback} from "../src/test/mocks/MockFallbackHandler.sol";
import {MockHook} from "../src/test/mocks/MockHook.sol";
import {MockRegistry} from "../src/test/mocks/MockRegistry.sol";
import {MockTarget} from "../src/test/mocks/MockTarget.sol";
import {MockDelegateTarget} from "../src/test/mocks/MockDelegateTarget.sol";
import {TestUSDC} from "../src/test/TestUSDC.sol";
import {TestERC20} from "../src/test/TestERC20.sol";
import {TestWETH} from "../src/test/TestWETH.sol";
import {TestUniswapV2} from "../src/test/TestUniswapV2.sol";

contract ModularTestBase is Test {
    using ECDSA for bytes32;
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address internal constant ENTRYPOINT_7 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    bytes32 internal constant TEST_SALT = keccak256("modular.test_salt");
    string internal constant AA22 = "AA22 expired or not due";
    string internal constant AA23 = "AA23 reverted";
    string internal constant AA24 = "AA24 signature error";

    /*//////////////////////////////////////////////////////////////
                              CONTRACTS
    //////////////////////////////////////////////////////////////*/

    IEntryPoint ENTRYPOINT = IEntryPoint(ENTRYPOINT_7);
    ModularEtherspotWallet internal IMPLEMENTATION;
    ModularEtherspotWallet internal SCW;
    ModularEtherspotWalletFactory internal FACTORY;
    Bootstrap internal BOOTSTRAP;
    ECDSAValidator internal ECDSA_VALIDATOR;
    MultipleOwnerECDSAValidator internal MULTIPLE_OWNER_ECDSA_VALIDATOR;
    GuardianRecoveryValidator internal GUARDIAN_RECOVERY_VALIDATOR;
    ERC20SessionKeyValidator internal ERC20_SESSION_KEY_VALIDATOR;
    SessionKeyValidator internal SESSION_KEY_VALIDATOR;
    ResourceLockValidator internal RESOURCE_LOCK_VALIDATOR;
    CredibleAccountValidator internal CREDIBLE_ACCOUNT_VALIDATOR;
    CredibleAccountHook internal CREDIBLE_ACCOUNT_HOOK;
    HookMultiPlexer internal HOOK_MULTIPLEXER;
    ERC1155FallbackHandler internal ERC1155_FALLBACK_HANDLER;
    TestUSDC internal USDC;
    TestERC20 internal USDT;
    TestERC20 internal DAI;
    TestERC20 internal LINK;
    TestWETH internal WETH;
    TestUniswapV2 internal UNISWAP_V2;

    MockValidator internal MOCK_VALIDATOR;
    MockExecutor internal MOCK_EXECUTOR;
    MockFallback internal MOCK_FALLBACK;
    MockHook internal MOCK_HOOK;
    MockRegistry internal MOCK_REGISTRY;
    MockTarget internal MOCK_TARGET;
    MockDelegateTarget internal MOCK_DELEGATE_TARGET;

    /*//////////////////////////////////////////////////////////////
                                USERS
    //////////////////////////////////////////////////////////////*/

    User internal alice;
    User internal beneficiary;
    User internal bob;
    User internal charlie;
    User internal deployer;
    User internal eoa;
    User internal guardian1;
    User internal guardian2;
    User internal guardian3;
    User internal guardian4;
    User internal malicious;
    User internal sessionKey;
    User internal zero;

    ModularEtherspotWallet internal ALICE_SCW;
    ModularEtherspotWallet internal BOB_SCW;

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct User {
        address payable pub;
        uint256 priv;
    }

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _testInit() internal {
        // Setup EntryPoint
        ENTRYPOINT = etchEntrypoint();
        // Setup Deployer
        deployer = _createDeployer("Deployer");
        // Mocks
        MOCK_VALIDATOR = new MockValidator();
        MOCK_EXECUTOR = new MockExecutor();
        MOCK_FALLBACK = new MockFallback();
        MOCK_HOOK = new MockHook();
        MOCK_REGISTRY = new MockRegistry();
        MOCK_TARGET = new MockTarget();
        MOCK_DELEGATE_TARGET = new MockDelegateTarget();
        vm.label({account: address(MOCK_VALIDATOR), newLabel: "MockValidator"});
        vm.label({account: address(MOCK_EXECUTOR), newLabel: "MockExecutor"});
        vm.label({account: address(MOCK_FALLBACK), newLabel: "MockFallback"});
        vm.label({account: address(MOCK_HOOK), newLabel: "MockHook"});
        vm.label({account: address(MOCK_REGISTRY), newLabel: "MockRegistry"});
        vm.label({account: address(MOCK_TARGET), newLabel: "MockTarget"});
        vm.label({account: address(MOCK_DELEGATE_TARGET), newLabel: "MockDelegateTarget"});
        // Contracts
        IMPLEMENTATION = new ModularEtherspotWallet(ENTRYPOINT);
        FACTORY = new ModularEtherspotWalletFactory(address(IMPLEMENTATION), eoa.pub);
        BOOTSTRAP = new Bootstrap();
        ECDSA_VALIDATOR = new ECDSAValidator();
        MULTIPLE_OWNER_ECDSA_VALIDATOR = new MultipleOwnerECDSAValidator();
        GUARDIAN_RECOVERY_VALIDATOR = new GuardianRecoveryValidator();
        ERC20_SESSION_KEY_VALIDATOR = new ERC20SessionKeyValidator();
        SESSION_KEY_VALIDATOR = new SessionKeyValidator();
        ERC1155_FALLBACK_HANDLER = new ERC1155FallbackHandler();
        HOOK_MULTIPLEXER = new HookMultiPlexer();
        CREDIBLE_ACCOUNT_VALIDATOR = new CredibleAccountValidator(deployer.pub, HOOK_MULTIPLEXER);
        CREDIBLE_ACCOUNT_HOOK = new CredibleAccountHook(CREDIBLE_ACCOUNT_VALIDATOR);
        RESOURCE_LOCK_VALIDATOR = new ResourceLockValidator();
        vm.label({account: address(IMPLEMENTATION), newLabel: "ModularEtherspotWallet"});
        vm.label({account: address(FACTORY), newLabel: "ModularEtherspotWalletFactory"});
        vm.label({account: address(BOOTSTRAP), newLabel: "Bootstrap"});
        vm.label({account: address(ECDSA_VALIDATOR), newLabel: "ECDSAValidator"});
        vm.label({account: address(MULTIPLE_OWNER_ECDSA_VALIDATOR), newLabel: "MultipleOwnerECDSAValidator"});
        vm.label({account: address(GUARDIAN_RECOVERY_VALIDATOR), newLabel: "GuardianRecoveryValidator"});
        vm.label({account: address(ERC20_SESSION_KEY_VALIDATOR), newLabel: "ERC20SessionKeyValidator"});
        vm.label({account: address(SESSION_KEY_VALIDATOR), newLabel: "SessionKeyValidator"});
        vm.label({account: address(ERC1155_FALLBACK_HANDLER), newLabel: "ERC1155FallbackHandler"});
        vm.label({account: address(HOOK_MULTIPLEXER), newLabel: "HookMultiPlexer"});
        vm.label({account: address(CREDIBLE_ACCOUNT_VALIDATOR), newLabel: "CredibleAccountValidator"});
        vm.label({account: address(CREDIBLE_ACCOUNT_HOOK), newLabel: "CredibleAccountHook"});
        vm.label({account: address(RESOURCE_LOCK_VALIDATOR), newLabel: "ResourceLockValidator"});
        // Tokens
        USDC = new TestUSDC();
        USDT = new TestERC20();
        DAI = new TestERC20();
        LINK = new TestERC20();
        WETH = new TestWETH();
        UNISWAP_V2 = new TestUniswapV2(WETH);
        vm.label({account: address(USDC), newLabel: "USDC"});
        vm.label({account: address(USDT), newLabel: "USDT"});
        vm.label({account: address(DAI), newLabel: "DAI"});
        vm.label({account: address(LINK), newLabel: "LINK"});
        vm.label({account: address(WETH), newLabel: "WETH"});
        vm.label({account: address(UNISWAP_V2), newLabel: "UniswapV2"});
        // Users
        alice = _createUser("Alice");
        beneficiary = _createUser("Beneficiary");
        bob = _createUser("Bob");
        charlie = _createUser("Charlie");
        eoa = _createUser("EOA");
        guardian1 = _createUser("Guardian 1");
        guardian2 = _createUser("Guardian 2");
        guardian3 = _createUser("Guardian 3");
        guardian4 = _createUser("Guardian 4");
        malicious = _createUser("Malicious EOA");
        sessionKey = _createUser("Session Key");
        zero = User({pub: payable(address(0)), priv: 0});
        // SCW
        SCW = _createSCW(eoa.pub);
        ALICE_SCW = _createSCW(alice.pub);
        BOB_SCW = _createSCW(bob.pub);
        // Initialize CredibleAccoutValidator
        vm.prank(deployer.pub);
        CREDIBLE_ACCOUNT_VALIDATOR.initialize(CREDIBLE_ACCOUNT_HOOK);
    }

    /*//////////////////////////////////////////////////////////////
                       FOUNDRY HELPERS/WRAPPERS
    //////////////////////////////////////////////////////////////*/
    function _makePayableAddrAndKey(string memory name)
        internal
        virtual
        returns (address payable addr, uint256 privateKey)
    {
        privateKey = uint256(keccak256(abi.encodePacked(name)));
        addr = payable(vm.addr(privateKey));
        vm.label(addr, name);
    }

    function _createDeployer(string memory _name) internal returns (User memory) {
        (address payable addr, uint256 key) = _makePayableAddrAndKey(_name);
        User memory user = User({pub: addr, priv: key});
        vm.label({account: addr, newLabel: _name});
        vm.deal({account: addr, newBalance: 100 ether});
        return user;
    }

    function _createUser(string memory _name) internal returns (User memory) {
        (address payable addr, uint256 key) = _makePayableAddrAndKey(_name);
        User memory user = User({pub: addr, priv: key});
        vm.label({account: addr, newLabel: _name});
        vm.deal({account: addr, newBalance: 100 ether});
        deal({token: address(DAI), to: addr, give: 100e18});
        deal({token: address(USDT), to: addr, give: 100e18});
        return user;
    }

    function _toRevert(bytes4 _selector, bytes memory _params) internal {
        if (_selector == bytes4(0)) {
            vm.expectRevert();
        } else if (_params.length == 0) {
            vm.expectRevert(abi.encodeWithSelector(_selector));
        } else {
            vm.expectRevert(abi.encodePacked(_selector, _params));
        }
    }

    /*//////////////////////////////////////////////////////////////
                      ERC-4337 HELPERS/WRAPPERS
    //////////////////////////////////////////////////////////////*/

    function _createUserOp(address _scw, address _validator) internal view returns (PackedUserOperation memory) {
        PackedUserOperation memory op = PackedUserOperation({
            sender: _scw,
            nonce: _getNonce(_scw, _validator),
            initCode: hex"",
            callData: "",
            accountGasLimits: bytes32(abi.encodePacked(uint128(2000000), uint128(2000000))),
            preVerificationGas: 1000000,
            gasFees: bytes32(abi.encodePacked(uint128(1), uint128(1))),
            paymasterAndData: hex"",
            signature: hex""
        });
        return op;
    }

    function _getNonce(address account, address validator) internal view returns (uint256 nonce) {
        uint192 key = uint192(bytes24(bytes20(validator)));
        nonce = ENTRYPOINT.getNonce(address(account), key);
    }

    function _sign(bytes32 hash, User memory _user) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_user.priv, hash);
        return abi.encodePacked(r, s, v);
    }

    function _ethSign(bytes32 hash, User memory _user) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_user.priv, ECDSA.toEthSignedMessageHash(hash));
        return abi.encodePacked(r, s, v);
    }

    function _executeUserOp(PackedUserOperation memory _op) internal {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _op;
        ENTRYPOINT.handleOps(ops, beneficiary.pub);
    }

    function _revertUserOpEvent(bytes32 _hash, uint256 _nonce, bytes4 _selector, bytes memory _params) internal {
        vm.expectEmit(false, false, false, true);
        emit IEntryPoint.UserOperationRevertReason(_hash, address(SCW), _nonce, abi.encodePacked(_selector, _params));
    }

    /*//////////////////////////////////////////////////////////////
                      ERC-7579 HELPERS/WRAPPERS
    //////////////////////////////////////////////////////////////*/

    function _createSCW(address _owner) internal returns (ModularEtherspotWallet) {
        // Setup data for HMP
        address[] memory emptySubHooks = new address[](0);
        SigHookInit[] memory sigHooks = new SigHookInit[](0);
        SigHookInit[] memory targetSigHooks = new SigHookInit[](0);
        bytes memory hmpData = abi.encode(emptySubHooks, emptySubHooks, emptySubHooks, sigHooks, targetSigHooks);
        // Create config for initial modules
        address[] memory validatorAddresses = new address[](2);
        validatorAddresses[0] = address(MOCK_VALIDATOR);
        validatorAddresses[1] = address(ECDSA_VALIDATOR);
        bytes[] memory validatorData = new bytes[](2);
        validatorData[1] = abi.encode(_owner);
        BootstrapConfig[] memory validators = BootstrapLib._buildMultipleConfigs(validatorAddresses, validatorData);
        BootstrapConfig[] memory executors = BootstrapLib._buildArrayConfig(address(MOCK_EXECUTOR), "");
        BootstrapConfig memory hook = BootstrapLib._buildSingleConfig(address(HOOK_MULTIPLEXER), hmpData);
        BootstrapConfig[] memory fallbacks = BootstrapLib._buildEmptyArrayConfig();
        bytes memory _initCode = abi.encode(
            address(BOOTSTRAP),
            abi.encodeCall(BOOTSTRAP.initializeModularAccount, (validators, executors, hook, fallbacks))
        );
        vm.startPrank(_owner);
        ModularEtherspotWallet scw = ModularEtherspotWallet(
            payable(FACTORY.createAccount({_owner: _owner, _salt: TEST_SALT, _initCode: _initCode}))
        );
        vm.deal(address(scw), 100 ether);
        vm.stopPrank();
        return scw;
    }

    function _installModule(
        address _owner,
        ModularEtherspotWallet _scw,
        uint256 _moduleType,
        address _module,
        bytes memory _initData
    ) internal returns (bool) {
        vm.startPrank(_owner);
        // Execute the module installation
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(_scw),
            address(_scw),
            0,
            abi.encodeWithSelector(_scw.installModule.selector, _moduleType, _module, _initData)
        );
        if (_moduleType == MODULE_TYPE_FALLBACK) {
            bytes4 selector = bytes4(bytes32(_initData));
            return _scw.isModuleInstalled(_moduleType, _module, abi.encode(selector));
        }
        vm.stopPrank();
        // Verify that the module is installed
        return _scw.isModuleInstalled(_moduleType, _module, "");
    }

    function _uninstallModule(
        address _owner,
        ModularEtherspotWallet _scw,
        uint256 _moduleType,
        address _module,
        bytes memory _deInitData
    ) internal returns (bool) {
        vm.startPrank(_owner);
        if (_moduleType == MODULE_TYPE_FALLBACK) {
            MOCK_EXECUTOR.executeViaAccount(
                IERC7579Account(_scw),
                address(_scw),
                0,
                abi.encodeWithSelector(_scw.uninstallModule.selector, _moduleType, _module, _deInitData)
            );
            return _scw.isModuleInstalled(_moduleType, _module, _deInitData);
        }
        address prevValidator = _getPrevValidator(_scw, _module);
        // Execute the module installation
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(_scw),
            address(_scw),
            0,
            abi.encodeWithSelector(
                _scw.uninstallModule.selector, _moduleType, _module, abi.encode(prevValidator, _deInitData)
            )
        );
        // Verify that the module is installed
        return _scw.isModuleInstalled(_moduleType, _module, "");
        vm.stopPrank();
    }

    function _installHookViaMultiplexer(ModularEtherspotWallet _scw, address _hook, HookType _hookType) internal {
        vm.startPrank(address(_scw));
        HOOK_MULTIPLEXER.addHook(_hook, _hookType);
        vm.stopPrank();
    }

    function _uninstallHookViaMultiplexer(ModularEtherspotWallet _scw, address _hook, HookType _hookType) internal {
        vm.startPrank(address(_scw));
        HOOK_MULTIPLEXER.removeHook(_hook, _hookType);
        vm.stopPrank();
    }

    function _getPrevValidator(ModularEtherspotWallet _scw, address _validator) internal view returns (address) {
        if (_validator == address(0)) return address(0);
        (address[] memory validators,) = _scw.getValidatorsPaginated(
            address(0x1), // Start from SENTINEL
            20 // Use a large batch to ensure validator found
        );
        for (uint256 i; i < validators.length; ++i) {
            if (validators[i] == _validator) {
                if (i == 0) return address(0x1); // If first element, return SENTINEL
                return validators[i - 1];
            }
        }
        return address(0);
    }

    /*//////////////////////////////////////////////////////////////
                       MERKLE HELPERS/WRAPPERS
    //////////////////////////////////////////////////////////////*/

    function getTestProof(bytes32 _leaf, bool valid)
        public
        pure
        returns (bytes32[] memory proof, bytes32 root, bytes32 leaf)
    {
        if (valid) {
            // Create a larger tree with 8 leaves
            proof = new bytes32[](3);
            // Level 1 proofs
            proof[0] = bytes32("b");
            // Level 2 proofs
            proof[1] = _hashPair(bytes32("c"), bytes32("d"));
            // Level 3 proofs
            proof[2] = _hashPair(_hashPair(bytes32("e"), bytes32("f")), _hashPair(bytes32("g"), bytes32("h")));
            // Build root from bottom up
            bytes32 level1Hash = _hashPair(_leaf, proof[0]);
            bytes32 level2Hash = _hashPair(level1Hash, proof[1]);
            root = _hashPair(level2Hash, proof[2]);
        } else {
            // Same structure but with invalid leaf
            proof = new bytes32[](3);
            proof[0] = bytes32("b");
            proof[1] = _hashPair(bytes32("c"), bytes32("d"));
            proof[2] = _hashPair(_hashPair(bytes32("e"), bytes32("f")), _hashPair(bytes32("g"), bytes32("h")));
            leaf = bytes32("invalid"); // Different leaf
            // Root remains from valid tree
            bytes32 level1Hash = _hashPair(bytes32("a"), proof[0]);
            bytes32 level2Hash = _hashPair(level1Hash, proof[1]);
            root = _hashPair(level2Hash, proof[2]);
        }
    }

    function _packProofForSignature(bytes32[] memory proof) internal pure returns (bytes memory) {
        bytes memory result;
        for (uint256 i; i < proof.length; ++i) {
            result = bytes.concat(result, abi.encodePacked(proof[i]));
        }
        return result;
    }

    function _hashPair(bytes32 left, bytes32 right) private pure returns (bytes32 result) {
        assembly {
            switch lt(left, right)
            case 0 {
                mstore(0x0, right)
                mstore(0x20, left)
            }
            default {
                mstore(0x0, left)
                mstore(0x20, right)
            }
            result := keccak256(0x0, 0x40)
        }
    }
}
