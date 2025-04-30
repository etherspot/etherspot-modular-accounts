// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC7579Account} from "../../../../src/interfaces/base/IERC7579Account.sol";
import {ExecutionLib} from "../../../../src/libraries/ExecutionLib.sol";
import {ModeLib} from "../../../../src/libraries/ModeLib.sol";
import {HookMultiPlexerLib as HMPL} from "../../../../src/libraries/HookMultiPlexerLib.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {MODULE_TYPE_HOOK, MODULE_TYPE_VALIDATOR} from "../../../../src/types/Constants.sol";
import {HookType} from "../../../../src/types/Enums.sol";
import {Execution, ResourceLock, SessionData, SigHookInit, TokenData} from "../../../../src/types/Structs.sol";
import {CredibleAccountTestUtils as TestUtils} from "../utils/CredibleAccountTestUtils.sol";
import {TestUniswapV2} from "../../../../src/test/TestUniswapV2.sol";

contract CredibleAccountTest is TestUtils {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CredibleAccountValidator_ModuleInstalled(address wallet);
    event CredibleAccountValidator_ModuleUninstalled(address wallet);
    event CredibleAccountValidator_SessionKeyEnabled(address indexed owner, address indexed sessionKey);
    event CredibleAccountValidator_SessionKeyDisabled(address indexed owner, address indexed sessionKey);
    event CredibleAccountValidator_TokenLocked(address indexed sessionKey, address indexed token, uint256 amount);
    event TokenClaimed(address indexed sessionKey, address indexed wallet, address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ValidatorUninstallFailed(address module, bytes data);
    error CredibleAccountValidator_InvalidHookMultiPlexer();
    error CredibleAccountValidator_HookMultiplexerIsNotInstalled();
    error CredibleAccountValidator_NotAddedToHookMultiplexer();
    error CredibleAccountValidator_SessionKeyAlreadyExists(address sessionKey);
    error CredibleAccountValidator_SessionKeyDoesNotExist(address sessionKey);
    error CredibleAccountValidator_InvalidSessionKeyParameters(address sessionKey, uint48 validAfter, uint48 validUntil);
    error CredibleAccountValidator_NoTokenDataProvided();
    error CredibleAccountValidator_InvalidTokenData();
    error CredibleAccountValidator_LockedTokensNotClaimed(address sessionKey);
    error CredibleAccountValidator_SessionKeyNotInWalletList(address owner, address sessionKey);
    error CredibleAccountHook_InsufficientUnlockedBalance(address token);
    error CredibleAccountHook_UninstallCredibleAccountValidatorFirst();

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testSetup();
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    // Test: Verify that the CredibleAccountValidator module can be installed
    // as validator and CredibleAccountHook as hook module
    function test_installModules() public withRequiredModules {
        // Verify that the validator module is installed
        assertTrue(
            SCW.isModuleInstalled(
                MODULE_TYPE_VALIDATOR,
                address(CREDIBLE_ACCOUNT_VALIDATOR),
                "CredibleAccountValidator module should be installed"
            )
        );
        // Verify that the hook module is installed via multiplexer
        assertEq(SCW.getActiveHook(), address(HOOK_MULTIPLEXER), "Active hook should be HookMultiPlexer");
        assertEq(HOOK_MULTIPLEXER.getHooks(address(SCW))[0], address(CREDIBLE_ACCOUNT_HOOK));
    }

    // todo: test removing hook and its removed
    function test_uninstallCredibleAccountHook() public withRequiredModules {
        // Verify that the hook is installed
        assertEq(HOOK_MULTIPLEXER.getHooks(address(SCW))[0], address(CREDIBLE_ACCOUNT_HOOK));
        // Uninstall the CredibleAccountValidator first
        _uninstallModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), hex"");
        // Uninstall the hook from the multiplexer
        _uninstallHookViaMultiplexer(SCW, address(CREDIBLE_ACCOUNT_HOOK), HookType.GLOBAL);
        // Verify the hook is removed
        assertEq(HOOK_MULTIPLEXER.getHooks(address(SCW)).length, 0, "Hook should be uninstalled");
    }

    function test_uninstallCredibleAccountHook_RevertIf_ValidatorStillInstalled() public withRequiredModules {
        // Verify that the hook is installed
        assertEq(HOOK_MULTIPLEXER.getHooks(address(SCW))[0], address(CREDIBLE_ACCOUNT_HOOK));
        // Should revert if CredibleAccountValidator still installed
        _toRevert(CredibleAccountHook_UninstallCredibleAccountValidatorFirst.selector, hex"");
        // Uninstall the hook from the multiplexer
        _uninstallHookViaMultiplexer(SCW, address(CREDIBLE_ACCOUNT_HOOK), HookType.GLOBAL);
        // Verify the hook is removed
        assertEq(HOOK_MULTIPLEXER.getHooks(address(SCW)).length, 1, "Hook should remain installed");
    }

    function test_onInstall_Validator_ViaUserOp_Single() public withRequiredModules {
        bytes memory installData = abi.encodeWithSelector(
            ModularEtherspotWallet.installModule.selector,
            uint256(MODULE_TYPE_VALIDATOR),
            address(CREDIBLE_ACCOUNT_VALIDATOR),
            abi.encode(MODULE_TYPE_VALIDATOR)
        );
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(SCW), 0, installData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(eoa, address(SCW), address(ECDSA_VALIDATOR), opCalldata);
        // Execute the user operation
        _executeUserOp(op);
        // Verify
        assertTrue(
            SCW.isModuleInstalled(
                MODULE_TYPE_VALIDATOR,
                address(CREDIBLE_ACCOUNT_VALIDATOR),
                "CredibleAccountValidator module should be installed"
            )
        );
        vm.stopPrank();
    }

    function test_onInstall_Hook_ViaUserOp() public {
        _testSetup();
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        _installHookViaMultiplexer(SCW, address(CREDIBLE_ACCOUNT_HOOK), HookType.GLOBAL);
        assertEq(HOOK_MULTIPLEXER.getHooks(address(SCW))[0], address(CREDIBLE_ACCOUNT_HOOK));
    }

    function test_onInstall_ValidatorAndHook_ViaUserOp_Batch() public {
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        vm.startPrank(address(SCW));
        Execution[] memory batch = new Execution[](2);
        batch[0] = Execution({
            target: address(HOOK_MULTIPLEXER),
            value: 0,
            callData: abi.encodeWithSelector(
                HOOK_MULTIPLEXER.addHook.selector, address(CREDIBLE_ACCOUNT_HOOK), HookType.GLOBAL
            )
        });
        batch[1] = Execution({
            target: address(SCW),
            value: 0,
            callData: abi.encodeWithSelector(
                ModularEtherspotWallet.installModule.selector,
                uint256(MODULE_TYPE_VALIDATOR),
                address(CREDIBLE_ACCOUNT_VALIDATOR),
                abi.encode(MODULE_TYPE_VALIDATOR)
            )
        });
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(eoa, address(SCW), address(ECDSA_VALIDATOR), opCalldata);
        // Execute the user operation
        _executeUserOp(op);
        // Verify that the modules are installed
        assertTrue(
            SCW.isModuleInstalled(
                MODULE_TYPE_VALIDATOR,
                address(CREDIBLE_ACCOUNT_VALIDATOR),
                "CredibleAccountValidator module should be installed"
            )
        );
        assertEq(HOOK_MULTIPLEXER.getHooks(address(SCW))[0], address(CREDIBLE_ACCOUNT_HOOK));
        vm.stopPrank();
    }

    // Test: Verify that the CredibleAccountValidator validator can be uninstalled
    // when all locked tokens have been claimed by the solver
    function test_uninstallModule_Validator_AllLockedTokensClaimed() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, SCW, amounts[0], amounts[1], amounts[2]);
        vm.stopPrank();
        // Execute the uninstallation
        _uninstallModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), hex"");
        // Verify that the module is uninstalled
        assertFalse(
            SCW.isModuleInstalled(
                MODULE_TYPE_VALIDATOR,
                address(CREDIBLE_ACCOUNT_VALIDATOR),
                "CredibleAccountValidator validator should not be installed"
            )
        );
    }

    // Test: Verify that the CredibleAccountValidator validator cannot be uninstalled
    // if locked tokens have not been claimed by the solver
    function test_uninstallModule_Validator_RevertWhen_LockedTokensNotClaimed() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Get previous validator in linked list
        address prevValidator = _getPrevValidator(SCW, address(CREDIBLE_ACCOUNT_VALIDATOR));
        _toRevert(ValidatorUninstallFailed.selector, abi.encode(address(CREDIBLE_ACCOUNT_VALIDATOR), hex""));
        SCW.uninstallModule(
            MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), abi.encode(prevValidator, hex"")
        );
        assertTrue(
            SCW.isModuleInstalled(
                MODULE_TYPE_VALIDATOR,
                address(CREDIBLE_ACCOUNT_VALIDATOR),
                "CredibleAccountValidator validator should be installed"
            )
        );

        vm.stopPrank();
    }

    // Test: Verify that a session key can be enabled
    function test_enableSessionKey() public withRequiredModules {
        vm.expectEmit(true, true, false, false);
        emit CredibleAccountValidator_SessionKeyEnabled(address(SCW), sessionKey.pub);
        // Enable session key
        _enableSessionKey(address(SCW));
        // Verify that the session key is enabled
        assertEq(CREDIBLE_ACCOUNT_VALIDATOR.getSessionKeysByWallet().length, 1, "Session key should be enabled");
        // Verify SessionData
        SessionData memory sessionData = CREDIBLE_ACCOUNT_VALIDATOR.getSessionData(sessionKey.pub, address(SCW));
        assertEq(sessionData.validUntil, validUntil, "validUntil does not match expected");
        assertEq(sessionData.validAfter, validAfter, "validAfter does not match expected");
        // Verify token data for session key
        TokenData[] memory tokenBalances =
            CREDIBLE_ACCOUNT_VALIDATOR.getSessionLockedTokenBalances(address(SCW), sessionKey.pub);
        assertEq(tokenBalances.length, 3, "Number of locked tokens does not match expected");
        assertEq(tokenBalances[0].token, tokens[0], "The first locked token address does not match expected");
        assertEq(tokenBalances[0].amount, amounts[0], "The first locked token amount does not match expected");
        assertEq(tokenBalances[1].token, tokens[1], "The second locked token address does not match expected");
        assertEq(tokenBalances[1].amount, amounts[1], "The second locked token amount does not match expected");
        assertEq(tokenBalances[2].token, tokens[2], "The third locked token address does not match expected");
        assertEq(tokenBalances[2].amount, amounts[2], "The third locked token amount does not match expected");
    }

    // Test: Enabling a session key with an invalid session key should revert
    function test_enableSessionKey_RevertIf_InvalidSessionKey() public withRequiredModules {
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(SCW),
                sessionKey: address(0),
                validAfter: validAfter,
                validUntil: validUntil,
                tokenData: tokenAmounts,
                nonce: 2
            })
        );
        // Attempt to enable the session key
        _toRevert(
            CredibleAccountValidator_InvalidSessionKeyParameters.selector,
            abi.encode(address(0), validAfter, validUntil)
        );
        CREDIBLE_ACCOUNT_VALIDATOR.enableSessionKey(rl);
        vm.stopPrank();
    }

    // Test: Enabling a session key with an invalid validAfter should revert
    function test_enableSessionKey_RevertIf_InvalidValidAfter() public withRequiredModules {
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(SCW),
                sessionKey: sessionKey.pub,
                validAfter: uint48(0),
                validUntil: validUntil,
                tokenData: tokenAmounts,
                nonce: 2
            })
        );
        // Attempt to enable the session key
        _toRevert(
            CredibleAccountValidator_InvalidSessionKeyParameters.selector,
            abi.encode(sessionKey.pub, uint48(0), validUntil)
        );
        CREDIBLE_ACCOUNT_VALIDATOR.enableSessionKey(rl);
        vm.stopPrank();
    }

    // Test: Enabling a session key with an invalid validUntil should revert
    function test_enableSessionKey_RevertIf_InvalidValidUntil() public withRequiredModules {
        // validUntil that is 0
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(SCW),
                sessionKey: sessionKey.pub,
                validAfter: validAfter,
                validUntil: uint48(0),
                tokenData: tokenAmounts,
                nonce: 2
            })
        );
        // Attempt to enable the session key
        _toRevert(
            CredibleAccountValidator_InvalidSessionKeyParameters.selector,
            abi.encode(sessionKey.pub, validAfter, uint48(0))
        );
        CREDIBLE_ACCOUNT_VALIDATOR.enableSessionKey(rl);
        // validUntil that is less than validAfter
        rl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(SCW),
                sessionKey: sessionKey.pub,
                validAfter: validAfter,
                validUntil: validAfter - 1,
                tokenData: tokenAmounts,
                nonce: 2
            })
        );
        // Attempt to enable the session key
        _toRevert(
            CredibleAccountValidator_InvalidSessionKeyParameters.selector,
            abi.encode(sessionKey.pub, validAfter, validAfter - 1)
        );
        CREDIBLE_ACCOUNT_VALIDATOR.enableSessionKey(rl);
        vm.stopPrank();
    }

    // Test: Verify that a session key can be disabled
    function test_disableSessionKey() public withRequiredModules {
        console2.log("test_disableSessionKey");
        // Enable session key
        _enableSessionKey(address(SCW));
        // Claim tokens by solver
        console2.log("Before claiming tokens by solver");
        _claimTokensBySolver(eoa, SCW, amounts[0], amounts[1], amounts[2]);
        console2.log("After claiming tokens by solver");
        // Expect emit a session key disabled event
        vm.expectEmit(true, true, false, false);
        emit CredibleAccountValidator_SessionKeyDisabled(address(SCW), sessionKey.pub);
        CREDIBLE_ACCOUNT_VALIDATOR.disableSessionKey(sessionKey.pub);
        vm.stopPrank();
    }

    // Test: Verify that a session key can be disabled after it expires
    // regardless of whether tokens are locked
    function test_disableSessionKey_WithLockedTokens_AfterSessionExpires() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Warp to a time after the session key has expired
        vm.warp(validUntil + 1);
        // Expect emit a session key disabled event
        vm.expectEmit(true, true, false, false);
        emit CredibleAccountValidator_SessionKeyDisabled(address(SCW), sessionKey.pub);
        CREDIBLE_ACCOUNT_VALIDATOR.disableSessionKey(sessionKey.pub);
        vm.stopPrank();
    }

    // Test: Disabling a session key with an invalid session key should revert
    function test_disableSessionKey_RevertIf_InvalidSessionKey() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Claim tokens by solver
        _claimTokensBySolver(eoa, SCW, amounts[0], amounts[1], amounts[2]);
        // Attempt to disable the session key
        _toRevert(
            CredibleAccountValidator_SessionKeyNotInWalletList.selector, abi.encode(address(SCW), otherSessionKey.pub)
        );
        CREDIBLE_ACCOUNT_VALIDATOR.disableSessionKey(otherSessionKey.pub);
        vm.stopPrank();
    }

    // Test: Disabling a session key when tokens aren't claimed reverts
    function test_disableSessionKey_RevertIf_TokensNotClaimed() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Attempt to disable the session key
        _toRevert(CredibleAccountValidator_LockedTokensNotClaimed.selector, abi.encode(sessionKey.pub));
        CREDIBLE_ACCOUNT_VALIDATOR.disableSessionKey(sessionKey.pub);
        vm.stopPrank();
    }

    // Test: Should return all session keys associated with a wallet
    function test_getSessionKeysByWallet() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        address[] memory sessions = CREDIBLE_ACCOUNT_VALIDATOR.getSessionKeysByWallet();
        assertEq(sessions.length, 1, "There should be one session key associated with wallet");
        assertEq(sessions[0], sessionKey.pub, "The associated session key should be the expected one");
        vm.stopPrank();
    }

    // Test: Should return correct session key data
    function test_getSessionData() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        SessionData memory sessionData = CREDIBLE_ACCOUNT_VALIDATOR.getSessionData(sessionKey.pub, address(SCW));
        assertEq(sessionData.validAfter, validAfter, "validAfter should be the expected value");
        assertEq(sessionData.validUntil, validUntil, "validUntil should be the expected value");
        vm.stopPrank();
    }

    // Test: claiming all tokens (batch)
    function test_claimingTokens_Batch() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, SCW, amounts[0], amounts[1], amounts[2]);
        // Check tokens are claimed
        assertTrue(CREDIBLE_ACCOUNT_VALIDATOR.isSessionClaimed(sessionKey.pub, address(SCW)));
        vm.stopPrank();
    }

    // Test: claiming tokens with an amount
    // that exceeds the locked amount fails (batch)
    function test_claimingTokens_Batch_RevertIf_ClaimExceedsLocked() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Set up calldata batch
        bytes memory usdcData = _createTokenTransferFromExecution(address(SCW), solver.pub, amounts[0]);
        bytes memory daiData = _createTokenTransferFromExecution(address(SCW), solver.pub, amounts[1]);
        bytes memory usdtData = _createTokenTransferFromExecution(address(SCW), solver.pub, amounts[2] + 1);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(USDC), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(DAI), value: 0, callData: daiData});
        batch[2] = Execution({target: address(USDT), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(SCW), address(CREDIBLE_ACCOUNT_VALIDATOR), opCalldata);
        // Expect the operation to revert due to signature error
        // (claiming exceeds locked)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, "AA24 signature error"));
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // Test: Should revert if the session key is expired
    // no tokens claimed yet
    // and solver tried to claim tokens
    function test_claimingTokens_Batch_RevertIf_SessionKeyExpired() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Warp time to expire the session key
        vm.warp(validUntil + 1);
        // Claim tokens by solver
        bytes memory usdcData = _createTokenTransferFromExecution(address(SCW), solver.pub, amounts[0]);
        bytes memory daiData = _createTokenTransferFromExecution(address(SCW), solver.pub, amounts[1]);
        bytes memory usdtData = _createTokenTransferFromExecution(address(SCW), solver.pub, amounts[2]);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(USDC), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(DAI), value: 0, callData: daiData});
        batch[2] = Execution({target: address(USDT), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(SCW), address(CREDIBLE_ACCOUNT_VALIDATOR), opCalldata);
        // Expect the operation to revert due to signature error (expired session)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, "AA22 expired or not due"));
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // Test: ERC20 transaction using amount that exceeds the
    // available unlocked balance fails (single)
    function test_transactingLockedTokens_Single_RevertIf_NotEnoughUnlockedBalance() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Mint extra tokens to wallet
        DAI.mint(address(SCW), 1e18);
        // Set up calldata batch
        // Invalid transaction as only 1 ether unlocked
        bytes memory daiData = _createTokenTransferFromExecution(address(SCW), alice.pub, 2e18);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute, (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(DAI), 0, daiData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(eoa, address(SCW), address(ECDSA_VALIDATOR), opCalldata);
        // Expect the HookMultiPlexer.SubHookPostCheckError error to be emitted
        // wrapped in UserOperationRevertReason event
        _revertUserOpEvent(
            hash, op.nonce, HMPL.SubHookPostCheckError.selector, abi.encode(address(CREDIBLE_ACCOUNT_HOOK))
        );
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // Test: ERC20 transaction using amount that exceeds the
    // available unlocked balance fails (batch)
    function test_transactingLockedTokens_Batch_RevertIf_OtherValidator() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Mint extra tokens to wallet
        USDC.mint(address(SCW), 1e6);
        DAI.mint(address(SCW), 1e18);
        USDT.mint(address(SCW), 1e18);
        // Set up calldata batch
        bytes memory usdcData = _createTokenTransferFromExecution(address(SCW), solver.pub, 1e6);
        bytes memory daiData = _createTokenTransferFromExecution(address(SCW), solver.pub, 1e18);
        // Invalid transaction as only 1 ether unlocked
        bytes memory usdtData = _createTokenTransferFromExecution(address(SCW), solver.pub, 2e18);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(USDC), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(DAI), value: 0, callData: daiData});
        batch[2] = Execution({target: address(USDT), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(eoa, address(SCW), address(ECDSA_VALIDATOR), opCalldata);
        // Expect the HookMultiPlexer.SubHookPostCheckError error to be emitted
        // wrapped in UserOperationRevertReason event
        _revertUserOpEvent(
            hash, op.nonce, HMPL.SubHookPostCheckError.selector, abi.encode(address(CREDIBLE_ACCOUNT_HOOK))
        );
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // Test: Uniswap V2 swap transaction using amount that exceeds the
    // available unlocked balance fails (single)
    function test_transactingLockedTokens_Complex_RevertIf_NotEnoughUnlockedBalance_singleExecute()
        public
        withRequiredModules
    {
        // Enable session key
        _enableSessionKey(address(SCW));
        USDT.mint(address(UNISWAP_V2), 10e18);
        DAI.approve(address(UNISWAP_V2), 2e18);
        // Mint extra tokens to wallet
        DAI.mint(address(SCW), 1e18);
        // Set up calldata trying to swap 1 DAI more than unlocked balance
        address[] memory paths = new address[](2);
        paths[0] = address(DAI);
        paths[1] = address(USDT);
        bytes memory swapData = abi.encodeWithSelector(
            TestUniswapV2.swapExactTokensForTokens.selector, 2e18, 2e18, paths, address(SCW), block.timestamp + 1000
        );
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(UNISWAP_V2), 0, swapData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(eoa, address(SCW), address(ECDSA_VALIDATOR), opCalldata);
        // Expect the HookMultiPlexer.SubHookPostCheckError error to be emitted
        // wrapped in UserOperationRevertReason event
        _revertUserOpEvent(
            hash, op.nonce, HMPL.SubHookPostCheckError.selector, abi.encode(address(CREDIBLE_ACCOUNT_HOOK))
        );
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // Test: Should return correct locked token balances
    function test_getLockedTokenBalances() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Get locked token balances
        TokenData[] memory lockedBalances = CREDIBLE_ACCOUNT_VALIDATOR.getLockedTokenBalances(address(SCW));
        // Verify the balances
        assertEq(lockedBalances.length, 3, "Should have 3 locked tokens");
        assertEq(lockedBalances[0].token, tokens[0], "First token should be USDC");
        assertEq(lockedBalances[0].amount, amounts[0], "USDC amount should match");
        assertEq(lockedBalances[1].token, tokens[1], "Second token should be DAI");
        assertEq(lockedBalances[1].amount, amounts[1], "DAI amount should match");
        assertEq(lockedBalances[2].token, tokens[2], "Third token should be USDT");
        assertEq(lockedBalances[2].amount, amounts[2], "USDT amount should match");
        vm.stopPrank();
    }

    // Test: Should return correct locked balance for a specific token
    function test_getLockedBalance() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Get locked balance for USDC
        uint256 lockedBalance = CREDIBLE_ACCOUNT_VALIDATOR.getLockedBalance(address(SCW), address(USDC));
        // Verify the balance
        assertEq(lockedBalance, amounts[0], "USDC locked balance should match");
        vm.stopPrank();
    }

    // Test: Should return correct session locked token balances
    function test_getSessionLockedTokenBalances() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Get session locked token balances
        TokenData[] memory sessionLockedBalances =
            CREDIBLE_ACCOUNT_VALIDATOR.getSessionLockedTokenBalances(address(SCW), sessionKey.pub);
        // Verify the balances
        assertEq(sessionLockedBalances.length, 3, "Should have 3 locked tokens for session");
        assertEq(sessionLockedBalances[0].token, tokens[0], "First token should be USDC");
        assertEq(sessionLockedBalances[0].amount, amounts[0], "USDC amount should match");
        assertEq(sessionLockedBalances[1].token, tokens[1], "Second token should be DAI");
        assertEq(sessionLockedBalances[1].amount, amounts[1], "DAI amount should match");
        assertEq(sessionLockedBalances[2].token, tokens[2], "Third token should be USDT");
        assertEq(sessionLockedBalances[2].amount, amounts[2], "USDT amount should match");
        vm.stopPrank();
    }

    // Test: Should return correct session locked balance for a specific token
    function test_getSessionLockedBalance() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Get session locked balance for USDC
        uint256 sessionLockedBalance =
            CREDIBLE_ACCOUNT_VALIDATOR.getSessionLockedBalance(address(SCW), sessionKey.pub, address(USDC));
        // Verify the balance
        assertEq(sessionLockedBalance, amounts[0], "USDC session locked balance should match");
        vm.stopPrank();
    }

    // Test: Should return true for isSessionClaimed when all tokens are claimed
    function test_isSessionClaimed_True() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, SCW, amounts[0], amounts[1], amounts[2]);
        // Check if session is claimed
        assertTrue(
            CREDIBLE_ACCOUNT_VALIDATOR.isSessionClaimed(sessionKey.pub, address(SCW)), "Session should be claimed"
        );
        vm.stopPrank();
    }

    // Test: Should return false for isSessionClaimed when not all tokens are claimed
    function test_isSessionClaimed_False() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Check if session is claimed
        assertFalse(
            CREDIBLE_ACCOUNT_VALIDATOR.isSessionClaimed(sessionKey.pub, address(SCW)), "Session should not be claimed"
        );
        vm.stopPrank();
    }

    // Test: Should return true for isModuleType with validator type
    function test_isModuleType_Validator_True() public withRequiredModules {
        assertTrue(CREDIBLE_ACCOUNT_VALIDATOR.isModuleType(MODULE_TYPE_VALIDATOR), "Should be validator module type");
        vm.stopPrank();
    }

    // Test: Should return true for isModuleType with hook type for hook
    function test_isModuleType_Hook_True() public withRequiredModules {
        assertTrue(CREDIBLE_ACCOUNT_HOOK.isModuleType(MODULE_TYPE_HOOK), "Should be hook module type");
        vm.stopPrank();
    }

    // Test: Should remove tokens with zero balance from active tokens list
    function test_removeZeroBalanceTokens() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, SCW, amounts[0], amounts[1], amounts[2]);
        // Get locked token balances
        TokenData[] memory lockedBalances = CREDIBLE_ACCOUNT_VALIDATOR.getLockedTokenBalances(address(SCW));
        // Verify no tokens are returned since all have zero balance
        assertEq(lockedBalances.length, 0, "Should have 0 locked tokens after claiming all");
        vm.stopPrank();
    }

    // Test: Hook should revert transactions that would reduce token balance below locked amount
    function test_hook_RevertIf_BalanceBelowLocked() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Try to transfer more DAI than unlocked amount
        bytes memory daiData = _createTokenTransferExecution(alice.pub, 1);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute, (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(DAI), 0, daiData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(eoa, address(SCW), address(ECDSA_VALIDATOR), opCalldata);
        // Expect the hook to revert with insufficient unlocked balance
        _revertUserOpEvent(
            hash, op.nonce, HMPL.SubHookPostCheckError.selector, abi.encode(address(CREDIBLE_ACCOUNT_HOOK))
        );
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // Test: Hook should allow transactions that maintain sufficient token balance
    function test_hook_AllowSufficientBalance() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Mint extra DAI to wallet
        DAI.mint(address(SCW), 2e18);
        // Transfer DAI but keep enough for locked amount
        bytes memory daiData = _createTokenTransferExecution(alice.pub, 1e18);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute, (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(DAI), 0, daiData))
        );
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(eoa, address(SCW), address(ECDSA_VALIDATOR), opCalldata);
        // Execute the user operation - should succeed
        _executeUserOp(op);
        // Verify DAI was transferred - alice starting balance of 100 DAI
        assertEq(DAI.balanceOf(alice.pub), 1e18 + 100e18, "Alice should have received 1 DAI");
        // Verify wallet still has enough DAI for locked amount
        assertEq(DAI.balanceOf(address(SCW)), amounts[1] + 1e18, "Wallet should have locked amount + 1 DAI");
        vm.stopPrank();
    }

    function test_mustClaimFullLockedAmount() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(SCW));
        // Try to claim only part of the locked amount
        bytes memory usdcData = _createTokenTransferFromExecution(address(SCW), solver.pub, amounts[0] / 2);
        Execution[] memory batch = new Execution[](1);
        batch[0] = Execution({target: address(USDC), value: 0, callData: usdcData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));

        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(SCW), address(CREDIBLE_ACCOUNT_VALIDATOR), opCalldata);
        // Expect the operation to fail
        vm.expectRevert();
        _executeUserOp(op);
        vm.stopPrank();
    }
}
