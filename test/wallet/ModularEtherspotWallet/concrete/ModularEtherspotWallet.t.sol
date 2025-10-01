// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {ExecutionLib} from "ERC7579/libs/ExecutionLib.sol";
import {
    ModeLib,
    ModeCode,
    CallType,
    ExecType,
    ModeSelector,
    ModePayload,
    CALLTYPE_DELEGATECALL,
    EXECTYPE_DEFAULT,
    MODE_DEFAULT
} from "ERC7579/libs/ModeLib.sol";
import {MockValidator} from "ERC7579/test/mocks/MockValidator.sol";
import {MockExecutor} from "ERC7579/test/mocks/MockExecutor.sol";
import {MockTarget} from "ERC7579/test/mocks/MockTarget.sol";
import {MockDelegateTarget} from "ERC7579/test/mocks/MockDelegateTarget.sol";
import "ERC7579/test/Bootstrap.t.sol";
import "ERC7579/test/dependencies/EntryPoint.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {ModularEtherspotWalletFactory} from "../../../../src/wallet/ModularEtherspotWalletFactory.sol";
import {MultipleOwnerECDSAValidator} from "../../../../src/modules/validators/MultipleOwnerECDSAValidator.sol";
import {ModularEtherspotWalletTestUtils as TestUtils} from "../utils/ModularEtherspotWalletTestUtils.sol";

contract ModularEtherspotWalletTest is TestUtils {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event OwnerAdded(address account, address added);
    event OwnerRemoved(address account, address removed);
    event GuardianAdded(address account, address newGuardian);
    event GuardianRemoved(address account, address removedGuardian);
    event ProposalTimelockChanged(address account, uint256 newTimelock);
    event ProposalSubmitted(address account, uint256 proposalId, address newOwnerProposed, address proposer);
    event QuorumNotReached(address account, uint256 proposalId, address newOwnerProposed, uint256 approvalCount);
    event ProposalDiscarded(address account, uint256 proposalId, address discardedBy);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyOwnerOrSelf();
    error AddingInvalidOwner();
    error RemovingInvalidOwner();
    error WalletNeedsOwner();
    error AddingInvalidGuardian();
    error RemovingInvalidGuardian();
    error OnlyGuardian();
    error NotEnoughGuardians();
    error ProposalUnresolved();
    error InvalidProposal();
    error AlreadySignedProposal();
    error ProposalResolved();
    error ProposalTimelocked();
    error OnlyOwnerOrGuardianOrSelf();
    error OnlyProxy();
    error RequiredModule();
    error LinkedList_InvalidEntry(address entry);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testInit();
    }

    /*//////////////////////////////////////////////////////////////
                    MODULAR ETHERSPOT WALLET TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initializeAccountRevert() public {
        _toRevert(OnlyProxy.selector, hex"");
        impl.initializeAccount("0x00");
    }

    function test_executeSingle() public validatorInstalled returns (address) {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1337);
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(mockTar), uint256(0), callData))
        );
        // Create and sign UserOp
        PackedUserOperation memory op = _createUserOp(address(scw), address(moecdsav));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa);
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        assertTrue(mockTar.value() == 1337);
    }

    function test_executeBatch() public validatorInstalled {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1337);
        // Create the executions
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: address(mockTar), value: 0, callData: callData});
        executions[1] = Execution({target: bob.pub, value: 1 wei, callData: ""});
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));
        // Create and sign UserOp
        PackedUserOperation memory op = _createUserOp(address(scw), address(moecdsav));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa);
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        // Bob starts with initial balance of 100 ether
        assertTrue(mockTar.value() == 1337);
        assertTrue(bob.pub.balance == 100 ether + 1 wei);
    }

    function test_executeSingle_FromExecutor() public validatorInstalled {
        bytes[] memory ret = mockExec.executeViaAccount(
            IERC7579Account(address(scw)),
            address(mockTar),
            0,
            abi.encodePacked(MockTarget.setValue.selector, uint256(1338))
        );
        assertEq(ret.length, 1);
        assertEq(abi.decode(ret[0], (uint256)), 1338);
    }

    function test_executeBatch_FromExecutor() public validatorInstalled {
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1338);
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: address(mockTar), value: 0, callData: callData});
        executions[1] = Execution({target: address(mockTar), value: 0, callData: callData});
        bytes[] memory ret = mockExec.execBatch({account: IERC7579Account(address(scw)), execs: executions});
        assertEq(ret.length, 2);
        assertEq(abi.decode(ret[0], (uint256)), 1338);
    }

    function test_delegateCall() public validatorInstalled {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeWithSelector(MockDelegateTarget.sendValue.selector, bob.pub, 1 ether);
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encode(CALLTYPE_DELEGATECALL, EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00)),
                abi.encodePacked(address(mockDelTar), callData)
            )
        );
        // Create and sign UserOp
        PackedUserOperation memory op = _createUserOp(address(scw), address(moecdsav));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa);
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        // Bob has starting balance of 100 ether
        assertTrue(bob.pub.balance == 100 ether + 1 ether);
    }

    function test_delegateCall_FromExecutor() public validatorInstalled {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeWithSelector(MockDelegateTarget.sendValue.selector, bob.pub, 1 ether);
        // Execute the delegatecall via the executor
        bytes[] memory ret =
            mockExec.execDelegatecall(IERC7579Account(address(scw)), abi.encodePacked(mockDelTar, callData));
        // Assert that the value was set ie that execution was successful
        // Bob has initial balance of 100 ether
        assertTrue(bob.pub.balance == 100 ether + 1 ether);
    }

    function test_execute_FromAnotherOwner() public validatorInstalled {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1337);
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(mockTar), uint256(0), callData))
        );
        // Create and sign UserOp
        PackedUserOperation memory op = _createUserOp(address(scw), address(moecdsav));
        op.callData = opCalldata;
        vm.prank(eoa.pub);
        scw.addOwner(alice.pub);
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, alice);
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        assertTrue(mockTar.value() == 1337);
    }

    function test_execute_RevertIf_FromNonOwner() public validatorInstalled {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1337);
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(mockTar), uint256(0), callData))
        );
        // Create and sign UserOp
        PackedUserOperation memory op = _createUserOp(address(scw), address(moecdsav));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _ethSign(hash, malicious);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Send the userOp to the entrypoint
        _executeUserOp(op);
    }

    /*//////////////////////////////////////////////////////////////
                       ACCESS CONTROLLER TESTS
    //////////////////////////////////////////////////////////////*/
    // AccessController

    function test_isOwner() public {
        assertTrue(scw.isOwner(eoa.pub));
    }

    function test_isOwner_RevertIf_NotOwner() public {
        assertFalse(scw.isOwner(malicious.pub));
    }

    function test_addOwner() public {
        vm.startPrank(eoa.pub);
        vm.expectEmit(true, true, true, true);
        emit OwnerAdded(address(scw), alice.pub);
        scw.addOwner(alice.pub);
        assertTrue(scw.isOwner(alice.pub));
        assertEq(2, scw.ownerCount());
        vm.stopPrank();
    }

    function test_addOwner_RevertIf_NotOwnerOrSelf() public {
        vm.startPrank(malicious.pub);
        _toRevert(OnlyOwnerOrSelf.selector, hex"");
        scw.addOwner(alice.pub);
        vm.stopPrank();
    }

    function test_addOwner_RevertIf_AddingInvalidOwner() public {
        vm.startPrank(eoa.pub);
        _toRevert(AddingInvalidOwner.selector, hex"");
        scw.addOwner(zero.pub);
        _toRevert(AddingInvalidOwner.selector, hex"");
        scw.addOwner(eoa.pub);
        scw.addGuardian(guardian1.pub);
        _toRevert(AddingInvalidOwner.selector, hex"");
        scw.addOwner(guardian1.pub);
        vm.stopPrank();
    }

    function test_removeOwner() public {
        vm.startPrank(eoa.pub);
        scw.addOwner(alice.pub);
        assertTrue(scw.isOwner(alice.pub));
        vm.expectEmit(true, true, true, true);
        emit OwnerRemoved(address(scw), eoa.pub);
        scw.removeOwner(eoa.pub);
        assertFalse(scw.isOwner(eoa.pub));
        assertEq(1, scw.ownerCount());
        vm.stopPrank();
    }

    function test_removeOwner_RevertIf_NotOwnerOrSelf() public {
        vm.startPrank(eoa.pub);
        scw.addOwner(alice.pub);
        vm.stopPrank();
        vm.startPrank(malicious.pub);
        _toRevert(OnlyOwnerOrSelf.selector, hex"");
        scw.removeOwner(alice.pub);
        vm.stopPrank();
    }

    function test_removeOwner_RevertIf_RemovingInvalidOwner() public {
        vm.startPrank(eoa.pub);
        _toRevert(RemovingInvalidOwner.selector, hex"");
        scw.removeOwner(address(0));
        _toRevert(RemovingInvalidOwner.selector, hex"");
        scw.removeOwner(alice.pub);
        vm.stopPrank();
    }

    function test_removeOwner_RevertIf_LastOwner() public {
        vm.startPrank(eoa.pub);
        _toRevert(WalletNeedsOwner.selector, hex"");
        scw.removeOwner(eoa.pub);
        vm.stopPrank();
    }

    function test_isGuardian() public {
        vm.startPrank(eoa.pub);
        scw.addGuardian(guardian1.pub);
        assertTrue(scw.isGuardian(guardian1.pub));
        vm.stopPrank();
    }

    function test_addGuardian() public {
        vm.startPrank(eoa.pub);
        vm.expectEmit(true, true, true, true);
        emit GuardianAdded(address(scw), guardian1.pub);
        scw.addGuardian(guardian1.pub);
        assertTrue(scw.isGuardian(guardian1.pub));
        assertEq(1, scw.guardianCount());
        vm.stopPrank();
    }

    function test_addGuardian_RevertIf_NotOwnerOrSelf() public {
        vm.startPrank(malicious.pub);
        _toRevert(OnlyOwnerOrSelf.selector, "");
        scw.addGuardian(guardian1.pub);
        vm.stopPrank();
    }

    function test_addGuardian_RevertIf_AddingInvalidGuardian() public {
        vm.startPrank(eoa.pub);
        scw.addGuardian(guardian1.pub);
        _toRevert(AddingInvalidGuardian.selector, hex"");
        scw.addGuardian(address(0));
        _toRevert(AddingInvalidGuardian.selector, hex"");
        scw.addGuardian(eoa.pub);
        _toRevert(AddingInvalidGuardian.selector, hex"");
        scw.addGuardian(guardian1.pub);
        vm.stopPrank();
    }

    function test_removeGuardian() public {
        vm.startPrank(eoa.pub);
        scw.addGuardian(guardian1.pub);
        assertTrue(scw.isGuardian(guardian1.pub));
        vm.expectEmit(true, true, true, true);
        emit GuardianRemoved(address(scw), guardian1.pub);
        scw.removeGuardian(guardian1.pub);
        assertFalse(scw.isGuardian(guardian1.pub));
        assertEq(0, scw.guardianCount());
        vm.stopPrank();
    }

    function test_removeGuardian_RevertIf_NotOwnerOrSelf() public {
        vm.startPrank(eoa.pub);
        scw.addGuardian(guardian1.pub);
        vm.stopPrank();
        vm.startPrank(malicious.pub);
        _toRevert(OnlyOwnerOrSelf.selector, hex"");
        scw.removeGuardian(guardian1.pub);
        vm.stopPrank();
    }

    function test_removeGuardian_RevertIf_RemovingInvalidGuardian() public {
        vm.startPrank(eoa.pub);
        _toRevert(RemovingInvalidGuardian.selector, hex"");
        scw.removeGuardian(address(0));
        _toRevert(RemovingInvalidGuardian.selector, hex"");
        scw.removeGuardian(malicious.pub);
        vm.stopPrank();
    }

    function test_changeProposalTimelock() public {
        vm.startPrank(eoa.pub);
        scw.changeProposalTimelock(6 days);
        assertEq(6 days, scw.proposalTimelock());
        vm.stopPrank();
    }

    function test_changeProposalTimelock_RevertIf_NotOwnerOrSelf() public {
        vm.startPrank(malicious.pub);
        _toRevert(OnlyOwnerOrSelf.selector, hex"");
        scw.changeProposalTimelock(6 days);
        vm.stopPrank();
    }

    function test_guardianPropose() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        vm.expectEmit(true, true, true, true);
        emit ProposalSubmitted(address(scw), 1, alice.pub, guardian1.pub);
        scw.guardianPropose(alice.pub);
        assertEq(1, scw.proposalId());
        vm.stopPrank();
    }

    function test_guardianPropose_RevertIf_NotGuardian() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        _toRevert(OnlyGuardian.selector, hex"");
        scw.guardianPropose(alice.pub);
        vm.stopPrank();
    }

    function test_guardianPropose_RevertIf_NotEnoughGuardians() public {
        vm.startPrank(eoa.pub);
        scw.addGuardian(guardian1.pub);
        scw.addGuardian(guardian2.pub);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        _toRevert(NotEnoughGuardians.selector, hex"");
        scw.guardianPropose(alice.pub);
        vm.stopPrank();
    }

    function test_guardianPropose_RevertIf_AddingInvalidOwner() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        _toRevert(AddingInvalidOwner.selector, hex"");
        scw.guardianPropose(address(0));
        _toRevert(AddingInvalidOwner.selector, hex"");
        scw.guardianPropose(guardian1.pub);
        _toRevert(AddingInvalidOwner.selector, hex"");
        scw.guardianPropose(eoa.pub);
        vm.stopPrank();
    }

    function test_guardianPropose_RevertIf_LastProposalUnresolved() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        scw.guardianPropose(alice.pub);
        _toRevert(ProposalUnresolved.selector, hex"");
        scw.guardianPropose(alice.pub);
        vm.stopPrank();
    }

    function test_getProposal() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        scw.guardianPropose(alice.pub);
        (address proposedNewOwner, uint256 approvalCount, address[] memory guardiansApproved, bool resolved,) =
            scw.getProposal(1);
        assertEq(alice.pub, proposedNewOwner);
        assertEq(1, approvalCount);
        assertEq(guardian1.pub, guardiansApproved[0]);
        assertEq(false, resolved);
        vm.stopPrank();
    }

    function test_getProposal_RevertIf_InvalidProposal() public {
        vm.startPrank(eoa.pub);
        _toRevert(InvalidProposal.selector, hex"");
        scw.getProposal(0);
        _toRevert(InvalidProposal.selector, hex"");
        scw.getProposal(1);
        vm.stopPrank();
    }

    function test_guardianCosign_QuorumNotReached() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        scw.addGuardian(guardian4.pub);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        scw.guardianPropose(alice.pub);
        vm.stopPrank();
        vm.startPrank(guardian2.pub);
        vm.expectEmit(true, true, true, true);
        emit QuorumNotReached(address(scw), 1, alice.pub, 2);
        scw.guardianCosign();
        vm.stopPrank();
    }

    function test_guardianCosign_OwnerAdded() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        scw.guardianPropose(alice.pub);
        vm.stopPrank();
        vm.startPrank(guardian2.pub);
        scw.guardianCosign();
        assertTrue(scw.isOwner(alice.pub));
        vm.stopPrank();
    }

    function test_guardianCosign_RevertIf_NotGuardian() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        scw.guardianPropose(alice.pub);
        vm.stopPrank();
        vm.startPrank(malicious.pub);
        _toRevert(OnlyGuardian.selector, hex"");
        scw.guardianCosign();
        vm.stopPrank();
    }

    function test_guardianCosign_RevertIf_InvalidProposal() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        _toRevert(InvalidProposal.selector, hex"");
        scw.guardianCosign();
        vm.stopPrank();
    }

    function test_guardianCosign_RevertIf_GuardianAlreadySignedProposal() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        scw.guardianPropose(alice.pub);
        _toRevert(AlreadySignedProposal.selector, hex"");
        scw.guardianCosign();
        vm.stopPrank();
    }

    function test_guardianCosign_RevertIf_ProposalResolved() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        scw.guardianPropose(alice.pub);
        vm.stopPrank();
        vm.startPrank(guardian2.pub);
        scw.guardianCosign();
        assertTrue(scw.isOwner(alice.pub));
        vm.stopPrank();
        vm.startPrank(guardian3.pub);
        _toRevert(ProposalResolved.selector, hex"");
        scw.guardianCosign();
        vm.stopPrank();
    }

    function test_discardCurrentProposal() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        scw.guardianPropose(alice.pub);
        (,,, bool resolved,) = scw.getProposal(1);
        assertFalse(resolved);
        vm.warp(25 hours);
        vm.expectEmit(true, true, true, true);
        emit ProposalDiscarded(address(scw), 1, guardian1.pub);
        scw.discardCurrentProposal();
        (,,, resolved,) = scw.getProposal(1);
        assertTrue(resolved);
        assertFalse(scw.isOwner(alice.pub));
        vm.stopPrank();
    }

    function test_discardCurrentProposal_ReveertIf_NotOwnerOrGuardianOrSelf() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        scw.guardianPropose(alice.pub);
        vm.warp(25 hours);
        vm.stopPrank();
        vm.startPrank(malicious.pub);
        _toRevert(OnlyOwnerOrGuardianOrSelf.selector, hex"");
        scw.discardCurrentProposal();
        vm.stopPrank();
    }

    function test_discardCurrentProposal_RevertIf_ProposalResolved() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        scw.guardianPropose(alice.pub);
        vm.stopPrank();
        vm.startPrank(guardian2.pub);
        scw.guardianCosign();
        _toRevert(ProposalResolved.selector, hex"");
        scw.discardCurrentProposal();
        vm.stopPrank();
    }

    function test_discardCurrentProposal_RevertIf_ProposalTimelocked() public {
        vm.startPrank(eoa.pub);
        _addGuardians(scw);
        vm.stopPrank();
        vm.startPrank(guardian1.pub);
        scw.guardianPropose(alice.pub);
        _toRevert(ProposalTimelocked.selector, hex"");
        scw.discardCurrentProposal();
        vm.stopPrank();
    }

    function test_paginateExecutors() public {
        // Paginate from sentinel (start node) and expect the 1 default executor
        (address[] memory results, address next) = scw.getExecutorsPaginated(address(0x1), 1);
        assertTrue(results.length == 1);
        assertEq(results[0], address(mockExec));
        assertEq(next, address(0x1));
        // Paginate from the default executor and expect no results
        (address[] memory results2, address next2) = scw.getExecutorsPaginated(address(mockExec), 1);
        assertTrue(results2.length == 0);
        assertEq(next2, address(0x1));
        // Expect the revert with the encoded reason
        _toRevert(LinkedList_InvalidEntry.selector, abi.encode(address(this)));
        scw.getExecutorsPaginated(address(this), 1);
    }
}
