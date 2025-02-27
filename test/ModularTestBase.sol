// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {IERC7579Account} from "ERC7579/interfaces/IERC7579Account.sol";
import {Bootstrap} from "ERC7579/utils/Bootstrap.sol";
import {BootstrapUtil, BootstrapConfig} from "ERC7579/test/Bootstrap.t.sol";
import {ExecutionLib} from "ERC7579/libs/ExecutionLib.sol";
import {
    ModeLib,
    ModeCode,
    CallType,
    ExecType,
    ModeSelector,
    ModePayload,
    CALLTYPE_STATIC,
    EXECTYPE_DEFAULT,
    MODE_DEFAULT
} from "ERC7579/libs/ModeLib.sol";
import "ERC7579/test/dependencies/EntryPoint.sol";
import {ModularEtherspotWallet} from "../src/wallet/ModularEtherspotWallet.sol";
import {ModularEtherspotWalletFactory} from "../src/wallet/ModularEtherspotWalletFactory.sol";
import {MultipleOwnerECDSAValidator} from "../src/modules/validators/MultipleOwnerECDSAValidator.sol";
import {ERC20SessionKeyValidator} from "../src/modules/validators/ERC20SessionKeyValidator.sol";
import {SessionKeyValidator} from "../src/modules/validators/SessionKeyValidator.sol";
import {ERC1155FallbackHandler} from "../src/modules/fallbacks/ERC1155FallbackHandler.sol";
import {ProofVerifier} from "../src/utils/ProofVerifier.sol";
import {CredibleAccountModule} from "../src/modules/validators/CredibleAccountModule.sol";
import {HookMultiPlexer} from "../src/modules/hooks/HookMultiPlexer.sol";
import {ResourceLockValidator} from "../src/modules/validators/ResourceLockValidator.sol";
import {MockValidator} from "ERC7579/test/mocks/MockValidator.sol";
import {MockExecutor} from "ERC7579/test/mocks/MockExecutor.sol";
import {MockFallback} from "ERC7579/test/mocks/MockFallbackHandler.sol";
import {MockHook} from "../src/test/mocks/MockHook.sol";
import {MockRegistry} from "../src/test/mocks/MockRegistry.sol";
import {MockTarget} from "ERC7579/test/mocks/MockTarget.sol";
import {MockDelegateTarget} from "ERC7579/test/mocks/MockDelegateTarget.sol";
import "../src/common/Constants.sol";
import "../src/common/Structs.sol";
import {TestUSDC} from "../src/test/TestUSDC.sol";
import {TestERC20} from "../src/test/TestERC20.sol";
import {TestWETH} from "../src/test/TestWETH.sol";
import {TestUniswapV2} from "../src/test/TestUniswapV2.sol";

contract ModularTestBase is BootstrapUtil, Test {
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

    IEntryPoint entrypoint = IEntryPoint(ENTRYPOINT_7);
    ModularEtherspotWallet internal impl;
    ModularEtherspotWallet internal scw;
    ModularEtherspotWalletFactory internal factory;
    MultipleOwnerECDSAValidator internal moecdsav;
    ERC20SessionKeyValidator internal erc20skv;
    SessionKeyValidator internal skv;
    ResourceLockValidator internal rlv;
    ProofVerifier internal pv;
    CredibleAccountModule internal cam;
    HookMultiPlexer internal hmp;
    ERC1155FallbackHandler internal erc1155fb;
    TestUSDC internal usdc;
    TestERC20 internal usdt;
    TestERC20 internal dai;
    TestERC20 internal link;
    TestWETH internal weth;
    TestUniswapV2 internal uniswapV2;

    MockValidator internal mockVal;
    MockExecutor internal mockExec;
    MockFallback internal mockFallback;
    MockHook internal mockHook;
    MockRegistry internal mockReg;
    MockTarget internal mockTar;
    MockDelegateTarget internal mockDelTar;

    /*//////////////////////////////////////////////////////////////
                                USERS
    //////////////////////////////////////////////////////////////*/

    User internal alice;
    User internal bob;
    User internal beneficiary;
    User internal eoa;
    User internal guardian1;
    User internal guardian2;
    User internal guardian3;
    User internal guardian4;
    User internal malicious;
    User internal sessionKey;
    User internal zero;

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
        etchEntrypoint();
        // Mocks
        mockVal = new MockValidator();
        mockExec = new MockExecutor();
        mockFallback = new MockFallback();
        mockHook = new MockHook();
        mockReg = new MockRegistry();
        mockTar = new MockTarget();
        mockDelTar = new MockDelegateTarget();
        vm.label({account: address(mockVal), newLabel: "MockValidator"});
        vm.label({account: address(mockExec), newLabel: "MockExecutor"});
        vm.label({account: address(mockFallback), newLabel: "MockFallback"});
        vm.label({account: address(mockHook), newLabel: "MockHook"});
        vm.label({account: address(mockReg), newLabel: "MockRegistry"});
        vm.label({account: address(mockTar), newLabel: "MockTarget"});
        vm.label({account: address(mockDelTar), newLabel: "MockDelegateTarget"});
        // Contracts
        impl = new ModularEtherspotWallet();
        factory = new ModularEtherspotWalletFactory(address(impl), eoa.pub);
        moecdsav = new MultipleOwnerECDSAValidator();
        erc20skv = new ERC20SessionKeyValidator();
        skv = new SessionKeyValidator();
        erc1155fb = new ERC1155FallbackHandler();
        pv = new ProofVerifier();
        hmp = new HookMultiPlexer(mockReg);
        cam = new CredibleAccountModule(address(pv), address(hmp));
        rlv = new ResourceLockValidator();
        vm.label({account: address(impl), newLabel: "ModularEtherspotWallet"});
        vm.label({account: address(factory), newLabel: "ModularEtherspotWalletFactory"});
        vm.label({account: address(moecdsav), newLabel: "MultipleOwnerECDSAValidator"});
        vm.label({account: address(erc20skv), newLabel: "ERC20SessionKeyValidator"});
        vm.label({account: address(skv), newLabel: "SessionKeyValidator"});
        vm.label({account: address(erc1155fb), newLabel: "ERC1155FallbackHandler"});
        vm.label({account: address(pv), newLabel: "ProofVerifier"});
        vm.label({account: address(hmp), newLabel: "HookMultiPlexer"});
        vm.label({account: address(cam), newLabel: "CredibleAccountModule"});
        vm.label({account: address(rlv), newLabel: "ResourceLockValidator"});
        // Tokens
        usdc = new TestUSDC();
        usdt = new TestERC20();
        dai = new TestERC20();
        weth = new TestWETH();
        link = new TestERC20();
        uniswapV2 = new TestUniswapV2(weth);
        vm.label({account: address(usdc), newLabel: "USDC"});
        vm.label({account: address(usdt), newLabel: "USDT"});
        vm.label({account: address(dai), newLabel: "DAI"});
        vm.label({account: address(link), newLabel: "LINK"});
        vm.label({account: address(weth), newLabel: "WETH"});
        vm.label({account: address(uniswapV2), newLabel: "UniswapV2"});
        // Users
        alice = _createUser("Alice");
        bob = _createUser("Bob");
        beneficiary = _createUser("Beneficiary");
        eoa = _createUser("EOA");
        guardian1 = _createUser("Guardian 1");
        guardian2 = _createUser("Guardian 2");
        guardian3 = _createUser("Guardian 3");
        guardian4 = _createUser("Guardian 4");
        malicious = _createUser("Malicious EOA");
        sessionKey = _createUser("Session Key");
        zero = User({pub: payable(address(0)), priv: 0});
        // SCW
        scw = _createSCW(eoa.pub);
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

    function _createUser(string memory _name) internal returns (User memory) {
        (address payable addr, uint256 key) = _makePayableAddrAndKey(_name);
        User memory user = User({pub: addr, priv: key});
        vm.label({account: addr, newLabel: _name});
        vm.deal({account: addr, newBalance: 100 ether});
        deal({token: address(dai), to: addr, give: 100e18});
        deal({token: address(usdt), to: addr, give: 100e18});
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
        nonce = entrypoint.getNonce(address(account), key);
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
        entrypoint.handleOps(ops, beneficiary.pub);
    }

    function _revertUserOpEvent(bytes32 _hash, uint256 _nonce, bytes4 _selector, bytes memory _params) internal {
        vm.expectEmit(false, false, false, true);
        emit IEntryPoint.UserOperationRevertReason(_hash, address(scw), _nonce, abi.encodePacked(_selector, _params));
    }

    /*//////////////////////////////////////////////////////////////
                      ERC-7579 HELPERS/WRAPPERS
    //////////////////////////////////////////////////////////////*/

    function _createSCW(address _owner) internal returns (ModularEtherspotWallet) {
        // Setup data for HMP
        address[] memory globalHooks = new address[](0);
        address[] memory valueHooks = new address[](0);
        address[] memory delegatecallHooks = new address[](0);
        SigHookInit[] memory sigHooks = new SigHookInit[](0);
        SigHookInit[] memory targetSigHooks = new SigHookInit[](0);
        bytes memory hmpData = abi.encode(globalHooks, valueHooks, delegatecallHooks, sigHooks, targetSigHooks);
        // Create config for initial modules
        BootstrapConfig[] memory validators = new BootstrapConfig[](1);
        validators[0] = _makeBootstrapConfig(address(mockVal), "");
        BootstrapConfig[] memory executors = makeBootstrapConfig(address(mockExec), "");
        BootstrapConfig memory hook = _makeBootstrapConfig(address(hmp), hmpData);
        BootstrapConfig[] memory fallbacks = makeBootstrapConfig(address(0), "");
        bytes memory _initCode = abi.encode(
            _owner,
            address(bootstrapSingleton),
            abi.encodeCall(bootstrapSingleton.initMSA, (validators, executors, hook, fallbacks))
        );
        vm.startPrank(_owner);
        scw = ModularEtherspotWallet(payable(factory.createAccount({salt: TEST_SALT, initCode: _initCode})));
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
        mockExec.executeViaAccount(
            IERC7579Account(_scw),
            address(_scw),
            0,
            abi.encodeWithSelector(_scw.installModule.selector, _moduleType, _module, _initData)
        );
        if (_moduleType == MODULE_TYPE_FALLBACK) {
            bytes4 selector = bytes4(bytes32(_initData));
            return scw.isModuleInstalled(_moduleType, _module, abi.encode(selector));
        }
        vm.stopPrank();
        // Verify that the module is installed
        return scw.isModuleInstalled(_moduleType, _module, "");
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
            mockExec.executeViaAccount(
                IERC7579Account(_scw),
                address(_scw),
                0,
                abi.encodeWithSelector(_scw.uninstallModule.selector, _moduleType, _module, _deInitData)
            );
            return scw.isModuleInstalled(_moduleType, _module, _deInitData);
        }
        address prevValidator = _getPrevValidator(_scw, _module);
        // Execute the module installation
        mockExec.executeViaAccount(
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
        hmp.addHook(_hook, _hookType);
        vm.stopPrank();
    }

    function _uninstallHookViaMultiplexer(ModularEtherspotWallet _scw, address _hook, HookType _hookType) internal {
        vm.startPrank(address(_scw));
        hmp.removeHook(_hook, _hookType);
        vm.stopPrank();
    }

    function _getPrevValidator(ModularEtherspotWallet _scw, address _validator) internal view returns (address) {
        if (_validator == address(0)) return address(0);
        (address[] memory validators,) = _scw.getValidatorPaginated(
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
