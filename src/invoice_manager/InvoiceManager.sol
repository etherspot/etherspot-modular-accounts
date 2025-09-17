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

    address public feeReceiver;

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
        feeReceiver = _feeReceiver;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new invoice for payment processing from encoded CredibleAccountModule data
     * @param _invoiceData Encoded bytes containing all invoice and token data from CredibleAccountModule
     * @dev Only callable by addresses with CREDIBLE_ACCOUNT_ROLE (CredibleAccountModule)
     * @dev Unpacks: (smartWallet, sessionKey, solver, bidHash, chainId, TokenData[])
     * @dev All tokens must be whitelisted and solver must be active
     * @dev Snapshots the solver's fee at creation time to prevent fee manipulation
     */
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

    /**
     * @notice Settles an invoice by transferring tokens to solver and fees to fee receiver
     * @param _sessionKey Session key of the invoice to settle
     * @dev Only callable by addresses with SETTLER_ROLE or the linked smart wallet
     * @dev Uses reentrancy protection to prevent attacks during token transfers
     * @dev Calculates fees based on snapshotted fee amount from invoice creation
     * @dev Deletes all invoice data after successful settlement
     */
    function settleInvoice(address _sessionKey) external onlySettlerOrLinkedWallet(_sessionKey) nonReentrant {
        Invoice storage invoice = invoices[_sessionKey];
        if (invoice.createdAt == 0) revert IM_InvoiceNotFound();

        bytes32 bidHash = invoice.data.bidHash;
        address solver = invoice.data.solver;
        if (!_canSolverSettle(solver)) revert SM_SolverCannotSettle();

        InvoiceTokenData[] storage tokens = invoiceTokenData[_sessionKey];
        uint256 tokensLength = tokens.length;
        uint256 invoicePulseFee = invoice.pulseFee;

        for (uint256 i; i < tokensLength; ++i) {
            if (tokens[i].creditedAmount != tokens[i].amount) {
                revert IM_InvoiceNotFullyCredited(
                    _sessionKey, tokens[i].token, tokens[i].amount, tokens[i].creditedAmount
                );
            }
        }

        // Process token transfers in a separate internal function to reduce stack depth
        _processTokenTransfers(_sessionKey, solver, tokens, tokensLength, invoicePulseFee);

        // Update solver stats
        _incrementSolverSettlements(solver);

        // Clean up data
        delete bidHashToSessionKey[bidHash];
        delete invoices[_sessionKey];
        delete invoiceTokenData[_sessionKey];
        _removeSolverInvoice(solver, _sessionKey);

        // Remove solver if required
        if (solvers[solver].pendingOffboard && solverInvoices[solver].length() == 0) {
            delete solvers[solver];
            emit SolverOffboarded(solver);
        }

        emit InvoiceSettled(_sessionKey, bidHash, solver);
    }

    /**
     * @notice Credits tokens to a specific invoice, recording that tokens have been received
     * @dev Only accounts with CREDIBLE_ACCOUNT_ROLE can credit tokens. This function is part
     *      of the two-phase settlement process where tokens must be credited before settlement.
     * @param _sessionKey The session key identifying the invoice
     * @param _token The address of the token being credited
     * @param _amount The amount of tokens being credited
     */
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
        uint256 newCreditedAmount = tokenData[tokenIndex].creditedAmount + _amount;
        if (newCreditedAmount > tokenData[tokenIndex].amount) {
            revert IM_TokenOverCredited(_sessionKey, _token, tokenData[tokenIndex].amount, newCreditedAmount);
        }

        // Attribute received tokens to invoice
        tokenData[tokenIndex].creditedAmount = newCreditedAmount;
        emit TokensCreditedToInvoice(_sessionKey, _token, _amount);
    }

    /**
     * @notice Cancels an invoice and removes all associated data
     * @param _sessionKey Session key of the invoice to cancel
     * @param _reason Human-readable reason for cancellation
     * @dev Only callable by addresses with SETTLER_ROLE
     * @dev Cleans up all mappings and allows bid hash to be reused
     */
    function cancelInvoice(address _sessionKey, string calldata _reason) external onlyRole(SETTLER_ROLE) {
        Invoice storage invoice = invoices[_sessionKey];
        if (invoice.createdAt == 0) revert IM_InvoiceNotFound();

        bytes32 bidHash = invoice.data.bidHash;
        address solver = invoice.data.solver;

        delete invoices[_sessionKey];
        delete invoiceTokenData[_sessionKey];
        delete bidHashToSessionKey[bidHash];
        _removeSolverInvoice(solver, _sessionKey);

        emit InvoiceCancelled(_sessionKey, _reason);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the address that receives collected fees
     * @param _feeReceiver New fee receiver address
     * @dev Only callable by addresses with FEE_MANAGER_ROLE
     * @dev Cannot be set to zero address
     */
    function setFeeReceiver(address _feeReceiver) external onlyRole(FEE_MANAGER_ROLE) {
        if (_feeReceiver == address(0)) revert IM_InvalidAddress();
        address oldReceiver = feeReceiver;
        feeReceiver = _feeReceiver;
        emit FeeReceiverUpdated(oldReceiver, _feeReceiver);
    }

    /**
     * @notice Emergency function to withdraw tokens from the contract
     * @param _token Address of the token to withdraw
     * @param _amount Amount of tokens to withdraw
     * @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
     * @dev Transfers tokens to the caller (admin)
     * @dev Should be used for tokens that are not preallocated to an invoice
     */
    function emergencyWithdraw(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_amount == 0) revert IM_InvalidTokenAmount();
        uint256 contractBalance = IERC20(_token).balanceOf(address(this));
        if (contractBalance < _amount) {
            revert IM_InsufficientContractBalance(_token, _amount, contractBalance);
        }
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

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
    function getInvoice(address _sessionKey) external view returns (Invoice memory, InvoiceTokenData[] memory) {
        Invoice storage invoice = invoices[_sessionKey];
        if (invoice.createdAt == 0) revert IM_InvoiceNotFound();
        return (invoice, invoiceTokenData[_sessionKey]);
    }

    /**
     * @notice Finds the session key associated with a specific bid hash
     * @param _bidHash The bid hash to look up
     * @return sessionKey Session key associated with the bid hash
     * @dev Reverts if bid hash is not found
     */
    function getInvoiceByBidHash(bytes32 _bidHash) external view returns (address sessionKey) {
        sessionKey = bidHashToSessionKey[_bidHash];
        if (sessionKey == address(0)) revert IM_InvoiceNotFound();
    }

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

    /**
     * @notice Calculates fees for each token in an invoice
     * @param _sessionKey Session key of the invoice to analyze
     * @return tokenFees Array of TokenData with token addresses and their corresponding fees
     * @dev Uses snapshotted fee from invoice creation (custom or default)
     * @dev Caps fees at token amounts to prevent over-charging
     */
    function calculateInvoiceFees(address _sessionKey) external view returns (TokenData[] memory tokenFees) {
        Invoice storage invoice = invoices[_sessionKey];
        if (invoice.createdAt == 0) revert IM_InvoiceNotFound();

        InvoiceTokenData[] storage tokenData = invoiceTokenData[_sessionKey];
        uint256 length = tokenData.length;
        tokenFees = new TokenData[](length);

        for (uint256 i; i < length; ++i) {
            uint256 fee = _calculateFeeForToken(tokenData[i].token, invoice.pulseFee);
            tokenFees[i] =
                TokenData({token: tokenData[i].token, amount: fee > tokenData[i].amount ? tokenData[i].amount : fee});
        }
    }

    /**
     * @notice Checks if an invoice can be successfully settled
     * @param _sessionKey Session key of the invoice to check
     * @return True if invoice exists, solver is active, all tokens are fully credited, and contract has sufficient token balances
     * @dev Performs balance checks and credit verification for all tokens in the invoice
     */
    function isInvoiceSettleable(address _sessionKey) external view returns (bool) {
        Invoice storage invoice = invoices[_sessionKey];
        if (invoice.createdAt == 0) return false;
        if (!_isSolverActive(invoice.data.solver)) return false;

        InvoiceTokenData[] storage tokenData = invoiceTokenData[_sessionKey];
        uint256 tokenDataLength = tokenData.length;

        for (uint256 i; i < tokenDataLength; ++i) {
            // Check if all tokens have been fully credited
            if (tokenData[i].creditedAmount != tokenData[i].amount) {
                return false;
            }
            // Check if contract has sufficient balance
            if (IERC20(tokenData[i].token).balanceOf(address(this)) < tokenData[i].amount) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Checks if an invoice exists for a given session key
     * @param _sessionKey Session key to check
     * @return True if invoice exists (has non-zero creation timestamp)
     */
    function invoiceExists(address _sessionKey) external view returns (bool) {
        return invoices[_sessionKey].createdAt != 0;
    }

    /**
     * @notice Checks if a bid hash is already in use
     * @param _bidHash Bid hash to check
     * @return True if bid hash is associated with an existing invoice
     */
    function bidHashExists(bytes32 _bidHash) external view returns (bool) {
        return bidHashToSessionKey[_bidHash] != address(0);
    }

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

    /**
     * @notice Grants CREDIBLE_ACCOUNT_ROLE to an address
     * @param _account Address to grant the role to
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function grantCredibleAccountRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(CREDIBLE_ACCOUNT_ROLE, _account);
    }

    /**
     * @notice Revokes CREDIBLE_ACCOUNT_ROLE from an address
     * @param _account Address to revoke the role from
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function revokeCredibleAccountRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(CREDIBLE_ACCOUNT_ROLE, _account);
    }

    /**
     * @notice Grants SETTLER_ROLE to an address
     * @param _account Address to grant the role to
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function grantSettlerRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(SETTLER_ROLE, _account);
    }

    /**
     * @notice Revokes SETTLER_ROLE from an address
     * @param _account Address to revoke the role from
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
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
        if (smartWallet == address(0) || sessionKey == address(0) || solver == address(0)) {
            revert IM_InvalidAddress();
        }

        // Validate chain ID if specified
        if (chainId != 0 && chainId != block.chainid) {
            revert IM_InvalidChainId(chainId);
        }

        // Check solver is active
        if (!_isSolverActive(solver)) revert SM_SolverInactive();

        // Validate token data
        uint256 tokenDataLength = tokenData.length;
        if (tokenDataLength == 0) revert TM_EmptyTokenData();

        // Get solver fee amount for validation
        uint256 solverPulseFee = _getSolverFeeAmount(solver);

        // Check all tokens are whitelisted and amounts are valid
        for (uint256 i; i < tokenDataLength; ++i) {
            if (!_isTokenWhitelisted(tokenData[i].token)) {
                revert TM_TokenNotWhitelisted(tokenData[i].token);
            }
            if (tokenData[i].amount == 0) revert IM_InvalidTokenAmount();
            // Check token amount is gt than calculated pulse fee
            uint256 pulseFee = _calculateFeeForToken(tokenData[i].token, solverPulseFee);
            if (tokenData[i].amount <= pulseFee) revert IM_InvalidTokenAmount();
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
        // Create InvoiceData struct
        InvoiceData memory invoiceDataStruct = InvoiceData({
            smartWallet: smartWallet,
            sessionKey: sessionKey,
            solver: solver,
            bidHash: bidHash,
            chainId: chainId
        });

        // Store invoice data
        Invoice storage invoice = invoices[sessionKey];
        invoice.data = invoiceDataStruct;
        invoice.createdAt = block.timestamp;
        invoice.pulseFee = _getSolverFeeAmount(solver);

        // Store token data
        uint256 tokenDataLength = tokenData.length;
        for (uint256 i; i < tokenDataLength; ++i) {
            invoiceTokenData[sessionKey].push(
                InvoiceTokenData({
                    token: tokenData[i].token,
                    amount: tokenData[i].amount, // Expected amount
                    creditedAmount: 0 // No tokens received yet
                })
            );
        }

        // Update mappings
        bidHashToSessionKey[bidHash] = sessionKey;
        _addSolverInvoice(solver, sessionKey);

        emit InvoiceCreated(sessionKey, bidHash, solver, tokenDataLength, invoice.pulseFee);
    }

    /**
     * @notice Calculate fee for a specific token with optional override
     * @param _token Token address
     * @param _feeOverride Fee override amount (0 means use calculated default)
     * @return fee Final fee amount in token's native decimals
     */
    function _calculateFeeForToken(address _token, uint256 _feeOverride) internal view returns (uint256 fee) {
        uint256 pulseFee = _feeOverride == 0 ? PULSE_BASE_FEE : _feeOverride; // Default 5 cents = 0.05 tokens
        try IERC20Metadata(_token).decimals() returns (uint8 decimals) {
            // Convert cents to token amount: (cents * 10^decimals) / 100
            return (pulseFee * 10 ** decimals) / 100;
        } catch {
            return (pulseFee * 10 ** 18) / 100; // Fallback to 18 decimals
        }
    }

    /**
     * @dev Internal function to process token transfers
     */
    function _processTokenTransfers(
        address _sessionKey,
        address solver,
        InvoiceTokenData[] storage tokens,
        uint256 tokensLength,
        uint256 invoicePulseFee
    ) internal {
        for (uint256 i; i < tokensLength; ++i) {
            address token = tokens[i].token;
            uint256 amount = tokens[i].amount;
            uint256 contractBalance = IERC20(token).balanceOf(address(this));

            if (contractBalance < amount) {
                revert IM_InsufficientContractBalance(token, amount, contractBalance);
            }

            uint256 pulseFee = _calculateFeeForToken(token, invoicePulseFee);
            if (pulseFee > amount) {
                pulseFee = amount;
            }
            uint256 solverAmount = amount - pulseFee;

            // Transfer tokens
            if (pulseFee > 0) {
                IERC20(token).safeTransfer(feeReceiver, pulseFee);
            }
            IERC20(token).safeTransfer(solver, solverAmount);

            emit TokenPaid(_sessionKey, solver, token, amount, pulseFee, solverAmount);
        }
    }
}
