// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC7579Account} from "../../../../src/interfaces/base/IERC7579Account.sol";
import {IGuardianRecoveryValidator} from "../../../../src/interfaces/modules/IGuardianRecoveryValidator.sol";
import {
    MODULE_TYPE_VALIDATOR, SIG_VALIDATION_SUCCESS, SIG_VALIDATION_FAILED
} from "../../../../src/types/Constants.sol";
import {GuardianRecoveryTestUtils} from "../utils/GuardianRecoveryTestUtils.sol";

contract GuardianRecoveryValidatorTest is GuardianRecoveryTestUtils {
    // Events to test
    event GRV_ValidatorEnabled(address indexed scw);
    event GRV_ValidatorDisabled(address indexed scw);
    event GRV_OwnerAdded(address indexed scw, address indexed owner);
    event GRV_OwnerRemoved(address indexed scw, address indexed owner);
    event GRV_GuardianAdded(address indexed scw, address indexed guardian);
    event GRV_GuardianRemoved(address indexed scw, address indexed guardian);
    event GRV_ProposalSubmitted(address indexed scw, uint256 indexed proposalId, address newOwner, address proposer);
    event GRV_ProposalDiscarded(address indexed scw, uint256 indexed proposalId, address caller);
    event GRV_QuorumReached(address indexed scw, uint256 indexed proposalId, address newOwner);
    event GRV_QuorumNotReached(
        address indexed scw, uint256 indexed proposalId, address newOwner, uint256 approvalCount
    );
    event GRV_ProposalTimelockChanged(address indexed scw, uint256 newTimelock);

    function setUp() public virtual {
        _testSetup();
    }

    /*//////////////////////////////////////////////////////////////
                       INSTALLATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_installValidator() public {
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = eoa.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        vm.expectEmit(true, true, true, true);
        emit GRV_ValidatorEnabled(address(SCW));
        bool success =
            _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
        assertTrue(success, "Validator should be installed");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isInitialized(address(SCW)), "Validator should be initialized");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), eoa.pub), "EOA should be the owner");
    }

    function test_installValidator_WithMultipleOwnersAndGuardians() public {
        address[] memory initialOwners = new address[](3);
        initialOwners[0] = eoa.pub;
        initialOwners[1] = alice.pub;
        initialOwners[2] = bob.pub;
        address[] memory initialGuardians = new address[](3);
        initialGuardians[0] = guardian1.pub;
        initialGuardians[1] = guardian2.pub;
        initialGuardians[2] = guardian3.pub;
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        bool success =
            _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
        assertTrue(success, "Validator should be installed");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), eoa.pub), "EOA should be an owner");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), alice.pub), "Alice should be an owner");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), bob.pub), "Bob should be an owner");
        assertTrue(
            GUARDIAN_RECOVERY_VALIDATOR.isGuardian(address(SCW), guardian1.pub), "Guardian1 should be a guardian"
        );
        assertTrue(
            GUARDIAN_RECOVERY_VALIDATOR.isGuardian(address(SCW), guardian2.pub), "Guardian2 should be a guardian"
        );
        assertTrue(
            GUARDIAN_RECOVERY_VALIDATOR.isGuardian(address(SCW), guardian3.pub), "Guardian3 should be a guardian"
        );
    }

    function test_installValidator_RevertIf_InvalidOwnerData() public {
        address[] memory initialOwners = new address[](0);
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _toRevert(IGuardianRecoveryValidator.GRV_InvalidOwnerData.selector, hex"");
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
    }

    function test_installValidator_RevertIf_ZeroAddressOwner() public {
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = address(0);
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _toRevert(IGuardianRecoveryValidator.GRV_AddingInvalidOwner.selector, abi.encode(address(SCW), address(0)));
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
    }

    function test_uninstallValidator() public {
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = eoa.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isInitialized(address(SCW)), "Validator should be initialized");
        vm.expectEmit(true, true, true, true);
        emit GRV_ValidatorDisabled(address(SCW));
        _uninstallModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), "");
        assertFalse(GUARDIAN_RECOVERY_VALIDATOR.isInitialized(address(SCW)), "Validator should not be initialized");
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addOwner() public {
        _installValidatorWithSetup();
        vm.prank(eoa.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_OwnerAdded(address(SCW), charlie.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addOwner.selector, address(SCW), charlie.pub)
        );
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), charlie.pub), "Charlie should be an owner");
        assertEq(GUARDIAN_RECOVERY_VALIDATOR.getOwnerCount(address(SCW)), 2, "Owner count should be 2");
    }

    function test_addOwner_RevertIf_NonOwner() public {
        _installValidatorWithSetup();
        vm.prank(alice.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_NotOwner.selector, abi.encode(alice.pub));
        GUARDIAN_RECOVERY_VALIDATOR.addOwner(address(SCW), alice.pub);
    }

    function test_addOwner_RevertIf_ExistingOwner() public {
        _installValidatorWithSetup();
        vm.prank(eoa.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_AddingInvalidOwner.selector, abi.encode(address(SCW), eoa.pub));
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addOwner.selector, address(SCW), eoa.pub)
        );
    }

    function test_removeOwner() public {
        _installValidatorWithSetup();
        // First add another owner
        vm.prank(eoa.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addOwner.selector, address(SCW), alice.pub)
        );
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), alice.pub), "Alice should be an owner");
        // Now remove the original owner
        vm.prank(eoa.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_OwnerRemoved(address(SCW), eoa.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.removeOwner.selector, address(SCW), eoa.pub)
        );
        assertFalse(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), eoa.pub), "EOA should not be an owner");
        assertEq(GUARDIAN_RECOVERY_VALIDATOR.getOwnerCount(address(SCW)), 1, "Owner count should be 1");
    }

    function test_removeOwner_RevertIf_LastOwner() public {
        _installValidatorWithSetup();
        vm.prank(eoa.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_WalletNeedsOwner.selector, hex"");
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.removeOwner.selector, address(SCW), eoa.pub)
        );
    }

    /*//////////////////////////////////////////////////////////////
                     GUARDIAN MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addGuardian() public {
        _installValidatorWithSetup();
        vm.prank(eoa.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_GuardianAdded(address(SCW), guardian1.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addGuardian.selector, address(SCW), guardian1.pub)
        );
        assertTrue(
            GUARDIAN_RECOVERY_VALIDATOR.isGuardian(address(SCW), guardian1.pub), "Guardian1 should be a guardian"
        );
        assertEq(GUARDIAN_RECOVERY_VALIDATOR.getGuardianCount(address(SCW)), 1, "Guardian count should be 1");
    }

    function test_addGuardian_RevertIf_NonOwner() public {
        _installValidatorWithSetup();
        vm.prank(alice.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_NotOwner.selector, abi.encode(alice.pub));
        GUARDIAN_RECOVERY_VALIDATOR.addGuardian(address(SCW), guardian1.pub);
    }

    function test_removeGuardian() public {
        _installValidatorWithAllGuardians();
        vm.prank(eoa.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_GuardianRemoved(address(SCW), guardian1.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.removeGuardian.selector, address(SCW), guardian1.pub)
        );
        assertFalse(
            GUARDIAN_RECOVERY_VALIDATOR.isGuardian(address(SCW), guardian1.pub), "Guardian1 should not be a guardian"
        );
        assertEq(GUARDIAN_RECOVERY_VALIDATOR.getGuardianCount(address(SCW)), 2, "Guardian count should be 2");
    }

    /*//////////////////////////////////////////////////////////////
                     GUARDIAN RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_guardianPropose() public {
        _installValidatorWithAllGuardians();
        vm.prank(guardian1.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_ProposalSubmitted(address(SCW), 1, alice.pub, guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
        (address proposedOwner, uint256 approvalCount, address[] memory approvers, bool resolved,) =
            GUARDIAN_RECOVERY_VALIDATOR.getProposal(address(SCW), 1);
        assertEq(proposedOwner, alice.pub, "Proposed owner should be Alice");
        assertEq(approvalCount, 1, "Approval count should be 1");
        assertEq(approvers.length, 1, "There should be 1 approver");
        assertEq(approvers[0], guardian1.pub, "Approver should be guardian1");
        assertFalse(resolved, "Proposal should not be resolved");
    }

    function test_guardianPropose_RevertIf_NotGuardian() public {
        _installValidatorWithAllGuardians();
        vm.prank(alice.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_NotGuardian.selector, abi.encode(alice.pub));
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
    }

    function test_guardianPropose_RevertIf_NotEnoughGuardians() public {
        _installValidatorWithSetup();
        // Add just one guardian
        vm.prank(eoa.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addGuardian.selector, address(SCW), guardian1.pub)
        );
        vm.prank(guardian1.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_NotEnoughGuardians.selector, hex"");
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
    }

    function test_guardianPropose_RevertIf_AddingInvalidOwner() public {
        _installValidatorWithAllGuardians();
        // Try to propose existing owner
        vm.prank(guardian1.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_AddingInvalidOwner.selector, abi.encode(address(SCW), eoa.pub));
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), eoa.pub);
        // Try to propose guardian as owner
        vm.prank(guardian1.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_AddingInvalidOwner.selector, abi.encode(address(SCW), guardian2.pub));
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), guardian2.pub);
        // Try to propose zero address
        vm.prank(guardian1.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_AddingInvalidOwner.selector, abi.encode(address(SCW), address(0)));
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), address(0));
    }

    function test_guardianPropose_RevertIf_LastProposalUnresolved() public {
        _installValidatorWithAllGuardians();
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
        vm.prank(guardian1.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_ProposalUnresolved.selector, hex"");
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), bob.pub);
    }

    function test_guardianCosign_QuorumNotReached() public {
        _installValidatorWithAllGuardians();
        // Add an extra guardian to make quorum harder to reach
        vm.prank(eoa.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addGuardian.selector, address(SCW), guardian4.pub)
        );
        // Guardian1 proposes
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
        // Guardian2 cosigns
        vm.prank(guardian2.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_QuorumNotReached(address(SCW), 1, alice.pub, 2);
        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));
        // Check proposal state
        (, uint256 approvalCount,, bool resolved,) = GUARDIAN_RECOVERY_VALIDATOR.getProposal(address(SCW), 1);
        assertEq(approvalCount, 2, "Approval count should be 2");
        assertFalse(resolved, "Proposal should not be resolved");
        assertFalse(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), alice.pub), "Alice should not be an owner yet");
    }

    function test_guardianCosign_QuorumReached() public {
        _installValidatorWithAllGuardians();
        // Guardian1 proposes
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
        // Guardian2 cosigns
        vm.prank(guardian2.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_QuorumReached(address(SCW), 1, alice.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));
        // Check proposal state
        (,,, bool resolved,) = GUARDIAN_RECOVERY_VALIDATOR.getProposal(address(SCW), 1);
        assertTrue(resolved, "Proposal should be resolved");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), alice.pub), "Alice should be an owner");
    }

    function test_guardianCosign_RevertIf_NotGuardian() public {
        _installValidatorWithAllGuardians();
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
        vm.prank(alice.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_NotGuardian.selector, abi.encode(alice.pub));
        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));
    }

    function test_guardianCosign_RevertIf_InvalidProposal() public {
        _installValidatorWithAllGuardians();
        vm.prank(guardian1.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_InvalidProposal.selector, hex"");
        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));
    }

    function test_guardianCosign_RevertIf_AlreadySignedProposal() public {
        _installValidatorWithAllGuardians();
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
        vm.prank(guardian1.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_AlreadySignedProposal.selector, hex"");
        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));
    }

    function test_guardianCosign_RevertIf_ProposalResolved() public {
        _installValidatorWithAllGuardians();
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
        vm.prank(guardian2.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));
        // Try to cosign after proposal is resolved
        vm.prank(guardian3.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_ProposalResolved.selector, hex"");
        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));
    }

    function test_discardCurrentProposal() public {
        _installValidatorWithAllGuardians();
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
        // Fast forward past the timelock period
        vm.warp(block.timestamp + 25 hours);
        vm.prank(guardian1.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_ProposalDiscarded(address(SCW), 1, guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.discardCurrentProposal(address(SCW));
        // Check proposal state
        (,,, bool resolved,) = GUARDIAN_RECOVERY_VALIDATOR.getProposal(address(SCW), 1);
        assertTrue(resolved, "Proposal should be resolved (discarded)");
        assertFalse(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), alice.pub), "Alice should not be an owner");
    }

    function test_discardCurrentProposal_RevertIf_NotOwnerOrGuardianOrSelf() public {
        _installValidatorWithAllGuardians();
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
        vm.warp(block.timestamp + 25 hours);
        vm.prank(malicious.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_NotOwnerOrGuardianOrSelf.selector, abi.encode(malicious.pub));
        GUARDIAN_RECOVERY_VALIDATOR.discardCurrentProposal(address(SCW));
    }

    function test_discardCurrentProposal_RevertIf_ProposalResolved() public {
        _installValidatorWithAllGuardians();
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
        vm.prank(guardian2.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));
        vm.prank(guardian1.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_ProposalResolved.selector, hex"");
        GUARDIAN_RECOVERY_VALIDATOR.discardCurrentProposal(address(SCW));
    }

    function test_discardCurrentProposal_RevertIf_ProposalTimelocked() public {
        _installValidatorWithAllGuardians();
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
        // Try to discard before timelock period is over
        vm.prank(guardian1.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_ProposalTimelocked.selector, hex"");
        GUARDIAN_RECOVERY_VALIDATOR.discardCurrentProposal(address(SCW));
    }

    function test_changeProposalTimelock() public {
        _installValidatorWithSetup();
        uint256 newTimelock = 48 hours;
        vm.prank(eoa.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_ProposalTimelockChanged(address(SCW), newTimelock);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(
                GUARDIAN_RECOVERY_VALIDATOR.changeProposalTimelock.selector, address(SCW), newTimelock
            )
        );
        assertEq(
            GUARDIAN_RECOVERY_VALIDATOR.getProposalTimelock(address(SCW)),
            newTimelock,
            "Proposal timelock should be updated"
        );
    }

    /*//////////////////////////////////////////////////////////////
                         SIGNATURE VALIDATION TESTS
        //////////////////////////////////////////////////////////////*/

    function test_validateUserOp() public {
        _installValidatorWithSetup();
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(GUARDIAN_RECOVERY_VALIDATOR));
        bytes32 userOpHash = keccak256(abi.encode("test userop hash"));
        userOp.signature = _sign(userOpHash, eoa);
        vm.prank(address(SCW)); // The validator expects msg.sender to be the account
        uint256 validationResult = GUARDIAN_RECOVERY_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation should succeed");
    }

    function test_validateUserOp_WithEthSign() public {
        _installValidatorWithSetup();
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(GUARDIAN_RECOVERY_VALIDATOR));
        bytes32 userOpHash = keccak256(abi.encode("test userop hash"));
        userOp.signature = _ethSign(userOpHash, eoa);
        vm.prank(address(SCW));
        uint256 validationResult = GUARDIAN_RECOVERY_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation with ethSign should succeed");
    }

    function test_validateUserOp_RevertIf_InvalidSigner() public {
        _installValidatorWithSetup();
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(GUARDIAN_RECOVERY_VALIDATOR));
        bytes32 userOpHash = keccak256(abi.encode("test userop hash"));
        userOp.signature = _sign(userOpHash, alice);
        vm.prank(address(SCW));
        uint256 validationResult = GUARDIAN_RECOVERY_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_FAILED, "UserOp validation should fail with invalid signer");
    }

    function test_isValidSignatureWithSender() public {
        _installValidatorWithSetup();
        bytes32 hash = keccak256(abi.encode("test message"));
        bytes memory signature = _sign(hash, eoa);
        vm.prank(address(SCW));
        bytes4 result = GUARDIAN_RECOVERY_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0x1626ba7e), "Signature should be valid");
    }

    function test_isValidSignatureWithSender_WithEthSign() public {
        _installValidatorWithSetup();
        bytes32 hash = keccak256(abi.encode("test message"));
        bytes memory signature = _ethSign(hash, eoa);
        vm.prank(address(SCW));
        bytes4 result = GUARDIAN_RECOVERY_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0x1626ba7e), "Signature with ethSign should be valid");
    }

    function test_isValidSignatureWithSender_RevertIf_InvalidSignature() public {
        _installValidatorWithSetup();
        bytes32 hash = keccak256(abi.encode("test message"));
        bytes memory signature = _sign(hash, alice);
        vm.prank(address(SCW));
        bytes4 result = GUARDIAN_RECOVERY_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0xffffffff), "Signature should be invalid");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER METHODS
        //////////////////////////////////////////////////////////////*/

    // Helper to test the full guardian recovery flow
    function testFull_GuardianRecoveryFlow() public {
        // 1. Install validator with owner and guardians
        _installValidatorWithAllGuardians();
        // 2. Guardian proposes new owner
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);
        // Check initial proposal state
        (address proposedOwner, uint256 approvalCount,, bool resolved,) = _getProposalInfo(address(SCW), 1);
        assertEq(proposedOwner, alice.pub, "Proposed owner should be Alice");
        assertEq(approvalCount, 1, "Approval count should be 1");
        assertFalse(resolved, "Proposal should not be resolved");
        // 3. Second guardian cosigns
        vm.prank(guardian2.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));
        // Check final proposal state
        (,,, resolved,) = _getProposalInfo(address(SCW), 1);
        assertTrue(resolved, "Proposal should be resolved");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), alice.pub), "Alice should now be an owner");
        // 4. Verify new owner can now perform operations
        vm.prank(alice.pub);
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(GUARDIAN_RECOVERY_VALIDATOR));
        bytes32 userOpHash = keccak256(abi.encode("test userop hash"));
        userOp.signature = _sign(userOpHash, alice);
        vm.prank(address(SCW));
        uint256 validationResult = GUARDIAN_RECOVERY_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "New owner should be able to sign transactions");
    }

    // Test interaction between owner and guardian management
    function test_ownerCannotBeGuardian() public {
        _installValidatorWithSetup();
        // Owner tries to add themselves as guardian
        vm.prank(eoa.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_AddingInvalidGuardian.selector, abi.encode(address(SCW), eoa.pub));
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addGuardian.selector, address(SCW), eoa.pub)
        );
    }

    function test_guardianCannotBeOwner() public {
        _installValidatorWithAllGuardians();
        // Owner tries to add a guardian as another owner
        vm.prank(eoa.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_AddingInvalidOwner.selector, abi.encode(address(SCW), guardian1.pub));
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addOwner.selector, address(SCW), guardian1.pub)
        );
    }
}
