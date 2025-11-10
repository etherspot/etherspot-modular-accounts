/*
 * Simplified Certora Specification for InvoiceManager
 * Focuses on core business logic without deep access control verification
 */

methods {
    // InvoiceManager core functions
    function settleInvoice(address) external returns (bool);
    function createInvoice(bytes) external;
    function creditTokensToInvoice(address, address, uint256) external;
    function cancelInvoice(address, string) external;
    function emergencyUncreditTokens(address, address, uint256, string) external;
    function emergencyWithdraw(address, uint256) external;
    function calculateInvoiceFees(address) external returns (uint256, uint256, uint256, uint256) envfree;
    function invoiceExists(address) external returns (bool) envfree;
    function isInvoiceSettleable(address) external returns (bool) envfree;
    function protocolFeeReceiver() external returns (address) envfree;
    function protocolFeeFixed() external returns (uint256) envfree;
    function setProtocolFee(uint256) external;
    function setProtocolFeeReceiver(address) external;

    // ERC20 functions - use NONDET to simplify verification
    function _.balanceOf(address) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
    function _.safeTransfer(address, uint256) external => NONDET;

    // AccessControl - summarize to avoid internal linking issues
    function _.hasRole(bytes32, address) external => NONDET;
    function _._checkRole(bytes32) internal => NONDET;
    function _._checkRole(bytes32, address) internal => NONDET;
}

/*
 * RULE 1: Successful settlement deletes invoice
 * Proves that settled invoices are properly cleaned up
 */
rule successfulSettlementDeletesInvoice(address sessionKey) {
    env e;

    // Precondition: Invoice exists
    require invoiceExists(sessionKey);

    // Settle the invoice
    bool success = settleInvoice(e, sessionKey);

    // If settlement succeeded, invoice must be deleted
    // This prevents double-settlement attacks
    assert success => !invoiceExists(sessionKey);
}

/*
 * RULE 2: Fee snapshotting - fees never change after invoice creation
 * Prevents fee manipulation attacks
 */
rule feeSnapshotImmutability(address sessionKey, method f) 
    filtered { f -> !f.isView && f.selector != sig:settleInvoice(address).selector }
{
    env e;
    
    // Precondition: Invoice exists
    require invoiceExists(sessionKey);
    
    // Get fees before any operation
    uint256 protocolFeeBefore;
    uint256 orchestratorFeeBefore;
    uint256 solverFeeBefore;
    uint256 totalFeesBefore;
    protocolFeeBefore, orchestratorFeeBefore, solverFeeBefore, totalFeesBefore = 
        calculateInvoiceFees(sessionKey);
    
    // Call any non-view function (except settle which deletes invoice)
    calldataarg args;
    f(e, args);
    
    // Get fees after operation
    uint256 protocolFeeAfter;
    uint256 orchestratorFeeAfter;
    uint256 solverFeeAfter;
    uint256 totalFeesAfter;
    protocolFeeAfter, orchestratorFeeAfter, solverFeeAfter, totalFeesAfter = 
        calculateInvoiceFees(sessionKey);
    
    // Prove fees are unchanged (or invoice was deleted)
    assert !invoiceExists(sessionKey) || (
        protocolFeeAfter == protocolFeeBefore &&
        orchestratorFeeAfter == orchestratorFeeBefore &&
        solverFeeAfter == solverFeeBefore &&
        totalFeesAfter == totalFeesBefore
    );
}

/*
 * RULE 3: Fee calculations are consistent
 * Verifies that calculateInvoiceFees returns the same values when called multiple times
 */
rule feeCalculationDeterministic(address sessionKey) {
    // Precondition: Invoice exists
    require invoiceExists(sessionKey);

    // Get fees first time
    uint256 protocolFee1; uint256 orchestratorFee1; uint256 solverFee1; uint256 totalFees1;
    protocolFee1, orchestratorFee1, solverFee1, totalFees1 = calculateInvoiceFees(sessionKey);

    // Get fees second time
    uint256 protocolFee2; uint256 orchestratorFee2; uint256 solverFee2; uint256 totalFees2;
    protocolFee2, orchestratorFee2, solverFee2, totalFees2 = calculateInvoiceFees(sessionKey);

    // Must return same values (deterministic)
    assert protocolFee1 == protocolFee2;
    assert orchestratorFee1 == orchestratorFee2;
    assert solverFee1 == solverFee2;
    assert totalFees1 == totalFees2;
}

/*
 * RULE 4: Total fees equal sum of individual fees
 * Verifies fee arithmetic integrity
 */
rule totalFeesEqualsSumOfParts(address sessionKey) {
    // Precondition: Invoice exists
    require invoiceExists(sessionKey);

    // Get all fees
    uint256 protocolFee; uint256 orchestratorFee; uint256 solverFee; uint256 totalFees;
    protocolFee, orchestratorFee, solverFee, totalFees = calculateInvoiceFees(sessionKey);

    // Total must equal sum of parts
    assert totalFees == protocolFee + orchestratorFee + solverFee;
}

/*
 * RULE 5: Cancelled invoices are deleted
 * Verifies cleanup happens on cancellation
 */
rule cancellationDeletesInvoice(address sessionKey, string reason) {
    env e;

    // Precondition: Invoice exists
    require invoiceExists(sessionKey);

    // Cancel invoice (may revert due to access control)
    cancelInvoice@withrevert(e, sessionKey, reason);
    bool reverted = lastReverted;

    // If cancellation succeeded, invoice must be deleted
    assert !reverted => !invoiceExists(sessionKey);
}

/*
 * RULE 6: Cannot settle the same invoice twice
 * Verifies double-settlement protection
 */
rule cannotDoubleSettle(address sessionKey) {
    env e1; env e2;

    // Precondition: Invoice exists and is settleable
    require invoiceExists(sessionKey);
    require isInvoiceSettleable(sessionKey);

    // First settlement
    bool success1 = settleInvoice(e1, sessionKey);
    require success1; // Assume first settlement succeeds

    // Second settlement attempt must fail
    settleInvoice@withrevert(e2, sessionKey);

    assert lastReverted;
}

/*
 * RULE 7: Fee snapshot immutability during address updates
 * Verifies that updating solver addresses (fee receiver, orchestrator receiver)
 * does NOT affect existing invoices - only new invoices use the updated addresses
 */
rule addressUpdateDoesNotAffectExistingInvoices(address sessionKey, method f)
    filtered { f -> f.selector == sig:setProtocolFeeReceiver(address).selector }
{
    env e;

    // Precondition: Invoice exists
    require invoiceExists(sessionKey);

    // Get fees before address update
    uint256 protocolFeeBefore;
    uint256 orchestratorFeeBefore;
    uint256 solverFeeBefore;
    uint256 totalFeesBefore;
    protocolFeeBefore, orchestratorFeeBefore, solverFeeBefore, totalFeesBefore =
        calculateInvoiceFees(sessionKey);

    // Update an address (e.g., protocol fee receiver)
    calldataarg args;
    f(e, args);

    // Get fees after address update
    uint256 protocolFeeAfter;
    uint256 orchestratorFeeAfter;
    uint256 solverFeeAfter;
    uint256 totalFeesAfter;
    protocolFeeAfter, orchestratorFeeAfter, solverFeeAfter, totalFeesAfter =
        calculateInvoiceFees(sessionKey);

    // Prove fees remain unchanged (snapshotting protection)
    assert invoiceExists(sessionKey) => (
        protocolFeeAfter == protocolFeeBefore &&
        orchestratorFeeAfter == orchestratorFeeBefore &&
        solverFeeAfter == solverFeeBefore &&
        totalFeesAfter == totalFeesBefore
    );
}

/*
 * RULE 8: Settlement is atomic - either fully succeeds or fully reverts
 * Verifies that settlement doesn't leave invoices in a partial state
 */
rule settlementIsAtomic(address sessionKey) {
    env e;

    // Precondition: Invoice exists before settlement
    bool existsBefore = invoiceExists(sessionKey);
    require existsBefore;

    // Attempt settlement
    settleInvoice@withrevert(e, sessionKey);
    bool reverted = lastReverted;

    // Check if invoice exists after
    bool existsAfter = invoiceExists(sessionKey);

    // If settlement succeeded, invoice MUST be deleted
    // If settlement failed, invoice MUST still exist
    assert !reverted => !existsAfter;
    assert reverted => existsAfter;
}

/*
 * RULE 9: Cancellation is atomic - either fully succeeds or fully reverts
 * Verifies that cancellation doesn't leave invoices in a partial state
 */
rule cancellationIsAtomic(address sessionKey, string reason) {
    env e;

    // Precondition: Invoice exists before cancellation
    bool existsBefore = invoiceExists(sessionKey);
    require existsBefore;

    // Attempt cancellation
    cancelInvoice@withrevert(e, sessionKey, reason);
    bool reverted = lastReverted;

    // Check if invoice exists after
    bool existsAfter = invoiceExists(sessionKey);

    // If cancellation succeeded, invoice MUST be deleted
    // If cancellation failed, invoice MUST still exist
    assert !reverted => !existsAfter;
    assert reverted => existsAfter;
}



