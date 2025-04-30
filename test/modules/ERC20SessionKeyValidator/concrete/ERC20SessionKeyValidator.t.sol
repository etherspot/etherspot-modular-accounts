// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {ExecutionLib} from "../../../../src/libraries/ExecutionLib.sol";
import {ModeLib} from "../../../../src/libraries/ModeLib.sol";
import {MODULE_TYPE_VALIDATOR} from "../../../../src/types/Constants.sol";
import {Execution} from "../../../../src/types/Structs.sol";
import "../../../../src/test/TestERC20.sol";
import "../../../../src/test/TestUSDC.sol";
import "../../../ModularTestBase.sol";

contract ERC20SessionKeyValidatorTest is ModularTestBase {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    User otherSessionKey;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ERC20SKV_ModuleInstalled(address wallet);
    event ERC20SKV_ModuleUninstalled(address wallet);
    event ERC20SKV_SessionKeyEnabled(address sessionKey, address wallet);
    event ERC20SKV_SessionKeyDisabled(address sessionKey, address wallet);
    event ERC20SKV_SessionKeyPaused(address sessionKey, address wallet);
    event ERC20SKV_SessionKeyUnpaused(address sessionKey, address wallet);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        _testInit();
        otherSessionKey = _createUser("Other Session Key");
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(ERC20_SESSION_KEY_VALIDATOR), hex"");
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    function test_installModule() public {
        assertTrue(SCW.isModuleInstalled(1, address(ERC20_SESSION_KEY_VALIDATOR), ""));
    }

    function test_uninstallModule() public {
        assertTrue(SCW.isModuleInstalled(1, address(ERC20_SESSION_KEY_VALIDATOR), ""));
        // Check emitted event
        vm.expectEmit(false, false, false, true);
        emit ERC20SKV_ModuleUninstalled(address(SCW));
        _uninstallModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(ERC20_SESSION_KEY_VALIDATOR), hex"");
        // Check session key validator is uninstalled
        assertFalse(SCW.isModuleInstalled(1, address(ERC20_SESSION_KEY_VALIDATOR), ""));
    }

    function test_enableSessionKey() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        // Check emitted event
        vm.expectEmit(false, false, false, true);
        emit ERC20SKV_SessionKeyEnabled(sessionKey.pub, eoa.pub);
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Session should be enabled
        assertFalse(ERC20_SESSION_KEY_VALIDATOR.getSessionKeyData(sessionKey.pub).validUntil == 0);
        vm.stopPrank();
    }

    function test_enableSessionKey_RevertIf_InvalidSessionKey() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            address(0),
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_InvalidSessionKey.selector, hex"");
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        vm.stopPrank();
    }

    function test_enableSessionKey_RevertIf_SessionKeyAlreadyExists() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_SessionKeyAlreadyExists.selector, abi.encode(sessionKey.pub));
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        vm.stopPrank();
    }

    function test_enableSessionKey_RevertIf_InvalidToken() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(0),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_InvalidToken.selector, hex"");
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        vm.stopPrank();
    }

    function test_enableSessionKey_RevertIf_InvalidFunctionSelector() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            bytes4(0),
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_InvalidFunctionSelector.selector, hex"");
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        vm.stopPrank();
    }

    function test_enableSessionKey_InvalidSpendingLimit() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(0),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_InvalidSpendingLimit.selector, hex"");

        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        vm.stopPrank();
    }

    function test_enableSessionKey_RevertIf_InvalidValidAfter() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(0),
            uint48(block.timestamp + 1 days)
        );
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_InvalidValidAfter.selector, abi.encode(uint48(0)));

        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        vm.stopPrank();
    }

    function test_fail_enableSessionKey_invalidValidUntil() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp + 1),
            uint48(0)
        );
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_InvalidValidUntil.selector, abi.encode(uint48(0)));
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        vm.stopPrank();
    }

    function test_disableSessionKey() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        assertEq(ERC20_SESSION_KEY_VALIDATOR.getAssociatedSessionKeys().length, 1);
        // Session should be enabled
        assertFalse(ERC20_SESSION_KEY_VALIDATOR.getSessionKeyData(sessionKey.pub).validUntil == 0);
        // Check emitted event
        vm.expectEmit(false, false, false, true);
        emit ERC20SKV_SessionKeyDisabled(sessionKey.pub, eoa.pub);
        // Disable session
        ERC20_SESSION_KEY_VALIDATOR.disableSessionKey(sessionKey.pub);
        // Session should now be disabled
        assertTrue(ERC20_SESSION_KEY_VALIDATOR.getSessionKeyData(sessionKey.pub).validUntil == 0);
        assertEq(ERC20_SESSION_KEY_VALIDATOR.getAssociatedSessionKeys().length, 0);
        vm.stopPrank();
    }

    function test_rotateSessionKey() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        assertFalse(ERC20_SESSION_KEY_VALIDATOR.getSessionKeyData(sessionKey.pub).validUntil == 0);
        // Rotate session key
        bytes memory newSessionData = abi.encodePacked(
            otherSessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(2),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.rotateSessionKey(sessionKey.pub, newSessionData);
        assertFalse(ERC20_SESSION_KEY_VALIDATOR.getSessionKeyData(otherSessionKey.pub).validUntil == 0);
        assertTrue(ERC20_SESSION_KEY_VALIDATOR.getSessionKeyData(sessionKey.pub).validUntil == 0);
        vm.stopPrank();
    }

    function test_rotateSessionKey_RevertIf_InvalidNewSessionData() public {
        vm.startPrank(eoa.pub);
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        bytes memory invalidNewSessionData = abi.encodePacked(address(0), address(0), bytes4(0), uint256(0), uint48(0));
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_InvalidSessionKey.selector, hex"");
        ERC20_SESSION_KEY_VALIDATOR.rotateSessionKey(sessionKey.pub, invalidNewSessionData);
        vm.stopPrank();
    }

    function test_rotateSessionKey_RevertIf_NonExistentKey() public {
        vm.startPrank(eoa.pub);
        bytes memory newSessionData = abi.encodePacked(
            otherSessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_SessionKeyDoesNotExist.selector, abi.encode(sessionKey.pub));
        ERC20_SESSION_KEY_VALIDATOR.rotateSessionKey(sessionKey.pub, newSessionData);
        vm.stopPrank();
    }

    function test_pass_toggleSessionKeyPause() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Session should be enabled
        assertTrue(ERC20_SESSION_KEY_VALIDATOR.isSessionKeyLive(sessionKey.pub));
        // Disable session
        vm.expectEmit(false, false, false, true);
        emit ERC20SKV_SessionKeyPaused(sessionKey.pub, eoa.pub);
        ERC20_SESSION_KEY_VALIDATOR.toggleSessionKeyPause(sessionKey.pub);
        // Session should now be disabled
        assertFalse(ERC20_SESSION_KEY_VALIDATOR.isSessionKeyLive(sessionKey.pub));
        vm.expectEmit(false, false, false, true);
        emit ERC20SKV_SessionKeyUnpaused(sessionKey.pub, eoa.pub);
        ERC20_SESSION_KEY_VALIDATOR.toggleSessionKeyPause(sessionKey.pub);
        vm.stopPrank();
    }

    function test_toggleSessionKeyPause_RevertIf_NonExistentKey() public {
        vm.startPrank(eoa.pub);
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_SessionKeyDoesNotExist.selector, abi.encode(sessionKey.pub));
        ERC20_SESSION_KEY_VALIDATOR.toggleSessionKeyPause(sessionKey.pub);
        vm.stopPrank();
    }

    function test_getAssociatedSessionKeys() public {
        vm.startPrank(eoa.pub);
        bytes memory sessionData1 = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        bytes memory sessionData2 = abi.encodePacked(
            otherSessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(2),
            uint48(block.timestamp),
            uint48(block.timestamp + 3 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData1);
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData2);
        address[] memory sessionKeys = ERC20_SESSION_KEY_VALIDATOR.getAssociatedSessionKeys();
        assertEq(sessionKeys.length, 2);
        vm.stopPrank();
    }

    function test_getSessionKeyData() public {
        vm.startPrank(eoa.pub);
        uint48 validUntil = uint48(block.timestamp + 1 days);
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            validUntil
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        ERC20SessionKeyValidator.SessionData memory data = ERC20_SESSION_KEY_VALIDATOR.getSessionKeyData(sessionKey.pub);
        assertEq(data.token, address(USDT));
        assertEq(data.funcSelector, IERC20.transferFrom.selector);
        assertEq(data.validUntil, validUntil);
        vm.stopPrank();
    }

    function test_validateUserOp() public {
        vm.startPrank(address(SCW));
        USDT.mint(address(SCW), 10 ether);
        assertEq(USDT.balanceOf(address(SCW)), 10 ether);
        USDT.approve(address(SCW), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(USDT), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        // Validation should succeed
        _executeUserOp(op);
        // Bob has 100 USDT to begin with
        assertEq(USDT.balanceOf(bob.pub), 105 ether);
        vm.stopPrank();
    }

    function test_validateUserOp_RevertIf_InvalidSessionKey() public {
        vm.startPrank(address(SCW));
        USDT.mint(address(SCW), 10 ether);
        USDT.approve(address(SCW), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );

        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(USDT), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        // Validation should fail
        ERC20_SESSION_KEY_VALIDATOR.disableSessionKey(sessionKey.pub);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_validateUserOp_RevertIf_InvalidFunctionSelector() public {
        vm.startPrank(address(SCW));
        // Construct and enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transfer.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Construct invalid selector user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(USDT), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_validateUserOp_RevertIf_SessionKeySpentLimitExceeded() public {
        vm.startPrank(address(SCW));
        // Construct and enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(1 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Construct invalid selector user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(2 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(USDT), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_usingExecuteSingle() public {
        vm.startPrank(address(SCW));
        USDT.mint(address(SCW), 10 ether);
        USDT.approve(address(SCW), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(USDT), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _executeUserOp(op);
        vm.stopPrank();
        // Bob already has a balance of 100 USDT
        assertEq(USDT.balanceOf(bob.pub), 105 ether);
    }

    function test_usingExecuteBatch() public {
        vm.startPrank(address(SCW));
        USDT.mint(address(SCW), 10 ether);
        USDT.approve(address(SCW), 10 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(2 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(2 ether));
        // Construct Executions - x5 of 2 ether each
        Execution[] memory executions = new Execution[](5);
        Execution memory executionData = Execution({target: address(USDT), value: 0, callData: data});
        for (uint256 i; i < executions.length; ++i) {
            executions[i] = executionData;
        }
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _executeUserOp(op);
        vm.stopPrank();
        // Bob already has a balance of 100 USDT
        assertEq(USDT.balanceOf(bob.pub), 110 ether);
    }

    function test_usingMultipleSessionKeys() public {
        vm.startPrank(address(SCW));
        // Setup Session Keys
        User memory approveSessionKey = _createUser("Approve Session Key");
        User memory transferSessionKey = _createUser("Transfer Session Key");
        // ERC20 mint
        USDT.mint(address(SCW), 10 ether);
        // Enable valid sessions
        // Session 1 - approve
        bytes memory approveSessionData = abi.encodePacked(
            approveSessionKey.pub,
            address(USDT),
            IERC20.approve.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(approveSessionData);
        // Session 2 - transfer
        bytes memory transferSessionData = abi.encodePacked(
            transferSessionKey.pub,
            address(USDT),
            IERC20.transfer.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(transferSessionData);
        // Construct user op data
        // Approve
        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, address(SCW), uint256(5 ether));
        // Transfer
        bytes memory transferData = abi.encodeWithSelector(IERC20.transfer.selector, bob.pub, uint256(2 ether));
        // Construct UserOp.calldatas
        bytes memory approveCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(USDT), uint256(0), approveData))
        );
        bytes memory transferCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(USDT), uint256(0), transferData))
        );
        // First UserOp - Approve
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = approveCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, approveSessionKey);
        _executeUserOp(op);
        // Second UserOp - Transfer
        op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = transferCalldata;
        hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, transferSessionKey);
        _executeUserOp(op);
        vm.stopPrank();
        // Bob already has balance of 100 USDT
        assertEq(USDT.balanceOf(bob.pub), 102 ether);
    }

    function test_validateUserOp_RevertIf_DifferentSessionKeyAsSigner() public {
        vm.startPrank(address(SCW));
        USDT.mint(address(SCW), 10 ether);
        USDT.approve(address(SCW), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Enable another session to act as signer (use transfer instead of transferFrom)
        bytes memory anotherSessionData = abi.encodePacked(
            otherSessionKey.pub,
            address(USDT),
            IERC20.transfer.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(anotherSessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(USDT), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, otherSessionKey);
        // Validation should fail - signed with different valid session key
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_validateUserOp_RevertIf_SessionSignedByOwnerEOA() public {
        vm.startPrank(address(SCW));
        USDT.mint(address(SCW), 10 ether);
        USDT.approve(address(SCW), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(USDT), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa);
        // Validation should fail - signed with different valid session key
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_validateUserOp_RevertIf_SessionSignedByInvalidKey() public {
        vm.startPrank(address(SCW));
        USDT.mint(address(SCW), 10 ether);
        USDT.approve(address(SCW), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(USDT), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, otherSessionKey);
        // Validation should fail - signed with different valid session key
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
    }

    function test_validUserOp_UsingWeiAmounts() public {
        vm.startPrank(address(SCW));
        // Test for successful transfer for 100000000000000 wei (0.0001 ether)
        // Test for failing transfer for 100000000000001 wei
        USDT.mint(address(SCW), 10 ether);
        USDT.approve(address(SCW), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(100000000000000),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(100000000000000));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(USDT), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _executeUserOp(op);
        // Bob already has balance of 100 USDT
        assertEq(USDT.balanceOf(bob.pub), 100000100000000000000);
        // Test for invalid Wei amount - should revert
        // Construct user op data
        data = abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(100000000000001));
        opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(USDT), uint256(0), data))
        );
        op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = opCalldata;
        hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        // Validation should fail - signed with different valid session key
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_validateUserOp_UsingTestUSDC() public {
        vm.startPrank(address(SCW));
        // Mint 10 USDC to SCW
        USDC.mint(address(SCW), 10000000);
        USDC.approve(address(SCW), 10000000);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDC),
            IERC20.transferFrom.selector,
            uint256(10000000),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(10000001));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(USDC), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_validateUserOp_RevertIf_BatchLastExecBad() public {
        vm.startPrank(address(SCW));
        // Mint and approve more than required for batch tx
        USDT.mint(address(SCW), 11 ether);
        USDT.approve(address(SCW), 11 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(USDT),
            IERC20.transferFrom.selector,
            uint256(2000000000000000000),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        ERC20_SESSION_KEY_VALIDATOR.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(2000000000000000000));
        Execution[] memory executions = new Execution[](5);
        Execution memory executionData = Execution({target: address(USDT), value: 0, callData: data});
        for (uint256 i; i < 4; ++i) {
            executions[i] = executionData;
        }
        // Construct bad data for last tx in batch
        bytes memory badData =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(SCW), bob.pub, uint256(2000000000000000001));
        // Bad execution data
        executions[4] = Execution({target: address(USDT), value: 0, callData: badData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ERC20_SESSION_KEY_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
    }
}
