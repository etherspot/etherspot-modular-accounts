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

    function testFuzz_claimingTokensBySolver(uint256[3] memory _claimAmounts) public withRequiredModules {
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
        _claimTokensBySolver(eoa, scw, sessionKey, _claimAmounts[0], _claimAmounts[1], _claimAmounts[2]);

        // Verify tokens have been claimed
        ICAM.LockedToken[] memory lockedTokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
        for (uint256 i; i < 3; ++i) {
            assertEq(lockedTokens[i].claimedAmount, _claimAmounts[i]);
        }
    }
}
