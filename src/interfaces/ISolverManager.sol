// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title ISolverManager
 * @notice Interface for solver management functionality
 * @author Etherspot
 */
interface ISolverManager {
    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/

    enum FeeType {
        FIXED,
        PERCENTAGE
    }

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Solver {
        // Addresses
        address executionAddress; // Where locked tokens go (repayments)
        address feeAddress; // Where Solver's fee goes (can be the same as executionAddress)
        address orchestratorReceiver; // PillarX or other Orchestrator
        // Solver Information
        string name;
        bool isActive;
        bool pendingOffboard;
        uint256 successfulSettlements;
        // Orchestrator Fee Configuration
        FeeType orchestratorFeeType; // FIXED or PERCENTAGE
        uint256 orchestratorFeeValue; // Cents or basis points
        // Solver Fee Configuration
        FeeType solverFeeType; // FIXED or PERCENTAGE
        uint256 solverFeeValue; // Cents or basis points
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SolverOnboarded(
        address indexed solver,
        string name,
        FeeType orchestratorFeeType,
        uint256 orchestratorFeeValue,
        FeeType solverFeeType,
        uint256 solverFeeValue
    );
    event SolverOffboarded(address indexed solver);
    event SolverFeeUpdated(address indexed solver, FeeType feeType, uint256 oldFee, uint256 newFee);
    event SolverStatusToggled(address indexed solver, bool isActive);
    event SolverMarkedForOffboarding(address indexed solver, uint256 pendingInvoices);
    event SolverFeeAddressUpdated(address indexed solver, address indexed oldFeeAddress, address indexed newFeeAddress);
    event OrchestratorReceiverUpdated(
        address indexed solver, address indexed oldOrchestratorReceiver, address indexed newOrchestratorReceiver
    );
    event OrchestratorFeeUpdated(
        address indexed solver, address indexed orchestrator, FeeType feeType, uint256 oldFee, uint256 newFee
    );

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a new solver with specified fee structure
     * @param _executionAddress Address where solver receives repayment
     * @param _feeAddress Address where solver receives their fee cut
     * @param _orchestratorReceiver Address where orchestrator fee is sent
     * @param _name Human-readable name for the solver
     * @param _orchestratorFeeType FIXED or PERCENTAGE
     * @param _orchestratorFeeValue Fee in cents (FIXED) or basis points (PERCENTAGE)
     * @param _solverFeeType FIXED or PERCENTAGE
     * @param _solverFeeValue Fee in cents (FIXED) or basis points (PERCENTAGE)
     */
    function onboardSolver(
        address _executionAddress,
        address _feeAddress,
        address _orchestratorReceiver,
        string calldata _name,
        FeeType _orchestratorFeeType,
        uint256 _orchestratorFeeValue,
        FeeType _solverFeeType,
        uint256 _solverFeeValue
    ) external;

    /**
     * @notice Updates the orchestrator fee structure for a solver
     * @param _solver Solver execution address
     * @param _feeType FIXED or PERCENTAGE
     * @param _feeValue Fee in cents (FIXED) or basis points (PERCENTAGE)
     */
    function updateOrchestratorFee(address _solver, FeeType _feeType, uint256 _feeValue) external;

    /**
     * @notice Updates the solver fee structure
     * @param _solver Solver execution address
     * @param _feeType FIXED or PERCENTAGE
     * @param _feeValue Fee in cents (FIXED) or basis points (PERCENTAGE)
     */
    function updateSolverFee(address _solver, FeeType _feeType, uint256 _feeValue) external;

    /**
     * @notice Removes a solver from the system and cleans up associated data
     * @param _solver Address of the solver to remove
     */
    function offboardSolver(address _solver) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves data for a solver
     * @param _solver Address of the solver to query
     * @return Solver struct containing all solver information
     */
    function getSolverData(address _solver) external view returns (Solver memory);

    /**
     * @notice Gets all active invoice session keys for a specific solver
     * @param _solver Address of the solver to query
     * @return Array of session key addresses for active invoices
     */
    function getSolverInvoices(address _solver) external view returns (address[] memory);

    /**
     * @notice Batch retrieval of multiple solver information
     * @param _solvers Array of solver addresses to retrieve
     * @return solvers_ Array of Solver structs
     */
    function getMultipleSolvers(address[] calldata _solvers) external view returns (Solver[] memory solvers_);

    /*//////////////////////////////////////////////////////////////
                            ROLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Grants SOLVER_MANAGER_ROLE to an address
     * @param _account Address to grant the role to
     */
    function grantSolverManagerRole(address _account) external;

    /**
     * @notice Revokes SOLVER_MANAGER_ROLE from an address
     * @param _account Address to revoke the role from
     */
    function revokeSolverManagerRole(address _account) external;

    /**
     * @notice Grants FEE_MANAGER_ROLE to an address
     * @param _account Address to grant the role to
     */
    function grantFeeManagerRole(address _account) external;

    /**
     * @notice Revokes FEE_MANAGER_ROLE from an address
     * @param _account Address to revoke the role from
     */
    function revokeFeeManagerRole(address _account) external;
}
