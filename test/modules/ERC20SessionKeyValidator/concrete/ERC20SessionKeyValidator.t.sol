// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {Execution} from "ERC7579/interfaces/IERC7579Account.sol";
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
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(erc20skv), hex"");
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    function test_installModule() public {
        assertTrue(scw.isModuleInstalled(1, address(erc20skv), ""));
    }

    function test_uninstallModule() public {
        assertTrue(scw.isModuleInstalled(1, address(erc20skv), ""));
        // Check emitted event
        vm.expectEmit(false, false, false, true);
        emit ERC20SKV_ModuleUninstalled(address(scw));
        _uninstallModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(erc20skv), hex"");
        // Check session key validator is uninstalled
        assertFalse(scw.isModuleInstalled(1, address(erc20skv), ""));
    }

    function test_enableSessionKey() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        // Check emitted event
        vm.expectEmit(false, false, false, true);
        emit ERC20SKV_SessionKeyEnabled(sessionKey.pub, eoa.pub);
        erc20skv.enableSessionKey(sessionData);
        // Session should be enabled
        assertFalse(erc20skv.getSessionKeyData(sessionKey.pub).validUntil == 0);
        vm.stopPrank();
    }

    function test_enableSessionKey_RevertIf_InvalidSessionKey() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            address(0),
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_InvalidSessionKey.selector, hex"");
        erc20skv.enableSessionKey(sessionData);
        vm.stopPrank();
    }

    function test_enableSessionKey_RevertIf_SessionKeyAlreadyExists() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_SessionKeyAlreadyExists.selector, abi.encode(sessionKey.pub));
        erc20skv.enableSessionKey(sessionData);
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
        erc20skv.enableSessionKey(sessionData);
        vm.stopPrank();
    }

    function test_enableSessionKey_RevertIf_InvalidFunctionSelector() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            bytes4(0),
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_InvalidFunctionSelector.selector, hex"");
        erc20skv.enableSessionKey(sessionData);
        vm.stopPrank();
    }

    function test_enableSessionKey_InvalidSpendingLimit() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(0),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_InvalidSpendingLimit.selector, hex"");

        erc20skv.enableSessionKey(sessionData);
        vm.stopPrank();
    }

    function test_enableSessionKey_RevertIf_InvalidValidAfter() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(0),
            uint48(block.timestamp + 1 days)
        );
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_InvalidValidAfter.selector, abi.encode(uint48(0)));

        erc20skv.enableSessionKey(sessionData);
        vm.stopPrank();
    }

    function test_fail_enableSessionKey_invalidValidUntil() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp + 1),
            uint48(0)
        );
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_InvalidValidUntil.selector, abi.encode(uint48(0)));
        erc20skv.enableSessionKey(sessionData);
        vm.stopPrank();
    }

    function test_disableSessionKey() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        assertEq(erc20skv.getAssociatedSessionKeys().length, 1);
        // Session should be enabled
        assertFalse(erc20skv.getSessionKeyData(sessionKey.pub).validUntil == 0);
        // Check emitted event
        vm.expectEmit(false, false, false, true);
        emit ERC20SKV_SessionKeyDisabled(sessionKey.pub, eoa.pub);
        // Disable session
        erc20skv.disableSessionKey(sessionKey.pub);
        // Session should now be disabled
        assertTrue(erc20skv.getSessionKeyData(sessionKey.pub).validUntil == 0);
        assertEq(erc20skv.getAssociatedSessionKeys().length, 0);
        vm.stopPrank();
    }

    function test_rotateSessionKey() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        assertFalse(erc20skv.getSessionKeyData(sessionKey.pub).validUntil == 0);
        // Rotate session key
        bytes memory newSessionData = abi.encodePacked(
            otherSessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(2),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.rotateSessionKey(sessionKey.pub, newSessionData);
        assertFalse(erc20skv.getSessionKeyData(otherSessionKey.pub).validUntil == 0);
        assertTrue(erc20skv.getSessionKeyData(sessionKey.pub).validUntil == 0);
        vm.stopPrank();
    }

    function test_rotateSessionKey_RevertIf_InvalidNewSessionData() public {
        vm.startPrank(eoa.pub);
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        bytes memory invalidNewSessionData = abi.encodePacked(address(0), address(0), bytes4(0), uint256(0), uint48(0));
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_InvalidSessionKey.selector, hex"");
        erc20skv.rotateSessionKey(sessionKey.pub, invalidNewSessionData);
        vm.stopPrank();
    }

    function test_rotateSessionKey_RevertIf_NonExistentKey() public {
        vm.startPrank(eoa.pub);
        bytes memory newSessionData = abi.encodePacked(
            otherSessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_SessionKeyDoesNotExist.selector, abi.encode(sessionKey.pub));
        erc20skv.rotateSessionKey(sessionKey.pub, newSessionData);
        vm.stopPrank();
    }

    function test_pass_toggleSessionKeyPause() public {
        vm.startPrank(eoa.pub);
        // Enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        // Session should be enabled
        assertTrue(erc20skv.isSessionKeyLive(sessionKey.pub));
        // Disable session
        vm.expectEmit(false, false, false, true);
        emit ERC20SKV_SessionKeyPaused(sessionKey.pub, eoa.pub);
        erc20skv.toggleSessionKeyPause(sessionKey.pub);
        // Session should now be disabled
        assertFalse(erc20skv.isSessionKeyLive(sessionKey.pub));
        vm.expectEmit(false, false, false, true);
        emit ERC20SKV_SessionKeyUnpaused(sessionKey.pub, eoa.pub);
        erc20skv.toggleSessionKeyPause(sessionKey.pub);
        vm.stopPrank();
    }

    function test_toggleSessionKeyPause_RevertIf_NonExistentKey() public {
        vm.startPrank(eoa.pub);
        _toRevert(ERC20SessionKeyValidator.ERC20SKV_SessionKeyDoesNotExist.selector, abi.encode(sessionKey.pub));
        erc20skv.toggleSessionKeyPause(sessionKey.pub);
        vm.stopPrank();
    }

    function test_getAssociatedSessionKeys() public {
        vm.startPrank(eoa.pub);
        bytes memory sessionData1 = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        bytes memory sessionData2 = abi.encodePacked(
            otherSessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(2),
            uint48(block.timestamp),
            uint48(block.timestamp + 3 days)
        );
        erc20skv.enableSessionKey(sessionData1);
        erc20skv.enableSessionKey(sessionData2);
        address[] memory sessionKeys = erc20skv.getAssociatedSessionKeys();
        assertEq(sessionKeys.length, 2);
        vm.stopPrank();
    }

    function test_getSessionKeyData() public {
        vm.startPrank(eoa.pub);
        uint48 validUntil = uint48(block.timestamp + 1 days);
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(100),
            uint48(block.timestamp),
            validUntil
        );
        erc20skv.enableSessionKey(sessionData);
        ERC20SessionKeyValidator.SessionData memory data = erc20skv.getSessionKeyData(sessionKey.pub);
        assertEq(data.token, address(usdt));
        assertEq(data.funcSelector, IERC20.transferFrom.selector);
        assertEq(data.validUntil, validUntil);
        vm.stopPrank();
    }

    function test_validateUserOp() public {
        vm.startPrank(address(scw));
        usdt.mint(address(scw), 10 ether);
        assertEq(usdt.balanceOf(address(scw)), 10 ether);
        usdt.approve(address(scw), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdt), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(scw), address(erc20skv));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        // Validation should succeed
        _executeUserOp(op);
        // Bob has 100 USDT to begin with
        assertEq(usdt.balanceOf(bob.pub), 105 ether);
        vm.stopPrank();
    }

    function test_validateUserOp_RevertIf_InvalidSessionKey() public {
        vm.startPrank(address(scw));
        usdt.mint(address(scw), 10 ether);
        usdt.approve(address(scw), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );

        erc20skv.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdt), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(scw), address(erc20skv));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        // Validation should fail
        erc20skv.disableSessionKey(sessionKey.pub);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_validateUserOp_RevertIf_InvalidFunctionSelector() public {
        vm.startPrank(address(scw));
        // Construct and enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transfer.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        // Construct invalid selector user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdt), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(scw), address(erc20skv));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_validateUserOp_RevertIf_SessionKeySpentLimitExceeded() public {
        vm.startPrank(address(scw));
        // Construct and enable session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(1 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        // Construct invalid selector user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(2 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdt), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(scw), address(erc20skv));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_usingExecuteSingle() public {
        vm.startPrank(address(scw));
        usdt.mint(address(scw), 10 ether);
        usdt.approve(address(scw), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdt), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(scw), address(erc20skv));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _executeUserOp(op);
        vm.stopPrank();
        // Bob already has a balance of 100 USDT
        assertEq(usdt.balanceOf(bob.pub), 105 ether);
    }

    function test_usingExecuteBatch() public {
        vm.startPrank(address(scw));
        usdt.mint(address(scw), 10 ether);
        usdt.approve(address(scw), 10 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(2 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(2 ether));
        // Construct Executions - x5 of 2 ether each
        Execution[] memory executions = new Execution[](5);
        Execution memory executionData = Execution({target: address(usdt), value: 0, callData: data});
        for (uint256 i = 0; i < executions.length; i++) {
            executions[i] = executionData;
        }
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));
        PackedUserOperation memory op = _createUserOp(address(scw), address(erc20skv));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _executeUserOp(op);
        vm.stopPrank();
        // Bob already has a balance of 100 USDT
        assertEq(usdt.balanceOf(bob.pub), 110 ether);
    }

    function test_usingMultipleSessionKeys() public {
        vm.startPrank(address(scw));
        // Setup Session Keys
        User memory approveSessionKey = _createUser("Approve Session Key");
        User memory transferSessionKey = _createUser("Transfer Session Key");
        // ERC20 mint
        usdt.mint(address(scw), 10 ether);
        // Enable valid sessions
        // Session 1 - approve
        bytes memory approveSessionData = abi.encodePacked(
            approveSessionKey.pub,
            address(usdt),
            IERC20.approve.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(approveSessionData);
        // Session 2 - transfer
        bytes memory transferSessionData = abi.encodePacked(
            transferSessionKey.pub,
            address(usdt),
            IERC20.transfer.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(transferSessionData);
        // Construct user op data
        // Approve
        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, address(scw), uint256(5 ether));
        // Transfer
        bytes memory transferData = abi.encodeWithSelector(IERC20.transfer.selector, bob.pub, uint256(2 ether));
        // Construct UserOp.calldatas
        bytes memory approveCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdt), uint256(0), approveData))
        );
        bytes memory transferCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdt), uint256(0), transferData))
        );
        // First UserOp - Approve
        PackedUserOperation memory op = _createUserOp(address(scw), address(erc20skv));
        op.callData = approveCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, approveSessionKey);
        _executeUserOp(op);
        // Second UserOp - Transfer
        op = _createUserOp(address(scw), address(erc20skv));
        op.callData = transferCalldata;
        hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, transferSessionKey);
        _executeUserOp(op);
        vm.stopPrank();
        // Bob already has balance of 100 USDT
        assertEq(usdt.balanceOf(bob.pub), 102 ether);
    }

    function test_validateUserOp_RevertIf_DifferentSessionKeyAsSigner() public {
        vm.startPrank(address(scw));
        usdt.mint(address(scw), 10 ether);
        usdt.approve(address(scw), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        // Enable another session to act as signer (use transfer instead of transferFrom)
        bytes memory anotherSessionData = abi.encodePacked(
            otherSessionKey.pub,
            address(usdt),
            IERC20.transfer.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(anotherSessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdt), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(scw), address(erc20skv));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, otherSessionKey);
        // Validation should fail - signed with different valid session key
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_validateUserOp_RevertIf_SessionSignedByOwnerEOA() public {
        vm.startPrank(address(scw));
        usdt.mint(address(scw), 10 ether);
        usdt.approve(address(scw), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdt), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(scw), address(erc20skv));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa);
        // Validation should fail - signed with different valid session key
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_validateUserOp_RevertIf_SessionSignedByInvalidKey() public {
        vm.startPrank(address(scw));
        usdt.mint(address(scw), 10 ether);
        usdt.approve(address(scw), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(5 ether),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(5 ether));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdt), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(scw), address(erc20skv));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, otherSessionKey);
        // Validation should fail - signed with different valid session key
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
    }

    function test_validUserOp_UsingWeiAmounts() public {
        vm.startPrank(address(scw));
        // Test for successful transfer for 100000000000000 wei (0.0001 ether)
        // Test for failing transfer for 100000000000001 wei
        usdt.mint(address(scw), 10 ether);
        usdt.approve(address(scw), 5 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(100000000000000),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(100000000000000));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdt), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(scw), address(erc20skv));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _executeUserOp(op);
        // Bob already has balance of 100 USDT
        assertEq(usdt.balanceOf(bob.pub), 100000100000000000000);
        // Test for invalid Wei amount - should revert
        // Construct user op data
        data = abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(100000000000001));
        opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdt), uint256(0), data))
        );
        op = _createUserOp(address(scw), address(erc20skv));
        op.callData = opCalldata;
        hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        // Validation should fail - signed with different valid session key
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_validateUserOp_UsingTestUSDC() public {
        vm.startPrank(address(scw));
        // Mint 10 USDC to SCW
        usdc.mint(address(scw), 10000000);
        usdc.approve(address(scw), 10000000);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdc),
            IERC20.transferFrom.selector,
            uint256(10000000),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(10000001));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdc), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(scw), address(erc20skv));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        vm.stopPrank();
    }

    function test_validateUserOp_RevertIf_BatchLastExecBad() public {
        vm.startPrank(address(scw));
        // Mint and approve more than required for batch tx
        usdt.mint(address(scw), 11 ether);
        usdt.approve(address(scw), 11 ether);
        // Enable valid session
        bytes memory sessionData = abi.encodePacked(
            sessionKey.pub,
            address(usdt),
            IERC20.transferFrom.selector,
            uint256(2000000000000000000),
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days)
        );
        erc20skv.enableSessionKey(sessionData);
        // Construct user op data
        bytes memory data =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(2000000000000000000));
        Execution[] memory executions = new Execution[](5);
        Execution memory executionData = Execution({target: address(usdt), value: 0, callData: data});
        for (uint256 i = 0; i < 4; i++) {
            executions[i] = executionData;
        }
        // Construct bad data for last tx in batch
        bytes memory badData =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), bob.pub, uint256(2000000000000000001));
        // Bad execution data
        executions[4] = Execution({target: address(usdt), value: 0, callData: badData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));
        PackedUserOperation memory op = _createUserOp(address(scw), address(erc20skv));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, sessionKey);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
    }
}
