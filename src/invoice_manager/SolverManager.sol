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
    uint256 public constant MAX_FEE_PERCENTAGE = 10000; // 100% in basis points
    uint256 public constant MAX_FEE_FIXED = 10000; // $100 in cents (100.00)

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => Solver) public solvers;
    mapping(address => EnumerableSet.AddressSet) internal solverInvoices;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error SM_InvalidSolver();
    error SM_SolverAlreadyExists();
    error SM_InvalidAddress();
    error SM_SolverInactive();
    error SM_SolverCannotSettle();
    error SM_SolverHasPendingInvoices();
    error SM_FeeValueTooHigh();
    error SM_SolverPendingOffboard();

    /*//////////////////////////////////////////////////////////////
                        SOLVER MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc ISolverManager
    function onboardSolver(
        address _executionAddress,
        address _feeAddress,
        address _orchestratorReceiver,
        string calldata _name,
        FeeType _orchestratorFeeType,
        uint256 _orchestratorFeeValue,
        FeeType _solverFeeType,
        uint256 _solverFeeValue
    ) external onlyRole(SOLVER_MANAGER_ROLE) {
        if (_executionAddress == address(0) || _feeAddress == address(0) || _orchestratorReceiver == address(0)) {
            revert SM_InvalidAddress();
        }
        // Validate orchestrator fee
        if (_orchestratorFeeType == FeeType.PERCENTAGE) {
            if (_orchestratorFeeValue > MAX_FEE_PERCENTAGE) revert SM_FeeValueTooHigh();
        } else {
            if (_orchestratorFeeValue > MAX_FEE_FIXED) revert SM_FeeValueTooHigh();
        }
        // Validate solver fee
        if (_solverFeeType == FeeType.PERCENTAGE) {
            if (_solverFeeValue > MAX_FEE_PERCENTAGE) revert SM_FeeValueTooHigh();
        } else {
            if (_solverFeeValue > MAX_FEE_FIXED) revert SM_FeeValueTooHigh();
        }
        Solver storage solver = solvers[_executionAddress];
        if (solver.executionAddress != address(0)) revert SM_SolverAlreadyExists();
        solver.executionAddress = _executionAddress;
        solver.feeAddress = _feeAddress;
        solver.orchestratorReceiver = _orchestratorReceiver;
        solver.name = _name;
        solver.isActive = true;
        solver.pendingOffboard = false;
        solver.successfulSettlements = 0;
        solver.orchestratorFeeType = _orchestratorFeeType;
        solver.orchestratorFeeValue = _orchestratorFeeValue;
        solver.solverFeeType = _solverFeeType;
        solver.solverFeeValue = _solverFeeValue;
        emit SolverOnboarded(
            _executionAddress, _name, _orchestratorFeeType, _orchestratorFeeValue, _solverFeeType, _solverFeeValue
        );
    }

    // @inheritdoc ISolverManager
    function updateSolverFeeAddress(address _solver, address _feeAddress) external onlyRole(SOLVER_MANAGER_ROLE) {
        if (_feeAddress == address(0)) revert SM_InvalidAddress();
        Solver storage solver = solvers[_solver];
        if (solver.executionAddress == address(0)) revert SM_InvalidSolver();
        if (solver.pendingOffboard) revert SM_SolverPendingOffboard();
        if (!solver.isActive) revert SM_SolverInactive();
        address oldFeeAddress = solver.feeAddress;
        solver.feeAddress = _feeAddress;
        emit SolverFeeAddressUpdated(_solver, oldFeeAddress, _feeAddress);
    }

    // @inheritdoc ISolverManager
    function updateOrchestratorReceiver(address _solver, address _orchestratorReceiver)
        external
        onlyRole(SOLVER_MANAGER_ROLE)
    {
        if (_orchestratorReceiver == address(0)) revert SM_InvalidAddress();
        Solver storage solver = solvers[_solver];
        if (solver.executionAddress == address(0)) revert SM_InvalidSolver();
        if (solver.pendingOffboard) revert SM_SolverPendingOffboard();
        address oldOrchestratorReceiver = solver.orchestratorReceiver;
        solver.orchestratorReceiver = _orchestratorReceiver;
        emit OrchestratorReceiverUpdated(_solver, oldOrchestratorReceiver, _orchestratorReceiver);
    }

    // @inheritdoc ISolverManager
    function updateSolverFee(address _solver, FeeType _feeType, uint256 _feeValue)
        external
        onlyRole(FEE_MANAGER_ROLE)
    {
        Solver storage solver = solvers[_solver];
        if (solver.executionAddress == address(0)) revert SM_InvalidSolver();
        if (solver.pendingOffboard) revert SM_SolverPendingOffboard();
        // Validate fee amount
        if (_feeType == FeeType.PERCENTAGE) {
            if (_feeValue > MAX_FEE_PERCENTAGE) revert SM_FeeValueTooHigh();
        } else {
            if (_feeValue > MAX_FEE_FIXED) revert SM_FeeValueTooHigh();
        }
        uint256 oldFee = solver.solverFeeValue;
        solver.solverFeeType = _feeType;
        solver.solverFeeValue = _feeValue;
        emit SolverFeeUpdated(_solver, _feeType, oldFee, _feeValue);
    }

    // @inheritdoc ISolverManager
    function updateOrchestratorFee(address _solver, FeeType _feeType, uint256 _feeValue)
        external
        onlyRole(FEE_MANAGER_ROLE)
    {
        Solver storage solver = solvers[_solver];
        if (solver.executionAddress == address(0)) revert SM_InvalidSolver();
        if (solver.pendingOffboard) revert SM_SolverPendingOffboard();
        // Validate fee amount
        if (_feeType == FeeType.PERCENTAGE) {
            if (_feeValue > MAX_FEE_PERCENTAGE) revert SM_FeeValueTooHigh();
        } else {
            if (_feeValue > MAX_FEE_FIXED) revert SM_FeeValueTooHigh();
        }
        uint256 oldFee = solver.orchestratorFeeValue;
        solver.orchestratorFeeType = _feeType;
        solver.orchestratorFeeValue = _feeValue;
        emit OrchestratorFeeUpdated(_solver, solver.orchestratorReceiver, _feeType, oldFee, _feeValue);
    }

    // @inheritdoc ISolverManager
    function offboardSolver(address _solver) external onlyRole(SOLVER_MANAGER_ROLE) {
        if (solvers[_solver].executionAddress == address(0)) revert SM_InvalidSolver();
        uint256 pendingInvoices = solverInvoices[_solver].length();
        if (pendingInvoices > 0) {
            // Marked as pending offboard (can't accept new invoices)
            solvers[_solver].isActive = false;
            solvers[_solver].pendingOffboard = true;
            emit SolverMarkedForOffboarding(_solver, pendingInvoices);
        } else {
            delete solvers[_solver];
            emit SolverOffboarded(_solver);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            SOLVER VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc ISolverManager
    function getSolverData(address _solver) external view returns (Solver memory) {
        return solvers[_solver];
    }

    // @inheritdoc ISolverManager
    function getSolverInvoices(address _solver) external view returns (address[] memory) {
        return solverInvoices[_solver].values();
    }

    // @inheritdoc ISolverManager
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

    // @inheritdoc ISolverManager
    function grantSolverManagerRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(SOLVER_MANAGER_ROLE, _account);
    }

    // @inheritdoc ISolverManager
    function revokeSolverManagerRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(SOLVER_MANAGER_ROLE, _account);
    }

    // @inheritdoc ISolverManager
    function grantFeeManagerRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(FEE_MANAGER_ROLE, _account);
    }

    // @inheritdoc ISolverManager
    function revokeFeeManagerRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(FEE_MANAGER_ROLE, _account);
    }
}
