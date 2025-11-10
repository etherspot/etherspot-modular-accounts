// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ISolverManager} from "../../../src/interfaces/ISolverManager.sol";
import {InvoiceManager} from "../../../src/invoice_manager/InvoiceManager.sol";
import {SolverManager} from "../../../src/invoice_manager/SolverManager.sol";
import {TokenManager} from "../../../src/invoice_manager/TokenManager.sol";
import {InvoiceManagerTestUtils} from "../utils/InvoiceManagerTestUtils.sol";
import {TokenData} from "../../../src/common/Structs.sol";

contract InvoiceManager_Concrete_Test is InvoiceManagerTestUtils {
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
        uint256 totalTokens,
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
    event SolverOnboarded(
        address indexed solver,
        string name,
        ISolverManager.FeeType orchestratorFeeType,
        uint256 orchestratorFeeValue,
        ISolverManager.FeeType solverFeeType,
        uint256 solverFeeValue
    );
    event SolverOffboarded(address indexed solver);
    event SolverFeeUpdated(address indexed solver, ISolverManager.FeeType feeType, uint256 oldFee, uint256 newFee);
    event SolverFeeAddressUpdated(address indexed solver, address indexed oldFeeAddress, address indexed newFeeAddress);
    event OrchestratorReceiverUpdated(
        address indexed solver, address indexed oldOrchestratorReceiver, address indexed newOrchestratorReceiver
    );
    event FeeReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);
    event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
    event ProtocolFeeReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);
    event TokenWhitelisted(address indexed token, address indexed addedBy);
    event TokenRemovedFromWhitelist(address indexed token, address indexed removedBy);
    event TokensCreditedToInvoice(
        address indexed sessionKey, address indexed token, uint256 expected, uint256 received, uint256 totalCredited
    );

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testSetup();
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_success() public {
        vm.startPrank(deployer.pub);

        InvoiceManager testManager =
            new InvoiceManager(deployer.pub, credibleAccount.pub, feeReceiver.pub, feeManager.pub);

        // Add tokens to whitelist
        testManager.addTokensToWhitelist(whitelistedTokenAddresses);

        // Verify roles are granted correctly
        assertTrue(testManager.hasRole(testManager.DEFAULT_ADMIN_ROLE(), deployer.pub));
        assertTrue(testManager.hasRole(testManager.CREDIBLE_ACCOUNT_ROLE(), credibleAccount.pub));
        assertTrue(testManager.hasRole(testManager.SETTLER_ROLE(), deployer.pub));
        assertTrue(testManager.hasRole(testManager.FEE_MANAGER_ROLE(), feeManager.pub));
        assertTrue(testManager.hasRole(testManager.SOLVER_MANAGER_ROLE(), deployer.pub));

        // Verify fee receiver is set
        assertEq(testManager.protocolFeeReceiver(), feeReceiver.pub);

        // Verify tokens are whitelisted
        assertTrue(testManager.isTokenWhitelisted(address(testUSDC)));
        assertTrue(testManager.isTokenWhitelisted(address(testUSDT)));
        assertTrue(testManager.isTokenWhitelisted(address(testDAI)));
        assertTrue(testManager.isTokenWhitelisted(address(testBUSD)));

        vm.stopPrank();
    }

    function test_constructor_revertIf_invalidOwner() public {
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        new InvoiceManager(
            address(0), // Invalid owner
            credibleAccount.pub,
            feeReceiver.pub,
            feeManager.pub
        );
    }

    function test_constructor_revertIf_invalidCredibleAccount() public {
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        new InvoiceManager(
            deployer.pub,
            address(0), // Invalid credible account
            feeReceiver.pub,
            feeManager.pub
        );
    }

    function test_constructor_revertIf_invalidFeeReceiver() public {
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        new InvoiceManager(
            deployer.pub,
            credibleAccount.pub,
            address(0), // Invalid fee receiver
            feeManager.pub
        );
    }

    function test_constructor_revertIf_invalidFeeManager() public {
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        new InvoiceManager(
            deployer.pub,
            credibleAccount.pub,
            feeReceiver.pub,
            address(0) // Invalid fee manager
        );
    }

    /*//////////////////////////////////////////////////////////////
                        CREATE INVOICE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_createInvoice_success() public withOnboardedSolvers {
        vm.startPrank(credibleAccount.pub);

        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        // Calculate expected fees
        (
            uint256 expectedProtocolFee,
            uint256 expectedOrchestratorFee,
            uint256 expectedSolverFee,
            uint256 expectedTotalFees
        ) = _calculateExpectedTotalFees(solver.pub, address(testUSDC), DEFAULT_USDC_AMOUNT);

        // Expect event with exact total fees
        vm.expectEmit(true, true, true, true);
        emit InvoiceCreated(sessionKey.pub, DEFAULT_BID_HASH, solver.pub, defaultTokenData.length, expectedTotalFees);

        invoiceManager.createInvoice(createInvoiceData);

        // Verify invoice was created
        assertTrue(invoiceManager.invoiceExists(sessionKey.pub));
        assertTrue(invoiceManager.bidHashExists(DEFAULT_BID_HASH));

        // Verify invoice data
        (InvoiceManager.Invoice memory invoice, InvoiceManager.InvoiceTokenData[] memory tokenData) =
            invoiceManager.getInvoice(sessionKey.pub);

        assertEq(invoice.data.smartWallet, address(scw));
        assertEq(invoice.data.sessionKey, sessionKey.pub);
        assertEq(invoice.data.solver, solver.pub);
        assertEq(invoice.data.bidHash, DEFAULT_BID_HASH);
        assertEq(invoice.fees.protocolFee, expectedProtocolFee, "Protocol fee should match calculated value");
        assertEq(
            invoice.fees.orchestratorFee, expectedOrchestratorFee, "Orchestrator fee should match calculated value"
        );
        assertEq(invoice.fees.solverFee, expectedSolverFee, "Solver fee should match calculated value");
        assertGt(invoice.createdAt, 0);

        // Verify token data
        assertEq(tokenData.length, defaultTokenData.length);
        for (uint256 i; i < tokenData.length; ++i) {
            assertEq(tokenData[i].token, defaultTokenData[i].token);
            assertEq(tokenData[i].amount, defaultTokenData[i].amount);
            assertEq(tokenData[i].creditedAmount, 0);
        }

        vm.stopPrank();
    }

    function test_createInvoice_success_multiToken_usesFirstTokenForFees() public withOnboardedSolvers {
        address[] memory tokens = new address[](2);
        tokens[0] = address(testUSDC);
        tokens[1] = address(testDAI);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = DEFAULT_USDC_AMOUNT; // fee base token
        amounts[1] = DEFAULT_DAI_AMOUNT; // pass-through token
        TokenData[] memory multiTokenData = _createTokenData(tokens, amounts);
        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, block.chainid, multiTokenData);
        vm.startPrank(credibleAccount.pub);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
        // Check invoice exists and base fees are denominated in USDC (token[0])
        (InvoiceManager.Invoice memory invoice, InvoiceManager.InvoiceTokenData[] memory tokenData) =
            invoiceManager.getInvoice(sessionKey.pub);
        assertEq(tokenData.length, 2, "Should have 2 tokens stored");
        (uint256 protocolFee, uint256 orchestratorFee, uint256 solverFee, uint256 totalFees) =
            invoiceManager.calculateInvoiceFees(sessionKey.pub);
        // Calculate expected fees using first token (USDC)
        (
            uint256 expectedProtocolFee,
            uint256 expectedOrchestratorFee,
            uint256 expectedSolverFee,
            uint256 expectedTotalFees
        ) = _calculateExpectedTotalFees(solver.pub, address(testUSDC), DEFAULT_USDC_AMOUNT);

        assertEq(protocolFee, expectedProtocolFee, "Protocol fee must match base token fees");
        assertEq(orchestratorFee, expectedOrchestratorFee, "Orchestrator fee must match base token fees");
        assertEq(solverFee, expectedSolverFee, "Solver fee must match base token fees");
        assertEq(totalFees, expectedTotalFees, "Total fees must match base token fees");
    }

    function test_createInvoice_revertIf_notCredibleAccountRole() public withOnboardedSolvers {
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        vm.prank(alice.pub); // Not credible account
        vm.expectRevert();
        invoiceManager.createInvoice(createInvoiceData);
    }

    function test_createInvoice_revertIf_nonWhitelistedToken() public withOnboardedSolvers {
        TokenData[] memory invalidTokenData = _createSingleTokenData(address(nonWhitelistedToken), 1000e18);

        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, invalidTokenData);
        vm.startPrank(credibleAccount.pub);
        _toRevert(TokenManager.TM_TokenNotWhitelisted.selector, abi.encode(address(nonWhitelistedToken)));
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_createInvoice_revertIf_solverNotActive() public withSetupInvoiceManager {
        // Don't onboard solvers, so solver is not active
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        vm.startPrank(credibleAccount.pub);
        _toRevert(SolverManager.SM_SolverInactive.selector, hex"");
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_createInvoice_revertIf_emptyTokenData() public withOnboardedSolvers {
        TokenData[] memory emptyTokenData = new TokenData[](0);

        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, emptyTokenData);

        vm.startPrank(credibleAccount.pub);
        _toRevert(TokenManager.TM_EmptyTokenData.selector, hex"");
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_createInvoice_revertIf_zeroTokenAmount() public withOnboardedSolvers {
        TokenData[] memory zeroAmountTokenData = _createSingleTokenData(
            address(testUSDC),
            0 // Zero amount
        );

        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, zeroAmountTokenData);

        vm.startPrank(credibleAccount.pub);
        _toRevert(InvoiceManager.IM_InvalidTokenAmount.selector, hex"");
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_createInvoice_revertIf_insufficientAmountForFees() public withOnboardedSolvers {
        // Use a very small amount where fees would consume everything
        // With protocol fee = 5 cents (50000 in 6 decimals), even 50000 would be insufficient
        // since there are also orchestrator (0.5%) and solver (0.2%) fees on top
        uint256 insufficientAmount = 50000; // 0.05 USDC - exactly the protocol fee, no room for other fees

        TokenData[] memory insufficientTokenData = _createSingleTokenData(address(testUSDC), insufficientAmount);

        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, insufficientTokenData);

        vm.startPrank(credibleAccount.pub);
        // Should revert because amount <= totalFees
        vm.expectRevert(
            abi.encodeWithSelector(
                InvoiceManager.IM_InsufficientAmountForFees.selector, insufficientAmount, insufficientAmount
            )
        );
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_createInvoice_revertIf_invoiceAlreadyExists() public withSampleInvoice {
        // Try to create invoice with same session key
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, SECOND_BID_HASH);

        vm.startPrank(credibleAccount.pub);
        _toRevert(InvoiceManager.IM_InvoiceAlreadyExists.selector, hex"");
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_createInvoice_revertIf_bidHashAlreadyExists() public withSampleInvoice {
        // Try to create invoice with same bid hash
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey2.pub, solver.pub, DEFAULT_BID_HASH);

        vm.startPrank(credibleAccount.pub);
        _toRevert(InvoiceManager.IM_BidHashAlreadyExists.selector, hex"");
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_createInvoice_revertIf_invalidChainId() public withOnboardedSolvers {
        uint256 wrongChainId = block.chainid + 1;

        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, wrongChainId, defaultTokenData);

        vm.startPrank(credibleAccount.pub);
        vm.expectRevert(abi.encodeWithSelector(InvoiceManager.IM_InvalidChainId.selector, wrongChainId));
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_createInvoice_success_chainIdZero() public withOnboardedSolvers {
        // chainId 0 means "any chain" and should succeed
        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, 0, defaultTokenData);

        vm.startPrank(credibleAccount.pub);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        assertTrue(invoiceManager.invoiceExists(sessionKey.pub), "Invoice should be created with chainId 0");
    }

    function test_createInvoice_revertIf_zeroSmartWallet() public withOnboardedSolvers {
        bytes memory createInvoiceData =
            abi.encode(address(0), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, defaultTokenData);

        vm.startPrank(credibleAccount.pub);
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_createInvoice_revertIf_zeroSessionKey() public withOnboardedSolvers {
        bytes memory createInvoiceData =
            abi.encode(address(scw), address(0), solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, defaultTokenData);

        vm.startPrank(credibleAccount.pub);
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_createInvoice_revertIf_zeroSolver() public withOnboardedSolvers {
        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, address(0), DEFAULT_BID_HASH, TEST_CHAIN_ID, defaultTokenData);

        vm.startPrank(credibleAccount.pub);
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_createInvoice_success_solverInvariantMaintained() public withOnboardedSolvers {
        // Verify that normal invoice creation maintains the solver invariant
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        vm.prank(credibleAccount.pub);
        invoiceManager.createInvoice(createInvoiceData);

        // Verify invoice was created and solver invariant is maintained
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(invoice.fees.solverExecutionAddress, solver.pub, "Solver execution address should match solver key");

        // Verify solver data is consistent
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);
        assertEq(solverData.executionAddress, solver.pub, "Solver execution address invariant maintained");
    }

    /*//////////////////////////////////////////////////////////////
                        SETTLE INVOICE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_settleInvoice_success_asSettler_deletesInvoice() public withSampleInvoice {
        address sessionKey = sessionKey.pub;

        // Get the actual bid hash from the invoice
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKey);
        bytes32 actualBidHash = invoice.data.bidHash;

        _settleInvoiceAsSettler(sessionKey);

        // Verify invoice is deleted
        assertFalse(invoiceManager.invoiceExists(sessionKey));
        assertFalse(invoiceManager.bidHashExists(actualBidHash)); // Use actual bid hash
    }

    function test_settleInvoice_success_asSettler_emitsEvent() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        // Mint tokens to contract
        _mintTokensToInvoiceManager();
        // Credit tokens before settlement
        _creditTokensToInvoice(sessionKey);

        // Get invoice to calculate expected values
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKey);
        uint256 totalFees = invoice.fees.protocolFee + invoice.fees.orchestratorFee + invoice.fees.solverFee;
        uint256 expectedRepayment = DEFAULT_USDC_AMOUNT - totalFees;

        vm.expectEmit(true, true, true, true);
        emit InvoiceSettled(sessionKey, DEFAULT_BID_HASH, solver.pub, expectedRepayment, totalFees);
        vm.prank(settler.pub);
        invoiceManager.settleInvoice(sessionKey);
    }

    function test_settleInvoice_success_asSettler_transfersTokens() public withSampleInvoice {
        address sessionKey = sessionKey.pub;

        uint256 initialProtocolReceiverUSDC = testUSDC.balanceOf(protocolFeeReceiver.pub);
        uint256 initialOrchestratorReceiverUSDC = testUSDC.balanceOf(orchestratorFeeReceiver.pub);
        uint256 initialSolverUSDC = testUSDC.balanceOf(solver.pub);

        // Get the snapshotted fees from the invoice
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKey);
        uint256 totalFees = invoice.fees.protocolFee + invoice.fees.orchestratorFee + invoice.fees.solverFee;
        uint256 expectedSolverRepayment = DEFAULT_USDC_AMOUNT - totalFees;

        _settleInvoiceAsSettler(sessionKey);

        // Verify transfers - separate receivers for protocol and orchestrator
        assertEq(
            testUSDC.balanceOf(protocolFeeReceiver.pub),
            initialProtocolReceiverUSDC + invoice.fees.protocolFee,
            "Protocol fee"
        );
        assertEq(
            testUSDC.balanceOf(orchestratorFeeReceiver.pub),
            initialOrchestratorReceiverUSDC + invoice.fees.orchestratorFee,
            "Orchestrator fee"
        );
        // Solver gets their fee + repayment (combined since addresses are same)
        assertEq(testUSDC.balanceOf(solver.pub), initialSolverUSDC + expectedSolverRepayment + invoice.fees.solverFee);
    }

    function test_settleInvoice_success_asSmartWallet() public withSampleInvoice {
        address sessionKey = sessionKey.pub;

        // Get initial balances
        uint256 initialProtocolReceiverUSDC = testUSDC.balanceOf(protocolFeeReceiver.pub);
        uint256 initialOrchestratorReceiverUSDC = testUSDC.balanceOf(orchestratorFeeReceiver.pub);
        uint256 initialSolverUSDC = testUSDC.balanceOf(solver.pub);

        // Mint tokens to contract
        _mintTokensToInvoiceManager();
        // Credit tokens before settlement
        _creditTokensToInvoice(sessionKey);

        // Get invoice to calculate expected values
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKey);
        uint256 totalFees = invoice.fees.protocolFee + invoice.fees.orchestratorFee + invoice.fees.solverFee;
        uint256 expectedRepayment = DEFAULT_USDC_AMOUNT - totalFees;

        vm.expectEmit(true, true, true, true);
        emit InvoiceSettled(sessionKey, DEFAULT_BID_HASH, solver.pub, expectedRepayment, totalFees);

        // Use the actual smart wallet address from the invoice (not settler role)
        vm.prank(address(scw));
        invoiceManager.settleInvoice(sessionKey);

        // Verify invoice is deleted
        assertFalse(invoiceManager.invoiceExists(sessionKey));
        assertFalse(invoiceManager.bidHashExists(DEFAULT_BID_HASH));

        // Verify exact fee amounts were transferred
        assertEq(
            testUSDC.balanceOf(protocolFeeReceiver.pub) - initialProtocolReceiverUSDC,
            invoice.fees.protocolFee,
            "Protocol fee should match"
        );
        assertEq(
            testUSDC.balanceOf(orchestratorFeeReceiver.pub) - initialOrchestratorReceiverUSDC,
            invoice.fees.orchestratorFee,
            "Orchestrator fee should match"
        );
        assertEq(
            testUSDC.balanceOf(solver.pub) - initialSolverUSDC,
            expectedRepayment + invoice.fees.solverFee,
            "Solver should receive repayment + fee"
        );
    }

    function test_settleInvoice_success_withHighFee() public withSetupInvoiceManager {
        _onboardDefaultSolvers();

        // Create invoice with solver2 (uses fixed fees: 10 cents orch + 5 cents solver)
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver2.pub, DEFAULT_BID_HASH);

        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Mint tokens to invoice manager
        _mintTokensToInvoiceManager();

        // Get actual fees from invoice
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKey.pub);
        uint256 totalFees = invoice.fees.protocolFee + invoice.fees.orchestratorFee + invoice.fees.solverFee;
        uint256 expectedSolverRepayment = DEFAULT_USDC_AMOUNT - totalFees;

        uint256 initialSolverUSDC = testUSDC.balanceOf(solver2.pub);

        _settleInvoiceAsSettler(sessionKey.pub);

        // Verify solver2 received repayment + their fee
        assertEq(testUSDC.balanceOf(solver2.pub), initialSolverUSDC + expectedSolverRepayment + invoice.fees.solverFee);
    }

    function test_settleInvoice_success_withSingleToken() public withOnboardedSolvers {
        // Create invoice with only one token
        TokenData[] memory singleTokenData = _createSingleTokenData(address(testUSDC), DEFAULT_USDC_AMOUNT);

        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, singleTokenData);

        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        _mintTokensToInvoiceManager();

        // Get actual fees from invoice
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKey.pub);
        uint256 totalFees = invoice.fees.protocolFee + invoice.fees.orchestratorFee + invoice.fees.solverFee;
        uint256 expectedSolverRepayment = DEFAULT_USDC_AMOUNT - totalFees;

        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);

        // Credit tokens before settlement
        _creditTokensToInvoice(sessionKey.pub);
        vm.expectEmit(true, true, true, true);
        emit InvoiceSettled(sessionKey.pub, DEFAULT_BID_HASH, solver.pub, expectedSolverRepayment, totalFees);
        vm.prank(settler.pub);
        invoiceManager.settleInvoice(sessionKey.pub);

        assertEq(
            testUSDC.balanceOf(solver.pub), initialSolverBalance + expectedSolverRepayment + invoice.fees.solverFee
        );
    }

    function test_settleInvoice_revertIf_invoiceDoesNotExist() public withSetupInvoiceManager {
        address nonExistentSessionKey = makeAddr("nonExistentSessionKey");

        vm.prank(settler.pub);
        _toRevert(InvoiceManager.IM_InvoiceNotFound.selector, hex"");
        invoiceManager.settleInvoice(nonExistentSessionKey);
    }

    function test_settleInvoice_revertIf_notAuthorized() public withSampleInvoice {
        address sessionKey = sessionKey.pub;

        // Try to settle as unauthorized user
        vm.prank(alice.pub);
        vm.expectRevert();
        invoiceManager.settleInvoice(sessionKey);
    }

    function test_settleInvoice_revertIf_notSmartWalletOwner() public withSampleInvoice {
        address sessionKey = sessionKey.pub;

        // Try to settle as wrong smart wallet
        vm.prank(address(scw2)); // Wrong wallet
        vm.expectRevert();
        invoiceManager.settleInvoice(sessionKey);
    }

    function test_settleInvoice_revertIf_insufficientTokenBalance_specificToken() public withOnboardedSolvers {
        // Create invoice
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        invoiceManager.createInvoice(createInvoiceData);

        invoiceManager.creditTokensToInvoice(sessionKey.pub, address(testUSDC), DEFAULT_USDC_AMOUNT);
        vm.stopPrank();

        // Mint tokens but 1 wei short
        testUSDC.mint(address(invoiceManager), DEFAULT_USDC_AMOUNT - 1);

        // Attempt to settle should revert when trying to transfer USDC
        vm.prank(settler.pub);
        vm.expectRevert(); // ERC20 transfer will revert with insufficient balance
        invoiceManager.settleInvoice(sessionKey.pub);
    }

    function test_settleInvoice_success_multipleInvoicesSameSolver() public withOnboardedSolvers {
        // Create multiple invoices for the same solver
        address[] memory sessionKeys = new address[](3);

        vm.startPrank(credibleAccount.pub);

        for (uint256 i; i < 3; ++i) {
            bytes32 bidHash = keccak256(abi.encodePacked("bid_hash_", i));
            address sessionKey = address(uint160(uint256(keccak256(abi.encodePacked("session_key_", i)))));

            bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey, solver.pub, bidHash);

            invoiceManager.createInvoice(createInvoiceData);
            sessionKeys[i] = sessionKey;
        }

        vm.stopPrank();

        _mintTokensToInvoiceManager();

        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);

        // Get fees from first invoice (all should be same)
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKeys[0]);
        uint256 totalFees = invoice.fees.protocolFee + invoice.fees.orchestratorFee + invoice.fees.solverFee;
        uint256 expectedSolverAmountPerInvoice = DEFAULT_USDC_AMOUNT - totalFees + invoice.fees.solverFee;

        // Settle all invoices
        for (uint256 i; i < 3; ++i) {
            _settleInvoiceAsSettler(sessionKeys[i]);
        }

        // Verify solver received payments from all invoices
        assertEq(testUSDC.balanceOf(solver.pub), initialSolverBalance + (expectedSolverAmountPerInvoice * 3));
    }

    function test_settleInvoice_success_maxFee() public withSetupInvoiceManager {
        // Onboard solver with max fee (1000 cents = 10.00 tokens)
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            "Max Fee Solver",
            ISolverManager.FeeType.FIXED,
            100, // 100 cents orchestrator fee
            ISolverManager.FeeType.FIXED,
            1000 // 1000 cents solver fee
        );
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        _mintTokensToInvoiceManager();

        // Calculate expected fees (sequential):
        // Protocol: 5 cents = 0.05 USDC = 50000
        uint256 protocolFee = (5 * 10 ** 6) / 100;
        // Orchestrator: 100 cents on remaining = 1.00 USDC = 1000000
        uint256 orchestratorFee = (100 * 10 ** 6) / 100;
        // Solver: 1000 cents on remaining = 10.00 USDC = 10000000
        uint256 solverFee = (1000 * 10 ** 6) / 100;
        uint256 totalFees = protocolFee + orchestratorFee + solverFee;
        uint256 expectedSolverRepayment = DEFAULT_USDC_AMOUNT - totalFees;

        uint256 initialProtocolReceiverBalance = testUSDC.balanceOf(protocolFeeReceiver.pub);
        uint256 initialOrchestratorReceiverBalance = testUSDC.balanceOf(orchestratorFeeReceiver.pub);
        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);

        _settleInvoiceAsSettler(sessionKey.pub);

        // Verify fee transfers - separate receivers for protocol and orchestrator
        assertEq(
            testUSDC.balanceOf(protocolFeeReceiver.pub),
            initialProtocolReceiverBalance + protocolFee,
            "Protocol fee transfer"
        );
        assertEq(
            testUSDC.balanceOf(orchestratorFeeReceiver.pub),
            initialOrchestratorReceiverBalance + orchestratorFee,
            "Orchestrator fee transfer"
        );
        assertEq(
            testUSDC.balanceOf(solver.pub),
            initialSolverBalance + expectedSolverRepayment + solverFee,
            "Solver repayment + fee"
        );
    }

    function test_settleInvoice_success_percentageBasedFees() public withSetupInvoiceManager {
        // Onboard solver with percentage-based fees to verify sequential calculation
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            orchestratorFeeReceiver.pub,
            "Percentage Solver",
            ISolverManager.FeeType.PERCENTAGE,
            100, // 100 basis points = 1% orchestrator fee
            ISolverManager.FeeType.PERCENTAGE,
            200 // 200 basis points = 2% solver fee
        );

        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        _mintTokensToInvoiceManager();

        // Calculate expected sequential fees on 100 USDC (100000000):
        // Protocol: 5 cents fixed = 50000
        uint256 protocolFee = 50000;
        uint256 afterProtocol = DEFAULT_USDC_AMOUNT - protocolFee; // 99950000

        // Orchestrator: 1% of remaining = 999500
        uint256 orchestratorFee = (afterProtocol * 100) / 10000;
        uint256 afterOrchestrator = afterProtocol - orchestratorFee; // 98950500

        // Solver: 2% of remaining = 1979010
        uint256 solverFee = (afterOrchestrator * 200) / 10000;
        uint256 expectedSolverRepayment = afterOrchestrator - solverFee; // 96971490

        uint256 initialProtocolBalance = testUSDC.balanceOf(protocolFeeReceiver.pub);
        uint256 initialOrchestratorBalance = testUSDC.balanceOf(orchestratorFeeReceiver.pub);
        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);

        _settleInvoiceAsSettler(sessionKey.pub);

        // Verify each tier received correct amount
        assertEq(
            testUSDC.balanceOf(protocolFeeReceiver.pub) - initialProtocolBalance, protocolFee, "Protocol fee incorrect"
        );
        assertEq(
            testUSDC.balanceOf(orchestratorFeeReceiver.pub) - initialOrchestratorBalance,
            orchestratorFee,
            "Orchestrator fee incorrect"
        );
        assertEq(
            testUSDC.balanceOf(solver.pub) - initialSolverBalance,
            expectedSolverRepayment + solverFee,
            "Solver repayment + fee incorrect"
        );
    }

    function test_settleInvoice_success_mixedFeeTypes() public withSetupInvoiceManager {
        // Test FIXED orchestrator fee with PERCENTAGE solver fee
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            orchestratorFeeReceiver.pub,
            "Mixed Fee Solver",
            ISolverManager.FeeType.FIXED,
            25, // 25 cents fixed orchestrator fee
            ISolverManager.FeeType.PERCENTAGE,
            150 // 150 basis points = 1.5% solver fee
        );

        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        _mintTokensToInvoiceManager();

        // Calculate expected sequential fees on 100 USDC:
        // Protocol: 5 cents fixed = 50000
        uint256 protocolFee = 50000;
        uint256 afterProtocol = DEFAULT_USDC_AMOUNT - protocolFee; // 99950000

        // Orchestrator: 25 cents fixed = 250000
        uint256 orchestratorFee = 250000;
        uint256 afterOrchestrator = afterProtocol - orchestratorFee; // 99700000

        // Solver: 1.5% of remaining = 1495500
        uint256 solverFee = (afterOrchestrator * 150) / 10000;
        uint256 expectedSolverRepayment = afterOrchestrator - solverFee; // 98204500

        uint256 initialProtocolBalance = testUSDC.balanceOf(protocolFeeReceiver.pub);
        uint256 initialOrchestratorBalance = testUSDC.balanceOf(orchestratorFeeReceiver.pub);
        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);

        _settleInvoiceAsSettler(sessionKey.pub);

        // Verify mixed fee types calculated correctly
        assertEq(
            testUSDC.balanceOf(protocolFeeReceiver.pub) - initialProtocolBalance, protocolFee, "Protocol fee incorrect"
        );
        assertEq(
            testUSDC.balanceOf(orchestratorFeeReceiver.pub) - initialOrchestratorBalance,
            orchestratorFee,
            "Orchestrator fee (FIXED) incorrect"
        );
        assertEq(
            testUSDC.balanceOf(solver.pub) - initialSolverBalance,
            expectedSolverRepayment + solverFee,
            "Solver repayment + fee (PERCENTAGE) incorrect"
        );
    }

    function test_settleInvoice_success_sequentialCalculationVerification() public withSetupInvoiceManager {
        // Explicit test documenting the sequential fee calculation formula
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            orchestratorFeeReceiver.pub,
            "Sequential Test Solver",
            ISolverManager.FeeType.PERCENTAGE,
            500, // 5% orchestrator
            ISolverManager.FeeType.PERCENTAGE,
            1000 // 10% solver
        );

        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        _mintTokensToInvoiceManager();

        // Get snapshotted fees from invoice
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKey.pub);

        // Verify sequential calculation:
        // Step 1: Protocol takes 5 cents from total
        uint256 expectedProtocolFee = 50000; // 5 cents
        assertEq(invoice.fees.protocolFee, expectedProtocolFee, "Protocol fee should be 5 cents");

        // Step 2: Orchestrator takes 5% of (total - protocol)
        uint256 remainingAfterProtocol = DEFAULT_USDC_AMOUNT - expectedProtocolFee;
        uint256 expectedOrchestratorFee = (remainingAfterProtocol * 500) / 10000;
        assertEq(invoice.fees.orchestratorFee, expectedOrchestratorFee, "Orchestrator should take 5% of remaining");

        // Step 3: Solver takes 10% of (total - protocol - orchestrator)
        uint256 remainingAfterOrchestrator = remainingAfterProtocol - expectedOrchestratorFee;
        uint256 expectedSolverFee = (remainingAfterOrchestrator * 1000) / 10000;
        assertEq(invoice.fees.solverFee, expectedSolverFee, "Solver should take 10% of remaining");

        // Verify total conservation
        uint256 totalFees = invoice.fees.protocolFee + invoice.fees.orchestratorFee + invoice.fees.solverFee;
        uint256 expectedRepayment = DEFAULT_USDC_AMOUNT - totalFees;

        // Settle and verify actual distribution matches calculation
        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);
        _settleInvoiceAsSettler(sessionKey.pub);

        assertEq(
            testUSDC.balanceOf(solver.pub) - initialSolverBalance,
            expectedRepayment + expectedSolverFee,
            "Final solver amount should match sequential calculation"
        );
    }

    function test_settleInvoice_success_separateSolverFeeReceiver() public withSetupInvoiceManager {
        // Create separate addresses for solver execution and fee receiver
        User memory solverExecutor = _createUser("Solver Executor");
        User memory solverFeeReceiver = _createUser("Solver Fee Receiver");

        // Onboard solver with different execution and fee addresses
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solverExecutor.pub, // execution address
            solverFeeReceiver.pub, // fee receiver address (different!)
            orchestratorFeeReceiver.pub,
            "Split Address Solver",
            ISolverManager.FeeType.PERCENTAGE,
            50, // 0.5% orchestrator
            ISolverManager.FeeType.PERCENTAGE,
            20 // 0.2% solver
        );

        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData =
            _createInvoiceData(address(scw), sessionKey.pub, solverExecutor.pub, DEFAULT_BID_HASH);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        _mintTokensToInvoiceManager();

        // Get fees from invoice
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKey.pub);
        uint256 totalFees = invoice.fees.protocolFee + invoice.fees.orchestratorFee + invoice.fees.solverFee;
        uint256 expectedRepayment = DEFAULT_USDC_AMOUNT - totalFees;

        uint256 initialExecutorBalance = testUSDC.balanceOf(solverExecutor.pub);
        uint256 initialFeeReceiverBalance = testUSDC.balanceOf(solverFeeReceiver.pub);

        _settleInvoiceAsSettler(sessionKey.pub);

        // Verify repayment goes to executor address
        assertEq(
            testUSDC.balanceOf(solverExecutor.pub) - initialExecutorBalance,
            expectedRepayment,
            "Repayment should go to solver execution address"
        );

        // Verify solver fee goes to fee receiver address
        assertEq(
            testUSDC.balanceOf(solverFeeReceiver.pub) - initialFeeReceiverBalance,
            invoice.fees.solverFee,
            "Solver fee should go to solver fee receiver address"
        );
    }

    function test_settleInvoice_success_executionAddressSnapshotted() public withOnboardedSolvers {
        // Create invoice (this snapshots the solver execution address)
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Verify execution address is snapshotted in invoice
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(invoice.fees.solverExecutionAddress, solver.pub, "Execution address should be snapshotted");

        // Note: We cannot change the execution address through normal means since it's immutable
        // This test verifies the snapshot exists and matches the solver key

        _mintTokensToInvoiceManager();

        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);
        uint256 totalFees = invoice.fees.protocolFee + invoice.fees.orchestratorFee + invoice.fees.solverFee;
        uint256 expectedRepayment = DEFAULT_USDC_AMOUNT - totalFees;

        _settleInvoiceAsSettler(sessionKey.pub);

        // Verify repayment went to snapshotted execution address
        assertEq(
            testUSDC.balanceOf(solver.pub) - initialSolverBalance,
            expectedRepayment + invoice.fees.solverFee,
            "Repayment should go to snapshotted execution address"
        );
    }

    function test_settleInvoice_success_feeAddressChangeDoesNotAffectExisting() public withOnboardedSolvers {
        // Create invoice with original fee address
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Verify original fee address is snapshotted (solver.pub is fee address in default setup)
        (InvoiceManager.Invoice memory oldInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        address originalFeeAddress = oldInvoice.fees.solverFeeReceiver;
        assertEq(originalFeeAddress, solver.pub, "Original fee address should be solver.pub");

        // Update solver fee address
        address newFeeAddress = address(0x9999);
        vm.prank(solverManager.pub);
        invoiceManager.updateSolverFeeAddress(solver.pub, newFeeAddress);

        // Verify old invoice still has original fee address (snapshot is immutable)
        (InvoiceManager.Invoice memory sameInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(
            sameInvoice.fees.solverFeeReceiver,
            originalFeeAddress,
            "Fee address should remain unchanged for existing invoice"
        );

        _mintTokensToInvoiceManager();

        uint256 initialOriginalBalance = testUSDC.balanceOf(originalFeeAddress);
        uint256 initialNewBalance = testUSDC.balanceOf(newFeeAddress);

        _settleInvoiceAsSettler(sessionKey.pub);

        // In default setup, solver.pub is BOTH execution address AND fee address
        // So it receives BOTH the solver fee and the repayment
        uint256 totalFees = sameInvoice.fees.protocolFee + sameInvoice.fees.orchestratorFee + sameInvoice.fees.solverFee;
        uint256 repayment = DEFAULT_USDC_AMOUNT - totalFees;

        // Verify solver.pub received both fee and repayment (snapshotted addresses), NOT new address
        assertEq(
            testUSDC.balanceOf(originalFeeAddress) - initialOriginalBalance,
            sameInvoice.fees.solverFee + repayment,
            "Solver fee AND repayment should go to snapshotted original address (since it's both execution and fee address)"
        );
        assertEq(
            testUSDC.balanceOf(newFeeAddress) - initialNewBalance,
            0,
            "New fee address should receive nothing for old invoices"
        );
    }

    function test_settleInvoice_success_orchestratorReceiverChangeDoesNotAffectExisting() public withOnboardedSolvers {
        // Create invoice with original orchestrator receiver
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Verify original orchestrator receiver is snapshotted (feeReceiver.pub in default setup)
        (InvoiceManager.Invoice memory oldInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        address originalOrchestratorReceiver = oldInvoice.fees.orchestratorFeeReceiver;
        assertEq(
            originalOrchestratorReceiver, feeReceiver.pub, "Original orchestrator receiver should be feeReceiver.pub"
        );

        // Update orchestrator receiver
        address newOrchestratorReceiver = address(0x8888);
        vm.prank(solverManager.pub);
        invoiceManager.updateOrchestratorReceiver(solver.pub, newOrchestratorReceiver);

        // Verify old invoice still has original orchestrator receiver
        (InvoiceManager.Invoice memory sameInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(
            sameInvoice.fees.orchestratorFeeReceiver,
            originalOrchestratorReceiver,
            "Orchestrator receiver should remain unchanged for existing invoice"
        );

        _mintTokensToInvoiceManager();

        uint256 initialOriginalBalance = testUSDC.balanceOf(originalOrchestratorReceiver);
        uint256 initialNewBalance = testUSDC.balanceOf(newOrchestratorReceiver);

        _settleInvoiceAsSettler(sessionKey.pub);

        // Verify orchestrator fee went to ORIGINAL receiver (snapshotted), NOT new receiver
        assertEq(
            testUSDC.balanceOf(originalOrchestratorReceiver) - initialOriginalBalance,
            sameInvoice.fees.orchestratorFee,
            "Orchestrator fee should go to snapshotted original receiver"
        );
        assertEq(
            testUSDC.balanceOf(newOrchestratorReceiver) - initialNewBalance,
            0,
            "New orchestrator receiver should receive nothing for old invoices"
        );
    }

    function test_createInvoice_success_snapshotsAllFeeAddresses() public withSetupInvoiceManager {
        // Onboard solver with specific addresses
        User memory solverExecutor = _createUser("Solver Executor");
        User memory solverFeeAddr = _createUser("Solver Fee Receiver");
        User memory orchestratorReceiver = _createUser("Orchestrator Receiver");

        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solverExecutor.pub,
            solverFeeAddr.pub,
            orchestratorReceiver.pub,
            "Test Solver",
            ISolverManager.FeeType.PERCENTAGE,
            50,
            ISolverManager.FeeType.PERCENTAGE,
            20
        );

        // Create invoice
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData =
            _createInvoiceData(address(scw), sessionKey.pub, solverExecutor.pub, DEFAULT_BID_HASH);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Verify all addresses are correctly snapshotted
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(invoice.fees.solverExecutionAddress, solverExecutor.pub, "Execution address should be snapshotted");
        assertEq(invoice.fees.solverFeeReceiver, solverFeeAddr.pub, "Solver fee receiver should be snapshotted");
        assertEq(
            invoice.fees.orchestratorFeeReceiver,
            orchestratorReceiver.pub,
            "Orchestrator receiver should be snapshotted"
        );
        assertEq(
            invoice.fees.protocolFeeReceiver, protocolFeeReceiver.pub, "Protocol fee receiver should be snapshotted"
        );
    }

    function test_updateOrchestratorFee_success_doesNotAffectExistingInvoices() public withSetupInvoiceManager {
        // Onboard solver with initial orchestrator fee
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            orchestratorFeeReceiver.pub,
            "Test Solver",
            ISolverManager.FeeType.PERCENTAGE,
            50, // Initial: 50 basis points = 0.5%
            ISolverManager.FeeType.PERCENTAGE,
            20
        );

        // Create invoice with original fee
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Get original fees from snapshotted invoice
        (InvoiceManager.Invoice memory invoiceBefore,) = invoiceManager.getInvoice(sessionKey.pub);
        uint256 originalOrchestratorFee = invoiceBefore.fees.orchestratorFee;

        // Calculate what the original fee should be (0.5% of remaining after protocol)
        uint256 afterProtocol = DEFAULT_USDC_AMOUNT - 50000; // After 5 cent protocol fee
        uint256 expectedOriginalFee = (afterProtocol * 50) / 10000;
        assertEq(originalOrchestratorFee, expectedOriginalFee, "Original orchestrator fee should be 0.5%");

        // Update orchestrator fee to much higher value
        vm.prank(feeManager.pub);
        invoiceManager.updateOrchestratorFee(solver.pub, ISolverManager.FeeType.PERCENTAGE, 500); // Change to 5%

        // Verify existing invoice still has original snapshotted fee
        (InvoiceManager.Invoice memory invoiceAfter,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(
            invoiceAfter.fees.orchestratorFee,
            originalOrchestratorFee,
            "Existing invoice should keep original snapshotted orchestrator fee"
        );

        // Settle and verify orchestrator receives ORIGINAL fee amount (not updated amount)
        _mintTokensToInvoiceManager();
        uint256 initialOrchestratorBalance = testUSDC.balanceOf(orchestratorFeeReceiver.pub);

        _settleInvoiceAsSettler(sessionKey.pub);

        // Orchestrator should receive the original snapshotted fee (0.5%), not the new fee (5%)
        assertEq(
            testUSDC.balanceOf(orchestratorFeeReceiver.pub) - initialOrchestratorBalance,
            originalOrchestratorFee,
            "Orchestrator should receive original snapshotted fee amount"
        );
    }

    function test_calculateInvoiceFees_success_matchesSnapshottedFees() public withSampleInvoice {
        // Get snapshotted fees from the invoice
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKey.pub);

        // Call calculateInvoiceFees
        (uint256 calculatedProtocol, uint256 calculatedOrchestrator, uint256 calculatedSolver, uint256 calculatedTotal)
        = invoiceManager.calculateInvoiceFees(sessionKey.pub);

        // Verify calculateInvoiceFees returns the snapshotted values (not recalculated)
        assertEq(calculatedProtocol, invoice.fees.protocolFee, "Protocol fee should match snapshotted");
        assertEq(calculatedOrchestrator, invoice.fees.orchestratorFee, "Orchestrator fee should match snapshotted");
        assertEq(calculatedSolver, invoice.fees.solverFee, "Solver fee should match snapshotted");
        assertEq(
            calculatedTotal,
            invoice.fees.protocolFee + invoice.fees.orchestratorFee + invoice.fees.solverFee,
            "Total should match sum of snapshotted fees"
        );

        // Change solver fees and verify calculated fees don't change
        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, ISolverManager.FeeType.PERCENTAGE, 500); // Change to 5%

        // Call calculateInvoiceFees again
        (uint256 recalcProtocol, uint256 recalcOrchestrator, uint256 recalcSolver, uint256 recalcTotal) =
            invoiceManager.calculateInvoiceFees(sessionKey.pub);

        // Fees should still match original snapshotted values
        assertEq(recalcProtocol, invoice.fees.protocolFee, "Protocol fee should remain snapshotted");
        assertEq(recalcOrchestrator, invoice.fees.orchestratorFee, "Orchestrator fee should remain snapshotted");
        assertEq(recalcSolver, invoice.fees.solverFee, "Solver fee should remain snapshotted after update");
        assertEq(recalcTotal, calculatedTotal, "Total should remain unchanged");
    }

    /*//////////////////////////////////////////////////////////////
                        CANCEL INVOICE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_cancelInvoice_success_asSettler() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        string memory reason = "User requested cancellation";

        // Verify invoice exists before cancellation
        assertTrue(invoiceManager.invoiceExists(sessionKey), "Invoice should exist");
        assertTrue(invoiceManager.bidHashExists(DEFAULT_BID_HASH), "Bid hash should exist");

        vm.expectEmit(true, false, false, true);
        emit InvoiceCancelled(sessionKey, reason);

        vm.prank(settler.pub); // settler has SETTLER_ROLE
        invoiceManager.cancelInvoice(sessionKey, reason);

        // Verify invoice is deleted
        assertFalse(invoiceManager.invoiceExists(sessionKey), "Invoice should be deleted");
        assertFalse(invoiceManager.bidHashExists(DEFAULT_BID_HASH), "Bid hash should be deleted");
    }

    function test_cancelInvoice_success_asDeployer() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        string memory reason = "Admin cancellation";

        vm.expectEmit(true, false, false, true);
        emit InvoiceCancelled(sessionKey, reason);

        vm.prank(deployer.pub); // deployer has SETTLER_ROLE
        invoiceManager.cancelInvoice(sessionKey, reason);

        // Verify invoice is deleted
        assertFalse(invoiceManager.invoiceExists(sessionKey), "Invoice should be deleted");
    }

    function test_cancelInvoice_success_longReason() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        string memory longReason =
            "This is a very long reason for cancelling the invoice that contains multiple words and should test the string handling properly in the event emission and storage";

        vm.expectEmit(true, false, false, true);
        emit InvoiceCancelled(sessionKey, longReason);

        vm.prank(settler.pub);
        invoiceManager.cancelInvoice(sessionKey, longReason);

        // Verify invoice is deleted
        assertFalse(invoiceManager.invoiceExists(sessionKey), "Invoice should be deleted");
    }

    function test_cancelInvoice_succeeds_evenIfCreditedTokensRemain() public withSampleInvoice {
        // credit before cancel
        _creditTokensToInvoice(sessionKey.pub);

        // snapshot pre-balance
        uint256 preBalance = testUSDC.balanceOf(address(invoiceManager));

        vm.expectEmit(true, false, false, true);
        emit InvoiceCancelled(sessionKey.pub, "User requested cancellation");

        vm.prank(settler.pub);
        invoiceManager.cancelInvoice(sessionKey.pub, "User requested cancellation");

        // invoice should be deleted
        assertFalse(invoiceManager.invoiceExists(sessionKey.pub), "Invoice should no longer exist");

        // contract balance unchanged
        uint256 postBalance = testUSDC.balanceOf(address(invoiceManager));
        assertEq(preBalance, postBalance, "No tokens should move on cancel");

        // bid hash reusable
        assertFalse(invoiceManager.bidHashExists(DEFAULT_BID_HASH), "Bid hash should be reusable");
    }

    function test_cancelInvoice_success_cleansUpAllData() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        string memory reason = "Cleanup test";

        // Verify data exists before cancellation
        assertTrue(invoiceManager.bidHashExists(DEFAULT_BID_HASH), "Bid hash should exist");
        (InvoiceManager.Invoice memory invoice, InvoiceManager.InvoiceTokenData[] memory tokens) =
            invoiceManager.getInvoice(sessionKey);
        assertGt(tokens.length, 0, "Token data should exist");

        // Verify solver has this invoice
        address[] memory solverInvoices = invoiceManager.getSolverInvoices(solver.pub);
        bool foundInvoice = false;
        for (uint256 i; i < solverInvoices.length; ++i) {
            if (solverInvoices[i] == sessionKey) {
                foundInvoice = true;
                break;
            }
        }
        assertTrue(foundInvoice, "Solver should have this invoice");

        vm.prank(settler.pub);
        invoiceManager.cancelInvoice(sessionKey, reason);

        // Verify all data is cleaned up
        assertFalse(invoiceManager.bidHashExists(DEFAULT_BID_HASH), "Bid hash should be deleted");

        _toRevert(InvoiceManager.IM_InvoiceNotFound.selector, hex"");
        invoiceManager.getInvoice(sessionKey);

        // Verify solver no longer has this invoice
        address[] memory solverInvoicesAfter = invoiceManager.getSolverInvoices(solver.pub);
        for (uint256 i; i < solverInvoicesAfter.length; ++i) {
            assertNotEq(solverInvoicesAfter[i], sessionKey, "Solver should not have this invoice after cancellation");
        }
    }

    function test_cancelInvoice_success_allowsReuseBidHashAfterCancellation() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        string memory reason = "Reuse bid hash test";

        // Cancel the invoice
        vm.prank(settler.pub);
        invoiceManager.cancelInvoice(sessionKey, reason);

        // Should be able to create new invoice with same bid hash
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData =
            _createInvoiceData(address(scw2), sessionKey2.pub, solver.pub, DEFAULT_BID_HASH);

        // This should not revert
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_cancelInvoice_success_multipleCancellations() public withOnboardedSolvers {
        // Create multiple invoices
        vm.startPrank(credibleAccount.pub);

        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        invoiceManager.createInvoice(createInvoiceData);

        bytes memory createInvoiceData2 =
            _createInvoiceData(address(scw2), sessionKey2.pub, solver.pub, SECOND_BID_HASH);

        invoiceManager.createInvoice(createInvoiceData2);

        vm.stopPrank();

        // Cancel with different reasons
        vm.startPrank(settler.pub);

        vm.expectEmit(true, false, false, true);
        emit InvoiceCancelled(sessionKey.pub, "First cancellation");
        invoiceManager.cancelInvoice(sessionKey.pub, "First cancellation");

        vm.expectEmit(true, false, false, true);
        emit InvoiceCancelled(sessionKey2.pub, "Second cancellation");
        invoiceManager.cancelInvoice(sessionKey2.pub, "Second cancellation");

        vm.stopPrank();

        // Verify both are cancelled
        assertFalse(invoiceManager.invoiceExists(sessionKey.pub), "First invoice should be deleted");
        assertFalse(invoiceManager.invoiceExists(sessionKey2.pub), "Second invoice should be deleted");
    }

    function test_cancelInvoice_revertIf_invoiceNotFound() public withSetupInvoiceManager {
        address nonExistentSessionKey = makeAddr("nonExistentSessionKey");
        string memory reason = "Does not exist";

        vm.prank(settler.pub);
        _toRevert(InvoiceManager.IM_InvoiceNotFound.selector, hex"");
        invoiceManager.cancelInvoice(nonExistentSessionKey, reason);
    }

    function test_cancelInvoice_revertIf_notSettlerRole() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        address unauthorizedUser = makeAddr("unauthorizedUser");
        string memory reason = "Unauthorized attempt";

        vm.prank(unauthorizedUser);
        vm.expectRevert(); // Should revert due to missing SETTLER_ROLE
        invoiceManager.cancelInvoice(sessionKey, reason);
    }

    function test_cancelInvoice_revertIf_solverTriesToCancel() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        string memory reason = "Solver attempt";

        // Test that solver cannot cancel
        vm.prank(solver.pub);
        vm.expectRevert(); // Should revert due to missing SETTLER_ROLE
        invoiceManager.cancelInvoice(sessionKey, reason);
    }

    function test_cancelInvoice_revertIf_alreadySettled() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        string memory reason = "Already settled";

        // First settle the invoice
        _settleInvoiceAsSettler(sessionKey);

        // Then try to cancel it
        vm.prank(settler.pub);
        _toRevert(InvoiceManager.IM_InvoiceNotFound.selector, hex"");
        invoiceManager.cancelInvoice(sessionKey, reason);
    }

    function test_cancelInvoice_revertIf_emptyReason() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        string memory emptyReason = "";

        vm.prank(settler.pub);
        _toRevert(InvoiceManager.IM_EmptyReasonNotAllowed.selector, hex"");
        invoiceManager.cancelInvoice(sessionKey, emptyReason);

        // Verify invoice still exists
        assertTrue(invoiceManager.invoiceExists(sessionKey), "Invoice should still exist");
    }

    function test_cancelInvoice_success_onlySettlerRoleCanCancel() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        string memory reason = "Role test";

        // Grant SETTLER_ROLE to a new user
        address newSettler = makeAddr("newSettler");
        vm.prank(deployer.pub);
        invoiceManager.grantSettlerRole(newSettler);

        // New settler should be able to cancel
        vm.expectEmit(true, false, false, true);
        emit InvoiceCancelled(sessionKey, reason);

        vm.prank(newSettler);
        invoiceManager.cancelInvoice(sessionKey, reason);

        // Verify invoice is deleted
        assertFalse(invoiceManager.invoiceExists(sessionKey), "Invoice should be deleted");
    }

    function test_cancelInvoice_success_withMultipleTokens() public withOnboardedSolvers {
        // Create invoice with all 4 tokens
        TokenData[] memory allTokenData = new TokenData[](4);
        allTokenData[0] = TokenData({token: address(testUSDC), amount: DEFAULT_USDC_AMOUNT});
        allTokenData[1] = TokenData({token: address(testUSDT), amount: DEFAULT_USDT_AMOUNT});
        allTokenData[2] = TokenData({token: address(testDAI), amount: DEFAULT_DAI_AMOUNT});
        allTokenData[3] = TokenData({token: address(testBUSD), amount: DEFAULT_BUSD_AMOUNT});

        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, allTokenData);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Verify all token data exists
        (, InvoiceManager.InvoiceTokenData[] memory tokens) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(tokens.length, 4, "Should have 4 tokens");

        string memory reason = "Multiple tokens test";
        vm.expectEmit(true, false, false, true);
        emit InvoiceCancelled(sessionKey.pub, reason);

        vm.prank(settler.pub);
        invoiceManager.cancelInvoice(sessionKey.pub, reason);

        // Verify invoice and all token data is deleted
        assertFalse(invoiceManager.invoiceExists(sessionKey.pub), "Invoice should be deleted");
        assertFalse(invoiceManager.bidHashExists(DEFAULT_BID_HASH), "Bid hash should be deleted");
    }

    function test_cancelInvoice_success_beforeAnyCreditedTokens() public withSampleInvoice {
        // Cancel before any tokens are credited (should succeed)
        vm.prank(settler.pub);
        invoiceManager.cancelInvoice(sessionKey.pub, "Cancelled before credit");

        assertFalse(invoiceManager.invoiceExists(sessionKey.pub), "Invoice should be deleted");
    }

    /*//////////////////////////////////////////////////////////////
                        SOLVER MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onboardSolver_success_defaultFee() public withSetupInvoiceManager {
        string memory solverName = "Default Fee Solver";

        vm.expectEmit(true, false, false, true);
        emit SolverOnboarded(
            solver.pub, solverName, ISolverManager.FeeType.PERCENTAGE, 50, ISolverManager.FeeType.PERCENTAGE, 20
        );

        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            solverName,
            ISolverManager.FeeType.PERCENTAGE,
            50,
            ISolverManager.FeeType.PERCENTAGE,
            20
        );

        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);

        assertEq(solverData.name, solverName, "Solver name should match");
        assertTrue(solverData.isActive, "Solver should be active");
        assertEq(solverData.solverFeeValue, 20, "Fee should be 20 basis points");
    }

    function test_onboardSolver_success_customFee() public withSetupInvoiceManager {
        string memory solverName = "Custom Fee Solver";
        uint256 customFee = 7500; // 75% (7500 basis points) - within MAX_FEE_PERCENTAGE limit

        vm.expectEmit(true, false, false, true);
        emit SolverOnboarded(
            solver.pub, solverName, ISolverManager.FeeType.PERCENTAGE, 50, ISolverManager.FeeType.PERCENTAGE, customFee
        );

        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            solverName,
            ISolverManager.FeeType.PERCENTAGE,
            50,
            ISolverManager.FeeType.PERCENTAGE,
            customFee
        );

        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);

        assertEq(solverData.name, solverName, "Solver name should match");
        assertTrue(solverData.isActive, "Solver should be active");
        assertEq(solverData.solverFeeValue, customFee, "Fee should match custom amount");
    }

    function test_onboardSolver_success_emptyName() public withSetupInvoiceManager {
        string memory emptyName = "";

        vm.expectEmit(true, false, false, true);
        emit SolverOnboarded(
            solver.pub, emptyName, ISolverManager.FeeType.PERCENTAGE, 50, ISolverManager.FeeType.PERCENTAGE, 20
        );

        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            emptyName,
            ISolverManager.FeeType.PERCENTAGE,
            50,
            ISolverManager.FeeType.PERCENTAGE,
            20
        );

        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);

        assertTrue(solverData.isActive, "Solver should be active");
        assertEq(solverData.name, emptyName, "Name should be empty");
    }

    function test_onboardSolver_success_longName() public withSetupInvoiceManager {
        string memory longName =
            "This is a very long solver name that contains multiple words and should test the string handling properly in the solver management system";

        vm.expectEmit(true, false, false, true);
        emit SolverOnboarded(
            solver.pub, longName, ISolverManager.FeeType.PERCENTAGE, 50, ISolverManager.FeeType.PERCENTAGE, 20
        );

        vm.prank(solverManager.pub);

        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            longName,
            ISolverManager.FeeType.PERCENTAGE,
            50,
            ISolverManager.FeeType.PERCENTAGE,
            20
        );

        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);

        assertTrue(solverData.isActive, "Solver should be active");
        assertEq(solverData.name, longName, "Name should match long name");
    }

    function test_onboardSolver_success_multipleSolvers() public withSetupInvoiceManager {
        vm.startPrank(solverManager.pub);

        // Onboard first solver with percentage fees
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            "Solver One",
            ISolverManager.FeeType.PERCENTAGE,
            50, // 0.5% orchestrator
            ISolverManager.FeeType.PERCENTAGE,
            20 // 0.2% solver
        );
        // Onboard second solver with fixed fees
        invoiceManager.onboardSolver(
            solver2.pub,
            solver2.pub,
            feeReceiver.pub,
            "Solver Two",
            ISolverManager.FeeType.FIXED,
            10, // 10 cents orchestrator
            ISolverManager.FeeType.FIXED,
            HIGH_FEE_AMOUNT // solver fee
        );

        vm.stopPrank();

        ISolverManager.Solver memory solverData1 = invoiceManager.getSolverData(solver.pub);

        ISolverManager.Solver memory solverData2 = invoiceManager.getSolverData(solver2.pub);

        // Verify both are active
        assertTrue(solverData1.isActive, "Solver 1 should be active");
        assertTrue(solverData2.isActive, "Solver 2 should be active");

        // Verify different fees (solver1 uses percentage, solver2 uses fixed)
        assertEq(solverData1.solverFeeValue, 20, "Solver 1 fee should be 20 basis points");
        assertEq(solverData2.solverFeeValue, HIGH_FEE_AMOUNT, "Solver 2 fee should match HIGH_FEE_AMOUNT");
    }

    function test_onboardSolver_revertIf_notSolverManagerRole() public withSetupInvoiceManager {
        vm.prank(alice.pub); // Not solver manager
        vm.expectRevert(); // Should revert due to missing SOLVER_MANAGER_ROLE
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            "Test Solver",
            ISolverManager.FeeType.PERCENTAGE,
            50,
            ISolverManager.FeeType.PERCENTAGE,
            20
        );
    }

    function test_onboardSolver_revertIf_invalidSolverAddress() public withSetupInvoiceManager {
        vm.prank(solverManager.pub);
        _toRevert(SolverManager.SM_InvalidAddress.selector, hex"");
        invoiceManager.onboardSolver(
            address(0),
            address(0),
            feeReceiver.pub,
            "Test Solver",
            ISolverManager.FeeType.PERCENTAGE,
            50,
            ISolverManager.FeeType.PERCENTAGE,
            20
        );
    }

    function test_onboardSolver_revertIf_solverAlreadyActive() public withOnboardedSolvers {
        // Try to onboard solver again
        vm.prank(solverManager.pub);
        _toRevert(SolverManager.SM_SolverAlreadyExists.selector, hex"");
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            "Duplicate Solver",
            ISolverManager.FeeType.PERCENTAGE,
            50,
            ISolverManager.FeeType.PERCENTAGE,
            20
        );
    }

    function test_onboardSolver_revertIf_orchestratorFeePercentageTooHigh() public withSetupInvoiceManager {
        vm.prank(solverManager.pub);
        _toRevert(SolverManager.SM_FeeValueTooHigh.selector, hex"");
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            "High Fee Solver",
            ISolverManager.FeeType.PERCENTAGE,
            10001, // Exceeds MAX_FEE_PERCENTAGE (10000)
            ISolverManager.FeeType.PERCENTAGE,
            20
        );
    }

    function test_onboardSolver_revertIf_solverFeePercentageTooHigh() public withSetupInvoiceManager {
        vm.prank(solverManager.pub);
        _toRevert(SolverManager.SM_FeeValueTooHigh.selector, hex"");
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            "High Fee Solver",
            ISolverManager.FeeType.PERCENTAGE,
            50,
            ISolverManager.FeeType.PERCENTAGE,
            750000 // Exceeds MAX_FEE_PERCENTAGE (10000)
        );
    }

    function test_onboardSolver_revertIf_orchestratorFeeFixedTooHigh() public withSetupInvoiceManager {
        vm.prank(solverManager.pub);
        _toRevert(SolverManager.SM_FeeValueTooHigh.selector, hex"");
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            "High Fee Solver",
            ISolverManager.FeeType.FIXED,
            1000001, // Exceeds MAX_FEE_FIXED (1000000 = $10,000)
            ISolverManager.FeeType.PERCENTAGE,
            20
        );
    }

    function test_onboardSolver_revertIf_solverFeeFixedTooHigh() public withSetupInvoiceManager {
        vm.prank(solverManager.pub);
        _toRevert(SolverManager.SM_FeeValueTooHigh.selector, hex"");
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            "High Fee Solver",
            ISolverManager.FeeType.PERCENTAGE,
            50,
            ISolverManager.FeeType.FIXED,
            2000000 // Exceeds MAX_FEE_FIXED (1000000 = $10,000)
        );
    }

    function test_offboardSolver_success() public withOnboardedSolvers {
        // Verify solver is active before offboarding
        ISolverManager.Solver memory solverDataBefore = invoiceManager.getSolverData(solver.pub);
        assertTrue(solverDataBefore.isActive, "Solver should be active");
        assertFalse(solverDataBefore.pendingOffboard, "Solver should not be pending offboard");

        vm.expectEmit(true, false, false, false);
        emit SolverOffboarded(solver.pub);

        vm.prank(solverManager.pub);
        invoiceManager.offboardSolver(solver.pub);

        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);

        // Verify solver data is cleared after offboarding
        assertEq(solverData.name, "", "Name should be empty");
        assertEq(solverData.orchestratorFeeValue, 0, "Orchestrator fee should be 0");
        assertEq(solverData.solverFeeValue, 0, "Solver fee should be 0");
        assertFalse(solverData.isActive, "Solver should be inactive");
        assertFalse(solverData.pendingOffboard, "Solver should not be pending offboard as no active invoices");
    }

    function test_offboardSolver_success_allowsReOnboarding() public withOnboardedSolvers {
        // Offboard solver
        vm.prank(solverManager.pub);
        invoiceManager.offboardSolver(solver.pub);

        ISolverManager.Solver memory solverDataAfterOffboard = invoiceManager.getSolverData(solver.pub);

        assertFalse(solverDataAfterOffboard.isActive, "Solver should be inactive");

        // Re-onboard with different parameters
        string memory newName = "Re-onboarded Solver";
        uint256 newFee = HIGH_FEE_AMOUNT;

        vm.expectEmit(true, false, false, true);
        emit SolverOnboarded(
            solver.pub, newName, ISolverManager.FeeType.FIXED, 10, ISolverManager.FeeType.FIXED, newFee
        );

        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            newName,
            ISolverManager.FeeType.FIXED,
            10, // 10 cents orchestrator fee
            ISolverManager.FeeType.FIXED,
            newFee // Use newFee (HIGH_FEE_AMOUNT) as solver fee
        );

        // Verify solver is active with new parameters
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);

        assertTrue(solverData.isActive, "Solver should be active again");
        assertEq(solverData.name, newName, "Name should be updated");
        assertEq(solverData.solverFeeValue, newFee, "Solver fee should be updated");
    }

    function test_offboardSolver_success_pendingOffboard() public withSampleInvoice {
        // Verify solver has invoices
        address[] memory solverInvoices = invoiceManager.getSolverInvoices(solver.pub);
        assertGt(solverInvoices.length, 0, "Solver should have invoices");

        vm.prank(solverManager.pub);
        invoiceManager.offboardSolver(solver.pub);

        // Verify solver is not active, pending offboarded and invoices still exist
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);
        assertFalse(solverData.isActive, "Solver should not be active");
        assertTrue(solverData.pendingOffboard, "Solver should not be active");
        assertTrue(invoiceManager.invoiceExists(sessionKey.pub), "Existing invoice should still exist");
    }

    function test_offboardSolver_revertIf_notSolverManagerRole() public withOnboardedSolvers {
        vm.prank(alice.pub); // Not solver manager
        vm.expectRevert(); // Should revert due to missing SOLVER_MANAGER_ROLE
        invoiceManager.offboardSolver(solver.pub);
    }

    function test_offboardSolver_revertIf_invalidAddress() public withSetupInvoiceManager {
        vm.prank(solverManager.pub);
        _toRevert(SolverManager.SM_InvalidSolver.selector, hex"");
        invoiceManager.offboardSolver(address(0));
    }

    function test_updateSolverFee_success() public withOnboardedSolvers {
        uint256 oldFee = 20; // From _onboardDefaultSolvers
        uint256 newFee = LOW_FEE_AMOUNT;

        vm.expectEmit(true, false, false, true);
        emit SolverFeeUpdated(solver.pub, ISolverManager.FeeType.PERCENTAGE, oldFee, newFee);

        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, ISolverManager.FeeType.PERCENTAGE, newFee);

        // Verify fee is updated
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);
        assertEq(solverData.solverFeeValue, newFee, "Solver fee should be updated");
    }

    function test_updateSolverFee_success_zeroFee() public withOnboardedSolvers {
        uint256 oldFee = 20; // From _onboardDefaultSolvers
        uint256 newFee = 0;

        vm.expectEmit(true, false, false, true);
        emit SolverFeeUpdated(solver.pub, ISolverManager.FeeType.PERCENTAGE, oldFee, newFee);

        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, ISolverManager.FeeType.PERCENTAGE, 0);

        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);
        assertEq(solverData.solverFeeValue, 0, "Solver fee should be zero");
    }

    function test_updateSolverFee_success_maxFee() public withOnboardedSolvers {
        uint256 oldFee = 20; // From _onboardDefaultSolvers
        uint256 newFee = 1000; // 10%

        vm.expectEmit(true, false, false, true);
        emit SolverFeeUpdated(solver.pub, ISolverManager.FeeType.PERCENTAGE, oldFee, newFee);

        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, ISolverManager.FeeType.PERCENTAGE, newFee);

        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);
        assertEq(solverData.solverFeeValue, newFee, "Solver fee should be max fee");
    }

    function test_updateSolverFee_success_sameFee() public withOnboardedSolvers {
        vm.expectEmit(true, false, false, true);
        emit SolverFeeUpdated(solver.pub, ISolverManager.FeeType.PERCENTAGE, 20, 20);

        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, ISolverManager.FeeType.PERCENTAGE, 20);

        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);

        assertEq(uint256(solverData.solverFeeType), uint256(ISolverManager.FeeType.PERCENTAGE));
        assertEq(solverData.solverFeeValue, 20, "Solver fee value should be 20 basis points");
    }

    function test_updateSolverFee_success_affectsNewInvoicesOnly() public withSampleInvoice {
        // Get original invoice fees (snapshotted)
        (InvoiceManager.Invoice memory originalInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        uint256 originalProtocolFee = originalInvoice.fees.protocolFee;
        uint256 originalOrchestratorFee = originalInvoice.fees.orchestratorFee;
        uint256 originalSolverFee = originalInvoice.fees.solverFee;

        // Update solver fee to fixed 10 cents
        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, ISolverManager.FeeType.FIXED, 10);

        // Existing invoice should keep original fees (snapshotted)
        (InvoiceManager.Invoice memory existingInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(existingInvoice.fees.protocolFee, originalProtocolFee, "Protocol fee should not change");
        assertEq(existingInvoice.fees.orchestratorFee, originalOrchestratorFee, "Orchestrator fee should not change");
        assertEq(existingInvoice.fees.solverFee, originalSolverFee, "Solver fee should not change");

        // Create new invoice - should use new solver fee
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw2), sessionKey2.pub, solver.pub, SECOND_BID_HASH);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // New invoice should have different solver fee
        (InvoiceManager.Invoice memory newInvoice,) = invoiceManager.getInvoice(sessionKey2.pub);
        assertNotEq(newInvoice.fees.solverFee, originalSolverFee, "New invoice should use updated solver fee");

        // Calculate expected new solver fee: 10 cents = 10 * 10^4 = 100,000 (for USDC with 6 decimals)
        uint256 expectedNewSolverFee = (10 * 10 ** 6) / 100; // 0.10 USDC
        assertEq(newInvoice.fees.solverFee, expectedNewSolverFee, "New invoice solver fee should be 10 cents");
    }

    function test_updateSolverFee_revertIf_notFeeManagerRole() public withOnboardedSolvers {
        vm.prank(alice.pub); // Not fee manager
        vm.expectRevert(); // Should revert due to missing FEE_MANAGER_ROLE
        invoiceManager.updateSolverFee(solver.pub, ISolverManager.FeeType.FIXED, 3);
    }

    function test_updateSolverFee_revertIf_solverNotActive() public withSetupInvoiceManager {
        vm.prank(feeManager.pub);
        _toRevert(SolverManager.SM_InvalidSolver.selector, hex"");
        invoiceManager.updateSolverFee(solver.pub, ISolverManager.FeeType.FIXED, 3);
    }

    function test_updateSolverFee_revertIf_invalidAddress() public withSetupInvoiceManager {
        vm.prank(feeManager.pub);
        _toRevert(SolverManager.SM_InvalidSolver.selector, hex"");
        invoiceManager.updateSolverFee(address(0), ISolverManager.FeeType.PERCENTAGE, 20);
    }

    function test_updateSolverFee_revertIf_solverOffboarded() public withOnboardedSolvers {
        // Offboard solver first
        vm.prank(solverManager.pub);
        invoiceManager.offboardSolver(solver.pub);

        // Try to update fee of offboarded solver
        vm.prank(feeManager.pub);
        _toRevert(SolverManager.SM_InvalidSolver.selector, hex"");
        invoiceManager.updateSolverFee(solver.pub, ISolverManager.FeeType.PERCENTAGE, 20);
    }

    function test_updateSolverFeeAddress_success() public withOnboardedSolvers {
        address newFeeAddress = address(0x1234);

        vm.expectEmit(true, true, true, true);
        emit SolverFeeAddressUpdated(solver.pub, solver.pub, newFeeAddress); // Old fee address is solver.pub in default setup

        vm.prank(solverManager.pub);
        invoiceManager.updateSolverFeeAddress(solver.pub, newFeeAddress);

        // Verify fee address was updated
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);
        assertEq(solverData.feeAddress, newFeeAddress, "Fee address should be updated");
    }

    function test_updateSolverFeeAddress_revertIf_notSolverManagerRole() public withOnboardedSolvers {
        address newFeeAddress = address(0x1234);

        vm.prank(alice.pub);
        vm.expectRevert(); // Should revert due to missing SOLVER_MANAGER_ROLE
        invoiceManager.updateSolverFeeAddress(solver.pub, newFeeAddress);
    }

    function test_updateSolverFeeAddress_revertIf_invalidAddress() public withOnboardedSolvers {
        vm.prank(solverManager.pub);
        _toRevert(SolverManager.SM_InvalidAddress.selector, hex"");
        invoiceManager.updateSolverFeeAddress(solver.pub, address(0));
    }

    function test_updateSolverFeeAddress_revertIf_invalidSolver() public withSetupInvoiceManager {
        address newFeeAddress = address(0x1234);

        vm.prank(solverManager.pub);
        _toRevert(SolverManager.SM_InvalidSolver.selector, hex"");
        invoiceManager.updateSolverFeeAddress(solver.pub, newFeeAddress);
    }

    function test_updateSolverFeeAddress_success_affectsNewInvoicesOnly() public withSampleInvoice {
        address newFeeAddress = address(0x1234);

        // Get old invoice and verify old fee address (solver.pub is fee address in default setup)
        (InvoiceManager.Invoice memory oldInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(oldInvoice.fees.solverFeeReceiver, solver.pub, "Old invoice should have old fee address");

        // Update fee address
        vm.prank(solverManager.pub);
        invoiceManager.updateSolverFeeAddress(solver.pub, newFeeAddress);

        // Old invoice should still have old fee address
        (InvoiceManager.Invoice memory sameInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(sameInvoice.fees.solverFeeReceiver, solver.pub, "Old invoice should still have old fee address");

        // Create new invoice
        bytes memory newInvoiceData =
            _createInvoiceData(address(scw), sessionKey2.pub, solver.pub, keccak256("new_bid"));
        vm.prank(credibleAccount.pub);
        invoiceManager.createInvoice(newInvoiceData);

        // New invoice should have new fee address
        (InvoiceManager.Invoice memory newInvoice,) = invoiceManager.getInvoice(sessionKey2.pub);
        assertEq(newInvoice.fees.solverFeeReceiver, newFeeAddress, "New invoice should have new fee address");
    }

    function test_updateOrchestratorReceiver_success() public withOnboardedSolvers {
        address newOrchestratorReceiver = address(0x5678);

        vm.expectEmit(true, true, true, true);
        emit OrchestratorReceiverUpdated(solver.pub, feeReceiver.pub, newOrchestratorReceiver); // Old orchestrator receiver is feeReceiver.pub in default setup

        vm.prank(solverManager.pub);
        invoiceManager.updateOrchestratorReceiver(solver.pub, newOrchestratorReceiver);

        // Verify orchestrator receiver was updated
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);
        assertEq(solverData.orchestratorReceiver, newOrchestratorReceiver, "Orchestrator receiver should be updated");
    }

    function test_updateOrchestratorReceiver_revertIf_notSolverManagerRole() public withOnboardedSolvers {
        address newOrchestratorReceiver = address(0x5678);

        vm.prank(alice.pub);
        vm.expectRevert(); // Should revert due to missing SOLVER_MANAGER_ROLE
        invoiceManager.updateOrchestratorReceiver(solver.pub, newOrchestratorReceiver);
    }

    function test_updateOrchestratorReceiver_revertIf_invalidAddress() public withOnboardedSolvers {
        vm.prank(solverManager.pub);
        _toRevert(SolverManager.SM_InvalidAddress.selector, hex"");
        invoiceManager.updateOrchestratorReceiver(solver.pub, address(0));
    }

    function test_updateOrchestratorReceiver_revertIf_invalidSolver() public withSetupInvoiceManager {
        address newOrchestratorReceiver = address(0x5678);

        vm.prank(solverManager.pub);
        _toRevert(SolverManager.SM_InvalidSolver.selector, hex"");
        invoiceManager.updateOrchestratorReceiver(solver.pub, newOrchestratorReceiver);
    }

    function test_updateOrchestratorReceiver_success_affectsNewInvoicesOnly() public withSampleInvoice {
        address newOrchestratorReceiver = address(0x5678);

        // Get old invoice and verify old orchestrator receiver (feeReceiver.pub in default setup)
        (InvoiceManager.Invoice memory oldInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(
            oldInvoice.fees.orchestratorFeeReceiver,
            feeReceiver.pub,
            "Old invoice should have old orchestrator receiver"
        );

        // Update orchestrator receiver
        vm.prank(solverManager.pub);
        invoiceManager.updateOrchestratorReceiver(solver.pub, newOrchestratorReceiver);

        // Old invoice should still have old orchestrator receiver
        (InvoiceManager.Invoice memory sameInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(
            sameInvoice.fees.orchestratorFeeReceiver,
            feeReceiver.pub,
            "Old invoice should still have old orchestrator receiver"
        );

        // Create new invoice
        bytes memory newInvoiceData =
            _createInvoiceData(address(scw), sessionKey2.pub, solver.pub, keccak256("new_bid"));
        vm.prank(credibleAccount.pub);
        invoiceManager.createInvoice(newInvoiceData);

        // New invoice should have new orchestrator receiver
        (InvoiceManager.Invoice memory newInvoice,) = invoiceManager.getInvoice(sessionKey2.pub);
        assertEq(
            newInvoice.fees.orchestratorFeeReceiver,
            newOrchestratorReceiver,
            "New invoice should have new orchestrator receiver"
        );
    }

    function test_getSolverData_success() public withOnboardedSolvers {
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);

        assertEq(solverData.name, "Solver One", "Name should match");
        // Check the fee structure matches what was set in _onboardDefaultSolvers
        assertEq(uint256(solverData.solverFeeType), uint256(ISolverManager.FeeType.PERCENTAGE), "Should be PERCENTAGE");
        assertEq(solverData.solverFeeValue, 20, "Solver fee should be 20 basis points");
        assertEq(
            uint256(solverData.orchestratorFeeType), uint256(ISolverManager.FeeType.PERCENTAGE), "Should be PERCENTAGE"
        );
        assertEq(solverData.orchestratorFeeValue, 50, "Orchestrator fee should be 50 basis points");
        assertTrue(solverData.isActive, "Solver should be active");
    }

    function test_getSolverData_success_offboardedSolver() public withOnboardedSolvers {
        // Offboard solver
        vm.prank(solverManager.pub);
        invoiceManager.offboardSolver(solver.pub);

        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);

        assertEq(solverData.name, "", "Name should no longer exist");
        assertEq(solverData.orchestratorFeeValue, 0, "Orchestrator fee should be 0");
        assertEq(solverData.solverFeeValue, 0, "Solver fee should be 0");
        assertFalse(solverData.isActive, "Solver should be inactive");
        assertFalse(solverData.pendingOffboard, "Solver should be not be pending offboarding");
    }

    function test_getSolverData_success_neverOnboardedSolver() public withSetupInvoiceManager {
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);

        assertEq(solverData.name, "", "Name should be empty");
        assertEq(solverData.orchestratorFeeValue, 0, "Orchestrator fee should be zero");
        assertEq(solverData.solverFeeValue, 0, "Solver fee should be zero");
        assertFalse(solverData.isActive, "Solver should be inactive");
    }

    function test_getSolverInvoices_success_emptySolver() public withOnboardedSolvers {
        address[] memory invoices = invoiceManager.getSolverInvoices(solver.pub);
        assertEq(invoices.length, 0, "New solver should have no invoices");
    }

    function test_getSolverInvoices_success_withInvoices() public withSampleInvoice {
        address[] memory invoices = invoiceManager.getSolverInvoices(solver.pub);
        assertEq(invoices.length, 1, "Solver should have one invoice");
        assertEq(invoices[0], sessionKey.pub, "Invoice should match session key");
    }

    function test_getSolverInvoices_success_multipleInvoices() public withOnboardedSolvers {
        // Create multiple invoices for solver
        vm.startPrank(credibleAccount.pub);

        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        invoiceManager.createInvoice(createInvoiceData);

        bytes memory createInvoiceData2 =
            _createInvoiceData(address(scw2), sessionKey2.pub, solver.pub, SECOND_BID_HASH);

        invoiceManager.createInvoice(createInvoiceData2);

        vm.stopPrank();

        address[] memory invoices = invoiceManager.getSolverInvoices(solver.pub);
        assertEq(invoices.length, 2, "Solver should have two invoices");

        // Check both invoices are present (order might vary)
        bool foundFirst = false;
        bool foundSecond = false;
        for (uint256 i; i < invoices.length; ++i) {
            if (invoices[i] == sessionKey.pub) foundFirst = true;
            if (invoices[i] == sessionKey2.pub) foundSecond = true;
        }
        assertTrue(foundFirst, "First invoice should be found");
        assertTrue(foundSecond, "Second invoice should be found");
    }

    function test_getSolverInvoices_success_afterSettlement() public withSampleInvoice {
        address[] memory invoicesBefore = invoiceManager.getSolverInvoices(solver.pub);
        assertEq(invoicesBefore.length, 1, "Solver should have one invoice before settlement");

        // Settle the invoice
        _settleInvoiceAsSettler(sessionKey.pub);

        address[] memory invoicesAfter = invoiceManager.getSolverInvoices(solver.pub);
        assertEq(invoicesAfter.length, 0, "Solver should have no invoices after settlement");
    }

    function test_getSolverInvoices_success_afterCancellation() public withSampleInvoice {
        address[] memory invoicesBefore = invoiceManager.getSolverInvoices(solver.pub);
        assertEq(invoicesBefore.length, 1, "Solver should have one invoice before cancellation");

        // Cancel the invoice
        vm.prank(settler.pub);
        invoiceManager.cancelInvoice(sessionKey.pub, "Test cancellation");

        address[] memory invoicesAfter = invoiceManager.getSolverInvoices(solver.pub);
        assertEq(invoicesAfter.length, 0, "Solver should have no invoices after cancellation");
    }

    function test_getSolverInvoices_success_mixedSolvers() public withOnboardedSolvers {
        // Create invoices for different solvers
        vm.startPrank(credibleAccount.pub);

        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);
        invoiceManager.createInvoice(createInvoiceData);

        bytes memory createInvoiceData2 =
            _createInvoiceData(address(scw2), sessionKey2.pub, solver2.pub, SECOND_BID_HASH);

        invoiceManager.createInvoice(createInvoiceData2);

        vm.stopPrank();

        // Check solver invoices
        address[] memory solverInvoices = invoiceManager.getSolverInvoices(solver.pub);
        assertEq(solverInvoices.length, 1, "Solver 1 should have one invoice");
        assertEq(solverInvoices[0], sessionKey.pub, "Solver 1 invoice should match");

        // Check solver2 invoices
        address[] memory solver2Invoices = invoiceManager.getSolverInvoices(solver2.pub);
        assertEq(solver2Invoices.length, 1, "Solver 2 should have one invoice");
        assertEq(solver2Invoices[0], sessionKey2.pub, "Solver 2 invoice should match");
    }

    function test_updateSolverFee_success_switchToCustom() public withSetupInvoiceManager {
        // Start with default solver
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            "Test Solver",
            ISolverManager.FeeType.PERCENTAGE,
            50, // 0.5% orchestrator fee
            ISolverManager.FeeType.PERCENTAGE,
            20 // 0.2% solver fee
        );

        // Update to custom fee
        uint256 newCustomFee = 80; // 0.8 USDC

        vm.expectEmit(true, false, false, true);
        emit SolverFeeUpdated(solver.pub, ISolverManager.FeeType.FIXED, 20, newCustomFee);

        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, ISolverManager.FeeType.FIXED, newCustomFee);

        // Verify fee is updated
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);
        assertEq(solverData.solverFeeValue, newCustomFee, "Solver fee value should be updated to custom amount");
    }

    function test_updateSolverFee_success_switchFeeTypeAndZeroPercent() public withSetupInvoiceManager {
        // Start with custom solver
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            "Test Solver",
            ISolverManager.FeeType.FIXED,
            10, // 10 cents orchestrator fee
            ISolverManager.FeeType.FIXED,
            5000
        );

        // Update to percentage fee of 0 basis points (0%)
        vm.expectEmit(true, false, false, true);
        emit SolverFeeUpdated(solver.pub, ISolverManager.FeeType.PERCENTAGE, 5000, 0);

        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, ISolverManager.FeeType.PERCENTAGE, 0);

        // Verify fee is updated (9 return values now)
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);

        assertEq(
            uint256(solverData.solverFeeType), uint256(ISolverManager.FeeType.PERCENTAGE), "Should be PERCENTAGE type"
        );
        assertEq(solverData.solverFeeValue, 0, "Fee should be updated to 0 basis points");
    }

    /*//////////////////////////////////////////////////////////////
                    FEE RECEIVER MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setProtocolFeeReceiver_success() public withSampleInvoice {
        address newProtocolFeeReceiver = makeAddr("newProtocolFeeReceiver");

        vm.prank(feeManager.pub);
        invoiceManager.setProtocolFeeReceiver(newProtocolFeeReceiver);

        // Create new invoice after changing fee receiver
        bytes32 newBidHash = keccak256("new_bid");
        address newSessionKey = makeAddr("newSessionKey");

        vm.prank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), newSessionKey, solver.pub, newBidHash);
        invoiceManager.createInvoice(createInvoiceData);

        // Mint tokens for settlement
        _mintTokensToInvoiceManager();

        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(newSessionKey);
        uint256 initialNewReceiverBalance = testUSDC.balanceOf(newProtocolFeeReceiver);

        // Settle invoice
        _settleInvoiceAsSettler(newSessionKey);

        // New receiver should get protocol fees
        assertEq(testUSDC.balanceOf(newProtocolFeeReceiver), initialNewReceiverBalance + invoice.fees.protocolFee);
    }

    function test_setProtocolFeeReceiver_success_affectsNewInvoicesOnly() public withSampleInvoice {
        address newProtocolFeeReceiver = makeAddr("newProtocolFeeReceiver");

        // Get original invoice - it should have old protocol fee receiver snapshotted
        (InvoiceManager.Invoice memory originalInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        address oldProtocolFeeReceiver = originalInvoice.fees.protocolFeeReceiver;

        // Update protocol fee receiver
        vm.prank(feeManager.pub);
        invoiceManager.setProtocolFeeReceiver(newProtocolFeeReceiver);

        // Original invoice should still have OLD protocol fee receiver (snapshotted)
        (InvoiceManager.Invoice memory existingInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(
            existingInvoice.fees.protocolFeeReceiver,
            oldProtocolFeeReceiver,
            "Existing invoice should keep old protocol fee receiver"
        );

        // Create new invoice - should use NEW protocol fee receiver
        bytes32 newBidHash = keccak256("new_bid");
        address newSessionKey = makeAddr("newSessionKey");

        vm.prank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), newSessionKey, solver.pub, newBidHash);
        invoiceManager.createInvoice(createInvoiceData);

        // New invoice should have new protocol fee receiver
        (InvoiceManager.Invoice memory newInvoice,) = invoiceManager.getInvoice(newSessionKey);
        assertEq(
            newInvoice.fees.protocolFeeReceiver,
            newProtocolFeeReceiver,
            "New invoice should use new protocol fee receiver"
        );

        // Mint tokens and settle the new invoice
        _mintTokensToInvoiceManager();
        uint256 initialNewReceiverBalance = testUSDC.balanceOf(newProtocolFeeReceiver);

        _settleInvoiceAsSettler(newSessionKey);

        // New receiver should get protocol fees from new invoice
        assertEq(
            testUSDC.balanceOf(newProtocolFeeReceiver),
            initialNewReceiverBalance + newInvoice.fees.protocolFee,
            "New receiver should get protocol fees"
        );
    }

    function test_setProtocolFeeReceiver_revertIf_notFeeManagerRole() public withSetupInvoiceManager {
        address newProtocolFeeReceiver = makeAddr("newProtocolFeeReceiver");

        vm.prank(alice.pub); // Not fee manager
        vm.expectRevert(); // Should revert due to missing FEE_MANAGER_ROLE
        invoiceManager.setProtocolFeeReceiver(newProtocolFeeReceiver);
    }

    function test_setProtocolFeeReceiver_revertIf_invalidAddress() public withSetupInvoiceManager {
        vm.prank(feeManager.pub);
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        invoiceManager.setProtocolFeeReceiver(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                      VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_calculateInvoiceFees_success() public withSampleInvoice {
        (uint256 protocolFee, uint256 orchestratorFee, uint256 solverFee, uint256 totalFees) =
            invoiceManager.calculateInvoiceFees(sessionKey.pub);

        // Verify fees are greater than zero
        assertGt(protocolFee, 0, "Protocol fee should be greater than 0");
        assertGt(orchestratorFee, 0, "Orchestrator fee should be greater than 0");
        assertGt(solverFee, 0, "Solver fee should be greater than 0");
        assertEq(totalFees, protocolFee + orchestratorFee + solverFee, "Total should equal sum");
    }

    function test_calculateInvoiceFees_revertIf_invoiceNotFound() public withSetupInvoiceManager {
        address nonExistentSessionKey = makeAddr("nonExistentSessionKey");

        _toRevert(InvoiceManager.IM_InvoiceNotFound.selector, hex"");
        invoiceManager.calculateInvoiceFees(nonExistentSessionKey);
    }

    function test_isInvoiceSettleable_success_false_insufficientBalance() public withOnboardedSolvers {
        // Create invoice without minting tokens to contract
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        bool settleable = invoiceManager.isInvoiceSettleable(sessionKey.pub);
        assertFalse(settleable, "Invoice should not be settleable without sufficient balance");
    }

    function test_isInvoiceSettleable_false_invoiceNotFound() public withOnboardedSolvers {
        assertFalse(invoiceManager.isInvoiceSettleable(address(0)), "Should return false for missing invoice");
    }

    function test_isInvoiceSettleable_false_notFullyCredited() public withSampleInvoice {
        // invoice exists but not credited yet
        bool settleable = invoiceManager.isInvoiceSettleable(sessionKey.pub);
        assertFalse(settleable, "Invoice should not be settleable until credited");
    }

    function test_isInvoiceSettleable_false_insufficientBalance() public withSampleInvoice {
        _creditTokensToInvoice(sessionKey.pub);

        // Drain contract of USDC to cause failure
        deal(address(testUSDC), address(invoiceManager), 0);

        bool settleable = invoiceManager.isInvoiceSettleable(sessionKey.pub);
        assertFalse(settleable, "Should return false if insufficient contract balance");
    }

    function test_isInvoiceSettleable_true_fullyCreditedAndSufficientBalance() public withSampleInvoice {
        _creditTokensToInvoice(sessionKey.pub);
        bool settleable = invoiceManager.isInvoiceSettleable(sessionKey.pub);
        assertTrue(settleable, "Should return true when fully credited and sufficient balance");
    }

    function test_getInvoiceByBidHash_success() public withSampleInvoice {
        address sessionKey_ = invoiceManager.getInvoiceByBidHash(DEFAULT_BID_HASH);
        assertEq(sessionKey_, sessionKey.pub, "Should return correct session key for bid hash");
    }

    function test_getInvoiceByBidHash_revertIf_bidHashNotFound() public withSetupInvoiceManager {
        bytes32 nonExistentBidHash = keccak256("nonExistentBidHash");

        _toRevert(InvoiceManager.IM_InvoiceNotFound.selector, hex"");
        invoiceManager.getInvoiceByBidHash(nonExistentBidHash);
    }

    function test_getMultipleInvoices_mixedExistingAndMissing() public withOnboardedSolvers {
        address[] memory sessionKeys = _createMultipleInvoices(3);

        // delete one invoice to simulate partial existence
        vm.prank(settler.pub);
        invoiceManager.cancelInvoice(sessionKeys[1], "Removed mid-batch");

        (InvoiceManager.Invoice[] memory invoices_, InvoiceManager.InvoiceTokenData[][] memory tokenData_) =
            invoiceManager.getMultipleInvoices(sessionKeys);

        assertEq(invoices_.length, 3);
        assertEq(tokenData_.length, 3);

        // first exists
        assertGt(invoices_[0].createdAt, 0, "Invoice[0] should exist");
        // second should be empty (cancelled)
        assertEq(invoices_[1].createdAt, 0, "Invoice[1] should be empty");
        // third exists
        assertGt(invoices_[2].createdAt, 0, "Invoice[2] should exist");
    }

    /*//////////////////////////////////////////////////////////////
                  EMERGENCY WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_emergencyWithdraw_success() public withSetupInvoiceManager {
        uint256 withdrawAmount = 1000e6;
        testUSDC.mint(address(invoiceManager), withdrawAmount);

        uint256 initialBalance = testUSDC.balanceOf(deployer.pub);

        vm.prank(deployer.pub); // deployer has DEFAULT_ADMIN_ROLE
        invoiceManager.emergencyWithdraw(address(testUSDC), withdrawAmount);

        assertEq(testUSDC.balanceOf(deployer.pub), initialBalance + withdrawAmount, "Should transfer tokens to admin");
        assertEq(testUSDC.balanceOf(address(invoiceManager)), 0, "Contract should have no tokens left");
    }

    function test_emergencyWithdraw_success_partialAmount() public withSetupInvoiceManager {
        uint256 mintAmount = 1000e6;
        uint256 withdrawAmount = 600e6;
        testUSDC.mint(address(invoiceManager), mintAmount);

        uint256 initialBalance = testUSDC.balanceOf(deployer.pub);

        vm.prank(deployer.pub);
        invoiceManager.emergencyWithdraw(address(testUSDC), withdrawAmount);

        assertEq(testUSDC.balanceOf(deployer.pub), initialBalance + withdrawAmount, "Should transfer partial amount");
        assertEq(
            testUSDC.balanceOf(address(invoiceManager)), mintAmount - withdrawAmount, "Contract should retain remainder"
        );
    }

    function test_emergencyWithdraw_revertIf_notDefaultAdminRole() public withSetupInvoiceManager {
        uint256 withdrawAmount = 1000e6;
        testUSDC.mint(address(invoiceManager), withdrawAmount);

        vm.prank(alice.pub); // Not admin
        vm.expectRevert(); // Should revert due to missing DEFAULT_ADMIN_ROLE
        invoiceManager.emergencyWithdraw(address(testUSDC), withdrawAmount);
    }

    /*//////////////////////////////////////////////////////////////
              TOKEN WHITELIST MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addTokenToWhitelist_success() public withSetupInvoiceManager {
        address newToken = makeAddr("newToken");

        vm.expectEmit(true, true, false, false);
        emit TokenWhitelisted(newToken, deployer.pub);

        vm.prank(deployer.pub);
        invoiceManager.addTokenToWhitelist(newToken);

        assertTrue(invoiceManager.isTokenWhitelisted(newToken), "Token should be whitelisted");
    }

    function test_addTokenToWhitelist_revertIf_invalidAddress() public withSetupInvoiceManager {
        vm.prank(deployer.pub);
        _toRevert(TokenManager.TM_InvalidAddress.selector, hex"");
        invoiceManager.addTokenToWhitelist(address(0));
    }

    function test_addTokenToWhitelist_revertIf_tokenAlreadyWhitelisted() public withSetupInvoiceManager {
        vm.prank(deployer.pub);
        _toRevert(TokenManager.TM_TokenAlreadyWhitelisted.selector, abi.encode(address(testUSDC)));
        invoiceManager.addTokenToWhitelist(address(testUSDC));
    }

    function test_removeTokenFromWhitelist_success() public withSetupInvoiceManager {
        vm.expectEmit(true, true, false, false);
        emit TokenRemovedFromWhitelist(address(testUSDC), deployer.pub);

        vm.prank(deployer.pub);
        invoiceManager.removeTokenFromWhitelist(address(testUSDC));

        assertFalse(invoiceManager.isTokenWhitelisted(address(testUSDC)), "Token should be removed from whitelist");
    }

    function test_removeTokenFromWhitelist_revertIf_tokenNotWhitelisted() public withSetupInvoiceManager {
        address nonWhitelistedToken = makeAddr("nonWhitelistedToken");

        vm.prank(deployer.pub);
        _toRevert(TokenManager.TM_TokenNotWhitelisted.selector, abi.encode(nonWhitelistedToken));
        invoiceManager.removeTokenFromWhitelist(nonWhitelistedToken);
    }

    function test_addTokensToWhitelist_success() public withSetupInvoiceManager {
        address[] memory newTokens = new address[](2);
        newTokens[0] = makeAddr("newToken1");
        newTokens[1] = makeAddr("newToken2");

        vm.prank(deployer.pub);
        invoiceManager.addTokensToWhitelist(newTokens);

        assertTrue(invoiceManager.isTokenWhitelisted(newTokens[0]), "First token should be whitelisted");
        assertTrue(invoiceManager.isTokenWhitelisted(newTokens[1]), "Second token should be whitelisted");
    }

    function test_getWhitelistedTokens_success() public withSetupInvoiceManager {
        address[] memory whitelistedTokens = invoiceManager.getWhitelistedTokens();
        assertEq(whitelistedTokens.length, 4, "Should return all whitelisted tokens");

        uint256 count = invoiceManager.getWhitelistedTokensCount();
        assertEq(count, 4, "Count should match array length");
    }

    /*//////////////////////////////////////////////////////////////
                          CREDIBLE ACCOUNT ROLE TESTS
      //////////////////////////////////////////////////////////////*/

    function test_grantCredibleAccountRole_success() public withSetupInvoiceManager {
        // Verify role not granted initially
        assertFalse(invoiceManager.hasRole(invoiceManager.CREDIBLE_ACCOUNT_ROLE(), newAccount));

        // Grant role as admin
        vm.prank(deployer.pub);
        invoiceManager.grantCredibleAccountRole(newAccount);

        // Verify role granted
        assertTrue(invoiceManager.hasRole(invoiceManager.CREDIBLE_ACCOUNT_ROLE(), newAccount));
    }

    function test_grantCredibleAccountRole_revertIf_notAdmin() public withSetupInvoiceManager {
        vm.startPrank(solver.pub); // Not admin
        _toRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            abi.encode(solver.pub, invoiceManager.DEFAULT_ADMIN_ROLE())
        );
        invoiceManager.grantCredibleAccountRole(newAccount);
    }

    function test_revokeCredibleAccountRole_success() public withSetupInvoiceManager {
        // Grant role first
        vm.prank(deployer.pub);
        invoiceManager.grantCredibleAccountRole(newAccount);
        assertTrue(invoiceManager.hasRole(invoiceManager.CREDIBLE_ACCOUNT_ROLE(), newAccount));

        // Revoke role
        vm.prank(deployer.pub);
        invoiceManager.revokeCredibleAccountRole(newAccount);

        // Verify role revoked
        assertFalse(invoiceManager.hasRole(invoiceManager.CREDIBLE_ACCOUNT_ROLE(), newAccount));
    }

    /*//////////////////////////////////////////////////////////////
                              SETTLER ROLE TESTS
      //////////////////////////////////////////////////////////////*/

    function test_grantSettlerRole_success() public withSetupInvoiceManager {
        assertFalse(invoiceManager.hasRole(invoiceManager.SETTLER_ROLE(), newAccount));

        vm.prank(deployer.pub);
        invoiceManager.grantSettlerRole(newAccount);

        assertTrue(invoiceManager.hasRole(invoiceManager.SETTLER_ROLE(), newAccount));
    }

    function test_revokeSettlerRole_success() public withSetupInvoiceManager {
        // Grant first
        vm.prank(deployer.pub);
        invoiceManager.grantSettlerRole(newAccount);

        // Revoke
        vm.prank(deployer.pub);
        invoiceManager.revokeSettlerRole(newAccount);

        assertFalse(invoiceManager.hasRole(invoiceManager.SETTLER_ROLE(), newAccount));
    }

    /*//////////////////////////////////////////////////////////////
                          FEE MANAGER ROLE TESTS
      //////////////////////////////////////////////////////////////*/

    function test_grantFeeManagerRole_success() public withSetupInvoiceManager {
        assertFalse(invoiceManager.hasRole(invoiceManager.FEE_MANAGER_ROLE(), newAccount));

        vm.prank(deployer.pub);
        invoiceManager.grantFeeManagerRole(newAccount);

        assertTrue(invoiceManager.hasRole(invoiceManager.FEE_MANAGER_ROLE(), newAccount));
    }

    function test_revokeFeeManagerRole_success() public withSetupInvoiceManager {
        vm.prank(deployer.pub);
        invoiceManager.grantFeeManagerRole(newAccount);

        vm.prank(deployer.pub);
        invoiceManager.revokeFeeManagerRole(newAccount);

        assertFalse(invoiceManager.hasRole(invoiceManager.FEE_MANAGER_ROLE(), newAccount));
    }

    function test_feeManagerRole_canUpdateFees() public withSetupInvoiceManager {
        // Grant fee manager role
        vm.startPrank(deployer.pub);
        invoiceManager.grantFeeManagerRole(newAccount);

        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            "Solver 1",
            ISolverManager.FeeType.PERCENTAGE,
            50, // 0.5% orchestrator fee
            ISolverManager.FeeType.PERCENTAGE,
            20 // 0.2% solver fee
        );
        vm.stopPrank();
        // Fee manager should be able to update solver fees
        vm.prank(newAccount);
        invoiceManager.updateSolverFee(solver.pub, ISolverManager.FeeType.FIXED, 100); // 100 cents = $1.00

        // Verify fee updated
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);

        assertEq(uint256(solverData.solverFeeType), uint256(ISolverManager.FeeType.FIXED), "Solver fee should be FIXED");
        assertEq(solverData.solverFeeValue, 100, "Solver fee should be 100 cents");
    }

    /*//////////////////////////////////////////////////////////////
                          SOLVER MANAGER ROLE TESTS
      //////////////////////////////////////////////////////////////*/

    function test_grantSolverManagerRole_success() public withSetupInvoiceManager {
        assertFalse(invoiceManager.hasRole(invoiceManager.SOLVER_MANAGER_ROLE(), newAccount));

        vm.prank(deployer.pub);
        invoiceManager.grantSolverManagerRole(newAccount);

        assertTrue(invoiceManager.hasRole(invoiceManager.SOLVER_MANAGER_ROLE(), newAccount));
    }

    function test_revokeSolverManagerRole_success() public withSetupInvoiceManager {
        vm.prank(deployer.pub);
        invoiceManager.grantSolverManagerRole(newAccount);

        vm.prank(deployer.pub);
        invoiceManager.revokeSolverManagerRole(newAccount);

        assertFalse(invoiceManager.hasRole(invoiceManager.SOLVER_MANAGER_ROLE(), newAccount));
    }

    function test_solverManagerRole_canManageSolvers() public withSetupInvoiceManager {
        address newSolver = makeAddr("newSolver");

        // Grant solver manager role
        vm.prank(deployer.pub);
        invoiceManager.grantSolverManagerRole(newAccount);

        // Solver manager should be able to onboard solvers
        vm.prank(newAccount);
        invoiceManager.onboardSolver(
            newSolver,
            newSolver,
            feeReceiver.pub,
            "New Solver",
            ISolverManager.FeeType.PERCENTAGE,
            50, // 0.5% orchestrator fee
            ISolverManager.FeeType.PERCENTAGE,
            20 // 0.2% solver fee
        );

        // Verify solver onboarded
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(newSolver);
        assertEq(solverData.name, "New Solver", "Should match correct solver name");
        assertTrue(solverData.isActive, "Solver should be active");
        // Check fee structure (assuming the test onboards with specific fees)
        assertEq(
            uint256(solverData.orchestratorFeeType),
            uint256(ISolverManager.FeeType.PERCENTAGE),
            "Orchestrator fee should be PERCENTAGE"
        );
        assertEq(solverData.orchestratorFeeValue, 50, "Orchestrator fee value should be 50 basis points");
        assertEq(
            uint256(solverData.solverFeeType),
            uint256(ISolverManager.FeeType.PERCENTAGE),
            "Solver fee should be PERCENTAGE"
        );
        assertEq(solverData.solverFeeValue, 20, "Solver fee value should be 20 basis points");
    }

    /*//////////////////////////////////////////////////////////////
                          ROLE ENFORCEMENT TESTS
      //////////////////////////////////////////////////////////////*/

    function test_createInvoice_requiresCredibleAccountRole() public withSetupInvoiceManager {
        vm.startPrank(newAccount); // No role granted
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        _toRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            abi.encode(newAccount, invoiceManager.CREDIBLE_ACCOUNT_ROLE())
        );
        invoiceManager.createInvoice(createInvoiceData);
    }

    function test_settleInvoice_requiresSettlerRoleOrSmartWallet() public withSampleInvoice {
        vm.prank(newAccount); // No role, not smart wallet
        _toRevert(InvoiceManager.IM_UnauthorizedSettler.selector, abi.encode(newAccount, sessionKey.pub));
        invoiceManager.settleInvoice(sessionKey.pub);
    }

    function test_onboardSolver_requiresSolverManagerRole() public withSetupInvoiceManager {
        address newSolver = makeAddr("newSolver");

        vm.startPrank(newAccount); // No role
        _toRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            abi.encode(newAccount, invoiceManager.SOLVER_MANAGER_ROLE())
        );
        invoiceManager.onboardSolver(
            newSolver,
            newSolver,
            feeReceiver.pub,
            "New Solver",
            ISolverManager.FeeType.PERCENTAGE,
            50,
            ISolverManager.FeeType.PERCENTAGE,
            20
        );
    }

    function test_updateSolverFee_requiresFeeManagerRole() public withSetupInvoiceManager {
        vm.startPrank(newAccount); // No role
        _toRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            abi.encode(newAccount, invoiceManager.FEE_MANAGER_ROLE())
        );
        invoiceManager.updateSolverFee(solver.pub, ISolverManager.FeeType.PERCENTAGE, 50);
    }

    /*//////////////////////////////////////////////////////////////
                      CREDIT TOKENS TO INVOICE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_creditTokensToInvoice_success() public withSampleInvoice {
        address sessionKey = sessionKey.pub;

        vm.expectEmit(true, true, false, true);
        emit TokensCreditedToInvoice(
            sessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT, DEFAULT_USDC_AMOUNT, DEFAULT_USDC_AMOUNT
        );

        vm.prank(credibleAccount.pub);
        invoiceManager.creditTokensToInvoice(sessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT);

        // Verify token is credited
        (, InvoiceManager.InvoiceTokenData[] memory tokens) = invoiceManager.getInvoice(sessionKey);
        bool found = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].token == address(testUSDC)) {
                assertEq(tokens[i].creditedAmount, DEFAULT_USDC_AMOUNT);
                found = true;
                break;
            }
        }
        assertTrue(found, "USDC should be found and credited");
    }

    function test_creditTokensToInvoice_success_allTokens() public withSampleInvoice {
        address sessionKey = sessionKey.pub;

        // Single token support - credit USDC only
        vm.startPrank(credibleAccount.pub);
        invoiceManager.creditTokensToInvoice(sessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT);
        vm.stopPrank();

        // Verify token credited
        (, InvoiceManager.InvoiceTokenData[] memory tokens) = invoiceManager.getInvoice(sessionKey);
        assertEq(tokens.length, 1, "Should have 1 token");
        assertEq(tokens[0].creditedAmount, tokens[0].amount, "USDC should be fully credited");
    }

    function test_creditTokensToInvoice_revertIf_notCredibleAccountRole() public withSampleInvoice {
        vm.startPrank(alice.pub); // Not credible account role
        _toRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            abi.encode(alice.pub, invoiceManager.CREDIBLE_ACCOUNT_ROLE())
        );
        invoiceManager.creditTokensToInvoice(sessionKey.pub, address(testUSDC), DEFAULT_USDC_AMOUNT);
    }

    function test_creditTokensToInvoice_revertIf_invoiceNotFound() public withSetupInvoiceManager {
        address nonExistentSessionKey = makeAddr("nonExistentSessionKey");

        vm.prank(credibleAccount.pub);
        _toRevert(InvoiceManager.IM_InvoiceNotFound.selector, hex"");
        invoiceManager.creditTokensToInvoice(nonExistentSessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT);
    }

    function test_creditTokensToInvoice_revertIf_tokenNotFoundInInvoice() public withSampleInvoice {
        vm.prank(credibleAccount.pub);
        _toRevert(
            InvoiceManager.IM_TokenNotFoundInInvoice.selector, abi.encode(sessionKey.pub, address(nonWhitelistedToken))
        );
        invoiceManager.creditTokensToInvoice(sessionKey.pub, address(nonWhitelistedToken), 1000);
    }

    function test_creditTokensToInvoice_revertIf_tokenAlreadyCredited() public withSampleInvoice {
        address sessionKey = sessionKey.pub;

        vm.startPrank(credibleAccount.pub);
        // Credit once
        invoiceManager.creditTokensToInvoice(sessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT);

        // Try to credit again
        _toRevert(
            InvoiceManager.IM_TokenOverCredited.selector,
            abi.encode(sessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT, DEFAULT_USDC_AMOUNT * 2)
        );
        invoiceManager.creditTokensToInvoice(sessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT);
        vm.stopPrank();
    }

    function test_creditTokensToInvoice_revertIf_amountMismatch() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        uint256 wrongAmount = DEFAULT_USDC_AMOUNT + 1000;

        vm.prank(credibleAccount.pub);
        _toRevert(
            InvoiceManager.IM_TokenOverCredited.selector,
            abi.encode(sessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT, wrongAmount)
        );
        invoiceManager.creditTokensToInvoice(sessionKey, address(testUSDC), wrongAmount);
    }

    function test_settleInvoice_revertIf_tokensNotCredited() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        _mintTokensToInvoiceManager();

        // Don't credit tokens, try to settle directly
        vm.prank(settler.pub);
        _toRevert(
            InvoiceManager.IM_InvoiceNotFullyCredited.selector,
            abi.encode(sessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT, 0)
        );
        invoiceManager.settleInvoice(sessionKey);
    }

    function test_settleInvoice_revertIf_partiallyCredited() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        _mintTokensToInvoiceManager();

        // Credit only partial amount (half of required)
        uint256 partialAmount = DEFAULT_USDC_AMOUNT / 2;
        vm.prank(credibleAccount.pub);
        invoiceManager.creditTokensToInvoice(sessionKey, address(testUSDC), partialAmount);

        // Try to settle - should fail because not fully credited
        vm.prank(settler.pub);
        _toRevert(
            InvoiceManager.IM_InvoiceNotFullyCredited.selector,
            abi.encode(sessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT, partialAmount)
        );
        invoiceManager.settleInvoice(sessionKey);
    }

    function test_settleInvoice_success_afterFullCrediting() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        _mintTokensToInvoiceManager();
        _creditTokensToInvoice(sessionKey);

        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);
        (InvoiceManager.Invoice memory invoice,) = invoiceManager.getInvoice(sessionKey);
        uint256 totalFees = invoice.fees.protocolFee + invoice.fees.orchestratorFee + invoice.fees.solverFee;
        uint256 expectedAmount = DEFAULT_USDC_AMOUNT - totalFees + invoice.fees.solverFee;

        vm.prank(settler.pub);
        invoiceManager.settleInvoice(sessionKey);

        assertEq(testUSDC.balanceOf(solver.pub), initialSolverBalance + expectedAmount);
        assertFalse(invoiceManager.invoiceExists(sessionKey));
    }

    function test_settleInvoice_success_multiToken_feesFromFirstTokenOnly() public withOnboardedSolvers {
        address[] memory tokens = new address[](2);
        tokens[0] = address(testUSDC);
        tokens[1] = address(testDAI);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = DEFAULT_USDC_AMOUNT; // fee base token
        amounts[1] = DEFAULT_DAI_AMOUNT; // pass-through token

        TokenData[] memory multiTokenData = _createTokenData(tokens, amounts);

        _mintTokensToInvoiceManager();

        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, block.chainid, multiTokenData);

        vm.startPrank(credibleAccount.pub);
        invoiceManager.createInvoice(createInvoiceData);

        // Fully credit both tokens
        invoiceManager.creditTokensToInvoice(sessionKey.pub, tokens[0], amounts[0]);
        invoiceManager.creditTokensToInvoice(sessionKey.pub, tokens[1], amounts[1]);
        vm.stopPrank();

        // Snapshot solver balances before settlement
        uint256 solverUSDCBefore = IERC20(tokens[0]).balanceOf(solver.pub);
        uint256 solverDAIBefore = IERC20(tokens[1]).balanceOf(solver.pub);

        vm.prank(settler.pub);
        invoiceManager.settleInvoice(sessionKey.pub);

        // Check invoice removed
        bool exists = invoiceManager.invoiceExists(sessionKey.pub);
        assertFalse(exists, "Invoice should be deleted after settlement");

        // Check fees taken only from token[0] (USDC)
        (uint256 protocolFee, uint256 orchestratorFee, uint256 solverFee, uint256 totalFees) =
            _calculateExpectedTotalFees(solver.pub, tokens[0], amounts[0]);

        uint256 solverUSDCExpected = solverUSDCBefore + (amounts[0] - totalFees + solverFee);
        uint256 solverDAIExpected = solverDAIBefore + amounts[1];

        assertEq(IERC20(tokens[0]).balanceOf(solver.pub), solverUSDCExpected, "USDC after fees");
        assertEq(IERC20(tokens[1]).balanceOf(solver.pub), solverDAIExpected, "DAI full amount, no fee taken");
    }

    function test_settleInvoice_reverts_ifAnyTokenNotCredited() public withOnboardedSolvers {
        // Arrange
        address[] memory tokens = new address[](2);
        tokens[0] = address(testUSDC);
        tokens[1] = address(testDAI);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = DEFAULT_USDC_AMOUNT;
        amounts[1] = DEFAULT_DAI_AMOUNT;

        TokenData[] memory multiTokenData = _createTokenData(tokens, amounts);
        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, block.chainid, multiTokenData);

        _mintTokensToInvoiceManager();

        vm.startPrank(credibleAccount.pub);
        invoiceManager.createInvoice(createInvoiceData);

        // Credit only the first token (simulate missing second token)
        invoiceManager.creditTokensToInvoice(sessionKey.pub, tokens[0], amounts[0]);
        vm.stopPrank();

        // Act + Assert: should revert because DAI not yet credited
        vm.startPrank(settler.pub);
        vm.expectRevert(); // IM_InvoiceNotFullyCredited
        invoiceManager.settleInvoice(sessionKey.pub);
        vm.stopPrank();
    }

    function test_getInvoicePaymentStatus_success_nothingCredited() public withSampleInvoice {
        (address[] memory tokens, uint256[] memory expectedAmounts, uint256[] memory creditedAmounts, bool isFullyPaid)
        = invoiceManager.getInvoicePaymentStatus(sessionKey.pub);

        assertEq(tokens.length, 1, "Should have 1 token (USDC only)");
        assertFalse(isFullyPaid);
        for (uint256 i = 0; i < tokens.length; i++) {
            assertGt(expectedAmounts[i], 0);
            assertEq(creditedAmounts[i], 0);
        }
    }

    function test_getInvoicePaymentStatus_success_fullyCredited() public withSampleInvoice {
        _creditTokensToInvoice(sessionKey.pub);

        (,,, bool isFullyPaid) = invoiceManager.getInvoicePaymentStatus(sessionKey.pub);
        assertTrue(isFullyPaid);
    }

    // Balance Check Tests (IM_InsufficientContractBalance)
    function test_settleInvoice_revertIf_insufficientContractBalance() public withSampleInvoice {
        _creditTokensToInvoice(sessionKey.pub);

        // Drain contract balance (simulate emergency withdraw or token issue)
        uint256 contractBalance = testUSDC.balanceOf(address(invoiceManager));
        vm.prank(deployer.pub);
        invoiceManager.emergencyWithdraw(address(testUSDC), contractBalance);

        // Attempt to settle should fail due to insufficient balance
        vm.expectRevert(
            abi.encodeWithSelector(
                InvoiceManager.IM_InsufficientContractBalance.selector, address(testUSDC), DEFAULT_USDC_AMOUNT, 0
            )
        );
        vm.prank(deployer.pub);
        invoiceManager.settleInvoice(sessionKey.pub);
    }

    function test_settleInvoice_revertIf_balanceExactlyOneLessThanRequired() public withSampleInvoice {
        _creditTokensToInvoice(sessionKey.pub);

        // Contract has 10x the amount, so withdraw excess to leave exactly 1 wei less than needed
        uint256 contractBalance = testUSDC.balanceOf(address(invoiceManager));
        uint256 excessBalance = contractBalance - DEFAULT_USDC_AMOUNT + 1; // Leave 1 wei less than needed
        vm.prank(deployer.pub);
        invoiceManager.emergencyWithdraw(address(testUSDC), excessBalance);

        uint256 newBalance = testUSDC.balanceOf(address(invoiceManager));

        // Attempt to settle should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                InvoiceManager.IM_InsufficientContractBalance.selector,
                address(testUSDC),
                DEFAULT_USDC_AMOUNT,
                newBalance
            )
        );
        vm.prank(deployer.pub);
        invoiceManager.settleInvoice(sessionKey.pub);
    }

    function test_settleInvoice_success_balanceExactlyEqualToRequired() public withSampleInvoice {
        _creditTokensToInvoice(sessionKey.pub);

        // Contract has 10x the amount, so withdraw excess to leave exactly what's needed
        uint256 contractBalance = testUSDC.balanceOf(address(invoiceManager));
        uint256 excessBalance = contractBalance - DEFAULT_USDC_AMOUNT;
        vm.prank(deployer.pub);
        invoiceManager.emergencyWithdraw(address(testUSDC), excessBalance);

        // Verify balance equals exactly what's needed
        uint256 newBalance = testUSDC.balanceOf(address(invoiceManager));
        assertEq(newBalance, DEFAULT_USDC_AMOUNT, "Balance should equal required amount");

        // Settlement should succeed
        vm.prank(deployer.pub);
        bool success = invoiceManager.settleInvoice(sessionKey.pub);
        assertTrue(success);
    }

    /*//////////////////////////////////////////////////////////////
                         PROTOCOL FEE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setProtocolFee_success() public withSetupInvoiceManager {
        uint256 newFee = 10; // 10 cents

        vm.expectEmit(true, true, true, true);
        emit ProtocolFeeUpdated(5, newFee);

        vm.prank(feeManager.pub);
        invoiceManager.setProtocolFee(newFee);

        assertEq(invoiceManager.protocolFeeFixed(), newFee);
    }

    function test_setProtocolFee_success_affectsNewInvoicesOnly() public withSampleInvoice {
        // Get old fee from existing invoice
        (InvoiceManager.Invoice memory oldInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        uint256 oldProtocolFee = oldInvoice.fees.protocolFee;

        // Update protocol fee
        uint256 newFeeValue = 10; // 10 cents
        vm.prank(feeManager.pub);
        invoiceManager.setProtocolFee(newFeeValue);

        // Existing invoice should still have old fee
        (InvoiceManager.Invoice memory invoiceAfterUpdate,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(invoiceAfterUpdate.fees.protocolFee, oldProtocolFee, "Existing invoice fee should not change");

        // Create new invoice - should use new fee
        User memory newSessionKey = _createUser("NewSessionKey2");
        User memory newSmartWallet = _createUser("NewSmartWallet2");

        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = abi.encode(
            newSmartWallet.pub, newSessionKey.pub, solver.pub, keccak256("newBidHash"), block.chainid, defaultTokenData
        );
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        (InvoiceManager.Invoice memory newInvoice,) = invoiceManager.getInvoice(newSessionKey.pub);
        uint256 expectedNewFee = (newFeeValue * 10 ** 6) / 100; // 10 cents in USDC decimals
        assertEq(newInvoice.fees.protocolFee, expectedNewFee, "New invoice should use new fee");
    }

    function test_setProtocolFee_success_zeroFee() public withSetupInvoiceManager {
        vm.prank(feeManager.pub);
        invoiceManager.setProtocolFee(0);

        assertEq(invoiceManager.protocolFeeFixed(), 0);
    }

    function test_setProtocolFee_success_maxFee() public withSetupInvoiceManager {
        uint256 maxFee = 1000; // $10.00

        vm.prank(feeManager.pub);
        invoiceManager.setProtocolFee(maxFee);

        assertEq(invoiceManager.protocolFeeFixed(), maxFee);
    }

    function test_setProtocolFee_revertIf_notFeeManagerRole() public withSetupInvoiceManager {
        vm.prank(deployer.pub); // Not feeManager
        vm.expectRevert();
        invoiceManager.setProtocolFee(10);
    }

    function test_setProtocolFee_emitsEvent() public withSetupInvoiceManager {
        uint256 oldFee = invoiceManager.protocolFeeFixed();
        uint256 newFee = 10;

        vm.expectEmit(true, true, true, true);
        emit ProtocolFeeUpdated(oldFee, newFee);

        vm.prank(feeManager.pub);
        invoiceManager.setProtocolFee(newFee);
    }

    function test_setProtocolFee_revertIf_feeExceedsMaximum() public withSetupInvoiceManager {
        uint256 tooHighFee = 10001; // Exceeds MAX_FEE_FIXED (10000 = $100 in cents)

        vm.prank(feeManager.pub);
        _toRevert(InvoiceManager.IM_FeeValueTooHigh.selector, hex"");
        invoiceManager.setProtocolFee(tooHighFee);
    }

    function test_setProtocolFee_success_atMaximum() public withSetupInvoiceManager {
        uint256 maxFee = 10000; // Exactly MAX_FEE_FIXED ($100)

        vm.prank(feeManager.pub);
        invoiceManager.setProtocolFee(maxFee);

        assertEq(invoiceManager.protocolFeeFixed(), maxFee, "Protocol fee should be set to maximum");
    }

    /*//////////////////////////////////////////////////////////////
                        ORCHESTRATOR FEE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateOrchestratorFee_success() public withOnboardedSolvers {
        ISolverManager.FeeType newFeeType = ISolverManager.FeeType.PERCENTAGE;
        uint256 newFeeValue = 200; // 2%
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);

        vm.expectEmit(true, true, true, true);
        emit ISolverManager.OrchestratorFeeUpdated(
            solver.pub, solverData.orchestratorReceiver, newFeeType, 50, newFeeValue
        );

        vm.prank(feeManager.pub);
        invoiceManager.updateOrchestratorFee(solver.pub, newFeeType, newFeeValue);

        solverData = invoiceManager.getSolverData(solver.pub);
        assertEq(uint8(solverData.orchestratorFeeType), uint8(newFeeType));
        assertEq(solverData.orchestratorFeeValue, newFeeValue);
    }

    function test_updateOrchestratorFee_success_switchBetweenFeeTypes() public withOnboardedSolvers {
        // Start with PERCENTAGE (default is 50 bps = 0.5%)
        ISolverManager.Solver memory solverData1 = invoiceManager.getSolverData(solver.pub);
        assertEq(uint8(solverData1.orchestratorFeeType), uint8(ISolverManager.FeeType.PERCENTAGE));

        // Switch to FIXED
        vm.prank(feeManager.pub);
        invoiceManager.updateOrchestratorFee(solver.pub, ISolverManager.FeeType.FIXED, 25); // 25 cents

        ISolverManager.Solver memory solverData2 = invoiceManager.getSolverData(solver.pub);
        assertEq(uint8(solverData2.orchestratorFeeType), uint8(ISolverManager.FeeType.FIXED));
        assertEq(solverData2.orchestratorFeeValue, 25);

        // Switch back to PERCENTAGE
        vm.prank(feeManager.pub);
        invoiceManager.updateOrchestratorFee(solver.pub, ISolverManager.FeeType.PERCENTAGE, 100); // 1%

        ISolverManager.Solver memory solverData3 = invoiceManager.getSolverData(solver.pub);
        assertEq(uint8(solverData3.orchestratorFeeType), uint8(ISolverManager.FeeType.PERCENTAGE));
        assertEq(solverData3.orchestratorFeeValue, 100);
    }

    function test_updateOrchestratorFee_success_zeroFee() public withOnboardedSolvers {
        vm.prank(feeManager.pub);
        invoiceManager.updateOrchestratorFee(solver.pub, ISolverManager.FeeType.FIXED, 0);

        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);
        assertEq(solverData.orchestratorFeeValue, 0);
    }

    function test_updateOrchestratorFee_success_maxFee() public withOnboardedSolvers {
        uint256 maxFee = 10000; // 100% for percentage, or $100 for fixed

        vm.prank(feeManager.pub);
        invoiceManager.updateOrchestratorFee(solver.pub, ISolverManager.FeeType.PERCENTAGE, maxFee);

        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(solver.pub);
        assertEq(solverData.orchestratorFeeValue, maxFee);
    }

    function test_updateOrchestratorFee_revertIf_notFeeManagerRole() public withOnboardedSolvers {
        vm.prank(deployer.pub); // Not feeManager
        vm.expectRevert();
        invoiceManager.updateOrchestratorFee(solver.pub, ISolverManager.FeeType.PERCENTAGE, 100);
    }

    function test_updateOrchestratorFee_revertIf_invalidSolver() public withSetupInvoiceManager {
        address nonExistentSolver = address(0x9999);

        vm.prank(feeManager.pub);
        vm.expectRevert(SolverManager.SM_InvalidSolver.selector);
        invoiceManager.updateOrchestratorFee(nonExistentSolver, ISolverManager.FeeType.PERCENTAGE, 100);
    }

    function test_updateOrchestratorFee_revertIf_solverOffboarded() public withOnboardedSolvers {
        // Offboard solver
        vm.prank(deployer.pub);
        invoiceManager.offboardSolver(solver.pub);

        // Try to update fee should fail
        vm.prank(feeManager.pub);
        vm.expectRevert(SolverManager.SM_InvalidSolver.selector);
        invoiceManager.updateOrchestratorFee(solver.pub, ISolverManager.FeeType.PERCENTAGE, 100);
    }
}
