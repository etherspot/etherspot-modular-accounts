// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {CALLTYPE_SINGLE} from "ERC7579/libs/ModeLib.sol";
import "ERC7579/test/dependencies/EntryPoint.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {CredibleAccountModuleHarness} from "../../../harnesses/CredibleAccountModuleHarness.sol";
import "../../../../src/common/Enums.sol";
import "../../../../src/common/Structs.sol";
import {TestERC20} from "../../../../src/test/TestERC20.sol";
import {TestUSDC} from "../../../../src/test/TestUSDC.sol";
import "../../../TestAdvancedUtils.t.sol";
import "../../../../src/utils/ERC4337Utils.sol";

contract CredibleAccountModuleTestUtils is ModularTestBase {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Contract instances
    CredibleAccountModuleHarness internal harness;

    // Test addresses and keys
    User solver;
    User otherSessionKey;

    // Test variables
    bytes internal constant PROOF = hex"1234567890abcdef";
    uint48 internal validAfter = uint48(block.timestamp);
    uint48 internal validUntil = uint48(block.timestamp + 1 days);
    address[3] internal tokens = [address(usdc), address(dai), address(usdt)];
    uint256[3] internal amounts = [100e6, 200e18, 300e18];

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier withRequiredModules() {
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(moecdsav), hex"");
        _installHookViaMultiplexer(scw, address(cam), HookType.GLOBAL);
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(cam), abi.encode(MODULE_TYPE_VALIDATOR));
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(eoa.pub));
        vm.startPrank(address(scw));
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        TEST HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor() {
        beneficiary = payable(address(uint160(uint256(keccak256(abi.encodePacked("beneficiary"))))));
        receiver = payable(address(uint160(uint256(keccak256(abi.encodePacked("receiver"))))));

        dummySessionKey = payable(address(uint160(uint256(keccak256(abi.encodePacked("dummySessionKey"))))));
    }

    function _testSetup() internal {
        // Set up contracts and wallet
        mew = setupMEWWithEmptyHookMultiplexer();
        harness = new CredibleAccountModuleHarness(address(proofVerifier), address(hookMultiPlexer));
        dai = new TestERC20();
        uni = new TestERC20();
        usdc = new TestUSDC();
        aave = new TestERC20();
        // Set up test addresses and keys
        (alice, aliceKey) = makeAddrAndKey("alice");
        (sessionKey, sessionKeyPrivateKey) = makeAddrAndKey("sessionKey");
        vm.deal(beneficiary, 1 ether);
        _addCredibleAccountModuleAsSubHook();
        _installCredibleAccountModuleAsValidator();
        vm.startPrank(address(mew));
        // Set up test variables
        tokens = [address(usdc), address(dai), address(usdt)];
        amounts = [100e6, 200e18, 300e18];
        // Mint and approve tokens
        usdc.mint(address(mew), amounts[0]);
        usdc.approve(address(mew), amounts[0]);
        dai.mint(address(mew), amounts[1]);
        dai.approve(address(mew), amounts[1]);
        uni.mint(address(mew), amounts[2]);
        uni.approve(address(mew), amounts[2]);
    }

    function _addCredibleAccountModuleAsSubHook() internal {
        vm.startPrank(owner1);
        bool isEcdsaValidatorInstalled = mew.isModuleInstalled(MODULE_TYPE_VALIDATOR, address(ecdsaValidator), "");
        bytes memory hookMultiPlexerInitData = _getHookMultiPlexerInitDataWithCredibleAccountModule();
        bytes memory hookMultiPlexerInitDataWithCredibleAccountModule =
            abi.encodeWithSelector(HookMultiPlexer.addHook.selector, address(credibleAccountModule), HookType.GLOBAL);
        bytes memory userOpCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(hookMultiPlexer), uint256(0), hookMultiPlexerInitDataWithCredibleAccountModule
                )
            )
        );
        (bytes32 hash, PackedUserOperation memory userOp) =
            _createUserOperationWithoutProof(address(mew), userOpCalldata, owner1Key);
        // Execute the user operation
        _executeUserOperation(userOp);
        vm.stopPrank();
    }

    function _installCredibleAccountModuleAsValidator() internal {
        vm.startPrank(owner1);
        Execution[] memory batchCall1 = new Execution[](1);
        batchCall1[0].target = address(mew);
        batchCall1[0].value = 0;
        batchCall1[0].callData = abi.encodeWithSelector(
            ModularEtherspotWallet.installModule.selector,
            uint256(1),
            address(credibleAccountModule),
            abi.encode(MODULE_TYPE_VALIDATOR)
        );
        defaultExecutor.execBatch(IERC7579Account(mew), batchCall1);
        vm.stopPrank();
    }

    function _createResourceLock(address _wallet) internal view returns (bytes memory) {
        TokenData[] memory td = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            td[i] = TokenData(tokens[i], amounts[i]);
        }
        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: _scw,
            sessionKey: sessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            bidHash: DUMMY_BID_HASH,
            tokenData: td
        });
        return rl;
    }

    function _enableDefaultSessionKey(address _wallet) internal {
        bytes memory rl = _createResourceLock(_wallet);
        credibleAccountModule.enableSessionKey(rl);
    }

    function _createTokenTransferExecution(address _recipient, uint256 _amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IERC20.transfer.selector, _recipient, _amount);
    }

    function _createTokenTransferFromExecution(address _from, address _recipient, uint256 _amount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(IERC20.transferFrom.selector, _from, _recipient, _amount);
    }

    function _createUserOpWithSignature(address _account, bytes memory _callData, uint256 _signerKey)
        internal
        view
        returns (PackedUserOperation memory, bytes32, uint8, bytes32, bytes32)
    {
        PackedUserOperation memory userOp = entrypoint.fillUserOp(_account, _callData);
        userOp.nonce = getNonce(_account, address(credibleAccountModule));
        bytes32 hash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerKey, ECDSA.toEthSignedMessageHash(hash));
        return (userOp, hash, v, r, s);
    }

    function _createUserOpWithSignatureWithDefaultValidator(
        address _account,
        bytes memory _callData,
        uint256 _signerKey
    ) internal view returns (PackedUserOperation memory, bytes32, uint8, bytes32, bytes32) {
        PackedUserOperation memory userOp = entrypoint.fillUserOp(_account, _callData);

        userOp.nonce = getNonce(_account, address(ecdsaValidator));
        bytes32 hash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerKey, ECDSA.toEthSignedMessageHash(hash));

        return (userOp, hash, v, r, s);
    }

    function _createUserOperation(address _account, bytes memory _callData, address _validator, uint256 _signerKey)
        internal
        view
        returns (bytes32, PackedUserOperation memory)
    {
        PackedUserOperation memory userOp = entrypoint.fillUserOp(_account, _callData);
        userOp.nonce = getNonce(_account, _validator);
        bytes32 hash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerKey, ECDSA.toEthSignedMessageHash(hash));
        if (_validator == address(credibleAccountModule)) {
            // append r, s, v of signature followed by Proof to the signature
            userOp.signature = abi.encodePacked(r, s, v, DUMMY_PROOF);
        } else {
            userOp.signature = abi.encodePacked(r, s, v);
        }
        return (hash, userOp);
    }

    function _createUserOperationWithoutProof(address _account, bytes memory _callData, uint256 _signerKey)
        internal
        view
        returns (bytes32, PackedUserOperation memory)
    {
        (PackedUserOperation memory userOp, bytes32 hash, uint8 v, bytes32 r, bytes32 s) =
            _createUserOpWithSignatureWithDefaultValidator(_account, _callData, _signerKey);

        // append r, s, v of signature followed by merkleRoot and merkleProof to the signature
        userOp.signature = abi.encodePacked(r, s, v);

        return (hash, userOp);
    }

    function _createUserOperationWithInvalidMessageProof(address _account, bytes memory _callData, uint256 _signerKey)
        internal
        view
        returns (bytes32, PackedUserOperation memory)
    {
        (PackedUserOperation memory userOp, bytes32 hash, uint8 v, bytes32 r, bytes32 s) =
            _createUserOpWithSignature(_account, _callData, _signerKey);
        // append r, s, v of signature followed by merkleRoot and merkleProof to the signature
        userOp.signature = abi.encodePacked(r, s, v, DUMMY_PROOF);
        return (hash, userOp);
    }

    function _executeUserOperation(PackedUserOperation memory _userOp) internal {
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = _userOp;
        entrypoint.handleOps(userOps, beneficiary);
    }

    function _claimTokensBySolver(uint256 _usdc, uint256 _dai, uint256 _uni) internal {
        bytes memory usdcData = _createTokenTransferFromExecution(address(mew), address(solver), _usdc);
        bytes memory daiData = _createTokenTransferFromExecution(address(mew), address(solver), _dai);
        bytes memory uniData = _createTokenTransferFromExecution(address(mew), address(solver), _uni);
        Execution[] memory batch = new Execution[](3);
        Execution memory usdcExec = Execution({target: address(usdc), value: 0, callData: usdcData});
        Execution memory daiExec = Execution({target: address(dai), value: 0, callData: daiData});
        Execution memory uniExec = Execution({target: address(uni), value: 0, callData: uniData});
        batch[0] = usdcExec;
        batch[1] = daiExec;
        batch[2] = uniExec;
        bytes memory userOpCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (, PackedUserOperation memory userOp) =
            _createUserOperation(address(mew), userOpCalldata, address(credibleAccountModule), sessionKeyPrivateKey);
        // Execute the user operation
        _executeUserOperation(userOp);
    }

    function _getPrevValidator(address _validator) internal view returns (address) {
        // Presuming that wallet won't have more than 20 different validators installed
        for (uint256 i = 1; i <= 20; i++) {
            (address[] memory validators,) = mew.getValidatorPaginated(address(0x1), i);
            if (validators.length > 0) {
                if (validators[validators.length - 1] == _validator) {
                    return validators.length > 1 ? validators[validators.length - 2] : address(0x1);
                }
            }
        }
        revert("Validator not found");
    }
}
