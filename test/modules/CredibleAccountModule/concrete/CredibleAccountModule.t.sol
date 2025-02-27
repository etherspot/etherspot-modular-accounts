// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "ERC4337/core/Helpers.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {VALIDATION_FAILED, MODULE_TYPE_HOOK, MODULE_TYPE_VALIDATOR} from "ERC7579/interfaces/IERC7579Module.sol";
import {ExecutionLib} from "ERC7579/libs/ExecutionLib.sol";
import "ERC7579/libs/ModeLib.sol";
import {CredibleAccountModule as CAM} from "../../../../src/modules/validators/CredibleAccountModule.sol";
import {ICredibleAccountModule as ICAM} from "../../../../src/interfaces/ICredibleAccountModule.sol";
import {HookMultiPlexerLib as HMPL} from "../../../../src/libraries/HookMultiPlexerLib.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import "../../../../src/common/Enums.sol";
import "../../../../src/common/Structs.sol";
import {CredibleAccountModuleTestUtils as TestUtils} from "../utils/CredibleAccountModuleTestUtils.sol";
import {TestWETH} from "../../../../src/test/TestWETH.sol";
import {TestUniswapV2} from "../../../../src/test/TestUniswapV2.sol";
import "../../../../src/utils/ERC4337Utils.sol";

using ERC4337Utils for IEntryPoint;

contract CredibleAccountModule_Concrete_Test is TestUtils {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CredibleAccountModule_ModuleInstalled(address wallet);
    event CredibleAccountModule_ModuleUninstalled(address wallet);
    event CredibleAccountModule_SessionKeyEnabled(address sessionKey, address wallet);
    event CredibleAccountModule_SessionKeyDisabled(address sessionKey, address wallet);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testSetup();
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    // Test: Verify that the CredibleAccountModule module can be installed
    // as both validator and hook modules
    function test_installModule() public withRequiredModules {
        // Verify that the module is installed
        assertTrue(scw.isModuleInstalled(1, address(cam), "CredibleAccountModule module should be installed"));
        assertEq(scw.getActiveHook(), address(hmp), "Active hook should be HookMultiPlexer");
        assertEq(hmp.getHooks(address(scw))[0], address(cam));
    }

    function test_uninstallCredibleAccountModule_Hook() public withRequiredModules {
        // Verify that the hook is installed
        assertEq(hmp.getHooks(address(scw))[0], address(cam));
        // Uninstall the HookMultiplexer
        _uninstallModule(eoa.pub, scw, MODULE_TYPE_HOOK, address(hmp), hex"");
        assertEq(scw.getActiveHook(), address(0), "Active hook should be Zero Address");
    }

    function test_onInstall_Validator_ViaUserOp_Single() public withRequiredModules {
        bytes memory installData = abi.encodeWithSelector(
            ModularEtherspotWallet.installModule.selector, uint256(1), address(cam), abi.encode(MODULE_TYPE_VALIDATOR)
        );
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(scw), 0, installData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(eoa, address(scw), address(moecdsav), opCalldata);
        // Execute the user operation
        _executeUserOp(op);
        // Verify
        assertTrue(scw.isModuleInstalled(1, address(cam), "CredibleAccountModule module should be installed"));
        vm.stopPrank();
    }

    function test_onInstall_CredibleAccountModuleAsHook() public {
        _testSetup();
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(moecdsav), hex"");
        _installHookViaMultiplexer(scw, address(cam), HookType.GLOBAL);
        assertEq(hmp.getHooks(address(scw))[0], address(cam));
    }

    function test_onInstall_ValidatorAndHook_ViaUserOp_Batch() public {
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(moecdsav), hex"");
        vm.startPrank(address(scw));
        Execution[] memory batch = new Execution[](2);
        batch[0] = Execution({
            target: address(hmp),
            value: 0,
            callData: abi.encodeWithSelector(hmp.addHook.selector, address(cam), HookType.GLOBAL)
        });
        batch[1] = Execution({
            target: address(scw),
            value: 0,
            callData: abi.encodeWithSelector(
                ModularEtherspotWallet.installModule.selector, uint256(1), address(cam), abi.encode(MODULE_TYPE_VALIDATOR)
            )
        });
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) = _createUserOpWithSignature(eoa, address(scw), address(moecdsav), opCalldata);
        // Execute the user operation
        _executeUserOp(op);
        // Verify that the module is installed
        assertTrue(scw.isModuleInstalled(1, address(cam), "CredibleAccountModule module should be installed"));
        assertEq(hmp.getHooks(address(scw))[0], address(cam));
        vm.stopPrank();
    }

    // Test: Verify that the CredibleAccountModule validator can be uninstalled
    // when all locked tokens have been claimed by the solver
    function test_uninstallModule_Validator_AllLockedTokensClaimed() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, scw, amounts[0], amounts[1], amounts[2]);
        vm.stopPrank();
        // Expect the uninstallation event to be emitted
        vm.expectEmit(false, false, false, true);
        emit CredibleAccountModule_ModuleUninstalled(address(scw));
        // Execute the uninstallation
        _uninstallModule(
            eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(cam), abi.encode(MODULE_TYPE_VALIDATOR, address(scw))
        );
        // Verify that the module is uninstalled
        assertFalse(scw.isModuleInstalled(1, address(cam), "CredibleAccountModule validator should not be installed"));
    }

    // Test: Verify that the CredibleAccountModule validator cannot be uninstalled
    // if locked tokens have not been claimed by the solver
    function test_uninstallModule_Validator_RevertWhen_LockedTokensNotClaimed() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Get previous validator in linked list
        address prevValidator = _getPrevValidator(scw, address(cam));
        _toRevert(CAM.CredibleAccountModule_LockedTokensNotClaimed.selector, abi.encode(sessionKey.pub));
        // Done this way to capture the revert message
        scw.uninstallModule(1, address(cam), abi.encode(prevValidator, abi.encode(MODULE_TYPE_VALIDATOR, address(scw))));
        assertTrue(scw.isModuleInstalled(1, address(cam), "CredibleAccountModule validator should be installed"));
        vm.stopPrank();
    }

    // Test: Verify that the CredibleAccountModule hook can be uninstalled
    // when all locked tokens have been claimed by the solver
    // and validator is uninstalled
    function test_uninstallModule_Hook_AllLockedTokensClaimed() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, scw, amounts[0], amounts[1], amounts[2]);
        vm.stopPrank();
        // Uninstall the validator module first
        vm.expectEmit(true, true, false, false);
        emit ICAM.CredibleAccountModule_ModuleUninstalled(address(scw));
        _uninstallModule(
            eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(cam), abi.encode(MODULE_TYPE_VALIDATOR, address(scw))
        );
        // Remove the hook from the multiplexer
        _uninstallHookViaMultiplexer(scw, address(cam), HookType.GLOBAL);
        assertEq(scw.getActiveHook(), address(hmp), "HookMultiPlexer should be active hook");
        // Verify wallet has no hooks installed via multiplexer
        assertEq(hmp.getHooks(address(scw)).length, 0);
    }

    // Test: Verify that the CredibleAccountModule hook can be uninstalled
    // when tokens partially claimed but session key has expired
    // and validator is uninstalled first
    function test_uninstallModule_Hook_SessionKeyExpired() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Warp to after session key expiration
        vm.warp(validUntil + 1);
        // Uninstall the validator module first
        vm.stopPrank();
        vm.expectEmit(true, true, false, false);
        emit ICAM.CredibleAccountModule_ModuleUninstalled(address(scw));
        _uninstallModule(
            eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(cam), abi.encode(MODULE_TYPE_VALIDATOR, address(scw))
        );
        // Remove the hook from the multiplexer
        _uninstallHookViaMultiplexer(scw, address(cam), HookType.GLOBAL);
        // Verify wallet has no hooks installed via multiplexer
        assertEq(hmp.getHooks(address(scw)).length, 0);
    }

    // Test: Verify that the CredibleAccountModule hook cannot be uninstalled
    // when validator is not uninstalled first
    function test_uninstallModule_Hook_RevertWhen_ValidatorIsInstalled() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Try to remove the hook from the multiplexer
        _toRevert(CAM.CredibleAccountModule_ValidatorExists.selector, hex"");
        vm.stopPrank();
        _uninstallHookViaMultiplexer(scw, address(cam), HookType.GLOBAL);
        // Verify that the hook is installed via the multiplexer for the wallet
        assertEq(hmp.getHooks(address(scw)).length, 1);
        assertEq(hmp.getHooks(address(scw))[0], address(cam));
    }

    // Test: Verify that a session key can be enabled
    function test_enableSessionKey() public withRequiredModules {
        vm.expectEmit(true, true, false, false);
        emit ICAM.CredibleAccountModule_SessionKeyEnabled(sessionKey.pub, address(scw));
        // Enable session key
        _enableSessionKey(address(scw));
        // Verify that the session key is enabled
        assertEq(cam.getSessionKeysByWallet().length, 1, "Session key should be enabled");
        // Verify SessionData
        SessionData memory sessionData = cam.getSessionKeyData(sessionKey.pub);
        assertEq(sessionData.validUntil, validUntil, "validUntil does not match expected");
        assertEq(sessionData.validAfter, validAfter, "validAfter does not match expected");
        // Verify LockedToken data for session key
        ICAM.LockedToken[] memory lockedTokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
        assertEq(lockedTokens.length, 3, "Number of locked tokens does not match expected");
        assertEq(lockedTokens[0].token, tokens[0], "The first locked token address does not match expected");
        assertEq(
            lockedTokens[0].lockedAmount, amounts[0], "The first locked token locked amount does not match expected"
        );
        assertEq(lockedTokens[0].claimedAmount, 0, "The first locked token claimed amount does not match expected");
        assertEq(lockedTokens[1].token, tokens[1], "The second locked token address does not match expected");
        assertEq(
            lockedTokens[1].lockedAmount, amounts[1], "The second locked token locked amount does not match expected"
        );
        assertEq(lockedTokens[1].claimedAmount, 0, "The second locked token claimed amount does not match expected");
        assertEq(lockedTokens[2].token, tokens[2], "The third locked token address does not match expected");
        assertEq(
            lockedTokens[2].lockedAmount, amounts[2], "The third locked token locked amount does not match expected"
        );
        assertEq(lockedTokens[2].claimedAmount, 0, "The third locked token claimed amount does not match expected");
    }

    // Test: Enabling a session key with an invalid session key should revert
    function test_enableSessionKey_RevertIf_InvalidSesionKey() public withRequiredModules {
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(scw),
                sessionKey: address(0),
                validAfter: validAfter,
                validUntil: validUntil,
                tokenData: tokenAmounts,
                nonce: 2
            })
        );
        // Attempt to enable the session key
        _toRevert(CAM.CredibleAccountModule_InvalidSessionKey.selector, hex"");
        cam.enableSessionKey(rl);
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
                smartWallet: address(scw),
                sessionKey: sessionKey.pub,
                validAfter: uint48(0),
                validUntil: validUntil,
                tokenData: tokenAmounts,
                nonce: 2
            })
        );
        // Attempt to enable the session key
        _toRevert(CAM.CredibleAccountModule_InvalidValidAfter.selector, hex"");
        cam.enableSessionKey(rl);
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
                smartWallet: address(scw),
                sessionKey: sessionKey.pub,
                validAfter: validAfter,
                validUntil: uint48(0),
                tokenData: tokenAmounts,
                nonce: 2
            })
        );
        // Attempt to enable the session key
        _toRevert(CAM.CredibleAccountModule_InvalidValidUntil.selector, abi.encode(0));
        cam.enableSessionKey(rl);
        // validUntil that is less than validAfter
        rl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(scw),
                sessionKey: sessionKey.pub,
                validAfter: validAfter,
                validUntil: validAfter - 1,
                tokenData: tokenAmounts,
                nonce: 2
            })
        );
        // Attempt to enable the session key
        _toRevert(CAM.CredibleAccountModule_InvalidValidUntil.selector, abi.encode(validAfter - 1));
        cam.enableSessionKey(rl);
        vm.stopPrank();
    }

    // Test: Verify that a session key can be disabled
    function test_disableSessionKey() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Claim tokens by solver
        _claimTokensBySolver(eoa, scw, amounts[0], amounts[1], amounts[2]);
        // Expect emit a session key disabled event
        vm.expectEmit(true, true, false, false);
        emit ICAM.CredibleAccountModule_SessionKeyDisabled(sessionKey.pub, address(scw));
        cam.disableSessionKey(sessionKey.pub);
        vm.stopPrank();
    }

    // Test: Verify that a session key can be disabled after it expires
    // regardless of whether tokens are locked
    function test_disableSessionKey_WithLockedTokens_AfterSessionExpires() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Warp to a time after the session key has expired
        vm.warp(validUntil + 1);
        // Expect emit a session key disabled event
        vm.expectEmit(true, true, false, false);
        emit ICAM.CredibleAccountModule_SessionKeyDisabled(sessionKey.pub, address(scw));
        cam.disableSessionKey(sessionKey.pub);
        vm.stopPrank();
    }

    // Test: Disabling a session key with an invalid session key should revert
    function test_disableSessionKey_RevertIf_InvalidSessionKey() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Claim tokens by solver
        _claimTokensBySolver(eoa, scw, amounts[0], amounts[1], amounts[2]);
        // Attempt to disable the session key
        _toRevert(CAM.CredibleAccountModule_SessionKeyDoesNotExist.selector, abi.encode(otherSessionKey.pub));
        cam.disableSessionKey(otherSessionKey.pub);
        vm.stopPrank();
    }

    // Test: Disabling a session key when tokens aren't claimed reverts
    function test_disableSessionKey_RevertIf_TokensNotClaimed() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Attempt to disable the session key
        _toRevert(CAM.CredibleAccountModule_LockedTokensNotClaimed.selector, abi.encode(sessionKey.pub));
        cam.disableSessionKey(sessionKey.pub);
        vm.stopPrank();
    }

    // Test: Should return all session kets associated with a wallet
    function test_getSessionKeysByWallet() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        address[] memory sessions = cam.getSessionKeysByWallet();
        assertEq(sessions.length, 1, "There should be one session key associated with wallet");
        assertEq(sessions[0], sessionKey.pub, "The associated session key should be the expected one");
        vm.stopPrank();
    }

    // Test: Should return correct session key data
    function test_getSessionKeyData() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        SessionData memory sessionData = cam.getSessionKeyData(sessionKey.pub);
        assertEq(sessionData.validAfter, validAfter, "validAfter should be the expected value");
        assertEq(sessionData.validUntil, validUntil, "validUntil should be the expected value");
        vm.stopPrank();
    }

    // Test: Should return default values for non-existant session key
    function test_getSessionKeyData_NonExistantSession_ReturnsDefaultValues() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        SessionData memory sessionData = cam.getSessionKeyData(otherSessionKey.pub);
        // All retrieved session data should be default values
        assertEq(sessionData.validAfter, 0, "validAfter should be default value");
        assertEq(sessionData.validUntil, 0, "validUntil should be  default value");
        vm.stopPrank();
    }

    // Test: Should return correct locked tokens for session key
    function test_getLockedTokensForSessionKey() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        ICAM.LockedToken[] memory lockedTokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
        assertEq(lockedTokens.length, 3, "Number of locked tokens does not match expected");
        assertEq(lockedTokens[0].token, tokens[0], "The first locked token address does not match expected");
        assertEq(
            lockedTokens[0].lockedAmount, amounts[0], "The first locked token locked amount does not match expected"
        );
        assertEq(lockedTokens[0].claimedAmount, 0, "The first locked token claimed amount does not match expected");
        assertEq(lockedTokens[1].token, tokens[1], "The second locked token address does not match expected");
        assertEq(
            lockedTokens[1].lockedAmount, amounts[1], "The second locked token locked amount does not match expected"
        );
        assertEq(lockedTokens[1].claimedAmount, 0, "The second locked token claimed amount does not match expected");
        assertEq(lockedTokens[2].token, tokens[2], "The third locked token address does not match expected");
        assertEq(
            lockedTokens[2].lockedAmount, amounts[2], "The third locked token locked amount does not match expected"
        );
        assertEq(lockedTokens[2].claimedAmount, 0, "The third locked token claimed amount does not match expected");
        vm.stopPrank();
    }

    // Test: Should return cumulative locked balance for a token
    // over all wallet's session keys
    function test_tokenTotalLockedForWallet() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Enable another session key
        usdc.mint(address(scw), 10e6);
        TokenData[] memory newTokenData = new TokenData[](1);
        newTokenData[0] = TokenData(address(usdc), 10e6);
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(scw),
                sessionKey: otherSessionKey.pub,
                validAfter: validAfter,
                validUntil: validUntil,
                tokenData: newTokenData,
                nonce: 2
            })
        );
        cam.enableSessionKey(rl);
        uint256 totalUSDCLocked = cam.tokenTotalLockedForWallet(address(usdc));
        assertEq(
            totalUSDCLocked, amounts[0] + 10e6, "Expected USDC cumulative locked balance does not match expected amount"
        );
    }

    function test_cumulativeLockedForWallet() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Enable another session key
        uint256[4] memory newAmounts = [uint256(10e6), uint256(40e18), uint256(50e18), uint256(113e18)];
        usdc.mint(address(scw), newAmounts[0]);
        dai.mint(address(scw), newAmounts[1]);
        usdt.mint(address(scw), newAmounts[2]);
        vm.deal(address(scw), newAmounts[3]);
        weth.deposit{value: newAmounts[3]}();
        TokenData[] memory newTokenData = new TokenData[](tokens.length + 1);
        for (uint256 i; i < 3; ++i) {
            newTokenData[i] = TokenData(tokens[i], newAmounts[i]);
        }
        // Append WETH lock onto newTokenData
        newTokenData[3] = TokenData(address(weth), newAmounts[3]);
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(scw),
                sessionKey: otherSessionKey.pub,
                validAfter: validAfter,
                validUntil: validUntil,
                tokenData: newTokenData,
                nonce: 2
            })
        );
        cam.enableSessionKey(rl);
        // Get cumulative locked funds for wallet
        TokenData[] memory data = cam.cumulativeLockedForWallet();
        // Verify retrieved data matches expected
        assertEq(data[0].token, address(usdc), "First token address does not match expected (expected USDC)");
        assertEq(
            data[0].amount, amounts[0] + newAmounts[0], "Cumulative USDC locked balance does not match expected amount"
        );
        assertEq(data[1].token, address(dai), "Second token address does not match expected (expected DAI)");
        assertEq(
            data[1].amount, amounts[1] + newAmounts[1], "Cumulative DAI locked balance does not match expected amount"
        );
        assertEq(data[2].token, address(usdt), "Third token address does not match expected (expected USDT)");
        assertEq(
            data[2].amount, amounts[2] + newAmounts[2], "Cumulative USDT locked balance does not match expected amount"
        );
        assertEq(data[3].token, address(weth), "Fourth token address does not match expected (expected WETH)");
        assertEq(data[3].amount, newAmounts[3], "Cumulative WETH locked balance does not match expected amount");
        vm.stopPrank();
    }

    function test_enableSessionKey_ViaUserOp() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Enable another session key
        uint256[2] memory newAmounts = [uint256(10e6), uint256(40e18)];
        usdc.mint(address(scw), newAmounts[0]);
        dai.mint(address(scw), newAmounts[1]);
        vm.deal(address(scw), uint256(113e18));
        TokenData[] memory newTokenData = new TokenData[](tokens.length + 1);
        for (uint256 i; i < 2; ++i) {
            newTokenData[i] = TokenData(tokens[i], newAmounts[i]);
        }
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(scw),
                sessionKey: otherSessionKey.pub,
                validAfter: validAfter,
                validUntil: validUntil,
                tokenData: newTokenData,
                nonce: 2
            })
        );
        bytes memory enableSessionKeyData = abi.encodeWithSelector(CAM.enableSessionKey.selector, rl);
        TokenData[] memory newTokenData2 = new TokenData[](tokens.length + 1);
        newTokenData2[0] = TokenData(0xa0Cb889707d426A7A386870A03bc70d1b0697598, uint256(10000000)); // USDC
        newTokenData2[1] = TokenData(0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9, uint256(40000000000000000000)); // DAI
        // Encode the session data
        bytes memory newRl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(scw),
                sessionKey: 0xB071527c3721215A46958d172A42E7E3BDd1DF46,
                validAfter: uint48(1729743735),
                validUntil: uint48(1729744025),
                tokenData: newTokenData2,
                nonce: 3
            })
        );
        // Encode the function call data with the function selector and the encoded session data
        bytes memory enableSessionKeyData2 = abi.encodeWithSelector(CAM.enableSessionKey.selector, newRl);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );
        (PackedUserOperation memory op,) = _createUserOpWithSignature(eoa, address(scw), address(moecdsav), opCalldata);
        // Execute the user operation
        _executeUserOp(op);
        // Get cumulative locked funds for wallet
        TokenData[] memory data = cam.cumulativeLockedForWallet();
        // Verify retrieved data matches expected
        assertEq(data[0].token, address(usdc), "First token address does not match expected (expected USDC)");
        assertEq(
            data[0].amount, amounts[0] + newAmounts[0], "Cumulative USDC locked balance does not match expected amount"
        );
        assertEq(data[1].token, address(dai), "Second token address does not match expected (expected DAI)");
        assertEq(
            data[1].amount, amounts[1] + newAmounts[1], "Cumulative DAI locked balance does not match expected amount"
        );
        vm.stopPrank();
    }

    // Test: Claimed session should return true
    function test_isSessionClaimed_True() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, scw, amounts[0], amounts[1], amounts[2]);
        assertTrue(cam.isSessionClaimed(sessionKey.pub));
        vm.stopPrank();
    }

    // Test: Unclaimed session should return false
    function test_isSessionClaimed_False() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        assertFalse(cam.isSessionClaimed(sessionKey.pub));
        vm.stopPrank();
    }

    // Test: Should return true on validator
    function test_isModuleType_Validator_True() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        assertTrue(cam.isModuleType(1));
        vm.stopPrank();
    }

    // Test: Should return true on hook
    function test_isModuleType_Hook_True() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        assertTrue(cam.isModuleType(4));
        vm.stopPrank();
    }

    // Test: Should always revert
    function test_isValidSignatureWithSender() public withRequiredModules {
        _toRevert(CAM.NotImplemented.selector, hex"");
        cam.isValidSignatureWithSender(eoa.pub, bytes32(0), hex"");
        vm.stopPrank();
    }

    // Test: claiming all tokens (batch)
    function test_claimingTokens_Batch() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, scw, amounts[0], amounts[1], amounts[2]);
        // Check tokens are unlocked
        assertTrue(cam.isSessionClaimed(sessionKey.pub));
        vm.stopPrank();
    }

    // Test: claiming tokens with an amount
    // that exceeds the locked amount fails (batch)
    function test_claimingTokens_Batch_RevertIf_ClaimExceedsLocked() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Set up calldata batch
        bytes memory usdcData = _createTokenTransferFromExecution(address(scw), solver.pub, amounts[0]);
        bytes memory daiData = _createTokenTransferFromExecution(address(scw), solver.pub, amounts[1]);
        bytes memory usdtData = _createTokenTransferFromExecution(address(scw), solver.pub, amounts[2] + 1);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(usdc), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(dai), value: 0, callData: daiData});
        batch[2] = Execution({target: address(usdt), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);
        // Expect the operation to revert due to signature error
        // (claiming exceeds locked)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // Test: Should revert if the session key is expired
    // no tokens claimed yet
    // and solver tried to claim tokens
    function test_claimingTokens_Batch_RevertIf_SessionKeyExpired() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Warp time to expire the session key
        vm.warp(validUntil + 1);
        // Claim tokens by solver
        bytes memory usdcData = _createTokenTransferFromExecution(address(scw), solver.pub, amounts[0]);
        bytes memory daiData = _createTokenTransferFromExecution(address(scw), solver.pub, amounts[1]);
        bytes memory usdtData = _createTokenTransferFromExecution(address(scw), solver.pub, amounts[2]);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(usdc), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(dai), value: 0, callData: daiData});
        batch[2] = Execution({target: address(usdt), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);
        // Expect the operation to revert due to signature error (expired session)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, "AA22 expired or not due"));
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // Test: Should revert if claiming tokens by solver
    // that dont match locked amounts
    function test_claimingTokens_DoesNotMatchLockedAmounts() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Claim tokens by solver that dont match locked amounts
        bytes memory usdcData = _createTokenTransferFromExecution(address(scw), solver.pub, 1e6);
        bytes memory daiData = _createTokenTransferFromExecution(address(scw), solver.pub, 1e18);
        bytes memory usdtData = _createTokenTransferFromExecution(address(scw), solver.pub, 1e18);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(usdc), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(dai), value: 0, callData: daiData});
        batch[2] = Execution({target: address(usdt), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);
        // Expect the operation to revert due to signature error (invalid amounts)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // Test: ERC20 transaction using amount that exceeds the
    // available unlocked balance fails (single)
    function test_transactingLockedTokens_Single_RevertIf_NotEnoughUnlockedBalance() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Mint extra tokens to wallet
        dai.mint(address(scw), 1e18);
        // Set up calldata batch
        // Invalid transaction as only 1 ether unlocked
        bytes memory daiData = _createTokenTransferFromExecution(address(scw), alice.pub, 2e18);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute, (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(dai), 0, daiData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(eoa, address(scw), address(moecdsav), opCalldata);
        // Expect the HookMultiPlexer.SubHookPostCheckError error to be emitted
        // wrapped in UserOperationRevertReason event
        _revertUserOpEvent(hash, op.nonce, HMPL.SubHookPostCheckError.selector, abi.encode(address(cam)));
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // Test: ERC20 transaction using amount that exceeds the
    // available unlocked balance fails (batch)
    function test_transactingLockedTokens_Batch_RevertIf_OtherValidator() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Mint extra tokens to wallet
        usdc.mint(address(scw), 1e6);
        dai.mint(address(scw), 1e18);
        usdt.mint(address(scw), 1e18);
        // Set up calldata batch
        bytes memory usdcData = _createTokenTransferFromExecution(address(scw), solver.pub, 1e6);
        bytes memory daiData = _createTokenTransferFromExecution(address(scw), solver.pub, 1e18);
        // Invalid transaction as only 1 ether unlocked
        bytes memory usdtData = _createTokenTransferFromExecution(address(scw), solver.pub, 2e18);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(usdc), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(dai), value: 0, callData: daiData});
        batch[2] = Execution({target: address(usdt), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(eoa, address(scw), address(moecdsav), opCalldata);
        // Expect the HookMultiPlexer.SubHookPostCheckError error to be emitted
        // wrapped in UserOperationRevertReason event
        _revertUserOpEvent(hash, op.nonce, HMPL.SubHookPostCheckError.selector, abi.encode(address(cam)));
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
        _enableSessionKey(address(scw));
        usdt.mint(address(uniswapV2), 10e18);
        dai.approve(address(uniswapV2), 2e18);
        // Mint extra tokens to wallet
        dai.mint(address(scw), 1e18);
        // Set up calldata trying to swap 1 DAI more than unlocked balance
        address[] memory paths = new address[](2);
        paths[0] = address(dai);
        paths[1] = address(usdt);
        bytes memory swapData = abi.encodeWithSelector(
            TestUniswapV2.swapExactTokensForTokens.selector, 2e18, 2e18, paths, address(scw), block.timestamp + 1000
        );
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(uniswapV2), 0, swapData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(eoa, address(scw), address(moecdsav), opCalldata);
        // Expect the HookMultiPlexer.SubHookPostCheckError error to be emitted
        // wrapped in UserOperationRevertReason event
        _revertUserOpEvent(hash, op.nonce, HMPL.SubHookPostCheckError.selector, abi.encode(address(cam)));
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // /*//////////////////////////////////////////////////////////////
    //                        INTERNAL TESTING
    // //////////////////////////////////////////////////////////////*/

    // Test: Should return correct digested ERC20.transferFrom claim
    function test_exposed_digestClaim() public withRequiredModules {
        bytes memory data = _createTokenTransferFromExecution(address(scw), alice.pub, amounts[0]);
        (bytes4 selector, address from, address to, uint256 amount) = harness.exposed_digestClaimTx(data);
        assertEq(selector, IERC20.transferFrom.selector);
        assertEq(from, address(scw));
        assertEq(to, alice.pub);
        assertEq(amount, amounts[0]);
        vm.stopPrank();
    }

    // Test: Should return blank information for non-ERC20.transfer claims
    function test_exposed_digestClaim_nonTransferFrom() public withRequiredModules {
        bytes memory data = _createTokenTransferExecution(alice.pub, amounts[0]);
        (bytes4 selector, address from, address to, uint256 amount) = harness.exposed_digestClaimTx(data);
        assertEq(selector, bytes4(0));
        assertEq(from, address(0));
        assertEq(to, address(0));
        assertEq(amount, 0);
        vm.stopPrank();
    }

    // Test: Should return correct signature digest
    function test_exposed_digestSignature() public {
        // Set up the test environment and enable a session key
        _testSetup();
        // Lock some tokens
        bytes memory rl = _createResourceLock(address(scw));
        harness.enableSessionKey(rl);
        // Prepare user operation data
        bytes memory data = _createTokenTransferFromExecution(address(scw), alice.pub, amounts[0]);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdc), uint256(0), data))
        );
        PackedUserOperation memory op = _createUserOp(address(scw), address(cam));
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        bytes memory expectedSig = _ethSign(hash, sessionKey);
        (op,) = _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);
        (bytes memory signature, bytes memory proof) = harness.exposed_digestSignature(op.signature);
        assertEq(signature, expectedSig, "signature should match");
        assertEq(proof.length, PROOF.length, "merkleProof should match");
        for (uint256 i; i < proof.length; ++i) {
            assertEq(proof[i], PROOF[i], "merkleProof should match");
        }
    }

    // Test: Retrieving locked balances
    function test_exposed_retrieveLockedBalance() public withRequiredModules {
        // Lock some tokens
        bytes memory rl = _createResourceLock(address(scw));
        harness.enableSessionKey(rl);
        // Lock same tokens again uder different session key
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], 1 wei);
        }
        bytes memory anotherRl = abi.encode(
            ResourceLock({
                chainId: 42161,
                smartWallet: address(scw),
                sessionKey: otherSessionKey.pub,
                validAfter: validAfter,
                validUntil: validUntil,
                tokenData: tokenAmounts,
                nonce: 2
            })
        );
        harness.enableSessionKey(anotherRl);
        // Verify both session keys enabled successfully
        assertEq(harness.getSessionKeysByWallet().length, 2, "Two sessions should be enabled successfully");
        // Retrieve the locked balances
        uint256 usdcLocked = harness.exposed_retrieveLockedBalance(address(scw), address(usdc));
        uint256 daiLocked = harness.exposed_retrieveLockedBalance(address(scw), address(dai));
        uint256 usdtLocked = harness.exposed_retrieveLockedBalance(address(scw), address(usdt));
        // Verify the locked balances
        assertEq(usdcLocked, amounts[0] + 1 wei, "USDC locked balance should match");
        assertEq(daiLocked, amounts[1] + 1 wei, "DAI locked balance should match");
        assertEq(usdtLocked, amounts[2] + 1 wei, "USDT locked balance should match");
    }

    // Test: Encoding state of all locked tokens for a wallet
    function test_exposed_cumulativeLockedForWallet() public withRequiredModules {
        // Lock some tokens
        bytes memory rl = _createResourceLock(address(scw));
        harness.enableSessionKey(rl);
        assertEq(harness.getSessionKeysByWallet()[0], sessionKey.pub, "Tokens should be locked successfully");
        // Call the exposed function
        TokenData[] memory initialBalances = harness.exposed_cumulativeLockedForWallet(address(scw));
        // Verify the encoded state
        assertEq(initialBalances.length, 3, "Should have 3 locked tokens");
        assertEq(initialBalances[0].token, address(usdc), "USDC should be first token");
        assertEq(initialBalances[0].amount, amounts[0], "Balance of USDC should be 100 USDC");
        assertEq(initialBalances[1].token, address(dai), "DAI should be first token");
        assertEq(initialBalances[1].amount, amounts[1], "Balance of DAI should be 200 DAI");
        assertEq(initialBalances[2].token, address(usdt), "USDT should be second token");
        assertEq(initialBalances[2].amount, amounts[2], "Balance of USDT should be 300 USDT");
    }
}
