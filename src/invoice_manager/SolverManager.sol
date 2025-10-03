// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ISolverManager} from "../interfaces/ISolverManager.sol";

/**
 * @title SolverManager
 * @notice Manages solver onboarding, offboarding, and configuration
 * @author Etherspot
 * @dev Provides solver management functionality to be inherited by InvoiceManager
 */
abstract contract SolverManager is ISolverManager, AccessControlEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant SOLVER_MANAGER_ROLE = keccak256("SOLVER_MANAGER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    uint256 public constant PULSE_BASE_FEE = 5;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => Solver) public solvers;
    mapping(address => EnumerableSet.AddressSet) internal solverInvoices;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    // Events are defined in ISolverManager interface

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error SM_InvalidSolver();
    error SM_SolverAlreadyExists();
    error SM_InvalidAddress();
    error SM_SolverInactive();
    error SM_SolverCannotSettle();
    error SM_SolverHasPendingInvoices();

    /*//////////////////////////////////////////////////////////////
                        SOLVER MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a new solver with specified name and fee structure
     * @param _solver Address of the solver to onboard
     * @param _name Human-readable name for the solver
     * @param _pulseFee Fee in cents (0 = use default 5 cents, >0 = custom fee amount)
     * @dev Only callable by addresses with SOLVER_MANAGER_ROLE
     * @dev Solver address cannot be zero and must not already exist
     */
    function onboardSolver(address _solver, string calldata _name, uint256 _pulseFee)
        external
        onlyRole(SOLVER_MANAGER_ROLE)
    {
        if (_solver == address(0)) revert SM_InvalidAddress();
        Solver storage solver = solvers[_solver];
        if (solver.solverAddress != address(0)) revert SM_SolverAlreadyExists();

        solver.solverAddress = _solver;
        solver.isActive = true;
        solver.pendingOffboard = false;
        solver.successfulSettlements = 0;
        solver.pulseFee = _pulseFee; // 0 = use default calculated fee, >0 = use custom fee
        solver.name = _name;

        emit SolverOnboarded(_solver, _name, _pulseFee);
    }

    /**
     * @notice Updates the fee structure for an existing solver
     * @param _solver Address of the solver to update
     * @param _newFee New fee amount in cents (0 = use default, >0 = custom)
     * @dev Only callable by addresses with FEE_MANAGER_ROLE
     * @dev Only affects future invoices, existing invoices retain their snapshotted fees
     */
    function updateSolverFee(address _solver, uint256 _newFee) external onlyRole(FEE_MANAGER_ROLE) {
        Solver storage solver = solvers[_solver];
        if (solver.solverAddress == address(0)) revert SM_InvalidSolver();

        uint256 oldFee = solver.pulseFee;
        solver.pulseFee = _newFee;

        emit SolverFeeUpdated(_solver, oldFee, _newFee);
    }

    /**
     * @notice Removes a solver from the system and cleans up associated data
     * @param _solver Address of the solver to remove
     * @dev Only callable by addresses with SOLVER_MANAGER_ROLE
     * @dev Will mark as pendingOffboard if solver has outstanding invoices
     * @dev If solver has no outstanding invoices, deletes solver data and associated invoice mappings
     */
    function offboardSolver(address _solver) external onlyRole(SOLVER_MANAGER_ROLE) {
        if (solvers[_solver].solverAddress == address(0)) revert SM_InvalidSolver();

        uint256 pendingInvoices = solverInvoices[_solver].length();

        if (pendingInvoices > 0) {
            // Marked as pending offboard (can't accept new invoices)
            solvers[_solver].isActive = false;
            solvers[_solver].pendingOffboard = true;
            emit SolverMarkedForOffboarding(_solver, pendingInvoices);
        } else {
            // Complete removal (no pending invoices)
            delete solverInvoices[_solver];
            delete solvers[_solver];
            emit SolverOffboarded(_solver);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            SOLVER VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves data for a solver
     * @param _solver Address of the solver to query
     * @return name Human-readable name of the solver
     * @return isActive Whether the solver is currently active
     * @return pendingOffboard Where the solver is being offboarded but has active invoices
     * @return successfulSettlements Number of invoices successfully settled
     * @return activeInvoices Number of currently active invoices
     * @return pulseFee Current fee setting in cents
     */
    function getSolverData(address _solver)
        external
        view
        returns (
            string memory name,
            bool isActive,
            bool pendingOffboard,
            uint256 successfulSettlements,
            uint256 activeInvoices,
            uint256 pulseFee
        )
    {
        Solver storage solver = solvers[_solver];
        return (
            solver.name,
            solver.isActive,
            solver.pendingOffboard,
            solver.successfulSettlements,
            solverInvoices[_solver].length(),
            solver.pulseFee
        );
    }

    /**
     * @notice Gets all active invoice session keys for a specific solver
     * @param _solver Address of the solver to query
     * @return Array of session key addresses for active invoices
     */
    function getSolverInvoices(address _solver) external view returns (address[] memory) {
        return solverInvoices[_solver].values();
    }

    /**
     * @notice Batch retrieval of multiple solver information
     * @param _solvers Array of solver addresses to retrieve
     * @return solvers_ Array of Solver structs
     * @dev Returns empty struct for non-existent solvers
     */
    function getMultipleSolvers(address[] calldata _solvers) external view returns (Solver[] memory solvers_) {
        uint256 solversLength = _solvers.length;
        solvers_ = new Solver[](solversLength);
        for (uint256 i; i < solversLength; ++i) {
            solvers_[i] = solvers[_solvers[i]];
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the effective fee amount for a solver (custom or default)
     * @param _solver Solver address
     * @return feeAmount The fee amount to use (0 means use calculated default)
     */
    function _getSolverFeeAmount(address _solver) internal view returns (uint256 feeAmount) {
        return solvers[_solver].pulseFee; // 0 means use default, non-zero means custom
    }

    /**
     * @notice Internal function to add an invoice to solver's active invoices
     * @param _solver Solver address
     * @param _sessionKey Session key to add
     */
    function _addSolverInvoice(address _solver, address _sessionKey) internal {
        solverInvoices[_solver].add(_sessionKey);
    }

    /**
     * @notice Internal function to remove an invoice from solver's active invoices
     * @param _solver Solver address
     * @param _sessionKey Session key to remove
     */
    function _removeSolverInvoice(address _solver, address _sessionKey) internal {
        solverInvoices[_solver].remove(_sessionKey);
    }

    /**
     * @notice Internal function to increment solver's successful settlements
     * @param _solver Solver address
     */
    function _incrementSolverSettlements(address _solver) internal {
        unchecked {
            solvers[_solver].successfulSettlements++;
        }
    }

    /**
     * @notice Internal function to check if solver is active
     * @param _solver Solver address
     * @return True if solver exists and is active
     */
    function _isSolverActive(address _solver) internal view returns (bool) {
        return solvers[_solver].isActive;
    }

    /**
     * @notice Internal function to check if solver can settle invoices
     * @param _solver Solver address
     * @return True if solver is pending offboard or is active
     */
    function _canSolverSettle(address _solver) internal view returns (bool) {
        Solver memory solver = solvers[_solver];
        return solver.isActive || solver.pendingOffboard; // Can settle if active OR pending offboard
    }

    /*//////////////////////////////////////////////////////////////
                            ROLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Grants SOLVER_MANAGER_ROLE to an address
     * @param _account Address to grant the role to
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function grantSolverManagerRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(SOLVER_MANAGER_ROLE, _account);
    }

    /**
     * @notice Revokes SOLVER_MANAGER_ROLE from an address
     * @param _account Address to revoke the role from
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function revokeSolverManagerRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(SOLVER_MANAGER_ROLE, _account);
    }

    /**
     * @notice Grants FEE_MANAGER_ROLE to an address
     * @param _account Address to grant the role to
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function grantFeeManagerRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(FEE_MANAGER_ROLE, _account);
    }

    /**
     * @notice Revokes FEE_MANAGER_ROLE from an address
     * @param _account Address to revoke the role from
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function revokeFeeManagerRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(FEE_MANAGER_ROLE, _account);
    }
}
