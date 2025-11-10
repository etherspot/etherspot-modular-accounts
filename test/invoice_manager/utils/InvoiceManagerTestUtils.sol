// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IInvoiceManager} from "../../../src/interfaces/IInvoiceManager.sol";
import {ISolverManager} from "../../../src/interfaces/ISolverManager.sol";
import {InvoiceManager} from "../../../src/invoice_manager/InvoiceManager.sol";
import {TestERC20} from "../../../src/test/TestERC20.sol";
import {TestUSDC} from "../../../src/test/TestUSDC.sol";
import {TokenData} from "../../../src/common/Structs.sol";
import "../../ModularTestBase.sol";

contract InvoiceManagerTestUtils is ModularTestBase {
    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Contract instances
    InvoiceManager internal invoiceManager;

    // Test tokens (stablecoins)
    TestUSDC internal testUSDC;
    TestERC20 internal testUSDT;
    TestERC20 internal testDAI;
    TestERC20 internal testBUSD;
    TestERC20 internal nonWhitelistedToken;

    // Test users
    User internal protocolFeeReceiver;
    User internal orchestratorFeeReceiver;
    User internal feeReceiver; // Legacy - same as orchestratorFeeReceiver for backward compatibility
    User internal feeManager;
    User internal solverManager;
    User internal credibleAccount;
    User internal settler;
    User internal solver1;
    User internal solver2;
    User internal sessionKey1;
    User internal sessionKey2;
    address internal newAccount;
    ModularEtherspotWallet scw2;

    // Test constants
    uint256 internal constant HIGH_FEE_AMOUNT = 50; // 0.5 USDC fixed
    uint256 internal constant LOW_FEE_AMOUNT = 1; // 0.01 USDC fixed
    uint256 internal constant CUSTOM_FEE_AMOUNT = 75; // 0.75 USDC fixed

    uint256 internal constant DEFAULT_USDC_AMOUNT = 1000e6; // 1000 USDC
    uint256 internal constant DEFAULT_USDT_AMOUNT = 500e18; // 500 USDT
    uint256 internal constant DEFAULT_DAI_AMOUNT = 750e18; // 750 DAI
    uint256 internal constant DEFAULT_BUSD_AMOUNT = 250e18; // 250 BUSD

    bytes32 internal constant DEFAULT_BID_HASH = keccak256("default_bid_hash");
    bytes32 internal constant SECOND_BID_HASH = keccak256("second_bid_hash");
    bytes32 internal constant THIRD_BID_HASH = keccak256("third_bid_hash");

    uint256 constant TEST_CHAIN_ID = 31337;

    // Arrays for easy access
    address[] internal whitelistedTokenAddresses;
    TokenData[] internal defaultTokenData;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier withSetupInvoiceManager() {
        _setupInvoiceManager();
        _;
    }

    modifier withOnboardedSolvers() {
        _setupInvoiceManager();
        _onboardDefaultSolvers();
        _;
    }

    modifier withSampleInvoice() {
        _setupInvoiceManager();
        _onboardDefaultSolvers();
        _createSampleInvoice();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        TEST HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _testSetup() internal {
        // Set up base contracts and wallet
        _testInit();

        // Create test users
        protocolFeeReceiver = _createUser("Protocol Fee Receiver");
        orchestratorFeeReceiver = _createUser("Orchestrator Fee Receiver");
        feeReceiver = orchestratorFeeReceiver; // For backward compatibility
        feeManager = _createUser("Fee Manager");
        solverManager = _createUser("Solver Manager");
        credibleAccount = _createUser("Credible Account");
        settler = _createUser("Settler");
        solver2 = _createUser("Solver 2");
        sessionKey2 = _createUser("Session Key 2");
        newAccount = makeAddr("newAccount");
        scw2 = _createSCW(newAccount);

        // Create additional test tokens
        testUSDC = new TestUSDC();
        testUSDT = new TestERC20();
        testDAI = new TestERC20();
        testBUSD = new TestERC20();
        nonWhitelistedToken = new TestERC20();

        vm.label(address(testUSDC), "Test USDC");
        vm.label(address(testUSDT), "Test USDT");
        vm.label(address(testDAI), "Test DAI");
        vm.label(address(testBUSD), "Test BUSD");
        vm.label(address(nonWhitelistedToken), "Non-Whitelisted Token");

        // Set up whitelisted tokens array
        whitelistedTokenAddresses = new address[](4);
        whitelistedTokenAddresses[0] = address(testUSDC);
        whitelistedTokenAddresses[1] = address(testUSDT);
        whitelistedTokenAddresses[2] = address(testDAI);
        whitelistedTokenAddresses[3] = address(testBUSD);
    }

    function _setupInvoiceManager() internal {
        _testSetup();

        vm.startPrank(deployer.pub);

        // Deploy InvoiceManager with separate protocol fee receiver
        invoiceManager = new InvoiceManager(deployer.pub, credibleAccount.pub, protocolFeeReceiver.pub, feeManager.pub);

        vm.label(address(invoiceManager), "InvoiceManager");

        // Add whitelisted tokens
        invoiceManager.addTokensToWhitelist(whitelistedTokenAddresses);

        // Grant additional roles
        invoiceManager.grantSettlerRole(settler.pub);
        invoiceManager.grantSolverManagerRole(solverManager.pub);

        vm.stopPrank();

        // Set up default token data
        _setupDefaultTokenData();
    }

    function _setupDefaultTokenData() internal {
        // Clear existing data
        delete defaultTokenData;

        // Single token support (USDC only)
        defaultTokenData.push(TokenData({token: address(testUSDC), amount: DEFAULT_USDC_AMOUNT}));
    }

    function _onboardDefaultSolvers() internal {
        vm.startPrank(solverManager.pub);

        // Onboard solver1 with percentage-based fees
        invoiceManager.onboardSolver(
            solver.pub, // executionAddress
            solver.pub, // feeAddress (same as execution)
            feeReceiver.pub, // orchestratorReceiver
            "Solver One",
            ISolverManager.FeeType.PERCENTAGE,
            50, // 0.5% orchestrator fee
            ISolverManager.FeeType.PERCENTAGE,
            20 // 0.2% solver fee
        );

        // Onboard solver2 with fixed fees
        invoiceManager.onboardSolver(
            solver2.pub, // executionAddress
            solver2.pub, // feeAddress (same as execution)
            feeReceiver.pub, // orchestratorReceiver
            "Solver Two",
            ISolverManager.FeeType.FIXED,
            10, // 10 cents orchestrator fee
            ISolverManager.FeeType.FIXED,
            5 // 5 cents solver fee
        );

        vm.stopPrank();
    }

    function _createSampleInvoice() internal returns (address sessionKey_) {
        // Mint tokens to invoice manager for settlement
        _mintTokensToInvoiceManager();

        vm.startPrank(credibleAccount.pub);

        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        invoiceManager.createInvoice(createInvoiceData);

        vm.stopPrank();

        return sessionKey.pub;
    }

    function _mintTokensToInvoiceManager() internal {
        // Mint tokens to invoice manager for settlement testing
        testUSDC.mint(address(invoiceManager), DEFAULT_USDC_AMOUNT * 10);
        testUSDT.mint(address(invoiceManager), DEFAULT_USDT_AMOUNT * 10);
        testDAI.mint(address(invoiceManager), DEFAULT_DAI_AMOUNT * 10);
        testBUSD.mint(address(invoiceManager), DEFAULT_BUSD_AMOUNT * 10);
    }

    function _mintTokensToUser(User memory _user, uint256 _multiplier) internal {
        testUSDC.mint(_user.pub, DEFAULT_USDC_AMOUNT * _multiplier);
        testUSDT.mint(_user.pub, DEFAULT_USDT_AMOUNT * _multiplier);
        testDAI.mint(_user.pub, DEFAULT_DAI_AMOUNT * _multiplier);
        testBUSD.mint(_user.pub, DEFAULT_BUSD_AMOUNT * _multiplier);
    }

    function _createInvoiceData(address _smartWallet, address _sessionKey, address _solver, bytes32 _bidHash)
        internal
        view
        returns (bytes memory)
    {
        return abi.encode(_smartWallet, _sessionKey, _solver, _bidHash, block.chainid, defaultTokenData);
    }

    function _createTokenData(address[] memory _tokens, uint256[] memory _amounts)
        internal
        pure
        returns (TokenData[] memory tokenData)
    {
        require(_tokens.length == _amounts.length, "Arrays length mismatch");

        tokenData = new TokenData[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenData[i] = TokenData({token: _tokens[i], amount: _amounts[i]});
        }
    }

    function _createSingleTokenData(address _token, uint256 _amount)
        internal
        pure
        returns (TokenData[] memory tokenData)
    {
        tokenData = new TokenData[](1);
        tokenData[0] = TokenData({token: _token, amount: _amount});
    }

    function _getTokenBalances(address _account, address[] memory _tokens)
        internal
        view
        returns (uint256[] memory balances)
    {
        balances = new uint256[](_tokens.length);
        for (uint256 i; i < _tokens.length; ++i) {
            balances[i] = IERC20(_tokens[i]).balanceOf(_account);
        }
    }

    function _createMultipleInvoices(uint256 _count) internal returns (address[] memory sessionKeys) {
        sessionKeys = new address[](_count);

        vm.startPrank(credibleAccount.pub);

        for (uint256 i; i < _count; ++i) {
            bytes32 bidHash = keccak256(abi.encodePacked("bid_hash_", i));
            address sessionKey = address(uint160(uint256(keccak256(abi.encodePacked("session_key_", i)))));

            bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey, solver.pub, bidHash);

            invoiceManager.createInvoice(createInvoiceData);
            sessionKeys[i] = sessionKey;
        }

        vm.stopPrank();
    }

    function _settleInvoiceAsSettler(address _sessionKey) internal {
        // Mint tokens to contract
        _mintTokensToInvoiceManager();

        // Credit tokens before settlement
        _creditTokensToInvoice(_sessionKey);
        vm.prank(settler.pub);
        invoiceManager.settleInvoice(_sessionKey);
    }

    /**
     * @notice Calculate total fees for a token amount based on solver configuration
     * @param _solver Solver address
     * @param _token Token address
     * @param _amount Token amount
     * @return protocolFee Protocol fee amount
     * @return orchestratorFee Orchestrator fee amount
     * @return solverFee Solver fee amount
     * @return totalFees Sum of all fees
     */
    function _calculateExpectedTotalFees(address _solver, address _token, uint256 _amount)
        internal
        view
        returns (uint256 protocolFee, uint256 orchestratorFee, uint256 solverFee, uint256 totalFees)
    {
        // Get solver data
        ISolverManager.Solver memory solverData = invoiceManager.getSolverData(_solver);

        uint8 decimals = IERC20Metadata(_token).decimals();

        // Protocol fee (5 cents fixed)
        protocolFee = (invoiceManager.protocolFeeFixed() * 10 ** decimals) / 100;
        uint256 remaining = _amount - protocolFee;

        // Orchestrator fee
        if (solverData.orchestratorFeeType == ISolverManager.FeeType.FIXED) {
            orchestratorFee = (solverData.orchestratorFeeValue * 10 ** decimals) / 100;
        } else {
            orchestratorFee = (remaining * solverData.orchestratorFeeValue) / 10000;
        }
        remaining = remaining - orchestratorFee;

        // Solver fee
        if (solverData.solverFeeType == ISolverManager.FeeType.FIXED) {
            solverFee = (solverData.solverFeeValue * 10 ** decimals) / 100;
        } else {
            solverFee = (remaining * solverData.solverFeeValue) / 10000;
        }

        totalFees = protocolFee + orchestratorFee + solverFee;
    }

    /**
     * @notice Calculate only protocol fee for backward compatibility with tests
     */
    function _calculateExpectedFeeForToken(address _token, uint256 _feeOverride) internal view returns (uint256) {
        uint256 protocolFee = invoiceManager.protocolFeeFixed();

        try IERC20Metadata(_token).decimals() returns (uint8 decimals) {
            return (protocolFee * 10 ** decimals) / 100;
        } catch {
            return (protocolFee * 10 ** 18) / 100;
        }
    }

    function _settleInvoiceAsSmartWallet(address _sessionKey, address _smartWallet) internal {
        vm.prank(_smartWallet);
        invoiceManager.settleInvoice(_sessionKey);
    }

    function _creditTokensToInvoice(address _sessionKey) internal {
        (InvoiceManager.Invoice memory invoice, InvoiceManager.InvoiceTokenData[] memory tokens) =
            invoiceManager.getInvoice(_sessionKey);

        vm.startPrank(credibleAccount.pub);
        for (uint256 i; i < tokens.length; ++i) {
            invoiceManager.creditTokensToInvoice(_sessionKey, tokens[i].token, tokens[i].amount);
        }
        vm.stopPrank();
    }
}
