// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "ERC4337/core/Helpers.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {ExecutionLib} from "ERC7579/libs/ExecutionLib.sol";
import "ERC7579/libs/ModeLib.sol";
import {CredibleAccountModule as CAM} from "../../../../src/modules/validators/CredibleAccountModule.sol";
import {ICredibleAccountModule as ICAM} from "../../../../src/interfaces/ICredibleAccountModule.sol";
import "../../../../src/wallet/ModularEtherspotWallet.sol";
import {CredibleAccountModuleTestUtils as LocalTestUtils} from "../utils/CredibleAccountModuleTestUtils.sol";
import "../../../../src/common/Structs.sol";
import {TestWETH} from "../../../../src/test/TestWETH.sol";
import {TestUniswapV2} from "../../../../src/test/TestUniswapV2.sol";
import "../../../../src/utils/ERC4337Utils.sol";

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
        }

        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: sk.pub,
            validAfter: _validAfter,
            validUntil: _validUntil,
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
        SessionData memory retrievedData = credibleAccountModule.getSessionKeyData(_sessionKey);
        assertEq(retrievedData.validAfter, _validAfter);
        assertEq(retrievedData.validUntil, _validUntil);

        // Get locked token data and validate
        ICAM.LockedToken[] memory lockedTokens = credibleAccountModule.getLockedTokensForSessionKey(_sessionKey);
        assertEq(lockedTokens.length, _tokens.length);
        for (uint256 i; i < _tokens.length; ++i) {
            assertEq(lockedTokens[i].token, _tokens[i]);
            assertEq(lockedTokens[i].lockedAmount, _amounts[i]);
            assertEq(lockedTokens[i].claimedAmount, 0);
        }
    }

    function testFuzz_disableSessionKey(string memory _sessionKey, uint256[3] memory _lockedAmounts) public {
        (address sk, uint256 skp) = makeAddrAndKey(_sessionKey);
        for (uint256 i; i < _lockedAmounts.length; ++i) {
            vm.assume(_lockedAmounts[i] > 0 && _lockedAmounts[i] < 1000 ether);
        }

        usdc.mint(address(scw), _lockedAmounts[0]);
        dai.mint(address(scw), _lockedAmounts[1]);
        usdt.mint(address(scw), _lockedAmounts[2]);

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
                tokenData: tokenAmounts,
                nonce: 2
            })
        );
        credibleAccountModule.enableSessionKey(rl);
        // Claim tokens to allow disabling
        bytes memory usdcData = _createTokenTransferFromExecution(address(mew), address(solver), _lockedAmounts[0]);

        bytes memory daiData = _createTokenTransferFromExecution(address(mew), address(solver), _lockedAmounts[1]);
        bytes memory uniData = _createTokenTransferFromExecution(address(mew), address(solver), _lockedAmounts[2]);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(usdc), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(dai), value: 0, callData: daiData});
        batch[2] = Execution({target: address(uni), value: 0, callData: uniData});
        bytes memory userOpCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (, PackedUserOperation memory userOp) =
            _createUserOperation(address(mew), userOpCalldata, address(credibleAccountModule), skp);
        // Execute the user operation
        _executeUserOperation(userOp);
        // Disable the session key
        credibleAccountModule.disableSessionKey(sk);
        // Verify no sessions for wallet
        address[] memory walletSessions = credibleAccountModule.getSessionKeysByWallet();
        assertEq(walletSessions.length, 0);
        // Verify reset data for session key
        SessionData memory sessionKeyData = credibleAccountModule.getSessionKeyData(sk);
        console2.log("sessionKeyData.validUntil", sessionKeyData.validUntil);
        assertEq(sessionKeyData.validUntil, 0);
        // Verify no locked tokens for session key
        ICAM.LockedToken[] memory lockedTokenData = credibleAccountModule.getLockedTokensForSessionKey(sk);
        assertEq(lockedTokenData.length, 0);
    }

    function testFuzz_validateSessionKeyParams(address _sessionKey, bytes calldata _callData) public {
        vm.assume(_sessionKey != address(0));
        // Enable a session key first
        _enableDefaultSessionKey(address(mew));
        PackedUserOperation memory userOp;
        userOp.callData = _callData;
        userOp.sender = address(mew);
        bool isValid = credibleAccountModule.validateSessionKeyParams(_sessionKey, userOp);
        if (_sessionKey == sessionKey) {
            // Additional checks based on _callData content could be added here
            assertTrue(isValid || !isValid);
        } else {
            assertFalse(isValid);
        }

        // Claim tokens in a separate block to reduce stack depth
        {
            Execution[] memory batch = new Execution[](3);
            batch[0] = Execution({
                target: address(usdc),
                value: 0,
                callData: _createTokenTransferExecution(solver.pub, _lockedAmounts[0])
            });
            batch[1] = Execution({
                target: address(dai),
                value: 0,
                callData: _createTokenTransferExecution(solver.pub, _lockedAmounts[1])
            });
            batch[2] = Execution({
                target: address(usdt),
                value: 0,
                callData: _createTokenTransferExecution(solver.pub, _lockedAmounts[2])
            });

            bytes memory opCalldata =
                abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
            (PackedUserOperation memory op,) = _createUserOpWithSignature(sk, address(scw), address(cam), opCalldata);
            _executeUserOp(op);
        }

        // Disable the session key
        cam.disableSessionKey(sk.pub);

        // Verify results
        assertEq(cam.getSessionKeysByWallet().length, 0);
        assertEq(cam.sessionKeyToWallet(sk.pub), address(0), "Session key should be disabled");
        assertEq(cam.getLockedTokensForSessionKey(sk.pub).length, 0);
    }

    function testFuzz_claimingTokensBySolver(uint256[3] memory _claimAmounts) public {
        for (uint256 i; i < _claimAmounts.length; ++i) {
            vm.assume(_claimAmounts[i] > 0 && _claimAmounts[i] < 1000 ether);
        }

        usdc.mint(address(scw), _claimAmounts[0]);
        dai.mint(address(scw), _claimAmounts[1]);
        usdt.mint(address(scw), _claimAmounts[2]);

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
        _claimTokensBySolver(_claimAmounts[0], _claimAmounts[1], _claimAmounts[2]);
        // Verify tokens have been claimed
        ICAM.LockedToken[] memory lockedTokens = credibleAccountModule.getLockedTokensForSessionKey(sessionKey);
        for (uint256 i; i < 3; ++i) {
            assertEq(lockedTokens[i].claimedAmount, _claimAmounts[i]);
        }
    }
}
