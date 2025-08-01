// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {TokenData} from "../common/Structs.sol";

/**
 * @title IInvoiceManager
 * @notice Interface for InvoiceManager contract that manages invoices for cross-chain payment processing
 * @author Etherspot
 */
interface IInvoiceManager {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct InvoiceData {
        address smartWallet;
        address sessionKey;
        address solver;
        bytes32 bidHash;
        uint256 chainId;
    }

    struct Invoice {
        InvoiceData data;
        uint256 createdAt;
        uint256 pulseFee;
    }

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

    event InvoiceCreated(
        address indexed sessionKey,
        bytes32 indexed bidHash,
        address indexed solver,
        uint256 totalTokens,
        uint256 pulseFee
    );
    event TokenPaid(
        address indexed sessionKey,
        address indexed solver,
        address indexed token,
        uint256 totalAmount,
        uint256 pulseFee,
        uint256 solverAmount
    );
    event InvoiceSettled(address indexed sessionKey, bytes32 indexed bidHash, address indexed solver);
    event InvoiceCancelled(address indexed sessionKey, string reason);
    event SolverOnboarded(address indexed solver, string name, uint256 pulseFee);
    event SolverOffboarded(address indexed solver);
    event SolverFeeUpdated(address indexed solver, uint256 oldFee, uint256 newFee);
    event FeeReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);
    event TokenWhitelisted(address indexed token, address indexed addedBy);
    event TokenRemovedFromWhitelist(address indexed token, address indexed removedBy);

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new invoice for payment processing with specified tokens and amounts
     * @param _invoiceData Bytes data containing invoice metadata (smart wallet, session key, solver, bid hash, etc.)
     * @return sessionKey The session key address of the created invoice
     */
    function createInvoice(bytes memory _invoiceData) external returns (address sessionKey);

    /**
     * @notice Settles an invoice by transferring tokens to solver and fees to fee receiver
     * @param _sessionKey Session key of the invoice to settle
     */
    function settleInvoice(address _sessionKey) external;

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

    /**
     * @notice Cancels an invoice and removes all associated data
     * @param _sessionKey Session key of the invoice to cancel
     * @param _reason Human-readable reason for cancellation
     */
    function cancelInvoice(address _sessionKey, string calldata _reason) external;

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the address that receives collected fees
     * @param _feeReceiver New fee receiver address
     */
    function setFeeReceiver(address _feeReceiver) external;

    /**
     * @notice Emergency function to withdraw tokens from the contract
     * @param _token Address of the token to withdraw
     * @param _amount Amount of tokens to withdraw
     */
    function emergencyWithdraw(address _token, uint256 _amount) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves complete invoice data including token information
     * @param _sessionKey Session key of the invoice to retrieve
     * @return invoice Complete Invoice struct with metadata and creation time
     * @return tokenData Array of TokenData structs with token addresses and amounts
     */
    function getInvoice(address _sessionKey) external view returns (Invoice memory, TokenData[] memory);

    /**
     * @notice Finds the session key associated with a specific bid hash
     * @param _bidHash The bid hash to look up
     * @return sessionKey Session key associated with the bid hash
     */
    function getInvoiceByBidHash(bytes32 _bidHash) external view returns (address sessionKey);

    /**
     * @notice Gets all active invoice session keys for a specific solver
     * @param _solver Address of the solver to query
     * @return Array of session key addresses for active invoices
     */
    function getSolverInvoices(address _solver) external view returns (address[] memory);

    /**
     * @notice Calculates fees for each token in an invoice
     * @param _sessionKey Session key of the invoice to analyze
     * @return tokenFees Array of TokenData with token addresses and their corresponding fees
     */
    function calculateInvoiceFees(address _sessionKey) external view returns (TokenData[] memory tokenFees);

    /**
     * @notice Checks if an invoice can be successfully settled
     * @param _sessionKey Session key of the invoice to check
     * @return True if invoice exists, solver is active, and contract has sufficient token balances
     */
    function isInvoiceSettleable(address _sessionKey) external view returns (bool);

    /**
     * @notice Checks if an invoice exists for a given session key
     * @param _sessionKey Session key to check
     * @return True if invoice exists (has non-zero creation timestamp)
     */
    function invoiceExists(address _sessionKey) external view returns (bool);

    /**
     * @notice Checks if a bid hash is already in use
     * @param _bidHash Bid hash to check
     * @return True if bid hash is associated with an existing invoice
     */
    function bidHashExists(bytes32 _bidHash) external view returns (bool);

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
     * @notice Batch retrieval of multiple invoices with their token data
     * @param _sessionKeys Array of session keys to retrieve
     * @return invoices_ Array of Invoice structs (empty struct if invoice doesn't exist)
     * @return tokenData_ Array of TokenData arrays corresponding to each invoice
     */
    function getMultipleInvoices(address[] calldata _sessionKeys)
        external
        view
        returns (Invoice[] memory invoices_, TokenData[][] memory tokenData_);

    /**
     * @notice Batch retrieval of multiple solver information
     * @param _solvers Array of solver addresses to retrieve
     * @return solvers_ Array of Solver structs
     */
    function getMultipleSolvers(address[] calldata _solvers) external view returns (Solver[] memory solvers_);

    /*//////////////////////////////////////////////////////////////
                    TOKEN WHITELIST MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a token to the whitelist
     * @param _token The token address to whitelist
     */
    function addTokenToWhitelist(address _token) external;

    /**
     * @notice Add multiple tokens to the whitelist
     * @param _tokens Array of token addresses to whitelist
     */
    function addTokensToWhitelist(address[] calldata _tokens) external;

    /**
     * @notice Remove a token from the whitelist
     * @param _token The token address to remove from whitelist
     */
    function removeTokenFromWhitelist(address _token) external;

    /**
     * @notice Remove multiple tokens from the whitelist
     * @param _tokens Array of token addresses to remove from whitelist
     */
    function removeTokensFromWhitelist(address[] calldata _tokens) external;

    /**
     * @notice Check if a token is whitelisted
     * @param _token The token address to check
     * @return bool True if token is whitelisted
     */
    function isTokenWhitelisted(address _token) external view returns (bool);

    /**
     * @notice Get all whitelisted tokens
     * @return address[] Array of whitelisted token addresses
     */
    function getWhitelistedTokens() external view returns (address[] memory);

    /**
     * @notice Get the number of whitelisted tokens
     * @return uint256 Number of whitelisted tokens
     */
    function getWhitelistedTokensCount() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        ROLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Grants CREDIBLE_ACCOUNT_ROLE to an address
     * @param _account Address to grant the role to
     */
    function grantCredibleAccountRole(address _account) external;

    /**
     * @notice Revokes CREDIBLE_ACCOUNT_ROLE from an address
     * @param _account Address to revoke the role from
     */
    function revokeCredibleAccountRole(address _account) external;

    /**
     * @notice Grants SETTLER_ROLE to an address
     * @param _account Address to grant the role to
     */
    function grantSettlerRole(address _account) external;

    /**
     * @notice Revokes SETTLER_ROLE from an address
     * @param _account Address to revoke the role from
     */
    function revokeSettlerRole(address _account) external;

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

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the default pulse base fee in cents
     * @return uint256 The pulse base fee (5 cents)
     */
    function PULSE_BASE_FEE() external view returns (uint256);

    /**
     * @notice Returns the fee receiver address
     * @return address The address that receives collected fees
     */
    function feeReceiver() external view returns (address);
}
