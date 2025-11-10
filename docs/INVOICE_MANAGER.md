# InvoiceManager, SolverManager, and TokenManager

The InvoiceManager, SolverManager, and TokenManager contracts work together to support secure, deterministic, and fee-aware invoice settlement between smart wallets and solvers.
They form the backbone of the Credible Network’s modular execution and fee distribution system.

## Overview

These contracts manage the invoice lifecycle, solver onboarding, and token whitelist enforcement for ERC-7579-compatible smart accounts.
They ensure predictable, auditable, and transparent fee calculations, enabling non-custodial settlements where solvers are paid atomically after completing executions.

## Key Features

- Invoice Lifecycle Management — creation, crediting, settlement, and cancellation
- Three-Tier Fee System — protocol, orchestrator, and solver fees (with FIXED or PERCENTAGE logic)
- Per-Solver Fee Configuration — isolated fee structures per solver
- Snapshot Logic — fees frozen at creation, ensuring deterministic settlement
- Multi-Token Invoices — support for multiple ERC-20 tokens (fees deducted from the first token)
- Secure Access Control — role-based permissions for each managerial operation
- Formal Verification-Friendly — deterministic flow for Certora and invariant proofs

## Architecture

The system is composed of three cooperating contracts:

| Contract	| Responsibility	| Core Role |
| --------- | --------------- | --------- |
| InvoiceManager	| Handles invoices, fee calculations, and settlements	| Operational core |
| SolverManager	| Manages solver registration and per-solver fee settings	| Fee governance |
| TokenManager	| Maintains whitelist of allowed ERC-20 tokens	| Security layer |

## Core Concepts

### Invoices

Invoices represent a single solver execution instance — a settlement request between a smart wallet and a solver.
Each invoice holds token data, a bid reference, and frozen fee configuration at creation time.

### Solvers

Solvers are service providers that execute intents or transactions for users.
Each solver can define:
- their own fee type and value (FIXED or PERCENTAGE),
- their orchestrator’s fee (to aggregators or PillarX),
- their fee/repayment addresses.

### Tokens

Only whitelisted tokens can be used for invoices or settlements.
The TokenManager contract enforces this globally.

## Contract: InvoiceManager

### Overview

The InvoiceManager is the system’s main settlement contract.
It creates invoices, receives token credits, calculates multi-tier fees, and distributes funds atomically during settlement.

### Three-Tier Fee Calculation

Fees are computed sequentially, each deducting from the remainder of the previous step.

| Tier	| Type	| Configurable?	| Example |
| ----- | ----- | ------------ | ------- |
| Protocol Fee | Fixed (cents)	| Global	| $0.05 per invoice |
| Orchestrator Fee | Fixed or Percentage |	Per Solver |	5% |
| Solver Fee | Fixed or Percentage |	Per Solver |	10% |

Example (100 USDC, 6 decimals)

1. **Protocol Fee:** (5 * 10^6) / 100 = 50,000 units = $0.05
Remaining = 99,950,000

2. **Orchestrator Fee:** (99,950,000 * 500) / 10,000 = 4,997,500 units = $4.9975
Remaining = 94,952,500

3. **Solver Fee:** (94,952,500 * 1,000) / 10,000 = 9,495,250 units = $9.49525
Remaining = 85,457,250

Solver receives $85.46; total fees $14.54.

### Structs

Invoice
```solidity
struct Invoice {
    InvoiceData data;
    uint256 createdAt;
    FeeStructure fees;
}
```

InvoiceData
```solidity
struct InvoiceData {
    address smartWallet;
    address sessionKey;
    address solver;
    bytes32 bidHash;
    uint256 chainId;
}
```

FeeStructure
```solidity
struct FeeStructure {
    uint256 protocolFee;
    address protocolFeeReceiver;
    uint256 orchestratorFee;
    address orchestratorFeeReceiver;
    uint256 solverFee;
    address solverFeeReceiver;
    address solverExecutionAddress;
}
```

TokenData
```solidity
struct TokenData {
    address token;
    uint256 amount;
    uint256 creditedAmount;
}
```

### Events

- `InvoiceCreated(address indexed sessionKey, bytes32 bidHash, address solver, uint256 totalTokens, uint256 totalFees)`
- `TokensCreditedToInvoice(address indexed sessionKey, address indexed token, uint256 amount)`
- `InvoiceSettled(address indexed sessionKey, bytes32 bidHash, address solver, uint256 solverRepayment, uint256 totalFees)`
- `InvoiceCancelled(address indexed sessionKey, bytes32 bidHash)`
- `ProtocolFeeUpdated(uint256 newProtocolFee)`
- `ProtocolFeeReceiverUpdated(address newReceiver)`

### Errors

- `IM_InvalidToken()` — Token not whitelisted
- `IM_InvoiceNotFound(address sessionKey)`
- `IM_InvoiceNotFullyCredited(address sessionKey, address token, uint256 required, uint256 credited)`
- `IM_InvalidSettlementCaller()`
- `IM_InvalidFeeCombination()`

### Core Methods

`createInvoice(bytes calldata createData)`:
Creates a new invoice with token data and frozen fee configuration.

Requirements:
- All tokens must be whitelisted
- Unique sessionKey
- Non-zero token amounts

`creditTokensToInvoice(address sessionKey, address token, uint256 amount)`:
Credits tokens to an invoice from a payer wallet.

`settleInvoice(address sessionKey)`:
Settles an invoice — calculates fees, distributes tokens, and deletes invoice.

Requirements:
- Must have `SETTLER_ROLE`
- All tokens fully credited

`cancelInvoice(address sessionKey)`:
Cancels an uncredited invoice.

`setProtocolFee(uint256 newFee)`
Sets the fixed global protocol fee in cents.

`setProtocolFeeReceiver(address receiver)`
Sets global protocol fee receiver.

## Contract: SolverManager

### Overview

The SolverManager is responsible for solver lifecycle and fee configuration.
Each solver defines where fees are sent, their type (FIXED or PERCENTAGE), and value.

### Structs

Solver
```solidity
struct Solver {
    address executionAddress;
    address feeAddress;
    address orchestratorReceiver;
    string name;
    bool isActive;
    bool pendingOffboard;
    uint256 successfulSettlements;
    FeeType orchestratorFeeType;
    uint256 orchestratorFeeValue;
    FeeType solverFeeType;
    uint256 solverFeeValue;
}
```

### Enums
```solidity
enum FeeType {
    FIXED,
    PERCENTAGE
}
```

### Constants
```solidity
uint256 public constant MAX_FEE_PERCENTAGE = 10000; // 100%
uint256 public constant MAX_FEE_FIXED = 10000; // $100 in cents
```

### Events

- `SolverOnboarded(address indexed solver, string name, FeeType orchestratorFeeType, uint256 orchestratorFeeValue, FeeType solverFeeType, uint256 solverFeeValue)`
- `SolverFeeUpdated(address indexed solver, FeeType newType, uint256 oldValue, uint256 newValue)`
- `OrchestratorFeeUpdated(address indexed solver, FeeType newType, uint256 oldValue, uint256 newValue)`
- `SolverFeeAddressUpdated(address indexed solver, address newFeeAddress)`
- `OrchestratorReceiverUpdated(address indexed solver, address newReceiver)`
- `SolverOffboarded(address indexed solver)`

### Errors

- `SM_SolverAlreadyExists(address solver)`
- `SM_SolverDoesNotExist(address solver)`
- `SM_InvalidFeeValue()`
- `SM_InvalidFeeTypeCombination()`

### Core Methods

`onboardSolver(...)`:
Registers a new solver with fee configuration and metadata.

Parameters:
- `_solverAddress` — Primary solver address
- `_executionAddress` — Execution contract (repayment target)
- `_feeAddress` — Where solver fees are sent
- `_orchestratorReceiver` — Fee receiver for orchestrator (e.g., PillarX)
- `_name` — Human-readable solver name
- `_orchestratorFeeType, _orchestratorFeeValue` — Fee parameters
- `_solverFeeType, _solverFeeValue` — Fee parameters

Access Control:
`onlyRole(SOLVER_MANAGER_ROLE)`

`updateSolverFee(address solver, FeeType feeType, uint256 feeValue)`:
Updates the solver’s fee structure.
Requires `FEE_MANAGER_ROLE`.

`updateOrchestratorFee(address solver, FeeType feeType, uint256 feeValue)`:
Updates the orchestrator’s fee structure for a given solver.
Requires `FEE_MANAGER_ROLE`.

`updateSolverFeeAddress(address solver, address newFeeAddress)`:
Changes where solver fees are sent.
Requires `SOLVER_MANAGER_ROLE`.

`updateOrchestratorReceiver(address solver, address newReceiver)`:
Updates orchestrator fee receiver.
Requires `SOLVER_MANAGER_ROLE`.

## Contract: TokenManager

### Overview

The TokenManager enforces ERC-20 token whitelisting across the ecosystem.
It ensures only approved tokens can be used in invoices and settlements.

### Events
- `TokenWhitelisted(address indexed token, address indexed addedBy)`
- `TokenRemoved(address indexed token, address indexed removedBy)`

### Errors
- `TM_TokenAlreadyWhitelisted(address token)`
- `TM_TokenNotWhitelisted(address token)`
- `TM_EmptyTokenData()`

### Core Methods

`addTokensToWhitelist(address[] calldata tokens)`:
Adds multiple tokens to the whitelist.
Requires `DEFAULT_ADMIN_ROLE`.

`removeTokensFromWhitelist(address[] calldata tokens)`:
Removes multiple tokens from the whitelist.
Requires `DEFAULT_ADMIN_ROLE`.

`isTokenWhitelisted(address token)`:
Checks if a token is approved for use.

### Access Control Roles

| Role	| Description |
| ----- | ----------- |
| `DEFAULT_ADMIN_ROLE` |	Full control over the protocol |
| `FEE_MANAGER_ROLE` |	Configure protocol and per-solver fees |
| `SOLVER_MANAGER_ROLE` |	Manage solver lifecycle |
| `SETTLER_ROLE` |	Execute settlements |

### Security Considerations

**Fee Sanity**
- Hard-capped fees prevent malicious or misconfigured values
- FIXED fees use cents, converted to token decimals at runtime
**Snapshot Logic**
- Fees are frozen at invoice creation
- Prevents retroactive fee manipulation
**Role Separation**
- Distinct roles isolate responsibilities
- Reduces risk of privilege escalation
**Multi-Token Safety**
- Fees always deducted from the first token in invoice
- Prevents cross-token miscalculations
**Formal Verification**
- Invariants ensure:
  - Invoices cannot be settled twice
  - Cancelled invoices cannot be reactivated
  - Fee math matches expected totals
  - Token balances remain solvent

## Summary
- InvoiceManager: Handles full invoice lifecycle and fee logic
- SolverManager: Configures solvers and their fees
- TokenManager: Enforces token whitelist
- Formal Verification-Ready: Predictable, auditable, role-secured architecture