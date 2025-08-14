// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "ERC4337/core/Helpers.sol";
import "ERC7579/interfaces/IERC7579Module.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {ExecutionLib} from "ERC7579/libs/ExecutionLib.sol";
import "ERC7579/libs/ModeLib.sol";
import {CredibleAccountModule as CAM} from "../../../../src/modules/validators/CredibleAccountModule.sol";
import {ICredibleAccountModule as ICAM} from "../../../../src/interfaces/ICredibleAccountModule.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {CredibleAccountModuleTestUtils as TestUtils} from "../utils/CredibleAccountModuleTestUtils.sol";
import "../../../../src/common/Structs.sol";

contract CredibleAccountModule_Fuzz_Test is TestUtils {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testSetup();
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_enableSessionKey(
        string memory _sessionKey,
        uint48 _validAfter,
        uint48 _validUntil,
        address[3] memory _tokens,
        uint256[3] memory _amounts
    ) public withRequiredModules {
        User memory sk = _createUser(_sessionKey);

        // Define assumptions
        vm.assume(_validAfter < _validUntil);
        vm.assume(_validAfter > block.timestamp);

        // Enable session key
        TokenData[] memory tokenAmounts = new TokenData[](_tokens.length);
        for (uint256 i; i < _tokens.length; ++i) {
            vm.assume(_tokens[i] != address(0));
            vm.assume(_amounts[i] > 0);
            tokenAmounts[i] = TokenData(_tokens[i], _amounts[i]);
            vm.stopPrank();
            vm.startPrank(deployer.pub);
            // Only whitelist if not already whitelisted
            if (!im.isTokenWhitelisted(_tokens[i])) {
                im.addTokenToWhitelist(_tokens[i]);
            }
            vm.stopPrank();
            vm.startPrank(address(scw));
        }

        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: sk.pub,
            validAfter: _validAfter,
            validUntil: _validUntil,
            solver: solver.pub,
            bidHash: DUMMY_BID_HASH,
            tokenData: tokenAmounts
        });

        bytes memory enableSessionKeyData = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );

        // Create user operation with proper signature format
        (PackedUserOperation memory op, bytes32[] memory proof, bytes32 root) =
            _createUserOpWithResourceLock(address(scw), eoa, address(rlv), opCalldata, rl, true);
        bytes memory sig = _sign(root, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(root), _packProofForSignature(proof));

        // Fund the wallet with enough ETH for gas fees
        vm.deal(address(scw), 1 ether);

        // Execute the user operation
        _executeUserOp(op);

        // Get session key data and validate
        SessionData memory retrievedData = cam.getSessionKeyData(sk.pub);
        assertEq(retrievedData.validAfter, _validAfter);
        assertEq(retrievedData.validUntil, _validUntil);

        // Get locked token data and validate
        ICAM.LockedToken[] memory lockedTokens = cam.getLockedTokensForSessionKey(sk.pub);
        assertEq(lockedTokens.length, _tokens.length);
        for (uint256 i; i < _tokens.length; ++i) {
            assertEq(lockedTokens[i].token, _tokens[i]);
            assertEq(lockedTokens[i].lockedAmount, _amounts[i]);
            assertEq(lockedTokens[i].claimedAmount, 0);
        }
    }

    function testFuzz_disableSessionKey(string memory _sessionKey, uint256[3] memory _lockedAmounts)
        public
        withRequiredModules
    {
        User memory sk = _createUser(_sessionKey);

        for (uint256 i; i < _lockedAmounts.length; ++i) {
            vm.assume(_lockedAmounts[i] > 0 && _lockedAmounts[i] < 1000 ether);
        }

        usdc.mint(address(scw), _lockedAmounts[0]);
        dai.mint(address(scw), _lockedAmounts[1]);
        usdt.mint(address(scw), _lockedAmounts[2]);
        usdc.approve(address(cam), _lockedAmounts[0]);
        dai.approve(address(cam), _lockedAmounts[1]);
        usdt.approve(address(cam), _lockedAmounts[2]);

        // Enable session key in a separate block to reduce stack depth
        {
            TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
            for (uint256 i; i < tokens.length; ++i) {
                tokenAmounts[i] = TokenData(tokens[i], _lockedAmounts[i]);
            }

            ResourceLock memory rl = ResourceLock({
                chainId: block.chainid,
                smartWallet: address(scw),
                sessionKey: sk.pub,
                validAfter: validAfter,
                validUntil: validUntil,
                solver: solver.pub,
                bidHash: DUMMY_BID_HASH,
                tokenData: tokenAmounts
            });

            bytes memory enableCalldata = abi.encodeCall(
                IERC7579Account.execute,
                (
                    ModeLib.encodeSimpleSingle(),
                    ExecutionLib.encodeSingle(
                        address(cam), 0, abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl))
                    )
                )
            );

            (PackedUserOperation memory enableOp, bytes32[] memory proof, bytes32 root) =
                _createUserOpWithResourceLock(address(scw), eoa, address(rlv), enableCalldata, rl, true);

            enableOp.signature = bytes.concat(_sign(root, eoa), abi.encodePacked(root), _packProofForSignature(proof));

            vm.deal(address(scw), 1 ether);
            _executeUserOp(enableOp);
        }

        // Claim tokens in a separate block to reduce stack depth
        {
            Execution[] memory batch = new Execution[](3);
            batch[0] = Execution({
                target: address(cam),
                value: 0,
                callData: _createClaimExecution(sk.pub, address(usdc), _lockedAmounts[0])
            });
            batch[1] = Execution({
                target: address(cam),
                value: 0,
                callData: _createClaimExecution(sk.pub, address(dai), _lockedAmounts[1])
            });
            batch[2] = Execution({
                target: address(cam),
                value: 0,
                callData: _createClaimExecution(sk.pub, address(usdt), _lockedAmounts[2])
            });

            bytes memory opCalldata =
                abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
            (PackedUserOperation memory op,) = _createUserOpWithSignature(sk, address(scw), address(cam), opCalldata);
            _executeUserOp(op);
        }

        // Disable the session key
        vm.startPrank(address(scw));
        cam.disableSessionKey(sk.pub);
        vm.stopPrank();
        // Verify results
        assertEq(cam.getSessionKeysByWallet().length, 0);
        assertEq(cam.sessionKeyToWallet(sk.pub), address(0), "Session key should be disabled");
        assertEq(cam.getLockedTokensForSessionKey(sk.pub).length, 0);
    }

    function testFuzz_claimingTokensBySolver(uint256[3] memory _claimAmounts) public withRequiredModules {
        for (uint256 i; i < _claimAmounts.length; ++i) {
            vm.assume(_claimAmounts[i] > 0 && _claimAmounts[i] < 1000 ether);
        }

        usdc.mint(address(scw), _claimAmounts[0]);
        dai.mint(address(scw), _claimAmounts[1]);
        usdt.mint(address(scw), _claimAmounts[2]);
        usdc.approve(address(cam), _claimAmounts[0]);
        dai.approve(address(cam), _claimAmounts[1]);
        usdt.approve(address(cam), _claimAmounts[2]);

        // Enable session key
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], _claimAmounts[i]);
        }

        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: sessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            solver: solver.pub,
            bidHash: DUMMY_BID_HASH,
            tokenData: tokenAmounts
        });

        bytes memory enableSessionKeyData = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );

        // Create user operation with proper signature format
        (PackedUserOperation memory op, bytes32[] memory proof, bytes32 root) =
            _createUserOpWithResourceLock(address(scw), eoa, address(rlv), opCalldata, rl, true);
        bytes memory sig = _sign(root, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(root), _packProofForSignature(proof));

        // Fund the wallet with enough ETH for gas fees
        vm.deal(address(scw), 1 ether);

        // Execute the user operation
        _executeUserOp(op);

        // Claim tokens by solver
        _claimTokensBySolver(eoa, scw, sessionKey, _claimAmounts[0], _claimAmounts[1], _claimAmounts[2]);

        // Verify tokens have been claimed
        ICAM.LockedToken[] memory lockedTokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
        for (uint256 i; i < 3; ++i) {
            assertEq(lockedTokens[i].claimedAmount, _claimAmounts[i]);
        }
    }

    function testFuzz_validateUserOp_passesWithApproveSelector(
        address tokenAddress,
        address spender,
        uint256 approveAmount
    ) public withRequiredModules {
        vm.assume(tokenAddress != address(0));
        vm.assume(spender != address(0));
        vm.assume(approveAmount > 0);

        _enableSessionKey(address(scw));

        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, spender, approveAmount);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(tokenAddress, 0, approveData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);

        uint256 result = cam.validateUserOp(op, hash);
        assertTrue(result != VALIDATION_FAILED, "Validation should pass with approve selector for any token");
    }

    function testFuzz_validateUserOp_passesWithMixedBatch(uint256 approveAmount, uint256 claimAmount)
        public
        withRequiredModules
    {
        vm.assume(approveAmount > 0 && approveAmount < 1000 ether);
        vm.assume(claimAmount > 0 && claimAmount < 1000 ether);

        _enableSessionKey(address(scw));

        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, address(im), approveAmount);
        bytes memory claimData = _createClaimExecution(sessionKey.pub, address(usdc), claimAmount);

        Execution[] memory batch = new Execution[](2);
        batch[0] = Execution({target: address(usdc), value: 0, callData: approveData});
        batch[1] = Execution({target: address(cam), value: 0, callData: claimData});

        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);

        uint256 result = cam.validateUserOp(op, hash);
        assertTrue(result != VALIDATION_FAILED, "Validation should pass with mixed approve/claim batch");
    }

    function testFuzz_validateUserOp_passesWithMultipleApprovesInBatch() public withRequiredModules {
        _enableSessionKey(address(scw));

        bytes memory approveUsdc = abi.encodeWithSelector(IERC20.approve.selector, address(im), amounts[0]);
        bytes memory approveDai = abi.encodeWithSelector(IERC20.approve.selector, address(im), amounts[1]);

        Execution[] memory batch = new Execution[](2);
        batch[0] = Execution({target: address(usdc), value: 0, callData: approveUsdc});
        batch[1] = Execution({target: address(dai), value: 0, callData: approveDai});

        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);

        uint256 result = cam.validateUserOp(op, hash);
        assertTrue(result != VALIDATION_FAILED, "Validation should pass with multiple approve calls");
    }

    function testFuzz_validateUserOp_passesWithZeroAmountApprove() public withRequiredModules {
        _enableSessionKey(address(scw));

        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, address(im), 0);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdc), 0, approveData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);

        uint256 result = cam.validateUserOp(op, hash);
        assertTrue(result != VALIDATION_FAILED, "Validation should pass with zero amount approve");
    }

    function testFuzz_validateUserOp_failsWithReplayedSignature() public withRequiredModules {
        _enableSessionKey(address(scw));

        bytes memory claimData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, claimData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);

        // First validation should pass
        uint256 result1 = cam.validateUserOp(op, hash);
        assertTrue(result1 != VALIDATION_FAILED);

        // Replay same userOp with different hash should fail
        uint256 result2 = cam.validateUserOp(op, keccak256("different_hash"));
        assertEq(result2, VALIDATION_FAILED, "Should fail signature validation on replay");
    }

    function testFuzz_validateUserOp_failsWithInvalidSignatureLength(uint256 sigLength) public withRequiredModules {
        vm.assume(sigLength != 65 && sigLength < 200); // Avoid extremely large values

        _enableSessionKey(address(scw));

        bytes memory claimData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, claimData))
        );

        PackedUserOperation memory op = PackedUserOperation({
            sender: address(scw),
            nonce: 0,
            initCode: "",
            callData: opCalldata,
            accountGasLimits: bytes32(uint256(2000000) << 128 | uint256(2000000)),
            preVerificationGas: 100000,
            gasFees: bytes32(uint256(1000000000) << 128 | uint256(1000000000)),
            paymasterAndData: "",
            signature: new bytes(sigLength) // Invalid length
        });

        uint256 result = cam.validateUserOp(op, keccak256("test"));
        assertEq(result, VALIDATION_FAILED, "Should fail with invalid signature length");
    }

    function testFuzz_validateUserOp_failsWithUnauthorizedSessionKey() public withRequiredModules {
        _enableSessionKey(address(scw));

        // Create different session key that wasn't enabled
        User memory unauthorizedKey = _createUser("unauthorized");

        bytes memory claimData = _createClaimExecution(unauthorizedKey.pub, address(usdc), amounts[0]);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, claimData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(unauthorizedKey, address(scw), address(cam), opCalldata);

        uint256 result = cam.validateUserOp(op, hash);
        assertEq(result, VALIDATION_FAILED, "Should fail with unauthorized session key");
    }
}
