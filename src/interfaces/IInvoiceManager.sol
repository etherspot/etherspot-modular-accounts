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

    struct FeeStructure {
        uint256 protocolFee; // Calculated amount in token decimals
        address protocolFeeReceiver;
        uint256 orchestratorFee; // Calculated amount in token decimals
        address orchestratorFeeReceiver;
        uint256 solverFee; // Calculated amount in token decimals
        address solverFeeReceiver;
        address solverExecutionAddress;
    }

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
        FeeStructure fees;
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
        uint256 totalFees
    );
    event TokenPaid(
        address indexed sessionKey,
        address indexed solver,
        address indexed token,
        uint256 totalAmount,
        uint256 pulseFee,
        uint256 solverAmount
    );
    event InvoiceSettled(
        address indexed sessionKey,
        bytes32 indexed bidHash,
        address indexed solver,
        uint256 solverRepayment,
        uint256 totalFees
    );
    event InvoiceCancelled(address indexed sessionKey, string reason);
    event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
    event ProtocolFeeReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);
    event TokensCreditedToInvoice(
        address indexed sessionKey, address indexed token, uint256 expected, uint256 received, uint256 totalCredited
    );
    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed receiver);

    /*//////////////////////////////////////////////////////////////
                            CORE INVOICE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new invoice for payment processing from encoded CredibleAccountModule data
     * @param _invoiceData Encoded bytes containing all invoice and token data from CredibleAccountModule
     * @dev Only callable by addresses with CREDIBLE_ACCOUNT_ROLE (CredibleAccountModule)
     * @dev Unpacks: (smartWallet, sessionKey, solver, bidHash, chainId, TokenData[])
     * @dev All tokens must be whitelisted and solver must be active
     * @dev Snapshots the solver's fee at creation time to prevent fee manipulation
     */
    function createInvoice(bytes memory _invoiceData) external;

    /**
     * @notice Settles an invoice by transferring tokens to solver and fees to fee receiver
     * @param _sessionKey Session key of the invoice to settle
     * @dev Only callable by addresses with SETTLER_ROLE or the linked smart wallet
     * @dev Uses reentrancy protection to prevent attacks during token transfers
     * @dev Calculates fees based on snapshotted fee amount from invoice creation
     * @dev Deletes all invoice data after successful settlement
     */
    function settleInvoice(address _sessionKey) external returns (bool);

    /**
     * @notice Credits tokens to a specific invoice, recording that tokens have been received
     * @dev Only accounts with CREDIBLE_ACCOUNT_ROLE can credit tokens. This function is part
     *      of the two-phase settlement process where tokens must be credited before settlement.
     * @param _sessionKey The session key identifying the invoice
     * @param _token The address of the token being credited
     * @param _amount The amount of tokens being credited
     */
    function creditTokensToInvoice(address _sessionKey, address _token, uint256 _amount) external;

    /**
     * @notice Cancels an invoice and removes all associated data
     * @param _sessionKey Session key of the invoice to cancel
     * @param _reason Human-readable reason for cancellation
     * @dev Only callable by addresses with SETTLER_ROLE
     * @dev Cleans up all mappings and allows bid hash to be reused
     * @dev If cancelling an Invoice with credited tokens, we can emergencyWithdraw to the
     *      DEFAULT_ADMIN_ROLE and distribute funds accordingly
     */
    function cancelInvoice(address _sessionKey, string calldata _reason) external;

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the protocol fee amount
     * @param _newProtocolFee New protocol fee in cents
     * @dev Only callable by addresses with FEE_MANAGER_ROLE
     */
    function setProtocolFee(uint256 _newProtocolFee) external;

    /**
     * @notice Updates the protocol fee receiver address
     * @param _protocolFeeReceiver New protocol fee receiver address
     * @dev Only callable by addresses with FEE_MANAGER_ROLE
     */
    function setProtocolFeeReceiver(address _protocolFeeReceiver) external;

    /**
     * @notice Returns the protocol fee receiver address
     * @return address The address that receives protocol fees
     */
    function protocolFeeReceiver() external view returns (address);

    /**
     * @notice Returns the protocol fee amount in cents
     * @return uint256 The protocol fee
     */
    function protocolFeeFixed() external view returns (uint256);

    /**
     * @notice Emergency function to withdraw tokens from the contract
     * @param _token Address of the token to withdraw
     * @param _amount Amount of tokens to withdraw
     * @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
     * @dev Transfers tokens to the caller (admin)
     * @dev Should be used for tokens that are not preallocated to an invoice
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
     * @dev Reverts if invoice does not exist
     */
    function getInvoice(address _sessionKey) external view returns (Invoice memory, InvoiceTokenData[] memory);

    /**
     * @notice Finds the session key associated with a specific bid hash
     * @param _bidHash The bid hash to look up
     * @return sessionKey Session key associated with the bid hash
     * @dev Reverts if bid hash is not found
     */
    function getInvoiceByBidHash(bytes32 _bidHash) external view returns (address sessionKey);

    /**
     * @notice Retrieves all tokens, expected and credited amounts for an invoice
     * @param _sessionKey Session key associated with the invoice
     * @return tokens Array of tokens
     * @return expectedAmounts Array of expected amounts to receive for that invoice token
     * @return creditedAmounts Array of received amounts credited for that invoice token
     * @dev Reverts if bid hash is not found
     */
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
     * @notice Calculates fee breakdown for an invoice
     * @param _sessionKey Session key of the invoice to analyze
     * @return protocolFee Protocol fee amount
     * @return orchestratorFee Orchestrator fee amount
     * @return solverFee Solver fee amount
     * @return totalFees Total of all fees
     * @dev Uses snapshotted fees from invoice creation
     */
    function calculateInvoiceFees(address _sessionKey)
        external
        view
        returns (uint256 protocolFee, uint256 orchestratorFee, uint256 solverFee, uint256 totalFees);

    /**
     * @notice Checks if an invoice can be successfully settled
     * @param _sessionKey Session key of the invoice to check
     * @return True if invoice exists, solver is active, all tokens are fully credited, and contract has sufficient token balances
     * @dev Performs balance checks and credit verification for all tokens in the invoice
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
     * @return tokenData_ Array of TokenData arrays corresponding to each invoice
     * @dev Returns empty structs for non-existent invoices instead of reverting
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
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function grantCredibleAccountRole(address _account) external;

    /**
     * @notice Revokes CREDIBLE_ACCOUNT_ROLE from an address
     * @param _account Address to revoke the role from
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function revokeCredibleAccountRole(address _account) external;

    /**
     * @notice Grants SETTLER_ROLE to an address
     * @param _account Address to grant the role to
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function grantSettlerRole(address _account) external;

    /**
     * @notice Revokes SETTLER_ROLE from an address
     * @param _account Address to revoke the role from
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function revokeSettlerRole(address _account) external;
}
