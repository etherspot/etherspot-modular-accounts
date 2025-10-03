# Gas Tank Paymaster

The GasTankPaymaster is an ERC-4337 compatible paymaster implementation that enables users to pay for gas fees using ERC20 tokens through a "gas tank" deposit system, with automatic liquidity management via Uniswap V3 integration and oracle-based pricing.

## Overview

This paymaster implements a sponsored transaction model where users deposit ERC20 tokens into their personal "gas tanks" and have their transactions sponsored by a verifying signer. The contract automatically manages liquidity by swapping accumulated tokens for native currency to maintain EntryPoint deposits, using Chainlink oracles for accurate pricing and Uniswap V3 for efficient token swaps.

## Key Features

- **Gas Tank System**: Personal token balances for each user with deposit/withdrawal functionality
- **ERC-4337 Compliance**: Full EntryPoint integration with user operation validation and sponsorship
- **Oracle Integration**: Chainlink price feeds for accurate token-to-native conversion rates
- **Automated Liquidity Management**: Automatic EntryPoint top-ups using accumulated tokens
- **Uniswap V3 Integration**: Efficient token swapping for liquidity management
- **Emergency Recovery**: Unsupported fund recovery mechanisms
- **Pause Functionality**: Circuit breaker for emergency situations
- **Role-Based Access**: Controlled access for critical operations
- **Price Caching**: Gas-efficient oracle price caching with staleness protection

## Architecture

The paymaster operates through several interconnected systems:

- **Validation Layer**: ERC-4337 user operation validation with signature verification
- **Gas Tank Management**: Token deposit/withdrawal system with balance tracking
- **Oracle System**: Price feed integration with caching and staleness protection
- **Liquidity Management**: Automated token swapping and EntryPoint deposit management
- **Access Control**: Role-based permissions for operational and emergency functions

## Core Concepts

### Gas Tank System

Individual token balance accounts that users can deposit to and withdraw from, enabling prepaid gas payments through ERC20 tokens rather than native currency.

### Sponsored Transaction Model

The verifying signer sponsors user operations upfront, with costs later recovered through the gas tank system or direct token transfers.

### Automatic Liquidity Management

The contract monitors EntryPoint deposits and automatically swaps accumulated tokens for native currency to maintain sufficient liquidity for sponsoring transactions.

### Oracle-Based Pricing

Real-time price feeds from Chainlink oracles ensure accurate token-to-native conversion rates, with markup configuration for operational costs and price volatility protection.

### Emergency Circuit Breakers

Comprehensive pause functionality and emergency unsupported token recovery mechanisms protect against various failure modes and ensure fund security.

## Contract Methods

### Core Paymaster Methods

#### `_validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 requiredPreFund)`

Primary ERC-4337 validation method that authenticates user operations and prepares sponsorship context.

**Parameters:**

- `userOp`: The user operation to validate
- `userOpHash`: Hash of the user operation (unused in current implementation)
- `requiredPreFund`: Required prefund amount for the operation

**Process:**

1. Parses paymaster data to extract validity timestamps and signature
2. Validates signature length (64 or 65 bytes)
3. Recovers signer from operation hash using ECDSA
4. Compares recovered signer with verifying signer
5. Calculates comprehensive charge information including post-op costs
6. Encodes context for post-operation processing

**Returns:**

- `context`: Encoded data containing sender and pre-charge amount
- `validationData`: Packed validation result with timing constraints

**Requirements:**

- Contract must not be paused
- Signature must be valid length
- Signature must be from authorized verifying signer
- Post-op gas limit must be sufficient

**Errors:**

- `GasTankPaymaster_IsPaused()`: Contract is paused
- `GasTankPaymaster_InvalidPaymasterAndDataSignatureLength()`: Invalid signature format
- `GasTankPaymaster_PostOpGasLimitTooLow()`: Insufficient gas limit for post-op

#### `_postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)`

Post-operation processing that handles EntryPoint top-ups and emits sponsorship events.

**Parameters:**

- `mode`: Post-operation mode (successful, reverted, or post-op reverted)
- `context`: Encoded context from validation phase
- `actualGasCost`: Actual gas cost of the user operation
- `actualUserOpFeePerGas`: Actual fee per gas used

**Process:**

1. Decodes sender and pre-charge amount from context
2. Triggers EntryPoint deposit top-up if needed
3. Calculates total gas costs including post-op fees
4. Emits comprehensive sponsorship event

**Events:**

- `GasTankPaymaster_UserOperationSponsored(address indexed sender, address indexed sponsor, uint256 actualGasCost, uint256 actualChargeNative, uint256 preChargeNative, uint256 indexed chainId, bool opReverted)`: Detailed sponsorship information

### Gas Tank Operations

#### `gasTankDeposit(uint256 _amount)`

Deposits tokens into the sender's gas tank balance.

**Parameters:**

- `_amount`: Amount of tokens to deposit

**Process:**

1. Validates amount is non-zero
2. Transfers tokens from sender to contract
3. Updates sender's balance
4. Emits deposit event

**Requirements:**

- Amount must be greater than zero
- Sender must have sufficient token balance and allowance

**Events:**

- `GasTankPaymaster_Deposited(address user, uint256 amount)`

**Errors:**

- `GasTankPaymaster_InvalidAmount()`: Zero amount provided

#### `gasTankDeposit(address _wallet, uint256 _amount)`

Deposits tokens into a specified wallet's gas tank balance.

**Parameters:**

- `_wallet`: Target wallet address for the deposit
- `_amount`: Amount of tokens to deposit

**Process:**

1. Validates wallet address and amount
2. Transfers tokens from sender to contract
3. Updates target wallet's balance
4. Emits deposit event

**Requirements:**

- Wallet address must be valid
- Amount must be greater than zero
- Sender must have sufficient tokens and allowance

**Events:**

- `GasTankPaymaster_Deposited(address user, uint256 amount)`

**Errors:**

- `GasTankPaymaster_InvalidAddress()`: Invalid wallet address
- `GasTankPaymaster_InvalidAmount()`: Zero amount provided

#### `gasTankWithdraw(uint256 _amount)`

Withdraws tokens from the sender's gas tank balance.

**Parameters:**

- `_amount`: Amount of tokens to withdraw

**Process:**

1. Checks sender's current balance
2. Validates sufficient balance exists
3. Transfers tokens to sender
4. Updates balance (using safe arithmetic)
5. Emits withdrawal event

**Requirements:**

- Sender must have sufficient balance
- Amount must be greater than zero

**Events:**

- `GasTankPaymaster_Withdrawn(address user, uint256 amount)`

**Errors:**

- `GasTankPaymaster_InsufficientBalance(address user, uint256 amount)`: Insufficient balance

#### `repaySponsoredTransaction(address _from, uint256 _amount)`

Transfers tokens from a user's gas tank to the verifying signer's balance to repay sponsored transactions.

**Parameters:**

- `_from`: Address to transfer tokens from
- `_amount`: Amount of tokens to transfer

**Process:**

1. Validates input parameters
2. Checks sufficient balance exists
3. Transfers tokens between internal balances
4. Emits repayment event

**Requirements:**

- Only callable by verifying signer
- Valid addresses and amounts
- Sufficient balance in source account
- Cannot transfer to self

**Events:**

- `GasTankPaymaster_RepaySponsoredTransaction(address from, uint256 amount)`

**Errors:**

- `GasTankPaymaster_OnlyVerifyingSigner()`: Unauthorized caller
- `GasTankPaymaster_InvalidAddress()`: Invalid address
- `GasTankPaymaster_InvalidAmount()`: Invalid amount
- `GasTankPaymaster_SelfTransfer()`: Self-transfer attempt
- `GasTankPaymaster_InsufficientBalance()`: Insufficient balance

### Oracle and Pricing Methods

#### `updateCachedPrice(bool force)`

Updates the cached token price from oracle feeds with staleness protection.

**Parameters:**

- `force`: Whether to force update regardless of cache age

**Process:**

1. Checks cache age against maximum allowed age
2. Returns cached price if still valid and not forced
3. Attempts to fetch fresh prices from oracles
4. Validates price data and staleness
5. Updates cache with new price and timestamp
6. Emits price update event

**Returns:**

- Updated price in internal denomination, or 0 if update failed

**Events:**

- `GasTankPaymaster_TokenPriceUpdated()`: Price update information
- `GasTankPaymaster_OracleUpdateFailed()`: Oracle fetch failure

#### `topUpEntryPointDeposit()`

Manually triggers EntryPoint deposit top-up using accumulated tokens.

**Process:**

1. Updates cached price
2. Calls internal top-up function
3. Executes token swap and deposit process

**Requirements:**

- Only callable by verifying signer
- Sufficient token balance for meaningful top-up

**Events:**

- `GasTankPaymaster_TopUpExecuted()`: Successful top-up
- `GasTankPaymaster_TopUpFailed()`: Top-up failure

**Errors:**

- `GasTankPaymaster_OnlyVerifyingSigner()`: Unauthorized caller

### Configuration Methods

#### `configurePaymaster(GasTankPaymasterConfig memory _paymasterConfig)`

Updates the paymaster configuration with new parameters.

**Parameters:**

- `_paymasterConfig`: New configuration struct with all parameters

**Process:**

1. Validates markup bounds (between 1x and 2x)
2. Updates configuration storage
3. Emits configuration update event

**Requirements:**

- Only callable by owner
- Markup must be between PRICE_DENOMINATOR and 2 * PRICE_DENOMINATOR

**Events:**

- `GasTankPaymaster_PaymasterConfigUpdated(GasTankPaymasterConfig newConfig)`

**Errors:**

- `GasTankPaymaster_PriceMarkupTooHigh(uint256 markup)`: Markup too high
- `GasTankPaymaster_PriceMarkupTooLow(uint256 markup)`: Markup too low

#### `setSwapRouter(ISwapRouter _swapRouter)`

Updates the Uniswap V3 swap router address.

**Parameters:**

- `_swapRouter`: New swap router contract address

**Requirements:**

- Only callable by owner
- Router address must be valid

**Events:**

- `GasTankPaymaster_SwapRouterUpdated(address swapRouter)`

**Errors:**

- `GasTankPaymaster_InvalidAddress()`: Invalid router address

#### `setSupportedToken(IERC20 _supportedToken)`

Updates the supported ERC20 token for gas payments.

**Parameters:**

- `_supportedToken`: New token contract address

**Requirements:**

- Only callable by owner
- Token address must be valid

**Events:**

- `GasTankPaymaster_SupportedTokenUpdated(address supportedToken)`

**Errors:**

- `GasTankPaymaster_InvalidAddress()`: Invalid token address

#### `setWrappedNativeToken(IERC20 _wrappedNative)`

Updates the wrapped native token address for swapping.

**Parameters:**

- `_wrappedNative`: New wrapped native token address

**Requirements:**

- Only callable by owner
- Address must be valid

**Events:**

- `GasTankPaymaster_WrappedNativeTokenUpdated(address wrappedNative)`

**Errors:**

- `GasTankPaymaster_InvalidAddress()`: Invalid address

### Administrative Methods

#### `pause()`

Pauses the paymaster, preventing new user operation validations.

**Process:**

1. Sets paused state to true
2. Emits pause event

**Requirements:**

- Only callable by verifying signer

**Events:**

- `GasTankPaymaster_Paused()`

**Errors:**

- `GasTankPaymaster_OnlyVerifyingSigner()`: Unauthorized caller

#### `unpause()`

Unpauses the paymaster, allowing normal operations to resume.

**Process:**

1. Sets paused state to false
2. Emits unpause event

**Requirements:**

- Only callable by verifying signer

**Events:**

- `GasTankPaymaster_Unpaused()`

**Errors:**

- `GasTankPaymaster_OnlyVerifyingSigner()`: Unauthorized caller

### Emergency Recovery Methods

#### `emergencyUnsupportedTokenRecovery(IERC20 _token, address _to)`

Recovers accidentally sent or airdropped tokens that aren't part of the core protocol.

**Parameters:**

- `_token`: Token contract to recover
- `_to`: Address to send recovered tokens to

**Process:**

1. Validates addresses
2. Prevents recovery of core protocol tokens
3. Checks token balance
4. Transfers tokens to recipient
5. Emits recovery event

**Requirements:**

- Only callable by owner
- Valid addresses required
- Cannot recover main token or WETH
- Token balance must be non-zero

**Events:**

- `GasTankPaymaster_EmergencyUnsupportedTokenRecovery(address token, address to, uint256 amount)`

**Errors:**

- `GasTankPaymaster_InvalidAddress()`: Invalid address
- `GasTankPaymaster_CannotRecoverMainToken()`: Attempted main token recovery
- `GasTankPaymaster_CannotRecoverWETH()`: Attempted WETH recovery
- `GasTankPaymaster_NoTokensToRecover()`: No tokens to recover

### `withdrawAllNative()`
Withdraws all native tokens and wrapped native tokens from the contract balance to the verifying signer.

**Process:**

1. Checks contract's native token balance (ETH)
2. Checks contract's wrapped native token balance (WETH)
3. Transfers native tokens to verifying signer if balance exists
4. Transfers wrapped native tokens to verifying signer if balance exists
5. Emits withdrawal events for each token type transferred

**Requirements:**

- Only callable by verifying signer
- Automatically handles both native and wrapped native tokens
- No minimum balance required (gracefully handles zero balances)

**Events:**

- `GasTankPaymaster_NativeWithdrawn(address to, uint256 amount)`: When native tokens are withdrawn
- `GasTankPaymaster_WrappedNativeWithdrawn(address to, uint256 amount)`: When wrapped native tokens are withdrawn

**Errors:**

- GasTankPaymaster_OnlyVerifyingSigner(): Unauthorized caller

### View Methods

#### `name()`

Returns the paymaster name.

**Returns:**

- `string`: Paymaster name

#### `version()`

Returns the paymaster version.

**Returns:**

- `string`: Paymaster version

#### `getPaymasterConfig()`

Returns the current paymaster configuration.

**Returns:**

- `GasTankPaymasterConfig`: Current configuration struct

#### `getPaymasterStatus()`

Returns comprehensive paymaster status information.

**Returns:**

- `entryPointBalance`: Current ETH balance in EntryPoint
- `cachedTokenPrice`: Current cached token price
- `priceTimestamp`: Timestamp of last price update
- `verifyingSignerUSDCBalance`: Token balance of verifying signer
- `needsTopUp`: Whether EntryPoint needs top-up
- `isPaused`: Whether paymaster is paused

#### `gasTankBalance()`

Returns the sender's gas tank balance.

**Returns:**

- `uint256`: Token balance of the sender

#### `gasTankBalance(address _wallet)`

Returns the gas tank balance for a specific wallet.

**Parameters:**

- `_wallet`: Wallet address to check

**Returns:**

- `uint256`: Token balance of the specified wallet

#### `isPaused()`

Returns whether the paymaster is currently paused.

**Returns:**

- `bool`: Whether the paymaster is paused

#### `getHash(PackedUserOperation calldata userOp, uint48 validUntil, uint48 validAfter)`

Generates hash for user operation validation.

**Parameters:**

- `userOp`: User operation to hash
- `validUntil`: Operation valid until timestamp
- `validAfter`: Operation valid after timestamp

**Returns:**

- `bytes32`: Hash of the user operation data

#### `parsePaymasterAndData(bytes calldata paymasterAndData)`

Parses paymaster data to extract validation parameters.

**Parameters:**

- `paymasterAndData`: Encoded paymaster data

**Returns:**

- `validUntil`: Operation valid until timestamp
- `validAfter`: Operation valid after timestamp
- `signature`: Signature bytes

### Internal Methods

#### `_topUpEntryPointDeposit(uint256 _cachedPrice)`

Automatically tops up EntryPoint deposit if needed using accumulated tokens.

**Parameters:**

- `_cachedPrice`: Current cached token price for conversion calculations

**Process:**

1. Checks current EntryPoint balance against minimum threshold
2. Returns early if no top-up needed or insufficient tokens
3. Attempts token-to-WETH swap using cached price
4. Unwraps WETH to native currency
5. Deposits native currency to EntryPoint
6. Emits success or failure events

**Events:**

- `GasTankPaymaster_InsufficientBalanceButTopUpRequired()`: When balance is low but tokens insufficient
- `GasTankPaymaster_TopUpExecuted()`: Successful top-up completion
- `GasTankPaymaster_TopUpFailed()`: Top-up attempt failed
- `GasTankPaymaster_TopUpSkippedDueToStalePrice()`: Skipped due to unreliable price

#### `_tryGetFreshPrice(GasTankPaymasterConfig storage gtpConfig)`

Attempts to fetch fresh price data from oracle feeds with comprehensive validation.

**Parameters:**

- `gtpConfig`: Reference to paymaster configuration storage

**Process:**

1. Fetches latest round data from both token and native oracles
2. Validates price values are positive
3. Checks price timestamps for staleness
4. Calculates conversion rate with proper decimal adjustments
5. Returns success status and calculated price

**Returns:**

- `success`: Whether price fetch was successful
- `price`: New price if successful, 0 if failed

**Events:**

- `GasTankPaymaster_InvalidTokenPrice()`: Invalid price from oracle
- `GasTankPaymaster_StaleTokenPrice()`: Price data is stale

## Data Structures

### GasTankPaymasterConfig

```solidity
struct GasTankPaymasterConfig {
    IOracle tokenUsdFeed;           // Chainlink oracle for token/USD price feed
    IOracle nativeUsdFeed;          // Chainlink oracle for native token/USD price feed
    uint128 minEPBalance;           // Minimum ETH balance to maintain in EntryPoint
    uint48 cachedPriceTimestamp;    // Timestamp of the last price update
    uint48 priceMaxAge;             // Maximum age of cached prices before stale
    uint48 postOpCost;              // Gas cost for post-operation processing
    uint256 cachedTokenPrice;       // Cached token price to avoid frequent oracle calls
    uint256 markup;                 // Price markup applied to oracle prices
    uint256 minVSTokenBalance       // Minimum verifying signer balance for EntryPoint top up
}
```

Core configuration struct containing all paymaster operational parameters including oracle feeds, timing constraints, gas costs, and pricing information.

### UniswapHelperConfig

```solidity
struct UniswapHelperConfig {
    uint24 poolFee;                 // Uniswap V3 pool fee tier
    uint256 minSwapAmount;          // Minimum amount required for swap execution
    uint16 slippageTolerance;       // Maximum allowed slippage in basis points
}
```

Configuration for Uniswap V3 integration controlling swap parameters, minimum thresholds, and slippage protection.

## Events

### Configuration Events

#### `GasTankPaymaster_PaymasterConfigUpdated(GasTankPaymasterConfig newConfig)`

Emitted when paymaster configuration is updated.

**Parameters:**

- `newConfig`: The new configuration struct

#### `GasTankPaymaster_SwapRouterUpdated(address swapRouter)`

Emitted when Uniswap swap router address is updated.

**Parameters:**

- `swapRouter`: New swap router address

#### `GasTankPaymaster_SupportedTokenUpdated(address supportedToken)`

Emitted when supported ERC20 token is updated.

**Parameters:**

- `supportedToken`: New supported token address

#### `GasTankPaymaster_WrappedNativeTokenUpdated(address wrappedNative)`

Emitted when wrapped native token address is updated.

**Parameters:**

- `wrappedNative`: New wrapped native token address

### Gas Tank Events

#### `GasTankPaymaster_Deposited(address indexed user, uint256 amount)`

Emitted when tokens are deposited into a gas tank.

**Parameters:**

- `user`: Address of the user whose gas tank received the deposit
- `amount`: Amount of tokens deposited

#### `GasTankPaymaster_Withdrawn(address indexed user, uint256 amount)`

Emitted when tokens are withdrawn from a gas tank.

**Parameters:**

- `user`: Address of the user who withdrew tokens
- `amount`: Amount of tokens withdrawn

#### `GasTankPaymaster_RepaySponsoredTransaction(address indexed from, uint256 amount)`

Emitted when a sponsored transaction is repaid through token transfer.

**Parameters:**

- `from`: Address from which tokens were transferred
- `amount`: Amount of tokens transferred

### Operation Events

#### `GasTankPaymaster_UserOperationSponsored(address indexed sender, address indexed sponsor, uint256 actualGasCost, uint256 actualChargeNative, uint256 preChargeNative, uint256 indexed chainId, bool opReverted)`

Emitted when a user operation is successfully sponsored.

**Parameters:**

- `sender`: Address of the user operation sender
- `sponsor`: Address of the sponsor (verifying signer)
- `actualGasCost`: Actual gas cost of the operation
- `actualChargeNative`: Actual charge in native currency
- `preChargeNative`: Pre-calculated charge amount
- `chainId`: Chain ID where operation occurred
- `opReverted`: Whether the operation was reverted

### Liquidity Management Events

#### `GasTankPaymaster_TopUpExecuted(uint256 tokenUsed, uint256 nativeAmount)`

Emitted when EntryPoint top-up is successfully executed.

**Parameters:**

- `tokenUsed`: Amount of tokens used for the top-up
- `nativeAmount`: Amount of native currency obtained

#### `GasTankPaymaster_TopUpFailed(uint256 tokenUsed, uint256 nativeAmount)`

Emitted when EntryPoint top-up attempt fails.

**Parameters:**

- `tokenUsed`: Amount of tokens that would have been used
- `nativeAmount`: Amount of native currency that would have been obtained

#### `GasTankPaymaster_InsufficientBalanceButTopUpRequired(uint256 currentBalance, uint256 minRequired)`

Emitted when top-up is needed but insufficient balance exists.

**Parameters:**

- `currentBalance`: Current token balance
- `minRequired`: Minimum balance required for top-up

#### `GasTankPaymaster_TopUpSkippedDueToStalePrice()`

Emitted when top-up is skipped due to stale price data.

### Oracle Events

#### `GasTankPaymaster_TokenPriceUpdated(uint256 currentPrice, uint256 previousPrice, uint256 cachedPriceTimestamp)`

Emitted when token price is successfully updated from oracle.

**Parameters:**

- `currentPrice`: New cached price
- `previousPrice`: Previous cached price
- `cachedPriceTimestamp`: Timestamp of the price update

#### `GasTankPaymaster_OracleUpdateFailed()`

Emitted when oracle price update fails.

#### `GasTankPaymaster_InvalidTokenPrice()`

Emitted when oracle returns invalid token price.

#### `GasTankPaymaster_StaleTokenPrice()`

Emitted when oracle price data is stale.

### Administrative Events

#### `GasTankPaymaster_Paused()`

Emitted when the paymaster is paused.

#### `GasTankPaymaster_Unpaused()`

Emitted when the paymaster is unpaused.

#### `GasTankPaymaster_Received(address indexed sender, uint256 value)`

Emitted when native tokens are received by the contract.

**Parameters:**

- `sender`: Address that sent the native tokens
- `value`: Amount of native tokens received

#### `GasTankPaymaster_NativeWithdrawn(address indexed to, uint256 amount)`

Emitted when native tokens are withdrawn from the contract.

**Parameters:**

- `to`: Address that received the native tokens
- `amount`: Amount of native tokens withdrawn

#### `GasTankPaymaster_WrappedNativeWithdrawn(address indexed to, uint256 amount)`

Emitted when wrapped native tokens are withdrawn from the contract.

**Parameters:**

- `to`: Address that received the wrapped native tokens
- `amount`: Amount of wrapped native tokens withdrawn

### Emergency Events

#### `GasTankPaymaster_EmergencyUnsupportedTokenRecovery(address indexed token, address indexed to, uint256 amount)`

Emitted when emergency unsupported token recovery is executed.

**Parameters:**

- `token`: Address of the recovered token
- `to`: Address that received the tokens
- `amount`: Amount of tokens recovered

## Error Conditions

### Access Control Errors

#### `GasTankPaymaster_OnlyVerifyingSigner()`

Thrown when a function restricted to the verifying signer is called by another address.

#### `GasTankPaymaster_IsPaused()`

Thrown when attempting to execute operations while the contract is paused.

### Configuration Errors

#### `GasTankPaymaster_PriceMarkupTooHigh(uint256 markup)`

Thrown when attempting to set price markup above maximum allowed value (2x).

**Parameters:**

- `markup`: The attempted markup value

#### `GasTankPaymaster_PriceMarkupTooLow(uint256 markup)`

Thrown when attempting to set price markup below minimum allowed value (1x).

**Parameters:**

- `markup`: The attempted markup value

#### `GasTankPaymaster_PostOpGasLimitTooLow()`

Thrown when post-operation gas limit is insufficient for required processing.

### Validation Errors

#### `GasTankPaymaster_InvalidPaymasterAndDataSignatureLength()`

Thrown when paymaster signature has invalid length (not 64 or 65 bytes).

#### `GasTankPaymaster_InvalidAddress()`

Thrown when an invalid or zero address is provided as a parameter.

#### `GasTankPaymaster_InvalidAmount()`

Thrown when an invalid amount (typically zero) is provided.

### Balance Errors

#### `GasTankPaymaster_InsufficientBalance(address user, uint256 amount)`

Thrown when a user has insufficient balance for the requested operation.

**Parameters:**

- `user`: Address of the user with insufficient balance
- `amount`: Amount that was requested

#### `GasTankPaymaster_SelfTransfer()`

Thrown when attempting to transfer tokens to the same address (self-transfer).

### Recovery Errors

#### `GasTankPaymaster_NoTokensToRecover(address token)`

Thrown when attempting to recover tokens but no balance exists.

**Parameters:**

- `token`: Address of the token with no balance

#### `GasTankPaymaster_CannotRecoverMainToken()`

Thrown when attempting to recover the main protocol token through emergency recovery.

#### `GasTankPaymaster_CannotRecoverWETH()`

Thrown when attempting to recover WETH through unsupported token recovery.

## Integration Guide

### Basic Setup

1. **Deploy Prerequisites**

   ```solidity
   // Deploy or reference existing contracts
   IEntryPoint entryPoint = IEntryPoint(ENTRY_POINT_ADDRESS);
   ISwapRouter uniswapRouter = ISwapRouter(UNISWAP_ROUTER_ADDRESS);
   IERC20Metadata token = IERC20Metadata(TOKEN_ADDRESS);
   IERC20 wrappedNative = IERC20(WETH_ADDRESS);
   ```

2. **Configure Paymaster Parameters**

   ```solidity
   GasTankPaymaster.GasTankPaymasterConfig memory config = GasTankPaymaster.GasTankPaymasterConfig({
       tokenUsdFeed: IOracle(TOKEN_USD_ORACLE),
       nativeUsdFeed: IOracle(ETH_USD_ORACLE),
       minEPBalance: 1 ether,
       cachedPriceTimestamp: 0,
       priceMaxAge: 1 hours,
       postOpCost: 35000,
       cachedTokenPrice: 0,
       markup: 120000000000000000000000000 // 1.2x markup
       minVSTokenBalance: 10 * 10 ** 6 // e.g. 10 USDC minimum
   });
   
   UniswapHelper.UniswapHelperConfig memory uniConfig = UniswapHelper.UniswapHelperConfig({
       poolFee: 3000,        // 0.3% fee tier
       minSwapAmount: 0.0001 ether,
       slippageTolerance: 50  // 0.5%
   });
   ```

3. **Deploy Paymaster**

   ```solidity
   GasTankPaymaster paymaster = new GasTankPaymaster(
       verifyingSignerAddress,
       entryPoint,
       uniswapRouter,
       token,
       wrappedNative,
       config,
       uniConfig
   );
   ```

4. **Initial Setup**

   ```solidity
   // Stake paymaster with EntryPoint
   paymaster.addStake{value: 1 ether}(86400); // 1 day unstake delay
   
   // Fund EntryPoint deposit
   paymaster.deposit{value: 5 ether}();
   
   // Initialize price cache
   paymaster.updateCachedPrice(true);
   ```

### User Integration

1. **Token Approval and Deposit**

   ```solidity
   // User approves tokens
   IERC20(tokenAddress).approve(address(paymaster), depositAmount);
   
   // User deposits to gas tank
   paymaster.gasTankDeposit(depositAmount);
   ```

2. **Creating Sponsored User Operations**

   ```solidity
   // Create paymaster data with signature
   bytes memory paymasterData = abi.encodePacked(
       validUntil,
       validAfter,
       signature
   );
   
   // Attach to user operation
   userOp.paymasterAndData = abi.encodePacked(
       address(paymaster),
       uint128(validationGasLimit),
       uint128(postOpGasLimit),
       paymasterData
   );
   ```

3. **Signature Generation**

   ```solidity
   bytes32 hash = paymaster.getHash(userOp, validUntil, validAfter);
   bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(hash);
   (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifyingSignerPrivateKey, ethSignedHash);
   bytes memory signature = abi.encodePacked(r, s, v);
   ```

## Dependencies

### Core Dependencies

- **ERC-4337**: Account abstraction standard for user operation handling and paymaster integration
- **OpenZeppelin Contracts**: Standard implementations for access control, token handling, and security patterns
- **Solady**: Optimized utilities for ECDSA signature operations and mathematical functions

### Oracle Dependencies

- **Chainlink Oracles**: Price feed integration for accurate token-to-native conversion rates
- **Custom IOracle Interface**: Flexible oracle interface supporting various price feed implementations

### DeFi Integration

- **Uniswap V3**: Decentralized exchange integration for automated token swapping and liquidity management
- **WETH**: Wrapped Ether integration for native currency handling in DeFi protocols

### Development Dependencies

- **Foundry**: Testing framework and development environment
- **Forge**: Unit testing and integration testing
- **Cast**: Command-line interaction with deployed contracts

## Monitoring and Maintenance

### Key Metrics to Monitor

1. **EntryPoint Balance**: Ensure sufficient liquidity for sponsoring transactions
2. **Oracle Price Staleness**: Monitor for price feed failures or delays
3. **Gas Tank Utilization**: Track user adoption and balance distributions
4. **Swap Success Rate**: Monitor Uniswap integration reliability
5. **Failed Operations**: Track validation failures and their causes

### Maintenance Tasks

1. **Price Cache Updates**: Regular price refreshes during high volatility
2. **Liquidity Management**: Manual top-ups during extreme market conditions
3. **Configuration Updates**: Markup adjustments based on operational costs
4. **Emergency Response**: Rapid response to security incidents or oracle failures

## License

This contract is released under the MIT License. See the LICENSE file for details.

---
