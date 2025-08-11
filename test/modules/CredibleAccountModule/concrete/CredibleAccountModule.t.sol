// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "ERC4337/core/Helpers.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import "ERC7579/interfaces/IERC7579Module.sol";
import {ExecutionLib} from "ERC7579/libs/ExecutionLib.sol";
import "ERC7579/libs/ModeLib.sol";
import {CredibleAccountModule as CAM} from "../../../../src/modules/validators/CredibleAccountModule.sol";
import {ICredibleAccountModule} from "../../../../src/interfaces/ICredibleAccountModule.sol";
import {HookMultiPlexer as HMP} from "../../../../src/modules/hooks/HookMultiPlexer.sol";
import {HookMultiPlexerLib as HMPL} from "../../../../src/libraries/HookMultiPlexerLib.sol";
import {ResourceLockValidator} from "../../../../src/modules/validators/ResourceLockValidator.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import "../../../../src/common/Enums.sol";
import "../../../../src/common/Structs.sol";
import {CredibleAccountModuleTestUtils as TestUtils} from "../utils/CredibleAccountModuleTestUtils.sol";
import {TestWETH} from "../../../../src/test/TestWETH.sol";
import {TestUniswapV2} from "../../../../src/test/TestUniswapV2.sol";
import "../../../../src/utils/ERC4337Utils.sol";
import {BootstrapConfig, BootstrapUtil, Bootstrap} from "../../../../src/utils/Bootstrap.sol";
import {MockTarget} from "../../../../src/test/mocks/MockTarget.sol";

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

    function test_uninstallCredibleAccountModule_hook() public withRequiredModules {
        // Verify that the hook is installed
        assertEq(hmp.getHooks(address(scw))[0], address(cam));
        // Uninstall CredibleAccountManager as Validator first
        _uninstallModule(
            eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(cam), abi.encode(MODULE_TYPE_VALIDATOR, address(scw))
        );
        // Uninstall the HookMultiplexer
        _uninstallHookViaMultiplexer(scw, address(cam), HookType.GLOBAL);
        assertFalse(
            hmp.hasHook(address(scw), address(cam), HookType.GLOBAL), "CredibleAccountModule should be uninstalled"
        );
    }

    function test_uninstallHookMultiPlexer_shouldRevert() public withRequiredModules {
        // Verify that the hook is installed
        assertEq(hmp.getHooks(address(scw))[0], address(cam));
        // Uninstall the HookMultiplexer
        _toRevert(HMP.CannotUninstall.selector, hex"");
        _uninstallModule(eoa.pub, scw, MODULE_TYPE_HOOK, address(hmp), hex"");
        assertEq(scw.getActiveHook(), address(hmp), "Active hook should be Zero Address");
    }

    function test_onInstall_validator_viaUserOp_single() public withRequiredModules {
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

    function test_onInstall_credibleAccountModuleAsHook() public {
        _testSetup();
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(moecdsav), hex"");
        _installHookViaMultiplexer(scw, address(cam), HookType.GLOBAL);
        assertEq(hmp.getHooks(address(scw))[0], address(cam));
    }

    function test_onInstall_validatorAndHook_viaUserOp_batch() public {
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
    function test_uninstallModule_validator_allLockedTokensClaimed() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);
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
    function test_uninstallModule_validator_revertWhen_lockedTokensNotClaimed() public withRequiredModules {
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
    function test_uninstallModule_hook_allLockedTokensClaimed() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);
        vm.stopPrank();
        // Uninstall the validator module first
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.CredibleAccountModule_ModuleUninstalled(address(scw));
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
    function test_uninstallModule_hook_sessionKeyExpired() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Warp to after session key expiration
        vm.warp(validUntil + 1);
        // Uninstall the validator module first
        vm.stopPrank();
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.CredibleAccountModule_ModuleUninstalled(address(scw));
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
    function test_uninstallModule_hook_revertWhen_validatorIsInstalled() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Try to remove the hook from the multiplexer
        _toRevert(CAM.CredibleAccountModule_ValidatorMustBeUninstalledFirst.selector, hex"");
        vm.stopPrank();
        _uninstallHookViaMultiplexer(scw, address(cam), HookType.GLOBAL);
        // Verify that the hook is installed via the multiplexer for the wallet
        assertEq(hmp.getHooks(address(scw)).length, 1);
        assertEq(hmp.getHooks(address(scw))[0], address(cam));
    }

    // Test: Verify that a session key can be enabled
    function test_enableSessionKey() public withRequiredModules {
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.CredibleAccountModule_SessionKeyEnabled(sessionKey.pub, address(scw));
        // Enable session key
        _enableSessionKey(address(scw));
        // Verify that the session key is enabled
        assertEq(cam.getSessionKeysByWallet().length, 1, "Session key should be enabled");
        // Verify SessionData
        SessionData memory sessionData = cam.getSessionKeyData(sessionKey.pub);
        assertEq(sessionData.validUntil, validUntil, "validUntil does not match expected");
        assertEq(sessionData.validAfter, validAfter, "validAfter does not match expected");
        // Verify LockedToken data for session key
        ICredibleAccountModule.LockedToken[] memory lockedTokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
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
    function test_enableSessionKey_revertIf_invalidSesionKey() public withRequiredModules {
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: block.chainid,
                smartWallet: address(scw),
                sessionKey: address(0),
                validAfter: validAfter,
                validUntil: validUntil,
                solver: solver.pub,
                bidHash: DUMMY_BID_HASH,
                tokenData: tokenAmounts
            })
        );
        // Attempt to enable the session key
        _toRevert(CAM.CredibleAccountModule_InvalidSessionKey.selector, hex"");
        cam.enableSessionKey(rl);
        vm.stopPrank();
    }

    // Test: Enabling a session key with an invalid validAfter should revert
    function test_enableSessionKey_revertIf_invalidValidAfter() public withRequiredModules {
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: block.chainid,
                smartWallet: address(scw),
                sessionKey: sessionKey.pub,
                validAfter: uint48(0),
                validUntil: validUntil,
                solver: solver.pub,
                bidHash: DUMMY_BID_HASH,
                tokenData: tokenAmounts
            })
        );
        // Attempt to enable the session key
        _toRevert(CAM.CredibleAccountModule_InvalidValidAfter.selector, hex"");
        cam.enableSessionKey(rl);
        vm.stopPrank();
    }

    // Test: Enabling a session key with an invalid validUntil should revert
    function test_enableSessionKey_revertIf_invalidValidUntil() public withRequiredModules {
        // validUntil that is 0
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: block.chainid,
                smartWallet: address(scw),
                sessionKey: sessionKey.pub,
                validAfter: validAfter,
                validUntil: uint48(0),
                solver: solver.pub,
                bidHash: DUMMY_BID_HASH,
                tokenData: tokenAmounts
            })
        );
        // Attempt to enable the session key
        _toRevert(CAM.CredibleAccountModule_InvalidValidUntil.selector, abi.encode(0));
        cam.enableSessionKey(rl);
        // validUntil that is less than validAfter
        rl = abi.encode(
            ResourceLock({
                chainId: block.chainid,
                smartWallet: address(scw),
                sessionKey: sessionKey.pub,
                validAfter: validAfter,
                validUntil: validAfter - 1,
                solver: solver.pub,
                bidHash: DUMMY_BID_HASH,
                tokenData: tokenAmounts
            })
        );
        // Attempt to enable the session key
        _toRevert(CAM.CredibleAccountModule_InvalidValidUntil.selector, abi.encode(validAfter - 1));
        cam.enableSessionKey(rl);
        vm.stopPrank();
    }

    // Test: Enabling a session key with an invalid solver should revert
    function test_enableSessionKey_revertIf_invalidSolver() public withRequiredModules {
        // validUntil that is 0
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: block.chainid,
                smartWallet: address(scw),
                sessionKey: sessionKey.pub,
                validAfter: validAfter,
                validUntil: validUntil,
                solver: address(0),
                bidHash: DUMMY_BID_HASH,
                tokenData: tokenAmounts
            })
        );
        // Attempt to enable the session key
        _toRevert(CAM.CredibleAccountModule_InvalidSolver.selector, hex"");
        cam.enableSessionKey(rl);
        vm.stopPrank();
    }

    // Test: Verify that a session key can be disabled
    function test_disableSessionKey() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Claim tokens by solver
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);
        // Expect emit a session key disabled event
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.CredibleAccountModule_SessionKeyDisabled(sessionKey.pub, address(scw));
        cam.disableSessionKey(sessionKey.pub);
        vm.stopPrank();
    }

    // Test: Verify that a session key can be disabled after it expires
    // regardless of whether tokens are locked
    function test_disableSessionKey_withLockedTokens_afterSessionExpires() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Warp to a time after the session key has expired
        vm.warp(validUntil + 1);
        // Expect emit a session key disabled event
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.CredibleAccountModule_SessionKeyDisabled(sessionKey.pub, address(scw));
        cam.disableSessionKey(sessionKey.pub);
        vm.stopPrank();
    }

    // Test: Disabling a session key when tokens aren't claimed reverts
    function test_disableSessionKey_revertIf_tokensNotClaimed() public withRequiredModules {
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
    function test_getSessionKeyData_nonExistantSession_returnsDefaultValues() public withRequiredModules {
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
        ICredibleAccountModule.LockedToken[] memory lockedTokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
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

        // Use different bid hash to avoid consumed bid hash error
        bytes32 SECOND_BID_HASH = keccak256("second_bid_hash");
        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: otherSessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            solver: solver.pub,
            bidHash: SECOND_BID_HASH, // Different bid hash
            tokenData: newTokenData
        });

        bytes memory enableSessionKeyData = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl));

        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );

        // Create user operation with proper signature format
        (PackedUserOperation memory op, bytes32[] memory proof, bytes32 root) =
            _createUserOpWithResourceLock(address(scw), eoa, address(rlv), opCalldata, rl, true);

        bytes memory sig = _sign(root, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(root), _packProofForSignature(proof));

        // Fund the wallet with enough ETH for gas fees
        vm.deal(address(scw), 1 ether);

        // Execute the user operation
        _executeUserOp(op);

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
        vm.deal(address(scw), newAmounts[3] + 1 ether);
        weth.deposit{value: newAmounts[3]}();

        TokenData[] memory newTokenData = new TokenData[](tokens.length + 1);
        for (uint256 i; i < 3; ++i) {
            newTokenData[i] = TokenData(tokens[i], newAmounts[i]);
        }
        // Append WETH lock onto newTokenData
        newTokenData[3] = TokenData(address(weth), newAmounts[3]);

        // Add WETH as supported token on InvoiceManager
        vm.stopPrank();
        vm.prank(deployer.pub);
        im.addTokenToWhitelist(address(weth));

        vm.startPrank(address(scw));
        // Use different bid hash to avoid consumed bid hash error
        bytes32 SECOND_BID_HASH = keccak256("second_bid_hash");
        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: otherSessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            solver: solver.pub,
            bidHash: SECOND_BID_HASH, // Different bid hash
            tokenData: newTokenData
        });

        bytes memory enableSessionKeyData = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl));

        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );

        // Create user operation with proper signature format
        (PackedUserOperation memory op, bytes32[] memory proof, bytes32 root) =
            _createUserOpWithResourceLock(address(scw), eoa, address(rlv), opCalldata, rl, true);

        bytes memory sig = _sign(root, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(root), _packProofForSignature(proof));

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
        assertEq(data[2].token, address(usdt), "Third token address does not match expected (expected USDT)");
        assertEq(
            data[2].amount, amounts[2] + newAmounts[2], "Cumulative USDT locked balance does not match expected amount"
        );
        assertEq(data[3].token, address(weth), "Fourth token address does not match expected (expected WETH)");
        assertEq(data[3].amount, newAmounts[3], "Cumulative WETH locked balance does not match expected amount");

        vm.stopPrank();
    }

    function test_enableSessionKey_viaUserOp() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Enable another session key
        uint256[2] memory newAmounts = [uint256(10e6), uint256(40e18)];
        usdc.mint(address(scw), newAmounts[0]);
        dai.mint(address(scw), newAmounts[1]);
        vm.deal(address(scw), uint256(113e18));
        TokenData[] memory newTokenData = new TokenData[](2);
        for (uint256 i; i < 2; ++i) {
            newTokenData[i] = TokenData(tokens[i], newAmounts[i]);
        }
        bytes32 SECOND_BID_HASH = keccak256("second_bid_hash");
        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: otherSessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            solver: solver.pub,
            bidHash: SECOND_BID_HASH,
            tokenData: newTokenData
        });
        bytes memory enableSessionKeyData = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );
        (PackedUserOperation memory op, bytes32[] memory proof, bytes32 root) =
            _createUserOpWithResourceLock(address(scw), eoa, address(rlv), opCalldata, rl, true);
        bytes memory sig = _sign(root, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(root), _packProofForSignature(proof));
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
    function test_isSessionClaimed_true() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);
        assertTrue(cam.isSessionClaimed(sessionKey.pub));
        vm.stopPrank();
    }

    // Test: Unclaimed session should return false
    function test_isSessionClaimed_false() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        assertFalse(cam.isSessionClaimed(sessionKey.pub));
        vm.stopPrank();
    }

    // Test: Should return true on validator
    function test_isModuleType_validator_true() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        assertTrue(cam.isModuleType(1));
        vm.stopPrank();
    }

    // Test: Should return true on hook
    function test_isModuleType_hook_true() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        assertTrue(cam.isModuleType(4));
        vm.stopPrank();
    }

    // Test: isValidSignatureWithSender should return success for valid signature
    function test_isValidSignatureWithSender_validSignature() public {
        // Create a test hash to sign
        bytes32 testHash = keccak256("test message");
        // Sign the hash with sessionKey
        bytes memory signature = _ethSign(testHash, sessionKey);
        // Call isValidSignatureWithSender
        bytes4 result = cam.isValidSignatureWithSender(sessionKey.pub, testHash, signature);
        // Should return ERC1271 success value
        assertEq(result, bytes4(0x1626ba7e), "Should return ERC1271 success value for valid signature");
    }

    // Test: isValidSignatureWithSender should fail when signer doesn't match sender
    function test_isValidSignatureWithSender_revertWhen_signerMismatch() public {
        // Create a test hash to sign
        bytes32 testHash = keccak256("test message");
        bytes memory signature = _ethSign(testHash, alice);
        // Call isValidSignatureWithSender
        bytes4 result = cam.isValidSignatureWithSender(sessionKey.pub, testHash, signature);
        // Should return failure value
        assertEq(result, bytes4(0xffffffff), "Should return failure value when signer doesn't match sender");
    }

    // Test: claiming all tokens (batch)
    function test_claimingTokens_batch() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);
        // Check tokens are unlocked
        assertTrue(cam.isSessionClaimed(sessionKey.pub));
        vm.stopPrank();
    }

    // Test: claiming tokens with an amount
    // that exceeds the locked amount fails (batch)
    function test_claimingTokens_batch_revertIf_claimExceedsLocked() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Set up calldata batch
        bytes memory usdcData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory daiData = _createClaimExecution(sessionKey.pub, address(dai), amounts[1]);
        bytes memory usdtData = _createClaimExecution(sessionKey.pub, address(usdt), amounts[2] + 1);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(cam), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(cam), value: 0, callData: daiData});
        batch[2] = Execution({target: address(cam), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);
        // Expect the operation to revert due to invalid amounts
        _revertUserOpEvent(hash, op.nonce, CAM.CredibleAccountModule_InvalidAmount.selector, hex"");
        // Attempt to execute the user operation
        _executeUserOp(op);
        // Verify NO tokens were claimed (all reverted):
        ICredibleAccountModule.LockedToken[] memory tokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
        assertEq(tokens[0].claimedAmount, 0, "USDC should not be claimed");
        assertEq(tokens[1].claimedAmount, 0, "DAI should not be claimed");
        assertEq(tokens[2].claimedAmount, 0, "USDT should not be claimed");

        // Verify NO tokens were transferred:
        assertEq(usdc.balanceOf(address(im)), 0, "No USDC should be transferred");
        assertEq(dai.balanceOf(address(im)), 0, "No DAI should be transferred");
        vm.stopPrank();
    }

    // Test: Should revert if the session key is expired
    // no tokens claimed yet
    // and solver tried to claim tokens
    function test_claimingTokens_batch_revertIf_sessionKeyExpired() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Warp time to expire the session key
        vm.warp(validUntil + 1);
        // Claim tokens by solver
        bytes memory usdcData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory daiData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[1]);
        bytes memory usdtData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[2]);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(cam), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(cam), value: 0, callData: daiData});
        batch[2] = Execution({target: address(cam), value: 0, callData: usdtData});
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
    function test_claimingTokens_batch_revertIf_doesNotMatchLockedAmounts() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Claim tokens by solver that dont match locked amounts
        bytes memory usdcData = _createClaimExecution(sessionKey.pub, address(usdc), 1e6);
        bytes memory daiData = _createClaimExecution(sessionKey.pub, address(dai), 1e18);
        bytes memory usdtData = _createClaimExecution(sessionKey.pub, address(usdt), 1e18);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(cam), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(cam), value: 0, callData: daiData});
        batch[2] = Execution({target: address(cam), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);
        // Expect the operation to revert due to invalid amounts
        _revertUserOpEvent(hash, op.nonce, CAM.CredibleAccountModule_InvalidAmount.selector, hex"");
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // Test: ERC20 transaction using amount that exceeds the
    // available unlocked balance fails (single)
    function test_transactingLockedTokens_single_revertIf_notEnoughUnlockedBalance() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Mint extra tokens to wallet
        dai.mint(address(scw), 1e18);
        // Set up calldata batch
        // Invalid transaction as only 1 ether unlocked
        bytes memory daiData = _createClaimExecution(sessionKey.pub, address(dai), 2e18);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute, (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, daiData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(eoa, address(scw), address(moecdsav), opCalldata);
        // Expect the HookMultiPlexer.SubHookPostCheckError error to be emitted
        // wrapped in UserOperationRevertReason event
        _revertUserOpEvent(hash, op.nonce, CAM.CredibleAccountModule_InvalidAmount.selector, hex"");
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // Test: ERC20 transaction using amount that exceeds the
    // available unlocked balance fails (batch)
    function test_transactingLockedTokens_batch_revertIf_notEnoughUnlockedBalance() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Mint extra tokens to wallet
        usdc.mint(address(scw), 1e6);
        dai.mint(address(scw), 1e18);
        usdt.mint(address(scw), 1e18);
        vm.startPrank(address(scw));
        usdc.approve(address(cam), amounts[0]);
        dai.approve(address(cam), amounts[1]);
        usdt.approve(address(cam), amounts[2]);
        vm.stopPrank();

        // Set up calldata batch
        bytes memory usdcData = _createClaimExecution(sessionKey.pub, address(usdc), 1e6);
        bytes memory daiData = _createClaimExecution(sessionKey.pub, address(dai), 1e18);
        // Invalid transaction as only 1 ether unlocked
        bytes memory usdtData = _createClaimExecution(sessionKey.pub, address(usdc), 1e18 + 1 wei);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(cam), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(cam), value: 0, callData: daiData});
        batch[2] = Execution({target: address(cam), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(eoa, address(scw), address(moecdsav), opCalldata);
        // Expect the HookMultiPlexer.SubHookPostCheckError error to be emitted
        // wrapped in UserOperationRevertReason event
        _revertUserOpEvent(hash, op.nonce, CAM.CredibleAccountModule_InvalidAmount.selector, hex"");
        // Attempt to execute the user operation
        _executeUserOp(op);
        vm.stopPrank();
    }

    // Test: Uniswap V2 swap transaction using amount that exceeds the
    // available unlocked balance fails (single)
    function test_transactingLockedTokens_complex_revertIf_notEnoughUnlockedBalance_singleExecute()
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

    /*//////////////////////////////////////////////////////////////
                        ROLE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    // Test: Grant SESSION_KEY_DISABLER role to an address
    function test_grantSessionKeyDisablerRole() public withRequiredModules {
        // Set up the test environment
        vm.stopPrank();
        vm.startPrank(deployer.pub);
        // Grant role to alice
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.SessionKeyDisablerRoleGranted(alice.pub, deployer.pub);
        cam.grantSessionKeyDisablerRole(alice.pub);
        // Verify alice has the role
        assertTrue(cam.hasSessionKeyDisablerRole(alice.pub), "Alice should have SESSION_KEY_DISABLER role");
    }

    // Test: Only admin can grant SESSION_KEY_DISABLER role
    function test_grantSessionKeyDisablerRole_revertWhen_notAdmin() public withRequiredModules {
        // Grant role to alice first
        vm.stopPrank();
        vm.startPrank(deployer.pub);
        cam.grantSessionKeyDisablerRole(alice.pub);
        vm.stopPrank();
        // Try to grant role from non-admin account
        vm.prank(alice.pub);
        vm.expectRevert();
        cam.grantSessionKeyDisablerRole(alice.pub);
    }

    // Test: Revoke SESSION_KEY_DISABLER role from an address
    function test_revokeSessionKeyDisablerRole() public withRequiredModules {
        vm.stopPrank();
        vm.startPrank(deployer.pub);
        // First grant role to alice
        cam.grantSessionKeyDisablerRole(alice.pub);
        // Verify alice has the role
        assertTrue(cam.hasSessionKeyDisablerRole(alice.pub), "Alice should have SESSION_KEY_DISABLER role");
        // Revoke role from alice
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.SessionKeyDisablerRoleRevoked(alice.pub, deployer.pub);
        cam.revokeSessionKeyDisablerRole(alice.pub);
        // Verify alice no longer has the role
        assertFalse(cam.hasSessionKeyDisablerRole(alice.pub), "Alice should not have SESSION_KEY_DISABLER role");
    }

    // Test: Only admin can revoke SESSION_KEY_DISABLER role
    function test_revokeSessionKeyDisablerRole_revertWhen_notAdmin() public withRequiredModules {
        // Grant role to alice first
        vm.stopPrank();
        vm.startPrank(deployer.pub);
        cam.grantSessionKeyDisablerRole(alice.pub);
        vm.stopPrank();
        // Try to revoke role from non-admin account
        vm.prank(alice.pub);
        vm.expectRevert();
        cam.revokeSessionKeyDisablerRole(alice.pub);
    }

    // Test: Get all addresses with SESSION_KEY_DISABLER role
    function test_getSessionKeyDisablers() public withRequiredModules {
        // Grant role to alice and another address
        vm.stopPrank();
        vm.startPrank(deployer.pub);
        cam.grantSessionKeyDisablerRole(alice.pub);
        cam.grantSessionKeyDisablerRole(bob.pub);
        vm.stopPrank();
        // Get all disablers
        address[] memory disablers = cam.getSessionKeyDisablers();
        // Should have 3 disablers (owner1, alice, bob)
        assertEq(disablers.length, 3, "Should have 3 session key disablers");
        // Check that all expected addresses are in the list
        bool foundOwner = false;
        bool foundAlice = false;
        bool foundBob = false;
        for (uint256 i; i < disablers.length; ++i) {
            if (disablers[i] == deployer.pub) foundOwner = true;
            if (disablers[i] == alice.pub) foundAlice = true;
            if (disablers[i] == bob.pub) foundBob = true;
        }
        assertTrue(foundOwner, "Owner should be in disablers list");
        assertTrue(foundAlice, "Alice should be in disablers list");
        assertTrue(foundBob, "Bob should be in disablers list");
    }

    // Test: Disable session key with SESSION_KEY_DISABLER role
    function test_disableSessionKey_withDisablerRole() public withRequiredModules {
        _enableSessionKey(address(scw));
        // Grant SESSION_KEY_DISABLER role to alice BEFORE claiming tokens
        vm.stopPrank();
        vm.prank(deployer.pub);
        cam.grantSessionKeyDisablerRole(alice.pub);
        // Verify session key exists and is active
        vm.startPrank(address(scw));
        SessionData memory sessionDataBefore = cam.getSessionKeyData(sessionKey.pub);
        assertGt(sessionDataBefore.validUntil, 0, "Session key should be active before test");
        // Alice should be able to disable the session key (with claimed tokens)
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);
        vm.stopPrank();
        vm.startPrank(alice.pub);
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.CredibleAccountModule_SessionKeyDisabled(sessionKey.pub, address(scw));
        cam.disableSessionKey(sessionKey.pub);
        SessionData memory finalSessionData = cam.getSessionKeyData(sessionKey.pub);
        assertEq(finalSessionData.validUntil, 0, "Session key should be disabled");
    }

    // Test: Wallet owner can still disable their own session keys
    function test_disableSessionKey_walletOwnerCanDisable() public withRequiredModules {
        _enableSessionKey(address(scw));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);
        // Wallet owner should be able to disable their own session key
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.CredibleAccountModule_SessionKeyDisabled(sessionKey.pub, address(scw));
        cam.disableSessionKey(sessionKey.pub);
        // Verify session key is disabled
        SessionData memory sessionData = cam.getSessionKeyData(sessionKey.pub);
        assertEq(sessionData.validUntil, 0, "Session key should be disabled");
    }

    // Test: Unauthorized user cannot disable session key
    function test_disableSessionKey_revertWhen_unauthorized() public withRequiredModules {
        _enableSessionKey(address(scw));
        // Claim all tokens by solver
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);
        // Unauthorized user should not be able to disable session key
        vm.stopPrank();
        vm.prank(alice.pub);
        _toRevert(CAM.CredibleAccountModule_UnauthorizedDisabler.selector, abi.encode(alice.pub));
        cam.disableSessionKey(sessionKey.pub);
    }

    // Test: Batch disable session keys
    function test_batchDisableSessionKeys() public withRequiredModules {
        // Enable multiple session keys
        _enableSessionKey(address(scw));

        // Enable another session key
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }

        // Use different bid hash to avoid consumed bid hash error
        bytes32 SECOND_BID_HASH = keccak256("second_bid_hash");
        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: otherSessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            solver: solver.pub,
            bidHash: SECOND_BID_HASH, // Different bid hash
            tokenData: tokenAmounts
        });

        bytes memory enableSessionKeyData = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl));

        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );

        // Create user operation with proper signature format
        (PackedUserOperation memory op, bytes32[] memory proof, bytes32 root) =
            _createUserOpWithResourceLock(address(scw), eoa, address(rlv), opCalldata, rl, true);

        bytes memory sig = _sign(root, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(root), _packProofForSignature(proof));

        // Fund the wallet with enough ETH for gas fees
        vm.deal(address(scw), 1 ether);

        // Execute the user operation
        _executeUserOp(op);

        // Claim all tokens for both session keys
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);

        // Batch disable session keys
        address[] memory sessionKeys = new address[](2);
        sessionKeys[0] = sessionKey.pub;
        sessionKeys[1] = otherSessionKey.pub;
        vm.stopPrank();
        vm.startPrank(deployer.pub);
        cam.batchDisableSessionKeys(sessionKeys);

        // Verify both session keys are disabled
        SessionData memory sessionData1 = cam.getSessionKeyData(sessionKeys[0]);
        SessionData memory sessionData2 = cam.getSessionKeyData(sessionKeys[1]);
        assertEq(sessionData1.validUntil, 0, "First session key should be disabled");
        assertEq(sessionData2.validUntil, 0, "Second session key should be disabled");
    }

    // Test: Only SESSION_KEY_DISABLER role can batch disable
    function test_batchDisableSessionKeys_revertWhen_unauthorized() public withRequiredModules {
        _enableSessionKey(address(scw));
        address[] memory sessionKeys = new address[](1);
        sessionKeys[0] = sessionKey.pub;
        // Unauthorized user should not be able to batch disable
        vm.stopPrank();
        vm.prank(alice.pub);
        vm.expectRevert();
        cam.batchDisableSessionKeys(sessionKeys);
    }

    // Test: Batch disable skips non-existent session keys
    function test_batchDisableSessionKeys_skipsNonExistentKeys() public withRequiredModules {
        _enableSessionKey(address(scw));
        // Claim all tokens
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);
        // Create array with valid and invalid session keys
        address[] memory sessionKeys = new address[](2);
        sessionKeys[0] = sessionKey.pub; // Valid
        sessionKeys[1] = otherSessionKey.pub; // Invalid
        // Should not revert, just skip invalid keys
        vm.stopPrank();
        vm.startPrank(deployer.pub);
        cam.batchDisableSessionKeys(sessionKeys);
        // Verify valid session key is disabled
        SessionData memory sessionData = cam.getSessionKeyData(sessionKeys[0]);
        assertEq(sessionData.validUntil, 0, "Valid session key should be disabled");
    }

    // Test: Emergency disable session key
    function test_emergencyDisableSessionKey() public withRequiredModules {
        _enableSessionKey(address(scw));
        // Emergency disable should work even with locked tokens
        vm.stopPrank();
        vm.startPrank(deployer.pub);
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.CredibleAccountModule_SessionKeyDisabled(sessionKey.pub, address(scw));
        cam.emergencyDisableSessionKey(sessionKey.pub);
        // Verify session key is disabled
        SessionData memory sessionData = cam.getSessionKeyData(sessionKey.pub);
        assertEq(sessionData.validUntil, 0, "Session key should be disabled");
    }

    // Test: Only DEFAULT_ADMIN_ROLE can emergency disable
    function test_emergencyDisableSessionKey_revertWhen_notAdmin() public withRequiredModules {
        _enableSessionKey(address(scw));
        // Non-admin should not be able to emergency disable
        vm.stopPrank();
        vm.prank(alice.pub);
        vm.expectRevert();
        cam.emergencyDisableSessionKey(sessionKey.pub);
    }

    // Test: Emergency disable with non-existent session key
    function test_emergencyDisableSessionKey_revertWhen_nonExistentKey() public withRequiredModules {
        vm.stopPrank();
        _toRevert(CAM.CredibleAccountModule_SessionKeyDoesNotExist.selector, abi.encode(otherSessionKey.pub));
        vm.startPrank(deployer.pub);
        cam.emergencyDisableSessionKey(otherSessionKey.pub);
    }

    // Test: Session key to wallet mapping is populated correctly
    function test_sessionKeyToWallet_mapping() public withRequiredModules {
        _enableSessionKey(address(scw));
        // Verify mapping is populated
        address mappedWallet = cam.sessionKeyToWallet(sessionKey.pub);
        assertEq(mappedWallet, address(scw), "Session key should be mapped to correct wallet");
    }

    // Test: Multiple users with SESSION_KEY_DISABLER role can disable keys
    function test_multipleDisablers_canDisableKeys() public withRequiredModules {
        // Enable session keys for both wallets
        _enableSessionKey(address(scw));
        vm.stopPrank();

        // Create two different wallets with session keys
        ModularEtherspotWallet scw2 = _createSCW(alice.pub);
        _installModule(alice.pub, scw2, MODULE_TYPE_VALIDATOR, address(moecdsav), hex"");
        _installHookViaMultiplexer(scw2, address(cam), HookType.GLOBAL);
        _installModule(alice.pub, scw2, MODULE_TYPE_VALIDATOR, address(cam), abi.encode(MODULE_TYPE_VALIDATOR));
        _installModule(alice.pub, scw2, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(alice.pub));

        usdc.mint(address(scw2), amounts[0]);
        dai.mint(address(scw2), amounts[1]);
        usdt.mint(address(scw2), amounts[2]);
        vm.startPrank(address(scw2));
        usdc.approve(address(cam), amounts[0]);
        dai.approve(address(cam), amounts[1]);
        usdt.approve(address(cam), amounts[2]);
        vm.stopPrank();

        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }

        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw2),
            sessionKey: otherSessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            solver: solver.pub,
            bidHash: keccak256(abi.encodePacked("someBidHash", otherSessionKey.pub)),
            tokenData: tokenAmounts
        });

        bytes memory enableSessionKeyData = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );

        // Create user operation with proper signature format
        (PackedUserOperation memory op, bytes32[] memory proof, bytes32 root) =
            _createUserOpWithResourceLock(address(scw2), alice, address(rlv), opCalldata, rl, true);
        bytes memory sig = _sign(root, alice);
        op.signature = bytes.concat(sig, abi.encodePacked(root), _packProofForSignature(proof));

        // Fund the wallet with enough ETH for gas fees
        vm.deal(address(scw2), 1 ether);

        // Execute the user operation
        _executeUserOp(op);

        // Grant SESSION_KEY_DISABLER role to alice and bob
        vm.startPrank(deployer.pub);
        cam.grantSessionKeyDisablerRole(alice.pub);
        cam.grantSessionKeyDisablerRole(bob.pub);
        vm.stopPrank();

        // Claim tokens for both session keys to make them disableable
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);
        _claimTokensBySolver(alice, scw2, otherSessionKey, amounts[0], amounts[1], amounts[2]);

        // Alice disables first session key
        vm.prank(alice.pub);
        cam.disableSessionKey(sessionKey.pub);

        // Bob disables second session key
        vm.prank(bob.pub);
        cam.disableSessionKey(otherSessionKey.pub);

        // Verify both session keys are disabled by checking they no longer exist in the mapping
        assertEq(cam.sessionKeyToWallet(sessionKey.pub), address(0), "First session key should be disabled");
        assertEq(cam.sessionKeyToWallet(otherSessionKey.pub), address(0), "Second session key should be disabled");
    }

    // Test: Batch disable with mixed valid/expired/claimed session keys
    function test_batchDisableSessionKeys_mixedStates() public withRequiredModules {
        // Enable multiple session keys with different states
        _enableSessionKey(address(scw));

        // Mint enough tokens for all session keys
        usdc.mint(address(scw), amounts[0] * 3); // Mint 300 USDC more
        usdt.mint(address(scw), amounts[1] * 3); // Mint 300 USDT more
        dai.mint(address(scw), amounts[2] * 3); // Mint 300 WETH more

        // Enable second session key that will expire
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }

        // Use different bid hash to avoid consumed bid hash error
        bytes32 SECOND_BID_HASH = keccak256("second_bid_hash");
        ResourceLock memory rl2 = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: otherSessionKey.pub,
            validAfter: validAfter,
            validUntil: uint48(block.timestamp + 100), // Will expire soon
            solver: solver.pub,
            bidHash: SECOND_BID_HASH,
            tokenData: tokenAmounts
        });

        bytes memory enableSessionKeyData2 = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl2));

        bytes memory opCalldata2 = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData2))
        );

        // Create user operation with proper signature format
        (PackedUserOperation memory op2, bytes32[] memory proof2, bytes32 root2) =
            _createUserOpWithResourceLock(address(scw), eoa, address(rlv), opCalldata2, rl2, true);

        bytes memory sig2 = _sign(root2, eoa);
        op2.signature = bytes.concat(sig2, abi.encodePacked(root2), _packProofForSignature(proof2));

        // Fund the wallet with enough ETH for gas fees
        vm.deal(address(scw), 1 ether);

        // Execute the user operation
        _executeUserOp(op2);

        // Enable third session key
        User memory thirdSessionKey = _createUser("Third Session Key");

        // Use different bid hash to avoid consumed bid hash error
        bytes32 THIRD_BID_HASH = keccak256("third_bid_hash");
        ResourceLock memory rl3 = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: thirdSessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            solver: solver.pub,
            bidHash: THIRD_BID_HASH,
            tokenData: tokenAmounts
        });

        bytes memory enableSessionKeyData3 = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl3));

        bytes memory opCalldata3 = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData3))
        );

        // Create user operation with proper signature format
        (PackedUserOperation memory op3, bytes32[] memory proof3, bytes32 root3) =
            _createUserOpWithResourceLock(address(scw), eoa, address(rlv), opCalldata3, rl3, true);

        bytes memory sig3 = _sign(root3, eoa);
        op3.signature = bytes.concat(sig3, abi.encodePacked(root3), _packProofForSignature(proof3));

        // Fund the wallet with enough ETH for gas fees
        vm.deal(address(scw), 1 ether);

        // Execute the user operation
        _executeUserOp(op3);

        // Claim tokens for first session key only
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);

        // Warp time to expire second session key
        vm.warp(block.timestamp + 150);

        // Batch disable all session keys
        address[] memory sessionKeys = new address[](3);
        sessionKeys[0] = sessionKey.pub; // Claimed
        sessionKeys[1] = otherSessionKey.pub; // Expired
        sessionKeys[2] = thirdSessionKey.pub; // Still has locked tokens, not expired
        vm.stopPrank();
        vm.startPrank(deployer.pub);
        cam.batchDisableSessionKeys(sessionKeys);

        // Verify first two are disabled, third should remain
        SessionData memory sessionData1 = cam.getSessionKeyData(sessionKeys[0]);
        SessionData memory sessionData2 = cam.getSessionKeyData(sessionKeys[1]);
        SessionData memory sessionData3 = cam.getSessionKeyData(sessionKeys[2]);
        assertEq(sessionData1.validUntil, 0, "Claimed session key should be disabled");
        assertEq(sessionData2.validUntil, 0, "Expired session key should be disabled");
        assertEq(sessionData3.validUntil, 0, "Active session key should be disabled");
    }

    // Test: Role management events are emitted correctly
    function test_roleManagement_events() public withRequiredModules {
        vm.stopPrank();
        vm.startPrank(deployer.pub);
        // Test granting role emits event
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.SessionKeyDisablerRoleGranted(alice.pub, deployer.pub);
        cam.grantSessionKeyDisablerRole(alice.pub);
        // Test revoking role emits event
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.SessionKeyDisablerRoleRevoked(alice.pub, deployer.pub);
        cam.revokeSessionKeyDisablerRole(alice.pub);
    }

    // Test: supportsInterface includes AccessControlEnumerable
    function test_supportsInterface_includesAccessControlEnumerable() public withRequiredModules {
        // Check that contract supports AccessControlEnumerable interface
        bytes4 accessControlEnumerableInterface = type(IAccessControlEnumerable).interfaceId;
        assertTrue(
            cam.supportsInterface(accessControlEnumerableInterface),
            "Contract should support IAccessControlEnumerable interface"
        );
    }

    // Test: Admin can transfer admin role
    function test_adminRoleTransfer() public withRequiredModules {
        vm.stopPrank();
        vm.startPrank(deployer.pub);
        // Grant admin role to alice
        cam.grantRole(cam.DEFAULT_ADMIN_ROLE(), alice.pub);
        // Alice should now be able to grant SESSION_KEY_DISABLER role
        vm.stopPrank();
        vm.prank(alice.pub);
        cam.grantSessionKeyDisablerRole(bob.pub);
        // Verify bob has the role
        assertTrue(cam.hasSessionKeyDisablerRole(bob.pub), "Bob should have SESSION_KEY_DISABLER role");
    }

    // Test: Emergency disable works even with locked tokens
    function test_emergencyDisableSessionKey_withLockedTokens() public withRequiredModules {
        _enableSessionKey(address(scw));
        // Verify session key has locked tokens
        ICredibleAccountModule.LockedToken[] memory lockedTokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
        assertGt(lockedTokens.length, 0, "Session key should have locked tokens");
        vm.stopPrank();
        vm.startPrank(deployer.pub);
        // Emergency disable should work even with locked tokens
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.CredibleAccountModule_SessionKeyDisabled(sessionKey.pub, address(scw));
        cam.emergencyDisableSessionKey(sessionKey.pub);

        // Verify session key is disabled
        SessionData memory sessionData = cam.getSessionKeyData(sessionKey.pub);
        assertEq(sessionData.validUntil, 0, "Session key should be disabled");
    }

    // Test: Session key mapping is cleaned up on disable
    function test_sessionKeyMapping_cleanedUpOnDisable() public withRequiredModules {
        _enableSessionKey(address(scw));
        // Verify mapping exists
        address mappedWallet = cam.sessionKeyToWallet(sessionKey.pub);
        assertEq(mappedWallet, address(scw), "Session key should be mapped to wallet");
        // Claim tokens and disable
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);
        cam.disableSessionKey(sessionKey.pub);
        // Verify mapping is cleaned up
        mappedWallet = cam.sessionKeyToWallet(sessionKey.pub);
        assertEq(mappedWallet, address(0), "Session key mapping should be cleared");
    }

    // Test: Get session key disablers when no additional roles granted
    function test_getSessionKeyDisablers_onlyDeployer() public withRequiredModules {
        // Should only have deployer (owner1)
        address[] memory disablers = cam.getSessionKeyDisablers();
        assertEq(disablers.length, 1, "Should have only one disabler");
        assertEq(disablers[0], deployer.pub, "Should be the deployer");
    }

    // Test: Disable session key works with different wallet contexts
    function test_disableSessionKey_differentWalletContexts() public withRequiredModules {
        // Enable session key from first wallet
        _enableSessionKey(address(scw));
        vm.stopPrank();

        // Create second wallet
        User memory differentOwner = _createUser("Different Owner");
        ModularEtherspotWallet scw2 = _createSCW(differentOwner.pub);
        _installModule(differentOwner.pub, scw2, MODULE_TYPE_VALIDATOR, address(moecdsav), hex"");
        _installHookViaMultiplexer(scw2, address(cam), HookType.GLOBAL);
        _installModule(differentOwner.pub, scw2, MODULE_TYPE_VALIDATOR, address(cam), abi.encode(MODULE_TYPE_VALIDATOR));
        _installModule(differentOwner.pub, scw2, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(differentOwner.pub));

        usdc.mint(address(scw2), amounts[0]);
        dai.mint(address(scw2), amounts[1]);
        usdt.mint(address(scw2), amounts[2]);
        vm.startPrank(address(scw2));
        usdc.approve(address(cam), amounts[0]);
        dai.approve(address(cam), amounts[1]);
        usdt.approve(address(cam), amounts[2]);
        vm.stopPrank();
        console.log("USDC balance of scw2:", usdc.balanceOf(address(scw2)));
        console.log("DAI balance of scw2:", dai.balanceOf(address(scw2)));
        console.log("USDT balance of scw2:", usdt.balanceOf(address(scw2)));

        // Enable session key from second wallet
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }

        // Use different bid hash to avoid consumed bid hash error
        bytes32 SECOND_WALLET_BID_HASH = keccak256("second_wallet_bid_hash");
        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw2),
            sessionKey: otherSessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            solver: solver.pub,
            bidHash: SECOND_WALLET_BID_HASH,
            tokenData: tokenAmounts
        });

        bytes memory enableSessionKeyData = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl));

        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );

        // Create user operation with proper signature format for second wallet
        (PackedUserOperation memory op, bytes32[] memory proof, bytes32 root) =
            _createUserOpWithResourceLock(address(scw2), differentOwner, address(rlv), opCalldata, rl, true);

        bytes memory sig = _sign(root, differentOwner);
        op.signature = bytes.concat(sig, abi.encodePacked(root), _packProofForSignature(proof));

        // Fund the second wallet with enough ETH for gas fees
        vm.deal(address(scw2), 1 ether);

        // Execute the user operation
        _executeUserOp(op);

        // Grant disabler role to alice
        vm.startPrank(deployer.pub);
        cam.grantSessionKeyDisablerRole(alice.pub);

        // Claim tokens for both session keys
        _claimTokensBySolver(eoa, scw, sessionKey, amounts[0], amounts[1], amounts[2]);
        console.log("scw address:", address(scw));
        console.log("scw2 address:", address(scw2));
        console.log("About to claim tokens for scw2...");
        _claimTokensBySolver(differentOwner, scw2, otherSessionKey, amounts[0], amounts[1], amounts[2]);

        // Alice should be able to disable both session keys
        vm.stopPrank();
        vm.startPrank(alice.pub);
        cam.disableSessionKey(sessionKey.pub);
        cam.disableSessionKey(otherSessionKey.pub);

        // Verify both are disabled
        SessionData memory sessionData1 = cam.getSessionKeyData(sessionKey.pub);
        SessionData memory sessionData2 = cam.getSessionKeyData(otherSessionKey.pub);
        assertEq(sessionData1.validUntil, 0, "First session key should be disabled");
        assertEq(sessionData2.validUntil, 0, "Second session key should be disabled");
    }

    // Test: claiming tokens with an amount
    // for a session key that has already been claimed
    function test_claimingTokens_batch_revertIf_alreadyClaimed() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Set up calldata batch
        bytes memory usdcData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory daiData = _createClaimExecution(sessionKey.pub, address(dai), amounts[1]);
        bytes memory usdtData = _createClaimExecution(sessionKey.pub, address(usdt), amounts[2]);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(cam), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(cam), value: 0, callData: daiData});
        batch[2] = Execution({target: address(cam), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);
        _executeUserOp(op);
        // Try and claim already claimed tokens again
        // Expect the operation to revert due to signature error
        // (claiming exceeds locked)
        (PackedUserOperation memory secondClaimOp, bytes32 hash) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);
        _revertUserOpEvent(
            hash,
            secondClaimOp.nonce,
            CAM.CredibleAccountModule_TokenAlreadyClaimed.selector,
            abi.encode(sessionKey.pub, address(usdc))
        );
        // Attempt to execute the user operation
        _executeUserOp(secondClaimOp);
        vm.stopPrank();
    }

    function test_claimingTokens_batch_asOrchestrator() public withRequiredModules {
        // Enable session key
        _enableSessionKey(address(scw));
        // Set up calldata batch
        User memory orchestrator = _createUser("Orchestrator");
        vm.startPrank(orchestrator.pub);
        bytes memory usdcData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory daiData = _createClaimExecution(sessionKey.pub, address(dai), amounts[1]);
        bytes memory usdtData = _createClaimExecution(sessionKey.pub, address(usdt), amounts[2]);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(cam), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(cam), value: 0, callData: daiData});
        batch[2] = Execution({target: address(cam), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);
        _executeUserOp(op);
        vm.stopPrank();
    }

    /// @notice Tests that enableSessionKey reverts when smartWallet doesn't match msg.sender
    /// @dev Verifies the CredibleAccountModule_InvalidWallet error is thrown for mismatched wallet addresses
    function test_enableSessionKey_revertIf_invalidWallet() public withRequiredModules {
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }

        // Create ResourceLock with different smartWallet address
        address wrongWallet = makeAddr("wrongWallet");
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: block.chainid,
                smartWallet: wrongWallet, // Different from msg.sender (scw)
                sessionKey: sessionKey.pub,
                validAfter: validAfter,
                validUntil: validUntil,
                solver: solver.pub,
                bidHash: DUMMY_BID_HASH,
                tokenData: tokenAmounts
            })
        );

        // Attempt to enable the session key - should revert
        _toRevert(CAM.CredibleAccountModule_InvalidWallet.selector, abi.encode(wrongWallet, address(scw)));
        cam.enableSessionKey(rl);
        vm.stopPrank();
    }

    /// @notice Tests that enableSessionKey reverts when session key already exists
    /// @dev Verifies the CredibleAccountModule_SessionKeyAlreadyExists error is thrown for duplicate session keys
    function test_enableSessionKey_revertIf_sessionKeyAlreadyExists() public withRequiredModules {
        // First, enable a session key successfully
        _enableSessionKey(address(scw));

        // Verify session key is enabled
        assertEq(cam.getSessionKeysByWallet().length, 1, "Session key should be enabled");

        // Try to enable the same session key again
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }

        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: block.chainid,
                smartWallet: address(scw),
                sessionKey: sessionKey.pub, // Same session key as before
                validAfter: validAfter,
                validUntil: validUntil,
                solver: solver.pub,
                bidHash: DUMMY_BID_HASH,
                tokenData: tokenAmounts
            })
        );

        // Attempt to enable the same session key again - should revert
        _toRevert(CAM.CredibleAccountModule_SessionKeyAlreadyExists.selector, abi.encode(sessionKey.pub));
        cam.enableSessionKey(rl);
        vm.stopPrank();
    }

    /// @notice Tests that enableSessionKey reverts when chainId doesn't match current chain
    /// @dev Verifies the CredibleAccountModule_InvalidChainId error is thrown for wrong chain ID
    function test_enableSessionKey_revertIf_invalidChainId() public withRequiredModules {
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }

        // Create ResourceLock with wrong chainId
        uint256 wrongChainId = block.chainid + 1;
        bytes memory rl = abi.encode(
            ResourceLock({
                chainId: wrongChainId, // Wrong chain ID
                smartWallet: address(scw),
                sessionKey: sessionKey.pub,
                validAfter: validAfter,
                validUntil: validUntil,
                solver: solver.pub,
                bidHash: DUMMY_BID_HASH,
                tokenData: tokenAmounts
            })
        );

        // Attempt to enable the session key - should revert
        _toRevert(CAM.CredibleAccountModule_InvalidChainId.selector, abi.encode(wrongChainId));
        cam.enableSessionKey(rl);
        vm.stopPrank();
    }

    /// @notice Tests that enableSessionKey succeeds when chainId is zero (wildcard)
    /// @dev Verifies that chainId = 0 is allowed as a wildcard for any chain
    function test_enableSessionKey_succeedsWhen_chainIdIsZero() public withRequiredModules {
        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }
        // Create ResourceLock with chainId = 0 (wildcard)
        ResourceLock memory rl = ResourceLock({
            chainId: 0, // Wildcard chain ID
            smartWallet: address(scw),
            sessionKey: sessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            solver: solver.pub,
            bidHash: DUMMY_BID_HASH,
            tokenData: tokenAmounts
        });
        bytes memory enableSessionKeyData = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl));
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );
        // Expect success event
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.CredibleAccountModule_SessionKeyEnabled(sessionKey.pub, address(scw));
        // Create user operation with proper signature format
        (PackedUserOperation memory op, bytes32[] memory proof, bytes32 root) =
            _createUserOpWithResourceLock(address(scw), eoa, address(rlv), opCalldata, rl, true);
        bytes memory sig = _sign(root, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(root), _packProofForSignature(proof));
        // Execute the user operation
        _executeUserOp(op);
        // Verify session key was enabled
        assertEq(cam.getSessionKeysByWallet().length, 1, "Session key should be enabled");
        vm.stopPrank();
    }

    /// @notice Tests that enableSessionKey reverts when token data exceeds maximum allowed
    /// @dev Verifies the CredibleAccountModule_MaxLockedTokensReached error is thrown for too many tokens
    function test_enableSessionKey_revertIf_maxLockedTokensReached() public withRequiredModules {
        // Create token data array that exceeds MAX_LOCKED_TOKENS (5)
        uint256 excessiveTokenCount = 6; // MAX_LOCKED_TOKENS is 5
        TokenData[] memory excessiveTokenAmounts = new TokenData[](excessiveTokenCount);
        for (uint256 i; i < excessiveTokenCount; ++i) {
            // Create dummy token addresses
            excessiveTokenAmounts[i] = TokenData(address(uint160(i + 1)), 100e18);
        }

        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: sessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            solver: solver.pub,
            bidHash: DUMMY_BID_HASH,
            tokenData: excessiveTokenAmounts // Too many tokens
        });

        bytes memory enableSessionKeyData = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl));

        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );

        // Create user operation with proper signature format
        (PackedUserOperation memory op, bytes32[] memory proof, bytes32 root) =
            _createUserOpWithResourceLock(address(scw), eoa, address(rlv), opCalldata, rl, true);

        bytes memory sig = _sign(root, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(root), _packProofForSignature(proof));

        // Fund the wallet with enough ETH for gas fees
        vm.deal(address(scw), 1 ether);

        // Attempt to enable the session key - should revert wrapped in UserOpEvent
        bytes32 hash = entrypoint.getUserOpHash(op);
        _revertUserOpEvent(
            hash, op.nonce, CAM.CredibleAccountModule_MaxLockedTokensReached.selector, abi.encode(sessionKey.pub)
        );
        _executeUserOp(op);
    }

    /// @notice Tests that enableSessionKey succeeds when token data equals maximum allowed
    /// @dev Verifies that exactly MAX_LOCKED_TOKENS is allowed
    function test_enableSessionKey_succeedsWhen_tokenDataEqualsMaximum() public withRequiredModules {
        // Create token data array that equals MAX_LOCKED_TOKENS (5)
        uint256 maxTokenCount = 5; // MAX_LOCKED_TOKENS is 5
        TokenData[] memory maxTokenAmounts = new TokenData[](maxTokenCount);
        for (uint256 i; i < maxTokenCount; ++i) {
            // Create dummy token addresses
            address newToken = address(uint160(i + 1));
            maxTokenAmounts[i] = TokenData(newToken, 100e18);
            // Add new token as whitelisted in InvoiceManager
            vm.stopPrank();
            vm.prank(deployer.pub);
            im.addTokenToWhitelist(newToken);
            vm.startPrank(address(scw));
        }

        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: sessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            solver: solver.pub,
            bidHash: DUMMY_BID_HASH,
            tokenData: maxTokenAmounts // Exactly MAX_LOCKED_TOKENS
        });

        bytes memory enableSessionKeyData = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(rl));

        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );

        // Expect success event
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.CredibleAccountModule_SessionKeyEnabled(sessionKey.pub, address(scw));

        // Create user operation with proper signature format
        (PackedUserOperation memory op, bytes32[] memory proof, bytes32 root) =
            _createUserOpWithResourceLock(address(scw), eoa, address(rlv), opCalldata, rl, true);

        bytes memory sig = _sign(root, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(root), _packProofForSignature(proof));

        // Execute the user operation
        _executeUserOp(op);

        // Verify session key was enabled
        assertEq(cam.getSessionKeysByWallet().length, 1, "Session key should be enabled");

        // Verify all tokens were locked
        ICredibleAccountModule.LockedToken[] memory lockedTokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
        assertEq(lockedTokens.length, maxTokenCount, "All tokens should be locked");

        vm.stopPrank();
    }

    /// @notice Tests that onUninstall reverts when sender mismatch occurs
    /// @dev Verifies the CredibleAccountModule_SenderMismatch error is thrown when sender != msg.sender and msg.sender != hookMultiPlexer
    function test_onUninstall_revertIf_senderMismatch() public withRequiredModules {
        // Setup: Install module first
        _enableSessionKey(address(scw));
        vm.stopPrank();
        // Create a different sender address (not the actual caller)
        address differentSender = makeAddr("differentSender");
        // Create uninstall data with different sender
        bytes memory uninstallData = abi.encode(MODULE_TYPE_VALIDATOR, differentSender);
        // Attempt to call onUninstall from scw (not hookMultiPlexer) with different sender
        // This should trigger: sender != msg.sender && msg.sender != address(hookMultiPlexer)
        vm.prank(address(scw));
        _toRevert(CAM.CredibleAccountModule_SenderMismatch.selector, abi.encode(differentSender, address(scw)));
        cam.onUninstall(uninstallData);
    }

    /// @notice Tests that validateUserOp reverts when validator module is not installed
    /// @dev Verifies the CredibleAccountModule_ModuleNotInstalled error is thrown when validator is not initialized
    function test_validateUserOp_RevertIf_ModuleNotInstalled() public {
        // Setup: Create a wallet but don't install the validator module
        address uninitializedWallet = makeAddr("uninitializedWallet");
        // Create a basic UserOp for the uninitialized wallet
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: uninitializedWallet,
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(abi.encodePacked(uint128(2000000), uint128(2000000))),
            preVerificationGas: 100000,
            gasFees: bytes32(abi.encodePacked(uint128(1000000000), uint128(1000000000))),
            paymasterAndData: "",
            signature: new bytes(65) // Valid length signature
        });
        bytes32 userOpHash = keccak256("dummy-hash");
        // Attempt to validate from uninitialized wallet - should revert
        vm.prank(uninitializedWallet);
        _toRevert(CAM.CredibleAccountModule_ModuleNotInstalled.selector, abi.encode(uninitializedWallet));
        cam.validateUserOp(userOp, userOpHash);
    }

    /// @notice Tests that validateUserOp reverts when msg.sender doesn't match userOp.sender
    /// @dev Verifies the CredibleAccountModule_InvalidCaller error is thrown for caller mismatch
    function test_validateUserOp_RevertIf_InvalidCaller() public withRequiredModules {
        // Setup: Install module and create session key
        _enableSessionKey(address(scw));
        vm.stopPrank();
        // Create a different wallet address
        address differentWallet = makeAddr("differentWallet");
        // Create UserOp with differentWallet as sender
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: differentWallet, // Different from msg.sender (scw)
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(abi.encodePacked(uint128(2000000), uint128(2000000))),
            preVerificationGas: 100000,
            gasFees: bytes32(abi.encodePacked(uint128(1000000000), uint128(1000000000))),
            paymasterAndData: "",
            signature: new bytes(65) // Valid length signature
        });
        bytes32 userOpHash = keccak256("dummy-hash");
        // Attempt to validate from scw but with differentWallet as userOp.sender - should revert
        vm.prank(address(scw));
        _toRevert(CAM.CredibleAccountModule_InvalidCaller.selector, hex"");
        cam.validateUserOp(userOp, userOpHash);
    }

    /// @notice Tests that validateUserOp reverts when hook is installed but validator is not
    /// @dev Verifies that having only hook module installed is not sufficient for validation
    function test_validateUserOp_RevertIf_OnlyHookInstalled() public {
        // Setup: Install only hook module (not validator)
        // Create a wallet and install only hook module
        address hookOnlyWallet = makeAddr("hookOnlyWallet");
        // Manually set hook as initialized but not validator
        vm.store(
            address(cam),
            keccak256(abi.encode(hookOnlyWallet, uint256(0))), // moduleInitialized mapping slot
            bytes32(uint256(1)) // hookInitialized = true, validatorInitialized = false
        );
        // Create UserOp for the hook-only wallet
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: hookOnlyWallet,
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(abi.encodePacked(uint128(2000000), uint128(2000000))),
            preVerificationGas: 100000,
            gasFees: bytes32(abi.encodePacked(uint128(1000000000), uint128(1000000000))),
            paymasterAndData: "",
            signature: new bytes(65) // Valid length signature
        });
        bytes32 userOpHash = keccak256("dummy-hash");
        // Attempt to validate from hook-only wallet - should revert
        vm.prank(hookOnlyWallet);
        _toRevert(CAM.CredibleAccountModule_ModuleNotInstalled.selector, abi.encode(hookOnlyWallet));
        cam.validateUserOp(userOp, userOpHash);
    }

    // Test: isInitialized returns true when both validator and hook are installed
    function test_isInitialized_returnsTrueWhen_bothModulesInstalled() public withRequiredModules {
        // Verify both modules are installed via the modifier
        assertTrue(cam.isInitialized(address(scw)), "Should return true when both validator and hook are initialized");
    }

    // Test: isInitialized returns false when only hook is installed
    function test_isInitialized_returnsFalseWhen_onlyHookInstalled() public {
        _testSetup();
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(moecdsav), hex"");
        // Install only hook module
        _installHookViaMultiplexer(scw, address(cam), HookType.GLOBAL);
        // Should return false since validator is not installed
        assertFalse(cam.isInitialized(address(scw)), "Should return false when only hook is initialized");
    }

    // Test: isInitialized returns false when only validator is installed
    function test_isInitialized_returnsFalseWhen_onlyValidatorInstalled() public {
        _testSetup();
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(moecdsav), hex"");
        // Install hook first (required for validator installation)
        _installHookViaMultiplexer(scw, address(cam), HookType.GLOBAL);
        // Install only validator module
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(cam), abi.encode(MODULE_TYPE_VALIDATOR));
        // Uninstall validator
        _uninstallModule(
            eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(cam), abi.encode(MODULE_TYPE_VALIDATOR, address(scw))
        );
        // Should return false since hook is not initialized
        assertFalse(cam.isInitialized(address(scw)), "Should return false when only validator is initialized");
    }

    function test_claimingTokens_exactWalletBalance_edgeCase() public withRequiredModules {
        // Get current wallet balances to determine exact amounts
        uint256 usdcBalance = usdc.balanceOf(address(scw));
        uint256 daiBalance = dai.balanceOf(address(scw));
        uint256 usdtBalance = usdt.balanceOf(address(scw));

        // Verify wallet has tokens initially
        assertTrue(usdcBalance > 0, "Wallet should have usdc balance");
        assertTrue(daiBalance > 0, "Wallet should have dai balance");
        assertTrue(usdtBalance > 0, "Wallet should have usdt balance");

        // Create session key data with EXACT wallet balances (edge case: 100% locked)
        TokenData[] memory exactTokenData = new TokenData[](3);
        exactTokenData[0] = TokenData({token: address(usdc), amount: usdcBalance});
        exactTokenData[1] = TokenData({token: address(dai), amount: daiBalance});
        exactTokenData[2] = TokenData({token: address(usdt), amount: usdtBalance});

        ResourceLock memory exactResourceLock = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: sessionKey.pub,
            validAfter: uint48(block.timestamp),
            validUntil: uint48(block.timestamp + 1000),
            solver: solver.pub,
            bidHash: keccak256("exactBalanceTest"),
            tokenData: exactTokenData
        });

        // Enable session key with exact wallet balance amounts
        bytes memory enableSessionKeyData =
            abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(exactResourceLock));

        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );

        // Create user operation with proper signature format
        (PackedUserOperation memory op, bytes32[] memory proof, bytes32 root) =
            _createUserOpWithResourceLock(address(scw), eoa, address(rlv), opCalldata, exactResourceLock, true);

        bytes memory sig = _sign(root, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(root), _packProofForSignature(proof));

        // Fund the wallet with enough ETH for gas fees
        vm.deal(address(scw), 1 ether);

        // Execute the user operation
        _executeUserOp(op);

        // Verify session key is enabled
        assertTrue(cam.getSessionKeyData(sessionKey.pub).live, "Session key should be live");

        // Claim ALL tokens (exact amounts) - this should result in zero wallet balance
        _claimTokensBySolver(eoa, scw, sessionKey, usdcBalance, daiBalance, usdtBalance);

        // Verify the edge case: wallet balances are now zero
        assertEq(usdc.balanceOf(address(scw)), 0, "usdc wallet balance should be zero");
        assertEq(dai.balanceOf(address(scw)), 0, "dai wallet balance should be zero");
        assertEq(usdt.balanceOf(address(scw)), 0, "usdt wallet balance should be zero");

        // Verify tokens are fully claimed
        assertTrue(cam.isSessionClaimed(sessionKey.pub), "Session should be fully claimed");

        // Verify no locked tokens remain
        assertEq(cam.tokenTotalLockedForWallet(address(usdc)), 0, "No usdc should remain locked");
        assertEq(cam.tokenTotalLockedForWallet(address(dai)), 0, "No dai should remain locked");
        assertEq(cam.tokenTotalLockedForWallet(address(usdt)), 0, "No usdt should remain locked");
    }

    function test_configure_revertIf_invalidCaller() public {
        vm.startPrank(eoa.pub);
        vm.expectRevert();
        cam.configure(address(0), address(im));
    }

    function test_configure_revertIf_invalidAddressesUsed() public {
        vm.startPrank(deployer.pub);
        _toRevert(CAM.CredibleAccountModule_InvalidResourceLockValidator.selector, hex"");
        cam.configure(address(0), address(im));
        _toRevert(CAM.CredibleAccountModule_InvalidInvoiceManager.selector, hex"");
        cam.configure(address(rlv), address(0));
    }

    function test_setInvoiceManager_success() public {
        address newIm = makeAddr("new_invoice_manager");
        vm.startPrank(deployer.pub);
        address previous = cam.invoiceManager();
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.CredibleAccountModule_InvoiceManagerUpdated(previous, newIm);
        cam.setInvoiceManager(newIm);
        address updated = cam.invoiceManager();
        assertNotEq(previous, updated);
    }

    function test_setInvoiceManager_revertIf_invalidCaller() public {
        address newIm = makeAddr("new_invoice_manager");
        vm.startPrank(eoa.pub);
        vm.expectRevert();
        cam.setInvoiceManager(newIm);
    }

    function test_setInvoiceManager_revertIf_invalidAddressesUsed() public {
        vm.startPrank(deployer.pub);
        _toRevert(CAM.CredibleAccountModule_InvalidInvoiceManager.selector, hex"");
        cam.setInvoiceManager(address(0));
    }

    function test_enableSessionKey_revertIf_resourceLockValidatorNotSet() public {
        CAM badSetupCAM = new CAM(deployer.pub, address(hmp));
        vm.stopPrank();
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(moecdsav), hex"");
        _installHookViaMultiplexer(scw, address(badSetupCAM), HookType.GLOBAL);
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(badSetupCAM), abi.encode(MODULE_TYPE_VALIDATOR));

        // Mint tokens for the session key
        usdc.mint(address(scw), amounts[0]);
        dai.mint(address(scw), amounts[1]);
        usdt.mint(address(scw), amounts[2]);

        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }

        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: sessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            solver: solver.pub,
            bidHash: DUMMY_BID_HASH,
            tokenData: tokenAmounts
        });
        bytes memory resourceLockData = abi.encode(rl);
        _toRevert(CAM.CredibleAccountModule_ResourceLockValidatorNotSet.selector, hex"");

        // Call enableSessionKey directly from the wallet address
        vm.prank(address(scw));
        badSetupCAM.enableSessionKey(resourceLockData);
    }

    function test_enableSessionKey_revertIf_sessionKeyNotAuthorized() public withRequiredModules {
        // Mint tokens for the session key
        usdc.mint(address(scw), amounts[0]);
        dai.mint(address(scw), amounts[1]);
        usdt.mint(address(scw), amounts[2]);

        TokenData[] memory tokenAmounts = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenAmounts[i] = TokenData(tokens[i], amounts[i]);
        }

        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: sessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            solver: solver.pub,
            bidHash: DUMMY_BID_HASH,
            tokenData: tokenAmounts
        });

        // Try to enable session key directly without proper RLV authorization
        vm.startPrank(address(scw));
        vm.expectRevert(abi.encodeWithSelector(CAM.CredibleAccountModule_SessionKeyNotAuthorized.selector));
        cam.enableSessionKey(abi.encode(rl));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           FULL E2E TESTING
    //////////////////////////////////////////////////////////////*/

    function test_fullE2E_resourceLockToSettlement() public withRequiredModules {
        _setupTokenBalances();
        bytes32 bidHash = _enableSessionKeyPhase();
        _executeTokenTransfers();
        _settleInvoicePhase();
        _verifyCleanupPhase(bidHash);
    }

    function _setupTokenBalances() internal {
        console2.log("=== SETUP PHASE ===");

        deal(address(usdc), address(scw), 1000e6);
        deal(address(usdt), address(scw), 1000e18);
        deal(address(dai), address(scw), 1000e18);

        console2.log("SCW USDC balance:", usdc.balanceOf(address(scw)));
        console2.log("SCW USDT balance:", usdt.balanceOf(address(scw)));
        console2.log("SCW DAI balance:", dai.balanceOf(address(scw)));
    }

    function _enableSessionKeyPhase() internal returns (bytes32 bidHash) {
        console2.log("\n=== PHASE 1: ENABLE SESSION KEY ===");

        bidHash = DUMMY_BID_HASH;

        // Create ResourceLock with specific token amounts
        TokenData[] memory tokenData = new TokenData[](3);
        tokenData[0] = TokenData({token: address(usdc), amount: 100e6});
        tokenData[1] = TokenData({token: address(usdt), amount: 50e18});
        tokenData[2] = TokenData({token: address(dai), amount: 200e18});

        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: sessionKey.pub,
            validAfter: uint48(block.timestamp),
            validUntil: uint48(block.timestamp + 1 hours),
            solver: solver.pub,
            bidHash: bidHash,
            tokenData: tokenData
        });

        _executeEnableSessionKey(rl);
    }

    function _executeEnableSessionKey(ResourceLock memory rl) internal {
        (bytes32[] memory proof, bytes32 merkleRoot,) = getTestProof(_buildResourceLockHash(rl), true);

        PackedUserOperation memory enableOp = _createUserOp(address(scw), address(rlv));
        enableOp.callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(cam), 0, abi.encodeWithSelector(cam.enableSessionKey.selector, abi.encode(rl))
                )
            )
        );

        bytes memory sig = _sign(merkleRoot, eoa);
        enableOp.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));

        console2.log("Executing enableSessionKey UserOp...");
        _executeUserOp(enableOp);

        assertTrue(cam.getSessionKeyData(sessionKey.pub).live, "Session key should be enabled");
        console2.log("Session key enabled successfully");

        ICredibleAccountModule.LockedToken[] memory lockedTokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
        assertEq(lockedTokens.length, rl.tokenData.length, "Should have expected number of locked tokens");
        console2.log("Invoice created with", lockedTokens.length, "token entries");
    }

    function _executeTokenTransfers() internal {
        console2.log("\n=== PHASE 2: USE SESSION KEY ===");

        // Record initial solver balances
        uint256 solverUsdcBefore = usdc.balanceOf(solver.pub);
        uint256 solverUsdtBefore = usdt.balanceOf(solver.pub);
        uint256 solverDaiBefore = dai.balanceOf(solver.pub);

        console2.log("Solver balances before:", solverUsdcBefore, solverUsdtBefore, solverDaiBefore);

        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({
            target: address(cam),
            value: 0,
            callData: abi.encodeCall(ICredibleAccountModule.claim, (sessionKey.pub, address(usdc), 100e6))
        });
        batch[1] = Execution({
            target: address(cam),
            value: 0,
            callData: abi.encodeCall(ICredibleAccountModule.claim, (sessionKey.pub, address(usdt), 50e18))
        });
        batch[2] = Execution({
            target: address(cam),
            value: 0,
            callData: abi.encodeCall(ICredibleAccountModule.claim, (sessionKey.pub, address(dai), 200e18))
        });

        bytes memory batchCallData =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));

        (PackedUserOperation memory transferOp,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), batchCallData);

        console2.log("Executing token transfer UserOp with session key...");
        _executeUserOp(transferOp);

        _verifyTokenTransfers();
    }

    function _verifyTokenTransfers() internal {
        console2.log("Tokens transferred to InvoiceManager");
        console2.log(
            "InvoiceManager balances:",
            usdc.balanceOf(address(im)),
            usdt.balanceOf(address(im)),
            dai.balanceOf(address(im))
        );

        ICredibleAccountModule.LockedToken[] memory lockedTokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
        for (uint256 i; i < lockedTokens.length; ++i) {
            console2.log("Token", i);
            console2.log("claimed:", lockedTokens[i].claimedAmount);
            console2.log("of", lockedTokens[i].lockedAmount);
            assertGt(lockedTokens[i].claimedAmount, 0, "Should have claimed tokens");
        }
    }

    function _settleInvoicePhase() internal {
        console2.log("\n=== PHASE 3: SETTLE INVOICE ===");

        uint256 solverUsdcBefore = usdc.balanceOf(solver.pub);
        uint256 solverUsdtBefore = usdt.balanceOf(solver.pub);
        uint256 solverDaiBefore = dai.balanceOf(solver.pub);

        vm.stopPrank();
        vm.prank(deployer.pub);
        console2.log("Settling invoice for session key...");
        im.settleInvoice(sessionKey.pub);

        uint256 solverUsdcAfter = usdc.balanceOf(solver.pub);
        uint256 solverUsdtAfter = usdt.balanceOf(solver.pub);
        uint256 solverDaiAfter = dai.balanceOf(solver.pub);

        console2.log("Solver balances after:", solverUsdcAfter, solverUsdtAfter, solverDaiAfter);

        assertGt(solverUsdcAfter, solverUsdcBefore, "Solver should receive USDC");
        assertGt(solverUsdtAfter, solverUsdtBefore, "Solver should receive USDT");
        assertGt(solverDaiAfter, solverDaiBefore, "Solver should receive DAI");

        console2.log("Solver paid successfully");
    }

    function _verifyCleanupPhase(bytes32 bidHash) internal {
        console2.log("\n=== PHASE 4: CLEANUP ===");

        bool isSessionClaimed = cam.isSessionClaimed(sessionKey.pub);
        console2.log("Session fully claimed:", isSessionClaimed);

        assertTrue(rlv.isConsumedBidHash(address(scw), bidHash), "Bid hash should be consumed");

        console2.log("E2E test completed successfully");
    }

    function test_fullE2E_preventBidHashReplay() public withRequiredModules {
        console2.log("=== SETUP: BID HASH REPLAY PREVENTION TEST ===");
        deal(address(usdc), address(scw), 1000e6);

        bytes32 firstBidHash = _executeFirstSession();
        _attemptBidHashReplay(firstBidHash);
        _verifyNewBidHashWorks();
    }

    function _executeFirstSession() internal returns (bytes32 firstBidHash) {
        console2.log("\n=== PHASE 1: FIRST SESSION WITH BID HASH ===");

        firstBidHash = keccak256("first_bid_hash");

        TokenData[] memory tokenData1 = new TokenData[](1);
        tokenData1[0] = TokenData({token: address(usdc), amount: 100e6});

        ResourceLock memory rl1 = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: sessionKey.pub,
            validAfter: uint48(block.timestamp),
            validUntil: uint48(block.timestamp + 1 hours),
            solver: solver.pub,
            bidHash: firstBidHash,
            tokenData: tokenData1
        });

        _executeEnableSessionKey(rl1);
        assertTrue(rlv.isConsumedBidHash(address(scw), firstBidHash), "Bid hash should be consumed");
        console2.log("First session enabled, bid hash consumed");

        // Complete the first session by claiming tokens
        _executeTokenClaim(100e6);
        console2.log("First session completed successfully");
    }

    function _executeTokenClaim(uint256 amount) internal {
        bytes memory usdcData = _createClaimExecution(sessionKey.pub, address(usdc), amount);
        bytes memory claimCallData = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, usdcData))
        );

        (PackedUserOperation memory claimOp,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), claimCallData);
        _executeUserOp(claimOp);
    }

    function _attemptBidHashReplay(bytes32 firstBidHash) internal {
        console2.log("\n=== PHASE 2: ATTEMPT BID HASH REPLAY ===");

        User memory replaySessionKey = _createUser("replay_session");

        TokenData[] memory tokenData2 = new TokenData[](1);
        tokenData2[0] = TokenData({token: address(usdc), amount: 50e6});

        ResourceLock memory rl2 = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: replaySessionKey.pub,
            validAfter: uint48(block.timestamp),
            validUntil: uint48(block.timestamp + 1 hours),
            solver: solver.pub,
            bidHash: firstBidHash, // REUSING SAME BID HASH!
            tokenData: tokenData2
        });

        (bytes32[] memory proof2, bytes32 merkleRoot2,) = getTestProof(_buildResourceLockHash(rl2), true);
        PackedUserOperation memory replayOp = _createUserOp(address(scw), address(rlv));
        replayOp.callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(cam), 0, abi.encodeWithSelector(cam.enableSessionKey.selector, abi.encode(rl2))
                )
            )
        );

        bytes memory sig2 = _sign(merkleRoot2, eoa);
        replayOp.signature = bytes.concat(sig2, abi.encodePacked(merkleRoot2), _packProofForSignature(proof2));

        console2.log("Attempting to reuse bid hash (should fail)...");
        _toRevert(
            IEntryPoint.FailedOpWithRevert.selector,
            abi.encode(
                0, AA23, abi.encodeWithSelector(ResourceLockValidator.RLV_BidHashAlreadyConsumed.selector, firstBidHash)
            )
        );
        _executeUserOp(replayOp);
        console2.log("Bid hash replay prevented");
    }

    function _verifyNewBidHashWorks() internal {
        console2.log("\n=== PHASE 3: NEW BID HASH SHOULD WORK ===");

        User memory replaySessionKey = _createUser("replay_session_2");
        bytes32 newBidHash = keccak256("new_bid_hash");

        TokenData[] memory tokenData3 = new TokenData[](1);
        tokenData3[0] = TokenData({token: address(usdc), amount: 50e6});

        ResourceLock memory rl3 = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: replaySessionKey.pub,
            validAfter: uint48(block.timestamp),
            validUntil: uint48(block.timestamp + 1 hours),
            solver: solver.pub,
            bidHash: newBidHash,
            tokenData: tokenData3
        });

        _executeEnableSessionKey(rl3);
        assertTrue(cam.getSessionKeyData(replaySessionKey.pub).live, "New session should be enabled");
        assertTrue(rlv.isConsumedBidHash(address(scw), newBidHash), "New bid hash should be consumed");
        console2.log("New bid hash worked successfully");
    }

    function test_fullE2E_expiredSessionKeyRejection() public withRequiredModules {
        // Setup: Create an expired session key using absolute timestamps
        uint48 expiredValidAfter = uint48(block.timestamp + 1 hours);
        uint48 expiredValidUntil = uint48(block.timestamp + 2 hours);

        TokenData[] memory td = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            td[i] = TokenData(tokens[i], amounts[i]);
        }

        ResourceLock memory expiredRl = ResourceLock({
            chainId: block.chainid,
            smartWallet: address(scw),
            sessionKey: sessionKey.pub,
            validAfter: expiredValidAfter,
            validUntil: expiredValidUntil,
            solver: solver.pub,
            bidHash: DUMMY_BID_HASH,
            tokenData: td
        });

        // First enable the session key (this should work)
        bytes memory enableSessionKeyData = abi.encodeWithSelector(CAM.enableSessionKey.selector, abi.encode(expiredRl));
        bytes memory enableOpCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, enableSessionKeyData))
        );

        (PackedUserOperation memory enableOp, bytes32[] memory proof, bytes32 root) =
            _createUserOpWithResourceLock(address(scw), eoa, address(rlv), enableOpCalldata, expiredRl, true);
        bytes memory enableSig = _sign(root, eoa);
        enableOp.signature = bytes.concat(enableSig, abi.encodePacked(root), _packProofForSignature(proof));
        _executeUserOp(enableOp);

        // Now advance time to make the session key expired
        vm.warp(block.timestamp + 3 hours);

        // Try to use the now-expired session key to claim tokens
        bytes memory usdcData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory claimOpCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, usdcData))
        );

        // Use session key to sign but it should fail due to expiration
        (PackedUserOperation memory claimOp,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), claimOpCalldata);

        // Expect AA22 due to expired timestamp validation
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA22));
        _executeUserOp(claimOp);
    }

    function test_fullE2E_inactiveSolverSettlement() public withRequiredModules {
        deal(address(usdc), address(scw), 1000e6);

        // Complete the full flow
        _enableSessionKey(address(scw));

        bytes memory claimData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory claimCallData = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, claimData))
        );

        (PackedUserOperation memory claimOp,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), claimCallData);
        _executeUserOp(claimOp);

        // Deactivate the solver
        vm.stopPrank();
        vm.prank(deployer.pub);
        im.toggleSolverStatus(solver.pub);

        // Try to settle with inactive solver (should fail)
        vm.prank(deployer.pub);
        vm.expectRevert(); // Should revert due to inactive solver
        im.settleInvoice(sessionKey.pub);
    }

    function test_fullE2E_emergencySessionDisable() public withRequiredModules {
        deal(address(usdc), address(scw), 1000e6);

        _enableSessionKey(address(scw));

        // Verify session is active
        assertTrue(cam.getSessionKeyData(sessionKey.pub).live, "Session should be active");

        // Admin emergency disable
        vm.stopPrank();
        vm.prank(deployer.pub);
        vm.expectEmit(true, true, false, false);
        emit ICredibleAccountModule.CredibleAccountModule_SessionKeyDisabled(sessionKey.pub, address(scw));
        cam.emergencyDisableSessionKey(sessionKey.pub);

        // Verify session is disabled
        assertEq(cam.getSessionKeyData(sessionKey.pub).validUntil, 0, "Session should be disabled");

        // Try to use disabled session key (should fail)
        bytes memory claimData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory claimCallData = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdc), 0, claimData))
        );

        (PackedUserOperation memory claimOp,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), claimCallData);

        // Should fail with AA24 because the disabled session key data no longer matches
        // (sessionData lookup returns empty struct, so sd.sessionKey != sessionKeySigner)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));

        _executeUserOp(claimOp);
    }

    /*//////////////////////////////////////////////////////////////
                          V2 CLAIMING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_claim_revertIf_tokenAlreadyClaimed() public withRequiredModules {
        _enableSessionKey(address(scw));

        // Claim USDC once
        bytes memory claimData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, claimData))
        );
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);
        _executeUserOp(op);

        // Try to claim same token again
        (PackedUserOperation memory secondOp, bytes32 hash) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);
        _revertUserOpEvent(
            hash,
            secondOp.nonce,
            CAM.CredibleAccountModule_TokenAlreadyClaimed.selector,
            abi.encode(sessionKey.pub, address(usdc))
        );
        _executeUserOp(secondOp);
    }

    function test_claim_revertIf_tokenNotFoundForSession() public withRequiredModules {
        _enableSessionKey(address(scw)); // Only enables USDC, DAI, USDT

        // Try to claim a token not in the session (e.g., different token)
        link.mint(address(scw), 100e18);
        link.approve(address(cam), 100e18);

        bytes memory claimData = _createClaimExecution(sessionKey.pub, address(link), 100e18);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, claimData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);

        _revertUserOpEvent(
            hash,
            op.nonce,
            CAM.CredibleAccountModule_TokenNotFoundForSession.selector,
            abi.encode(sessionKey.pub, address(link))
        );
        _executeUserOp(op);
    }

    function test_validateUserOp_passesWithoutBusinessLogicValidation() public withRequiredModules {
        _enableSessionKey(address(scw));

        // Create invalid claim operation that should pass validation but fail execution
        bytes memory claimData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0] + 1); // Wrong amount
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, claimData))
        );
        (PackedUserOperation memory op, bytes32 hash) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);

        // Validation should pass (structural validation only)
        uint256 result = cam.validateUserOp(op, hash);
        assertTrue(result != VALIDATION_FAILED, "Validation should pass even with business logic errors");
    }

    function test_validateUserOp_failsWithWrongTarget() public withRequiredModules {
        _enableSessionKey(address(scw));

        // Create operation targeting wrong contract
        bytes memory claimData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(usdc), 0, claimData))
        ); // Wrong target
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);

        // Validation should fail (structural validation)
        uint256 result = cam.validateUserOp(op, keccak256("test"));
        assertEq(result, VALIDATION_FAILED, "Validation should fail with wrong target");
    }

    function test_validateUserOp_failsWithWrongSelector() public withRequiredModules {
        _enableSessionKey(address(scw));

        // Create operation with wrong function selector
        bytes memory transferData = abi.encodeWithSelector(IERC20.transfer.selector, address(im), amounts[0]);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, transferData))
        ); // Wrong selector
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);

        uint256 result = cam.validateUserOp(op, keccak256("test"));
        assertEq(result, VALIDATION_FAILED, "Validation should fail with wrong selector");
    }

    function test_claim_batch_atomicFailure() public withRequiredModules {
        _enableSessionKey(address(scw));

        // Create batch where first two are valid, third fails
        bytes memory usdcData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory daiData = _createClaimExecution(sessionKey.pub, address(dai), amounts[1]);
        bytes memory usdtData = _createClaimExecution(sessionKey.pub, address(usdt), amounts[2] + 1); // Invalid amount

        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(cam), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(cam), value: 0, callData: daiData});
        batch[2] = Execution({target: address(cam), value: 0, callData: usdtData});

        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);

        _executeUserOp(op); // Should revert

        // Verify NO tokens were claimed (atomic failure)
        ICredibleAccountModule.LockedToken[] memory tokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
        assertEq(tokens[0].claimedAmount, 0, "USDC should not be claimed due to batch failure");
        assertEq(tokens[1].claimedAmount, 0, "DAI should not be claimed due to batch failure");
        assertEq(tokens[2].claimedAmount, 0, "USDT should not be claimed due to batch failure");
    }

    function test_claim_batch_partialClaims() public withRequiredModules {
        _enableSessionKey(address(scw));

        // Claim only 2 out of 3 tokens successfully
        bytes memory usdcData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory daiData = _createClaimExecution(sessionKey.pub, address(dai), amounts[1]);

        Execution[] memory batch = new Execution[](2); // Only 2 tokens
        batch[0] = Execution({target: address(cam), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(cam), value: 0, callData: daiData});

        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);

        _executeUserOp(op);

        // Verify partial claiming worked
        ICredibleAccountModule.LockedToken[] memory tokens = cam.getLockedTokensForSessionKey(sessionKey.pub);
        assertEq(tokens[0].claimedAmount, amounts[0], "USDC should be claimed");
        assertEq(tokens[1].claimedAmount, amounts[1], "DAI should be claimed");
        assertEq(tokens[2].claimedAmount, 0, "USDT should NOT be claimed");

        // Verify session is not fully claimed
        assertFalse(cam.isSessionClaimed(sessionKey.pub), "Session should not be fully claimed");
    }

    function test_claim_integrationWithInvoiceManager() public withRequiredModules {
        _enableSessionKey(address(scw));
        uint256 initialBalance = usdc.balanceOf(address(im));

        bytes memory claimData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, claimData))
        );
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);

        _executeUserOp(op);

        // Verify tokens went to invoice manager
        assertEq(
            usdc.balanceOf(address(im)), initialBalance + amounts[0], "Tokens should be transferred to InvoiceManager"
        );
        assertEq(usdc.balanceOf(address(scw)), 0, "Wallet should have no USDC left");
    }

    function test_claim_eventEmission() public withRequiredModules {
        _enableSessionKey(address(scw));

        bytes memory claimData = _createClaimExecution(sessionKey.pub, address(usdc), amounts[0]);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(cam), 0, claimData))
        );
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(scw), address(cam), opCalldata);

        vm.expectEmit(true, true, false, true);
        emit ICredibleAccountModule.CredibleAccountModule_TokensClaimed(sessionKey.pub, address(usdc), amounts[0]);

        _executeUserOp(op);
    }
}
