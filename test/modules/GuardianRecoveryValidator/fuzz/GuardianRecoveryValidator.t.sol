// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC7579Account} from "../../../../src/interfaces/base/IERC7579Account.sol";
import {IGuardianRecoveryValidator} from "../../../../src/interfaces/modules/IGuardianRecoveryValidator.sol";
import {
    MODULE_TYPE_VALIDATOR, SIG_VALIDATION_SUCCESS, SIG_VALIDATION_FAILED
} from "../../../../src/types/Constants.sol";
import {GuardianRecoveryTestUtils} from "../utils/GuardianRecoveryTestUtils.sol";

contract GuardianRecoveryValidator_Fuzz_Test is GuardianRecoveryTestUtils {
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
                       INSTALLATION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_installValidator(string memory ownerName) public {
        User memory user = _createUser(ownerName);

        address[] memory initialOwners = new address[](1);
        initialOwners[0] = user.pub;

        address[] memory initialGuardians = new address[](0);

        bytes memory initData = abi.encode(initialOwners, initialGuardians);

        vm.expectEmit(true, true, true, true);
        emit GRV_ValidatorEnabled(address(SCW));

        bool success =
            _installModule(user.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
        assertTrue(success, "Validator should be installed");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isInitialized(address(SCW)), "Validator should be initialized");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), user.pub), "User should be the owner");
    }

    function testFuzz_installValidator_WithMultipleOwners(string memory name1, string memory name2, string memory name3)
        public
    {
        vm.assume(
            keccak256(bytes(name1)) != keccak256(bytes(name2)) && keccak256(bytes(name1)) != keccak256(bytes(name3))
                && keccak256(bytes(name2)) != keccak256(bytes(name3))
        );

        User memory user1 = _createUser(name1);
        User memory user2 = _createUser(name2);
        User memory user3 = _createUser(name3);

        address[] memory initialOwners = new address[](3);
        initialOwners[0] = user1.pub;
        initialOwners[1] = user2.pub;
        initialOwners[2] = user3.pub;

        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);

        bool success =
            _installModule(user1.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
        assertTrue(success, "Validator should be installed");

        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), user1.pub), "User1 should be an owner");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), user2.pub), "User2 should be an owner");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), user3.pub), "User3 should be an owner");
        assertEq(GUARDIAN_RECOVERY_VALIDATOR.getOwnerCount(address(SCW)), 3, "Owner count should be 3");
    }

    function testFuzz_installValidator_WithOwnersAndGuardians(
        string memory ownerName,
        string memory g1Name,
        string memory g2Name
    ) public {
        vm.assume(
            keccak256(bytes(ownerName)) != keccak256(bytes(g1Name))
                && keccak256(bytes(ownerName)) != keccak256(bytes(g2Name))
                && keccak256(bytes(g1Name)) != keccak256(bytes(g2Name))
        );

        User memory owner = _createUser(ownerName);
        User memory g1 = _createUser(g1Name);
        User memory g2 = _createUser(g2Name);

        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;

        address[] memory initialGuardians = new address[](2);
        initialGuardians[0] = g1.pub;
        initialGuardians[1] = g2.pub;

        bytes memory initData = abi.encode(initialOwners, initialGuardians);

        bool success =
            _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
        assertTrue(success, "Validator should be installed");

        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), owner.pub), "Owner should be set");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isGuardian(address(SCW), g1.pub), "Guardian1 should be set");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isGuardian(address(SCW), g2.pub), "Guardian2 should be set");
        assertEq(GUARDIAN_RECOVERY_VALIDATOR.getGuardianCount(address(SCW)), 2, "Guardian count should be 2");
    }

    function testFuzz_installValidator_RevertIf_EmptyOwners() public {
        address[] memory initialOwners = new address[](0);
        address[] memory initialGuardians = new address[](0);

        bytes memory initData = abi.encode(initialOwners, initialGuardians);

        _toRevert(IGuardianRecoveryValidator.GRV_InvalidOwnerData.selector, hex"");
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
    }

    function testFuzz_installValidator_RevertIf_DuplicateOwners(string memory ownerName) public {
        User memory owner = _createUser(ownerName);

        address[] memory initialOwners = new address[](2);
        initialOwners[0] = owner.pub;
        initialOwners[1] = owner.pub; // Duplicate owner

        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);

        _toRevert(IGuardianRecoveryValidator.GRV_AddingInvalidOwner.selector, abi.encode(address(SCW), owner.pub));
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
    }

    function testFuzz_uninstallValidator(string memory ownerName) public {
        User memory owner = _createUser(ownerName);

        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);

        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isInitialized(address(SCW)), "Validator should be initialized");

        vm.expectEmit(true, true, true, true);
        emit GRV_ValidatorDisabled(address(SCW));

        _uninstallModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), "");
        assertFalse(GUARDIAN_RECOVERY_VALIDATOR.isInitialized(address(SCW)), "Validator should not be initialized");
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER MANAGEMENT FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_addOwner(string memory ownerName, string memory newOwnerName) public {
        vm.assume(keccak256(bytes(ownerName)) != keccak256(bytes(newOwnerName)));

        User memory owner = _createUser(ownerName);
        User memory newOwner = _createUser(newOwnerName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Add new owner
        vm.prank(owner.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_OwnerAdded(address(SCW), newOwner.pub);

        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addOwner.selector, address(SCW), newOwner.pub)
        );

        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), newOwner.pub), "New owner should be added");
        assertEq(GUARDIAN_RECOVERY_VALIDATOR.getOwnerCount(address(SCW)), 2, "Owner count should be 2");
    }

    function testFuzz_addOwner_RevertIf_NotOwner(
        string memory ownerName,
        string memory nonOwnerName,
        string memory newOwnerName
    ) public {
        vm.assume(
            keccak256(bytes(ownerName)) != keccak256(bytes(nonOwnerName))
                && keccak256(bytes(ownerName)) != keccak256(bytes(newOwnerName))
                && keccak256(bytes(nonOwnerName)) != keccak256(bytes(newOwnerName))
        );

        User memory owner = _createUser(ownerName);
        User memory nonOwner = _createUser(nonOwnerName);
        User memory newOwner = _createUser(newOwnerName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Try to add owner from non-owner account
        vm.prank(nonOwner.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_NotOwner.selector, abi.encode(nonOwner.pub));
        GUARDIAN_RECOVERY_VALIDATOR.addOwner(address(SCW), newOwner.pub);
    }

    function testFuzz_addOwner_RevertIf_InvalidOwner(string memory ownerName) public {
        User memory owner = _createUser(ownerName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Try to add zero address as owner
        vm.prank(owner.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_AddingInvalidOwner.selector, abi.encode(address(SCW), address(0)));
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addOwner.selector, address(SCW), address(0))
        );
    }

    function testFuzz_addOwner_RevertIf_AddingExistingOwner(string memory ownerName) public {
        User memory owner = _createUser(ownerName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Try to add existing owner
        vm.prank(owner.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_AddingInvalidOwner.selector, abi.encode(address(SCW), owner.pub));
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addOwner.selector, address(SCW), owner.pub)
        );
    }

    function testFuzz_removeOwner(string memory name1, string memory name2) public {
        vm.assume(keccak256(bytes(name1)) != keccak256(bytes(name2)));

        User memory owner1 = _createUser(name1);
        User memory owner2 = _createUser(name2);

        // Install validator with two owners
        address[] memory initialOwners = new address[](2);
        initialOwners[0] = owner1.pub;
        initialOwners[1] = owner2.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner1.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Remove one owner
        vm.prank(owner1.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_OwnerRemoved(address(SCW), owner2.pub);

        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.removeOwner.selector, address(SCW), owner2.pub)
        );

        assertFalse(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), owner2.pub), "Owner2 should be removed");
        assertEq(GUARDIAN_RECOVERY_VALIDATOR.getOwnerCount(address(SCW)), 1, "Owner count should be 1");
    }

    function testFuzz_removeOwner_RevertIf_LastOwner(string memory ownerName) public {
        User memory owner = _createUser(ownerName);

        // Install validator with one owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Try to remove the last owner
        vm.prank(owner.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_WalletNeedsOwner.selector, hex"");
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.removeOwner.selector, address(SCW), owner.pub)
        );
    }

    function testFuzz_removeOwner_RevertIf_InvalidOwner(string memory ownerName, string memory nonExistentName)
        public
    {
        vm.assume(keccak256(bytes(ownerName)) != keccak256(bytes(nonExistentName)));
        User memory owner = _createUser(ownerName);
        User memory nonExistent = _createUser(nonExistentName);
        // Install validator with one owner
        address[] memory initialOwners = new address[](2);
        initialOwners[0] = owner.pub;
        initialOwners[1] = eoa.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
        vm.prank(owner.pub);
        _toRevert(
            IGuardianRecoveryValidator.GRV_RemovingInvalidOwner.selector, abi.encode(address(SCW), nonExistent.pub)
        );
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.removeOwner.selector, address(SCW), nonExistent.pub)
        );
    }

    /*//////////////////////////////////////////////////////////////
                    GUARDIAN MANAGEMENT FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_addGuardian(string memory ownerName, string memory guardianName) public {
        vm.assume(keccak256(bytes(ownerName)) != keccak256(bytes(guardianName)));

        User memory owner = _createUser(ownerName);
        User memory guardian = _createUser(guardianName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Add guardian
        vm.prank(owner.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_GuardianAdded(address(SCW), guardian.pub);

        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addGuardian.selector, address(SCW), guardian.pub)
        );

        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isGuardian(address(SCW), guardian.pub), "Guardian should be added");
        assertEq(GUARDIAN_RECOVERY_VALIDATOR.getGuardianCount(address(SCW)), 1, "Guardian count should be 1");
    }

    function testFuzz_addGuardian_RevertIf_NotOwner(
        string memory ownerName,
        string memory nonOwnerName,
        string memory guardianName
    ) public {
        vm.assume(
            keccak256(bytes(ownerName)) != keccak256(bytes(nonOwnerName))
                && keccak256(bytes(ownerName)) != keccak256(bytes(guardianName))
                && keccak256(bytes(nonOwnerName)) != keccak256(bytes(guardianName))
        );

        User memory owner = _createUser(ownerName);
        User memory nonOwner = _createUser(nonOwnerName);
        User memory guardian = _createUser(guardianName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Try to add guardian from non-owner account
        vm.prank(nonOwner.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_NotOwner.selector, abi.encode(nonOwner.pub));
        GUARDIAN_RECOVERY_VALIDATOR.addGuardian(address(SCW), guardian.pub);
    }

    function testFuzz_addGuardian_RevertIf_AddingInvalidGuardian(string memory ownerName) public {
        User memory owner = _createUser(ownerName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Try to add zero address as guardian
        vm.prank(owner.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_AddingInvalidGuardian.selector, abi.encode(address(SCW), address(0)));
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addGuardian.selector, address(SCW), address(0))
        );
    }

    function testFuzz_addGuardian_RevertIf_AddingOwnerAsGuardian(string memory ownerName) public {
        User memory owner = _createUser(ownerName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Try to add owner as guardian
        vm.prank(owner.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_AddingInvalidGuardian.selector, abi.encode(address(SCW), owner.pub));
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addGuardian.selector, address(SCW), owner.pub)
        );
    }

    function testFuzz_removeGuardian(string memory ownerName, string memory guardianName) public {
        vm.assume(keccak256(bytes(ownerName)) != keccak256(bytes(guardianName)));

        User memory owner = _createUser(ownerName);
        User memory guardian = _createUser(guardianName);

        // Install validator with owner and guardian
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](1);
        initialGuardians[0] = guardian.pub;
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Remove guardian
        vm.prank(owner.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_GuardianRemoved(address(SCW), guardian.pub);

        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.removeGuardian.selector, address(SCW), guardian.pub)
        );

        assertFalse(GUARDIAN_RECOVERY_VALIDATOR.isGuardian(address(SCW), guardian.pub), "Guardian should be removed");
        assertEq(GUARDIAN_RECOVERY_VALIDATOR.getGuardianCount(address(SCW)), 0, "Guardian count should be 0");
    }

    function testFuzz_removeGuardian_RevertIf_RemovingInvalidGuardian(
        string memory ownerName,
        string memory nonGuardianName
    ) public {
        vm.assume(keccak256(bytes(ownerName)) != keccak256(bytes(nonGuardianName)));

        User memory owner = _createUser(ownerName);
        User memory nonGuardian = _createUser(nonGuardianName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Try to remove non-existent guardian
        vm.prank(owner.pub);
        _toRevert(
            IGuardianRecoveryValidator.GRV_RemovingInvalidGuardian.selector, abi.encode(address(SCW), nonGuardian.pub)
        );
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.removeGuardian.selector, address(SCW), nonGuardian.pub)
        );
    }

    /*//////////////////////////////////////////////////////////////
                      RECOVERY PROCESS FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_changeProposalTimelock(string memory ownerName, uint256 newTimelock) public {
        // Limit timelock to avoid test timeouts
        newTimelock = bound(newTimelock, 1, 100 days);

        User memory owner = _createUser(ownerName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Change proposal timelock
        vm.prank(owner.pub);
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

    function testFuzz_guardianPropose(string memory ownerName, string memory guardianName, string memory newOwnerName)
        public
    {
        vm.assume(
            keccak256(bytes(ownerName)) != keccak256(bytes(guardianName))
                && keccak256(bytes(ownerName)) != keccak256(bytes(newOwnerName))
                && keccak256(bytes(guardianName)) != keccak256(bytes(newOwnerName))
        );
        User memory owner = _createUser(ownerName);
        User memory guardian = _createUser(guardianName);
        User memory newOwner = _createUser(newOwnerName);
        // Install validator with owner and guardian
        _installValidatorWithAllGuardians();
        // Add guardian
        vm.prank(eoa.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addGuardian.selector, address(SCW), guardian.pub)
        );

        vm.prank(guardian.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_ProposalSubmitted(address(SCW), 1, newOwner.pub, guardian.pub);

        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), newOwner.pub);

        (address proposedOwner, uint256 approvalCount, address[] memory approvers, bool resolved, uint256 proposedAt) =
            _getProposalInfo(address(SCW), 1);

        assertEq(proposedOwner, newOwner.pub, "Proposed owner should match");
        assertEq(approvalCount, 1, "Approval count should be 1");
        assertEq(approvers[0], guardian.pub, "Approver should be the proposing guardian");
        assertFalse(resolved, "Proposal should not be resolved");
        assertEq(proposedAt, block.timestamp, "Proposal timestamp should be set correctly");
    }

    function testFuzz_guardianPropose_RevertIf_NotEnoughGuardians(string memory ownerName, string memory newOwnerName)
        public
    {
        vm.assume(keccak256(bytes(ownerName)) != keccak256(bytes(newOwnerName)));
        User memory owner = _createUser(ownerName);
        User memory newOwner = _createUser(newOwnerName);
        // Install validator with owner and no guardians
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](1);
        initialGuardians[0] = guardian1.pub;
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Add just one guardian
        vm.prank(owner.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addGuardian.selector, address(SCW), guardian2.pub)
        );

        vm.prank(guardian1.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_NotEnoughGuardians.selector, hex"");
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), newOwner.pub);
    }

    function testFuzz_guardianPropose_RevertIf_NotGuardian(string memory ownerName, string memory nonGuardianName)
        public
    {
        vm.assume(keccak256(bytes(ownerName)) != keccak256(bytes(nonGuardianName)));

        User memory owner = _createUser(ownerName);
        User memory nonGuardian = _createUser(nonGuardianName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Try to propose as non-guardian
        vm.prank(nonGuardian.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_NotGuardian.selector, abi.encode(nonGuardian.pub));
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), owner.pub);
    }

    function testFuzz_guardianPropose_RevertIf_ProposalUnresolved(
        string memory newOwnerName1,
        string memory newOwnerName2
    ) public {
        vm.assume(keccak256(bytes(newOwnerName1)) != keccak256(bytes(newOwnerName2)));

        User memory newOwner1 = _createUser(newOwnerName1);
        User memory newOwner2 = _createUser(newOwnerName2);

        _installValidatorWithAllGuardians();

        // Create a proposal
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), newOwner1.pub);

        // Try to create another proposal before resolving the first one
        vm.prank(guardian1.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_ProposalUnresolved.selector, hex"");
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), newOwner2.pub);
    }

    function testFuzz_guardianCosign(string memory newOwnerName) public {
        User memory newOwner = _createUser(newOwnerName);

        _installValidatorWithAllGuardians();

        // Create a proposal
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), newOwner.pub);

        // Cosign the proposal
        vm.prank(guardian2.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_QuorumReached(address(SCW), 1, newOwner.pub);

        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));

        // Check that the proposal is resolved and the new owner is added
        (,,, bool resolved,) = _getProposalInfo(address(SCW), 1);
        assertTrue(resolved, "Proposal should be resolved");
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), newOwner.pub), "New owner should be added");
    }

    function testFuzz_guardianCosign_QuorumNotReached(string memory newOwnerName) public {
        User memory newOwner = _createUser(newOwnerName);

        _installValidatorWithAllGuardians();

        // Add an extra guardian to increase the required quorum
        vm.prank(eoa.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(GUARDIAN_RECOVERY_VALIDATOR),
            0,
            abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addGuardian.selector, address(SCW), guardian4.pub)
        );

        // Create a proposal
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), newOwner.pub);

        // Second guardian cosigns
        vm.prank(guardian2.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_QuorumNotReached(address(SCW), 1, newOwner.pub, 2);

        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));

        // Check that the proposal is not resolved
        (,,, bool resolved,) = _getProposalInfo(address(SCW), 1);
        assertFalse(resolved, "Proposal should not be resolved yet");
        assertFalse(
            GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), newOwner.pub), "New owner should not be added yet"
        );
    }

    function testFuzz_guardianCosign_RevertIf_NotGuardian(string memory nonGuardianName) public {
        User memory nonGuardian = _createUser(nonGuardianName);

        _installValidatorWithAllGuardians();

        // Create a proposal
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);

        // Try to cosign from non-guardian account
        vm.prank(nonGuardian.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_NotGuardian.selector, abi.encode(nonGuardian.pub));
        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));
    }

    function testFuzz_guardianCosign_RevertIf_AlreadySignedProposal(string memory newOwnerName) public {
        User memory newOwner = _createUser(newOwnerName);

        _installValidatorWithAllGuardians();

        // Create a proposal
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), newOwner.pub);

        // Try to cosign with same guardian
        vm.prank(guardian1.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_AlreadySignedProposal.selector, hex"");
        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));
    }

    function testFuzz_discardCurrentProposal(string memory newOwnerName) public {
        User memory newOwner = _createUser(newOwnerName);

        _installValidatorWithAllGuardians();

        // Create a proposal
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), newOwner.pub);

        // Wait for timelock to pass
        vm.warp(block.timestamp + 24 hours + 1);

        // Discard the proposal
        vm.prank(guardian1.pub);
        vm.expectEmit(true, true, true, true);
        emit GRV_ProposalDiscarded(address(SCW), 1, guardian1.pub);

        GUARDIAN_RECOVERY_VALIDATOR.discardCurrentProposal(address(SCW));

        // Check that the proposal is resolved (discarded)
        (,,, bool resolved,) = _getProposalInfo(address(SCW), 1);
        assertTrue(resolved, "Proposal should be resolved (discarded)");
        assertFalse(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), newOwner.pub), "New owner should not be added");
    }

    function testFuzz_discardCurrentProposal_RevertIf_Timelocked(string memory newOwnerName) public {
        User memory newOwner = _createUser(newOwnerName);

        _installValidatorWithAllGuardians();

        // Create a proposal
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), newOwner.pub);

        // Try to discard before timelock expires
        vm.prank(guardian1.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_ProposalTimelocked.selector, hex"");
        GUARDIAN_RECOVERY_VALIDATOR.discardCurrentProposal(address(SCW));
    }

    function testFuzz_discardCurrentProposal_RevertIf_NotOwnerOrGuardianOrSelf(string memory nonUserName) public {
        User memory nonUser = _createUser(nonUserName);

        _installValidatorWithAllGuardians();

        // Create a proposal
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), alice.pub);

        // Wait for timelock to pass
        vm.warp(block.timestamp + 24 hours + 1);

        // Try to discard from non-owner, non-guardian account
        vm.prank(nonUser.pub);
        _toRevert(IGuardianRecoveryValidator.GRV_NotOwnerOrGuardianOrSelf.selector, abi.encode(nonUser.pub));
        GUARDIAN_RECOVERY_VALIDATOR.discardCurrentProposal(address(SCW));
    }

    /*//////////////////////////////////////////////////////////////
                    SIGNATURE VALIDATION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_validateUserOp(bytes32 userOpHash, string memory ownerName) public {
        User memory owner = _createUser(ownerName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Create and sign UserOp
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(GUARDIAN_RECOVERY_VALIDATOR));
        bytes memory signature = _sign(userOpHash, owner);
        userOp.signature = signature;

        vm.prank(address(SCW));
        uint256 validationResult = GUARDIAN_RECOVERY_VALIDATOR.validateUserOp(userOp, userOpHash);

        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation should succeed");
    }

    function testFuzz_validateUserOp_WithEthSign(bytes32 userOpHash, string memory ownerName) public {
        User memory owner = _createUser(ownerName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Create and sign UserOp with ethSign
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(GUARDIAN_RECOVERY_VALIDATOR));
        bytes memory signature = _ethSign(userOpHash, owner);
        userOp.signature = signature;

        vm.prank(address(SCW));
        uint256 validationResult = GUARDIAN_RECOVERY_VALIDATOR.validateUserOp(userOp, userOpHash);

        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation with ethSign should succeed");
    }

    function testFuzz_validateUserOp_RevertIf_InvalidSigner(
        bytes32 userOpHash,
        string memory ownerName,
        string memory nonOwnerName
    ) public {
        vm.assume(keccak256(bytes(ownerName)) != keccak256(bytes(nonOwnerName)));

        User memory owner = _createUser(ownerName);
        User memory nonOwner = _createUser(nonOwnerName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Create and sign UserOp with non-owner
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(GUARDIAN_RECOVERY_VALIDATOR));
        bytes memory signature = _sign(userOpHash, nonOwner);
        userOp.signature = signature;

        vm.prank(address(SCW));
        uint256 validationResult = GUARDIAN_RECOVERY_VALIDATOR.validateUserOp(userOp, userOpHash);

        assertEq(validationResult, SIG_VALIDATION_FAILED, "UserOp validation should fail with invalid signer");
    }

    function testFuzz_isValidSignatureWithSender(bytes32 hash, string memory ownerName) public {
        User memory owner = _createUser(ownerName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Create signature
        bytes memory signature = _sign(hash, owner);

        vm.prank(address(SCW));
        bytes4 result = GUARDIAN_RECOVERY_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);

        assertEq(result, bytes4(0x1626ba7e), "ERC1271 signature should be valid");
    }

    function testFuzz_isValidSignatureWithSender_WithEthSign(bytes32 hash, string memory ownerName) public {
        User memory owner = _createUser(ownerName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Create signature with ethSign
        bytes memory signature = _ethSign(hash, owner);

        vm.prank(address(SCW));
        bytes4 result = GUARDIAN_RECOVERY_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);

        assertEq(result, bytes4(0x1626ba7e), "ERC1271 signature with ethSign should be valid");
    }

    function testFuzz_isValidSignatureWithSender_RevertIf_InvalidSigner(
        bytes32 hash,
        string memory ownerName,
        string memory nonOwnerName
    ) public {
        vm.assume(keccak256(bytes(ownerName)) != keccak256(bytes(nonOwnerName)));

        User memory owner = _createUser(ownerName);
        User memory nonOwner = _createUser(nonOwnerName);

        // Install validator with owner
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);

        // Create signature with non-owner
        bytes memory signature = _sign(hash, nonOwner);

        vm.prank(address(SCW));
        bytes4 result = GUARDIAN_RECOVERY_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);

        assertEq(result, bytes4(0xffffffff), "ERC1271 signature should be invalid");
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_multipleRecoveryScenarios(
        string memory ownerName,
        string memory newOwnerName,
        uint8 guardianCount,
        uint8 cosignerFraction
    ) public {
        vm.assume(keccak256(bytes(ownerName)) != keccak256(bytes(newOwnerName)));
        guardianCount = uint8(bound(guardianCount, 3, 7));
        uint256 quorumNeeded = (guardianCount * 600 + 999) / 1000;
        uint8 maxCosigners = uint8(quorumNeeded > 1 ? quorumNeeded - 1 : 1);
        maxCosigners = maxCosigners < guardianCount - 1 ? maxCosigners : uint8(guardianCount - 1);
        cosignerFraction = uint8(bound(cosignerFraction, 1, 100));
        // Determine number of cosigners to use
        uint8 cosignersNeeded;
        if (cosignerFraction <= 50) {
            if (maxCosigners > 1) {
                cosignersNeeded = uint8(bound(cosignerFraction % maxCosigners, 1, maxCosigners - 1));
            } else {
                cosignersNeeded = 1;
            }
        } else {
            cosignersNeeded = maxCosigners;
        }
        require(cosignersNeeded >= 1 && cosignersNeeded < guardianCount, "Invalid cosignersNeeded");
        User memory owner = _createUser(ownerName);
        User memory newOwner = _createUser(newOwnerName);
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner.pub;
        address[] memory initialGuardians = new address[](guardianCount);
        User[] memory guardianUsers = new User[](guardianCount);
        for (uint8 i; i < guardianCount; ++i) {
            guardianUsers[i] = _createUser(string(abi.encodePacked("guardian", i)));
            initialGuardians[i] = guardianUsers[i].pub;
        }
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
        vm.prank(guardianUsers[0].pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), newOwner.pub);
        for (uint8 i = 1; i <= cosignersNeeded && i < guardianCount; ++i) {
            vm.prank(guardianUsers[i].pub);
            GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));
        }
        (,,, bool resolved,) = _getProposalInfo(address(SCW), 1);
        uint256 totalApprovals = 1 + cosignersNeeded;
        if (totalApprovals >= quorumNeeded) {
            assertTrue(resolved, "Proposal should be resolved with sufficient cosigners");
            assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), newOwner.pub), "New owner should be added");
        } else {
            assertFalse(resolved, "Proposal should not be resolved with insufficient cosigners");
            assertFalse(
                GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), newOwner.pub), "New owner should not be added"
            );
        }
    }

    function testFuzz_ownershipTransferScenario(
        string memory oldOwnerName,
        string memory newOwnerName,
        bytes32 userOpHash
    ) public {
        vm.assume(keccak256(bytes(oldOwnerName)) != keccak256(bytes(newOwnerName)));

        User memory oldOwner = _createUser(oldOwnerName);
        User memory newOwner = _createUser(newOwnerName);

        _installValidatorWithAllGuardians();

        // Guardian proposes recovery
        vm.prank(guardian1.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianPropose(address(SCW), newOwner.pub);

        // Second guardian cosigns to reach quorum
        vm.prank(guardian2.pub);
        GUARDIAN_RECOVERY_VALIDATOR.guardianCosign(address(SCW));

        // Verify new owner is added and can validate operations
        assertTrue(GUARDIAN_RECOVERY_VALIDATOR.isOwner(address(SCW), newOwner.pub), "New owner should be added");

        // Create and sign UserOp with new owner
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(GUARDIAN_RECOVERY_VALIDATOR));
        bytes memory signature = _sign(userOpHash, newOwner);
        userOp.signature = signature;

        vm.prank(address(SCW));
        uint256 validationResult = GUARDIAN_RECOVERY_VALIDATOR.validateUserOp(userOp, userOpHash);

        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "New owner should be able to validate operations");
    }
}
