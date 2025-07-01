// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./utils/GasTankPaymasterTestUtils.sol";

contract GasTankPaymasterTest is GasTankPaymasterTestUtils {
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();
        _testSetup();
    }

    /*//////////////////////////////////////////////////////////////
                             HELPER EVENTS
    //////////////////////////////////////////////////////////////*/

    event GasTankPaymaster_MinVSTokenBalanceUpdated(uint256 oldMinBalance, uint256 newMinBalance);
    event GasTankPaymaster_InsufficientBalanceButTopUpRequired(uint256 currentBalance, uint256 minRequired);
    event GasTankPaymaster_TopUpSkippedDueToStalePrice();
    event GasTankPaymaster_NativeWithdrawn(address indexed to, uint256 amount);
    event GasTankPaymaster_WrappedNativeWithdrawn(address indexed to, uint256 amount);
    event GasTankPaymaster_EmergencyUnsupportedTokenRecovery(address indexed token, address indexed to, uint256 amount);
    event GasTankPaymaster_Received(address indexed sender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                         BASIC FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    // Gas Tank Deposits - Self
    function test_gasTankDeposit_forSelf() public {
        _depositToGasTank(gasTankUSDC, address(usdc), user1, USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(user1), USDC_INITIAL_MINT - USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(user1), USDC_DEPOSIT_AMOUNT);
    }

    function test_gasTankDeposit_forSelf_multipleDeposits() public {
        _depositToGasTank(gasTankUSDC, address(usdc), user1, USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(user1), USDC_DEPOSIT_AMOUNT);
        _depositToGasTank(gasTankUSDC, address(usdc), user1, USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(user1), USDC_DEPOSIT_AMOUNT * 2);
        _depositToGasTank(gasTankUSDC, address(usdc), user1, USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(user1), USDC_DEPOSIT_AMOUNT * 3);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), USDC_DEPOSIT_AMOUNT * 3);
        assertEq(usdc.balanceOf(user1), USDC_INITIAL_MINT - USDC_DEPOSIT_AMOUNT * 3);
    }

    function test_gasTankDeposit_forSelf_revertWhen_insufficientAllowance() public {
        vm.startPrank(user1);
        usdc.approve(address(gasTankUSDC), USDC_DEPOSIT_AMOUNT / 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(gasTankUSDC),
                USDC_DEPOSIT_AMOUNT / 2,
                USDC_DEPOSIT_AMOUNT
            )
        );
        gasTankUSDC.gasTankDeposit(USDC_DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_gasTankDeposit_forSelf_revertWhen_insufficientBalance() public {
        address poorUser = makeAddr("poorUser");
        vm.startPrank(poorUser);
        usdc.approve(address(gasTankUSDC), USDC_DEPOSIT_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, poorUser, 0, USDC_DEPOSIT_AMOUNT)
        );
        gasTankUSDC.gasTankDeposit(USDC_DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_gasTankDeposit_forSelf_revertWhen_zeroAmount() public {
        vm.startPrank(user1);
        usdc.approve(address(gasTankUSDC), 0);
        vm.expectRevert(abi.encodeWithSelector(GasTankPaymaster.GasTankPaymaster_InvalidAmount.selector));
        gasTankUSDC.gasTankDeposit(0);
        vm.stopPrank();
    }

    // Gas Tank Deposits - For Another Wallet
    function test_gasTankDeposit_forAnotherWallet() public {
        _depositToGasTankForWallet(gasTankUSDC, address(usdc), user1, user2, USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(user1), USDC_INITIAL_MINT - USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(user2), USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(user1), 0);
    }

    function test_gasTankDeposit_forAnotherWallet_withExistingBalance() public {
        _depositToGasTankForWallet(gasTankUSDC, address(usdc), user1, user2, USDC_DEPOSIT_AMOUNT);
        _depositToGasTankForWallet(gasTankUSDC, address(usdc), user1, user2, USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), USDC_DEPOSIT_AMOUNT * 2);
        assertEq(usdc.balanceOf(user1), USDC_INITIAL_MINT - USDC_DEPOSIT_AMOUNT * 2);
        assertEq(gasTankUSDC.gasTankBalance(user2), USDC_DEPOSIT_AMOUNT * 2);
    }

    function test_gasTankDeposit_forAnotherWallet_transfersFromSpecifiedWallet() public {
        _depositToGasTankForWallet(gasTankUSDC, address(usdc), user1, user2, USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(user1), USDC_INITIAL_MINT - USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(user2), USDC_INITIAL_MINT);
        assertEq(gasTankUSDC.gasTankBalance(user2), USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(user1), 0);
    }

    function test_gasTankDeposit_forAnotherWallet_revertWhen_zeroAddress() public {
        vm.startPrank(user1);
        usdc.approve(address(gasTankUSDC), USDC_DEPOSIT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(GasTankPaymaster.GasTankPaymaster_InvalidAddress.selector));
        gasTankUSDC.gasTankDeposit(address(0), USDC_DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    // Gas Tank Withdrawals
    function test_gasTankWithdraw_partial() public {
        _depositToGasTank(gasTankUSDC, address(usdc), user1, USDC_DEPOSIT_AMOUNT);
        _withdrawFromGasTank(gasTankUSDC, address(usdc), user1, USDC_WITHDRAW_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(user1), USDC_DEPOSIT_AMOUNT - USDC_WITHDRAW_AMOUNT);
        assertEq(usdc.balanceOf(user1), USDC_INITIAL_MINT - USDC_DEPOSIT_AMOUNT + USDC_WITHDRAW_AMOUNT);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), USDC_DEPOSIT_AMOUNT - USDC_WITHDRAW_AMOUNT);
    }

    function test_gasTankWithdraw_full() public {
        _depositToGasTank(gasTankUSDC, address(usdc), user1, USDC_DEPOSIT_AMOUNT);
        _withdrawFromGasTank(gasTankUSDC, address(usdc), user1, USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(user1), 0);
        assertEq(usdc.balanceOf(user1), USDC_INITIAL_MINT);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), 0);
    }

    function test_gasTankWithdraw_revertWhen_insufficientBalance() public {
        _depositToGasTank(gasTankUSDC, address(usdc), user1, USDC_DEPOSIT_AMOUNT);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                GasTankPaymaster.GasTankPaymaster_InsufficientBalance.selector, user1, USDC_DEPOSIT_AMOUNT + 1
            )
        );
        gasTankUSDC.gasTankWithdraw(USDC_DEPOSIT_AMOUNT + 1);
    }

    function test_gasTankWithdraw_RevertWhen_NoBalance() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                GasTankPaymaster.GasTankPaymaster_InsufficientBalance.selector, user1, USDC_WITHDRAW_AMOUNT
            )
        );
        gasTankUSDC.gasTankWithdraw(USDC_WITHDRAW_AMOUNT);
    }

    // Gas Tank Balance Queries
    function test_gasTankBalance() public {
        assertEq(gasTankUSDC.gasTankBalance(user1), 0);
        _depositToGasTank(gasTankUSDC, address(usdc), user1, USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(user1), USDC_DEPOSIT_AMOUNT);
        _withdrawFromGasTank(gasTankUSDC, address(usdc), user1, USDC_WITHDRAW_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(user1), USDC_DEPOSIT_AMOUNT - USDC_WITHDRAW_AMOUNT);
    }

    function test_gasTankBalance_multipleUsers() public {
        _depositToGasTank(gasTankUSDC, address(usdc), user1, USDC_DEPOSIT_AMOUNT);
        _depositToGasTank(gasTankUSDC, address(usdc), user2, USDC_DEPOSIT_AMOUNT * 2);
        assertEq(gasTankUSDC.gasTankBalance(user1), USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(user2), USDC_DEPOSIT_AMOUNT * 2);
    }

    /*//////////////////////////////////////////////////////////////
                       ACCESS CONTROL & PAUSABILITY
    //////////////////////////////////////////////////////////////*/

    function test_pause_success() public {
        assertFalse(gasTankUSDC.isPaused());
        vm.prank(deployer);
        gasTankUSDC.pause();
        assertTrue(gasTankUSDC.isPaused());
    }

    function test_unpause_success() public {
        vm.prank(deployer);
        gasTankUSDC.pause();
        assertTrue(gasTankUSDC.isPaused());
        vm.prank(deployer);
        gasTankUSDC.unpause();
        assertFalse(gasTankUSDC.isPaused());
    }

    function test_pause_revertWhen_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        gasTankUSDC.pause();
    }

    function test_unpause_revertWhen_notOwner() public {
        vm.prank(deployer);
        gasTankUSDC.pause();
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        gasTankUSDC.unpause();
        assertTrue(gasTankUSDC.isPaused());
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_transferOwnership() public {
        vm.prank(deployer);
        _transferOwnership(gasTankUSDC, user1);
        assertEq(gasTankUSDC.owner(), user1);
    }

    function test_setVerifyingSigner() public {
        (address payable newVerifyingSigner, uint256 newVerifyingSignerKey) =
            _makePayableAddrAndKey("newVerifyingSigner");
        vm.startPrank(deployer);
        _setVerifyingSigner(gasTankUSDC, newVerifyingSigner);
        assertEq(gasTankUSDC.verifyingSigner(), newVerifyingSigner);
    }

    function test_setSwapRouter() public {
        address newSwapRouter = makeAddr("newSwapRouter");
        vm.prank(deployer);
        _setSwapRouter(gasTankUSDC, newSwapRouter);
        assertEq(address(gasTankUSDC.uniswap()), newSwapRouter);
    }

    function test_setSupportedToken() public {
        address newToken = makeAddr("newToken");
        vm.prank(deployer);
        _setSupportedToken(gasTankUSDC, newToken);
        assertEq(address(gasTankUSDC.supportedToken()), newToken);
    }

    function test_withdrawFromEntryPoint() public {
        uint256 withdrawAmount = 0.5 ether;
        uint256 initialDeposit = _getEntryPointDeposit(gasTankUSDC);
        vm.prank(deployer);
        _withdrawFromEntryPoint(gasTankUSDC, beneficiary, withdrawAmount);
        uint256 newDeposit = _getEntryPointDeposit(gasTankUSDC);
        assertEq(newDeposit, initialDeposit - withdrawAmount);
    }

    function test_configurePaymaster() public {
        uint256 newMarkup = PRICE_DENOMINATOR * 15 / 10;
        uint128 newMinEPBalance = 2 ether;
        uint48 newPostOpCost = 40000;
        uint48 newPriceMaxAge = 2 hours;
        _configurePaymaster(gasTankUSDC, newMarkup, newMinEPBalance, newPostOpCost, newPriceMaxAge);
        GasTankPaymaster.GasTankPaymasterConfig memory config = gasTankUSDC.getPaymasterConfig();
        assertEq(config.markup, newMarkup);
        assertEq(config.minEPBalance, newMinEPBalance);
        assertEq(config.postOpCost, newPostOpCost);
        assertEq(config.priceMaxAge, newPriceMaxAge);
    }

    function test_updateMinVSTokenBalance_success() public {
        uint256 newMinBalance = 5 * 10 ** 6; // 5 USDC
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_MinVSTokenBalanceUpdated(10 * 10 ** 6, newMinBalance);
        gasTankUSDC.updateMinVSTokenBalance(newMinBalance);
        GasTankPaymaster.GasTankPaymasterConfig memory config = gasTankUSDC.getPaymasterConfig();
        assertEq(config.minVSTokenBalance, newMinBalance);
    }

    function test_transferOwnership_revertWhen_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        gasTankUSDC.transferOwnership(user2);
    }

    function test_configurePaymaster_revertWhen_notOwner() public {
        GasTankPaymaster.GasTankPaymasterConfig memory currentConfig = gasTankUSDC.getPaymasterConfig();
        currentConfig.markup = PRICE_DENOMINATOR * 15 / 10;
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        gasTankUSDC.configurePaymaster(currentConfig);
    }

    function test_configurePaymaster_revertWhen_markupTooLow() public {
        uint256 tooLowMarkup = PRICE_DENOMINATOR * 9 / 10;
        GasTankPaymaster.GasTankPaymasterConfig memory testConfig = gasTankUSDC.getPaymasterConfig();
        testConfig.markup = tooLowMarkup;
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(GasTankPaymaster.GasTankPaymaster_PriceMarkupTooLow.selector, tooLowMarkup)
        );
        gasTankUSDC.configurePaymaster(testConfig);
    }

    function test_configurePaymaster_revertWhen_markupTooHigh() public {
        uint256 tooHighMarkup = PRICE_DENOMINATOR * 21 / 10;
        GasTankPaymaster.GasTankPaymasterConfig memory testConfig = gasTankUSDC.getPaymasterConfig();
        testConfig.markup = tooHighMarkup;
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(GasTankPaymaster.GasTankPaymaster_PriceMarkupTooHigh.selector, tooHighMarkup)
        );
        gasTankUSDC.configurePaymaster(testConfig);
    }

    function test_setVerifyingSigner_revertWhen_notOwner() public {
        (address payable maliciousUser, uint256 maliciousKey) = _makePayableAddrAndKey("maliciousUser");
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        gasTankUSDC.setVerifyingSigner(maliciousUser);
    }

    function test_updateMinVSTokenBalance_revertWhen_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        gasTankUSDC.updateMinVSTokenBalance(5 * 10 ** 6);
    }

    function test_updateMinVSTokenBalance_revertWhen_invalidNewMinimumTopup() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(GasTankPaymaster.GasTankPaymaster_InvalidVSMinimumTopupBalance.selector));
        gasTankUSDC.updateMinVSTokenBalance(0);
    }

    function test_addStake() public {
        vm.startPrank(deployer);
        uint256 initStake = _getEntryPointStake(gasTankUSDC);
        uint256 stakeAmount = 1 ether;
        uint32 unstakeDelay = 86400;
        _addStake(gasTankUSDC, stakeAmount, unstakeDelay);
        uint256 stake = _getEntryPointStake(gasTankUSDC);
        assertEq(stake, initStake + stakeAmount);
        vm.stopPrank();
    }

    function test_withdrawFromEntryPoint_revertWhen_insufficientDeposit() public {
        uint256 initialDeposit = _getEntryPointDeposit(gasTankUSDC);
        vm.prank(deployer);
        vm.expectRevert("Withdraw amount too large");
        gasTankUSDC.withdrawTo(beneficiary, initialDeposit + 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        PAYMASTER STATUS QUERIES  
    //////////////////////////////////////////////////////////////*/

    function test_getPaymasterStatus_needsTopUp_false() public {
        uint256 currentBalance = entrypoint.balanceOf(address(gasTankUSDC));
        if (currentBalance < 5 ether) {
            vm.deal(owner1, 10 ether);
            vm.prank(owner1);
            gasTankUSDC.deposit{value: 10 ether}();
        }
        GasTankPaymaster.GasTankPaymasterConfig memory newConfig = gasTankUSDC.getPaymasterConfig();
        newConfig.minEPBalance = 0.1 ether;
        vm.prank(deployer);
        gasTankUSDC.configurePaymaster(newConfig);
        (,,,, bool needsTopUp,) = gasTankUSDC.getPaymasterStatus();
        assertFalse(needsTopUp);
    }

    /*//////////////////////////////////////////////////////////////
                  PAYMASTER VALIDATION & PROCESSING
    //////////////////////////////////////////////////////////////*/

    function test_validatePaymasterUserOp_validSignature() public {
        bytes memory callData = abi.encodeWithSignature("execute()");
        vm.warp(block.timestamp + 1 days);
        uint48 validUntil = uint48(block.timestamp + 1 hours);
        uint48 validAfter = uint48(block.timestamp - 1 minutes);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC, address(mew), owner1Key, callData, 1 gwei, 1 gwei, verifyingSignerKey, validUntil, validAfter
        );
        vm.prank(address(entrypoint));
        (bytes memory context, uint256 validationData) =
            gasTankUSDC.validatePaymasterUserOp(userOp, keccak256("dummy"), 1 ether);
        assertEq(context.length, 64);
        bool sigFailed = (validationData & 1) == 1;
        uint48 returnedValidUntil = uint48(validationData >> 160);
        uint48 returnedValidAfter = uint48(validationData >> 208);
        assertFalse(sigFailed);
        assertEq(returnedValidUntil, validUntil);
        assertEq(returnedValidAfter, validAfter);
    }

    function test_validatePaymasterUserOp_invalidSignature() public {
        bytes memory callData = abi.encodeWithSignature("execute()");
        vm.warp(block.timestamp + 1 days);
        uint48 validUntil = uint48(block.timestamp + 1 hours);
        uint48 validAfter = uint48(block.timestamp - 1 minutes);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC, address(mew), owner1Key, callData, 1 gwei, 1 gwei, user1Key, validUntil, validAfter
        );
        vm.prank(address(entrypoint));
        (bytes memory context, uint256 validationData) =
            gasTankUSDC.validatePaymasterUserOp(userOp, keccak256("dummy"), 1 ether);
        assertEq(context.length, 0);
        assertTrue((validationData & 1) == 1);
    }

    function test_validatePaymasterUserOp_revertWhen_invalidSignatureLength() public {
        bytes memory callData = abi.encodeWithSignature("execute()");
        vm.warp(block.timestamp + 1 days);
        uint48 validUntil = uint48(block.timestamp + 1 hours);
        uint48 validAfter = uint48(block.timestamp - 1 minutes);
        PackedUserOperation memory userOp = _createUserOperation(address(mew), callData, 1 gwei, 1 gwei, user1Key);
        bytes memory invalidSignature = new bytes(63);
        bytes memory paymasterData = abi.encodePacked(abi.encode(validUntil, validAfter), invalidSignature);
        userOp.paymasterAndData =
            abi.encodePacked(address(gasTankUSDC), uint128(300000), uint128(300000), paymasterData);
        vm.prank(address(entrypoint));
        vm.expectRevert(
            abi.encodeWithSelector(GasTankPaymaster.GasTankPaymaster_InvalidPaymasterAndDataSignatureLength.selector)
        );
        gasTankUSDC.validatePaymasterUserOp(userOp, keccak256("dummy"), 1 ether);
    }

    function test_validatePaymasterUserOp_expiredSignature() public {
        bytes memory callData = abi.encodeWithSignature("execute()");
        vm.warp(block.timestamp + 1 days);
        uint48 validUntil = uint48(block.timestamp - 1 hours); // Already expired
        uint48 validAfter = uint48(block.timestamp - 2 hours);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC, address(mew), owner1Key, callData, 1 gwei, 1 gwei, verifyingSignerKey, validUntil, validAfter
        );
        vm.prank(address(entrypoint));
        (bytes memory context, uint256 validationData) =
            gasTankUSDC.validatePaymasterUserOp(userOp, keccak256("dummy"), 1 ether);
        assertEq(context.length, 64);
        uint48 returnedValidUntil = uint48(validationData >> 160);
        uint48 returnedValidAfter = uint48(validationData >> 208);
        assertEq(returnedValidUntil, validUntil);
        assertEq(returnedValidAfter, validAfter);
    }

    function test_parsePaymasterAndData() public {
        uint48 validUntil = uint48(block.timestamp + 1 hours);
        uint48 validAfter = uint48(block.timestamp);
        bytes memory signature =
            hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12";
        bytes memory paymasterData = abi.encodePacked(
            address(gasTankUSDC), // paymaster address (20 bytes)
            uint128(300000), // verificationGasLimit (16 bytes)
            uint128(300000), // postOpGasLimit (16 bytes)
            validUntil, // validUntil (6 bytes when packed)
            validAfter, // validAfter (6 bytes when packed)
            signature // signature (64+ bytes)
        );
        (uint48 parsedUntil, uint48 parsedAfter, bytes memory parsedSig) =
            gasTankUSDC.parsePaymasterAndData(paymasterData);
        assertEq(parsedUntil, validUntil, "validUntil should match");
        assertEq(parsedAfter, validAfter, "validAfter should match");
        assertEq(parsedSig, signature, "signature should match");
    }

    function test_getHash() public {
        // Create a user operation with properly formatted paymasterAndData
        PackedUserOperation memory userOp = _createBasicUserOp();
        // Add minimal paymaster data structure (paymaster address + gas limits)
        userOp.paymasterAndData = abi.encodePacked(
            address(gasTankUSDC), // paymaster address (20 bytes)
            uint128(300000), // verificationGasLimit (16 bytes)
            uint128(300000) // postOpGasLimit (16 bytes)
                // Total: 52 bytes, which matches PAYMASTER_DATA_OFFSET
        );
        uint48 validUntil = uint48(block.timestamp + 1 hours);
        uint48 validAfter = uint48(block.timestamp);
        bytes32 hash1 = gasTankUSDC.getHash(userOp, validUntil, validAfter);
        bytes32 hash2 = gasTankUSDC.getHash(userOp, validUntil, validAfter);
        assertEq(hash1, hash2, "Same inputs should produce same hash");
        // Test with different values
        bytes32 hash3 = gasTankUSDC.getHash(userOp, validUntil + 1, validAfter);
        assertNotEq(hash1, hash3, "Different inputs should produce different hash");
        // Test with different validAfter
        bytes32 hash4 = gasTankUSDC.getHash(userOp, validUntil, validAfter + 1);
        assertNotEq(hash1, hash4, "Different validAfter should produce different hash");
        // Test with different sender
        userOp.sender = address(0x123);
        bytes32 hash5 = gasTankUSDC.getHash(userOp, validUntil, validAfter);
        assertNotEq(hash1, hash5, "Different sender should produce different hash");
    }

    function test_validatePaymasterUserOp_revertWhen_paused() public {
        vm.prank(deployer);
        gasTankUSDC.pause();
        PackedUserOperation memory userOp = _createBasicUserOp();
        vm.prank(address(entrypoint));
        vm.expectRevert(GasTankPaymaster.GasTankPaymaster_IsPaused.selector);
        gasTankUSDC.validatePaymasterUserOp(userOp, keccak256("dummy"), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    SPONSORED TRANSACTION REPAYMENT
    //////////////////////////////////////////////////////////////*/

    function test_repaySponsoredTransaction_success() public {
        vm.startPrank(user1);
        usdc.approve(address(gasTankUSDC), 1000 * 10 ** 6);
        gasTankUSDC.gasTankDeposit(1000 * 10 ** 6);
        vm.stopPrank();
        uint256 initialFromBalance = gasTankUSDC.gasTankBalance(user1);
        uint256 initialVerifyingSignerBalance = gasTankUSDC.gasTankBalance(verifyingSigner);
        uint256 repayAmount = 500 * 10 ** 6;
        vm.prank(deployer);
        gasTankUSDC.repaySponsoredTransaction(user1, repayAmount);
        assertEq(gasTankUSDC.gasTankBalance(user1), initialFromBalance - repayAmount);
        assertEq(gasTankUSDC.gasTankBalance(verifyingSigner), initialVerifyingSignerBalance + repayAmount);
    }

    function test_repaySponsoredTransaction_exactBalance() public {
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.startPrank(user1);
        usdc.approve(address(gasTankUSDC), depositAmount);
        gasTankUSDC.gasTankDeposit(depositAmount);
        vm.stopPrank();
        uint256 initialVerifyingSignerBalance = gasTankUSDC.gasTankBalance(verifyingSigner);
        vm.prank(deployer);
        gasTankUSDC.repaySponsoredTransaction(user1, depositAmount);
        assertEq(gasTankUSDC.gasTankBalance(user1), 0);
        assertEq(gasTankUSDC.gasTankBalance(verifyingSigner), initialVerifyingSignerBalance + depositAmount);
    }

    function test_repaySponsoredTransaction_revertWhen_insufficientBalance() public {
        vm.startPrank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                GasTankPaymaster.GasTankPaymaster_InsufficientBalance.selector, user1, 1000 * 10 ** 6
            )
        );
        gasTankUSDC.repaySponsoredTransaction(user1, 1000 * 10 ** 6);
        vm.stopPrank();
    }

    function test_repaySponsoredTransaction_revertWhen_invalidAddress() public {
        vm.prank(deployer);
        vm.expectRevert(GasTankPaymaster.GasTankPaymaster_InvalidAddress.selector);
        gasTankUSDC.repaySponsoredTransaction(address(0), 100 * 10 ** 6);
    }

    function test_repaySponsoredTransaction_revertWhen_invalidAmount() public {
        vm.prank(deployer);
        vm.expectRevert(GasTankPaymaster.GasTankPaymaster_InvalidAmount.selector);
        gasTankUSDC.repaySponsoredTransaction(user1, 0);
    }

    /*//////////////////////////////////////////////////////////////
                         PRICE & ORACLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function test_updateCachedPrice_invalidTokenPrice() public {
        vm.startPrank(verifyingSigner);
        TestOracle(address(usdcOracle)).configurePrice(0);
        TestOracle(address(nativeOracle)).configurePrice(2000e8);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    function test_updateCachedPrice_invalidNativePrice() public {
        vm.startPrank(verifyingSigner);
        TestOracle(address(usdcOracle)).configurePrice(1e8);
        TestOracle(address(nativeOracle)).configurePrice(-100e8);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    function test_updateCachedPrice_staleTokenPrice() public {
        vm.startPrank(verifyingSigner);
        uint256 oldTimestamp = block.timestamp;
        TestOracle(address(usdcOracle)).configurePrice(1e8);
        TestOracle(address(usdcOracle)).configureUpdatedAt(oldTimestamp);
        TestOracle(address(nativeOracle)).configurePrice(2000e8);
        uint256 priceMaxAge = gasTankUSDC.getPaymasterConfig().priceMaxAge;
        vm.warp(oldTimestamp + priceMaxAge + 1);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    function test_updateCachedPrice_staleNativePrice() public {
        vm.startPrank(verifyingSigner);
        uint256 oldTimestamp = block.timestamp;
        TestOracle(address(usdcOracle)).configurePrice(1e8);
        TestOracle(address(nativeOracle)).configurePrice(2000e8);
        TestOracle(address(nativeOracle)).configureUpdatedAt(oldTimestamp);
        uint256 priceMaxAge = gasTankUSDC.getPaymasterConfig().priceMaxAge;
        vm.warp(oldTimestamp + priceMaxAge + 1);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    function test_updateCachedPrice_oracleRevert() public {
        vm.startPrank(verifyingSigner);
        TestOracle(address(usdcOracle)).configureShouldRevert(true);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    function test_updateCachedPrice_oracleReturnsZero() public {
        vm.startPrank(verifyingSigner);
        TestOracle(address(usdcOracle)).configurePrice(0);
        TestOracle(address(nativeOracle)).configurePrice(2000e8);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    function test_updateCachedPrice_oracleReturnsNegative() public {
        vm.startPrank(verifyingSigner);
        TestOracle(address(usdcOracle)).configurePrice(-1e8);
        TestOracle(address(nativeOracle)).configurePrice(2000e8);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       ENTRYPOINT TOP-UP FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    function test_topUpEntryPointDeposit_belowMinimum() public {
        vm.startPrank(address(uniswapV3));
        usdc.mint(address(uniswapV3), 50000 * 10 ** 6);
        vm.deal(address(uniswapV3), 25 ether);
        weth.deposit{value: 25 ether}();
        vm.stopPrank();
        _depositToGasTank(gasTankUSDC, address(usdc), verifyingSigner, 200 * 10 ** 6);
        _depositToGasTank(gasTankUSDC, address(usdc), user1, 100 * 10 ** 6);
        vm.startPrank(deployer);
        TestOracle(address(usdcOracle)).configurePrice(1e8);
        TestOracle(address(nativeOracle)).configurePrice(2000e8);
        gasTankUSDC.updateCachedPrice(true);
        uint256 initStake = _getEntryPointStake(gasTankUSDC);
        gasTankUSDC.withdrawTo(beneficiary, initStake - 0.96 ether);
        gasTankUSDC.topUpEntryPointDeposit();
        uint256 currentBalance = gasTankUSDC.getDeposit();
        assertGt(currentBalance, 1 ether);
        assertEq(gasTankUSDC.gasTankBalance(verifyingSigner), 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        PAYMASTER STATUS QUERIES  
    //////////////////////////////////////////////////////////////*/

    function test_getPaymasterStatus_basicInfo() public {
        vm.startPrank(verifyingSigner);
        usdcOracle.configurePrice(1e8); // $1 USDT
        nativeOracle.configurePrice(2000e8); // $2000 ETH
        uint256 updatedPrice = gasTankUSDC.updateCachedPrice(true);
        assertGt(updatedPrice, 0, "Price update should succeed");
        _depositToGasTank(gasTankUSDC, address(usdc), verifyingSigner, 500 * 10 ** 6);
        (
            uint256 entryPointBalance,
            uint256 cachedTokenPrice,
            uint48 priceTimestamp,
            uint256 verifyingSignerUSDCBalance,
            bool needsTopUp,
            bool isPaused
        ) = gasTankUSDC.getPaymasterStatus();
        assertEq(cachedTokenPrice, 5e22);
        assertEq(verifyingSignerUSDCBalance, 500 * 10 ** 6);
        assertEq(entryPointBalance, entrypoint.balanceOf(address(gasTankUSDC)));
        assertFalse(isPaused);
    }

    function test_getPaymasterStatus_needsTopUp_true() public {
        GasTankPaymaster.GasTankPaymasterConfig memory newConfig = gasTankUSDC.getPaymasterConfig();
        newConfig.minEPBalance = 10000 ether;
        vm.prank(deployer);
        gasTankUSDC.configurePaymaster(newConfig);
        (,,,, bool needsTopUp,) = gasTankUSDC.getPaymasterStatus();
        assertTrue(needsTopUp);
    }

    /*//////////////////////////////////////////////////////////////
                      FULL USER OPERATION FLOWS
    //////////////////////////////////////////////////////////////*/

    function test_fullUserOperationFlow_USDC_withoutTopUp() public {
        uint256 currentEPBalance = gasTankUSDC.getDeposit();
        GasTankPaymaster.GasTankPaymasterConfig memory config = gasTankUSDC.getPaymasterConfig();
        if (currentEPBalance < config.minEPBalance + 0.5 ether) {
            vm.deal(owner1, 1 ether);
            vm.prank(owner1);
            gasTankUSDC.deposit{value: 1 ether}();
        }
        uint256 initialEPBalance = gasTankUSDC.getDeposit();
        assertGt(initialEPBalance, config.minEPBalance);
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(owner1);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(mew),
            owner1Key,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSignerKey,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );
        _executeUserOp(userOp);
        uint256 finalEPBalance = gasTankUSDC.getDeposit();
        assertLt(finalEPBalance, initialEPBalance);
        assertGt(finalEPBalance, config.minEPBalance);
    }

    function test_automaticTopUp_USDC_duringUserOperation() public {
        GasTankPaymaster.GasTankPaymasterConfig memory newConfig = gasTankUSDC.getPaymasterConfig();
        newConfig.markup = PRICE_DENOMINATOR * 12 / 10;
        newConfig.minEPBalance = 2 ether;
        newConfig.postOpCost = 35000;
        newConfig.priceMaxAge = 25 hours;
        vm.prank(deployer);
        gasTankUSDC.configurePaymaster(newConfig);
        vm.deal(address(weth), 100 ether);
        _depositToGasTank(gasTankUSDC, address(usdc), verifyingSigner, 20 * 10 ** 6);
        usdc.mint(address(mew), 100 * 10 ** 6);
        _depositToGasTank(gasTankUSDC, address(usdc), address(mew), 10 * 10 ** 6);
        vm.startPrank(deployer);
        usdcOracle.configurePrice(1e8); // $1 USDT
        nativeOracle.configurePrice(2000e8); // $2000 ETH
        uint256 updatedPrice = gasTankUSDC.updateCachedPrice(true);
        assertGt(updatedPrice, 0, "Price update should succeed");
        uint256 currentBalance = gasTankUSDC.getDeposit();
        gasTankUSDC.withdrawTo(beneficiary, currentBalance - 1.5 ether);
        vm.warp(block.timestamp + 1 days);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(mew),
            owner1Key,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSignerKey,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(owner1Key, ECDSA.toEthSignedMessageHash(userOpHash));
        userOp.signature = abi.encodePacked(r, s, v);
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
        entrypoint.handleOps(userOps, beneficiary);
        uint256 finalEPBalance = gasTankUSDC.getDeposit();
        assertGt(finalEPBalance, 1.4 ether);
        vm.stopPrank();
    }

    function test_fullUserOperationFlow_USDT_withoutTopUp() public {
        uint256 currentEPBalance = gasTankUSDT.getDeposit();
        GasTankPaymaster.GasTankPaymasterConfig memory config = gasTankUSDT.getPaymasterConfig();
        if (currentEPBalance < config.minEPBalance + 0.5 ether) {
            vm.deal(owner1, 1 ether);
            vm.prank(owner1);
            gasTankUSDT.deposit{value: 1 ether}();
        }
        uint256 initialEPBalance = gasTankUSDT.getDeposit();
        assertGt(initialEPBalance, config.minEPBalance);
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(owner1);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDT,
            address(mew),
            owner1Key,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSignerKey,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );
        _executeUserOp(userOp);
        uint256 finalEPBalance = gasTankUSDT.getDeposit();
        assertLt(finalEPBalance, initialEPBalance);
        assertGt(finalEPBalance, config.minEPBalance);
    }

    function test_automaticTopUp_USDT_duringUserOperation() public {
        GasTankPaymaster.GasTankPaymasterConfig memory newConfig = gasTankUSDC.getPaymasterConfig();
        newConfig.markup = PRICE_DENOMINATOR * 12 / 10;
        newConfig.minEPBalance = 2 ether;
        newConfig.postOpCost = 35000;
        newConfig.priceMaxAge = 1 hours;
        vm.prank(deployer);
        gasTankUSDT.configurePaymaster(newConfig);
        vm.deal(address(weth), 100 ether);
        _depositToGasTank(gasTankUSDT, address(usdt), verifyingSigner, 20 * 10 ** 18);
        usdt.mint(address(mew), 100 * 10 ** 18);
        _depositToGasTank(gasTankUSDT, address(usdt), address(mew), 10 * 10 ** 18);
        vm.startPrank(deployer);
        usdtOracle.configurePrice(1e8); // $1 USDT
        nativeOracle.configurePrice(2000e8); // $2000 ETH
        uint256 updatedPrice = gasTankUSDT.updateCachedPrice(true);
        assertGt(updatedPrice, 0, "Price update should succeed");
        uint256 currentBalance = gasTankUSDT.getDeposit();
        gasTankUSDT.withdrawTo(beneficiary, currentBalance - 1.5 ether);
        vm.warp(block.timestamp + 30 minutes);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDT,
            address(mew),
            owner1Key,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSignerKey,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(owner1Key, ECDSA.toEthSignedMessageHash(userOpHash));
        userOp.signature = abi.encodePacked(r, s, v);
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
        entrypoint.handleOps(userOps, beneficiary);
        uint256 finalEPBalance = gasTankUSDT.getDeposit();
        assertGt(finalEPBalance, 1.4 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                     EMERGENCY RECOVERY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_emergencyUnsupportedTokenRecovery_success() public {
        TestERC20 unsupportedToken = new TestERC20();
        uint256 tokenAmount = 100 * 10 ** 18;
        unsupportedToken.mint(address(gasTankUSDC), tokenAmount);
        uint256 initialBalance = unsupportedToken.balanceOf(beneficiary);
        vm.prank(deployer);
        gasTankUSDC.emergencyUnsupportedTokenRecovery(IERC20(address(unsupportedToken)), beneficiary);
        assertEq(unsupportedToken.balanceOf(beneficiary), initialBalance + tokenAmount);
        assertEq(unsupportedToken.balanceOf(address(gasTankUSDC)), 0);
    }

    function test_emergencyUnsupportedTokenRecovery_revertWhen_mainToken() public {
        vm.prank(deployer);
        vm.expectRevert(GasTankPaymaster.GasTankPaymaster_CannotRecoverMainToken.selector);
        gasTankUSDC.emergencyUnsupportedTokenRecovery(IERC20(address(usdc)), beneficiary);
    }

    function test_emergencyUnsupportedTokenRecovery_revertWhen_WETH() public {
        vm.prank(deployer);
        vm.expectRevert(GasTankPaymaster.GasTankPaymaster_CannotRecoverWETH.selector);
        gasTankUSDC.emergencyUnsupportedTokenRecovery(IERC20(address(weth)), beneficiary);
    }

    function test_emergencyUnsupportedTokenRecovery_revertWhen_notOwner() public {
        TestERC20 unsupportedToken = new TestERC20();
        unsupportedToken.mint(address(gasTankUSDC), 100 * 10 ** 18);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        gasTankUSDC.emergencyUnsupportedTokenRecovery(IERC20(address(unsupportedToken)), beneficiary);
    }

    function test_emergencyUnsupportedTokenRecovery_revertWhen_noTokensToRecover() public {
        TestERC20 unsupportedToken = new TestERC20();
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                GasTankPaymaster.GasTankPaymaster_NoTokensToRecover.selector, address(unsupportedToken)
            )
        );
        gasTankUSDC.emergencyUnsupportedTokenRecovery(IERC20(address(unsupportedToken)), beneficiary);
    }

    function test_withdrawAllNative_native() public {
        uint256 nAmount = 1 ether;
        vm.deal(user1, nAmount);
        vm.prank(user1);
        (bool success,) = address(gasTankUSDC).call{value: nAmount}("");
        assertTrue(success);
        assertEq(address(gasTankUSDC).balance, nAmount);
        uint256 vsNativeBalancePre = address(verifyingSigner).balance;
        vm.prank(deployer);
        vm.expectEmit(true, true, true, false);
        emit GasTankPaymaster_NativeWithdrawn(address(verifyingSigner), nAmount);
        gasTankUSDC.withdrawAllNative(verifyingSigner);
        uint256 vsNativeBalancePost = address(verifyingSigner).balance;
        assertEq(address(gasTankUSDC).balance, 0);
        assertEq(vsNativeBalancePost, vsNativeBalancePre + nAmount);
    }

    function test_withdrawAllNative_wrappedNative() public {
        uint256 wnAmount = 2 ether;
        vm.startPrank(user1);
        weth.deposit{value: wnAmount}();
        weth.transfer(address(gasTankUSDC), wnAmount);
        vm.stopPrank();
        assertEq(weth.balanceOf(address(gasTankUSDC)), wnAmount);
        uint256 vsWrappedNativeBalancePre = weth.balanceOf(address(verifyingSigner));
        vm.prank(deployer);
        vm.expectEmit(true, true, true, false);
        emit GasTankPaymaster_WrappedNativeWithdrawn(address(verifyingSigner), wnAmount);
        gasTankUSDC.withdrawAllNative(verifyingSigner);
        uint256 vsWrappedNativeBalancePost = weth.balanceOf(address(verifyingSigner));
        assertEq(weth.balanceOf(address(gasTankUSDC)), 0);
        assertEq(vsWrappedNativeBalancePost, vsWrappedNativeBalancePre + wnAmount);
    }

    function test_withdrawAllNative_both() public {
        uint256 nAmount = 1 ether;
        uint256 wnAmount = 2 ether;
        vm.deal(user1, nAmount + wnAmount);
        vm.startPrank(user1);
        (bool success,) = address(gasTankUSDC).call{value: nAmount}("");
        assertTrue(success);
        weth.deposit{value: wnAmount}();
        weth.transfer(address(gasTankUSDC), wnAmount);
        vm.stopPrank();
        assertEq(address(gasTankUSDC).balance, nAmount);
        assertEq(weth.balanceOf(address(gasTankUSDC)), wnAmount);
        uint256 vsNativeBalancePre = address(verifyingSigner).balance;
        uint256 vsWrappedNativeBalancePre = weth.balanceOf(address(verifyingSigner));
        vm.prank(deployer);
        vm.expectEmit(true, true, true, false);
        emit GasTankPaymaster_NativeWithdrawn(address(verifyingSigner), nAmount);
        vm.expectEmit(true, true, true, false);
        emit GasTankPaymaster_WrappedNativeWithdrawn(address(verifyingSigner), wnAmount);
        gasTankUSDC.withdrawAllNative(verifyingSigner);
        uint256 vsNativeBalancePost = address(verifyingSigner).balance;
        uint256 vsWrappedNativeBalancePost = weth.balanceOf(address(verifyingSigner));
        assertEq(address(gasTankUSDC).balance, 0);
        assertEq(weth.balanceOf(address(gasTankUSDC)), 0);
        assertEq(vsNativeBalancePost, vsNativeBalancePre + nAmount);
        assertEq(vsWrappedNativeBalancePost, vsWrappedNativeBalancePre + wnAmount);
    }

    function test_withdrawAllNative_revertWhen_notOwner() public {
        uint256 nAmount = 1 ether;
        vm.deal(user1, nAmount);
        vm.prank(user1);
        (bool success,) = address(gasTankUSDC).call{value: nAmount}("");
        assertTrue(success);
        assertEq(address(gasTankUSDC).balance, nAmount);
        uint256 vsNativeBalancePre = address(verifyingSigner).balance;
        vm.prank(verifyingSigner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, verifyingSigner));
        gasTankUSDC.withdrawAllNative(verifyingSigner);
    }

    /*//////////////////////////////////////////////////////////////
                         INTEGRATION & EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_fullFlow_depositAndWithdraw() public {
        _depositToGasTank(gasTankUSDC, address(usdc), user1, USDC_DEPOSIT_AMOUNT);
        bytes memory callData = abi.encodeWithSignature("execute()");
        PackedUserOperation memory userOp =
            _createUserOperationWithPaymaster(user1, callData, 1 gwei, 1 gwei, user1Key, address(gasTankUSDC));
        uint256 remainingBalance = gasTankUSDC.gasTankBalance(user1);
        _withdrawFromGasTank(gasTankUSDC, address(usdc), user1, remainingBalance);
        assertEq(gasTankUSDC.gasTankBalance(user1), 0);
        assertEq(usdc.balanceOf(user1), USDC_INITIAL_MINT);
    }

    function test_automaticTopUp_USDT_fails_butUserOpSucceeds() public {
        GasTankPaymaster.GasTankPaymasterConfig memory newConfig = gasTankUSDC.getPaymasterConfig();
        newConfig.minEPBalance = 2 ether;
        newConfig.priceMaxAge = 25 hours;
        vm.prank(deployer);
        gasTankUSDT.configurePaymaster(newConfig);
        vm.startPrank(address(uniswapV3));
        // Drain all USDT/WETH from the mock exchange to cause swap failure
        uint256 usdtBalance = usdt.balanceOf(address(uniswapV3));
        uint256 wethBalance = weth.balanceOf(address(uniswapV3));
        if (usdtBalance > 0) {
            usdt.transfer(address(1), usdtBalance); // Send to burn address
        }
        if (wethBalance > 0) {
            weth.transfer(address(1), wethBalance); // Send to burn address
        }
        vm.stopPrank();
        _depositToGasTank(gasTankUSDT, address(usdt), verifyingSigner, 1e18);
        usdt.mint(address(mew), 100 * 10 ** 18);
        _depositToGasTank(gasTankUSDT, address(usdt), address(mew), 10 * 10 ** 18);
        vm.startPrank(deployer);
        usdtOracle.configurePrice(1e8);
        nativeOracle.configurePrice(2000e8);
        gasTankUSDT.updateCachedPrice(true);
        uint256 currentBalance = gasTankUSDT.getDeposit();
        gasTankUSDT.withdrawTo(beneficiary, currentBalance - 0.2 ether);
        vm.stopPrank();
        vm.warp(block.timestamp + 30 minutes);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDT,
            address(mew),
            owner1Key,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSignerKey,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(owner1Key, ECDSA.toEthSignedMessageHash(userOpHash));
        userOp.signature = abi.encodePacked(r, s, v);
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
        entrypoint.handleOps(userOps, beneficiary);
        uint256 finalEPBalance = gasTankUSDT.getDeposit();
        uint256 finalVSBalance = gasTankUSDT.gasTankBalance(verifyingSigner);
        assertLt(finalEPBalance, currentBalance);
        assertEq(finalVSBalance, 1 * 10 ** 18);
        assertLt(finalEPBalance, 2 ether);
    }

    function test_automaticTopUp_USDT_insufficientBalance_butUserOpSucceeds() public {
        // Configure paymaster with lower minimum balance to trigger top-up
        GasTankPaymaster.GasTankPaymasterConfig memory newConfig = gasTankUSDC.getPaymasterConfig();
        newConfig.minEPBalance = 2 ether;
        newConfig.priceMaxAge = 25 hours;
        newConfig.minVSTokenBalance = 2 * 10 ** 18; // Set to 2 USDT to trigger insufficient
        vm.prank(deployer);
        gasTankUSDT.configurePaymaster(newConfig);
        // Give verifying signer EXACTLY the minimum token balance (1e18 for 18-decimal token)
        // This will trigger: vsBalance <= minTokenBalance
        uint256 minTokenBalance = 10 ** 18; // 1e18 for USDT (18 decimals)
        _depositToGasTank(gasTankUSDT, address(usdt), verifyingSigner, minTokenBalance);
        usdt.mint(address(mew), 100 * 10 ** 18);
        _depositToGasTank(gasTankUSDT, address(usdt), address(mew), 10 * 10 ** 18);
        vm.startPrank(deployer);
        usdtOracle.configurePrice(1e8); // $1 USDT
        nativeOracle.configurePrice(2000e8); // $2000 ETH
        gasTankUSDT.updateCachedPrice(true);
        // Reduce EntryPoint balance to trigger top-up attempt
        uint256 currentBalance = gasTankUSDT.getDeposit();
        gasTankUSDT.withdrawTo(beneficiary, currentBalance - 0.2 ether);
        currentBalance = gasTankUSDT.getDeposit();
        vm.stopPrank();
        vm.warp(block.timestamp + 30 minutes);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDT,
            address(mew),
            owner1Key,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSignerKey,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(owner1Key, ECDSA.toEthSignedMessageHash(userOpHash));
        userOp.signature = abi.encodePacked(r, s, v);
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_InsufficientBalanceButTopUpRequired(minTokenBalance, 2 * 10 ** 18);
        entrypoint.handleOps(userOps, beneficiary);
        uint256 finalEPBalance = gasTankUSDT.getDeposit();
        uint256 finalVSBalance = gasTankUSDT.gasTankBalance(verifyingSigner);
        assertLt(finalEPBalance, currentBalance, "EntryPoint balance should decrease due to gas consumption");
        assertEq(finalVSBalance, minTokenBalance, "VerifyingSigner balance should be unchanged - no top-up attempted");
        assertLt(finalEPBalance, 2 ether, "Should still be below minimum threshold since top-up was skipped");
        assertTrue(true, "User operation should succeed despite insufficient balance for top-up");
    }

    function test_automaticTopUp_USDT_stalePrice_butUserOpSucceeds() public {
        // Configure paymaster with shorter price max age to make prices go stale easily
        GasTankPaymaster.GasTankPaymasterConfig memory newConfig = gasTankUSDC.getPaymasterConfig();
        newConfig.minEPBalance = 2 ether;
        newConfig.priceMaxAge = 1 hours; // Short max age for easy staleness
        vm.prank(deployer);
        gasTankUSDT.configurePaymaster(newConfig);
        _depositToGasTank(gasTankUSDT, address(usdt), verifyingSigner, 10 * 10 ** 18);
        usdt.mint(address(mew), 100 * 10 ** 18);
        _depositToGasTank(gasTankUSDT, address(usdt), address(mew), 10 * 10 ** 18);
        vm.startPrank(deployer);
        usdtOracle.configurePrice(1e8); // $1 USDT
        nativeOracle.configurePrice(2000e8); // $2000 ETH
        gasTankUSDT.updateCachedPrice(true);
        // Reduce EntryPoint balance to trigger top-up attempt
        uint256 currentBalance = gasTankUSDT.getDeposit();
        gasTankUSDT.withdrawTo(beneficiary, currentBalance - 0.2 ether);
        currentBalance = gasTankUSDT.getDeposit();
        vm.stopPrank();
        vm.warp(block.timestamp + 2 hours); // Beyond the 1 hour priceMaxAge
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDT,
            address(mew),
            owner1Key,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSignerKey,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(owner1Key, ECDSA.toEthSignedMessageHash(userOpHash));
        userOp.signature = abi.encodePacked(r, s, v);
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_TopUpSkippedDueToStalePrice();
        entrypoint.handleOps(userOps, beneficiary);
        uint256 finalEPBalance = gasTankUSDT.getDeposit();
        uint256 finalVSBalance = gasTankUSDT.gasTankBalance(verifyingSigner);
        assertLt(finalEPBalance, currentBalance, "EntryPoint balance should decrease due to gas consumption");
        assertEq(
            finalVSBalance, 10 * 10 ** 18, "VerifyingSigner balance should be unchanged - no top-up due to stale price"
        );
        assertLt(finalEPBalance, 2 ether, "Should still be below minimum threshold since top-up was skipped");
        assertTrue(true, "User operation should succeed despite stale price condition");
    }

    /*//////////////////////////////////////////////////////////////
                        GENERIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_supportedToken() public {
        assertEq(gasTankUSDC.supportedToken(), address(usdc));
        assertEq(gasTankUSDT.supportedToken(), address(usdt));
    }

    function test_supportedWrappedNative() public {
        assertEq(gasTankUSDC.supportedWrappedNative(), address(weth));
        assertEq(gasTankUSDT.supportedWrappedNative(), address(weth));
    }

    function test_name() public {
        assertEq(gasTankUSDC.name(), "GasTankPaymaster");
    }

    function test_version() public {
        assertEq(gasTankUSDC.version(), "1.0.0");
    }

    /*//////////////////////////////////////////////////////////////
                           RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    function test_receive() public {
        uint256 amount = 1 ether;
        vm.deal(user1, amount);
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_Received(user1, amount);
        (bool success,) = address(gasTankUSDC).call{value: amount}("");
        assertTrue(success);
    }
}
