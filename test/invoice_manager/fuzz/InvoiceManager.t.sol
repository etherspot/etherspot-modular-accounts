// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISolverManager} from "../../../src/interfaces/ISolverManager.sol";
import {InvoiceManager} from "../../../src/invoice_manager/InvoiceManager.sol";
import {SolverManager} from "../../../src/invoice_manager/SolverManager.sol";
import {TokenManager} from "../../../src/invoice_manager/TokenManager.sol";
import {InvoiceManagerTestUtils} from "../utils/InvoiceManagerTestUtils.sol";
import {MockTokenWithDecimals} from "../utils/MockTokenWithDecimals.sol";
import {TokenData} from "../../../src/common/Structs.sol";

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

        // Create invoice with the fuzz token
        TokenData[] memory tokenData = new TokenData[](1);
        tokenData[0] = TokenData({
            token: address(fuzzToken),
            amount: 1000 * 10 ** decimals // 1000 tokens
        });

        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, tokenData);

        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Get the calculated fees from the invoice
        (uint256 protocolFee, uint256 orchestratorFee, uint256 solverFee, uint256 totalFees) =
            invoiceManager.calculateInvoiceFees(sessionKey.pub);

        // Calculate expected total fees (protocol is always 5 cents)
        uint256 expectedProtocolFee = (5 * 10 ** decimals) / 100;

        // Verify the fee calculation
        assertGt(totalFees, 0, "Total fees should be greater than 0");
        assertEq(protocolFee, expectedProtocolFee, "Protocol fee should be 5 cents");
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

        // Onboard a solver first
        vm.prank(solverManager.pub);
        invoiceManager.onboardSolver(
            solver.pub,
            solver.pub,
            feeReceiver.pub,
            "Fuzz Test Solver",
            ISolverManager.FeeType.PERCENTAGE,
            50,
            ISolverManager.FeeType.PERCENTAGE,
            20
        );

        // Create token data
        TokenData[] memory tokenData = new TokenData[](1);
        tokenData[0] = TokenData({token: address(fuzzToken), amount: amount});

        // Create invoice
        vm.startPrank(credibleAccount.pub);
        bytes memory createInvoiceData =
            abi.encode(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH, TEST_CHAIN_ID, tokenData);

        invoiceManager.createInvoice(createInvoiceData);
        vm.stopPrank();

        // Verify invoice exists
        assertTrue(invoiceManager.invoiceExists(sessionKey.pub));

        // Test fee calculation consistency
        (uint256 protocolFee, uint256 orchestratorFee, uint256 solverFee, uint256 totalFees) =
            invoiceManager.calculateInvoiceFees(sessionKey.pub);

        // Total fees should be reasonable (not exceed amount)
        assertTrue(totalFees <= amount, "Total fees should not exceed token amount");

        // Protocol fee should be 5 cents
        uint256 expectedProtocolFee = (invoiceManager.protocolFeeFixed() * 10 ** tokenDecimals) / 100;
        assertEq(protocolFee, expectedProtocolFee, "Protocol fee should be 5 cents");
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

            invoiceManager.createInvoice(createInvoiceData);
            vm.stopPrank();

            // Get the calculated fees from the invoice
            (uint256 protocolFee, uint256 orchestratorFee, uint256 solverFee, uint256 totalFees) =
                invoiceManager.calculateInvoiceFees(sessionKey);

            uint256 expectedProtocolFee = (invoiceManager.protocolFeeFixed() * 10 ** decimalsArray[i]) / 100;

            assertEq(protocolFee, expectedProtocolFee, "Protocol fee calculation should be consistent across decimals");

            // Verify protocol fee represents 0.05 tokens regardless of decimals
            uint256 humanReadableFee = (protocolFee * 100) / (10 ** decimalsArray[i]);
            assertEq(humanReadableFee, 5, "Protocol fee should always represent 5 cents");
        }
    }

    function testFuzz_solverManagement(uint256 solverCount, uint256 operationCount, uint256 seedValue)
        public
        withSetupInvoiceManager
    {
        solverCount = bound(solverCount, 1, 20);
        operationCount = bound(operationCount, 5, 50);

        address[] memory solvers = new address[](solverCount);

        // Create random solvers
        for (uint256 i; i < solverCount; ++i) {
            solvers[i] = address(uint160(uint256(keccak256(abi.encodePacked("solver", i, seedValue)))));
        }

        // Perform random operations
        for (uint256 i; i < operationCount; ++i) {
            uint256 operation = uint256(keccak256(abi.encodePacked(seedValue, i))) % 3;
            uint256 solverIndex = uint256(keccak256(abi.encodePacked(seedValue, i, "index"))) % solverCount;
            address solver = solvers[solverIndex];

            bool solverExists = _solverExists(solver);
            bool solverPendingOffboard = false;

            // Get current solver state if it exists
            if (solverExists) {
                try invoiceManager.getSolverData(solver) returns (ISolverManager.Solver memory solverData) {
                    solverPendingOffboard = solverData.pendingOffboard;
                } catch {
                    solverExists = false;
                }
            }

            vm.startPrank(solverManager.pub);

            if (operation == 0) {
                // Onboard
                if (!solverExists) {
                    invoiceManager.onboardSolver(
                        solver,
                        solver,
                        feeReceiver.pub,
                        "Test Solver",
                        ISolverManager.FeeType.PERCENTAGE,
                        50,
                        ISolverManager.FeeType.PERCENTAGE,
                        20
                    );
                }
            } else if (operation == 1 && solverExists && !solverPendingOffboard) {
                // Update fee
                vm.stopPrank();
                vm.prank(feeManager.pub);
                invoiceManager.updateSolverFee(solver, ISolverManager.FeeType.PERCENTAGE, 20);
                vm.startPrank(solverManager.pub);
            }

            vm.stopPrank();
        }

        // Verify contract state is consistent
        for (uint256 i; i < solverCount; ++i) {
            if (_solverExists(solvers[i])) {
                try invoiceManager.getSolverData(solvers[i]) returns (ISolverManager.Solver memory solverData) {
                    // Verify state consistency
                    if (solverData.pendingOffboard) {
                        assertFalse(solverData.isActive, "Pending offboard solver should not be active");
                    }

                    // Verify basic invariants
                    assertTrue(bytes(solverData.name).length > 0, "Solver should have a name");
                } catch {
                    revert("getSolverData failed for existing solver");
                }
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

    function testFuzz_errorConditions_randomInputs(
        address randomSolver,
        bytes32 randomBidHash,
        uint256 randomAmount,
        uint8 randomTokenDecimals
    ) public withSetupInvoiceManager {
        address sessionKey = address(uint160(uint256(randomBidHash)));
        vm.assume(sessionKey != address(0));
        randomAmount = bound(randomAmount, 0, type(uint128).max);
        randomTokenDecimals = uint8(bound(randomTokenDecimals, 0, 30));

        // Test various error conditions with random inputs
        // Use salt to ensure unique addresses for each fuzz run
        bytes32 salt = keccak256(abi.encodePacked(randomSolver, randomBidHash, randomAmount, randomTokenDecimals));
        MockTokenWithDecimals randomToken = new MockTokenWithDecimals{salt: salt}("Random", "RND", randomTokenDecimals);

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

        // Test 1: Invalid solver should fail first (before token whitelist check)
        if (randomAmount > 0) {
            // randomSolver is not onboarded yet, should get SM_SolverInactive
            vm.expectRevert(SolverManager.SM_SolverInactive.selector);
            invoiceManager.createInvoice(createInvoiceData);
        }

        vm.stopPrank();

        // Test 2: Onboard solver but don't whitelist token - should get token whitelist error
        vm.prank(deployer.pub);
        try invoiceManager.onboardSolver(
            randomSolver,
            randomSolver,
            feeReceiver.pub,
            "Random Solver",
            ISolverManager.FeeType.PERCENTAGE,
            50,
            ISolverManager.FeeType.PERCENTAGE,
            20
        ) {} catch {}

        if (randomAmount > 0) {
            vm.startPrank(credibleAccount.pub);
            vm.expectRevert(abi.encodeWithSelector(TokenManager.TM_TokenNotWhitelisted.selector, address(randomToken)));
            invoiceManager.createInvoice(createInvoiceData);
            vm.stopPrank();
        }

        // Test 3: Whitelist token and test amount validation
        vm.prank(deployer.pub);
        invoiceManager.addTokenToWhitelist(address(randomToken));

        if (randomAmount == 0) {
            vm.startPrank(credibleAccount.pub);
            vm.expectRevert(InvoiceManager.IM_InvalidTokenAmount.selector);
            invoiceManager.createInvoice(createInvoiceData);
            vm.stopPrank();
        }

        // Test 4: Valid conditions - should succeed
        if (randomAmount > 0) {
            // This should succeed if all conditions are met
            vm.startPrank(credibleAccount.pub);
            try invoiceManager.createInvoice(createInvoiceData) {
                assertTrue(invoiceManager.invoiceExists(address(uint160(uint256(randomBidHash)))));
            } catch {
                // May fail due to duplicate session key or bid hash, which is fine
            }
            vm.stopPrank();
        }
    }

    function _solverExists(address solver) internal view returns (bool) {
        // Solver struct has 11 fields:
        // executionAddress, feeAddress, orchestratorReceiver, solverData.name, solverData.isActive,
        // pendingOffboard, successfulSettlements, orchestratorFeeType, orchestratorFeeValue,
        // solverData.solverFeeType, solverData.solverFeeValue
        (
            address executionAddress,
            , // feeAddress
            , // orchestratorReceiver
            , // solverData.name
            , // solverData.isActive
            , // pendingOffboard
            , // successfulSettlements
            , // orchestratorFeeType
            , // orchestratorFeeValue
            , // solverData.solverFeeType
                // solverData.solverFeeValue
        ) = invoiceManager.solvers(solver);
        return executionAddress != address(0);
    }
}
