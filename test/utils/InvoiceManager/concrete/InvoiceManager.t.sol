// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {InvoiceManager} from "../../../../src/utils/InvoiceManager.sol";
import {InvoiceManagerTestUtils} from "../utils/InvoiceManagerTestUtils.sol";
import {TokenData} from "../../../../src/common/Structs.sol";

contract InvoiceManager_Concrete_Test is InvoiceManagerTestUtils {
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
        uint256 totalTokens,
        uint256 pulseFee,
        uint256 solverAmount
    );

    event InvoiceSettled(address indexed sessionKey, bytes32 indexed bidHash, address indexed solver);

    event InvoiceCancelled(address indexed sessionKey, string reason);

    event SolverOnboarded(address indexed solver, string name, uint256 pulseFee);

    event SolverOffboarded(address indexed solver);

    event SolverFeeUpdated(address indexed solver, uint256 oldFee, uint256 newFee);

    event FeeReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);

    event TokenWhitelisted(address indexed token, address indexed addedBy);

    event TokenRemovedFromWhitelist(address indexed token, address indexed removedBy);

    event TokensCreditedToInvoice(address indexed sessionKey, address indexed token, uint256 amount);

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

        InvoiceManager testManager = new InvoiceManager(
            deployer.pub, credibleAccount.pub, feeReceiver.pub, feeManager.pub, whitelistedTokenAddresses
        );

        // Verify roles are granted correctly
        assertTrue(testManager.hasRole(testManager.DEFAULT_ADMIN_ROLE(), deployer.pub));
        assertTrue(testManager.hasRole(testManager.CREDIBLE_ACCOUNT_ROLE(), credibleAccount.pub));
        assertTrue(testManager.hasRole(testManager.SETTLER_ROLE(), deployer.pub));
        assertTrue(testManager.hasRole(testManager.FEE_MANAGER_ROLE(), feeManager.pub));
        assertTrue(testManager.hasRole(testManager.SOLVER_MANAGER_ROLE(), deployer.pub));

        // Verify fee receiver is set
        assertEq(testManager.feeReceiver(), feeReceiver.pub);

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
            feeManager.pub,
            whitelistedTokenAddresses
        );
    }

    function test_constructor_revertIf_invalidCredibleAccount() public {
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        new InvoiceManager(
            deployer.pub,
            address(0), // Invalid credible account
            feeReceiver.pub,
            feeManager.pub,
            whitelistedTokenAddresses
        );
    }

    function test_constructor_revertIf_invalidFeeReceiver() public {
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        new InvoiceManager(
            deployer.pub,
            credibleAccount.pub,
            address(0), // Invalid fee receiver
            feeManager.pub,
            whitelistedTokenAddresses
        );
    }

    function test_constructor_revertIf_invalidFeeManager() public {
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        new InvoiceManager(
            deployer.pub,
            credibleAccount.pub,
            feeReceiver.pub,
            address(0), // Invalid fee manager
            whitelistedTokenAddresses
        );
    }

    function test_constructor_revertIf_emptyTokenWhitelist() public {
        address[] memory emptyTokens = new address[](0);

        _toRevert(InvoiceManager.IM_EmptyTokenWhitelist.selector, hex"");
        new InvoiceManager(deployer.pub, credibleAccount.pub, feeReceiver.pub, feeManager.pub, emptyTokens);
    }

    function test_constructor_revertIf_zeroAddressInTokenWhitelist() public {
        address[] memory tokensWithZero = new address[](2);
        tokensWithZero[0] = address(testUSDC);
        tokensWithZero[1] = address(0); // Invalid token address

        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        new InvoiceManager(deployer.pub, credibleAccount.pub, feeReceiver.pub, feeManager.pub, tokensWithZero);
    }

    function test_constructor_emitsTokenWhitelistedEvents() public {
        vm.startPrank(deployer.pub);

        // Expect events for each whitelisted token
        for (uint256 i; i < whitelistedTokenAddresses.length; ++i) {
            vm.expectEmit(true, true, false, false);
            emit TokenWhitelisted(whitelistedTokenAddresses[i], deployer.pub);
        }

        new InvoiceManager(
            deployer.pub, credibleAccount.pub, feeReceiver.pub, feeManager.pub, whitelistedTokenAddresses
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        CREATE INVOICE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_createInvoice_success() public withOnboardedSolvers {
        vm.startPrank(credibleAccount.pub);

        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        vm.expectEmit(true, true, true, true);
        emit InvoiceCreated(sessionKey.pub, DEFAULT_BID_HASH, solver.pub, defaultTokenData.length, 0);

        address returnedSessionKey = invoiceManager.createInvoice(createInvoiceData);

        // Verify return value
        assertEq(returnedSessionKey, sessionKey.pub);

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
        assertEq(invoice.pulseFee, 0);
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
        _toRevert(InvoiceManager.IM_TokenNotWhitelisted.selector, abi.encode(address(nonWhitelistedToken)));
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_createInvoice_revertIf_solverNotActive() public withSetupInvoiceManager {
        // Don't onboard solvers, so solver is not active
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        vm.startPrank(credibleAccount.pub);
        _toRevert(InvoiceManager.IM_SolverInactive.selector, hex"");
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_createInvoice_revertIf_emptyTokenData() public withOnboardedSolvers {
        TokenData[] memory emptyTokenData = new TokenData[](0);

        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, emptyTokenData);

        vm.startPrank(credibleAccount.pub);
        _toRevert(InvoiceManager.IM_EmptyTokenData.selector, hex"");
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
        vm.expectEmit(true, true, true, false);
        emit InvoiceSettled(sessionKey, DEFAULT_BID_HASH, solver.pub);
        vm.prank(settler.pub);
        invoiceManager.settleInvoice(sessionKey);
    }

    function test_settleInvoice_success_asSettler_transfersTokens() public withSampleInvoice {
        address sessionKey = sessionKey.pub;

        uint256 initialFeeReceiverUSDC = testUSDC.balanceOf(feeReceiver.pub);
        uint256 initialSolverUSDC = testUSDC.balanceOf(solver.pub);

        // Calculate expected fee dynamically
        uint256 expectedUSDCFee = _calculateExpectedFeeForToken(address(testUSDC), 0);
        uint256 expectedUSDCSolver = DEFAULT_USDC_AMOUNT - expectedUSDCFee;

        _settleInvoiceAsSettler(sessionKey);

        // Verify USDC transfers
        assertEq(testUSDC.balanceOf(feeReceiver.pub), initialFeeReceiverUSDC + expectedUSDCFee);
        assertEq(testUSDC.balanceOf(solver.pub), initialSolverUSDC + expectedUSDCSolver);
    }

    function test_settleInvoice_success_asSmartWallet() public withSampleInvoice {
        address sessionKey = sessionKey.pub;

        // Get initial balances
        uint256 initialFeeReceiverUSDC = testUSDC.balanceOf(feeReceiver.pub);
        uint256 initialSolverUSDC = testUSDC.balanceOf(solver.pub);

        // Mint tokens to contract
        _mintTokensToInvoiceManager();
        // Credit tokens before settlement
        _creditTokensToInvoice(sessionKey);
        vm.expectEmit(true, true, true, false);
        emit InvoiceSettled(sessionKey, DEFAULT_BID_HASH, solver.pub);
        vm.prank(settler.pub);
        invoiceManager.settleInvoice(sessionKey);

        // Verify invoice is deleted
        assertFalse(invoiceManager.invoiceExists(sessionKey));
        assertFalse(invoiceManager.bidHashExists(DEFAULT_BID_HASH));

        // Verify tokens were transferred
        assertGt(testUSDC.balanceOf(feeReceiver.pub), initialFeeReceiverUSDC);
        assertGt(testUSDC.balanceOf(solver.pub), initialSolverUSDC);
    }

    function test_settleInvoice_success_withHighFee() public withSetupInvoiceManager {
        _onboardDefaultSolvers();

        // Create invoice with solver2 (high fee: 50 cents)
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver2.pub, DEFAULT_BID_HASH);

        address sessionKey = invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Mint tokens to invoice manager
        _mintTokensToInvoiceManager();

        // Calculate expected fees: 50 cents for USDC = (50 * 10^6) / 100 = 500,000 (0.50 USDC)
        uint256 expectedUSDCFee = (HIGH_FEE_AMOUNT * 10 ** 6) / 100;
        uint256 expectedUSDCSolver = DEFAULT_USDC_AMOUNT - expectedUSDCFee;

        uint256 initialFeeReceiverUSDC = testUSDC.balanceOf(feeReceiver.pub);
        uint256 initialSolverUSDC = testUSDC.balanceOf(solver2.pub);

        _settleInvoiceAsSettler(sessionKey);

        // Verify higher fees were deducted
        assertEq(testUSDC.balanceOf(feeReceiver.pub), initialFeeReceiverUSDC + expectedUSDCFee);
        assertEq(testUSDC.balanceOf(solver2.pub), initialSolverUSDC + expectedUSDCSolver);
    }

    function test_settleInvoice_success_withSingleToken() public withOnboardedSolvers {
        // Create invoice with only one token
        TokenData[] memory singleTokenData = _createSingleTokenData(address(testUSDC), DEFAULT_USDC_AMOUNT);

        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, singleTokenData);

        address sessionKey = invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        _mintTokensToInvoiceManager();

        uint256 expectedFee = _calculateExpectedFeeForToken(address(testUSDC), 0);
        uint256 expectedSolverAmount = DEFAULT_USDC_AMOUNT - expectedFee;

        uint256 initialFeeReceiverBalance = testUSDC.balanceOf(feeReceiver.pub);
        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);

        // Credit tokens before settlement
        _creditTokensToInvoice(sessionKey);
        vm.expectEmit(true, true, true, false);
        emit InvoiceSettled(sessionKey, DEFAULT_BID_HASH, solver.pub);
        vm.prank(settler.pub);
        invoiceManager.settleInvoice(sessionKey);

        assertEq(testUSDC.balanceOf(feeReceiver.pub), initialFeeReceiverBalance + expectedFee);
        assertEq(testUSDC.balanceOf(solver.pub), initialSolverBalance + expectedSolverAmount);
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

        address sessionKey = invoiceManager.createInvoice(createInvoiceData);

        invoiceManager.creditTokensToInvoice(sessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT);
        invoiceManager.creditTokensToInvoice(sessionKey, address(testUSDT), DEFAULT_USDT_AMOUNT);
        invoiceManager.creditTokensToInvoice(sessionKey, address(testDAI), DEFAULT_DAI_AMOUNT);
        vm.stopPrank();

        testUSDC.mint(address(invoiceManager), DEFAULT_USDC_AMOUNT);
        testUSDT.mint(address(invoiceManager), DEFAULT_USDT_AMOUNT);
        testDAI.mint(address(invoiceManager), DEFAULT_DAI_AMOUNT - 1); // 1 wei short

        // Attempt to settle should revert when trying to transfer DAI
        vm.prank(settler.pub);
        _toRevert(
            InvoiceManager.IM_InsufficientContractBalance.selector,
            abi.encode(address(testDAI), DEFAULT_DAI_AMOUNT, DEFAULT_DAI_AMOUNT - 1)
        );
        invoiceManager.settleInvoice(sessionKey);
    }

    function test_settleInvoice_success_multipleInvoicesSameSolver() public withOnboardedSolvers {
        // Create multiple invoices for the same solver
        address[] memory sessionKeys = new address[](3);

        vm.startPrank(credibleAccount.pub);

        for (uint256 i; i < 3; ++i) {
            bytes32 bidHash = keccak256(abi.encodePacked("bid_hash_", i));
            address sessionKey = address(uint160(uint256(keccak256(abi.encodePacked("session_key_", i)))));

            bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey, solver.pub, bidHash);

            sessionKeys[i] = invoiceManager.createInvoice(createInvoiceData);
        }

        vm.stopPrank();

        _mintTokensToInvoiceManager();

        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);
        uint256 expectedSolverAmountPerInvoice =
            DEFAULT_USDC_AMOUNT - _calculateExpectedFeeForToken(address(testUSDC), 0);

        // Settle all invoices
        for (uint256 i; i < 3; ++i) {
            _settleInvoiceAsSettler(sessionKeys[i]);
        }

        // Verify solver received payments from all invoices
        assertEq(testUSDC.balanceOf(solver.pub), initialSolverBalance + (expectedSolverAmountPerInvoice * 3));
    }

    function test_settleInvoice_success_zeroFee() public withSetupInvoiceManager {
        // Onboard solver with zero fee
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(solver.pub, "Zero Fee Solver", 0);

        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        address sessionKey = invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        _mintTokensToInvoiceManager();

        uint256 initialFeeReceiverBalance = testUSDC.balanceOf(feeReceiver.pub);
        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);

        // When pulseFee = 0, contract calculates default fee (25 cents)
        uint256 expectedUSDCFee = _calculateExpectedFeeForToken(address(testUSDC), 0);
        uint256 expectedUSDTFee = _calculateExpectedFeeForToken(address(testUSDT), 0);
        uint256 expectedDAIFee = _calculateExpectedFeeForToken(address(testDAI), 0);

        // Start recording logs
        vm.recordLogs();

        _settleInvoiceAsSettler(sessionKey);

        // Get all recorded logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify we have the expected number of events
        // 3 TokensCreditedToInvoice + 3 TokenPaid + 1 InvoiceSettled = 7 events minimum
        assertGe(logs.length, 7, "Should have at least 7 events");

        // Find and verify TokensCreditedToInvoice events
        uint256 creditEventCount;
        uint256 paymentEventCount;
        uint256 settlementEventCount;

        for (uint256 i; i < logs.length; ++i) {
            // TokensCreditedToInvoice event signature
            if (logs[i].topics[0] == keccak256("TokensCreditedToInvoice(address,address,uint256)")) {
                creditEventCount++;
            }
            // TokenPaid event signature
            else if (logs[i].topics[0] == keccak256("TokenPaid(address,address,address,uint256,uint256,uint256)")) {
                paymentEventCount++;

                // Decode and verify TokenPaid event data
                address sessionKeyFromEvent = address(uint160(uint256(logs[i].topics[1])));
                address solverFromEvent = address(uint160(uint256(logs[i].topics[2])));
                address tokenFromEvent = address(uint160(uint256(logs[i].topics[3])));

                assertEq(sessionKeyFromEvent, sessionKey, "SessionKey should match");
                assertEq(solverFromEvent, solver.pub, "Solver should match");

                // Decode the data portion for amounts
                (uint256 totalTokens, uint256 pulseFee, uint256 solverAmount) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256));

                if (tokenFromEvent == address(testUSDC)) {
                    assertEq(totalTokens, DEFAULT_USDC_AMOUNT, "USDC total should match");
                    assertEq(pulseFee, expectedUSDCFee, "USDC fee should match");
                    assertEq(solverAmount, DEFAULT_USDC_AMOUNT - expectedUSDCFee, "USDC solver amount should match");
                } else if (tokenFromEvent == address(testUSDT)) {
                    assertEq(totalTokens, DEFAULT_USDT_AMOUNT, "USDT total should match");
                    assertEq(pulseFee, expectedUSDTFee, "USDT fee should match");
                    assertEq(solverAmount, DEFAULT_USDT_AMOUNT - expectedUSDTFee, "USDT solver amount should match");
                } else if (tokenFromEvent == address(testDAI)) {
                    assertEq(totalTokens, DEFAULT_DAI_AMOUNT, "DAI total should match");
                    assertEq(pulseFee, expectedDAIFee, "DAI fee should match");
                    assertEq(solverAmount, DEFAULT_DAI_AMOUNT - expectedDAIFee, "DAI solver amount should match");
                }
            }
            // InvoiceSettled event signature
            else if (logs[i].topics[0] == keccak256("InvoiceSettled(address,bytes32,address)")) {
                settlementEventCount++;

                // Verify settlement event data
                address sessionKeyFromEvent = address(uint160(uint256(logs[i].topics[1])));
                bytes32 bidHashFromEvent = logs[i].topics[2];
                address solverFromEvent = address(uint160(uint256(logs[i].topics[3])));

                assertEq(sessionKeyFromEvent, sessionKey, "Settlement sessionKey should match");
                assertEq(bidHashFromEvent, DEFAULT_BID_HASH, "Settlement bidHash should match");
                assertEq(solverFromEvent, solver.pub, "Settlement solver should match");
            }
        }

        // Verify we got the expected number of each event type
        assertEq(creditEventCount, 3, "Should have 3 TokensCreditedToInvoice events");
        assertEq(paymentEventCount, 3, "Should have 3 TokenPaid events");
        assertEq(settlementEventCount, 1, "Should have 1 InvoiceSettled event");

        // Fee receiver should get the calculated default fees
        assertEq(testUSDC.balanceOf(feeReceiver.pub), initialFeeReceiverBalance + expectedUSDCFee);
        // Solver should get amount minus fees
        assertEq(testUSDC.balanceOf(solver.pub), initialSolverBalance + (DEFAULT_USDC_AMOUNT - expectedUSDCFee));
    }

    function test_settleInvoice_success_maxFee() public withSetupInvoiceManager {
        // Onboard solver with max fee (1000 cents = 10.00 tokens)
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(solver.pub, "Max Fee Solver", 1000); // 1000 cents

        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        address sessionKey = invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        _mintTokensToInvoiceManager();

        // Calculate expected fee: 1000 cents for USDC = (1000 * 10^6) / 100 = 10,000,000 (10.00 USDC)
        uint256 expectedFee = (1000 * 10 ** 6) / 100;
        uint256 expectedSolverAmount = DEFAULT_USDC_AMOUNT - expectedFee;

        uint256 initialFeeReceiverBalance = testUSDC.balanceOf(feeReceiver.pub);
        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);

        _settleInvoiceAsSettler(sessionKey);

        assertEq(testUSDC.balanceOf(feeReceiver.pub), initialFeeReceiverBalance + expectedFee);
        assertEq(testUSDC.balanceOf(solver.pub), initialSolverBalance + expectedSolverAmount);
    }

    // Edge cases

    function test_settleInvoice_revertIf_solverDeactivatedAfterInvoiceCreation() public withSampleInvoice {
        address sessionKey = sessionKey.pub;

        // Deactivate solver after invoice creation
        vm.prank(solverManager.pub);
        invoiceManager.toggleSolverStatus(solver.pub);

        // Settlement should fail
        vm.prank(settler.pub);
        _toRevert(InvoiceManager.IM_SolverInactive.selector, hex"");
        invoiceManager.settleInvoice(sessionKey);
    }

    function test_settleInvoice_success_reactivatedSolverAfterDeactivation() public withSampleInvoice {
        address sessionKey = sessionKey.pub;

        // Deactivate then reactivate solver
        vm.prank(solverManager.pub);
        invoiceManager.toggleSolverStatus(solver.pub);

        vm.prank(solverManager.pub);
        invoiceManager.toggleSolverStatus(solver.pub);

        // Settlement should now succeed
        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);
        uint256 expectedAmount = DEFAULT_USDC_AMOUNT - _calculateExpectedFeeForToken(address(testUSDC), 0);

        _settleInvoiceAsSettler(sessionKey);

        assertEq(testUSDC.balanceOf(solver.pub), initialSolverBalance + expectedAmount);
        assertFalse(invoiceManager.invoiceExists(sessionKey));
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

    function test_cancelInvoice_success_emptyReason() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        string memory emptyReason = "";

        vm.expectEmit(true, false, false, true);
        emit InvoiceCancelled(sessionKey, emptyReason);

        vm.prank(settler.pub);
        invoiceManager.cancelInvoice(sessionKey, emptyReason);

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
        address newSessionKey = invoiceManager.createInvoice(createInvoiceData);
        assertEq(newSessionKey, sessionKey2.pub, "New invoice should be created successfully");
        vm.stopPrank();
    }

    function test_cancelInvoice_success_multipleCancellations() public withOnboardedSolvers {
        // Create multiple invoices
        vm.startPrank(credibleAccount.pub);

        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        address sessionKey = invoiceManager.createInvoice(createInvoiceData);

        bytes memory createInvoiceData2 =
            _createInvoiceData(address(scw2), sessionKey2.pub, solver.pub, SECOND_BID_HASH);

        address sessionKey2 = invoiceManager.createInvoice(createInvoiceData2);

        vm.stopPrank();

        // Cancel with different reasons
        vm.startPrank(settler.pub);

        vm.expectEmit(true, false, false, true);
        emit InvoiceCancelled(sessionKey, "First cancellation");
        invoiceManager.cancelInvoice(sessionKey, "First cancellation");

        vm.expectEmit(true, false, false, true);
        emit InvoiceCancelled(sessionKey2, "Second cancellation");
        invoiceManager.cancelInvoice(sessionKey2, "Second cancellation");

        vm.stopPrank();

        // Verify both are cancelled
        assertFalse(invoiceManager.invoiceExists(sessionKey), "First invoice should be deleted");
        assertFalse(invoiceManager.invoiceExists(sessionKey2), "Second invoice should be deleted");
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

    /*//////////////////////////////////////////////////////////////
                    SOLVER MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onboardSolver_success_defaultFee() public withSetupInvoiceManager {
        string memory solverName = "Default Fee Solver";
        uint256 defaultFee = 0; // Use calculated fee

        vm.expectEmit(true, false, false, true);
        emit SolverOnboarded(solver.pub, solverName, defaultFee);

        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(solver.pub, solverName, defaultFee);

        (string memory name, bool isActive,,, uint256 fee) = invoiceManager.getSolverData(solver.pub);

        assertEq(name, solverName, "Solver name should match");
        assertTrue(isActive, "Solver should be active");
        assertEq(fee, 0, "Fee should be 0 (default)");
    }

    function test_onboardSolver_success_customFee() public withSetupInvoiceManager {
        string memory solverName = "Custom Fee Solver";
        uint256 customFee = 750000; // 0.75 USDC

        vm.expectEmit(true, false, false, true);
        emit SolverOnboarded(solver.pub, solverName, customFee);

        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(solver.pub, solverName, customFee);

        (string memory name, bool isActive,,, uint256 fee) = invoiceManager.getSolverData(solver.pub);

        assertEq(name, solverName, "Solver name should match");
        assertTrue(isActive, "Solver should be active");
        assertEq(fee, customFee, "Fee should match custom amount");
    }

    function test_onboardSolver_success_emptyName() public withSetupInvoiceManager {
        string memory emptyName = "";
        uint256 feeAmount = 0; // Default fee

        vm.expectEmit(true, false, false, true);
        emit SolverOnboarded(solver.pub, emptyName, feeAmount);

        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(solver.pub, emptyName, feeAmount);

        (string memory name, bool isActive,,,) = invoiceManager.getSolverData(solver.pub);

        assertTrue(isActive, "Solver should be active");
        assertEq(name, emptyName, "Name should be empty");
    }

    function test_onboardSolver_success_longName() public withSetupInvoiceManager {
        string memory longName =
            "This is a very long solver name that contains multiple words and should test the string handling properly in the solver management system";
        uint256 fee = DEFAULT_FEE_AMOUNT;

        vm.expectEmit(true, false, false, true);
        emit SolverOnboarded(solver.pub, longName, fee);

        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(solver.pub, longName, DEFAULT_FEE_AMOUNT); // Use longName, not "Solver One"

        (string memory name, bool isActive,,,) = invoiceManager.getSolverData(solver.pub);

        assertTrue(isActive, "Solver should be active");
        assertEq(name, longName, "Name should match long name");
    }

    function test_onboardSolver_success_multipleSolvers() public withSetupInvoiceManager {
        vm.startPrank(solverManager.pub);

        // Onboard first solver
        invoiceManager.onboardSolver(solver.pub, "Solver One", DEFAULT_FEE_AMOUNT);
        // Onboard second solver
        invoiceManager.onboardSolver(solver2.pub, "Solver Two", HIGH_FEE_AMOUNT);

        vm.stopPrank();

        (string memory s1Name, bool isActive1,,, uint256 fee1) = invoiceManager.getSolverData(solver.pub);
        (string memory s2Name, bool isActive2,,, uint256 fee2) = invoiceManager.getSolverData(solver2.pub);

        // Verify both are active
        assertTrue(isActive1, "Solver 1 should be active");
        assertTrue(isActive2, "Solver 2 should be active");

        // Verify different fees
        assertEq(fee1, DEFAULT_FEE_AMOUNT, "Solver 1 fee should match");
        assertEq(fee2, HIGH_FEE_AMOUNT, "Solver 2 fee should match");
    }

    function test_onboardSolver_revertIf_notSolverManagerRole() public withSetupInvoiceManager {
        vm.prank(alice.pub); // Not solver manager
        vm.expectRevert(); // Should revert due to missing SOLVER_MANAGER_ROLE
        invoiceManager.onboardSolver(solver.pub, "Test Solver", DEFAULT_FEE_AMOUNT);
    }

    function test_onboardSolver_revertIf_invalidSolverAddress() public withSetupInvoiceManager {
        vm.prank(solverManager.pub);
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        invoiceManager.onboardSolver(address(0), "Test Solver", DEFAULT_FEE_AMOUNT);
    }

    function test_onboardSolver_revertIf_solverAlreadyActive() public withOnboardedSolvers {
        // Try to onboard solver again
        vm.prank(solverManager.pub);
        _toRevert(InvoiceManager.IM_SolverAlreadyExists.selector, hex"");
        invoiceManager.onboardSolver(solver.pub, "Duplicate Solver", DEFAULT_FEE_AMOUNT);
    }

    function test_offboardSolver_success() public withOnboardedSolvers {
        // Verify solver is active before offboarding
        (, bool isActivePre,,,) = invoiceManager.getSolverData(solver.pub);
        assertTrue(isActivePre, "Solver should be active");

        vm.expectEmit(true, false, false, false);
        emit SolverOffboarded(solver.pub);

        vm.prank(solverManager.pub);
        invoiceManager.offboardSolver(solver.pub);

        (string memory name, bool isActivePost,,, uint256 fee) = invoiceManager.getSolverData(solver.pub);

        // Verify solver data still exists but marked inactive
        assertEq(name, "", "Name should still exist");
        assertEq(fee, 0, "Fee should still exist");
        assertFalse(isActivePost, "Solver should be inactive");
    }

    function test_offboardSolver_success_withExistingInvoices() public withSampleInvoice {
        // Verify solver has invoices
        address[] memory solverInvoices = invoiceManager.getSolverInvoices(solver.pub);
        assertGt(solverInvoices.length, 0, "Solver should have invoices");

        vm.expectEmit(true, false, false, false);
        emit SolverOffboarded(solver.pub);

        vm.prank(solverManager.pub);
        invoiceManager.offboardSolver(solver.pub);

        // Verify solver is offboarded but invoices still exist
        (, bool isActive,,,) = invoiceManager.getSolverData(solver.pub);
        assertFalse(isActive, "Solver should not be active");
        assertTrue(invoiceManager.invoiceExists(sessionKey.pub), "Existing invoice should still exist");
    }

    function test_offboardSolver_success_allowsReOnboarding() public withOnboardedSolvers {
        // Offboard solver
        vm.prank(solverManager.pub);
        invoiceManager.offboardSolver(solver.pub);

        (, bool isActive1,,,) = invoiceManager.getSolverData(solver.pub);

        assertFalse(isActive1, "Solver should be inactive");

        // Re-onboard with different parameters
        string memory newName = "Re-onboarded Solver";
        uint256 newFee = HIGH_FEE_AMOUNT;

        vm.expectEmit(true, false, false, true);
        emit SolverOnboarded(solver.pub, newName, newFee);

        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(solver.pub, newName, newFee);

        // Verify solver is active with new parameters
        (string memory name, bool isActive2,,, uint256 fee) = invoiceManager.getSolverData(solver.pub);

        assertTrue(isActive2, "Solver should be active again");
        assertEq(name, newName, "Name should be updated");
        assertEq(fee, newFee, "Fee should be updated");
    }

    function test_offboardSolver_revertIf_notSolverManagerRole() public withOnboardedSolvers {
        vm.prank(alice.pub); // Not solver manager
        vm.expectRevert(); // Should revert due to missing SOLVER_MANAGER_ROLE
        invoiceManager.offboardSolver(solver.pub);
    }

    function test_offboardSolver_revertIf_invalidAddress() public withSetupInvoiceManager {
        vm.prank(solverManager.pub);
        _toRevert(InvoiceManager.IM_InvalidSolver.selector, hex"");
        invoiceManager.offboardSolver(address(0));
    }

    function test_updateSolverFee_success() public withOnboardedSolvers {
        uint256 oldFee = DEFAULT_FEE_AMOUNT;
        uint256 newFee = LOW_FEE_AMOUNT;

        vm.expectEmit(true, false, false, true);
        emit SolverFeeUpdated(solver.pub, oldFee, newFee);

        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, newFee);

        // Verify fee is updated
        (,,,, uint256 fee) = invoiceManager.getSolverData(solver.pub);
        assertEq(fee, newFee, "Fee should be updated");
    }

    function test_updateSolverFee_success_zeroFee() public withOnboardedSolvers {
        uint256 oldFee = DEFAULT_FEE_AMOUNT;
        uint256 newFee = 0;

        vm.expectEmit(true, false, false, true);
        emit SolverFeeUpdated(solver.pub, oldFee, newFee);

        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, newFee);

        (,,,, uint256 fee) = invoiceManager.getSolverData(solver.pub);
        assertEq(fee, 0, "Fee should be zero");
    }

    function test_updateSolverFee_success_maxFee() public withOnboardedSolvers {
        uint256 oldFee = DEFAULT_FEE_AMOUNT;
        uint256 newFee = 1000; // 10%

        vm.expectEmit(true, false, false, true);
        emit SolverFeeUpdated(solver.pub, oldFee, newFee);

        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, newFee);

        (,,,, uint256 fee) = invoiceManager.getSolverData(solver.pub);
        assertEq(fee, newFee, "Fee should be max fee");
    }

    function test_updateSolverFee_success_sameFee() public withOnboardedSolvers {
        uint256 currentFee = DEFAULT_FEE_AMOUNT;

        vm.expectEmit(true, false, false, true);
        emit SolverFeeUpdated(solver.pub, currentFee, currentFee);

        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, currentFee);

        (,,,, uint256 fee) = invoiceManager.getSolverData(solver.pub);
        assertEq(fee, currentFee, "Fee should remain the same");
    }

    function test_updateSolverFee_success_affectsNewInvoicesOnly() public withSampleInvoice {
        // Get original invoice fee
        (InvoiceManager.Invoice memory originalInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        uint256 originalInvoiceFee = originalInvoice.pulseFee;

        // Update solver fee
        uint256 newFee = HIGH_FEE_AMOUNT;
        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, newFee);

        // Existing invoice should keep original fee
        (InvoiceManager.Invoice memory existingInvoice,) = invoiceManager.getInvoice(sessionKey.pub);
        assertEq(existingInvoice.pulseFee, originalInvoiceFee, "Existing invoice fee should not change");

        // Create new invoice - should use new fee
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw2), sessionKey2.pub, solver.pub, SECOND_BID_HASH);
        address newSessionKey = invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // New invoice should use updated fee
        (InvoiceManager.Invoice memory newInvoice,) = invoiceManager.getInvoice(newSessionKey);
        assertEq(newInvoice.pulseFee, newFee, "New invoice should use updated fee");
    }

    function test_updateSolverFee_revertIf_notFeeManagerRole() public withOnboardedSolvers {
        vm.prank(alice.pub); // Not fee manager
        vm.expectRevert(); // Should revert due to missing FEE_MANAGER_ROLE
        invoiceManager.updateSolverFee(solver.pub, LOW_FEE_AMOUNT);
    }

    function test_updateSolverFee_revertIf_solverNotActive() public withSetupInvoiceManager {
        vm.prank(feeManager.pub);
        _toRevert(InvoiceManager.IM_InvalidSolver.selector, hex"");
        invoiceManager.updateSolverFee(solver.pub, LOW_FEE_AMOUNT);
    }

    function test_updateSolverFee_revertIf_invalidAddress() public withSetupInvoiceManager {
        vm.prank(feeManager.pub);
        _toRevert(InvoiceManager.IM_InvalidSolver.selector, hex"");
        invoiceManager.updateSolverFee(address(0), LOW_FEE_AMOUNT);
    }

    function test_updateSolverFee_revertIf_solverOffboarded() public withOnboardedSolvers {
        // Offboard solver first
        vm.prank(solverManager.pub);
        invoiceManager.offboardSolver(solver.pub);

        // Try to update fee of offboarded solver
        vm.prank(feeManager.pub);
        _toRevert(InvoiceManager.IM_InvalidSolver.selector, hex"");
        invoiceManager.updateSolverFee(solver.pub, LOW_FEE_AMOUNT);
    }

    function test_getSolverData_success() public withOnboardedSolvers {
        (string memory name, bool isActive,,, uint256 fee) = invoiceManager.getSolverData(solver.pub);

        assertEq(name, "Solver One", "Name should match");
        assertEq(fee, DEFAULT_FEE_AMOUNT, "Fee should match");
        assertTrue(isActive, "Solver should be active");
    }

    function test_getSolverData_success_offboardedSolver() public withOnboardedSolvers {
        // Offboard solver
        vm.prank(solverManager.pub);
        invoiceManager.offboardSolver(solver.pub);

        (string memory name, bool isActive,,, uint256 fee) = invoiceManager.getSolverData(solver.pub);

        assertEq(name, "", "Name should no longer exist");
        assertEq(fee, 0, "Fee should no longer exist");
        assertFalse(isActive, "Solver should be inactive");
    }

    function test_getSolverData_success_neverOnboardedSolver() public withSetupInvoiceManager {
        (string memory name, bool isActive,,, uint256 fee) = invoiceManager.getSolverData(solver.pub);

        assertEq(name, "", "Name should be empty");
        assertEq(fee, 0, "Fee should be zero");
        assertFalse(isActive, "Solver should be inactive");
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

        address sessionKey = invoiceManager.createInvoice(createInvoiceData);

        bytes memory createInvoiceData2 =
            _createInvoiceData(address(scw2), sessionKey2.pub, solver.pub, SECOND_BID_HASH);

        address sessionKey2 = invoiceManager.createInvoice(createInvoiceData2);

        vm.stopPrank();

        address[] memory invoices = invoiceManager.getSolverInvoices(solver.pub);
        assertEq(invoices.length, 2, "Solver should have two invoices");

        // Check both invoices are present (order might vary)
        bool foundFirst = false;
        bool foundSecond = false;
        for (uint256 i; i < invoices.length; ++i) {
            if (invoices[i] == sessionKey) foundFirst = true;
            if (invoices[i] == sessionKey2) foundSecond = true;
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
        address sessionKey = invoiceManager.createInvoice(createInvoiceData);

        bytes memory createInvoiceData2 =
            _createInvoiceData(address(scw2), sessionKey2.pub, solver2.pub, SECOND_BID_HASH);

        address sessionKey2 = invoiceManager.createInvoice(createInvoiceData2);

        vm.stopPrank();

        // Check solver invoices
        address[] memory solverInvoices = invoiceManager.getSolverInvoices(solver.pub);
        assertEq(solverInvoices.length, 1, "Solver 1 should have one invoice");
        assertEq(solverInvoices[0], sessionKey, "Solver 1 invoice should match");

        // Check solver2 invoices
        address[] memory solver2Invoices = invoiceManager.getSolverInvoices(solver2.pub);
        assertEq(solver2Invoices.length, 1, "Solver 2 should have one invoice");
        assertEq(solver2Invoices[0], sessionKey2, "Solver 2 invoice should match");
    }

    function test_getSolverInvoices_success_dataCleared() public withSampleInvoice {
        // Verify solver has invoices
        address[] memory invoicesBefore = invoiceManager.getSolverInvoices(solver.pub);
        assertEq(invoicesBefore.length, 1, "Solver should have one invoice");

        // Offboard solver
        vm.prank(solverManager.pub);
        invoiceManager.offboardSolver(solver.pub);

        // Invoices should still be accessible
        address[] memory invoicesAfter = invoiceManager.getSolverInvoices(solver.pub);
        assertEq(invoicesAfter.length, 0, "Offboarded solver should no longer have invoices");
    }

    function test_updateSolverFee_success_switchToCustom() public withSetupInvoiceManager {
        // Start with default solver
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(solver.pub, "Test Solver", 0);

        // Update to custom fee
        uint256 newCustomFee = 800000; // 0.8 USDC

        vm.expectEmit(true, false, false, true);
        emit SolverFeeUpdated(solver.pub, 0, newCustomFee);

        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, newCustomFee);

        // Verify fee is updated
        (,,,, uint256 fee) = invoiceManager.getSolverData(solver.pub);
        assertEq(fee, newCustomFee, "Fee should be updated to custom amount");
    }

    function test_updateSolverFee_success_switchToDefault() public withSetupInvoiceManager {
        // Start with custom solver
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(solver.pub, "Test Solver", 500000);

        // Update to default fee (0)
        vm.expectEmit(true, false, false, true);
        emit SolverFeeUpdated(solver.pub, 500000, 0);

        vm.prank(feeManager.pub);
        invoiceManager.updateSolverFee(solver.pub, 0);

        // Verify fee is updated
        (,,,, uint256 fee) = invoiceManager.getSolverData(solver.pub);
        assertEq(fee, 0, "Fee should be updated to default (0)");
    }

    /*//////////////////////////////////////////////////////////////
                    FEE RECEIVER MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setFeeReceiver_success() public withSetupInvoiceManager {
        address newFeeReceiver = makeAddr("newFeeReceiver");

        vm.expectEmit(true, true, false, false);
        emit FeeReceiverUpdated(feeReceiver.pub, newFeeReceiver);

        vm.prank(feeManager.pub);
        invoiceManager.setFeeReceiver(newFeeReceiver);

        assertEq(invoiceManager.feeReceiver(), newFeeReceiver, "Fee receiver should be updated");
    }

    function test_setFeeReceiver_success_affectsNewSettlements() public withSampleInvoice {
        address newFeeReceiver = makeAddr("newFeeReceiver");

        // Update fee receiver
        vm.prank(feeManager.pub);
        invoiceManager.setFeeReceiver(newFeeReceiver);

        // Mint tokens for settlement
        _mintTokensToInvoiceManager();

        uint256 expectedFee = _calculateExpectedFeeForToken(address(testUSDC), 0);
        uint256 initialOldReceiverBalance = testUSDC.balanceOf(feeReceiver.pub);
        uint256 initialNewReceiverBalance = testUSDC.balanceOf(newFeeReceiver);

        // Settle invoice
        _settleInvoiceAsSettler(sessionKey.pub);

        // Old receiver should get nothing, new receiver should get fees
        assertEq(testUSDC.balanceOf(feeReceiver.pub), initialOldReceiverBalance, "Old receiver should get no fees");
        assertEq(
            testUSDC.balanceOf(newFeeReceiver), initialNewReceiverBalance + expectedFee, "New receiver should get fees"
        );
    }

    function test_setFeeReceiver_revertIf_notFeeManagerRole() public withSetupInvoiceManager {
        address newFeeReceiver = makeAddr("newFeeReceiver");

        vm.prank(alice.pub); // Not fee manager
        vm.expectRevert(); // Should revert due to missing FEE_MANAGER_ROLE
        invoiceManager.setFeeReceiver(newFeeReceiver);
    }

    function test_setFeeReceiver_revertIf_invalidAddress() public withSetupInvoiceManager {
        vm.prank(feeManager.pub);
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        invoiceManager.setFeeReceiver(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                  TOGGLE SOLVER STATUS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_toggleSolverStatus_success_activateInactive() public withOnboardedSolvers {
        // First deactivate solver
        vm.prank(solverManager.pub);
        invoiceManager.toggleSolverStatus(solver.pub);

        (, bool isActive1,,,) = invoiceManager.getSolverData(solver.pub);
        assertFalse(isActive1, "Solver should be inactive after first toggle");

        // Then reactivate solver
        vm.prank(solverManager.pub);
        invoiceManager.toggleSolverStatus(solver.pub);

        (, bool isActive2,,,) = invoiceManager.getSolverData(solver.pub);
        assertTrue(isActive2, "Solver should be active after second toggle");
    }

    function test_toggleSolverStatus_success_deactivateActive() public withOnboardedSolvers {
        // Verify solver is initially active
        (, bool initialStatus,,,) = invoiceManager.getSolverData(solver.pub);
        assertTrue(initialStatus, "Solver should be initially active");

        // Deactivate solver
        vm.prank(solverManager.pub);
        invoiceManager.toggleSolverStatus(solver.pub);

        (, bool afterToggle,,,) = invoiceManager.getSolverData(solver.pub);
        assertFalse(afterToggle, "Solver should be inactive after toggle");
    }

    function test_toggleSolverStatus_success_preventsInvoiceCreationWhenInactive() public withOnboardedSolvers {
        // Deactivate solver
        vm.prank(solverManager.pub);
        invoiceManager.toggleSolverStatus(solver.pub);

        // Try to create invoice with inactive solver
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        _toRevert(InvoiceManager.IM_SolverInactive.selector, hex"");
        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();
    }

    function test_toggleSolverStatus_revertIf_notSolverManagerRole() public withOnboardedSolvers {
        vm.prank(alice.pub); // Not solver manager
        vm.expectRevert(); // Should revert due to missing SOLVER_MANAGER_ROLE
        invoiceManager.toggleSolverStatus(solver.pub);
    }

    function test_toggleSolverStatus_revertIf_invalidSolver() public withSetupInvoiceManager {
        vm.prank(solverManager.pub);
        _toRevert(InvoiceManager.IM_InvalidSolver.selector, hex"");
        invoiceManager.toggleSolverStatus(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                      VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_calculateInvoiceFees_success() public withSampleInvoice {
        TokenData[] memory tokenFees = invoiceManager.calculateInvoiceFees(sessionKey.pub);

        // Verify we have the correct number of tokens
        assertEq(tokenFees.length, 3, "Should return fees for 3 tokens");

        uint256 expectedUSDCFee = _calculateExpectedFeeForToken(address(testUSDC), 0);
        uint256 expectedUSDTFee = _calculateExpectedFeeForToken(address(testUSDT), 0);
        uint256 expectedDAIFee = _calculateExpectedFeeForToken(address(testDAI), 0);

        // Verify individual token addresses and fee amounts
        assertEq(tokenFees[0].token, address(testUSDC), "First token should be USDC");
        assertEq(tokenFees[0].amount, expectedUSDCFee, "USDC fee should match expected");
        assertEq(tokenFees[1].token, address(testUSDT), "Second token should be USDT");
        assertEq(tokenFees[1].amount, expectedUSDTFee, "USDT fee should match expected");
        assertEq(tokenFees[2].token, address(testDAI), "Third token should be DAI");
        assertEq(tokenFees[2].amount, expectedDAIFee, "DAI fee should match expected");
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
        address sessionKey = invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        bool settleable = invoiceManager.isInvoiceSettleable(sessionKey);
        assertFalse(settleable, "Invoice should not be settleable without sufficient balance");
    }

    function test_isInvoiceSettleable_success_false_inactiveSolver() public withSampleInvoice {
        // Deactivate solver
        vm.prank(solverManager.pub);
        invoiceManager.toggleSolverStatus(solver.pub);

        bool settleable = invoiceManager.isInvoiceSettleable(sessionKey.pub);
        assertFalse(settleable, "Invoice should not be settleable with inactive solver");
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
        _toRevert(InvoiceManager.IM_InvalidAddress.selector, hex"");
        invoiceManager.addTokenToWhitelist(address(0));
    }

    function test_addTokenToWhitelist_revertIf_tokenAlreadyWhitelisted() public withSetupInvoiceManager {
        vm.prank(deployer.pub);
        _toRevert(InvoiceManager.IM_TokenAlreadyWhitelisted.selector, abi.encode(address(testUSDC)));
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
        _toRevert(InvoiceManager.IM_TokenNotWhitelisted.selector, abi.encode(nonWhitelistedToken));
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

        invoiceManager.onboardSolver(solver.pub, "Solver 1", 0);
        vm.stopPrank();
        // Fee manager should be able to update solver fees
        vm.prank(newAccount);
        invoiceManager.updateSolverFee(solver.pub, 100); // 1.00 tokens

        // Verify fee updated
        (,,,, uint256 pulseFee) = invoiceManager.getSolverData(solver.pub);
        assertEq(pulseFee, 100);
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
        invoiceManager.onboardSolver(newSolver, "New Solver", 30);

        // Verify solver onboarded
        (string memory name, bool isActive,,, uint256 pulseFee) = invoiceManager.getSolverData(newSolver);
        assertEq(name, "New Solver", "Should match correct solver name");
        assertEq(pulseFee, 30, "Should match correct Pulse fee");
        assertTrue(isActive, "Solver should be active");
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
        invoiceManager.onboardSolver(newSolver, "New Solver", 25);
    }

    function test_updateSolverFee_requiresFeeManagerRole() public withSetupInvoiceManager {
        vm.startPrank(newAccount); // No role
        _toRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            abi.encode(newAccount, invoiceManager.FEE_MANAGER_ROLE())
        );
        invoiceManager.updateSolverFee(solver.pub, 50);
    }

    /*//////////////////////////////////////////////////////////////
                      CREDIT TOKENS TO INVOICE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_creditTokensToInvoice_success() public withSampleInvoice {
        address sessionKey = sessionKey.pub;

        vm.expectEmit(true, true, false, true);
        emit TokensCreditedToInvoice(sessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT);

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

        vm.startPrank(credibleAccount.pub);
        invoiceManager.creditTokensToInvoice(sessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT);
        invoiceManager.creditTokensToInvoice(sessionKey, address(testUSDT), DEFAULT_USDT_AMOUNT);
        invoiceManager.creditTokensToInvoice(sessionKey, address(testDAI), DEFAULT_DAI_AMOUNT);
        vm.stopPrank();

        // Verify all tokens credited
        (, InvoiceManager.InvoiceTokenData[] memory tokens) = invoiceManager.getInvoice(sessionKey);
        for (uint256 i; i < tokens.length; ++i) {
            assertEq(tokens[i].creditedAmount, tokens[i].amount, "Token should be fully credited");
        }
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

        // Credit only one token
        vm.prank(credibleAccount.pub);
        invoiceManager.creditTokensToInvoice(sessionKey, address(testUSDC), DEFAULT_USDC_AMOUNT);

        // Try to settle - should fail because DAI and USDT not credited
        vm.prank(settler.pub);
        _toRevert(
            InvoiceManager.IM_InvoiceNotFullyCredited.selector,
            abi.encode(sessionKey, address(testUSDT), DEFAULT_USDT_AMOUNT, 0)
        );
        invoiceManager.settleInvoice(sessionKey);
    }

    function test_settleInvoice_success_afterFullCrediting() public withSampleInvoice {
        address sessionKey = sessionKey.pub;
        _mintTokensToInvoiceManager();
        _creditTokensToInvoice(sessionKey);

        uint256 initialSolverBalance = testUSDC.balanceOf(solver.pub);
        uint256 expectedAmount = DEFAULT_USDC_AMOUNT - _calculateExpectedFeeForToken(address(testUSDC), 0);

        vm.prank(settler.pub);
        invoiceManager.settleInvoice(sessionKey);

        assertEq(testUSDC.balanceOf(solver.pub), initialSolverBalance + expectedAmount);
        assertFalse(invoiceManager.invoiceExists(sessionKey));
    }

    function test_getInvoicePaymentStatus_success_nothingCredited() public withSampleInvoice {
        (address[] memory tokens, uint256[] memory expectedAmounts, uint256[] memory creditedAmounts, bool isFullyPaid)
        = invoiceManager.getInvoicePaymentStatus(sessionKey.pub);

        assertEq(tokens.length, 3);
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
}
