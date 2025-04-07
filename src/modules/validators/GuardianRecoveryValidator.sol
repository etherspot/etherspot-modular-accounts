// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IGuardianRecoveryValidator} from "../../interfaces/modules/IGuardianRecoveryValidator.sol";
import {
    ERC1271_INVALID,
    ERC1271_MAGIC_VALUE,
    MODULE_TYPE_VALIDATOR,
    SIG_VALIDATION_SUCCESS,
    SIG_VALIDATION_FAILED
} from "../../types/Constants.sol";

/// @title GuardianRecoveryValidator
/// @author @cryptonoyaiba | Etherspot
/// @notice A validator module that enables social recovery through guardians
/// @dev Implements a guardian-based recovery system for smart accounts with quorum voting
contract GuardianRecoveryValidator is IGuardianRecoveryValidator {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Storage structure for validator configuration
    /// @param owners Array of owner addresses for the smart account
    /// @param guardians Array of guardian addresses for the smart account
    /// @param isOwner Mapping to quickly check if an address is an owner
    /// @param isGuardian Mapping to quickly check if an address is a guardian
    /// @param proposals Mapping from proposal ID to proposal data
    /// @param proposalId Current proposal ID counter
    /// @param proposalTimelock Time period before a proposal can be discarded
    /// @param ownerCount Number of owners
    /// @param guardianCount Number of guardians
    /// @param enabled Whether the validator is active
    struct ValidatorStorage {
        address[] owners;
        address[] guardians;
        mapping(address => bool) isOwner;
        mapping(address => bool) isGuardian;
        mapping(uint256 => NewOwnerProposal) proposals;
        uint256 proposalId;
        uint256 proposalTimelock;
        uint256 ownerCount;
        uint256 guardianCount;
        bool enabled;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Multiplication factor for percentage calculations
    uint128 constant MULTIPLY_FACTOR = 1000;

    /// @notice Threshold percentage for guardian approval (60%)
    uint16 constant SIXTY_PERCENT = 600;

    /// @notice Default timelock period for proposals (24 hours)
    uint24 constant INITIAL_PROPOSAL_TIMELOCK = 24 hours;

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps smart account addresses to their validator configuration
    mapping(address => ValidatorStorage) private validatorStorage;

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the validator when installed in a smart account
    /// @dev Sets up initial owners and guardians for the smart account
    /// @param data The installation data containing owners and guardians
    /// @custom:events Emits various events for initialization steps
    /// @custom:errors Various errors if initialization parameters are invalid
    function onInstall(bytes calldata data) external override {
        if (validatorStorage[msg.sender].enabled) {
            revert GRV_AlreadyInitialized(msg.sender);
        }
        address[] memory initialOwners;
        address[] memory initialGuardians;
        // Check if data starts with a function selector (bootstrap method)
        if (data.length >= 4 && data[0] != 0) {
            // Skip the function selector and try to decode
            try this.decodeBootstrapData(data) returns (address[] memory owners, address[] memory guardians) {
                initialOwners = owners;
                initialGuardians = guardians;
            } catch {
                // If that fails, try other methods or revert
                revert GRV_InvalidOwnerData();
            }
        } else {
            // Direct method - simple abi.encode
            (initialOwners, initialGuardians) = abi.decode(data, (address[], address[]));
        }
        if (initialOwners.length == 0) revert GRV_InvalidOwnerData();
        ValidatorStorage storage vs = validatorStorage[msg.sender];
        // Set up initial owners
        for (uint256 i; i < initialOwners.length; ++i) {
            address owner = initialOwners[i];
            if (owner == address(0) || vs.isOwner[owner] || vs.isGuardian[owner]) {
                revert GRV_AddingInvalidOwner(msg.sender, owner);
            }
            vs.owners.push(owner);
            vs.isOwner[owner] = true;
            vs.ownerCount++;
            emit GRV_OwnerAdded(msg.sender, owner);
        }
        // Set up initial guardians
        for (uint256 i; i < initialGuardians.length; ++i) {
            address guardian = initialGuardians[i];
            if (guardian == address(0) || vs.isOwner[guardian] || vs.isGuardian[guardian]) {
                revert GRV_AddingInvalidGuardian(msg.sender, guardian);
            }
            vs.guardians.push(guardian);
            vs.isGuardian[guardian] = true;
            vs.guardianCount++;
            emit GRV_GuardianAdded(msg.sender, guardian);
        }
        // Initialize proposal timelock
        vs.proposalTimelock = INITIAL_PROPOSAL_TIMELOCK;
        vs.enabled = true;
        emit GRV_ValidatorEnabled(msg.sender);
    }

    /// @notice Cleans up validator data when uninstalled from a smart account
    /// @dev Removes all validator configuration for the calling smart account
    /// @param data Unused parameter (required by interface)
    /// @custom:events Emits GRV_ValidatorDisabled when successfully uninstalled
    /// @custom:errors GRV_NotInitialized if not initialized for the smart account
    function onUninstall(bytes calldata data) external override {
        if (!_isInitialized(msg.sender)) revert GRV_NotInitialized(msg.sender);
        delete validatorStorage[msg.sender];
        emit GRV_ValidatorDisabled(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds a new owner to the smart account
    /// @dev Can only be called by the wallet itself or an existing owner
    /// @param _scw The address of the smart account
    /// @param _newOwner The address of the new owner to add
    /// @custom:events Emits GRV_OwnerAdded when an owner is successfully added
    /// @custom:errors Various errors if the owner is invalid or caller is unauthorized
    function addOwner(address _scw, address _newOwner) external {
        _onlyWalletOrOwner(_scw);

        ValidatorStorage storage vs = validatorStorage[_scw];
        if (_newOwner == address(0) || vs.isOwner[_newOwner] || vs.isGuardian[_newOwner]) {
            revert GRV_AddingInvalidOwner(_scw, _newOwner);
        }

        vs.owners.push(_newOwner);
        vs.isOwner[_newOwner] = true;
        vs.ownerCount++;

        emit GRV_OwnerAdded(_scw, _newOwner);
    }

    /// @notice Removes an owner from the smart account
    /// @dev Can only be called by the wallet itself or an existing owner
    /// @param _scw The address of the smart account
    /// @param _owner The address of the owner to remove
    /// @custom:events Emits GRV_OwnerRemoved when an owner is successfully removed
    /// @custom:errors Various errors if the owner is invalid or caller is unauthorized
    function removeOwner(address _scw, address _owner) external {
        _onlyWalletOrOwner(_scw);
        ValidatorStorage storage vs = validatorStorage[_scw];

        if (vs.ownerCount <= 1) {
            revert GRV_WalletNeedsOwner();
        }

        if (!vs.isOwner[_owner]) {
            revert GRV_RemovingInvalidOwner(_scw, _owner);
        }

        vs.isOwner[_owner] = false;
        vs.ownerCount--;

        // Remove from array
        for (uint256 i; i < vs.owners.length; ++i) {
            if (vs.owners[i] == _owner) {
                vs.owners[i] = vs.owners[vs.owners.length - 1];
                vs.owners.pop();
                break;
            }
        }

        emit GRV_OwnerRemoved(_scw, _owner);
    }

    /*//////////////////////////////////////////////////////////////
                        GUARDIAN MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds a new guardian to the smart account
    /// @dev Can only be called by the wallet itself or an existing owner
    /// @param _scw The address of the smart account
    /// @param _newGuardian The address of the new guardian to add
    /// @custom:events Emits GRV_GuardianAdded when a guardian is successfully added
    /// @custom:errors Various errors if the guardian is invalid or caller is unauthorized
    function addGuardian(address _scw, address _newGuardian) external {
        _onlyWalletOrOwner(_scw);

        ValidatorStorage storage vs = validatorStorage[_scw];
        if (_newGuardian == address(0) || vs.isGuardian[_newGuardian] || vs.isOwner[_newGuardian]) {
            revert GRV_AddingInvalidGuardian(_scw, _newGuardian);
        }

        vs.guardians.push(_newGuardian);
        vs.isGuardian[_newGuardian] = true;
        vs.guardianCount++;

        // If there's an unresolved proposal, discard it
        if (!_resolvedProposal(_scw)) {
            _discardCurrentProposal(_scw);
        }

        emit GRV_GuardianAdded(_scw, _newGuardian);
    }

    /// @notice Removes a guardian from the smart account
    /// @dev Can only be called by the wallet itself or an existing owner
    /// @param _scw The address of the smart account
    /// @param _guardian The address of the guardian to remove
    /// @custom:events Emits GRV_GuardianRemoved when a guardian is successfully removed
    /// @custom:errors Various errors if the guardian is invalid or caller is unauthorized
    function removeGuardian(address _scw, address _guardian) external {
        _onlyWalletOrOwner(_scw);
        ValidatorStorage storage vs = validatorStorage[_scw];

        if (!vs.isGuardian[_guardian]) {
            revert GRV_RemovingInvalidGuardian(_scw, _guardian);
        }

        vs.isGuardian[_guardian] = false;
        vs.guardianCount--;

        // Remove from array
        for (uint256 i; i < vs.guardians.length; ++i) {
            if (vs.guardians[i] == _guardian) {
                vs.guardians[i] = vs.guardians[vs.guardians.length - 1];
                vs.guardians.pop();
                break;
            }
        }

        // If there's an unresolved proposal, discard it
        if (!_resolvedProposal(_scw)) {
            _discardCurrentProposal(_scw);
        }

        emit GRV_GuardianRemoved(_scw, _guardian);
    }

    /*//////////////////////////////////////////////////////////////
                        PROPOSAL MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Changes the timelock period for proposals
    /// @dev Can only be called by the wallet itself or an existing owner
    /// @param _scw The address of the smart account
    /// @param _newTimelock The new timelock period in seconds
    /// @custom:events Emits GRV_ProposalTimelockChanged when timelock is updated
    function changeProposalTimelock(address _scw, uint256 _newTimelock) external {
        _onlyWalletOrOwner(_scw);
        validatorStorage[_scw].proposalTimelock = _newTimelock;
        emit GRV_ProposalTimelockChanged(_scw, _newTimelock);
    }

    /// @notice Creates a new recovery proposal to add a new owner
    /// @dev Can only be called by a guardian of the smart account
    /// @param _scw The address of the smart account
    /// @param _newOwner The address of the proposed new owner
    /// @custom:events Emits GRV_ProposalSubmitted when a proposal is created
    /// @custom:errors Various errors if parameters are invalid or caller is unauthorized
    function guardianPropose(address _scw, address _newOwner) external {
        ValidatorStorage storage vs = validatorStorage[_scw];

        if (!vs.isGuardian[msg.sender]) {
            revert GRV_NotGuardian(msg.sender);
        }

        if (_newOwner == address(0) || vs.isGuardian[_newOwner] || vs.isOwner[_newOwner]) {
            revert GRV_AddingInvalidOwner(_scw, _newOwner);
        }

        if (vs.guardianCount < 3) {
            revert GRV_NotEnoughGuardians();
        }

        NewOwnerProposal storage prop = vs.proposals[vs.proposalId];
        if (prop.guardiansApproved.length != 0 && !prop.resolved) {
            revert GRV_ProposalUnresolved();
        }

        uint256 newProposalId = vs.proposalId + 1;
        NewOwnerProposal storage newProp = vs.proposals[newProposalId];
        newProp.newOwnerProposed = _newOwner;
        newProp.guardiansApproved.push(msg.sender);
        newProp.approvalCount = 1;
        newProp.resolved = false;
        newProp.proposedAt = block.timestamp;
        vs.proposalId = newProposalId;

        emit GRV_ProposalSubmitted(_scw, newProposalId, _newOwner, msg.sender);
    }

    /// @notice Allows a guardian to cosign an existing recovery proposal
    /// @dev If enough guardians approve, the proposal is executed
    /// @param _scw The address of the smart account
    /// @custom:events Emits various events based on the outcome of the cosigning
    /// @custom:errors Various errors if conditions are not met
    function guardianCosign(address _scw) external {
        ValidatorStorage storage vs = validatorStorage[_scw];

        if (!vs.isGuardian[msg.sender]) {
            revert GRV_NotGuardian(msg.sender);
        }

        uint256 latestId = vs.proposalId;
        if (latestId == 0) {
            revert GRV_InvalidProposal();
        }

        NewOwnerProposal storage latestProp = vs.proposals[latestId];

        if (_checkIfSigned(_scw, latestId)) {
            revert GRV_AlreadySignedProposal();
        }

        if (latestProp.resolved) {
            revert GRV_ProposalResolved();
        }

        latestProp.guardiansApproved.push(msg.sender);
        latestProp.approvalCount++;

        address newOwner = latestProp.newOwnerProposed;

        if (_checkQuorumReached(_scw, latestId)) {
            latestProp.resolved = true;

            // Add the new owner
            vs.owners.push(newOwner);
            vs.isOwner[newOwner] = true;
            vs.ownerCount++;

            emit GRV_QuorumReached(_scw, latestId, newOwner);
            emit GRV_OwnerAdded(_scw, newOwner);
        } else {
            emit GRV_QuorumNotReached(_scw, latestId, newOwner, latestProp.approvalCount);
        }
    }

    /// @notice Discards the current recovery proposal
    /// @dev Can be called by owners, guardians, or the wallet itself
    /// @param _scw The address of the smart account
    /// @custom:events Emits GRV_ProposalDiscarded when a proposal is discarded
    /// @custom:errors Various errors if conditions are not met
    function discardCurrentProposal(address _scw) external {
        ValidatorStorage storage vs = validatorStorage[_scw];

        if (!vs.isOwner[msg.sender] && !vs.isGuardian[msg.sender] && msg.sender != _scw) {
            revert GRV_NotOwnerOrGuardianOrSelf(msg.sender);
        }

        _discardCurrentProposal(_scw);
    }

    /*//////////////////////////////////////////////////////////////
                        VALIDATOR PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates a user operation signed by an owner
    /// @dev Implements the ERC-4337 validation interface
    /// @param userOp The packed user operation to validate
    /// @param userOpHash The hash of the user operation for signature verification
    /// @return uint256 Validation result (success or failure)
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        override
        returns (uint256)
    {
        bytes calldata sig = userOp.signature;

        // If the signature is just a standard ECDSA signature (65 bytes)
        if (sig.length == 65) {
            address recovered = ECDSA.recover(userOpHash, sig);
            if (recovered == address(0) || !_isOwner(msg.sender, recovered)) {
                bytes32 ethHash = userOpHash.toEthSignedMessageHash();
                recovered = ECDSA.recover(ethHash, sig);
                if (recovered == address(0) || !_isOwner(msg.sender, recovered)) {
                    return SIG_VALIDATION_FAILED;
                }
            }
            return SIG_VALIDATION_SUCCESS;
        }

        // If it's a more complex signature format (potentially for guardian recovery)
        // Add custom recovery logic if needed for recovery operations

        return SIG_VALIDATION_FAILED;
    }

    /// @notice ERC-1271 signature validation
    /// @dev Implements the ERC-1271 validation interface
    /// @param sender The address of the sender requesting validation
    /// @param hash The hash of the data that was signed
    /// @param signature The signature to validate
    /// @return bytes4 Magic value if signature is valid, error value otherwise
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        override
        returns (bytes4)
    {
        address recovered = ECDSA.recover(hash, signature);
        if (_isOwner(msg.sender, recovered)) {
            return ERC1271_MAGIC_VALUE;
        }

        bytes32 ethHash = ECDSA.toEthSignedMessageHash(hash);
        recovered = ECDSA.recover(ethHash, signature);
        if (_isOwner(msg.sender, recovered)) {
            return ERC1271_MAGIC_VALUE;
        }

        return ERC1271_INVALID;
    }

    /// @notice Checks if the module is initialized for a specific smart account
    /// @param smartAccount Address of the smart account to check
    /// @return bool True if the module is initialized, false otherwise
    function isInitialized(address smartAccount) external view override returns (bool) {
        return _isInitialized(smartAccount);
    }

    /// @notice Checks if this module supports the specified module type
    /// @param typeID The module type identifier to check
    /// @return bool True if this module is a validator module
    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == MODULE_TYPE_VALIDATOR;
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if an address is an owner of the smart account
    /// @param _scw The address of the smart account
    /// @param _owner The address to check
    /// @return bool True if the address is an owner, false otherwise
    function isOwner(address _scw, address _owner) external view returns (bool) {
        return _isOwner(_scw, _owner);
    }

    /// @notice Checks if an address is a guardian of the smart account
    /// @param _scw The address of the smart account
    /// @param _guardian The address to check
    /// @return bool True if the address is a guardian, false otherwise
    function isGuardian(address _scw, address _guardian) external view returns (bool) {
        return validatorStorage[_scw].isGuardian[_guardian];
    }

    /// @notice Gets the list of owners for a smart account
    /// @param _scw The address of the smart account
    /// @return address[] Array of owner addresses
    function getOwners(address _scw) external view returns (address[] memory) {
        return validatorStorage[_scw].owners;
    }

    /// @notice Gets the list of guardians for a smart account
    /// @param _scw The address of the smart account
    /// @return address[] Array of guardian addresses
    function getGuardians(address _scw) external view returns (address[] memory) {
        return validatorStorage[_scw].guardians;
    }

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
        )
    {
        if (_proposalId == 0 || _proposalId > validatorStorage[_scw].proposalId) {
            revert GRV_InvalidProposal();
        }

        NewOwnerProposal storage proposal = validatorStorage[_scw].proposals[_proposalId];
        return (
            proposal.newOwnerProposed,
            proposal.approvalCount,
            proposal.guardiansApproved,
            proposal.resolved,
            proposal.proposedAt
        );
    }

    /// @notice Gets the current proposal ID for a smart account
    /// @param _scw The address of the smart account
    /// @return uint256 The current proposal ID
    function getCurrentProposalId(address _scw) external view returns (uint256) {
        return validatorStorage[_scw].proposalId;
    }

    /// @notice Gets the number of owners for a smart account
    /// @param _scw The address of the smart account
    /// @return uint256 The number of owners
    function getOwnerCount(address _scw) external view returns (uint256) {
        return validatorStorage[_scw].ownerCount;
    }

    /// @notice Gets the number of guardians for a smart account
    /// @param _scw The address of the smart account
    /// @return uint256 The number of guardians
    function getGuardianCount(address _scw) external view returns (uint256) {
        return validatorStorage[_scw].guardianCount;
    }

    /// @notice Gets the proposal timelock period for a smart account
    /// @param _scw The address of the smart account
    /// @return uint256 The proposal timelock in seconds
    function getProposalTimelock(address _scw) external view returns (uint256) {
        return validatorStorage[_scw].proposalTimelock;
    }

    /// @notice Helper function to decode bootstrap data
    /// @dev Handles complex nested ABI encoding from bootstrap calls
    /// @param data The encoded bootstrap data
    /// @return owners Array of owner addresses
    /// @return guardians Array of guardian addresses
    function decodeBootstrapData(bytes calldata data)
        external
        pure
        returns (address[] memory owners, address[] memory guardians)
    {
        // Skip function selector (4 bytes)
        bytes calldata actualData = data[4:];
        // For complex nested structures, we need to navigate through the ABI encoding
        // First 32 bytes after selector is often a pointer to where the actual data begins
        uint256 dataPtr;
        assembly {
            dataPtr := calldataload(add(actualData.offset, 0))
        }
        // If dataPtr is a reasonable offset
        if (dataPtr >= 32 && dataPtr < data.length) {
            bytes calldata offsetData = actualData[dataPtr:];
            // Try to decode the data at the offset
            return abi.decode(offsetData, (address[], address[]));
        }
        // If that doesn't work, try to decode the data directly
        return abi.decode(actualData, (address[], address[]));
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL/PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if the validator is initialized for a smart account
    /// @param _scw The address of the smart account
    /// @return bool True if initialized, false otherwise
    function _isInitialized(address _scw) internal view returns (bool) {
        return validatorStorage[_scw].enabled;
    }

    /// @notice Checks if an address is an owner of the smart account
    /// @param _scw The address of the smart account
    /// @param _owner The address to check
    /// @return bool True if the address is an owner, false otherwise
    function _isOwner(address _scw, address _owner) internal view returns (bool) {
        return validatorStorage[_scw].isOwner[_owner];
    }

    /// @notice Verifies that the caller is either the wallet itself or an owner
    /// @param _scw The address of the smart account
    /// @custom:errors GRV_NotOwner if the caller is not authorized
    function _onlyWalletOrOwner(address _scw) internal view {
        if (msg.sender != _scw && !_isOwner(_scw, msg.sender)) {
            revert GRV_NotOwner(msg.sender);
        }
    }

    /// @notice Checks if the current proposal is resolved
    /// @param _scw The address of the smart account
    /// @return bool True if the proposal is resolved, false otherwise
    function _resolvedProposal(address _scw) internal view returns (bool) {
        uint256 proposalId = validatorStorage[_scw].proposalId;
        if (proposalId == 0) return true; // No proposals yet
        return validatorStorage[_scw].proposals[proposalId].resolved;
    }

    /// @notice Checks if the caller has already signed a proposal
    /// @param _scw The address of the smart account
    /// @param _proposalId The ID of the proposal to check
    /// @return bool True if the caller has already signed, false otherwise
    function _checkIfSigned(address _scw, uint256 _proposalId) internal view returns (bool) {
        address[] storage approvers = validatorStorage[_scw].proposals[_proposalId].guardiansApproved;
        for (uint256 i; i < approvers.length; ++i) {
            if (approvers[i] == msg.sender) {
                return true;
            }
        }
        return false;
    }

    /// @notice Checks if a proposal has reached the required quorum
    /// @param _scw The address of the smart account
    /// @param _proposalId The ID of the proposal to check
    /// @return bool True if quorum is reached, false otherwise
    function _checkQuorumReached(address _scw, uint256 _proposalId) internal view returns (bool) {
        ValidatorStorage storage vs = validatorStorage[_scw];
        return ((vs.proposals[_proposalId].approvalCount * MULTIPLY_FACTOR) / vs.guardianCount >= SIXTY_PERCENT);
    }

    /// @notice Internal function to discard the current proposal
    /// @param _scw The address of the smart account
    /// @custom:events Emits GRV_ProposalDiscarded when a proposal is discarded
    /// @custom:errors Various errors if conditions are not met
    function _discardCurrentProposal(address _scw) internal {
        ValidatorStorage storage vs = validatorStorage[_scw];
        uint256 currentProposalId = vs.proposalId;

        if (currentProposalId == 0) return; // No proposals to discard

        NewOwnerProposal storage prop = vs.proposals[currentProposalId];

        if (prop.resolved) {
            revert GRV_ProposalResolved();
        }

        // If caller is a guardian, check the timelock
        if (vs.isGuardian[msg.sender] && !vs.isOwner[msg.sender] && msg.sender != _scw) {
            uint256 timelock = vs.proposalTimelock == 0 ? INITIAL_PROPOSAL_TIMELOCK : vs.proposalTimelock;
            if (prop.proposedAt + timelock >= block.timestamp) {
                revert GRV_ProposalTimelocked();
            }
        }

        prop.resolved = true;
        emit GRV_ProposalDiscarded(_scw, currentProposalId, msg.sender);
    }
}
