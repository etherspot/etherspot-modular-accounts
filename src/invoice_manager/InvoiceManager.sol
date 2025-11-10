// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IInvoiceManager} from "../interfaces/IInvoiceManager.sol";
import {TokenData} from "../common/Structs.sol";
import {SolverManager} from "./SolverManager.sol";
import {TokenManager} from "./TokenManager.sol";

/**
 * @title InvoiceManager
 * @notice Manages invoices for cross-chain payment processing with configurable solver fees
 * @author Etherspot
 */
contract InvoiceManager is IInvoiceManager, SolverManager, TokenManager, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant CREDIBLE_ACCOUNT_ROLE = keccak256("CREDIBLE_ACCOUNT_ROLE");
    bytes32 public constant SETTLER_ROLE = keccak256("SETTLER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public protocolFeeReceiver;
    uint256 public protocolFeeFixed = 5; // 5 cents

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(address => Invoice) public invoices;
    mapping(bytes32 => address) public bidHashToSessionKey;
    mapping(address => InvoiceTokenData[]) public invoiceTokenData;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    // Core invoice-specific errors
    error IM_InvalidAddress();
    error IM_InvoiceNotFound();
    error IM_InvoiceAlreadyExists();
    error IM_BidHashAlreadyExists();
    error IM_InvalidTokenAmount();
    error IM_UnauthorizedSettler(address caller, address sessionKey);
    error IM_InsufficientContractBalance(address token, uint256 requiredAmount, uint256 availableBalance);
    error IM_InvalidChainId(uint256 chainId);
    error IM_TokenNotFoundInInvoice(address sessionKey, address token);
    error IM_TokenAmountMismatch(address sessionKey, address token, uint256 expected, uint256 actual);
    error IM_TokenOverCredited(address sessionKey, address token, uint256 expected, uint256 attempted);
    error IM_InvoiceNotFullyCredited(address sessionKey, address token, uint256 expected, uint256 credited);
    error IM_UnauthorizedSolver();
    error IM_InsufficientCredits();
    error IM_InsufficientAmountForFees(uint256 amount, uint256 totalFees);
    error IM_FeeValueTooHigh();
    error IM_CannotCancelCreditedInvoice();
    error IM_InsufficientCreditsToUncredit(address sessionKey, address token, uint256 requested, uint256 available);
    error IM_EmptyReasonNotAllowed();

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlySettlerOrLinkedWallet(address _sessionKey) {
        // Check if caller has SETTLER_ROLE
        bool hasSettlerRole = hasRole(SETTLER_ROLE, msg.sender);
        // Check if caller is the smart wallet linked to the session key
        bool isLinkedWallet = false;
        if (_sessionKey != address(0)) {
            // Get the invoice data for this session key
            InvoiceData memory invoiceData = invoices[_sessionKey].data;
            isLinkedWallet = (msg.sender == invoiceData.smartWallet);
        }
        if (!hasSettlerRole && !isLinkedWallet) {
            revert IM_UnauthorizedSettler(msg.sender, _sessionKey);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the InvoiceManager contract with required roles and whitelisted tokens
     * @param _owner Address that will receive DEFAULT_ADMIN_ROLE and SETTLER_ROLE
     * @param _credibleAccountModule Address that will receive CREDIBLE_ACCOUNT_ROLE
     * @param _feeReceiver Address that will receive collected fees
     * @param _feeManager Address that will receive FEE_MANAGER_ROLE
     * @dev Reverts if any address is zero
     */
    constructor(address _owner, address _credibleAccountModule, address _feeReceiver, address _feeManager) {
        if (
            _owner == address(0) || _credibleAccountModule == address(0) || _feeReceiver == address(0)
                || _feeManager == address(0)
        ) {
            revert IM_InvalidAddress();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(CREDIBLE_ACCOUNT_ROLE, _credibleAccountModule);
        _grantRole(SETTLER_ROLE, _owner);
        _grantRole(FEE_MANAGER_ROLE, _feeManager);
        _grantRole(SOLVER_MANAGER_ROLE, _owner);
        protocolFeeReceiver = _feeReceiver;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc IInvoiceManager
    function createInvoice(bytes memory _invoiceData) external onlyRole(CREDIBLE_ACCOUNT_ROLE) {
        // Unpack the encoded data from CredibleAccountModule
        (
            address smartWallet,
            address sessionKey,
            address solver,
            bytes32 bidHash,
            uint256 chainId,
            TokenData[] memory tokenData
        ) = abi.decode(_invoiceData, (address, address, address, bytes32, uint256, TokenData[]));
        // Validate all parameters
        _validateInvoiceParameters(smartWallet, sessionKey, solver, chainId, bidHash, tokenData);
        // Create and store invoice
        _createAndStoreInvoice(sessionKey, smartWallet, solver, bidHash, chainId, tokenData);
    }

    // @inheritdoc IInvoiceManager
    function settleInvoice(address _sessionKey)
        external
        nonReentrant
        onlySettlerOrLinkedWallet(_sessionKey)
        returns (bool)
    {
        Invoice storage invoice = invoices[_sessionKey];
        InvoiceTokenData[] storage tokens = invoiceTokenData[_sessionKey];
        if (tokens.length == 0) revert IM_InvoiceNotFound();
        // Ensure all tokens have been fully credited before settlement
        uint256 tokenCount = tokens.length;
        for (uint256 i; i < tokenCount; ++i) {
            if (tokens[i].creditedAmount < tokens[i].amount) {
                revert IM_InvoiceNotFullyCredited(
                    _sessionKey, tokens[i].token, tokens[i].amount, tokens[i].creditedAmount
                );
            }
        }
        // Distribute fees and repayment using all token data (fees from first token only)
        (uint256 solverRepayment, uint256 totalFees) = _distributeFees(invoice, tokens);
        // Clean up invoice data and update solver stats
        address solver = invoice.data.solver;
        bytes32 bidHash = invoice.data.bidHash;
        _cleanupInvoice(solver, _sessionKey, bidHash);
        _incrementSolverSettlements(solver);
        emit InvoiceSettled(_sessionKey, bidHash, solver, solverRepayment, totalFees);
        return true;
    }

    // @inheritdoc IInvoiceManager
    function creditTokensToInvoice(address _sessionKey, address _token, uint256 _amount)
        external
        onlyRole(CREDIBLE_ACCOUNT_ROLE)
    {
        Invoice storage invoice = invoices[_sessionKey];
        if (invoice.createdAt == 0) revert IM_InvoiceNotFound();
        InvoiceTokenData[] storage tokenData = invoiceTokenData[_sessionKey];
        bool tokenFound = false;
        uint256 tokenIndex;
        for (uint256 i; i < tokenData.length; ++i) {
            if (tokenData[i].token == _token) {
                tokenFound = true;
                tokenIndex = i;
                break;
            }
        }
        if (!tokenFound) revert IM_TokenNotFoundInInvoice(_sessionKey, _token);
        // Check if adding this amount would exceed expected
        InvoiceTokenData storage t = tokenData[tokenIndex];
        uint256 expectedAmount = t.amount;
        uint256 newCreditedAmount = t.creditedAmount + _amount;
        if (newCreditedAmount > expectedAmount) {
            revert IM_TokenOverCredited(_sessionKey, _token, expectedAmount, newCreditedAmount);
        }
        // Attribute received tokens to invoice
        t.creditedAmount = newCreditedAmount;
        emit TokensCreditedToInvoice(_sessionKey, _token, expectedAmount, _amount, newCreditedAmount);
    }

    // @inheritdoc IInvoiceManager
    function cancelInvoice(address _sessionKey, string calldata _reason) external onlyRole(SETTLER_ROLE) {
        if (bytes(_reason).length == 0) revert IM_EmptyReasonNotAllowed();
        Invoice storage invoice = invoices[_sessionKey];
        if (invoice.createdAt == 0) revert IM_InvoiceNotFound();
        bytes32 bidHash = invoice.data.bidHash;
        address solver = invoice.data.solver;
        _cleanupInvoice(solver, _sessionKey, bidHash);
        emit InvoiceCancelled(_sessionKey, _reason);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc IInvoiceManager
    function setProtocolFee(uint256 _newProtocolFee) external onlyRole(FEE_MANAGER_ROLE) {
        if (_newProtocolFee > MAX_FEE_FIXED) revert IM_FeeValueTooHigh();
        uint256 oldFee = protocolFeeFixed;
        protocolFeeFixed = _newProtocolFee;
        emit ProtocolFeeUpdated(oldFee, _newProtocolFee);
    }

    // @inheritdoc IInvoiceManager
    function setProtocolFeeReceiver(address _protocolFeeReceiver) external onlyRole(FEE_MANAGER_ROLE) {
        if (_protocolFeeReceiver == address(0)) revert IM_InvalidAddress();
        address oldReceiver = protocolFeeReceiver;
        protocolFeeReceiver = _protocolFeeReceiver;
        emit ProtocolFeeReceiverUpdated(oldReceiver, _protocolFeeReceiver);
    }

    // @inheritdoc IInvoiceManager
    function emergencyWithdraw(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_amount == 0) revert IM_InvalidTokenAmount();
        uint256 contractBalance = IERC20(_token).balanceOf(address(this));
        if (contractBalance < _amount) revert IM_InsufficientContractBalance(_token, _amount, contractBalance);
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(_token, _amount, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc IInvoiceManager
    function getInvoice(address _sessionKey) external view returns (Invoice memory, InvoiceTokenData[] memory) {
        Invoice storage invoice = invoices[_sessionKey];
        if (invoice.createdAt == 0) revert IM_InvoiceNotFound();
        return (invoice, invoiceTokenData[_sessionKey]);
    }

    // @inheritdoc IInvoiceManager
    function getInvoiceByBidHash(bytes32 _bidHash) external view returns (address sessionKey) {
        sessionKey = bidHashToSessionKey[_bidHash];
        if (sessionKey == address(0)) revert IM_InvoiceNotFound();
    }

    // @inheritdoc IInvoiceManager
    function getInvoicePaymentStatus(address _sessionKey)
        external
        view
        returns (
            address[] memory tokens,
            uint256[] memory expectedAmounts,
            uint256[] memory creditedAmounts,
            bool isFullyPaid
        )
    {
        InvoiceTokenData[] storage tokenData = invoiceTokenData[_sessionKey];
        uint256 length = tokenData.length;
        tokens = new address[](length);
        expectedAmounts = new uint256[](length);
        creditedAmounts = new uint256[](length);
        isFullyPaid = true;
        for (uint256 i; i < length; ++i) {
            tokens[i] = tokenData[i].token;
            expectedAmounts[i] = tokenData[i].amount;
            creditedAmounts[i] = tokenData[i].creditedAmount;
            if (tokenData[i].creditedAmount != tokenData[i].amount) {
                isFullyPaid = false;
            }
        }
    }

    // @inheritdoc IInvoiceManager
    function calculateInvoiceFees(address _sessionKey)
        external
        view
        returns (uint256 protocolFee, uint256 orchestratorFee, uint256 solverFee, uint256 totalFees)
    {
        Invoice storage invoice = invoices[_sessionKey];
        if (invoice.createdAt == 0) revert IM_InvoiceNotFound();
        FeeStructure memory fees = invoice.fees;
        protocolFee = fees.protocolFee;
        orchestratorFee = fees.orchestratorFee;
        solverFee = fees.solverFee;
        totalFees = protocolFee + orchestratorFee + solverFee;
    }

    // @inheritdoc IInvoiceManager
    function isInvoiceSettleable(address _sessionKey) external view returns (bool) {
        Invoice storage invoice = invoices[_sessionKey];
        if (invoice.createdAt == 0) return false;
        if (!_canSolverSettle(invoice.data.solver)) return false;
        InvoiceTokenData[] storage tokenData = invoiceTokenData[_sessionKey];
        uint256 tokenDataLength = tokenData.length;
        for (uint256 i; i < tokenDataLength; ++i) {
            // Check if all tokens have been fully credited
            if (tokenData[i].creditedAmount != tokenData[i].amount) return false;
            // Check if contract has sufficient balance
            if (IERC20(tokenData[i].token).balanceOf(address(this)) < tokenData[i].amount) return false;
        }
        return true;
    }

    // @inheritdoc IInvoiceManager
    function invoiceExists(address _sessionKey) external view returns (bool) {
        return invoices[_sessionKey].createdAt != 0;
    }

    // @inheritdoc IInvoiceManager
    function bidHashExists(bytes32 _bidHash) external view returns (bool) {
        return bidHashToSessionKey[_bidHash] != address(0);
    }

    // @inheritdoc IInvoiceManager
    function getMultipleInvoices(address[] calldata _sessionKeys)
        external
        view
        returns (Invoice[] memory invoices_, InvoiceTokenData[][] memory tokenData_)
    {
        uint256 sessionKeysLength = _sessionKeys.length;
        invoices_ = new Invoice[](sessionKeysLength);
        tokenData_ = new InvoiceTokenData[][](sessionKeysLength);
        for (uint256 i; i < sessionKeysLength; ++i) {
            address sessionKey = _sessionKeys[i];
            if (invoices[sessionKey].createdAt != 0) {
                invoices_[i] = invoices[sessionKey];
                tokenData_[i] = invoiceTokenData[sessionKey];
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ROLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc IInvoiceManager
    function grantCredibleAccountRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(CREDIBLE_ACCOUNT_ROLE, _account);
    }

    // @inheritdoc IInvoiceManager
    function revokeCredibleAccountRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(CREDIBLE_ACCOUNT_ROLE, _account);
    }

    // @inheritdoc IInvoiceManager
    function grantSettlerRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(SETTLER_ROLE, _account);
    }

    // @inheritdoc IInvoiceManager
    function revokeSettlerRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(SETTLER_ROLE, _account);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates all parameters for invoice creation
     * @dev Internal validation function that checks addresses, chain ID, solver status,
     *      token whitelist, amounts, and prevents duplicate invoices
     * @param smartWallet The smart wallet address for the invoice
     * @param sessionKey The unique session key for the invoice
     * @param solver The solver address handling the invoice
     * @param chainId The chain ID (0 for any chain, or must match current)
     * @param bidHash The unique bid hash for the invoice
     * @param tokenData Array of token data containing addresses and amounts
     */
    function _validateInvoiceParameters(
        address smartWallet,
        address sessionKey,
        address solver,
        uint256 chainId,
        bytes32 bidHash,
        TokenData[] memory tokenData
    ) internal view {
        // Validate basic parameters
        if (smartWallet == address(0) || sessionKey == address(0) || solver == address(0)) revert IM_InvalidAddress();
        // Validate chain ID if specified
        if (chainId != 0 && chainId != block.chainid) revert IM_InvalidChainId(chainId);
        // Check solver is active
        if (!_isSolverActive(solver)) revert SM_SolverInactive();
        // Validate token data
        uint256 tokenDataLength = tokenData.length;
        if (tokenDataLength == 0) revert TM_EmptyTokenData();
        // Check all tokens are whitelisted and amounts are valid
        for (uint256 i; i < tokenDataLength; ++i) {
            if (!_isTokenWhitelisted(tokenData[i].token)) revert TM_TokenNotWhitelisted(tokenData[i].token);
            if (tokenData[i].amount == 0) revert IM_InvalidTokenAmount();
            // Calculate total fees to ensure amount is sufficient
            (uint256 protocolFee, uint256 orchestratorFee, uint256 solverFee) =
                _calculateBaseTokenFees(solver, tokenData[i].token, tokenData[i].amount);
            uint256 totalFees = protocolFee + orchestratorFee + solverFee;
            if (tokenData[i].amount <= totalFees) revert IM_InsufficientAmountForFees(tokenData[i].amount, totalFees);
        }
        // Check for existing invoice
        if (invoices[sessionKey].createdAt != 0) revert IM_InvoiceAlreadyExists();
        if (bidHashToSessionKey[bidHash] != address(0)) revert IM_BidHashAlreadyExists();
    }

    /**
     * @notice Creates and stores a new invoice with all associated data
     * @dev Internal function that creates the invoice struct, stores token data,
     *      updates mappings, and emits the creation event
     * @param sessionKey The unique session key for the invoice
     * @param smartWallet The smart wallet address for the invoice
     * @param solver The solver address handling the invoice
     * @param bidHash The unique bid hash for the invoice
     * @param chainId The chain ID for the invoice
     * @param tokenData Array of token data containing addresses and amounts
     */
    function _createAndStoreInvoice(
        address sessionKey,
        address smartWallet,
        address solver,
        bytes32 bidHash,
        uint256 chainId,
        TokenData[] memory tokenData
    ) internal {
        // Multi-token support (fees always based on first token)
        if (tokenData.length == 0) revert TM_EmptyTokenData();
        // Store invoice data
        Invoice storage invoice = invoices[sessionKey];
        invoice.data = InvoiceData({
            smartWallet: smartWallet,
            sessionKey: sessionKey,
            solver: solver,
            bidHash: bidHash,
            chainId: chainId
        });
        invoice.createdAt = block.timestamp;
        // Calculate and store fees using the first token only
        (uint256 protocolFee, uint256 orchestratorFee, uint256 solverFee) =
            _calculateBaseTokenFees(solver, tokenData[0].token, tokenData[0].amount);
        uint256 totalFees = protocolFee + orchestratorFee + solverFee;
        if (tokenData[0].amount <= totalFees) revert IM_InsufficientAmountForFees(tokenData[0].amount, totalFees);
        if (protocolFeeReceiver == address(0)) revert IM_InvalidAddress();
        if (solvers[solver].orchestratorReceiver == address(0)) revert IM_InvalidAddress();
        if (solvers[solver].feeAddress == address(0)) revert IM_InvalidAddress();
        invoice.fees = FeeStructure({
            protocolFee: protocolFee,
            orchestratorFee: orchestratorFee,
            solverFee: solverFee,
            protocolFeeReceiver: protocolFeeReceiver,
            orchestratorFeeReceiver: solvers[solver].orchestratorReceiver,
            solverFeeReceiver: solvers[solver].feeAddress,
            solverExecutionAddress: solvers[solver].executionAddress
        });
        // Store token data
        for (uint256 i; i < tokenData.length; ++i) {
            invoiceTokenData[sessionKey].push(
                InvoiceTokenData({token: tokenData[i].token, amount: tokenData[i].amount, creditedAmount: 0})
            );
        }
        bidHashToSessionKey[bidHash] = sessionKey;
        _addSolverInvoice(solver, sessionKey);
        emit InvoiceCreated(sessionKey, bidHash, solver, tokenData.length, totalFees);
    }

    /**
     * @notice Calculate all fees sequentially
     * @param _solver Solver address
     * @param _token Token address
     * @param _amount Initial locked amount
     * @return protocolFee Calculated protocol fee
     * @return orchestratorFee Calculated orchestrator fee (on remaining after protocol)
     * @return solverFee Calculated solver fee (on remaining after protocol + orchestrator)
     */
    function _calculateBaseTokenFees(address _solver, address _token, uint256 _amount)
        internal
        view
        returns (uint256 protocolFee, uint256 orchestratorFee, uint256 solverFee)
    {
        Solver memory solver = solvers[_solver];
        uint8 decimals = IERC20Metadata(_token).decimals();
        // Protocol fee
        protocolFee = (protocolFeeFixed * 10 ** decimals) / 100;
        // Remaining after protocol fee
        uint256 remaining = _amount - protocolFee;
        // Orchestrator fee
        if (solver.orchestratorFeeType == FeeType.FIXED) {
            // If FIXED FeeType
            orchestratorFee = (solver.orchestratorFeeValue * 10 ** decimals) / 100;
        } else {
            // If PERCENTAGE FeeType
            orchestratorFee = (remaining * solver.orchestratorFeeValue) / 10000;
        }
        // Remaining after protocol + orchestrator fees
        remaining = remaining - orchestratorFee;
        // Solver fees
        if (solver.solverFeeType == FeeType.FIXED) {
            // If FIXED FeeType
            solverFee = (solver.solverFeeValue * 10 ** decimals) / 100;
        } else {
            // If PERCENTAGE FeeType
            solverFee = (remaining * solver.solverFeeValue) / 10000;
        }
    }

    /**
     * @notice Distributes fees (taken from first token) and transfers all tokens to solver
     * @param invoice Invoice data containing fee structure and solver information
     * @param tokens Array of all token data associated with the invoice
     * @return solverRepayment Amount of repayment sent to solver (for event emission)
     * @return totalFees Total fees collected (for event emission)
     * @dev Fees are denominated in the first token (base token), all other tokens are
     *      transferred fully to the solver executor. Prevents mixing fee denominations.
     */
    function _distributeFees(Invoice storage invoice, InvoiceTokenData[] storage tokens)
        internal
        returns (uint256 solverRepayment, uint256 totalFees)
    {
        if (tokens.length == 0) revert TM_EmptyTokenData();
        // Base token used for fees
        InvoiceTokenData storage base = tokens[0];
        address token = base.token;
        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        if (contractBalance < base.amount) revert IM_InsufficientContractBalance(token, base.amount, contractBalance);
        FeeStructure memory fees = invoice.fees;
        address solverExecutor = fees.solverExecutionAddress;
        totalFees = fees.protocolFee + fees.orchestratorFee + fees.solverFee;
        solverRepayment = base.amount - totalFees;
        // Transfer protocol and orchestrator fees
        if (fees.protocolFee > 0) {
            IERC20(token).safeTransfer(fees.protocolFeeReceiver, fees.protocolFee);
        }
        if (fees.orchestratorFee > 0) {
            IERC20(token).safeTransfer(fees.orchestratorFeeReceiver, fees.orchestratorFee);
        }
        // Transfer solver fee + repayment for base token
        if (fees.solverFeeReceiver == solverExecutor) {
            uint256 totalSolverAmount = solverRepayment + fees.solverFee;
            if (totalSolverAmount > 0) {
                IERC20(token).safeTransfer(solverExecutor, totalSolverAmount);
            }
        } else {
            if (fees.solverFee > 0) {
                IERC20(token).safeTransfer(fees.solverFeeReceiver, fees.solverFee);
            }
            if (solverRepayment > 0) {
                IERC20(token).safeTransfer(solverExecutor, solverRepayment);
            }
        }
        // Transfer all other tokens (if any) directly to solver executor
        uint256 tokenCount = tokens.length;
        if (tokenCount > 1) {
            for (uint256 i = 1; i < tokenCount; ++i) {
                IERC20 other = IERC20(tokens[i].token);
                uint256 amt = tokens[i].amount;
                if (amt > 0) {
                    uint256 bal = other.balanceOf(address(this));
                    if (bal < amt) revert IM_InsufficientContractBalance(tokens[i].token, amt, bal);
                    other.safeTransfer(solverExecutor, amt);
                }
            }
        }
    }

    /**
     * @notice Internal function to cleanup all invoice data
     * @param _solver Solver address
     * @param _sessionKey Session key to cleanup
     * @param _bidHash Bid hash associated with the invoice
     * @dev Deletes all invoice-related mappings and removes from solver's invoice list
     * @dev Centralizes cleanup logic used by both settleInvoice and cancelInvoice
     */
    function _cleanupInvoice(address _solver, address _sessionKey, bytes32 _bidHash) internal {
        delete invoices[_sessionKey];
        delete invoiceTokenData[_sessionKey];
        delete bidHashToSessionKey[_bidHash];
        _removeSolverInvoice(_solver, _sessionKey);
    }
}
