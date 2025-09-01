// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {BasePaymaster} from "ERC4337/core/BasePaymaster.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {UserOperationLib} from "ERC4337/core/UserOperationLib.sol";
import "ERC4337/core/Helpers.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {UniswapHelper} from "./utils/UniswapHelper.sol";

/**
 * @title GasTankPaymaster
 * @author Etherspot
 * @notice A paymaster implementation that allows users to pay for gas using ERC20 tokens
 * @dev This paymaster integrates with Uniswap V3 for token swaps and Chainlink oracles for price feeds.
 *      Users can deposit tokens into their "gas tank" and have transactions sponsored by the verifying signer.
 *      The paymaster automatically tops up the EntryPoint deposit using accumulated tokens.
 */
contract GasTankPaymaster is BasePaymaster, UniswapHelper {
    using UserOperationLib for PackedUserOperation;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Offset for valid timestamp in paymaster data
    uint256 private constant VALID_TIMESTAMP_OFFSET = PAYMASTER_DATA_OFFSET + 32;
    /// @notice Offset for signature in paymaster data
    uint256 private constant SIGNATURE_OFFSET = VALID_TIMESTAMP_OFFSET + 64;
    /// @notice Contract version following semantic versioning
    string private constant VERSION = "1.0.0";
    /// @notice Contract name for identification
    string private constant NAME = "GasTankPaymaster";
    /// @notice Denominator used for price calculations (1e26 for high precision)
    uint256 public constant PRICE_DENOMINATOR = 1e26;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address authorized to sign paymaster operations and manage the contract
    address payable public verifyingSigner;
    /// @notice Address used for receiving fees and topping up EntryPoint
    address payable public feeReceiver;
    /// @notice Current paymaster configuration
    GasTankPaymasterConfig private paymasterConfig;
    /// @notice Whether the paymaster is currently paused
    bool public paused;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configuration struct for the paymaster
     * @param tokenUsdFeed Oracle for token/USD price feed
     * @param nativeUsdFeed Oracle for native token/USD price feed
     * @param minEPBalance Minimum ETH balance to maintain in EntryPoint
     * @param cachedPriceTimestamp Timestamp of the last price update
     * @param tokenMaxAge Maximum age of token cached price before it's considered stale
     * @param nativeMaxAge Maximum age of native cached price before it's considered stale
     * @param postOpCost Gas cost for post-operation processing
     * @param cachedTokenPrice Cached token price to avoid frequent oracle calls
     * @param markup Price markup applied to oracle prices (in PRICE_DENOMINATOR units)
     * @param minVSTokenBalance Minimum token balance required for verifying signer to attempt top-up
     */
    struct GasTankPaymasterConfig {
        IOracle tokenUsdFeed;
        IOracle nativeUsdFeed;
        uint128 minEPBalance;
        uint48 cachedPriceTimestamp;
        uint48 tokenMaxAge;
        uint48 nativeMaxAge;
        uint48 postOpCost;
        uint256 cachedTokenPrice;
        uint256 markup;
        uint256 minFeeReceiverTokenBalance;
    }

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of wallet addresses to their token balances
    mapping(address wallet => uint256 balance) private balances;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the paymaster is paused
    event GasTankPaymaster_Paused();
    /// @notice Emitted when the paymaster is unpaused
    event GasTankPaymaster_Unpaused();
    /// @notice Emitted when paymaster configuration is updated
    event GasTankPaymaster_PaymasterConfigUpdated(GasTankPaymasterConfig newConfig);
    /// @notice Emitted when minimum token balance for top-up is updated
    event GasTankPaymaster_MinFeeReceiverTokenBalanceUpdated(uint256 oldMinBalance, uint256 newMinBalance);
    /// @notice Emitted when verifying signer is updated
    event GasTankPaymaster_VerifyingSignerUpdated(address verifyingSigner);
    /// @notice Emitted when fee receiver is updated
    event GasTankPaymaster_FeeReceiverUpdated(address feeReceiver);
    /// @notice Emitted when swap router is updated
    event GasTankPaymaster_SwapRouterUpdated(address swapRouter);
    /// @notice Emitted when supported token is updated
    event GasTankPaymaster_SupportedTokenUpdated(address supportedToken);
    /// @notice Emitted when wrapped native token is updated
    event GasTankPaymaster_WrappedNativeTokenUpdated(address wrappedNative);
    /// @notice Emitted when a user deposits tokens into their gas tank
    event GasTankPaymaster_Deposited(address indexed user, uint256 amount);
    /// @notice Emitted when a user withdraws tokens from their gas tank
    event GasTankPaymaster_Withdrawn(address indexed user, uint256 amount);
    /// @notice Emitted when the contract receives native tokens
    event GasTankPaymaster_Received(address indexed sender, uint256 value);
    /// @notice Emitted when a user operation is sponsored
    event GasTankPaymaster_UserOperationSponsored(
        address indexed sender,
        address indexed sponsor,
        uint256 actualGasCost,
        uint256 actualChargeNative,
        uint256 preChargeNative,
        uint256 indexed chainId,
        bool opReverted
    );
    /// @notice Emitted when a sponsored transaction is repaid
    event GasTankPaymaster_RepaySponsoredTransaction(address indexed from, uint256 amount);
    /// @notice Emitted when balance is insufficient but top-up is required
    event GasTankPaymaster_InsufficientBalanceButTopUpRequired(uint256 currentBalance, uint256 minRequired);
    /// @notice Emitted when EntryPoint top-up is executed successfully
    event GasTankPaymaster_TopUpExecuted(uint256 tokenUsed, uint256 nativeAmount);
    /// @notice Emitted when EntryPoint top-up fails
    event GasTankPaymaster_TopUpFailed(uint256 tokenUsed, uint256 nativeAmount);
    /// @notice Emitted when token price is updated
    event GasTankPaymaster_TokenPriceUpdated(uint256 currentPrice, uint256 previousPrice, uint256 cachedPriceTimestamp);
    /// @notice Emitted when oracle update fails
    event GasTankPaymaster_OracleUpdateFailed();
    /// @notice Emitted when token price is invalid
    event GasTankPaymaster_InvalidTokenPrice();
    /// @notice Emitted when native price is invalid
    event GasTankPaymaster_InvalidNativePrice();
    /// @notice Emitted when token price is stale
    event GasTankPaymaster_StaleTokenPrice();
    /// @notice Emitted when native price is stale
    event GasTankPaymaster_StaleNativePrice();
    /// @notice Emitted when top-up is skipped due to stale price
    event GasTankPaymaster_TopUpSkippedDueToStalePrice();
    /// @notice Emitted when emergency unsupported token recovery is executed successfully
    event GasTankPaymaster_EmergencyUnsupportedTokenRecovery(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when native is withdrawn
    event GasTankPaymaster_NativeWithdrawn(address indexed to, uint256 amount);
    /// @notice Emitted when wrapped native is withdrawn
    event GasTankPaymaster_WrappedNativeWithdrawn(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when contract is paused
    error GasTankPaymaster_IsPaused();
    /// @notice Thrown when price markup is too high
    error GasTankPaymaster_PriceMarkupTooHigh(uint256 markup);
    /// @notice Thrown when price markup is too low
    error GasTankPaymaster_PriceMarkupTooLow(uint256 markup);
    /// @notice Thrown when post-op gas limit is too low
    error GasTankPaymaster_PostOpGasLimitTooLow();
    /// @notice Thrown when paymaster signature length is invalid
    error GasTankPaymaster_InvalidPaymasterAndDataSignatureLength();
    /// @notice Thrown when an invalid address is provided
    error GasTankPaymaster_InvalidAddress();
    /// @notice Thrown when an invalid amount is provided
    error GasTankPaymaster_InvalidAmount();
    /// @notice Thrown when user has insufficient balance
    error GasTankPaymaster_InsufficientBalance(address user, uint256 amount);
    /// @notice Thrown when attempting to recover tokens from self
    error GasTankPaymaster_NoTokensToRecover(address token);
    /// @notice Thrown when attempting to recover main token
    error GasTankPaymaster_CannotRecoverMainToken();
    /// @notice Thrown when attempting to recover WETH
    error GasTankPaymaster_CannotRecoverWETH();
    /// @notice Thrown when attempting to set an invalid minimum top-up balance
    error GasTankPaymaster_InvalidFeeReceiverMinimumTopupBalance();
    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Ensures contract is not paused
    modifier whenNotPaused() {
        if (paused) revert GasTankPaymaster_IsPaused();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the GasTankPaymaster contract
     * @param _owner Address of the contract owner
     * @param _verifyingSigner Address authorized to sign paymaster operations
     * @param _feeReceiver Address to receive fees
     * @param _ep EntryPoint contract address
     * @param _swapRouter Uniswap V3 SwapRouter address
     * @param _token ERC20 token used for payments
     * @param _wrappedNative Wrapped native token address
     * @param _paymasterConfig Initial paymaster configuration
     * @param _uniswapConfig Uniswap helper configuration
     */
    constructor(
        address _owner,
        address payable _verifyingSigner,
        address payable _feeReceiver,
        IEntryPoint _ep,
        ISwapRouter _swapRouter,
        IERC20Metadata _token,
        IERC20 _wrappedNative,
        GasTankPaymasterConfig memory _paymasterConfig,
        UniswapHelperConfig memory _uniswapConfig
    ) BasePaymaster(_ep) UniswapHelper(_token, _wrappedNative, _swapRouter, _uniswapConfig) {
        if (_owner == address(0)) revert GasTankPaymaster_InvalidAddress();
        if (_verifyingSigner == address(0)) revert GasTankPaymaster_InvalidAddress();
        if (_feeReceiver == address(0)) revert GasTankPaymaster_InvalidAddress();
        if (address(_ep) == address(0)) revert GasTankPaymaster_InvalidAddress();
        if (address(_swapRouter) == address(0)) revert GasTankPaymaster_InvalidAddress();
        if (address(_token) == address(0)) revert GasTankPaymaster_InvalidAddress();
        if (address(_wrappedNative) == address(0)) revert GasTankPaymaster_InvalidAddress();
        if (address(_paymasterConfig.tokenUsdFeed) == address(0)) revert GasTankPaymaster_InvalidAddress();
        if (address(_paymasterConfig.nativeUsdFeed) == address(0)) revert GasTankPaymaster_InvalidAddress();
        verifyingSigner = _verifyingSigner;
        feeReceiver = _feeReceiver;
        configurePaymaster(_paymasterConfig);
        transferOwnership(_owner);
    }

    /*//////////////////////////////////////////////////////////////
                        PAYMASTER CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the paymaster configuration
     * @param _paymasterConfig New configuration parameters
     */
    function configurePaymaster(GasTankPaymasterConfig memory _paymasterConfig) public onlyOwner {
        if (_paymasterConfig.markup > 2 * PRICE_DENOMINATOR) {
            revert GasTankPaymaster_PriceMarkupTooHigh(_paymasterConfig.markup);
        }
        if (_paymasterConfig.markup < PRICE_DENOMINATOR) {
            revert GasTankPaymaster_PriceMarkupTooLow(_paymasterConfig.markup);
        }
        paymasterConfig = _paymasterConfig;
        emit GasTankPaymaster_PaymasterConfigUpdated(_paymasterConfig);
    }

    /**
     * @notice Updates the minimum token balance required for top-up attempts
     * @dev Only callable by the owner for operational flexibility
     * @param _newMinBalance New minimum token balance
     */
    function updateMinFeeReceiverTokenBalance(uint256 _newMinBalance) external onlyOwner {
        if (_newMinBalance == 0) revert GasTankPaymaster_InvalidFeeReceiverMinimumTopupBalance();
        uint256 oldMinBalance = paymasterConfig.minFeeReceiverTokenBalance;
        paymasterConfig.minFeeReceiverTokenBalance = _newMinBalance;
        emit GasTankPaymaster_MinFeeReceiverTokenBalanceUpdated(oldMinBalance, _newMinBalance);
    }

    /**
     * @notice Updates the verifying signer address
     * @dev Only callable by the owner
     * @param _verifyingSigner New verifying signer address
     */
    function setVerifyingSigner(address payable _verifyingSigner) external onlyOwner {
        if (_verifyingSigner == address(0)) revert GasTankPaymaster_InvalidAddress();
        verifyingSigner = _verifyingSigner;
        emit GasTankPaymaster_VerifyingSignerUpdated(_verifyingSigner);
    }

    /**
     * @notice Updates the fee receiver address
     * @dev Only callable by the owner
     * @param _feeReceiver New fee receiver address
     */
    function setFeeReceiver(address payable _feeReceiver) external onlyOwner {
        if (_feeReceiver == address(0)) revert GasTankPaymaster_InvalidAddress();
        feeReceiver = _feeReceiver;
        emit GasTankPaymaster_FeeReceiverUpdated(_feeReceiver);
    }

    /**
     * @notice Updates the Uniswap swap router address
     * @param _swapRouter New swap router address
     */
    function setSwapRouter(ISwapRouter _swapRouter) external onlyOwner {
        if (address(_swapRouter) == address(0)) revert GasTankPaymaster_InvalidAddress();
        uniswap = _swapRouter;
        token.approve(address(uniswap), type(uint256).max);
        emit GasTankPaymaster_SwapRouterUpdated(address(_swapRouter));
    }

    /**
     * @notice Updates the supported ERC20 token
     * @param _supportedToken New supported token address
     */
    function setSupportedToken(IERC20 _supportedToken) external onlyOwner {
        if (address(_supportedToken) == address(0)) revert GasTankPaymaster_InvalidAddress();
        token = _supportedToken;
        emit GasTankPaymaster_SupportedTokenUpdated(address(_supportedToken));
    }

    /**
     * @notice Updates the wrapped native token address
     * @param _wrappedNative New wrapped native token address
     */
    function setWrappedNativeToken(IERC20 _wrappedNative) external onlyOwner {
        if (address(_wrappedNative) == address(0)) revert GasTankPaymaster_InvalidAddress();
        wrappedNative = _wrappedNative;
        emit GasTankPaymaster_WrappedNativeTokenUpdated(address(_wrappedNative));
    }

    /*//////////////////////////////////////////////////////////////
                           GAS TANK OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits tokens into the sender's gas tank
     * @param _amount Amount of tokens to deposit
     */
    function gasTankDeposit(uint256 _amount) external {
        if (_amount == 0) revert GasTankPaymaster_InvalidAmount();
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), _amount);
        balances[msg.sender] += _amount;
        emit GasTankPaymaster_Deposited(msg.sender, _amount);
    }

    /**
     * @notice Deposits tokens into a specified wallet's gas tank
     * @param _wallet Target wallet address
     * @param _amount Amount of tokens to deposit
     */
    function gasTankDeposit(address _wallet, uint256 _amount) external {
        if (_wallet == address(0)) revert GasTankPaymaster_InvalidAddress();
        if (_amount == 0) revert GasTankPaymaster_InvalidAmount();
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), _amount);
        balances[_wallet] += _amount;
        emit GasTankPaymaster_Deposited(_wallet, _amount);
    }

    /**
     * @notice Withdraws tokens from the sender's gas tank
     * @param _amount Amount of tokens to withdraw
     */
    function gasTankWithdraw(uint256 _amount) external {
        uint256 currentBalance = balances[msg.sender];
        if (currentBalance < _amount) revert GasTankPaymaster_InsufficientBalance(msg.sender, _amount);
        SafeERC20.safeTransfer(token, msg.sender, _amount);
        balances[msg.sender] = currentBalance - _amount; // Safe due to check above
        emit GasTankPaymaster_Withdrawn(msg.sender, _amount);
    }

    /**
     * @notice Transfers tokens from a user's gas tank to the verifying signer's balance
     * @dev Only callable by the owner to collect payment for sponsored transactions
     * @param _from Address to transfer tokens from
     * @param _amount Amount of tokens to transfer
     */
    function repaySponsoredTransaction(address _from, uint256 _amount) external onlyOwner {
        if (_from == address(0)) revert GasTankPaymaster_InvalidAddress();
        if (_amount == 0) revert GasTankPaymaster_InvalidAmount();
        if (balances[_from] < _amount) revert GasTankPaymaster_InsufficientBalance(_from, _amount);
        balances[_from] -= _amount;
        balances[feeReceiver] += _amount;
        emit GasTankPaymaster_RepaySponsoredTransaction(_from, _amount);
    }

    /**
     * @notice Manually triggers EntryPoint deposit top-up
     * @dev Only callable by the owner
     */
    function topUpEntryPointDeposit() external onlyOwner {
        uint256 cPrice = updateCachedPrice(false);
        _topUpEntryPointDeposit(cPrice);
    }

    /*//////////////////////////////////////////////////////////////
                            ORACLE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the cached token price from oracle feeds
     * @param force Whether to force update regardless of cache age
     * @return Updated price, or 0 if update failed
     */
    function updateCachedPrice(bool force) public returns (uint256) {
        GasTankPaymasterConfig storage gtpConfig = paymasterConfig;
        uint256 cacheAge = block.timestamp - gtpConfig.cachedPriceTimestamp;
        if (!force && cacheAge <= gtpConfig.nativeMaxAge && gtpConfig.cachedTokenPrice > 0) {
            return gtpConfig.cachedTokenPrice;
        }
        // Try to get and validate prices
        (bool success, uint256 newPrice) = _tryGetFreshPrice(gtpConfig);
        if (success) {
            gtpConfig.cachedTokenPrice = newPrice;
            gtpConfig.cachedPriceTimestamp = uint48(block.timestamp);
            emit GasTankPaymaster_TokenPriceUpdated(newPrice, 0, gtpConfig.cachedPriceTimestamp);
            return newPrice;
        } else {
            emit GasTankPaymaster_OracleUpdateFailed();
            return 0; // Signal failure
        }
    }

    /*//////////////////////////////////////////////////////////////
                        PAYMASTER VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates a user operation for sponsorship
     * @param userOp The user operation to validate
     * @param requiredPreFund Required prefund amount
     * @return context Encoded context for post-operation processing
     * @return validationData Validation result and timing data
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32, /*userOpHash*/
        uint256 requiredPreFund
    ) internal view override whenNotPaused returns (bytes memory context, uint256 validationData) {
        (uint48 validUntil, uint48 validAfter, bytes calldata signature) =
            parsePaymasterAndData(userOp.paymasterAndData);
        // Signature validation
        if (signature.length != 64 && signature.length != 65) {
            revert GasTankPaymaster_InvalidPaymasterAndDataSignatureLength();
        }
        bytes32 hash = ECDSA.toEthSignedMessageHash(getHash(userOp, validUntil, validAfter));
        if (verifyingSigner != ECDSA.recover(hash, signature)) {
            return ("", _packValidationData(true, validUntil, validAfter));
        }
        // Calculate comprehensive charge information
        uint256 maxFeePerGas = userOp.unpackMaxFeePerGas();
        uint256 refundPostopCost = paymasterConfig.postOpCost;
        if (refundPostopCost >= userOp.unpackPostOpGasLimit()) {
            revert GasTankPaymaster_PostOpGasLimitTooLow();
        }
        uint256 preChargeNative = requiredPreFund + (refundPostopCost * maxFeePerGas);
        // Include more context for backend processing
        context = abi.encode(userOp.sender, preChargeNative);
        return (context, _packValidationData(false, validUntil, validAfter));
    }

    /**
     * @notice Post-operation processing after user operation execution
     * @param mode Post-operation mode (successful, reverted, or post-op reverted)
     * @param context Encoded context from validation phase
     * @param actualGasCost Actual gas cost of the operation
     * @param actualUserOpFeePerGas Actual fee per gas used
     */
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        internal
        override
    {
        (address userOpSender, uint256 preChargeNative) = abi.decode(context, (address, uint256));
        uint256 priceForTopUp;
        // Try to get fresh price
        try this.updateCachedPrice(false) returns (uint256 freshPrice) {
            if (freshPrice > 0) {
                priceForTopUp = freshPrice;
            } else {
                priceForTopUp = paymasterConfig.cachedTokenPrice;
            }
        } catch {
            priceForTopUp = paymasterConfig.cachedTokenPrice;
        }
        // Top up EntryPoint if required
        _topUpEntryPointDeposit(priceForTopUp);
        bool opReverted = mode == PostOpMode.opReverted;
        // Calculate total gas cost in native currency (wei)
        uint256 totalGasCostWei = actualGasCost + (paymasterConfig.postOpCost * actualUserOpFeePerGas);
        emit GasTankPaymaster_UserOperationSponsored(
            userOpSender,
            feeReceiver,
            actualGasCost,
            actualGasCost + paymasterConfig.postOpCost * actualUserOpFeePerGas,
            preChargeNative,
            block.chainid,
            opReverted
        );
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSE FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pauses the paymaster, preventing new operations
     * @dev Only callable by the owner
     */
    function pause() external onlyOwner {
        paused = true;
        emit GasTankPaymaster_Paused();
    }

    /**
     * @notice Unpauses the paymaster, allowing operations to resume
     * @dev Only callable by the owner
     */
    function unpause() external onlyOwner {
        paused = false;
        emit GasTankPaymaster_Unpaused();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current paymaster configuration
     * @return Current paymaster configuration struct
     */
    function getPaymasterConfig() external view returns (GasTankPaymasterConfig memory) {
        return paymasterConfig;
    }

    /**
     * @notice Returns comprehensive paymaster status information
     * @return entryPointBalance_ Current ETH balance in EntryPoint
     * @return cachedTokenPrice_ Current cached token price
     * @return priceTimestamp_ Timestamp of last price update
     * @return feeReceiverUSDCBalance_ Token balance of fee receiver
     * @return needsTopUp_ Whether EntryPoint needs top-up
     * @return isPaused_ Whether paymaster is paused
     */
    function getPaymasterStatus()
        external
        view
        returns (
            uint256 entryPointBalance_,
            uint256 cachedTokenPrice_,
            uint48 priceTimestamp_,
            uint256 feeReceiverUSDCBalance_,
            bool needsTopUp_,
            bool isPaused_
        )
    {
        entryPointBalance_ = entryPoint.balanceOf(address(this));
        cachedTokenPrice_ = paymasterConfig.cachedTokenPrice;
        priceTimestamp_ = paymasterConfig.cachedPriceTimestamp;
        feeReceiverUSDCBalance_ = balances[feeReceiver];
        needsTopUp_ = entryPointBalance_ < paymasterConfig.minEPBalance;
        isPaused_ = paused;
    }

    /**
     * @notice Returns the sender's gas tank balance
     * @return Token balance of the sender
     */
    function gasTankBalance() external view returns (uint256) {
        return balances[msg.sender];
    }

    /**
     * @notice Returns the gas tank balance for a specific wallet
     * @param _wallet Wallet address to check
     * @return Token balance of the specified wallet
     */
    function gasTankBalance(address _wallet) external view returns (uint256) {
        return balances[_wallet];
    }

    function supportedToken() public view returns (address) {
        return address(token);
    }

    function supportedWrappedNative() public view returns (address) {
        return address(wrappedNative);
    }

    /**
     * @notice Returns whether the paymaster is currently paused
     * @return Whether the paymaster is paused
     */
    function isPaused() external view returns (bool) {
        return paused;
    }

    /**
     * @notice Generates hash for user operation validation
     * @param userOp User operation to hash
     * @param validUntil Operation valid until timestamp
     * @param validAfter Operation valid after timestamp
     * @return Hash of the user operation data
     */
    function getHash(PackedUserOperation calldata userOp, uint48 validUntil, uint48 validAfter)
        public
        view
        returns (bytes32)
    {
        // Can't use userOp.hash(), since it contains also the paymasterAndData itself
        address sender = userOp.getSender();
        return keccak256(
            abi.encode(
                sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                uint256(bytes32(userOp.paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET:PAYMASTER_DATA_OFFSET])),
                userOp.preVerificationGas,
                userOp.gasFees,
                block.chainid,
                address(this),
                validUntil,
                validAfter
            )
        );
    }

    /**
     * @notice Parses paymaster data to extract validation parameters
     * @param paymasterAndData Encoded paymaster data
     * @return validUntil_ Operation valid until timestamp
     * @return validAfter_ Operation valid after timestamp
     * @return signature_ Signature bytes
     */
    function parsePaymasterAndData(bytes calldata paymasterAndData)
        public
        pure
        returns (uint48 validUntil_, uint48 validAfter_, bytes calldata signature_)
    {
        validUntil_ = uint48(bytes6(paymasterAndData[52:58]));
        validAfter_ = uint48(bytes6(paymasterAndData[58:64]));
        signature_ = paymasterAndData[64:];
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Automatically tops up EntryPoint deposit if needed
     * @param _cachedPrice Current cached token price
     */
    function _topUpEntryPointDeposit(uint256 _cachedPrice) internal {
        uint256 epBalance = entryPoint.balanceOf(address(this));
        uint256 minBalance = paymasterConfig.minEPBalance;
        // Early return if no top-up needed
        if (epBalance >= minBalance) return;
        // Skip top-up if we don't have a reliable price
        if (_cachedPrice == 0) {
            emit GasTankPaymaster_TopUpSkippedDueToStalePrice();
            return;
        }
        uint256 frBalance = balances[feeReceiver];
        uint8 tokenDecimals = IERC20Metadata(address(token)).decimals();
        uint256 minTokenBalance = paymasterConfig.minFeeReceiverTokenBalance;
        if (frBalance <= minTokenBalance) {
            // Early return if insufficient tokens
            emit GasTankPaymaster_InsufficientBalanceButTopUpRequired(frBalance, minTokenBalance);
            return;
        }
        uint256 swappedWeth = _maybeSwapTokenToWeth(token, frBalance, _cachedPrice);
        if (swappedWeth > 0) {
            balances[feeReceiver] = 0;
            unwrapWeth(swappedWeth);
            try entryPoint.depositTo{value: address(this).balance}(address(this)) {
                emit GasTankPaymaster_TopUpExecuted(frBalance, swappedWeth);
            } catch {
                emit GasTankPaymaster_TopUpFailed(frBalance, swappedWeth);
            }
        } else {
            emit GasTankPaymaster_TopUpFailed(frBalance, 0);
        }
    }

    /**
     * @notice Attempts to fetch fresh price data from oracle feeds
     * @param gtpConfig Reference to paymaster configuration
     * @return success Whether price fetch was successful
     * @return price New price if successful, 0 if failed
     */
    function _tryGetFreshPrice(GasTankPaymasterConfig storage gtpConfig)
        private
        returns (bool success, uint256 price)
    {
        try gtpConfig.tokenUsdFeed.latestRoundData() returns (
            uint80, int256 tokenUsdPrice, uint256, uint256 tokenUpdatedAt, uint80
        ) {
            try gtpConfig.nativeUsdFeed.latestRoundData() returns (
                uint80, int256 nativeUsdPrice, uint256, uint256 nativeUpdatedAt, uint80
            ) {
                // Validate prices
                if (tokenUsdPrice <= 0 || nativeUsdPrice <= 0) {
                    emit GasTankPaymaster_InvalidTokenPrice();
                    return (false, 0);
                }
                if (
                    block.timestamp - tokenUpdatedAt >= gtpConfig.tokenMaxAge
                        || block.timestamp - nativeUpdatedAt >= gtpConfig.nativeMaxAge
                ) {
                    emit GasTankPaymaster_StaleTokenPrice();
                    return (false, 0);
                }
                // Calculate price: (tokenUSD / nativeUSD) * PRICE_DENOMINATOR
                // Adjusting for different oracle decimal places
                uint256 newPrice = (
                    uint256(tokenUsdPrice) * (10 ** gtpConfig.nativeUsdFeed.decimals()) * PRICE_DENOMINATOR
                ) / (uint256(nativeUsdPrice) * (10 ** gtpConfig.tokenUsdFeed.decimals()));
                return (true, newPrice);
            } catch {
                return (false, 0);
            }
        } catch {
            return (false, 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                     EMERGENCY RECOVERY FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Recovers accidentally sent or airdropped tokens
     * @dev Only works for tokens that aren't part of core protocol
     * @param _token Token contract to recover
     * @param _to Address to send recovered tokens to
     */
    function emergencyUnsupportedTokenRecovery(IERC20 _token, address _to) external onlyOwner {
        if (_to == address(0)) revert GasTankPaymaster_InvalidAddress();
        // Prevent recovery of core protocol tokens
        if (address(_token) == address(token)) revert GasTankPaymaster_CannotRecoverMainToken();
        if (address(_token) == address(wrappedNative)) revert GasTankPaymaster_CannotRecoverWETH();
        uint256 balance = _token.balanceOf(address(this));
        if (balance == 0) revert GasTankPaymaster_NoTokensToRecover(address(_token));
        SafeERC20.safeTransfer(_token, _to, balance);
        emit GasTankPaymaster_EmergencyUnsupportedTokenRecovery(address(_token), _to, balance);
    }

    /**
     * @notice Withdraws all native tokens from the contract balance to the owner.
     * @dev Only callable by the owner. Convenience function for full withdrawal.
     * @param _to Address to send recovered tokens to
     */
    function withdrawAllNative(address payable _to) external onlyOwner {
        uint256 nativeBalance = address(this).balance;
        uint256 wNativeBalance = wrappedNative.balanceOf(address(this));
        if (nativeBalance > 0) {
            _to.transfer(nativeBalance);
            emit GasTankPaymaster_NativeWithdrawn(_to, nativeBalance);
        }
        if (wNativeBalance > 0) {
            SafeERC20.safeTransfer(wrappedNative, _to, wNativeBalance);
            emit GasTankPaymaster_WrappedNativeWithdrawn(_to, wNativeBalance);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Receives native tokens sent to the contract
     * @dev Emits an event when native tokens are received
     */
    receive() external payable {
        emit GasTankPaymaster_Received(msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                        NAME/VERSION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function name() external pure returns (string memory) {
        return NAME;
    }

    function version() external pure returns (string memory) {
        return VERSION;
    }
}
