// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IValidator} from "../base/IValidator.sol";

/// @title IGuardianRecoveryValidator
/// @author @cryptonoyaiba | Etherspot
/// @notice Interface for a validator module that enables social recovery through guardians
/// @dev Defines functions for guardian-based recovery system with quorum voting
interface IGuardianRecoveryValidator is IValidator {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Structure for storing recovery proposals
    /// @param newOwnerProposed The address proposed to become a new owner
    /// @param guardiansApproved Array of guardian addresses that have approved the proposal
    /// @param approvalCount Number of guardians that have approved the proposal
    /// @param resolved Whether the proposal has been resolved (approved or discarded)
    /// @param proposedAt Timestamp when the proposal was created
    struct NewOwnerProposal {
        address newOwnerProposed;
        address[] guardiansApproved;
        uint256 approvalCount;
        bool resolved;
        uint256 proposedAt;
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a non-owner tries to perform an owner-only action
    error GRV_NotOwner(address caller);

    /// @notice Thrown when a non-guardian tries to perform a guardian-only action
    error GRV_NotGuardian(address caller);

    /// @notice Thrown when an action requires either owner or guardian status
    error GRV_NotOwnerOrGuardian(address caller);

    /// @notice Thrown when an action requires owner, guardian, or wallet status
    error GRV_NotOwnerOrGuardianOrSelf(address caller);

    /// @notice Thrown when trying to initialize an already initialized validator
    error GRV_AlreadyInitialized(address scw);

    /// @notice Thrown when trying to use an uninitialized validator
    error GRV_NotInitialized(address scw);

    /// @notice Thrown when the provided owner data is invalid
    error GRV_InvalidOwnerData();

    /// @notice Thrown when trying to add an invalid owner
    error GRV_AddingInvalidOwner(address scw, address owner);

    /// @notice Thrown when trying to remove an invalid owner
    error GRV_RemovingInvalidOwner(address scw, address owner);

    /// @notice Thrown when trying to remove the last owner
    error GRV_CannotRemoveLastOwner(address scw);

    /// @notice Thrown when trying to add an invalid guardian
    error GRV_AddingInvalidGuardian(address scw, address guardian);

    /// @notice Thrown when trying to remove an invalid guardian
    error GRV_RemovingInvalidGuardian(address scw, address guardian);

    /// @notice Thrown when trying to remove the last owner
    error GRV_WalletNeedsOwner();

    /// @notice Thrown when there are not enough guardians for recovery
    error GRV_NotEnoughGuardians();

    /// @notice Thrown when trying to act on a resolved proposal
    error GRV_ProposalResolved();

    /// @notice Thrown when a proposal is still unresolved
    error GRV_ProposalUnresolved();

    /// @notice Thrown when a guardian tries to sign a proposal twice
    error GRV_AlreadySignedProposal();

    /// @notice Thrown when trying to discard a proposal during timelock
    error GRV_ProposalTimelocked();

    /// @notice Thrown when trying to access an invalid proposal
    error GRV_InvalidProposal();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the validator is enabled for a smart account
    event GRV_ValidatorEnabled(address indexed scw);

    /// @notice Emitted when the validator is disabled for a smart account
    event GRV_ValidatorDisabled(address indexed scw);

    /// @notice Emitted when an owner is added to a smart account
    event GRV_OwnerAdded(address indexed scw, address indexed owner);

    /// @notice Emitted when an owner is removed from a smart account
    event GRV_OwnerRemoved(address indexed scw, address indexed owner);

    /// @notice Emitted when a guardian is added to a smart account
    event GRV_GuardianAdded(address indexed scw, address indexed guardian);

    /// @notice Emitted when a guardian is removed from a smart account
    event GRV_GuardianRemoved(address indexed scw, address indexed guardian);

    /// @notice Emitted when a new recovery proposal is submitted
    event GRV_ProposalSubmitted(address indexed scw, uint256 indexed proposalId, address newOwner, address proposer);

    /// @notice Emitted when a proposal is discarded
    event GRV_ProposalDiscarded(address indexed scw, uint256 indexed proposalId, address caller);

    /// @notice Emitted when a proposal reaches quorum and is approved
    event GRV_QuorumReached(address indexed scw, uint256 indexed proposalId, address newOwner);

    /// @notice Emitted when a guardian signs but quorum is not yet reached
    event GRV_QuorumNotReached(
        address indexed scw, uint256 indexed proposalId, address newOwner, uint256 approvalCount
    );

    /// @notice Emitted when the proposal timelock is changed
    event GRV_ProposalTimelockChanged(address indexed scw, uint256 newTimelock);

    /*//////////////////////////////////////////////////////////////
                        PUBLIC/EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds a new owner to the smart account
    /// @param _scw The address of the smart account
    /// @param _newOwner The address of the new owner to add
    function addOwner(address _scw, address _newOwner) external;

    /// @notice Removes an owner from the smart account
    /// @param _scw The address of the smart account
    /// @param _owner The address of the owner to remove
    function removeOwner(address _scw, address _owner) external;

    /// @notice Adds a new guardian to the smart account
    /// @param _scw The address of the smart account
    /// @param _newGuardian The address of the new guardian to add
    function addGuardian(address _scw, address _newGuardian) external;

    /// @notice Removes a guardian from the smart account
    /// @param _scw The address of the smart account
    /// @param _guardian The address of the guardian to remove
    function removeGuardian(address _scw, address _guardian) external;

    /// @notice Changes the timelock period for proposals
    /// @param _scw The address of the smart account
    /// @param _newTimelock The new timelock period in seconds
    function changeProposalTimelock(address _scw, uint256 _newTimelock) external;

    /// @notice Creates a new recovery proposal to add a new owner
    /// @param _scw The address of the smart account
    /// @param _newOwner The address of the proposed new owner
    function guardianPropose(address _scw, address _newOwner) external;

    /// @notice Allows a guardian to cosign an existing recovery proposal
    /// @param _scw The address of the smart account
    function guardianCosign(address _scw) external;

    /// @notice Discards the current recovery proposal
    /// @param _scw The address of the smart account
    function discardCurrentProposal(address _scw) external;

    /// @notice Checks if an address is an owner of the smart account
    /// @param _scw The address of the smart account
    /// @param _owner The address to check
    /// @return bool True if the address is an owner, false otherwise
    function isOwner(address _scw, address _owner) external view returns (bool);

    /// @notice Checks if an address is a guardian of the smart account
    /// @param _scw The address of the smart account
    /// @param _guardian The address to check
    /// @return bool True if the address is a guardian, false otherwise
    function isGuardian(address _scw, address _guardian) external view returns (bool);

    /// @notice Gets the list of owners for a smart account
    /// @param _scw The address of the smart account
    /// @return address[] Array of owner addresses
    function getOwners(address _scw) external view returns (address[] memory);

    /// @notice Gets the list of guardians for a smart account
    /// @param _scw The address of the smart account
    /// @return address[] Array of guardian addresses
    function getGuardians(address _scw) external view returns (address[] memory);

    /// @notice Gets the details of a specific proposal
    /// @param _scw The address of the smart account
    /// @param _proposalId The ID of the proposal to retrieve
    /// @return ownerProposed_ The proposed new owner address
    /// @return approvalCount_ Number of guardians that have approved
    /// @return guardiansApproved_ Array of guardian addresses that have approved
    /// @return resolved_ Whether the proposal has been resolved
    /// @return proposedAt_ Timestamp when the proposal was created
    function getProposal(address _scw, uint256 _proposalId)
        external
        view
        returns (
            address ownerProposed_,
            uint256 approvalCount_,
            address[] memory guardiansApproved_,
            bool resolved_,
            uint256 proposedAt_
        );

    /// @notice Gets the current proposal ID for a smart account
    /// @param _scw The address of the smart account
    /// @return uint256 The current proposal ID
    function getCurrentProposalId(address _scw) external view returns (uint256);

    /// @notice Gets the number of owners for a smart account
    /// @param _scw The address of the smart account
    /// @return uint256 The number of owners
    function getOwnerCount(address _scw) external view returns (uint256);

    /// @notice Gets the number of guardians for a smart account
    /// @param _scw The address of the smart account
    /// @return uint256 The number of guardians
    function getGuardianCount(address _scw) external view returns (uint256);

    /// @notice Gets the proposal timelock period for a smart account
    /// @param _scw The address of the smart account
    /// @return uint256 The proposal timelock in seconds
    function getProposalTimelock(address _scw) external view returns (uint256);

    /// @notice Helper function to decode bootstrap data
    /// @param data The encoded bootstrap data
    /// @return owners Array of owner addresses
    /// @return guardians Array of guardian addresses
    function decodeBootstrapData(bytes calldata data)
        external
        pure
        returns (address[] memory owners, address[] memory guardians);
}
