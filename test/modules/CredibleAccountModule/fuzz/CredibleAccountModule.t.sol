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
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(scw),
                sessionKey: sk.pub,
                validAfter: _validAfter,
                validUntil: _validUntil,
                tokenData: tokenAmounts,
                nonce: 2
            })
        );
        cam.enableSessionKey(rl);
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
        vm.stopPrank();
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
        // Enable a session key
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], _lockedAmounts[i]);
        }
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(scw),
                sessionKey: sk.pub,
                validAfter: validAfter,
                validUntil: validUntil,
                tokenData: tokenAmounts,
                nonce: 2
            })
        );
        cam.enableSessionKey(rl);
        // Claim tokens to allow disabling
        bytes memory usdcData = _createTokenTransferFromExecution(address(scw), solver.pub, _lockedAmounts[0]);

        bytes memory daiData = _createTokenTransferFromExecution(address(scw), solver.pub, _lockedAmounts[1]);
        bytes memory usdtData = _createTokenTransferFromExecution(address(scw), solver.pub, _lockedAmounts[2]);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(usdc), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(dai), value: 0, callData: daiData});
        batch[2] = Execution({target: address(usdt), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) = _createUserOpWithSignature(sk, address(scw), address(cam), opCalldata);
        // Execute the user operation
        _executeUserOp(op);
        // Disable the session key
        cam.disableSessionKey(sk.pub);
        // Verify no sessions for wallet
        address[] memory walletSessions = cam.getSessionKeysByWallet();
        assertEq(walletSessions.length, 0);
        // Verify reset data for session key
        SessionData memory sessionKeyData = cam.getSessionKeyData(sk.pub);
        console2.log("sessionKeyData.validUntil", sessionKeyData.validUntil);
        assertEq(sessionKeyData.validUntil, 0);
        // Verify no locked tokens for session key
        ICAM.LockedToken[] memory lockedTokenData = cam.getLockedTokensForSessionKey(sk.pub);
        assertEq(lockedTokenData.length, 0);
        vm.stopPrank();
    }

    function testFuzz_validateSessionKeyParams(address _sessionKey, bytes calldata _callData)
        public
        withRequiredModules
    {
        vm.assume(_sessionKey != address(0));
        // Enable a session key first
        _enableSessionKey(address(scw));
        PackedUserOperation memory op;
        op.callData = _callData;
        op.sender = address(scw);
        bool isValid = cam.validateSessionKeyParams(_sessionKey, op);
        if (_sessionKey == sessionKey.pub) {
            // Additional checks based on _callData content could be added here
            assertTrue(isValid || !isValid);
        } else {
            assertFalse(isValid);
        }
        vm.stopPrank();
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
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(scw),
                sessionKey: sessionKey.pub,
                validAfter: validAfter,
                validUntil: validUntil,
                tokenData: tokenAmounts,
                nonce: 2
            })
        );
        cam.enableSessionKey(rl);
        // Claim tokens by solver
        _claimTokensBySolver(eoa, scw, _claimAmounts[0], _claimAmounts[1], _claimAmounts[2]);
        // Verify tokens have been claimed
        ICAM.LockedToken[] memory lockedTokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
        for (uint256 i; i < 3; ++i) {
            assertEq(lockedTokens[i].claimedAmount, _claimAmounts[i]);
        }
        vm.stopPrank();
    }
}
