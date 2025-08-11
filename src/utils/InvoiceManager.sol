// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IInvoiceManager} from "../interfaces/IInvoiceManager.sol";
import {TokenData} from "../common/Structs.sol";

/**
 * @title InvoiceManager
 * @notice Manages invoices for cross-chain payment processing with configurable solver fees
 * @author Etherspot
 */
contract InvoiceManager is IInvoiceManager, AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant CREDIBLE_ACCOUNT_ROLE = keccak256("CREDIBLE_ACCOUNT_ROLE");
    bytes32 public constant SETTLER_ROLE = keccak256("SETTLER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant SOLVER_MANAGER_ROLE = keccak256("SOLVER_MANAGER_ROLE");
    uint256 public constant PULSE_BASE_FEE = 5;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public feeReceiver;
    EnumerableSet.AddressSet private whitelistedTokens;

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(address => Invoice) public invoices;
    mapping(bytes32 => address) public bidHashToSessionKey;
    mapping(address => Solver) public solvers;
    mapping(address => EnumerableSet.AddressSet) private solverInvoices;
    mapping(address => InvoiceTokenData[]) public invoiceTokenData;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error IM_InvoiceNotFound();
    error IM_InvoiceAlreadyExists();
    error IM_InvalidSolver();
    error IM_SolverAlreadyExists();
    error IM_InvalidAddress();
    error IM_EmptyTokenData();
    error IM_BidHashAlreadyExists();
    error IM_InvalidTokenAmount();
    error IM_SolverInactive();
    error IM_UnauthorizedSettler(address caller, address sessionKey);
    error IM_TokenNotWhitelisted(address token);
    error IM_TokenAlreadyWhitelisted(address token);
    error IM_EmptyTokenWhitelist();
    error IM_InsufficientContractBalance(address token, uint256 requiredAmount, uint256 availableBalance);
    error IM_ArraysLengthMismatch();
    error IM_InvalidChainId(uint256 chainId);
    error IM_TokenNotFoundInInvoice(address sessionKey, address token);
    error IM_TokenAlreadyCredited(address sessionKey, address token);
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

    modifier onlyWhitelistedTokens(TokenData[] calldata _tokenData) {
        uint256 tokenDataLength = _tokenData.length;
        for (uint256 i; i < tokenDataLength; ++i) {
            if (!whitelistedTokens.contains(_tokenData[i].token)) {
                revert IM_TokenNotWhitelisted(_tokenData[i].token);
            }
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
     * @param _whitelistedTokens Array of token addresses to whitelist at deployment
     * @dev Reverts if any address is zero or if no tokens are provided for whitelist
     */
    constructor(
        address _owner,
        address _credibleAccountModule,
        address _feeReceiver,
        address _feeManager,
        address[] memory _whitelistedTokens
    ) {
        if (
            _owner == address(0) || _credibleAccountModule == address(0) || _feeReceiver == address(0)
                || _feeManager == address(0)
        ) {
            revert IM_InvalidAddress();
        }
        if (_whitelistedTokens.length == 0) {
            revert IM_EmptyTokenWhitelist();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(CREDIBLE_ACCOUNT_ROLE, _credibleAccountModule);
        _grantRole(SETTLER_ROLE, _owner);
        _grantRole(FEE_MANAGER_ROLE, _feeManager);
        _grantRole(SOLVER_MANAGER_ROLE, _owner);
        feeReceiver = _feeReceiver;
        for (uint256 i; i < _whitelistedTokens.length; ++i) {
            if (_whitelistedTokens[i] == address(0)) {
                revert IM_InvalidAddress();
            }
            whitelistedTokens.add(_whitelistedTokens[i]);
            emit TokenWhitelisted(_whitelistedTokens[i], _owner);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new invoice for payment processing from encoded CredibleAccountModule data
     * @param _invoiceData Encoded bytes containing all invoice and token data from CredibleAccountModule
     * @return sessionKey The session key address of the created invoice
     * @dev Only callable by addresses with CREDIBLE_ACCOUNT_ROLE (CredibleAccountModule)
     * @dev Unpacks: (smartWallet, sessionKey, solver, bidHash, chainId, TokenData[])
     * @dev All tokens must be whitelisted and solver must be active
     * @dev Snapshots the solver's fee at creation time to prevent fee manipulation
     */
    function createInvoice(bytes memory _invoiceData)
        external
        onlyRole(CREDIBLE_ACCOUNT_ROLE)
        returns (address sessionKey)
    {
        // Unpack the encoded data from CredibleAccountModule
        (
            address smartWallet,
            address sessionKeyAddr,
            address solver,
            bytes32 bidHash,
            uint256 chainId,
            TokenData[] memory tokenData
        ) = abi.decode(_invoiceData, (address, address, address, bytes32, uint256, TokenData[]));
        sessionKey = sessionKeyAddr;
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
        if (!solvers[solver].isActive) revert IM_SolverInactive();
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
        unchecked {
            solvers[solver].successfulSettlements++;
        }
        // Clean up data
        delete bidHashToSessionKey[bidHash];
        delete invoices[_sessionKey];
        delete invoiceTokenData[_sessionKey];
        solverInvoices[solver].remove(_sessionKey);
        emit InvoiceSettled(_sessionKey, bidHash, solver);
    }

    /**
     * @notice Credits tokens to a specific invoice, recording that tokens have been received
     * @dev Only accounts with CREDIBLE_ACCOUNT_ROLE can credit tokens. This function is part
     *      of the two-phase settlement process where tokens must be credited before settlement.
     * @param _sessionKey The session key identifying the invoice
     * @param _token The address of the token being credited
     * @param _amount The amount of tokens being credited
     *
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
        if (tokenData[tokenIndex].creditedAmount == tokenData[tokenIndex].amount) {
            revert IM_TokenAlreadyCredited(_sessionKey, _token);
        }
        // 4. if checks passed then attribute to invoice
        tokenData[tokenIndex].creditedAmount = newCreditedAmount;
        emit TokensCreditedToInvoice(_sessionKey, _token, _amount);
    }

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
        if (_solver == address(0)) revert IM_InvalidAddress();
        Solver storage solver = solvers[_solver];
        if (solver.solverAddress != address(0)) revert IM_SolverAlreadyExists();
        solver.solverAddress = _solver;
        solver.isActive = true;
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
        if (solver.solverAddress == address(0)) revert IM_InvalidSolver();
        uint256 oldFee = solver.pulseFee;
        solver.pulseFee = _newFee;
        emit SolverFeeUpdated(_solver, oldFee, _newFee);
    }

    /**
     * @notice Removes a solver from the system and cleans up associated data
     * @param _solver Address of the solver to remove
     * @dev Only callable by addresses with SOLVER_MANAGER_ROLE
     * @dev Deletes solver data and associated invoice mappings
     */
    function offboardSolver(address _solver) external onlyRole(SOLVER_MANAGER_ROLE) {
        if (solvers[_solver].solverAddress == address(0)) revert IM_InvalidSolver();
        delete solverInvoices[_solver];
        delete solvers[_solver];
        emit SolverOffboarded(_solver);
    }

    /**
     * @notice Toggles the active status of a solver between active and inactive
     * @param _solver Address of the solver to toggle
     * @dev Only callable by addresses with SOLVER_MANAGER_ROLE
     * @dev Inactive solvers cannot have new invoices created for them
     */
    function toggleSolverStatus(address _solver) external onlyRole(SOLVER_MANAGER_ROLE) {
        Solver storage solver = solvers[_solver];
        if (solver.solverAddress == address(0)) revert IM_InvalidSolver();
        solver.isActive = !solver.isActive;
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
        solverInvoices[solver].remove(_sessionKey);
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
     * @notice Gets all active invoice session keys for a specific solver
     * @param _solver Address of the solver to query
     * @return Array of session key addresses for active invoices
     */
    function getSolverInvoices(address _solver) external view returns (address[] memory) {
        return solverInvoices[_solver].values();
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
     * @return True if invoice exists, solver is active, and contract has sufficient token balances
     * @dev Performs balance checks for all tokens in the invoice
     */
    function isInvoiceSettleable(address _sessionKey) external view returns (bool) {
        Invoice storage invoice = invoices[_sessionKey];
        if (invoice.createdAt == 0) return false;
        if (!solvers[invoice.data.solver].isActive) return false;
        InvoiceTokenData[] storage tokenData = invoiceTokenData[_sessionKey];
        uint256 tokenDataLength = tokenData.length;
        for (uint256 i; i < tokenDataLength; ++i) {
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
        )
    {
        Solver storage solver = solvers[_solver];
        return (
            solver.name,
            solver.isActive,
            solver.successfulSettlements,
            solverInvoices[_solver].length(),
            solver.pulseFee
        );
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
                    TOKEN WHITELIST MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a token to the whitelist
     * @param _token The token address to whitelist
     */
    function addTokenToWhitelist(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_token == address(0)) revert IM_InvalidAddress();
        if (whitelistedTokens.contains(_token)) revert IM_TokenAlreadyWhitelisted(_token);

        whitelistedTokens.add(_token);
        emit TokenWhitelisted(_token, msg.sender);
    }

    /**
     * @notice Add multiple tokens to the whitelist
     * @param _tokens Array of token addresses to whitelist
     */
    function addTokensToWhitelist(address[] calldata _tokens) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 tokensLength = _tokens.length;
        if (tokensLength == 0) revert IM_EmptyTokenData();
        for (uint256 i; i < tokensLength; ++i) {
            address token = _tokens[i];
            if (token == address(0)) revert IM_InvalidAddress();
            if (!whitelistedTokens.contains(token)) {
                whitelistedTokens.add(token);
                emit TokenWhitelisted(token, msg.sender);
            }
        }
    }

    /**
     * @notice Remove a token from the whitelist
     * @param _token The token address to remove from whitelist
     */
    function removeTokenFromWhitelist(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!whitelistedTokens.contains(_token)) revert IM_TokenNotWhitelisted(_token);
        whitelistedTokens.remove(_token);
        emit TokenRemovedFromWhitelist(_token, msg.sender);
    }

    /**
     * @notice Remove multiple tokens from the whitelist
     * @param _tokens Array of token addresses to remove from whitelist
     */
    function removeTokensFromWhitelist(address[] calldata _tokens) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 tokensLength = _tokens.length;
        for (uint256 i; i < tokensLength; ++i) {
            address token = _tokens[i];
            if (whitelistedTokens.contains(token)) {
                whitelistedTokens.remove(token);
                emit TokenRemovedFromWhitelist(token, msg.sender);
            }
        }
    }

    /**
     * @notice Check if a token is whitelisted
     * @param _token The token address to check
     * @return bool True if token is whitelisted
     */
    function isTokenWhitelisted(address _token) external view returns (bool) {
        return whitelistedTokens.contains(_token);
    }

    /**
     * @notice Get all whitelisted tokens
     * @return address[] Array of whitelisted token addresses
     */
    function getWhitelistedTokens() external view returns (address[] memory) {
        return whitelistedTokens.values();
    }

    /**
     * @notice Get the number of whitelisted tokens
     * @return uint256 Number of whitelisted tokens
     */
    function getWhitelistedTokensCount() external view returns (uint256) {
        return whitelistedTokens.length();
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
     *
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
        if (!solvers[solver].isActive) revert IM_SolverInactive();

        // Validate token data
        uint256 tokenDataLength = tokenData.length;
        if (tokenDataLength == 0) revert IM_EmptyTokenData();

        // Check all tokens are whitelisted and amounts are valid
        for (uint256 i; i < tokenDataLength; ++i) {
            if (!whitelistedTokens.contains(tokenData[i].token)) {
                revert IM_TokenNotWhitelisted(tokenData[i].token);
            }
            if (tokenData[i].amount == 0) revert IM_InvalidTokenAmount();
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
     *
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
        solverInvoices[solver].add(sessionKey);

        emit InvoiceCreated(sessionKey, bidHash, solver, tokenDataLength, invoice.pulseFee);
    }

    /**
     * @notice Get the effective fee amount for a solver (custom or default)
     * @param _solver Solver address
     * @return feeAmount The fee amount to use (0 means use calculated default)
     */
    function _getSolverFeeAmount(address _solver) internal view returns (uint256 feeAmount) {
        return solvers[_solver].pulseFee; // 0 means use default, non-zero means custom
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
            // TODO: check †his logic
            // Ensure fee doesn't exceed token amount
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
