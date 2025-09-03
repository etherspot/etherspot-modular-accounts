// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title ISolverManager
 * @notice Interface for solver management functionality
 * @author Etherspot
 */
interface ISolverManager {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Solver {
        address solverAddress;
        uint256 successfulSettlements;
        bool isActive;
        string name;
        uint256 pulseFee;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SolverOnboarded(address indexed solver, string name, uint256 pulseFee);
    event SolverOffboarded(address indexed solver);
    event SolverFeeUpdated(address indexed solver, uint256 oldFee, uint256 newFee);
    event SolverStatusToggled(address indexed solver, bool isActive);

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a new solver with specified name and fee structure
     * @param _solver Address of the solver to onboard
     * @param _name Human-readable name for the solver
     * @param _pulseFee Fee in cents (0 = use default 5 cents, >0 = custom fee amount)
     */
    function onboardSolver(address _solver, string calldata _name, uint256 _pulseFee) external;

    /**
     * @notice Updates the fee structure for an existing solver
     * @param _solver Address of the solver to update
     * @param _newFee New fee amount in cents (0 = use default, >0 = custom)
     */
    function updateSolverFee(address _solver, uint256 _newFee) external;

    /**
     * @notice Removes a solver from the system and cleans up associated data
     * @param _solver Address of the solver to remove
     */
    function offboardSolver(address _solver) external;

    /**
     * @notice Toggles the active status of a solver between active and inactive
     * @param _solver Address of the solver to toggle
     */
    function toggleSolverStatus(address _solver) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves data for a solver
     * @param _solver Address of the solver to query
     * @return name Human-readable name of the solver
     * @return isActive Whether the solver is currently active
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
            uint256 successfulSettlements,
            uint256 activeInvoices,
            uint256 pulseFee
        );

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

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the default pulse base fee in cents
     * @return uint256 The pulse base fee (5 cents)
     */
    function PULSE_BASE_FEE() external view returns (uint256);
}