// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IInvoiceManager} from "../../../../src/interfaces/IInvoiceManager.sol";
import {InvoiceManager} from "../../../../src/utils/InvoiceManager.sol";
import {TestERC20} from "../../../../src/test/TestERC20.sol";
import {TestUSDC} from "../../../../src/test/TestUSDC.sol";
import {TokenData} from "../../../../src/common/Structs.sol";
import "../../../ModularTestBase.sol";

contract InvoiceManagerTestUtils is ModularTestBase {
    using ECDSA for bytes32;

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
    User internal feeReceiver;
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
    uint256 internal constant DEFAULT_FEE_AMOUNT = 0; // Use calculated default
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
        feeReceiver = _createUser("Fee Receiver");
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

        // Deploy InvoiceManager with whitelisted tokens
        invoiceManager = new InvoiceManager(deployer.pub, credibleAccount.pub, feeReceiver.pub, feeManager.pub);

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

        // Add default token amounts
        defaultTokenData.push(TokenData({token: address(testUSDC), amount: DEFAULT_USDC_AMOUNT}));

        defaultTokenData.push(TokenData({token: address(testUSDT), amount: DEFAULT_USDT_AMOUNT}));

        defaultTokenData.push(TokenData({token: address(testDAI), amount: DEFAULT_DAI_AMOUNT}));
    }

    function _onboardDefaultSolvers() internal {
        vm.startPrank(solverManager.pub);

        // Onboard solver1 with default fee (0 = use calculated per-token fee)
        invoiceManager.onboardSolver(solver.pub, "Solver One", DEFAULT_FEE_AMOUNT);

        // Onboard solver2 with custom fee (50 = 0.5 USDC fixed fee)
        invoiceManager.onboardSolver(solver2.pub, "Solver Two", HIGH_FEE_AMOUNT);

        vm.stopPrank();
    }

    function _createSampleInvoice() internal returns (address sessionKey_) {
        // Mint tokens to invoice manager for settlement
        _mintTokensToInvoiceManager();

        vm.startPrank(credibleAccount.pub);

        bytes memory createInvoiceData = _createInvoiceData(address(scw), sessionKey.pub, solver.pub, DEFAULT_BID_HASH);

        sessionKey_ = invoiceManager.createInvoice(createInvoiceData);

        vm.stopPrank();

        return sessionKey_;
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

    function _calculateExpectedFees(TokenData[] memory _tokenData, uint256 _feePercentage)
        internal
        pure
        returns (uint256 totalFees, uint256 totalSolverAmount)
    {
        for (uint256 i = 0; i < _tokenData.length; i++) {
            uint256 fee = (_tokenData[i].amount * _feePercentage) / 10000; // BASIS_POINTS
            uint256 solverAmount = _tokenData[i].amount - fee;
            totalFees += fee;
            totalSolverAmount += solverAmount;
        }
    }

    function _getTokenBalances(address _account, address[] memory _tokens)
        internal
        view
        returns (uint256[] memory balances)
    {
        balances = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
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

            sessionKeys[i] = invoiceManager.createInvoice(createInvoiceData);
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

    function _settleInvoiceAsSmartWallet(address _sessionKey, address _smartWallet) internal {
        vm.prank(_smartWallet);
        invoiceManager.settleInvoice(_sessionKey);
    }

    function _calculateExpectedFeeForToken(address _token, uint256 _feeOverride) internal view returns (uint256) {
        // Use the same constant as the contract
        uint256 pulseFee = _feeOverride == 0 ? invoiceManager.PULSE_BASE_FEE() : _feeOverride;

        try IERC20Metadata(_token).decimals() returns (uint8 decimals) {
            return (pulseFee * 10 ** decimals) / 100;
        } catch {
            return (pulseFee * 10 ** 18) / 100;
        }
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
