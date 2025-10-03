// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {TokenData} from "../common/Structs.sol";

/**
 * @title IInvoiceManager
 * @notice Interface for core InvoiceManager functionality
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

    struct InvoiceTokenData {
        address token;
        uint256 amount;
        uint256 creditedAmount;
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
    event FeeReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);
    event TokensCreditedToInvoice(address indexed sessionKey, address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            CORE INVOICE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new invoice for payment processing with specified tokens and amounts
     * @param _invoiceData Bytes data containing invoice metadata (smart wallet, session key, solver, bid hash, etc.)
     */
    function createInvoice(bytes memory _invoiceData) external;

    /**
     * @notice Settles an invoice by transferring tokens to solver and fees to fee receiver
     * @param _sessionKey Session key of the invoice to settle
     */
    function settleInvoice(address _sessionKey) external;

    /**
     * @notice Credits tokens to a specific invoice, recording receipt for settlement
     * @dev This function is called to record that tokens have been received for an invoice,
     *      typically by the CredibleAccountModule during token claiming. Part of the two-phase
     *      settlement process where tokens must be credited before settlement can occur.
     * @param _sessionKey The session key identifying the invoice to credit
     * @param _token The address of the token being credited
     * @param _amount The amount of tokens being credited to the invoice
     */
    function creditTokensToInvoice(address _sessionKey, address _token, uint256 _amount) external;

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
     * @return tokenData Array of InvoiceTokenData structs with token addresses and amounts
     */
    function getInvoice(address _sessionKey) external view returns (Invoice memory, InvoiceTokenData[] memory);

    /**
     * @notice Finds the session key associated with a specific bid hash
     * @param _bidHash The bid hash to look up
     * @return sessionKey Session key associated with the bid hash
     */
    function getInvoiceByBidHash(bytes32 _bidHash) external view returns (address sessionKey);

    function getInvoicePaymentStatus(address _sessionKey)
        external
        view
        returns (
            address[] memory tokens,
            uint256[] memory expectedAmounts,
            uint256[] memory creditedAmounts,
            bool isFullyPaid
        );

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
     * @notice Batch retrieval of multiple invoices with their token data
     * @param _sessionKeys Array of session keys to retrieve
     * @return invoices_ Array of Invoice structs (empty struct if invoice doesn't exist)
     * @return tokenData_ Array of InvoiceTokenData arrays corresponding to each invoice
     */
    function getMultipleInvoices(address[] calldata _sessionKeys)
        external
        view
        returns (Invoice[] memory invoices_, InvoiceTokenData[][] memory tokenData_);

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

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the fee receiver address
     * @return address The address that receives collected fees
     */
    function feeReceiver() external view returns (address);
}
