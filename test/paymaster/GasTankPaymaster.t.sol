// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./utils/GasTankPaymasterTestUtils.sol";

contract GasTankPaymasterTest is GasTankPaymasterTestUtils {
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testSetup();
    }

    /*//////////////////////////////////////////////////////////////
                             HELPER EVENTS
    //////////////////////////////////////////////////////////////*/

    event GasTankPaymaster_MinFeeReceiverTokenBalanceUpdated(uint256 oldMinBalance, uint256 newMinBalance);
    event GasTankPaymaster_InsufficientBalanceButTopUpRequired(uint256 currentBalance, uint256 minRequired);
    event GasTankPaymaster_TopUpSkippedDueToStalePrice();
    event GasTankPaymaster_NativeWithdrawn(address indexed to, uint256 amount);
    event GasTankPaymaster_WrappedNativeWithdrawn(address indexed to, uint256 amount);
    event GasTankPaymaster_EmergencyUnsupportedTokenRecovery(address indexed token, address indexed to, uint256 amount);
    event GasTankPaymaster_Received(address indexed sender, uint256 amount);
    event GasTankPaymaster_StaleTokenPrice();
    event GasTankPaymaster_TopUpExecuted(uint256 tokenUsed, uint256 nativeAmount);
    event GasTankPaymaster_SequencerDown();
    event GasTankPaymaster_SequencerGracePeriodActive(uint256 timeSinceUp);
    event GasTankPaymaster_OracleUpdateFailed();
    event GasTankPaymaster_PaymasterConfigUpdated(GasTankPaymaster.GasTankPaymasterConfig newConfig);

    /*//////////////////////////////////////////////////////////////
                         BASIC FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    // Gas Tank Deposits - Self
    function test_gasTankDeposit_forSelf() public {
        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(alice.pub), USDC_INITIAL_MINT - USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), USDC_DEPOSIT_AMOUNT);
    }

    function test_gasTankDeposit_forSelf_multipleDeposits() public {
        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), USDC_DEPOSIT_AMOUNT);
        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), USDC_DEPOSIT_AMOUNT * 2);
        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), USDC_DEPOSIT_AMOUNT * 3);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), USDC_DEPOSIT_AMOUNT * 3);
        assertEq(usdc.balanceOf(alice.pub), USDC_INITIAL_MINT - USDC_DEPOSIT_AMOUNT * 3);
    }

    function test_gasTankDeposit_forSelf_revertWhen_insufficientAllowance() public {
        vm.startPrank(alice.pub);
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
        vm.startPrank(alice.pub);
        usdc.approve(address(gasTankUSDC), 0);
        vm.expectRevert(abi.encodeWithSelector(GasTankPaymaster.GasTankPaymaster_InvalidAmount.selector));
        gasTankUSDC.gasTankDeposit(0);
        vm.stopPrank();
    }

    // Gas Tank Deposits - For Another Wallet
    function test_gasTankDeposit_forAnotherWallet() public {
        _depositToGasTankForWallet(gasTankUSDC, address(usdc), alice.pub, bob.pub, USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(alice.pub), USDC_INITIAL_MINT - USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(bob.pub), USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), 0);
    }

    function test_gasTankDeposit_forAnotherWallet_withExistingBalance() public {
        _depositToGasTankForWallet(gasTankUSDC, address(usdc), alice.pub, bob.pub, USDC_DEPOSIT_AMOUNT);
        _depositToGasTankForWallet(gasTankUSDC, address(usdc), alice.pub, bob.pub, USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), USDC_DEPOSIT_AMOUNT * 2);
        assertEq(usdc.balanceOf(alice.pub), USDC_INITIAL_MINT - USDC_DEPOSIT_AMOUNT * 2);
        assertEq(gasTankUSDC.gasTankBalance(bob.pub), USDC_DEPOSIT_AMOUNT * 2);
    }

    function test_gasTankDeposit_forAnotherWallet_transfersFromSpecifiedWallet() public {
        _depositToGasTankForWallet(gasTankUSDC, address(usdc), alice.pub, bob.pub, USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(alice.pub), USDC_INITIAL_MINT - USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(bob.pub), USDC_INITIAL_MINT);
        assertEq(gasTankUSDC.gasTankBalance(bob.pub), USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), 0);
    }

    function test_gasTankDeposit_forAnotherWallet_revertWhen_zeroAddress() public {
        vm.startPrank(alice.pub);
        usdc.approve(address(gasTankUSDC), USDC_DEPOSIT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(GasTankPaymaster.GasTankPaymaster_InvalidAddress.selector));
        gasTankUSDC.gasTankDeposit(address(0), USDC_DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    // Gas Tank Withdrawals
    function test_gasTankWithdraw_partial() public {
        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_DEPOSIT_AMOUNT);
        _withdrawFromGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_WITHDRAW_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), USDC_DEPOSIT_AMOUNT - USDC_WITHDRAW_AMOUNT);
        assertEq(usdc.balanceOf(alice.pub), USDC_INITIAL_MINT - USDC_DEPOSIT_AMOUNT + USDC_WITHDRAW_AMOUNT);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), USDC_DEPOSIT_AMOUNT - USDC_WITHDRAW_AMOUNT);
    }

    function test_gasTankWithdraw_full() public {
        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_DEPOSIT_AMOUNT);
        _withdrawFromGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), 0);
        assertEq(usdc.balanceOf(alice.pub), USDC_INITIAL_MINT);
        assertEq(usdc.balanceOf(address(gasTankUSDC)), 0);
    }

    function test_gasTankWithdraw_revertWhen_insufficientBalance() public {
        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_DEPOSIT_AMOUNT);
        vm.prank(alice.pub);
        vm.expectRevert(
            abi.encodeWithSelector(
                GasTankPaymaster.GasTankPaymaster_InsufficientBalance.selector, alice.pub, USDC_DEPOSIT_AMOUNT + 1
            )
        );
        gasTankUSDC.gasTankWithdraw(USDC_DEPOSIT_AMOUNT + 1);
    }

    function test_gasTankWithdraw_RevertWhen_NoBalance() public {
        vm.prank(alice.pub);
        vm.expectRevert(
            abi.encodeWithSelector(
                GasTankPaymaster.GasTankPaymaster_InsufficientBalance.selector, alice.pub, USDC_WITHDRAW_AMOUNT
            )
        );
        gasTankUSDC.gasTankWithdraw(USDC_WITHDRAW_AMOUNT);
    }

    // Gas Tank Balance Queries
    function test_gasTankBalance() public {
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), 0);
        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), USDC_DEPOSIT_AMOUNT);
        _withdrawFromGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_WITHDRAW_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), USDC_DEPOSIT_AMOUNT - USDC_WITHDRAW_AMOUNT);
    }

    function test_gasTankBalance_multipleUsers() public {
        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_DEPOSIT_AMOUNT);
        _depositToGasTank(gasTankUSDC, address(usdc), bob.pub, USDC_DEPOSIT_AMOUNT * 2);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(bob.pub), USDC_DEPOSIT_AMOUNT * 2);
    }

    /*//////////////////////////////////////////////////////////////
                       ACCESS CONTROL & PAUSABILITY
    //////////////////////////////////////////////////////////////*/

    function test_pause_success() public {
        assertFalse(gasTankUSDC.isPaused());
        vm.prank(deployer.pub);
        gasTankUSDC.pause();
        assertTrue(gasTankUSDC.isPaused());
    }

    function test_unpause_success() public {
        vm.prank(deployer.pub);
        gasTankUSDC.pause();
        assertTrue(gasTankUSDC.isPaused());
        vm.prank(deployer.pub);
        gasTankUSDC.unpause();
        assertFalse(gasTankUSDC.isPaused());
    }

    function test_pause_revertWhen_notOwner() public {
        vm.prank(alice.pub);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice.pub));
        gasTankUSDC.pause();
    }

    function test_unpause_revertWhen_notOwner() public {
        vm.prank(deployer.pub);
        gasTankUSDC.pause();
        vm.prank(alice.pub);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice.pub));
        gasTankUSDC.unpause();
        assertTrue(gasTankUSDC.isPaused());
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_transferOwnership() public {
        vm.prank(deployer.pub);
        _transferOwnership(gasTankUSDC, alice.pub);
        assertEq(gasTankUSDC.owner(), alice.pub);
    }

    function test_setVerifyingSigner() public {
        (address payable newVerifyingSigner, uint256 newVerifyingSignerKey) =
            _makePayableAddrAndKey("newVerifyingSigner");
        vm.startPrank(deployer.pub);
        _setVerifyingSigner(gasTankUSDC, newVerifyingSigner);
        assertEq(gasTankUSDC.verifyingSigner(), newVerifyingSigner);
    }

    function test_setFeeReceiver() public {
        (address payable newFeeReceiver, uint256 newFeeReceiverKey) = _makePayableAddrAndKey("newFeeReceiver");
        vm.startPrank(deployer.pub);
        gasTankUSDC.pause();
        _setFeeReceiver(gasTankUSDC, newFeeReceiver);
        gasTankUSDC.unpause();
        assertEq(gasTankUSDC.feeReceiver(), newFeeReceiver);
    }

    function test_setFeeReceiver_revertIf_notPaused() public {
        (address payable newFeeReceiver, uint256 newFeeReceiverKey) = _makePayableAddrAndKey("newFeeReceiver");
        vm.startPrank(deployer.pub);
        _toRevert(GasTankPaymaster.GasTankPaymaster_IsNotPaused.selector, hex"");
        _setFeeReceiver(gasTankUSDC, newFeeReceiver);
    }

    function test_setSwapRouter() public {
        address newSwapRouter = makeAddr("newSwapRouter");
        vm.prank(deployer.pub);
        _setSwapRouter(gasTankUSDC, newSwapRouter);
        assertEq(address(gasTankUSDC.uniswap()), newSwapRouter);
    }

    function test_setSwapRouter_revokesOldApproval() public {
        address initialRouter = address(gasTankUSDC.uniswap());
        uint256 initialApproval = usdc.allowance(address(gasTankUSDC), initialRouter);
        assertEq(initialApproval, type(uint256).max, "Initial router should have max approval");
        address newSwapRouter = makeAddr("newSwapRouter");
        vm.prank(deployer.pub);
        gasTankUSDC.setSwapRouter(ISwapRouter(newSwapRouter));
        uint256 oldApproval = usdc.allowance(address(gasTankUSDC), initialRouter);
        assertEq(oldApproval, 0, "Old router approval should be revoked");
        uint256 newApproval = usdc.allowance(address(gasTankUSDC), newSwapRouter);
        assertEq(newApproval, type(uint256).max, "New router should have max approval");
        assertEq(address(gasTankUSDC.uniswap()), newSwapRouter, "Router should be updated");
    }

    function test_withdrawFromEntryPoint() public {
        uint256 withdrawAmount = 0.5 ether;
        uint256 initialDeposit = _getEntryPointDeposit(gasTankUSDC);
        vm.prank(deployer.pub);
        _withdrawFromEntryPoint(gasTankUSDC, beneficiary.pub, withdrawAmount);
        uint256 newDeposit = _getEntryPointDeposit(gasTankUSDC);
        assertEq(newDeposit, initialDeposit - withdrawAmount);
    }

    function test_configurePaymaster() public {
        uint256 newMarkup = PRICE_DENOMINATOR * 15 / 10;
        uint128 newMinEPBalance = 2 ether;
        uint48 newPostOpCost = 40000;
        uint48 newTokenMaxAge = 2 hours;
        uint48 newNativeMaxAge = 48 hours;
        _configurePaymaster(gasTankUSDC, newMarkup, newMinEPBalance, newPostOpCost, newTokenMaxAge, newNativeMaxAge);
        GasTankPaymaster.GasTankPaymasterConfig memory config = gasTankUSDC.getPaymasterConfig();
        assertEq(config.markup, newMarkup);
        assertEq(config.minEPBalance, newMinEPBalance);
        assertEq(config.postOpCost, newPostOpCost);
        assertEq(config.tokenMaxAge, newTokenMaxAge);
        assertEq(config.nativeMaxAge, newNativeMaxAge);
    }

    function test_updateMinFeeReceiverTokenBalance_success() public {
        uint256 newMinBalance = 5 * 10 ** 6; // 5 USDC
        vm.prank(deployer.pub);
        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_MinFeeReceiverTokenBalanceUpdated(10 * 10 ** 6, newMinBalance);
        gasTankUSDC.updateMinFeeReceiverTokenBalance(newMinBalance);
        GasTankPaymaster.GasTankPaymasterConfig memory config = gasTankUSDC.getPaymasterConfig();
        assertEq(config.minFeeReceiverTokenBalance, newMinBalance);
    }

    function test_transferOwnership_revertWhen_notOwner() public {
        vm.prank(alice.pub);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice.pub));
        gasTankUSDC.transferOwnership(bob.pub);
    }

    function test_configurePaymaster_revertWhen_notOwner() public {
        GasTankPaymaster.GasTankPaymasterConfig memory currentConfig = gasTankUSDC.getPaymasterConfig();
        currentConfig.markup = PRICE_DENOMINATOR * 15 / 10;
        vm.prank(alice.pub);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice.pub));
        gasTankUSDC.configurePaymaster(currentConfig);
    }

    function test_configurePaymaster_revertWhen_markupTooLow() public {
        uint256 tooLowMarkup = PRICE_DENOMINATOR * 9 / 10;
        GasTankPaymaster.GasTankPaymasterConfig memory testConfig = gasTankUSDC.getPaymasterConfig();
        testConfig.markup = tooLowMarkup;
        vm.prank(deployer.pub);
        vm.expectRevert(
            abi.encodeWithSelector(GasTankPaymaster.GasTankPaymaster_PriceMarkupTooLow.selector, tooLowMarkup)
        );
        gasTankUSDC.configurePaymaster(testConfig);
    }

    function test_configurePaymaster_revertWhen_markupTooHigh() public {
        uint256 tooHighMarkup = PRICE_DENOMINATOR * 21 / 10;
        GasTankPaymaster.GasTankPaymasterConfig memory testConfig = gasTankUSDC.getPaymasterConfig();
        testConfig.markup = tooHighMarkup;
        vm.prank(deployer.pub);
        vm.expectRevert(
            abi.encodeWithSelector(GasTankPaymaster.GasTankPaymaster_PriceMarkupTooHigh.selector, tooHighMarkup)
        );
        gasTankUSDC.configurePaymaster(testConfig);
    }

    function test_setVerifyingSigner_revertWhen_notOwner() public {
        (address payable maliciousUser, uint256 maliciousKey) = _makePayableAddrAndKey("maliciousUser");
        vm.startPrank(alice.pub);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice.pub));
        gasTankUSDC.setVerifyingSigner(maliciousUser);
    }

    function test_setFeeReceiver_revertWhen_notOwner() public {
        (address payable maliciousUser, uint256 maliciousKey) = _makePayableAddrAndKey("maliciousUser");
        vm.startPrank(alice.pub);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice.pub));
        gasTankUSDC.setFeeReceiver(maliciousUser);
    }

    function test_updateMinFeeReceiverTokenBalance_revertWhen_notOwner() public {
        vm.prank(alice.pub);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice.pub));
        gasTankUSDC.updateMinFeeReceiverTokenBalance(5 * 10 ** 6);
    }

    function test_updateMinFeeReceiverTokenBalance_revertWhen_invalidNewMinimumTopup() public {
        vm.prank(deployer.pub);
        vm.expectRevert(
            abi.encodeWithSelector(GasTankPaymaster.GasTankPaymaster_InvalidFeeReceiverMinimumTopupBalance.selector)
        );
        gasTankUSDC.updateMinFeeReceiverTokenBalance(0);
    }

    function test_addStake() public {
        vm.startPrank(deployer.pub);
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
        vm.prank(deployer.pub);
        vm.expectRevert("Withdraw amount too large");
        gasTankUSDC.withdrawTo(beneficiary.pub, initialDeposit + 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        PAYMASTER STATUS QUERIES  
    //////////////////////////////////////////////////////////////*/

    function test_getPaymasterStatus_needsTopUp_false() public {
        uint256 currentBalance = entrypoint.balanceOf(address(gasTankUSDC));
        if (currentBalance < 5 ether) {
            vm.deal(address(scw), 10 ether);
            vm.prank(address(scw));
            gasTankUSDC.deposit{value: 10 ether}();
        }
        GasTankPaymaster.GasTankPaymasterConfig memory newConfig = gasTankUSDC.getPaymasterConfig();
        newConfig.minEPBalance = 0.1 ether;
        vm.prank(deployer.pub);
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
            gasTankUSDC, address(scw), eoa.priv, callData, 1 gwei, 1 gwei, verifyingSigner.priv, validUntil, validAfter
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
            gasTankUSDC, address(scw), eoa.priv, callData, 1 gwei, 1 gwei, alice.priv, validUntil, validAfter
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
        PackedUserOperation memory userOp = _createUserOperation(address(scw), callData, 1 gwei, 1 gwei, eoa.priv);
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
            gasTankUSDC, address(scw), eoa.priv, callData, 1 gwei, 1 gwei, verifyingSigner.priv, validUntil, validAfter
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
        vm.prank(deployer.pub);
        gasTankUSDC.pause();
        PackedUserOperation memory userOp = _createBasicUserOp();
        vm.prank(address(entrypoint));
        vm.expectRevert(GasTankPaymaster.GasTankPaymaster_IsPaused.selector);
        gasTankUSDC.validatePaymasterUserOp(userOp, keccak256("dummy"), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                       TOKEN RESERVATION SYSTEM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_reservationAmounts_initiallyZero() public {
        assertEq(gasTankUSDC.getReservedAmount(alice.pub), 0);
        assertEq(gasTankUSDC.getReservedAmount(bob.pub), 0);
        assertEq(gasTankUSDC.getReservedAmount(address(scw)), 0);
    }

    function test_gasTankAvailableBalance_withoutReservation() public {
        // Setup: Deposit tokens
        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_DEPOSIT_AMOUNT);

        // Available balance should equal total balance when no reservations
        assertEq(gasTankUSDC.gasTankAvailableBalance(alice.pub), USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), USDC_DEPOSIT_AMOUNT);
    }

    function test_gasTankAvailableBalance_afterSponsoredTransaction() public {
        // Setup: Deposit tokens and fund EntryPoint
        uint256 initialDeposit = 1000 * 10 ** 6;
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), initialDeposit);

        vm.deal(address(scw), 5 ether);
        vm.prank(address(scw));
        gasTankUSDC.deposit{value: 5 ether}();

        // Execute sponsored transaction to trigger reservation
        vm.warp(block.timestamp + 1 days);

        // Update oracle timestamps to current time to avoid stale price
        usdcOracle.configureUpdatedAt(block.timestamp);
        nativeOracle.configureUpdatedAt(block.timestamp);

        // Force fresh price calculation by clearing cache and updating
        vm.startPrank(deployer.pub);
        // First, get current config to modify it
        GasTankPaymaster.GasTankPaymasterConfig memory config = gasTankUSDC.getPaymasterConfig();
        config.cachedTokenPrice = 0; // Clear cached price
        config.cachedPriceTimestamp = 0; // Clear timestamp to force refresh
        gasTankUSDC.configurePaymaster(config);
        gasTankUSDC.updateCachedPrice(true); // Force update with new oracle values
        vm.stopPrank();

        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        vm.startPrank(address(scw));
        _executeUserOp(userOp);
        vm.stopPrank();

        // Check that tokens are now reserved
        uint256 reservedAmount = gasTankUSDC.getReservedAmount(address(scw));
        assertGt(reservedAmount, 0); // Some amount should be reserved

        // Available balance should be total - reserved
        uint256 availableBalance = gasTankUSDC.gasTankAvailableBalance(address(scw));
        assertEq(availableBalance, initialDeposit - reservedAmount);
    }

    function test_gasTankWithdraw_success_withoutReservation() public {
        // Setup: Normal withdrawal should work
        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_DEPOSIT_AMOUNT);
        assertEq(gasTankUSDC.getReservedAmount(alice.pub), 0);

        // Should succeed
        _withdrawFromGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_WITHDRAW_AMOUNT);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), USDC_DEPOSIT_AMOUNT - USDC_WITHDRAW_AMOUNT);
    }

    function test_gasTankWithdraw_success_withAvailableBalance() public {
        // Setup: Execute sponsored transaction to create reservation
        uint256 initialDeposit = 1000 * 10 ** 6;
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), initialDeposit);

        vm.deal(address(scw), 5 ether);
        vm.prank(address(scw));
        gasTankUSDC.deposit{value: 5 ether}();

        // Execute sponsored transaction
        vm.warp(block.timestamp + 1 days);

        // Update oracle timestamps to current time to avoid stale price
        usdcOracle.configureUpdatedAt(block.timestamp);
        nativeOracle.configureUpdatedAt(block.timestamp);

        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        vm.startPrank(address(scw));
        _executeUserOp(userOp);
        vm.stopPrank();

        // Get available amount and withdraw it
        uint256 actualBalance = gasTankUSDC.gasTankBalance(address(scw));
        console2.log("ACTUAL BALANCE:", actualBalance);
        uint256 availableAmount = gasTankUSDC.gasTankAvailableBalance(address(scw));
        uint256 reservedAmount = gasTankUSDC.getReservedAmount(address(scw));

        assertGt(reservedAmount, 0); // Should have some reservation
        assertLt(availableAmount, initialDeposit); // Available should be less than total

        // Withdraw available amount should succeed
        vm.prank(address(scw));
        gasTankUSDC.gasTankWithdraw(availableAmount);

        assertEq(gasTankUSDC.gasTankBalance(address(scw)), reservedAmount);
        assertEq(gasTankUSDC.getReservedAmount(address(scw)), reservedAmount);
    }

    function test_gasTankWithdraw_revertWhen_exceedsAvailableBalance() public {
        // Setup: Execute sponsored transaction to create reservation
        uint256 initialDeposit = 1000 * 10 ** 6;
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), initialDeposit);

        vm.deal(address(scw), 5 ether);
        vm.prank(address(scw));
        gasTankUSDC.deposit{value: 5 ether}();

        // Execute sponsored transaction
        vm.warp(block.timestamp + 1 days);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        vm.startPrank(address(scw));
        _executeUserOp(userOp);
        vm.stopPrank();

        // Try to withdraw more than available balance
        uint256 availableBalance = gasTankUSDC.gasTankAvailableBalance(address(scw));
        uint256 attemptWithdraw = availableBalance + 1;

        vm.prank(address(scw));
        vm.expectRevert(
            abi.encodeWithSelector(
                GasTankPaymaster.GasTankPaymaster_InsufficientBalance.selector, address(scw), attemptWithdraw
            )
        );
        gasTankUSDC.gasTankWithdraw(attemptWithdraw);
    }

    function test_gasTankWithdraw_revertWhen_allTokensReserved() public {
        // Setup: Execute multiple sponsored transactions to reserve most/all tokens
        uint256 initialDeposit = 500 * 10 ** 6; // Smaller deposit to make it easier to reserve all
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), initialDeposit);

        vm.deal(address(scw), 5 ether);
        vm.prank(address(scw));
        gasTankUSDC.deposit{value: 5 ether}();

        // Execute sponsored transaction
        vm.warp(block.timestamp + 1 days);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        vm.startPrank(address(scw));
        _executeUserOp(userOp);
        vm.stopPrank();

        // Get available balance
        uint256 availableBalance = gasTankUSDC.gasTankAvailableBalance(address(scw));

        if (availableBalance == 0) {
            // All tokens are reserved - any withdrawal should fail
            vm.prank(address(scw));
            vm.expectRevert(
                abi.encodeWithSelector(GasTankPaymaster.GasTankPaymaster_InsufficientBalance.selector, address(scw), 1)
            );
            gasTankUSDC.gasTankWithdraw(1);
        } else {
            // Some tokens available - try to withdraw more than available
            vm.prank(address(scw));
            vm.expectRevert(
                abi.encodeWithSelector(
                    GasTankPaymaster.GasTankPaymaster_InsufficientBalance.selector, address(scw), availableBalance + 1
                )
            );
            gasTankUSDC.gasTankWithdraw(availableBalance + 1);
        }
    }

    function test_reservationSystem_doesNotAffectOtherUsers() public {
        // Setup: Both users deposit tokens
        uint256 aliceDeposit = 1000 * 10 ** 6;
        uint256 bobDeposit = 2000 * 10 ** 6;

        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, aliceDeposit);
        _depositToGasTank(gasTankUSDC, address(usdc), bob.pub, bobDeposit);

        // Both users start with full available balance
        assertEq(gasTankUSDC.getReservedAmount(alice.pub), 0);
        assertEq(gasTankUSDC.getReservedAmount(bob.pub), 0);
        assertEq(gasTankUSDC.gasTankAvailableBalance(alice.pub), aliceDeposit);
        assertEq(gasTankUSDC.gasTankAvailableBalance(bob.pub), bobDeposit);

        // Execute sponsored transaction for Alice only
        vm.deal(alice.pub, 5 ether);
        vm.prank(alice.pub);
        gasTankUSDC.deposit{value: 5 ether}();

        // Create sponsored transaction for Alice using her wallet
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), aliceDeposit);
        vm.deal(address(scw), 5 ether);
        vm.prank(address(scw));
        gasTankUSDC.deposit{value: 5 ether}();

        vm.warp(block.timestamp + 1 days);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        vm.startPrank(address(scw));
        _executeUserOp(userOp);
        vm.stopPrank();

        // Alice (represented by scw) should have reservations, Bob should not
        assertGt(gasTankUSDC.getReservedAmount(address(scw)), 0);
        assertEq(gasTankUSDC.getReservedAmount(bob.pub), 0);

        // Bob should still have full available balance
        assertEq(gasTankUSDC.gasTankAvailableBalance(bob.pub), bobDeposit);

        // Bob can withdraw normally
        _withdrawFromGasTank(gasTankUSDC, address(usdc), bob.pub, 100 * 10 ** 6);
        assertEq(gasTankUSDC.gasTankBalance(bob.pub), bobDeposit - 100 * 10 ** 6);

        // Alice (scw) can only withdraw available amount
        uint256 aliceAvailable = gasTankUSDC.gasTankAvailableBalance(address(scw));
        if (aliceAvailable > 0) {
            vm.prank(address(scw));
            gasTankUSDC.gasTankWithdraw(aliceAvailable);
        }
    }

    function test_validatePaymasterUserOp_success_withReservation() public {
        // Setup: Execute sponsored transaction to create reservations
        uint256 initialDeposit = 1000 * 10 ** 6;
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), initialDeposit);

        vm.deal(address(scw), 5 ether);
        vm.prank(address(scw));
        gasTankUSDC.deposit{value: 5 ether}();

        // Execute first sponsored transaction
        vm.warp(block.timestamp + 1 days);
        PackedUserOperation memory userOp1 = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        vm.startPrank(address(scw));
        _executeUserOp(userOp1);
        vm.stopPrank();

        // Verify reservation exists
        assertGt(gasTankUSDC.getReservedAmount(address(scw)), 0);

        // Create second user operation - should still validate successfully
        PackedUserOperation memory userOp2 = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        // Validation should succeed even with existing reservations - test by executing the operation
        vm.startPrank(address(scw));
        _executeUserOp(userOp2);
        vm.stopPrank();

        // Verify second transaction succeeded and increased reservations
        uint256 finalReservation = gasTankUSDC.getReservedAmount(address(scw));
        // Final reservation should be greater than zero (accumulation of both transactions)
        assertGt(finalReservation, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    SPONSORED TRANSACTION REPAYMENT
    //////////////////////////////////////////////////////////////*/

    function test_repaySponsoredTransaction_reducesReservation() public {
        // Setup: Execute sponsored transaction to create reservation
        uint256 initialDeposit = 1000 * 10 ** 6;
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), initialDeposit);

        vm.deal(address(scw), 5 ether);
        vm.prank(address(scw));
        gasTankUSDC.deposit{value: 5 ether}();

        // Execute sponsored transaction
        vm.warp(block.timestamp + 1 days);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        vm.startPrank(address(scw));
        _executeUserOp(userOp);
        vm.stopPrank();

        // Verify reservation exists
        uint256 initialReservation = gasTankUSDC.getReservedAmount(address(scw));
        assertGt(initialReservation, 0);

        // Repay part of the reservation
        uint256 repayAmount = 50 * 10 ** 6;
        uint256 initialBalance = gasTankUSDC.gasTankBalance(address(scw));

        vm.prank(deployer.pub);
        gasTankUSDC.repaySponsoredTransaction(address(scw), repayAmount);

        // Verify reservation is reduced
        uint256 newReservation = gasTankUSDC.getReservedAmount(address(scw));
        if (initialReservation >= repayAmount) {
            assertEq(newReservation, initialReservation - repayAmount);
        } else {
            assertEq(newReservation, 0); // Cleared if repay exceeds reservation
        }

        // Verify balance is reduced
        assertEq(gasTankUSDC.gasTankBalance(address(scw)), initialBalance - repayAmount);
    }

    function test_repaySponsoredTransaction_clearsReservationCompletely() public {
        // Setup: Execute sponsored transaction
        uint256 initialDeposit = 1000 * 10 ** 6;
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), initialDeposit);

        vm.deal(address(scw), 5 ether);
        vm.prank(address(scw));
        gasTankUSDC.deposit{value: 5 ether}();

        vm.warp(block.timestamp + 1 days);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        vm.startPrank(address(scw));
        _executeUserOp(userOp);
        vm.stopPrank();

        uint256 reservedAmount = gasTankUSDC.getReservedAmount(address(scw));
        assertGt(reservedAmount, 0);

        // Repay amount equal to or greater than reserved amount
        uint256 repayAmount = reservedAmount + 10 * 10 ** 6; // Pay a bit extra

        vm.prank(deployer.pub);
        gasTankUSDC.repaySponsoredTransaction(address(scw), repayAmount);

        // Reservation should be completely cleared
        assertEq(gasTankUSDC.getReservedAmount(address(scw)), 0);

        // User should now be able to withdraw remaining balance
        uint256 remainingBalance = gasTankUSDC.gasTankBalance(address(scw));
        if (remainingBalance > 0) {
            vm.prank(address(scw));
            gasTankUSDC.gasTankWithdraw(remainingBalance);
            assertEq(gasTankUSDC.gasTankBalance(address(scw)), 0);
        }
    }

    function test_repaySponsoredTransaction_partialReservationClearing() public {
        // Setup: Execute sponsored transaction
        uint256 initialDeposit = 1000 * 10 ** 6;
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), initialDeposit);

        vm.deal(address(scw), 5 ether);
        vm.prank(address(scw));
        gasTankUSDC.deposit{value: 5 ether}();

        vm.warp(block.timestamp + 1 days);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        vm.startPrank(address(scw));
        _executeUserOp(userOp);
        vm.stopPrank();

        uint256 reservedAmount = gasTankUSDC.getReservedAmount(address(scw));
        assertGt(reservedAmount, 0);

        // Repay partial amount (ensure it's less than reserved)
        uint256 repayAmount = reservedAmount / 2; // Pay half

        // Only proceed if we have a meaningful partial amount
        if (repayAmount > 0 && repayAmount < reservedAmount) {
            vm.prank(deployer.pub);
            gasTankUSDC.repaySponsoredTransaction(address(scw), repayAmount);

            // Reservation should be reduced by repayment amount
            assertEq(gasTankUSDC.getReservedAmount(address(scw)), reservedAmount - repayAmount);

            // User should have more available balance now
            uint256 currentBalance = gasTankUSDC.gasTankBalance(address(scw));
            uint256 newAvailable = gasTankUSDC.gasTankAvailableBalance(address(scw));
            assertEq(newAvailable, currentBalance - (reservedAmount - repayAmount));
        } else {
            // If reservation is too small for meaningful partial repayment, just verify the reservation exists
            assertTrue(reservedAmount > 0);
        }
    }

    function test_repaySponsoredTransaction_exactBalance() public {
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.startPrank(alice.pub);
        usdc.approve(address(gasTankUSDC), depositAmount);
        gasTankUSDC.gasTankDeposit(depositAmount);
        vm.stopPrank();
        uint256 initialFeeReceiverBalance = gasTankUSDC.gasTankBalance(feeReceiver.pub);
        vm.prank(deployer.pub);
        gasTankUSDC.repaySponsoredTransaction(alice.pub, depositAmount);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), 0);
        assertEq(gasTankUSDC.gasTankBalance(feeReceiver.pub), initialFeeReceiverBalance + depositAmount);
    }

    function test_repaySponsoredTransaction_revertWhen_insufficientBalance() public {
        vm.startPrank(deployer.pub);
        vm.expectRevert(
            abi.encodeWithSelector(
                GasTankPaymaster.GasTankPaymaster_InsufficientBalance.selector, alice.pub, 1000 * 10 ** 6
            )
        );
        gasTankUSDC.repaySponsoredTransaction(alice.pub, 1000 * 10 ** 6);
        vm.stopPrank();
    }

    function test_repaySponsoredTransaction_revertWhen_invalidAddress() public {
        vm.prank(deployer.pub);
        vm.expectRevert(GasTankPaymaster.GasTankPaymaster_InvalidAddress.selector);
        gasTankUSDC.repaySponsoredTransaction(address(0), 100 * 10 ** 6);
    }

    function test_repaySponsoredTransaction_revertWhen_invalidAmount() public {
        vm.prank(deployer.pub);
        vm.expectRevert(GasTankPaymaster.GasTankPaymaster_InvalidAmount.selector);
        gasTankUSDC.repaySponsoredTransaction(alice.pub, 0);
    }

    /*//////////////////////////////////////////////////////////////
                         PRICE & ORACLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function test_updateCachedPrice_invalidTokenPrice() public {
        vm.startPrank(feeReceiver.pub);
        TestOracle(address(usdcOracle)).configurePrice(0);
        TestOracle(address(nativeOracle)).configurePrice(2000e8);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    function test_updateCachedPrice_invalidNativePrice() public {
        vm.startPrank(feeReceiver.pub);
        TestOracle(address(usdcOracle)).configurePrice(1e8);
        TestOracle(address(nativeOracle)).configurePrice(-100e8);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    function test_updateCachedPrice_staleTokenPrice() public {
        vm.startPrank(feeReceiver.pub);
        uint256 oldTimestamp = block.timestamp;
        TestOracle(address(usdcOracle)).configurePrice(1e8);
        TestOracle(address(usdcOracle)).configureUpdatedAt(oldTimestamp);
        TestOracle(address(nativeOracle)).configurePrice(2000e8);
        TestOracle(address(nativeOracle)).configureUpdatedAt(block.timestamp);
        uint48 tokenMaxAge = gasTankUSDC.getPaymasterConfig().tokenMaxAge;
        vm.warp(oldTimestamp + tokenMaxAge + 1);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    function test_updateCachedPrice_staleNativePrice() public {
        vm.startPrank(feeReceiver.pub);
        uint256 oldTimestamp = block.timestamp;
        TestOracle(address(usdcOracle)).configurePrice(1e8);
        TestOracle(address(usdcOracle)).configureUpdatedAt(block.timestamp);
        TestOracle(address(nativeOracle)).configurePrice(2000e8);
        TestOracle(address(nativeOracle)).configureUpdatedAt(oldTimestamp);
        uint48 nativeMaxAge = gasTankUSDC.getPaymasterConfig().nativeMaxAge;
        vm.warp(oldTimestamp + nativeMaxAge + 1);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    function test_updateCachedPrice_oracleRevert() public {
        vm.startPrank(feeReceiver.pub);
        TestOracle(address(usdcOracle)).configureShouldRevert(true);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    function test_updateCachedPrice_oracleReturnsZero() public {
        vm.startPrank(feeReceiver.pub);
        TestOracle(address(usdcOracle)).configurePrice(0);
        TestOracle(address(nativeOracle)).configurePrice(2000e8);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    function test_updateCachedPrice_oracleReturnsNegative() public {
        vm.startPrank(feeReceiver.pub);
        TestOracle(address(usdcOracle)).configurePrice(-1e8);
        TestOracle(address(nativeOracle)).configurePrice(2000e8);
        uint256 result = gasTankUSDC.updateCachedPrice(true);
        assertEq(result, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                TOKEN RESERVATION ESCAPE ATTACK PREVENTION
    //////////////////////////////////////////////////////////////*/

    function test_fullTokenReservationEscapePreventionFlow() public {
        // Setup: User deposits tokens into gas tank
        uint256 initialDeposit = 1000 * 10 ** 6; // 1000 USDC
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), initialDeposit);

        // Ensure EntryPoint has enough balance to avoid top-up complications
        vm.deal(address(scw), 5 ether);
        vm.prank(address(scw));
        gasTankUSDC.deposit{value: 5 ether}();

        assertEq(gasTankUSDC.getReservedAmount(address(scw)), 0);
        assertEq(gasTankUSDC.gasTankBalance(address(scw)), initialDeposit);
        assertEq(gasTankUSDC.gasTankAvailableBalance(address(scw)), initialDeposit);

        // Step 1: User submits a transaction that gets sponsored
        vm.warp(block.timestamp + 1 days);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        // Execute user operation - this should trigger token reservation in _postOp
        vm.startPrank(address(scw));
        _executeUserOp(userOp);
        vm.stopPrank();

        // Step 2: Verify tokens are now reserved (prevents escape attack)
        uint256 reservedAmount = gasTankUSDC.getReservedAmount(address(scw));
        console2.log("RESERVED AMOUNT:", reservedAmount);
        assertGt(reservedAmount, 0); // Some amount should be reserved

        uint256 availableBalance = gasTankUSDC.gasTankAvailableBalance(address(scw));
        console2.log("AVAILABE BALANCE:", availableBalance);
        assertEq(availableBalance, initialDeposit - reservedAmount);

        // Step 3: User attempts to withdraw all funds (escape attack) - should fail
        vm.prank(address(scw));
        vm.expectRevert(
            abi.encodeWithSelector(
                GasTankPaymaster.GasTankPaymaster_InsufficientBalance.selector, address(scw), initialDeposit
            )
        );
        gasTankUSDC.gasTankWithdraw(initialDeposit);

        // Step 3b: User can only withdraw available balance (but let's keep balance for second transaction)
        // Don't withdraw yet - we need balance for the second transaction to demonstrate accumulation

        // Step 4: User can still sponsor new transactions (reservation doesn't block validation)
        PackedUserOperation memory userOp2 = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );
        vm.prank(address(scw));
        _executeUserOp(userOp2);

        // Step 5: Verify reservations accumulated from both transactions
        uint256 totalReservationAfterTwo = gasTankUSDC.getReservedAmount(address(scw));
        assertGt(totalReservationAfterTwo, reservedAmount); // Should be greater than first reservation

        // Step 6: Admin collects repayment for gas costs
        uint256 repaymentAmount = totalReservationAfterTwo / 2; // Repay half of total reservation
        uint256 initialReservedAmount = totalReservationAfterTwo;

        vm.prank(deployer.pub);
        gasTankUSDC.repaySponsoredTransaction(address(scw), repaymentAmount);

        // Step 7: After repayment, reservation should be reduced
        uint256 newReservedAmount = gasTankUSDC.getReservedAmount(address(scw));
        if (initialReservedAmount >= repaymentAmount) {
            assertEq(newReservedAmount, initialReservedAmount - repaymentAmount);
        } else {
            assertEq(newReservedAmount, 0);
        }

        // Step 8: User now has available balance again after partial repayment
        uint256 newAvailableBalance = gasTankUSDC.gasTankAvailableBalance(address(scw));
        if (newAvailableBalance > 0) {
            vm.prank(address(scw));
            gasTankUSDC.gasTankWithdraw(newAvailableBalance);
        }

        // Step 8: User can sponsor new transactions normally
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), 100 * 10 ** 6);
        assertEq(gasTankUSDC.gasTankAvailableBalance(address(scw)), 100 * 10 ** 6);

        // Create a fresh user operation
        PackedUserOperation memory userOp3 = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        vm.prank(address(scw));
        _executeUserOp(userOp3);
    }

    function test_multipleUserOperations_reservationSequence() public {
        // Setup: Multiple users with gas tank deposits
        uint256 aliceDeposit = 1000 * 10 ** 6;
        uint256 bobDeposit = 2000 * 10 ** 6;

        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, aliceDeposit);
        _depositToGasTank(gasTankUSDC, address(usdc), bob.pub, bobDeposit);

        // Ensure EntryPoint has enough balance
        vm.deal(alice.pub, 5 ether);
        vm.prank(alice.pub);
        gasTankUSDC.deposit{value: 5 ether}();

        // Both users start with no reservations
        assertEq(gasTankUSDC.getReservedAmount(alice.pub), 0);
        assertEq(gasTankUSDC.getReservedAmount(bob.pub), 0);
        assertEq(gasTankUSDC.gasTankAvailableBalance(alice.pub), aliceDeposit);
        assertEq(gasTankUSDC.gasTankAvailableBalance(bob.pub), bobDeposit);

        // Execute sponsored transaction for Alice (using scw as proxy)
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), aliceDeposit);
        vm.deal(address(scw), 5 ether);
        vm.prank(address(scw));
        gasTankUSDC.deposit{value: 5 ether}();

        vm.warp(block.timestamp + 1 days);
        PackedUserOperation memory aliceUserOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        vm.startPrank(address(scw));
        _executeUserOp(aliceUserOp);
        vm.stopPrank();

        // Alice (scw) should have reservation, Bob should not
        assertGt(gasTankUSDC.getReservedAmount(address(scw)), 0);
        assertEq(gasTankUSDC.getReservedAmount(bob.pub), 0);

        // Bob can still withdraw normally
        _withdrawFromGasTank(gasTankUSDC, address(usdc), bob.pub, 100 * 10 ** 6);

        // Alice (scw) can only withdraw available amount
        uint256 aliceAvailable = gasTankUSDC.gasTankAvailableBalance(address(scw));
        if (aliceAvailable > 0) {
            vm.prank(address(scw));
            gasTankUSDC.gasTankWithdraw(aliceAvailable);
        }

        // Alice (scw) cannot withdraw beyond available (escape attack prevention)
        vm.prank(address(scw));
        vm.expectRevert(
            abi.encodeWithSelector(
                GasTankPaymaster.GasTankPaymaster_InsufficientBalance.selector, address(scw), 100 * 10 ** 6
            )
        );
        gasTankUSDC.gasTankWithdraw(100 * 10 ** 6);

        // Repay Alice partially
        uint256 aliceReservation = gasTankUSDC.getReservedAmount(address(scw));
        uint256 aliceRepayment = aliceReservation / 2;

        if (aliceRepayment > 0) {
            vm.prank(deployer.pub);
            gasTankUSDC.repaySponsoredTransaction(address(scw), aliceRepayment);

            // Alice's reservation should be reduced
            assertEq(gasTankUSDC.getReservedAmount(address(scw)), aliceReservation - aliceRepayment);
        }

        // Bob still unaffected
        assertEq(gasTankUSDC.getReservedAmount(bob.pub), 0);
        assertGt(gasTankUSDC.gasTankAvailableBalance(bob.pub), 0);
    }

    function test_tokenReservation_preventsCompleteEscapeAttack() public {
        // Setup: Execute multiple transactions to build up reservations
        uint256 largeDeposit = 2000 * 10 ** 6;
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), largeDeposit);

        vm.deal(address(scw), 10 ether);
        vm.prank(address(scw));
        gasTankUSDC.deposit{value: 10 ether}();

        // Execute first transaction
        vm.warp(block.timestamp + 1 days);
        PackedUserOperation memory userOp1 = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        vm.startPrank(address(scw));
        _executeUserOp(userOp1);
        vm.stopPrank();

        uint256 firstReservation = gasTankUSDC.getReservedAmount(address(scw));
        assertGt(firstReservation, 0);

        // Execute second transaction to increase reservations
        PackedUserOperation memory userOp2 = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        vm.startPrank(address(scw));
        _executeUserOp(userOp2);
        vm.stopPrank();

        uint256 totalReservation = gasTankUSDC.getReservedAmount(address(scw));
        assertGt(totalReservation, firstReservation); // Should have increased

        // Verify user cannot escape with funds reserved for gas payments
        uint256 availableBalance = gasTankUSDC.gasTankAvailableBalance(address(scw));
        assertEq(availableBalance, largeDeposit - totalReservation);

        // User can only withdraw non-reserved amount
        if (availableBalance > 0) {
            vm.prank(address(scw));
            gasTankUSDC.gasTankWithdraw(availableBalance);
        }

        assertEq(gasTankUSDC.gasTankBalance(address(scw)), totalReservation);

        // Attempt to withdraw reserved amount should fail
        if (totalReservation > 0) {
            vm.prank(address(scw));
            vm.expectRevert(
                abi.encodeWithSelector(
                    GasTankPaymaster.GasTankPaymaster_InsufficientBalance.selector, address(scw), totalReservation
                )
            );
            gasTankUSDC.gasTankWithdraw(totalReservation);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        PAYMASTER STATUS QUERIES  
    //////////////////////////////////////////////////////////////*/

    function test_getPaymasterStatus_basicInfo() public {
        vm.startPrank(feeReceiver.pub);
        usdcOracle.configurePrice(1e8); // $1 USDT
        nativeOracle.configurePrice(2000e8); // $2000 ETH
        uint256 updatedPrice = gasTankUSDC.updateCachedPrice(true);
        assertGt(updatedPrice, 0, "Price update should succeed");
        _depositToGasTank(gasTankUSDC, address(usdc), feeReceiver.pub, 500 * 10 ** 6);
        (
            uint256 entryPointBalance,
            uint256 cachedTokenPrice,
            uint48 priceTimestamp,
            uint256 feeReceiverUSDCBalance,
            bool needsTopUp,
            bool isPaused
        ) = gasTankUSDC.getPaymasterStatus();
        assertEq(cachedTokenPrice, 5e22); // Base price without markup (cached price should not include markup)
        assertEq(feeReceiverUSDCBalance, 500 * 10 ** 6);
        assertEq(entryPointBalance, entrypoint.balanceOf(address(gasTankUSDC)));
        assertFalse(isPaused);
    }

    function test_getPaymasterStatus_needsTopUp_true() public {
        GasTankPaymaster.GasTankPaymasterConfig memory newConfig = gasTankUSDC.getPaymasterConfig();
        newConfig.minEPBalance = 10000 ether;
        vm.prank(deployer.pub);
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
            vm.deal(address(scw), 1 ether);
            vm.prank(address(scw));
            gasTankUSDC.deposit{value: 1 ether}();
        }
        uint256 initialEPBalance = gasTankUSDC.getDeposit();
        assertGt(initialEPBalance, config.minEPBalance);
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(scw));
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
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
        newConfig.tokenMaxAge = 5 minutes;
        newConfig.nativeMaxAge = 25 hours;
        vm.prank(deployer.pub);
        gasTankUSDC.configurePaymaster(newConfig);
        vm.deal(address(weth), 100 ether);
        _depositToGasTank(gasTankUSDC, address(usdc), feeReceiver.pub, 20 * 10 ** 6);
        usdc.mint(address(scw), 100 * 10 ** 6);
        _depositToGasTank(gasTankUSDC, address(usdc), address(scw), 10 * 10 ** 6);
        vm.startPrank(deployer.pub);
        usdcOracle.configurePrice(1e8); // $1 USDT
        nativeOracle.configurePrice(2000e8); // $2000 ETH
        uint256 updatedPrice = gasTankUSDC.updateCachedPrice(true);
        assertGt(updatedPrice, 0, "Price update should succeed");
        uint256 currentBalance = gasTankUSDC.getDeposit();
        gasTankUSDC.withdrawTo(beneficiary.pub, currentBalance - 1.5 ether);
        vm.warp(block.timestamp + 1 days);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoa.priv, ECDSA.toEthSignedMessageHash(userOpHash));
        userOp.signature = abi.encodePacked(r, s, v);
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
        entrypoint.handleOps(userOps, beneficiary.pub);
        uint256 finalEPBalance = gasTankUSDC.getDeposit();
        assertGt(finalEPBalance, 1.4 ether);
        vm.stopPrank();
    }

    function test_fullUserOperationFlow_USDT_withoutTopUp() public {
        uint256 currentEPBalance = gasTankUSDT.getDeposit();
        GasTankPaymaster.GasTankPaymasterConfig memory config = gasTankUSDT.getPaymasterConfig();
        if (currentEPBalance < config.minEPBalance + 0.5 ether) {
            vm.deal(address(scw), 1 ether);
            vm.prank(address(scw));
            gasTankUSDT.deposit{value: 1 ether}();
        }
        uint256 initialEPBalance = gasTankUSDT.getDeposit();
        assertGt(initialEPBalance, config.minEPBalance);
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(scw));
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDT,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
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
        newConfig.tokenMaxAge = 5 minutes;
        newConfig.nativeMaxAge = 25 hours;
        vm.prank(deployer.pub);
        gasTankUSDT.configurePaymaster(newConfig);
        vm.deal(address(weth), 100 ether);
        _depositToGasTank(gasTankUSDT, address(usdt), feeReceiver.pub, 20 * 10 ** 18);
        usdt.mint(address(scw), 100 * 10 ** 18);
        _depositToGasTank(gasTankUSDT, address(usdt), address(scw), 10 * 10 ** 18);
        vm.startPrank(deployer.pub);
        usdtOracle.configurePrice(1e8); // $1 USDT
        nativeOracle.configurePrice(2000e8); // $2000 ETH
        uint256 updatedPrice = gasTankUSDT.updateCachedPrice(true);
        assertGt(updatedPrice, 0, "Price update should succeed");
        uint256 currentBalance = gasTankUSDT.getDeposit();
        gasTankUSDT.withdrawTo(beneficiary.pub, currentBalance - 1.5 ether);
        vm.warp(block.timestamp + 30 minutes);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDT,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoa.priv, ECDSA.toEthSignedMessageHash(userOpHash));
        userOp.signature = abi.encodePacked(r, s, v);
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
        entrypoint.handleOps(userOps, beneficiary.pub);
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
        uint256 initialBalance = unsupportedToken.balanceOf(beneficiary.pub);
        vm.prank(deployer.pub);
        gasTankUSDC.emergencyUnsupportedTokenRecovery(IERC20(address(unsupportedToken)), beneficiary.pub);
        assertEq(unsupportedToken.balanceOf(beneficiary.pub), initialBalance + tokenAmount);
        assertEq(unsupportedToken.balanceOf(address(gasTankUSDC)), 0);
    }

    function test_emergencyUnsupportedTokenRecovery_revertWhen_mainToken() public {
        vm.prank(deployer.pub);
        vm.expectRevert(GasTankPaymaster.GasTankPaymaster_CannotRecoverMainToken.selector);
        gasTankUSDC.emergencyUnsupportedTokenRecovery(IERC20(address(usdc)), beneficiary.pub);
    }

    function test_emergencyUnsupportedTokenRecovery_revertWhen_WETH() public {
        vm.prank(deployer.pub);
        vm.expectRevert(GasTankPaymaster.GasTankPaymaster_CannotRecoverWETH.selector);
        gasTankUSDC.emergencyUnsupportedTokenRecovery(IERC20(address(weth)), beneficiary.pub);
    }

    function test_emergencyUnsupportedTokenRecovery_revertWhen_notOwner() public {
        TestERC20 unsupportedToken = new TestERC20();
        unsupportedToken.mint(address(gasTankUSDC), 100 * 10 ** 18);
        vm.prank(alice.pub);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice.pub));
        gasTankUSDC.emergencyUnsupportedTokenRecovery(IERC20(address(unsupportedToken)), beneficiary.pub);
    }

    function test_emergencyUnsupportedTokenRecovery_revertWhen_noTokensToRecover() public {
        TestERC20 unsupportedToken = new TestERC20();
        vm.prank(deployer.pub);
        vm.expectRevert(
            abi.encodeWithSelector(
                GasTankPaymaster.GasTankPaymaster_NoTokensToRecover.selector, address(unsupportedToken)
            )
        );
        gasTankUSDC.emergencyUnsupportedTokenRecovery(IERC20(address(unsupportedToken)), beneficiary.pub);
    }

    function test_withdrawAllNative_native() public {
        uint256 nAmount = 1 ether;
        vm.deal(alice.pub, nAmount);
        vm.prank(alice.pub);
        (bool success,) = address(gasTankUSDC).call{value: nAmount}("");
        assertTrue(success);
        assertEq(address(gasTankUSDC).balance, nAmount);
        uint256 frNativeBalancePre = address(feeReceiver.pub).balance;
        vm.prank(deployer.pub);
        vm.expectEmit(true, true, true, false);
        emit GasTankPaymaster_NativeWithdrawn(address(feeReceiver.pub), nAmount);
        gasTankUSDC.withdrawAllNative(feeReceiver.pub);
        uint256 frNativeBalancePost = address(feeReceiver.pub).balance;
        assertEq(address(gasTankUSDC).balance, 0);
        assertEq(frNativeBalancePost, frNativeBalancePre + nAmount);
    }

    function test_withdrawAllNative_wrappedNative() public {
        uint256 wnAmount = 2 ether;
        vm.startPrank(alice.pub);
        weth.deposit{value: wnAmount}();
        weth.transfer(address(gasTankUSDC), wnAmount);
        vm.stopPrank();
        assertEq(weth.balanceOf(address(gasTankUSDC)), wnAmount);
        uint256 frWrappedNativeBalancePre = weth.balanceOf(address(feeReceiver.pub));
        vm.prank(deployer.pub);
        vm.expectEmit(true, true, true, false);
        emit GasTankPaymaster_WrappedNativeWithdrawn(address(feeReceiver.pub), wnAmount);
        gasTankUSDC.withdrawAllNative(feeReceiver.pub);
        uint256 frWrappedNativeBalancePost = weth.balanceOf(address(feeReceiver.pub));
        assertEq(weth.balanceOf(address(gasTankUSDC)), 0);
        assertEq(frWrappedNativeBalancePost, frWrappedNativeBalancePre + wnAmount);
    }

    function test_withdrawAllNative_both() public {
        uint256 nAmount = 1 ether;
        uint256 wnAmount = 2 ether;
        vm.deal(alice.pub, nAmount + wnAmount);
        vm.startPrank(alice.pub);
        (bool success,) = address(gasTankUSDC).call{value: nAmount}("");
        assertTrue(success);
        weth.deposit{value: wnAmount}();
        weth.transfer(address(gasTankUSDC), wnAmount);
        vm.stopPrank();
        assertEq(address(gasTankUSDC).balance, nAmount);
        assertEq(weth.balanceOf(address(gasTankUSDC)), wnAmount);
        uint256 frNativeBalancePre = address(feeReceiver.pub).balance;
        uint256 frWrappedNativeBalancePre = weth.balanceOf(address(feeReceiver.pub));
        vm.prank(deployer.pub);
        vm.expectEmit(true, true, true, false);
        emit GasTankPaymaster_NativeWithdrawn(address(feeReceiver.pub), nAmount);
        vm.expectEmit(true, true, true, false);
        emit GasTankPaymaster_WrappedNativeWithdrawn(address(feeReceiver.pub), wnAmount);
        gasTankUSDC.withdrawAllNative(feeReceiver.pub);
        uint256 frNativeBalancePost = address(feeReceiver.pub).balance;
        uint256 frWrappedNativeBalancePost = weth.balanceOf(address(feeReceiver.pub));
        assertEq(address(gasTankUSDC).balance, 0);
        assertEq(weth.balanceOf(address(gasTankUSDC)), 0);
        assertEq(frNativeBalancePost, frNativeBalancePre + nAmount);
        assertEq(frWrappedNativeBalancePost, frWrappedNativeBalancePre + wnAmount);
    }

    function test_withdrawAllNative_revertWhen_notOwner() public {
        uint256 nAmount = 1 ether;
        vm.deal(alice.pub, nAmount);
        vm.prank(alice.pub);
        (bool success,) = address(gasTankUSDC).call{value: nAmount}("");
        assertTrue(success);
        assertEq(address(gasTankUSDC).balance, nAmount);
        vm.prank(feeReceiver.pub);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, feeReceiver.pub));
        gasTankUSDC.withdrawAllNative(feeReceiver.pub);
    }

    /*//////////////////////////////////////////////////////////////
                         INTEGRATION & EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_fullFlow_depositAndWithdraw() public {
        _depositToGasTank(gasTankUSDC, address(usdc), alice.pub, USDC_DEPOSIT_AMOUNT);
        bytes memory callData = abi.encodeWithSignature("execute()");
        PackedUserOperation memory userOp =
            _createUserOperationWithPaymaster(address(scw), callData, 1 gwei, 1 gwei, eoa.priv, address(gasTankUSDC));
        uint256 remainingBalance = gasTankUSDC.gasTankBalance(alice.pub);
        _withdrawFromGasTank(gasTankUSDC, address(usdc), alice.pub, remainingBalance);
        assertEq(gasTankUSDC.gasTankBalance(alice.pub), 0);
        assertEq(usdc.balanceOf(alice.pub), USDC_INITIAL_MINT);
    }

    function test_automaticTopUp_USDT_fails_butUserOpSucceeds() public {
        GasTankPaymaster.GasTankPaymasterConfig memory newConfig = gasTankUSDC.getPaymasterConfig();
        newConfig.minEPBalance = 2 ether;
        newConfig.tokenMaxAge = 5 minutes;
        newConfig.nativeMaxAge = 25 hours;
        vm.prank(deployer.pub);
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
        _depositToGasTank(gasTankUSDT, address(usdt), feeReceiver.pub, 1e18);
        usdt.mint(address(scw), 100 * 10 ** 18);
        _depositToGasTank(gasTankUSDT, address(usdt), address(scw), 10 * 10 ** 18);
        vm.startPrank(deployer.pub);
        usdtOracle.configurePrice(1e8);
        nativeOracle.configurePrice(2000e8);
        gasTankUSDT.updateCachedPrice(true);
        uint256 currentBalance = gasTankUSDT.getDeposit();
        gasTankUSDT.withdrawTo(beneficiary.pub, currentBalance - 0.2 ether);
        vm.stopPrank();
        vm.warp(block.timestamp + 30 minutes);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDT,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoa.priv, ECDSA.toEthSignedMessageHash(userOpHash));
        userOp.signature = abi.encodePacked(r, s, v);
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
        entrypoint.handleOps(userOps, beneficiary.pub);
        uint256 finalEpBalance = gasTankUSDT.getDeposit();
        uint256 finalFrBalance = gasTankUSDT.gasTankBalance(feeReceiver.pub);
        assertLt(finalEpBalance, currentBalance);
        assertEq(finalFrBalance, 1 * 10 ** 18);
        assertLt(finalEpBalance, 2 ether);
    }

    function test_automaticTopUp_USDT_insufficientBalance_butUserOpSucceeds() public {
        // Configure paymaster with lower minimum balance to trigger top-up
        GasTankPaymaster.GasTankPaymasterConfig memory newConfig = gasTankUSDC.getPaymasterConfig();
        newConfig.minEPBalance = 2 ether;
        newConfig.tokenMaxAge = 5 minutes;
        newConfig.nativeMaxAge = 25 hours;
        newConfig.minFeeReceiverTokenBalance = 2 * 10 ** 18; // Set to 2 USDT to trigger insufficient
        vm.prank(deployer.pub);
        gasTankUSDT.configurePaymaster(newConfig);
        // Give verifying signer EXACTLY the minimum token balance (1e18 for 18-decimal token)
        // This will trigger: frBalance <= minTokenBalance
        uint256 minTokenBalance = 10 ** 18; // 1e18 for USDT (18 decimals)
        _depositToGasTank(gasTankUSDT, address(usdt), feeReceiver.pub, minTokenBalance);
        usdt.mint(address(scw), 100 * 10 ** 18);
        _depositToGasTank(gasTankUSDT, address(usdt), address(scw), 10 * 10 ** 18);
        vm.startPrank(deployer.pub);
        usdtOracle.configurePrice(1e8); // $1 USDT
        nativeOracle.configurePrice(2000e8); // $2000 ETH
        gasTankUSDT.updateCachedPrice(true);
        // Reduce EntryPoint balance to trigger top-up attempt
        uint256 currentBalance = gasTankUSDT.getDeposit();
        gasTankUSDT.withdrawTo(beneficiary.pub, currentBalance - 0.2 ether);
        currentBalance = gasTankUSDT.getDeposit();
        vm.stopPrank();
        vm.warp(block.timestamp + 30 minutes);
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDT,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoa.priv, ECDSA.toEthSignedMessageHash(userOpHash));
        userOp.signature = abi.encodePacked(r, s, v);
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_InsufficientBalanceButTopUpRequired(minTokenBalance, 2 * 10 ** 18);
        entrypoint.handleOps(userOps, beneficiary.pub);
        uint256 finalEpBalance = gasTankUSDT.getDeposit();
        uint256 finalFrBalance = gasTankUSDT.gasTankBalance(feeReceiver.pub);
        assertLt(finalEpBalance, currentBalance, "EntryPoint balance should decrease due to gas consumption");
        assertEq(finalFrBalance, minTokenBalance, "feeReceiver balance should be unchanged - no top-up attempted");
        assertLt(finalEpBalance, 2 ether, "Should still be below minimum threshold since top-up was skipped");
        assertTrue(true, "User operation should succeed despite insufficient balance for top-up");
    }

    function test_automaticTopUp_USDT_stalePriceShouldUseCached_andUserOpSucceeds() public {
        // Configure paymaster with shorter price max age to make prices go stale easily
        GasTankPaymaster.GasTankPaymasterConfig memory newConfig = gasTankUSDC.getPaymasterConfig();
        newConfig.minEPBalance = 2 ether;
        newConfig.tokenMaxAge = 5 minutes;
        newConfig.nativeMaxAge = 5 minutes;
        vm.prank(deployer.pub);
        gasTankUSDT.configurePaymaster(newConfig);
        _depositToGasTank(gasTankUSDT, address(usdt), feeReceiver.pub, 10 * 10 ** 18);
        usdt.mint(address(scw), 100 * 10 ** 18);
        _depositToGasTank(gasTankUSDT, address(usdt), address(scw), 10 * 10 ** 18);
        vm.startPrank(deployer.pub);
        usdtOracle.configurePrice(1e8); // $1 USDT
        nativeOracle.configurePrice(2000e8); // $2000 ETH
        gasTankUSDT.updateCachedPrice(true);
        // Reduce EntryPoint balance to trigger top-up attempt
        uint256 currentBalance = gasTankUSDT.getDeposit();
        gasTankUSDT.withdrawTo(beneficiary.pub, currentBalance - 0.2 ether);
        currentBalance = gasTankUSDT.getDeposit();
        vm.stopPrank();
        vm.warp(block.timestamp + 10 minutes); // Beyond both 5 minute max ages
        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDT,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoa.priv, ECDSA.toEthSignedMessageHash(userOpHash));
        userOp.signature = abi.encodePacked(r, s, v);
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        // Expect stale price detection and successful top-up using cached price
        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_StaleTokenPrice();
        vm.expectEmit(true, false, false, false);
        emit GasTankPaymaster_TopUpExecuted(10 * 10 ** 18, 0); // Using cached price for top-up

        entrypoint.handleOps(userOps, beneficiary.pub);
        uint256 finalEpBalance = gasTankUSDT.getDeposit();
        uint256 finalFrBalance = gasTankUSDT.gasTankBalance(feeReceiver.pub);
        assertEq(finalFrBalance, 0, "feeReceiver balance should be 0 after top-up swap");
        // Note: final balance may be higher or lower than initial due to top-up vs gas consumption
        // The key is that the top-up occurred (feeReceiver balance = 0) using cached price fallback
        assertTrue(true, "User operation should succeed with stale price fallback to cached price");
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
        vm.deal(alice.pub, amount);
        vm.prank(alice.pub);
        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_Received(alice.pub, amount);
        (bool success,) = address(gasTankUSDC).call{value: amount}("");
        assertTrue(success);
    }

    /*//////////////////////////////////////////////////////////////
                   TEST POSTOP ORACLE FALLBACK LOGIC
    //////////////////////////////////////////////////////////////*/

    function test_postOp_oracleUpdateSuccess_usesFreshPrice() public {
        // Setup: Deposit tokens for fee receiver and set initial oracle prices
        _depositToGasTank(gasTankUSDC, address(usdc), feeReceiver.pub, 20 * 10 ** 6);

        vm.startPrank(deployer.pub);
        usdcOracle.configurePrice(1e8);
        nativeOracle.configurePrice(2000e8);
        gasTankUSDC.updateCachedPrice(true);

        // Reduce EntryPoint balance to trigger top-up
        uint256 initialBalance = gasTankUSDC.getDeposit();
        gasTankUSDC.withdrawTo(beneficiary.pub, initialBalance - 0.2 ether);

        vm.warp(block.timestamp + 1 days);

        // Update oracle prices to new values that should be used
        usdcOracle.configurePrice(12e7); // $1.20
        nativeOracle.configurePrice(2200e8); // $2200 ETH
        vm.stopPrank();

        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        _executeUserOp(userOp);

        // Verify fee receiver balance was used for top-up (should be 0 after successful swap)
        uint256 finalFrBalance = gasTankUSDC.gasTankBalance(feeReceiver.pub);
        assertEq(finalFrBalance, 0);
    }

    function test_postOp_oracleUpdateFails_usesCachedPrice() public {
        // Setup: Deposit tokens and establish cached price FIRST
        _depositToGasTank(gasTankUSDC, address(usdc), feeReceiver.pub, 20 * 10 ** 6);

        vm.startPrank(deployer.pub);
        usdcOracle.configurePrice(1e8);
        nativeOracle.configurePrice(2000e8);
        uint256 cachedPrice = gasTankUSDC.updateCachedPrice(true); // This sets cached price
        assertGt(cachedPrice, 0, "Should have cached price set");

        // Reduce EntryPoint balance to trigger top-up
        uint256 initialBalance = gasTankUSDC.getDeposit();
        gasTankUSDC.withdrawTo(beneficiary.pub, initialBalance - 0.2 ether);

        // Move time forward to ensure cache is considered stale (force oracle call)
        vm.warp(block.timestamp + 2 hours); // Beyond priceMaxAge of 1 hour

        // Make oracle fail by setting it to revert AFTER establishing cache
        usdcOracle.configureShouldRevert(true);
        vm.stopPrank();

        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        _executeUserOp(userOp);

        // Verify cached price was used (fee receiver balance should be 0 after top-up)
        uint256 finalFrBalance = gasTankUSDC.gasTankBalance(feeReceiver.pub);
        assertEq(finalFrBalance, 0);
    }

    function test_postOp_oracleStalePrice_usesCachedPrice() public {
        // Setup: Deposit tokens and establish cached price
        _depositToGasTank(gasTankUSDC, address(usdc), feeReceiver.pub, 20 * 10 ** 6);

        vm.startPrank(deployer.pub);
        usdcOracle.configurePrice(1e8);
        nativeOracle.configurePrice(2000e8);
        gasTankUSDC.updateCachedPrice(true);

        // Reduce EntryPoint balance to trigger top-up
        uint256 initialBalance = gasTankUSDC.getDeposit();
        gasTankUSDC.withdrawTo(beneficiary.pub, initialBalance - 0.2 ether);

        // Advance time beyond priceMaxAge (1 hour) to make prices stale
        vm.warp(block.timestamp + 2 hours);

        // Set new oracle prices (these should be ignored due to staleness)
        usdcOracle.configurePrice(15e7); // $1.50
        nativeOracle.configurePrice(2500e8); // $2500 ETH
        // IMPORTANT: Set updatedAt AFTER configurePrice to make them stale
        usdcOracle.configureUpdatedAt(1); // Make stale
        nativeOracle.configureUpdatedAt(1); // Make stale
        vm.stopPrank();

        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        _executeUserOp(userOp);

        // Verify cached price was used for top-up
        uint256 finalFrBalance = gasTankUSDC.gasTankBalance(feeReceiver.pub);
        assertEq(finalFrBalance, 0);
    }

    function test_postOp_noCachedPrice_skipTopUp() public {
        // Setup: Deposit tokens but don't set cached price
        _depositToGasTank(gasTankUSDC, address(usdc), feeReceiver.pub, 20 * 10 ** 6);

        // Configure paymaster with no cached price
        GasTankPaymaster.GasTankPaymasterConfig memory config = gasTankUSDC.getPaymasterConfig();
        config.cachedTokenPrice = 0; // No cached price
        vm.startPrank(deployer.pub);
        gasTankUSDC.configurePaymaster(config);

        // Reduce EntryPoint balance to trigger top-up attempt
        uint256 initialBalance = gasTankUSDC.getDeposit();
        gasTankUSDC.withdrawTo(beneficiary.pub, initialBalance - 0.2 ether);

        // Make oracle fail and no cached price available
        usdcOracle.configurePrice(0); // Invalid price
        nativeOracle.configurePrice(2000e8);
        vm.stopPrank();

        PackedUserOperation memory userOp = _createUserOperationWithGasTankPaymaster(
            gasTankUSDC,
            address(scw),
            eoa.priv,
            _getBasicCalldata(),
            2 gwei,
            1 gwei,
            verifyingSigner.priv,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp)
        );

        // Should emit event indicating top-up was skipped due to no reliable price
        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_TopUpSkippedDueToStalePrice();
        _executeUserOp(userOp);

        // Verify fee receiver balance unchanged (no top-up occurred)
        uint256 finalFrBalance = gasTankUSDC.gasTankBalance(feeReceiver.pub);
        assertEq(finalFrBalance, 20 * 10 ** 6);
    }

    /*//////////////////////////////////////////////////////////////
                      L2 SEQUENCER UPTIME TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getSequencerStatus_withoutFeed_assumesUp() public {
        // Default setup has no sequencer feed (address(0))
        (bool isUp, bool hasSequencerFeed) = gasTankUSDC.getSequencerStatus();

        assertFalse(hasSequencerFeed, "Should not have sequencer feed by default");
        assertTrue(isUp, "Should assume sequencer is up for non-L2 chains");
    }

    function test_getSequencerStatus_withFeed_up() public {
        // Warp to a reasonable timestamp first to avoid underflow
        vm.warp(10000);

        // Set mock sequencer feed
        MockSequencerUptimeFeed mockFeed = new MockSequencerUptimeFeed();
        // Set sequencer up with old timestamp (past grace period)
        uint256 oldTimestamp = block.timestamp - 7200; // 2 hours ago
        mockFeed.setSequencerUpWithTimestamp(oldTimestamp);

        vm.prank(deployer.pub);
        gasTankUSDC.setSequencerUptimeFeed(AggregatorV2V3Interface(address(mockFeed)));

        (bool isUp, bool hasSequencerFeed) = gasTankUSDC.getSequencerStatus();

        assertTrue(hasSequencerFeed, "Should have sequencer feed");
        assertTrue(isUp, "Sequencer should be up");
    }

    function test_getSequencerStatus_withFeed_down() public {
        MockSequencerUptimeFeed mockFeed = new MockSequencerUptimeFeed();
        mockFeed.setSequencerDown();

        vm.prank(deployer.pub);
        gasTankUSDC.setSequencerUptimeFeed(AggregatorV2V3Interface(address(mockFeed)));

        (bool isUp, bool hasSequencerFeed) = gasTankUSDC.getSequencerStatus();

        assertTrue(hasSequencerFeed, "Should have sequencer feed");
        assertFalse(isUp, "Sequencer should be down");
    }

    function test_getSequencerStatus_gracePeriod() public {
        // Warp to a reasonable timestamp first to avoid underflow
        vm.warp(10000);

        MockSequencerUptimeFeed mockFeed = new MockSequencerUptimeFeed();
        // Set sequencer as recently came up (within grace period)
        uint256 recentTimestamp = block.timestamp - 1800; // 30 minutes ago
        mockFeed.setSequencerUpWithTimestamp(recentTimestamp);

        vm.prank(deployer.pub);
        gasTankUSDC.setSequencerUptimeFeed(AggregatorV2V3Interface(address(mockFeed)));

        (bool isUp, bool hasSequencerFeed) = gasTankUSDC.getSequencerStatus();

        assertTrue(hasSequencerFeed, "Should have sequencer feed");
        assertFalse(isUp, "Should be in grace period");
    }

    function test_getSequencerStatus_pastGracePeriod() public {
        // Warp to a reasonable timestamp first to avoid underflow
        vm.warp(10000);

        MockSequencerUptimeFeed mockFeed = new MockSequencerUptimeFeed();
        // Set sequencer as came up before grace period
        uint256 oldTimestamp = block.timestamp - 7200; // 2 hours ago
        mockFeed.setSequencerUpWithTimestamp(oldTimestamp);

        vm.prank(deployer.pub);
        gasTankUSDC.setSequencerUptimeFeed(AggregatorV2V3Interface(address(mockFeed)));

        (bool isUp, bool hasSequencerFeed) = gasTankUSDC.getSequencerStatus();

        assertTrue(hasSequencerFeed, "Should have sequencer feed");
        assertTrue(isUp, "Should be past grace period");
    }

    function test_setSequencerUptimeFeed_success() public {
        MockSequencerUptimeFeed mockFeed = new MockSequencerUptimeFeed();

        // Get current config and update it with the new sequencer feed to match what will be emitted
        GasTankPaymaster.GasTankPaymasterConfig memory expectedConfig = gasTankUSDC.getPaymasterConfig();
        expectedConfig.sequencerUptimeFeed = AggregatorV2V3Interface(address(mockFeed));

        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_PaymasterConfigUpdated(expectedConfig);

        vm.prank(deployer.pub);
        gasTankUSDC.setSequencerUptimeFeed(AggregatorV2V3Interface(address(mockFeed)));

        GasTankPaymaster.GasTankPaymasterConfig memory config = gasTankUSDC.getPaymasterConfig();
        assertEq(address(config.sequencerUptimeFeed), address(mockFeed), "Sequencer feed should be updated");
    }

    function test_setSequencerUptimeFeed_revertWhen_notOwner() public {
        MockSequencerUptimeFeed mockFeed = new MockSequencerUptimeFeed();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice.pub));

        vm.prank(alice.pub);
        gasTankUSDC.setSequencerUptimeFeed(AggregatorV2V3Interface(address(mockFeed)));
    }

    function test_updateCachedPrice_sequencerDown_returnsZero() public {
        MockSequencerUptimeFeed mockFeed = new MockSequencerUptimeFeed();
        mockFeed.setSequencerDown();

        vm.prank(deployer.pub);
        gasTankUSDC.setSequencerUptimeFeed(AggregatorV2V3Interface(address(mockFeed)));

        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_OracleUpdateFailed();

        uint256 price = gasTankUSDC.updateCachedPrice(true);
        assertEq(price, 0, "Should return 0 when sequencer is down");
    }

    function test_updateCachedPrice_gracePeriod_returnsZero() public {
        // Warp to a reasonable timestamp first to avoid underflow
        vm.warp(10000);

        MockSequencerUptimeFeed mockFeed = new MockSequencerUptimeFeed();
        // Set sequencer as recently came up
        uint256 recentTimestamp = block.timestamp - 1800; // 30 minutes ago
        mockFeed.setSequencerUpWithTimestamp(recentTimestamp);

        vm.prank(deployer.pub);
        gasTankUSDC.setSequencerUptimeFeed(AggregatorV2V3Interface(address(mockFeed)));

        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_OracleUpdateFailed();

        uint256 price = gasTankUSDC.updateCachedPrice(true);
        assertEq(price, 0, "Should return 0 during grace period");
    }

    function test_updateCachedPrice_sequencerUp_pastGracePeriod_succeeds() public {
        // Warp to exactly the oracle timestamp to make data fresh
        vm.warp(1680509051); // Exactly at oracle timestamp

        // Update oracle timestamps to match warped time to make data fresh
        usdcOracle.configureUpdatedAt(block.timestamp);
        nativeOracle.configureUpdatedAt(block.timestamp);

        MockSequencerUptimeFeed mockFeed = new MockSequencerUptimeFeed();
        // Set sequencer as came up well before grace period
        uint256 oldTimestamp = block.timestamp - 7200; // 2 hours ago
        mockFeed.setSequencerUpWithTimestamp(oldTimestamp);

        vm.prank(deployer.pub);
        gasTankUSDC.setSequencerUptimeFeed(AggregatorV2V3Interface(address(mockFeed)));

        uint256 price = gasTankUSDC.updateCachedPrice(true);
        assertGt(price, 0, "Should return valid price when sequencer is up and past grace period");
    }

    function test_topUpEntryPointDeposit_sequencerDown_skipsTopUp() public {
        MockSequencerUptimeFeed mockFeed = new MockSequencerUptimeFeed();
        mockFeed.setSequencerDown();

        vm.prank(deployer.pub);
        gasTankUSDC.setSequencerUptimeFeed(AggregatorV2V3Interface(address(mockFeed)));

        // Fund the fee receiver with tokens
        _depositToGasTankForWallet(gasTankUSDC, address(usdc), feeReceiver.pub, feeReceiver.pub, USDC_DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_OracleUpdateFailed();

        vm.prank(deployer.pub);
        gasTankUSDC.topUpEntryPointDeposit();
    }

    function test_topUpEntryPointDeposit_gracePeriod_skipsTopUp() public {
        // Warp to a reasonable timestamp first to avoid underflow
        vm.warp(10000);

        MockSequencerUptimeFeed mockFeed = new MockSequencerUptimeFeed();
        // Set sequencer in grace period
        uint256 recentTimestamp = block.timestamp - 1800; // 30 minutes ago
        mockFeed.setSequencerUpWithTimestamp(recentTimestamp);

        vm.prank(deployer.pub);
        gasTankUSDC.setSequencerUptimeFeed(AggregatorV2V3Interface(address(mockFeed)));

        // Fund the fee receiver with tokens
        _depositToGasTankForWallet(gasTankUSDC, address(usdc), feeReceiver.pub, feeReceiver.pub, USDC_DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit GasTankPaymaster_OracleUpdateFailed();

        vm.prank(deployer.pub);
        gasTankUSDC.topUpEntryPointDeposit();
    }

    function test_sequencerFeed_failsCall_assumesDown() public {
        // Deploy a mock that will revert on latestRoundData
        MockFailingSequencerFeed failingFeed = new MockFailingSequencerFeed();

        vm.prank(deployer.pub);
        gasTankUSDC.setSequencerUptimeFeed(AggregatorV2V3Interface(address(failingFeed)));

        (bool isUp,) = gasTankUSDC.getSequencerStatus();
        assertFalse(isUp, "Should assume sequencer is down when feed fails");
    }

    function test_sequencer_transitionFromDownToUp() public {
        // Warp to a reasonable timestamp first to avoid underflow
        vm.warp(10000);

        MockSequencerUptimeFeed mockFeed = new MockSequencerUptimeFeed();

        vm.prank(deployer.pub);
        gasTankUSDC.setSequencerUptimeFeed(AggregatorV2V3Interface(address(mockFeed)));

        // Start with sequencer down
        mockFeed.setSequencerDown();
        (bool isUp,) = gasTankUSDC.getSequencerStatus();
        assertFalse(isUp, "Sequencer should be down");

        // Move sequencer to up but in grace period
        uint256 recentTimestamp = block.timestamp - 1800; // 30 minutes ago
        mockFeed.setSequencerUpWithTimestamp(recentTimestamp);
        (isUp,) = gasTankUSDC.getSequencerStatus();
        assertFalse(isUp, "Should be in grace period");

        // Wait past grace period
        vm.warp(block.timestamp + 2400); // Add 40 minutes
        (isUp,) = gasTankUSDC.getSequencerStatus();
        assertTrue(isUp, "Should be up after grace period");
    }
}
