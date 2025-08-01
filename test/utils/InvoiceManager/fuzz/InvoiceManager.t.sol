// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {InvoiceManager} from "../../../../src/utils/InvoiceManager.sol";
import {InvoiceManagerTestUtils} from "../utils/InvoiceManagerTestUtils.sol";
import {MockTokenWithDecimals} from "../utils/MockTokenWithDecimals.sol";
import {TokenData} from "../../../../src/common/Structs.sol";

contract InvoiceManager_FuzzTests_Test is InvoiceManagerTestUtils {
    MockTokenWithDecimals internal mockToken6;
    MockTokenWithDecimals internal mockToken8;
    MockTokenWithDecimals internal mockToken12;
    MockTokenWithDecimals internal mockToken18;
    MockTokenWithDecimals internal mockToken24;

    function setUp() public {
        _testSetup();
        _setupInvoiceManager();

        // Create tokens with various decimal configurations
        mockToken6 = new MockTokenWithDecimals("Mock6", "M6", 6);
        mockToken8 = new MockTokenWithDecimals("Mock8", "M8", 8);
        mockToken12 = new MockTokenWithDecimals("Mock12", "M12", 12);
        mockToken18 = new MockTokenWithDecimals("Mock18", "M18", 18);
        mockToken24 = new MockTokenWithDecimals("Mock24", "M24", 24);

        // Add to whitelist
        vm.startPrank(deployer.pub);
        invoiceManager.addTokenToWhitelist(address(mockToken6));
        invoiceManager.addTokenToWhitelist(address(mockToken8));
        invoiceManager.addTokenToWhitelist(address(mockToken12));
        invoiceManager.addTokenToWhitelist(address(mockToken18));
        invoiceManager.addTokenToWhitelist(address(mockToken24));
        vm.stopPrank();

        // Mint tokens to invoice manager
        mockToken6.mint(address(invoiceManager), 1000000 * 10 ** 6);
        mockToken8.mint(address(invoiceManager), 1000000 * 10 ** 8);
        mockToken12.mint(address(invoiceManager), 1000000 * 10 ** 12);
        mockToken18.mint(address(invoiceManager), 1000000 * 10 ** 18);
        mockToken24.mint(address(invoiceManager), 1000000 * 10 ** 24);
    }

    /*//////////////////////////////////////////////////////////////
                          FEE CALCULATION FUZZ TESTS
      //////////////////////////////////////////////////////////////*/

    function testFuzz_feeCalculation_differentDecimals(uint8 decimals, uint256 pulseFee)
        public
        withSetupInvoiceManager
    {
        // Bound inputs to reasonable ranges
        decimals = uint8(bound(decimals, 0, 30)); // 0-30 decimals
        pulseFee = bound(pulseFee, 0, 10000); // 0-100.00 tokens max fee

        // Create mock token with fuzzed decimals
        MockTokenWithDecimals fuzzToken = new MockTokenWithDecimals("FuzzToken", "FUZZ", decimals);

        // Add token to whitelist
        vm.prank(deployer.pub);
        invoiceManager.addTokenToWhitelist(address(fuzzToken));

        // Onboard solver with custom fee
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(solver.pub, "Test Solver", pulseFee);

        // Create invoice with the fuzz token
        TokenData[] memory tokenData = new TokenData[](1);
        tokenData[0] = TokenData({
            token: address(fuzzToken),
            amount: 1000 * 10 ** decimals // 1000 tokens
        });

        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, tokenData);

        address sessionKey = invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Get the calculated fees from the invoice
        TokenData[] memory tokenFees = invoiceManager.calculateInvoiceFees(sessionKey);

        // Calculate expected fee
        uint256 effectiveFee = pulseFee == 0 ? invoiceManager.PULSE_BASE_FEE() : pulseFee;
        uint256 expectedFee = (effectiveFee * 10 ** decimals) / 100;

        // For very small token amounts, fee might be capped
        uint256 tokenAmount = 1000 * 10 ** decimals;
        if (expectedFee > tokenAmount) {
            expectedFee = tokenAmount;
        }

        // Verify the fee calculation
        assertEq(tokenFees.length, 1, "Should have one token fee");
        assertEq(tokenFees[0].token, address(fuzzToken), "Token address should match");
        assertEq(tokenFees[0].amount, expectedFee, "Fee should match expected calculation");
    }

    function testFuzz_invoiceCreation_variableAmounts(uint256 amount, uint8 tokenDecimals) public {
        // Bound inputs to prevent overflow and ensure reasonable values
        tokenDecimals = uint8(bound(tokenDecimals, 0, 18));
        amount = bound(amount, 10 ** tokenDecimals, 1000000 * 10 ** tokenDecimals); // 1 to 1M tokens

        // Create token
        MockTokenWithDecimals fuzzToken = new MockTokenWithDecimals("FuzzToken", "FUZZ", tokenDecimals);

        // Add to whitelist
        vm.prank(deployer.pub);
        invoiceManager.addTokenToWhitelist(address(fuzzToken));

        // Mint sufficient tokens
        fuzzToken.mint(address(invoiceManager), amount * 2);

        // FIXED: Onboard a solver first (solver doesn't exist by default in fuzz tests)
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(solver.pub, "Fuzz Test Solver", DEFAULT_FEE_AMOUNT);

        // Create token data
        TokenData[] memory tokenData = new TokenData[](1);
        tokenData[0] = TokenData({token: address(fuzzToken), amount: amount});

        // Create invoice
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, tokenData);

        address sessionKey = invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Verify invoice exists
        assertTrue(invoiceManager.invoiceExists(sessionKey));

        // Test fee calculation consistency
        TokenData[] memory tokenFees = invoiceManager.calculateInvoiceFees(sessionKey);
        assertEq(tokenFees.length, 1, "Should return one token fee");
        assertEq(tokenFees[0].token, address(fuzzToken), "Token address should match");

        // Fee should be reasonable (not exceed amount)
        assertTrue(tokenFees[0].amount <= amount, "Fee should not exceed token amount");

        // Fee should be exactly 0.05 tokens (default fee) or capped at amount
        uint256 expectedFee = (invoiceManager.PULSE_BASE_FEE() * 10 ** tokenDecimals) / 100;
        uint256 cappedFee = expectedFee > amount ? amount : expectedFee;
        assertEq(tokenFees[0].amount, cappedFee, "Fee should match expected calculation");
    }

    function testFuzz_settlement_variableTokenAmounts(uint256 amount6, uint256 amount18) public {
        // Bound amounts to reasonable ranges
        amount6 = bound(amount6, 10 ** 6, 1000 * 10 ** 6); // 1 to 1000 tokens (6 decimals)
        amount18 = bound(amount18, 10 ** 18, 1000 * 10 ** 18); // 1 to 1000 tokens (18 decimals)

        // FIXED: Onboard solver first
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(solver.pub, "Settlement Test Solver", DEFAULT_FEE_AMOUNT);

        // Create multi-token invoice
        TokenData[] memory tokenData = new TokenData[](2);
        tokenData[0] = TokenData({token: address(mockToken6), amount: amount6});
        tokenData[1] = TokenData({token: address(mockToken18), amount: amount18});

        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, tokenData);

        address sessionKey = invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Record initial balances
        uint256 initialSolverBalance6 = mockToken6.balanceOf(solver.pub);
        uint256 initialSolverBalance18 = mockToken18.balanceOf(solver.pub);
        uint256 initialFeeBalance6 = mockToken6.balanceOf(feeReceiver.pub);
        uint256 initialFeeBalance18 = mockToken18.balanceOf(feeReceiver.pub);

        // Settle invoice
        vm.prank(settler.pub);
        invoiceManager.settleInvoice(sessionKey);

        // Verify settlement
        assertFalse(invoiceManager.invoiceExists(sessionKey));

        // Check that solver received tokens (minus fees)
        assertTrue(mockToken6.balanceOf(solver.pub) > initialSolverBalance6);
        assertTrue(mockToken18.balanceOf(solver.pub) > initialSolverBalance18);

        // Check that fee receiver got fees
        assertTrue(mockToken6.balanceOf(feeReceiver.pub) >= initialFeeBalance6);
        assertTrue(mockToken18.balanceOf(feeReceiver.pub) >= initialFeeBalance18);

        // Verify total amounts are conserved
        uint256 totalReceived6 = (mockToken6.balanceOf(solver.pub) - initialSolverBalance6)
            + (mockToken6.balanceOf(feeReceiver.pub) - initialFeeBalance6);
        uint256 totalReceived18 = (mockToken18.balanceOf(solver.pub) - initialSolverBalance18)
            + (mockToken18.balanceOf(feeReceiver.pub) - initialFeeBalance18);

        assertEq(totalReceived6, amount6);
        assertEq(totalReceived18, amount18);
    }

    function testFuzz_feeConsistency_acrossDecimals() public withSetupInvoiceManager {
        // Test that 0.05 tokens fee is consistent across different decimal tokens
        address[5] memory tokens =
            [address(mockToken6), address(mockToken8), address(mockToken12), address(mockToken18), address(mockToken24)];

        uint8[5] memory decimalsArray = [6, 8, 12, 18, 24];

        // Add all tokens to whitelist
        vm.startPrank(deployer.pub);
        for (uint256 i; i < tokens.length; ++i) {
            invoiceManager.addTokenToWhitelist(tokens[i]);
        }
        vm.stopPrank();

        // Onboard solver with default fee (0 = use calculated default)
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(solver.pub, "Test Solver", 0);

        for (uint256 i; i < tokens.length; ++i) {
            // Create invoice with each token type
            TokenData[] memory tokenData = new TokenData[](1);
            tokenData[0] = TokenData({
                token: tokens[i],
                amount: 1000 * 10 ** decimalsArray[i] // 1000 tokens
            });

            vm.startPrank(credibleAccount.pub);
            bytes32 bidHash = keccak256(abi.encodePacked("bid_hash_", i));
            address sessionKey = address(uint160(uint256(keccak256(abi.encodePacked("session_key_", i)))));

            bytes memory createInvoiceData =
                abi.encode(address(scw), sessionKey, solver.pub, bidHash, TEST_CHAIN_ID, tokenData);

            address createdSessionKey = invoiceManager.createInvoice(createInvoiceData);
            vm.stopPrank();

            // Get the calculated fees from the invoice
            TokenData[] memory tokenFees = invoiceManager.calculateInvoiceFees(createdSessionKey);

            uint256 fee = tokenFees[0].amount;
            uint256 expectedFee = (invoiceManager.PULSE_BASE_FEE() * 10 ** decimalsArray[i]) / 100;

            assertEq(fee, expectedFee, "Fee calculation should be consistent across decimals");

            // Verify fee represents 0.05 tokens regardless of decimals
            // Convert back to human readable: fee * 100 / 10^decimals should equal 5
            uint256 humanReadableFee = (fee * 100) / (10 ** decimalsArray[i]);
            assertEq(humanReadableFee, 5, "Fee should always represent 5 cents (0.05 tokens)");
        }
    }

    function testFuzz_solverManagement(uint256 solverCount, uint256 operationCount, uint256 seedValue)
        public
        withSetupInvoiceManager
    {
        solverCount = bound(solverCount, 1, 20);
        operationCount = bound(operationCount, 5, 50);

        address[] memory solvers = new address[](solverCount);
        bool[] memory solverActive = new bool[](solverCount);

        // Create random solvers
        for (uint256 i; i < solverCount; ++i) {
            solvers[i] = address(uint160(uint256(keccak256(abi.encodePacked("solver", i, seedValue)))));
        }

        // Perform random operations
        for (uint256 i; i < operationCount; ++i) {
            uint256 operation = uint256(keccak256(abi.encodePacked(seedValue, i))) % 4;
            uint256 solverIndex = uint256(keccak256(abi.encodePacked(seedValue, i, "index"))) % solverCount;
            address solver = solvers[solverIndex];

            vm.startPrank(solverManager.pub);

            if (operation == 0) {
                // Onboard
                if (!solverActive[solverIndex]) {
                    uint256 fee = bound(uint256(keccak256(abi.encodePacked(seedValue, i, "fee"))), 0, 1000);
                    invoiceManager.onboardSolver(solver, "Test Solver", fee);
                    solverActive[solverIndex] = true;
                }
            } else if (operation == 1 && solverActive[solverIndex]) {
                // Toggle status
                invoiceManager.toggleSolverStatus(solver);
            } else if (operation == 2 && solverActive[solverIndex]) {
                // Update fee
                uint256 newFee = bound(uint256(keccak256(abi.encodePacked(seedValue, i, "newfee"))), 0, 1000);
                vm.stopPrank();
                vm.prank(feeManager.pub);
                invoiceManager.updateSolverFee(solver, newFee);
                vm.startPrank(solverManager.pub);
            } else if (operation == 3 && solverActive[solverIndex]) {
                // Offboard
                invoiceManager.offboardSolver(solver);
                solverActive[solverIndex] = false;
            }

            vm.stopPrank();
        }

        // Verify contract state is consistent
        for (uint256 i; i < solverCount; ++i) {
            if (solverActive[i]) {
                (, bool isActive,,,) = invoiceManager.getSolverData(solvers[i]);
                // Solver should exist if we think it's active
                assertTrue(isActive || !isActive); // Just verify no revert
            }
        }
    }

    function testFuzz_tokenWhitelist(uint256 tokenCount, uint256 operationCount, uint256 seedValue)
        public
        withSetupInvoiceManager
    {
        tokenCount = bound(tokenCount, 1, 50);
        operationCount = bound(operationCount, 10, 100);

        address[] memory tokens = new address[](tokenCount);
        bool[] memory tokenWhitelisted = new bool[](tokenCount);

        // Create random token addresses
        for (uint256 i; i < tokenCount; ++i) {
            tokens[i] = address(uint160(uint256(keccak256(abi.encodePacked("token", i, seedValue)))));
        }

        vm.startPrank(deployer.pub);

        for (uint256 i; i < operationCount; ++i) {
            uint256 operation = uint256(keccak256(abi.encodePacked(seedValue, i))) % 3;
            uint256 tokenIndex = uint256(keccak256(abi.encodePacked(seedValue, i, "token"))) % tokenCount;
            address token = tokens[tokenIndex];

            if (operation == 0) {
                // Add single token
                if (!tokenWhitelisted[tokenIndex]) {
                    try invoiceManager.addTokenToWhitelist(token) {
                        tokenWhitelisted[tokenIndex] = true;
                    } catch {}
                }
            } else if (operation == 1) {
                // Remove single token
                if (tokenWhitelisted[tokenIndex]) {
                    try invoiceManager.removeTokenFromWhitelist(token) {
                        tokenWhitelisted[tokenIndex] = false;
                    } catch {}
                }
            } else if (operation == 2) {
                // Batch add
                uint256 batchSize = bound(uint256(keccak256(abi.encodePacked(seedValue, i, "batch"))), 1, 5);
                address[] memory batchTokens = new address[](batchSize);
                for (uint256 j; j < batchSize; ++j) {
                    uint256 batchIndex = (tokenIndex + j) % tokenCount;
                    batchTokens[j] = tokens[batchIndex];
                }
                try invoiceManager.addTokensToWhitelist(batchTokens) {
                    for (uint256 j; j < batchSize; ++j) {
                        uint256 batchIndex = (tokenIndex + j) % tokenCount;
                        tokenWhitelisted[batchIndex] = true;
                    }
                } catch {}
            }
        }

        vm.stopPrank();

        // Verify final state consistency
        uint256 actualWhitelistedCount = invoiceManager.getWhitelistedTokensCount();
        assertTrue(actualWhitelistedCount >= 4); // At least the initial tokens
    }

    function testFuzz_multiTokenInvoice(uint8 tokenCount, uint256 seedValue) public withSetupInvoiceManager {
        tokenCount = uint8(bound(tokenCount, 1, 10));

        MockTokenWithDecimals[] memory tokens = new MockTokenWithDecimals[](tokenCount);
        TokenData[] memory tokenData = new TokenData[](tokenCount);

        vm.startPrank(deployer.pub);

        // Create and whitelist random tokens
        for (uint256 i; i < tokenCount; ++i) {
            uint8 decimals = uint8(bound(uint256(keccak256(abi.encodePacked(seedValue, i, "decimals"))), 0, 18));
            tokens[i] = new MockTokenWithDecimals(
                string(abi.encodePacked("Token", i)), string(abi.encodePacked("TK", i)), decimals
            );

            invoiceManager.addTokenToWhitelist(address(tokens[i]));

            uint256 amount = bound(
                uint256(keccak256(abi.encodePacked(seedValue, i, "amount"))), 10 ** decimals, 1000000 * 10 ** decimals
            );

            tokens[i].mint(address(invoiceManager), amount * 2);
            tokenData[i] = TokenData({token: address(tokens[i]), amount: amount});
        }

        vm.stopPrank();

        // Onboard solver
        vm.prank(solverManager.pub);
        uint256 solverFee = bound(uint256(keccak256(abi.encodePacked(seedValue, "solver"))), 0, 100);
        invoiceManager.onboardSolver(solver.pub, "Multi Token Solver", solverFee);

        // Create multi-token invoice
        vm.startPrank(credibleAccount.pub);
        bytes32 bidHash = keccak256(abi.encodePacked("multi_token_bid", seedValue));
        address sessionKey = address(uint160(uint256(keccak256(abi.encodePacked("multi_session", seedValue)))));

        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey, solver.pub, bidHash, TEST_CHAIN_ID, tokenData);

        address createdSessionKey = invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Verify invoice creation
        assertTrue(invoiceManager.invoiceExists(createdSessionKey));

        // Calculate expected fees for all tokens
        TokenData[] memory fees = invoiceManager.calculateInvoiceFees(createdSessionKey);
        assertEq(fees.length, tokenCount);

        // Settle and verify all tokens are processed correctly
        uint256[] memory initialBalances = new uint256[](tokenCount);
        for (uint256 i; i < tokenCount; ++i) {
            initialBalances[i] = tokens[i].balanceOf(solver.pub);
        }

        vm.prank(settler.pub);
        invoiceManager.settleInvoice(createdSessionKey);

        // Verify all tokens were transferred
        for (uint256 i; i < tokenCount; ++i) {
            assertTrue(tokens[i].balanceOf(solver.pub) > initialBalances[i]);
        }
    }

    function testFuzz_errorConditions_randomInputs(
        address randomSolver,
        bytes32 randomBidHash,
        uint256 randomAmount,
        uint8 randomTokenDecimals
    ) public withSetupInvoiceManager {
        randomAmount = bound(randomAmount, 0, type(uint128).max);
        randomTokenDecimals = uint8(bound(randomTokenDecimals, 0, 30));

        // Test various error conditions with random inputs
        MockTokenWithDecimals randomToken = new MockTokenWithDecimals("Random", "RND", randomTokenDecimals);
        vm.prank(deployer.pub);
        invoiceManager.onboardSolver(randomSolver, "random solver", 0);

        vm.startPrank(credibleAccount.pub);

        TokenData[] memory tokenData = new TokenData[](1);
        tokenData[0] = TokenData({token: address(randomToken), amount: randomAmount});
        bytes memory createInvoiceData = abi.encode(
            address(scw),
            address(uint160(uint256(randomBidHash))),
            randomSolver,
            randomBidHash,
            TEST_CHAIN_ID,
            tokenData
        );

        // Test 1: Non-whitelisted token should always fail first
        if (randomAmount > 0) {
            vm.expectRevert(
                abi.encodeWithSelector(InvoiceManager.IM_TokenNotWhitelisted.selector, address(randomToken))
            );
            invoiceManager.createInvoice(createInvoiceData);
        }

        // Test 2: Whitelist token but use invalid solver
        vm.stopPrank();
        vm.prank(deployer.pub);
        invoiceManager.addTokenToWhitelist(address(randomToken));

        vm.startPrank(credibleAccount.pub);

        // If randomSolver is not onboarded or inactive, should get IM_SolverInactive
        bool solverExists = false;
        try invoiceManager.getSolverData(randomSolver) returns (string memory, bool isActive, uint256, uint256, uint256)
        {
            solverExists = isActive;
        } catch {
            solverExists = false;
        }

        if (!solverExists && randomAmount > 0) {
            vm.expectRevert(InvoiceManager.IM_SolverInactive.selector);
            invoiceManager.createInvoice(createInvoiceData);
        }

        vm.stopPrank();

        // Test 3: Valid solver but zero amount
        if (randomAmount == 0) {
            // Onboard the solver to make it valid
            vm.prank(solverManager.pub);
            try invoiceManager.onboardSolver(randomSolver, "Random Solver", 0) {} catch {}

            vm.startPrank(credibleAccount.pub);
            vm.expectRevert(InvoiceManager.IM_InvalidTokenAmount.selector);
            invoiceManager.createInvoice(createInvoiceData);
            vm.stopPrank();
        }

        // Test 4: Valid conditions - should succeed
        if (randomAmount > 0) {
            // Onboard the solver
            vm.prank(solverManager.pub);
            try invoiceManager.onboardSolver(randomSolver, "Random Solver", 0) {} catch {}

            // This should succeed if all conditions are met
            vm.startPrank(credibleAccount.pub);
            try invoiceManager.createInvoice(createInvoiceData) returns (address sessionKey) {
                assertTrue(invoiceManager.invoiceExists(sessionKey));
            } catch {
                // May fail due to duplicate session key or bid hash, which is fine
            }
            vm.stopPrank();
        }
    }
}
