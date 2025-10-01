// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MODULE_TYPE_VALIDATOR} from "ERC7579/interfaces/IERC7579Module.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {ExecutionLib} from "ERC7579/libs/ExecutionLib.sol";
import "ERC7579/libs/ModeLib.sol";
import {SentinelListLib} from "ERC7579/libs/SentinelList.sol";
import "ERC7579/test/dependencies/EntryPoint.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {SessionKeyValidator} from "../../../../src/modules/validators/SessionKeyValidator.sol";
import {ExecutionValidation, ParamCondition, Permission, SessionData} from "../../../../src/common/Structs.sol";
import {ComparisonRule} from "../../../../src/common/Enums.sol";
import {TestCounter} from "../../../../src/test/TestCounter.sol";
import {TestERC20} from "../../../../src/test/TestERC20.sol";
import {TestWETH} from "../../../../src/test/TestWETH.sol";
import {TestUniswapV2} from "../../../../src/test/TestUniswapV2.sol";
import {TestUniswapV3} from "../../../../src/test/TestUniswapV3.sol";
import {TestERC721} from "../../../../src/test/TestERC721.sol";
import {SessionKeyTestUtils as TestUtils} from "../utils/SessionKeyTestUtils.sol";

contract SessionKeyValidator_Concrete_Test is TestUtils {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SKV_ModuleInstalled(address indexed wallet);
    event SKV_ModuleUninstalled(address indexed wallet);
    event SKV_SessionKeyEnabled(address indexed sessionKey, address indexed wallet);
    event SKV_SessionKeyDisabled(address indexed sessionKey, address indexed wallet);
    event SKV_SessionKeyPauseToggled(address indexed sessionKey, address indexed wallet, bool live);
    event SKV_PermissionUsesUpdated(address indexed sessionKey, uint256 index, uint256 previousUses, uint256 newUses);
    event SKV_SessionKeyValidUntilUpdated(address indexed sessionKey, address indexed wallet, uint48 newValidUntil);
    event SKV_PermissionAdded(
        address indexed sessionKey,
        address indexed wallet,
        address indexed target,
        bytes4 selector,
        uint256 payableLimit,
        uint256 uses,
        ParamCondition[] paramConditions
    );
    event SKV_PermissionRemoved(address indexed sessionKey, address indexed wallet, uint256 indexToRemove);
    event SKV_PermissionModified(
        address indexed sessionKey,
        address indexed wallet,
        uint256 index,
        address target,
        bytes4 selector,
        uint256 payableLimit,
        uint256 uses,
        ParamCondition[] paramConditions
    );
    event SKV_PermissionUsed(address indexed sessionKey, Permission permission, uint256 oldUses, uint256 newUses);

    // From TestCounter contract
    event ReceivedPayableCall(uint256 amount, uint256 payment);
    event ReceivedMultiTypeCall(address addr, uint256 num, bool boolVal);

    // From TestUniswapV2/V3 contracts
    event MockUniswapExchangeEvent(uint256 amountIn, uint256 amountOut, address tokenIn, address tokenOut);

    // From TestERC721 contract
    event TestNFTPuchased(address indexed buyer, address indexed receiver, uint256 tokenId);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testSetup();
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    function test_installModule() public {
        // Expect the module installation event to be emitted
        vm.expectEmit(true, false, false, false);
        emit SKV_ModuleInstalled(address(scw));
        // Execute the module installation
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(skv), hex"");
        // Verify that the module is installed
        assertTrue(scw.isModuleInstalled(1, address(skv), ""), "SessionKeyValidator module should be installed");
    }

    function test_installModule_RevertIf_DoubleInstall() public {
        // Expect the module installation event to be emitted
        vm.expectEmit(true, false, false, false);
        emit SKV_ModuleInstalled(address(scw));
        // Execute the module installation
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(skv), hex"");
        _toRevert(SentinelListLib.LinkedList_EntryAlreadyInList.selector, abi.encode(address(skv)));
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(skv), hex"");
    }

    function test_uninstallModule() public validatorInstalled {
        assertTrue(scw.isModuleInstalled(1, address(skv), ""));
        // Set up a session key
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Verify that one session key is associated with the wallet
        assertEq(skv.getSessionKeysByWallet().length, 1, "Should have 1 associated session key");
        // Expect the module uninstallation event to be emitted
        vm.expectEmit(true, false, false, false);
        emit SKV_ModuleUninstalled(address(scw));
        // Execute the module uninstallation
        _uninstallModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(skv), hex"");
        // Verify that SessionKeyValidator is uninstalled
        assertFalse(scw.isModuleInstalled(1, address(skv), ""), "SessionKeyValidator should be uninstalled");
        // Verify that SessionKeyValidator is not initialized on wallet after uninstall
        assertFalse(skv.isInitialized(address(scw)), "SessionKeyValidator should not be initialized after uninstall");
        // Verify that no session keys are associated after uninstall
        assertEq(skv.getSessionKeysByWallet().length, 0, "Should have no associated session keys after uninstall");
    }

    function test_uninstallModule_cantUninstallIfNotInstalled() public {
        // Prank account that does not have SessionKeyValidator installed
        vm.prank(eoa.pub);
        // Expect the function call to revert with SKV_ModuleNotInstalled error
        // when trying to uninstall without installing first
        _toRevert(SessionKeyValidator.SKV_ModuleNotInstalled.selector, hex"");
        // Attempt to uninstall SessionKeyValidator
        skv.onUninstall("");
    }

    function test_isModuleType() public {
        // Verify that SessionKeyValidator is of MODULE_TYPE_VALIDATOR type
        assertTrue(
            skv.isModuleType(MODULE_TYPE_VALIDATOR), "SessionKeyValidator should be of MODULE_TYPE_VALIDATOR type"
        );
    }

    function test_isInitialized() public validatorInstalled {
        // Verify that SessionKeyValidator is initialized for the wallet
        assertTrue(skv.isInitialized(address(scw)), "SessionKeyValidator should be initialized for SCW");
    }

    function test_isValidSignatureWithSender() public {
        // Expect the function call to revert with NotImplemented error
        _toRevert(SessionKeyValidator.NotImplemented.selector, hex"");
        // Call isValidSignatureWithSender
        skv.isValidSignatureWithSender(address(0), bytes32(0), "");
    }

    function test_enableSessionKey() public {
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        vm.expectEmit(false, false, false, true);
        emit SKV_SessionKeyEnabled(sessionKey.pub, address(scw));
        skv.enableSessionKey(sd, perms);
        Permission[] memory skPerm = skv.getSessionKeyPermissions(sessionKey.pub);
        assertEq(skPerm.length, 1);
        assertEq(skPerm[0].target, address(counter1));
        assertEq(skPerm[0].selector, TestCounter.multiTypeCall.selector);
        assertEq(skPerm[0].payableLimit, 100 wei);
        assertEq(skPerm[0].paramConditions.length, 2);
        assertEq(skPerm[0].paramConditions[0].offset, 4);
        assertEq(
            uint8(skPerm[0].paramConditions[0].rule),
            2 // ComparisonRule.EQUAL
        );
        assertEq(skPerm[0].paramConditions[0].value, bytes32(uint256(uint160(address(alice.pub)))));
        assertEq(skPerm[0].paramConditions[1].offset, 36);
        assertEq(
            uint8(skPerm[0].paramConditions[1].rule),
            1 // ComparisonRule.LESS_THAN_OR_EQUAL_TO
        );
        assertEq(skPerm[0].paramConditions[1].value, bytes32(uint256(5)));
    }

    function test_enableSessionKey_RevertIf_SessionKeyZeroAddress() public {
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(zero);
        // Expect the function call to revert with SKV_InvalidSessionKeyData error
        // when trying to set up a session key with a zero address
        _toRevert(
            SessionKeyValidator.SKV_InvalidSessionKeyData.selector, abi.encode(address(0), validAfter, validUntil)
        );
        // Attempt to set up a session key with a zero address
        skv.enableSessionKey(sd, perms);
    }

    function test_enableSessionKey_RevertIf_SessionKeyAlreadyExists() public {
        // Set up a session key
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Expect the function call to revert with SKV_SessionKeyAlreadyExists error
        // when trying to enable an already existing session key
        _toRevert(SessionKeyValidator.SKV_SessionKeyAlreadyExists.selector, abi.encode(sessionKey.pub));
        // Attempt to enable the same session key again
        skv.enableSessionKey(sd, perms);
    }

    function test_enableSessionKey_RevertIf_InvalidValidAfter() public {
        // Set up targets with one valid address and one invalid (zero) validAfter timestamp
        SessionData memory sd =
            SessionData({sessionKey: sessionKey.pub, validAfter: uint48(0), validUntil: validUntil, live: false});
        ParamCondition[] memory conditions = new ParamCondition[](1);
        conditions[0] = ParamCondition({
            offset: 4,
            rule: ComparisonRule.EQUAL,
            value: bytes32(uint256(uint160(address(alice.pub))))
        });
        Permission[] memory perms = new Permission[](1);
        perms[0] = Permission({
            target: address(counter1),
            selector: TestCounter.multiTypeCall.selector,
            payableLimit: 100 wei,
            uses: tenUses,
            paramConditions: conditions
        });
        // Expect the function call to revert with SKV_InvalidSessionKeyData error
        // when trying to set up a session key with an invalid (zero) validAfter timestamp
        _toRevert(
            SessionKeyValidator.SKV_InvalidSessionKeyData.selector, abi.encode(sessionKey.pub, uint48(0), validUntil)
        );
        // Attempt to set up a session key with an invalid (zero) validAfter timestamp
        skv.enableSessionKey(sd, perms);
    }

    function test_enableSessionKey_RevertIf_InvalidValidUntil() public {
        // Set up targets with one valid address and one invalid (zero) validUntil timestamp
        SessionData memory sd =
            SessionData({sessionKey: sessionKey.pub, validAfter: validAfter, validUntil: uint48(0), live: false});
        ParamCondition[] memory conditions = new ParamCondition[](1);
        conditions[0] = ParamCondition({
            offset: 4,
            rule: ComparisonRule.EQUAL,
            value: bytes32(uint256(uint160(address(alice.pub))))
        });
        Permission[] memory perms = new Permission[](1);
        perms[0] = Permission({
            target: address(counter1),
            selector: TestCounter.multiTypeCall.selector,
            payableLimit: 100 wei,
            uses: tenUses,
            paramConditions: conditions
        });
        // Expect the function call to revert with SKV_InvalidSessionKeyData error
        // when trying to set up a session key with an invalid (zero) validUntil timestamp
        _toRevert(
            SessionKeyValidator.SKV_InvalidSessionKeyData.selector, abi.encode(sessionKey.pub, validAfter, uint48(0))
        );
        // Attempt to set up a session key with an invalid (zero) validAfter timestamp
        skv.enableSessionKey(sd, perms);
    }

    function test_enableSessionKey_RevertIf_InvalidUsageAmount() public {
        // Set up SessionData with invalid uses amount
        SessionData memory sd =
            SessionData({sessionKey: sessionKey.pub, validAfter: validAfter, validUntil: validUntil, live: false});
        ParamCondition[] memory conditions = new ParamCondition[](1);
        conditions[0] = ParamCondition({
            offset: 4,
            rule: ComparisonRule.EQUAL,
            value: bytes32(uint256(uint160(address(alice.pub))))
        });
        Permission[] memory perms = new Permission[](1);
        perms[0] = Permission({
            target: address(counter1),
            selector: TestCounter.multiTypeCall.selector,
            payableLimit: 100 wei,
            uses: 0,
            paramConditions: conditions
        });

        // Expect the function call to revert with SKV_InvalidSessionKeyData error
        // when trying to set up a session key with an invalid (zero) usage amount
        _toRevert(
            SessionKeyValidator.SKV_InvalidPermissionData.selector,
            abi.encode(sessionKey.pub, address(counter1), TestCounter.multiTypeCall.selector, 100 wei, 0, conditions)
        );
        // Attempt to set up a session key with an invalid (zero) usage amount
        skv.enableSessionKey(sd, perms);
    }

    function test_enableSessionKey_RevertIf_PermissionInvalidTarget() public {
        // Set up targets with one valid address and one invalid (zero) address
        SessionData memory sd =
            SessionData({sessionKey: sessionKey.pub, validAfter: validAfter, validUntil: validUntil, live: false});
        ParamCondition[] memory conditions = new ParamCondition[](1);
        conditions[0] = ParamCondition({
            offset: 4,
            rule: ComparisonRule.EQUAL,
            value: bytes32(uint256(uint160(address(alice.pub))))
        });
        Permission[] memory perms = new Permission[](1);
        perms[0] = Permission({
            target: address(0),
            selector: TestCounter.multiTypeCall.selector,
            payableLimit: 100 wei,
            uses: tenUses,
            paramConditions: conditions
        });
        // Expect the function call to revert with SKV_InvalidPermissionData error
        // when trying to set up a session key with an invalid (zero) target address
        _toRevert(
            SessionKeyValidator.SKV_InvalidPermissionData.selector,
            abi.encode(sessionKey.pub, address(0), perms[0].selector, perms[0].payableLimit, perms[0].uses, conditions)
        );
        // Attempt to set up a session key with the invalid target
        skv.enableSessionKey(sd, perms);
    }

    function test_disableSessionKey() public {
        vm.startPrank(address(scw));
        // Set up default session key and permission data
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Verify that wallet has one session key initially
        assertEq(skv.getSessionKeysByWallet().length, 1, "Should have one associated session key initially");
        // Verify that the session key is valid initially
        assertFalse(skv.getSessionKeyData(sessionKey.pub).validUntil == 0, "Session key should be valid initially");
        // Expect the SKV_SessionKeyDisabled event to be emitted
        vm.expectEmit(true, true, false, false);
        emit SKV_SessionKeyDisabled(sessionKey.pub, address(scw));
        // Disable the session key
        skv.disableSessionKey(sessionKey.pub);
        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        // when trying to get  SessionData for disabled session key
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(sessionKey.pub));
        skv.getSessionKeyData(sessionKey.pub);

        // Verify that there are no associated session keys after disabling
        assertEq(skv.getSessionKeysByWallet().length, 0, "Should have no associated session keys after disabling");
        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        // when trying to get Permission data for disabled session key
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(sessionKey.pub));
        skv.getSessionKeyPermissions(sessionKey.pub);
        vm.stopPrank();
    }

    function test_disableSessionKey_RevertIf_SessionKeyAlreadyDisabled() public {
        // Set up default session key and permission data
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Disable the session key
        skv.disableSessionKey(sessionKey.pub);
        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        // when trying to disable an already disabled session key
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(sessionKey.pub));
        // Attempt to disable the already disabled session key
        skv.disableSessionKey(sessionKey.pub);
    }

    function test_disableSessionKey_RevertIf_NonExistentSessionKey() public {
        address newSessionKey = address(0x1234567890123456789012345678901234567890);

        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        // when trying to disable a non-existant session key
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(newSessionKey));
        // Attempt to disable the already disabled session key
        skv.disableSessionKey(newSessionKey);
    }

    function test_rotateSessionKey() public {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        address newSessionKey = address(0x1234567890123456789012345678901234567890);
        SessionData memory newSd = SessionData({
            sessionKey: newSessionKey,
            validAfter: uint48(block.timestamp),
            validUntil: uint48(block.timestamp + 7 days),
            live: false
        });
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: bytes32(uint256(7))});
        Permission[] memory newPerms = new Permission[](1);
        newPerms[0] = Permission({
            target: address(counter2),
            selector: TestCounter.changeCount.selector,
            payableLimit: 0,
            uses: 20,
            paramConditions: newConditions
        });

        skv.rotateSessionKey(sessionKey.pub, newSd, newPerms);
        assertFalse(
            skv.getSessionKeyData(newSessionKey).validUntil == 0, "New session key should be valid after rotation"
        );
        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        // when trying to get SessionData for disabled session key
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(sessionKey.pub));
        skv.getSessionKeyData(sessionKey.pub);
    }

    function test_rotateSessionKey_RevertIf_NonExistantSessionKey() public {
        address newSessionKey = address(0x1234567890123456789012345678901234567890);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        // when trying to rotate non-existant session key
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(newSessionKey));
        // Attempt to rotate the non-existant session key
        skv.rotateSessionKey(newSessionKey, sd, perms);
    }

    function test_toggleSessionKeyPause_and_isSessionLive() public {
        vm.startPrank(address(scw));
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Verify that the session key is live initially
        assertTrue(skv.isSessionLive(sessionKey.pub), "Session key should be live initially");
        // Expect the SKV_SessionKeyPaused event to be emitted
        vm.expectEmit(true, true, false, false);
        emit SKV_SessionKeyPauseToggled(sessionKey.pub, address(scw), false);
        // Pause the session key
        skv.toggleSessionKeyPause(sessionKey.pub);
        // Verify that the session key is now paused
        assertFalse(skv.isSessionLive(sessionKey.pub), "Session key should be paused");
        vm.stopPrank();
    }

    function test_toggleSessionKeyPause_RevertIf_SessionKeyDoesNotExist() public {
        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        // when trying to toggle pause for a non-existent session key
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(sessionKey.pub));
        // Attempt to toggle pause for a non-existent session key
        skv.toggleSessionKeyPause(sessionKey.pub);
    }

    function test_getSessionKeyData_and_getSessionKeyPermissions() public {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Get SessionData
        SessionData memory data = skv.getSessionKeyData(sessionKey.pub);
        // Verify SessionData
        assertEq(data.validAfter, validAfter, "ValidAfter should match the set value");
        assertEq(data.validUntil, validUntil, "ValidUntil should match the set value");
        assertEq(data.live, true, "Session key should be live");
        // Get Permission data
        Permission[] memory permissions = skv.getSessionKeyPermissions(sessionKey.pub);
        // Verify Permission data
        assertEq(permissions[0].target, address(counter1), "First permission target should be counter1");
        assertEq(
            permissions[0].selector,
            TestCounter.multiTypeCall.selector,
            "First permission selector should be multiTypeCall"
        );
        assertEq(permissions[0].payableLimit, 100 wei, "First permission payable limit should be 1 wei");
        assertEq(permissions[0].uses, tenUses, "First permission uses should be 10");
        // Get ParamCondition data for Permission
        ParamCondition[] memory conditions = permissions[0].paramConditions;
        // Verify ParamCondition data
        assertEq(conditions[0].offset, 4, "First permission value offset should be 4");
        assertEq(uint8(conditions[0].rule), 2, "First permission rule should be EQUAL (2)");
        assertEq(
            conditions[0].value,
            bytes32(uint256(uint160(address(alice.pub)))),
            "First permission value should be alice's address"
        );
        assertEq(conditions[1].offset, 36, "Second permission value offset should be 68");
        assertEq(uint8(conditions[1].rule), 1, "Second permission rule should be LESS_THAN_OR_EQUAL (1)");
        assertEq(conditions[1].value, bytes32(uint256(5)), "Second permission value should be 14");
    }

    function test_getSessionKeyData_RevertIf_SessionKeyDoesNotExist() public {
        address newSessionKey = address(0x1234567890123456789012345678901234567890);
        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        // when trying to get data for a non-existent session key
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(newSessionKey));
        // Attempt to get data for a non-existent session key
        skv.getSessionKeyData(newSessionKey);
    }

    function test_getSessionKeyPermissions_RevertIf_SessionKeyDoesNotExist() public {
        // Define a non-existent session key address
        address nonExistentSessionKey = address(0x123);
        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(nonExistentSessionKey));
        // Attempt to get permissions for the non-existent session key
        skv.getSessionKeyPermissions(nonExistentSessionKey);
    }

    function test_getSessionKeysByWallet() public {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Get wallet session keys
        address[] memory walletSessionKeys = skv.getSessionKeysByWallet();
        // Verify that the wallet session keys match the expected session key
        assertEq(walletSessionKeys.length, 1);
        assertEq(walletSessionKeys[0], sessionKey.pub);
    }

    function test_getSessionKeyByWallet_returnEmptyForWalletWithNoSessionKeys() public {
        // Get wallet session keys
        address[] memory walletSessionKeys = skv.getSessionKeysByWallet();
        // Verify that the wallet session keys match the expected session key
        assertEq(walletSessionKeys.length, 0);
    }

    function test_getUsesLeft_and_updateUses() public {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Verify that the session key has 10 uses initially
        assertEq(skv.getUsesLeft(sessionKey.pub, 0), 10);
        // Update the session key to have 5 uses and should emit event
        vm.expectEmit(true, true, false, false);
        emit SKV_PermissionUsesUpdated(sessionKey.pub, 0, 10, 5);
        skv.updateUses(sessionKey.pub, 0, 5);
        // Verify that the session key has 5 uses
        assertEq(skv.getUsesLeft(sessionKey.pub, 0), 5);
    }

    function test_updateUses_RevertIf_InvaildSessionKey() public {
        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(sessionKey.pub));
        // Attempt to update uses for a non-existent session key
        skv.updateUses(sessionKey.pub, 0, uint256(11));
    }

    function test_updateValidUntil() public {
        vm.startPrank(address(scw));
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Verify that the session key has 10 uses initially
        assertEq(skv.getSessionKeyData(sessionKey.pub).validUntil, validUntil);
        // Update the session key to have later timestamp and should emit event
        uint48 newValidUntil = uint48(block.timestamp + 14 days);
        vm.expectEmit(true, true, false, false);
        emit SKV_SessionKeyValidUntilUpdated(sessionKey.pub, address(scw), newValidUntil);
        skv.updateValidUntil(sessionKey.pub, newValidUntil);
        // Verify that the session key has 5 uses
        assertEq(skv.getSessionKeyData(sessionKey.pub).validUntil, newValidUntil);
        vm.stopPrank();
    }

    function test_updateValidUntil_RevertIf_SessionKeyDoesNotExist() public {
        // Define a non-existent session key address
        address nonExistentSessionKey = address(0x123);
        // Define a new validUntil timestamp
        uint48 newValidUntil = uint48(block.timestamp + 2 days);
        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        // when trying to update validUntil for a non-existent session key
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(nonExistentSessionKey));
        // Attempt to update validUntil for the non-existent session key
        skv.updateValidUntil(nonExistentSessionKey, newValidUntil);
    }

    function test_updateValidUntil_MultipleTimes() public {
        vm.startPrank(address(scw));
        // Define multiple new validUntil timestamps
        uint48[] memory newValidUntilList = new uint48[](3);
        newValidUntilList[0] = uint48(block.timestamp + 2 days);
        newValidUntilList[1] = uint48(block.timestamp + 3 days);
        newValidUntilList[2] = uint48(block.timestamp + 4 days);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Perform multiple updates to the validUntil timestamp
        for (uint256 i; i < newValidUntilList.length; ++i) {
            // Expect the SKV_SessionKeyValidUntilUpdated event to be emitted
            vm.expectEmit(true, true, false, true);
            emit SKV_SessionKeyValidUntilUpdated(sessionKey.pub, address(scw), newValidUntilList[i]);
            // Update the validUntil timestamp
            skv.updateValidUntil(sessionKey.pub, newValidUntilList[i]);
            // Retrieve updated session key data
            SessionData memory updatedData = skv.getSessionKeyData(sessionKey.pub);
            // Verify that the validUntil timestamp has been updated correctly
            assertEq(updatedData.validUntil, newValidUntilList[i], "ValidUntil should be updated correctly");
        }
        vm.stopPrank();
    }

    function test_addPermission() public {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Verify that session key is set up initially with one permission
        assertEq(skv.getSessionKeyPermissions(sessionKey.pub).length, 1);
        // Create a new permission and add to session key
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(14))});
        Permission memory newPerm = Permission({
            target: address(counter1),
            selector: TestCounter.changeCount.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: newConditions
        });
        // Expect event to be emitted
        vm.expectEmit(false, false, false, true);
        emit SKV_PermissionAdded(
            sessionKey.pub,
            address(scw),
            newPerm.target,
            newPerm.selector,
            newPerm.payableLimit,
            newPerm.uses,
            newPerm.paramConditions
        );
        skv.addPermission(sessionKey.pub, newPerm);
        // Verify that session key now has two permissions
        assertEq(skv.getSessionKeyPermissions(sessionKey.pub).length, 2);
    }

    function test_addPermission_RevertIf_SessionKeyDoesNotExist() public {
        // Define a non-existent session key address
        address nonExistentSessionKey = address(0x456);
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(14))});
        Permission memory newPerm = Permission({
            target: address(counter1),
            selector: TestCounter.changeCount.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: newConditions
        });
        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        // when trying to add a permission to a non-existent session key
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(nonExistentSessionKey));
        // Attempt to add a permission to the non-existent session key
        skv.addPermission(nonExistentSessionKey, newPerm);
    }

    function test_addPermission_RevertIf_InvalidTarget() public {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up new Permission to be added with invalid target
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(14))});
        Permission memory newPerm = Permission({
            target: address(0),
            selector: TestCounter.changeCount.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: newConditions
        });

        // Expect the function call to revert with SKV_InvalidPermissionData error
        // when trying to add a permission with an invalid (zero) target address
        _toRevert(
            SessionKeyValidator.SKV_InvalidPermissionData.selector,
            abi.encode(sessionKey.pub, address(0), TestCounter.changeCount.selector, 0, tenUses, newConditions)
        );
        // Attempt to add a permission with an invalid (zero) target address
        skv.addPermission(sessionKey.pub, newPerm);
    }

    function test_removePermission() public {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create a new permission and add to session key
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(14))});
        Permission memory newPerm = Permission({
            target: address(counter1),
            selector: TestCounter.changeCount.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: newConditions
        });
        skv.addPermission(sessionKey.pub, newPerm);
        // Verify that session key has two permissions
        assertEq(skv.getSessionKeyPermissions(sessionKey.pub).length, 2);
        // Index to be removed (0)
        uint256 idx;
        // Expect event to be emitted
        vm.expectEmit(false, false, false, true);
        emit SKV_PermissionRemoved(sessionKey.pub, address(scw), idx);
        skv.removePermission(sessionKey.pub, idx);
        // Verify that session key now has two permissions
        assertEq(skv.getSessionKeyPermissions(sessionKey.pub).length, 1);
    }

    function test_removePermission_RevertIf_SessionKeyDoesNotExist() public {
        // Define a non-existent session key address
        address nonExistentSessionKey = address(0x123);
        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        // when trying to remove a permission from a non-existent session key
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(nonExistentSessionKey));
        // Attempt to remove a permission from the non-existent session key
        skv.removePermission(nonExistentSessionKey, 0);
    }

    function test_removePermission_RevertIf_InvalidPermissionIndex() public {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Get an invalid index (equal to the number of permissions)
        uint256 invalidIndex = skv.getSessionKeyPermissions(sessionKey.pub).length;
        // Expect the function call to revert with SKV_InvalidPermissionIndex error
        // when trying to remove a permission with an invalid index
        _toRevert(SessionKeyValidator.SKV_InvalidPermissionIndex.selector, hex"");
        // Attempt to remove a permission using the invalid index
        skv.removePermission(sessionKey.pub, invalidIndex);
    }

    function test_removePermission_RemoveLastPermission() public {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Get the index of the last permission
        uint256 lastPermissionIndex = skv.getSessionKeyPermissions(sessionKey.pub).length - 1;
        // Remove the last permission
        skv.removePermission(sessionKey.pub, lastPermissionIndex);
        // Retrieve updated session key data
        Permission[] memory newPermissionData = skv.getSessionKeyPermissions(sessionKey.pub);
        // Verify the number of permissions has decreased by 1
        assertEq(newPermissionData.length, 0, "Number of permissions should decrease by 1");
    }

    function test_modifyPermission() public {
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        address newTarget = address(0x1234);
        bytes4 newSelector = bytes4(keccak256("newFunction()"));
        uint256 newPayableLimit = 200;
        uint256 newUses = 99;
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] = ParamCondition({offset: 0, rule: ComparisonRule.EQUAL, value: bytes32(uint256(42))});
        skv.modifyPermission(sessionKey.pub, 0, newTarget, newSelector, newPayableLimit, newUses, newConditions);
        Permission[] memory modifiedPerms = skv.getSessionKeyPermissions(sessionKey.pub);
        assertEq(modifiedPerms[0].target, newTarget);
        assertEq(modifiedPerms[0].selector, newSelector);
        assertEq(modifiedPerms[0].payableLimit, newPayableLimit);
        assertEq(modifiedPerms[0].uses, newUses);
        assertEq(modifiedPerms[0].paramConditions.length, 1);
        assertEq(modifiedPerms[0].paramConditions[0].offset, 0);
        assertEq(uint8(modifiedPerms[0].paramConditions[0].rule), uint8(ComparisonRule.EQUAL));
        assertEq(modifiedPerms[0].paramConditions[0].value, bytes32(uint256(42)));
    }

    function test_modifyPermission_PartialUpdate() public {
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Store the original paramConditions
        ParamCondition[] memory originalConditions = skv.getSessionKeyPermissions(sessionKey.pub)[0].paramConditions;
        address newTarget = address(0x1234);
        bytes4 newSelector = bytes4(keccak256("newFunction()"));
        uint256 newPayableLimit = 200;
        uint256 newUses = 99;
        // Modify the permission with partial updates
        skv.modifyPermission(
            sessionKey.pub,
            0,
            newTarget,
            newSelector,
            newPayableLimit,
            newUses,
            new ParamCondition[](0) // Empty array to keep paramConditions unchanged
        );
        Permission[] memory modifiedPerms = skv.getSessionKeyPermissions(sessionKey.pub);
        // Assert that the specified fields have been updated
        assertEq(modifiedPerms[0].target, newTarget);
        assertEq(modifiedPerms[0].selector, newSelector);
        assertEq(modifiedPerms[0].payableLimit, newPayableLimit);
        assertEq(modifiedPerms[0].uses, newUses);
        // Assert that paramConditions have remained unchanged
        assertEq(modifiedPerms[0].paramConditions.length, originalConditions.length);
        for (uint256 i; i < originalConditions.length; ++i) {
            assertEq(modifiedPerms[0].paramConditions[i].offset, originalConditions[i].offset);
            assertEq(uint8(modifiedPerms[0].paramConditions[i].rule), uint8(originalConditions[i].rule));
            assertEq(modifiedPerms[0].paramConditions[i].value, originalConditions[i].value);
        }
    }

    function test_modifyPermission_NonExistentSessionKey() public {
        address nonExistentSessionKey = address(0xdead);
        _toRevert(SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector, abi.encode(nonExistentSessionKey));
        skv.modifyPermission(
            nonExistentSessionKey,
            0,
            address(0x1234),
            bytes4(keccak256("newFunction()")),
            200,
            tenUses,
            new ParamCondition[](0)
        );
    }

    function test_modifyPermission_InvalidIndex() public {
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        uint256 invalidIndex = perms.length;
        _toRevert(SessionKeyValidator.SKV_InvalidPermissionIndex.selector, hex"");
        skv.modifyPermission(
            sessionKey.pub,
            invalidIndex,
            address(0x1234),
            bytes4(keccak256("newFunction()")),
            200,
            tenUses,
            new ParamCondition[](0)
        );
    }

    function test_validateUserOp_Single() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation parameters
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode the call data for the counter function
        bytes memory callData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, uint256(4), true);
        // Set up a single user operation
        PackedUserOperation memory op =
            _setupSingleUserOp(address(skv), address(counter1), 0, callData, evs, sessionKey);
        // Expect event emit
        vm.expectEmit(false, false, false, true);
        emit ReceivedMultiTypeCall(alice.pub, 4, true);
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_validateUserOp_Single_Native() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create and add new Permission for session key
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] = ParamCondition({offset: 0, rule: ComparisonRule.NOT_EQUAL, value: 0});
        Permission memory newPermission = Permission({
            target: bob.pub,
            selector: bytes4(0),
            payableLimit: 10 wei,
            uses: tenUses,
            paramConditions: newConditions
        });
        skv.addPermission(sessionKey.pub, newPermission);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation for native transfer
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Set up a single user operation
        PackedUserOperation memory op = _setupSingleUserOp(address(skv), bob.pub, 9 wei, hex"", evs, sessionKey); // Execute the user operation
        _executeUserOp(op);
        // Verify that the receiver's balance has been updated correctly
        // Bob already has balance of 100 ether
        assertEq(bob.pub.balance, 100 ether + 9 wei, "Receiver balance should match transferred amount");
        // Verify that the session key uses has decreased
        uint256 usesLeft = skv.getUsesLeft(sessionKey.pub, 0);
        usesLeft = skv.getUsesLeft(sessionKey.pub, 1);
        assertEq(usesLeft, tenUses - 1, "Session key uses should be decremented");
    }

    function test_validateUserOp_Single_CallPayable() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create and add new Permission for session key
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] = ParamCondition({offset: 4, rule: ComparisonRule.GREATER_THAN, value: bytes32(uint256(7579))});
        Permission memory newPermission = Permission({
            target: address(counter1),
            selector: TestCounter.payableCall.selector,
            payableLimit: 87 wei,
            uses: tenUses,
            paramConditions: newConditions
        });
        skv.addPermission(sessionKey.pub, newPermission);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation for native transfer
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode the call data for the counter function
        bytes memory callData = abi.encodeWithSelector(TestCounter.payableCall.selector, uint256(7580));
        // Set up a single user operation
        PackedUserOperation memory op =
            _setupSingleUserOp(address(skv), address(counter1), 86 wei, callData, evs, sessionKey);
        // Execute the user operation
        vm.expectEmit(false, false, false, true);
        emit ReceivedPayableCall(uint256(7580), 86 wei);
        _executeUserOp(op);
        // Verify that the receiver's balance has been updated correctly
        assertEq(counter1.getCount(), uint256(7580), "Counter1 count value should be 7580");
    }

    function test_validateUserOp_Single_RevertIf_NoPermissions() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Remove all permissions from the session key (only initialized with one)
        skv.removePermission(sessionKey.pub, 0);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation parameters
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode the call data for the counter function
        bytes memory callData = abi.encodeWithSelector(TestCounter.changeCount.selector, 1 ether);
        // Set up a single user operation
        PackedUserOperation memory op =
            _setupSingleUserOp(address(skv), address(counter1), 0, callData, evs, sessionKey);
        // Expect the operation to revert due to signature error (no permissions)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Attempt to execute the user operation
        _executeUserOp(op);
    }

    function test_validateUserOp_Single_RevertIf_InvalidSessionKey() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation parameters
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode the call data for the counter function
        bytes memory callData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, 4);
        // Set up a single user operation
        PackedUserOperation memory op =
            _setupSingleUserOp(address(skv), address(counter1), 0, callData, evs, sessionKey);
        // Disable the session key
        skv.disableSessionKey(sessionKey.pub);
        // Expect the operation to revert due to signature error (invalid session key)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Attempt to execute the user operations
        _executeUserOp(op);
    }

    function test_validateUserOp_Single_RevertIf_InvalidTarget() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation parameters
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode the call data for the counter function
        bytes memory callData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, 4);
        // Set up a single user operation
        PackedUserOperation memory op = _setupSingleUserOp(address(skv), alice.pub, 0, callData, evs, sessionKey);
        // Expect the operation to revert due to signature error (invalid target)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Attempt to execute the user operations
        _executeUserOp(op);
    }

    function test_validateUserOp_Single_RevertIf_InvalidFunctionSelector() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation parameters
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode invalid call data with an unauthorized function selector
        bytes memory invalidData = abi.encodeWithSelector(TestCounter.invalid.selector, alice.pub, uint256(1 ether));
        // Set up a single user operation
        PackedUserOperation memory op =
            _setupSingleUserOp(address(skv), address(counter1), 0, invalidData, evs, sessionKey);
        // Expect the operation to revert due to signature error (invalid function selector)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Attempt to execute the user operations
        _executeUserOp(op);
    }

    function test_validateUserOp_Single_RevertIf_NoUsesLeft() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation parameters
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode the call data for the counter function
        bytes memory callData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, 4);
        // Set up a single user operation
        PackedUserOperation memory op =
            _setupSingleUserOp(address(skv), address(counter1), 0, callData, evs, sessionKey);
        // Set the remaining uses of the session key to 0
        skv.updateUses(sessionKey.pub, 0, 0);
        // Expect the operation to revert due to signature error (no uses left)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Attempt to execute the user operations
        _executeUserOp(op);
    }

    function test_validateUserOp_Single_MaximumUsesForPermissionExceeded() public validatorInstalled {
        uint256 maxUses = 3;
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        perms[0].uses = maxUses;
        harness.enableSessionKey(sd, perms);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation parameters
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        bytes memory callData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, 4, false);
        PackedUserOperation memory op;
        for (uint256 i; i < maxUses; ++i) {
            // Set up a single user operation
            op = _setupSingleUserOp(address(skv), address(counter1), 0, callData, evs, sessionKey);
            (bool success,,) = harness.exposed_validateSessionKeyParams(sessionKey.pub, op, evs);
            assertTrue(success, "Permission should be valid");
        }
        // Set up a single user operation
        op = _setupSingleUserOp(address(skv), address(counter1), 0, callData, evs, sessionKey);
        (bool finalSuccess,,) = harness.exposed_validateSessionKeyParams(sessionKey.pub, op, evs);
        assertFalse(finalSuccess, "Permission should be invalid after maximum uses");
    }

    function test_validateUserOp_Single_RevertIf_Paused() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation parameters
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode the call data for the counter function
        bytes memory callData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, 4);
        // Set up a single user operation
        PackedUserOperation memory op =
            _setupSingleUserOp(address(skv), address(counter1), 0, callData, evs, sessionKey);
        // Set the remaining uses of the session key to 0
        skv.toggleSessionKeyPause(sessionKey.pub);
        // Expect the operation to revert due to signature error (no uses left)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Attempt to execute the user operations
        _executeUserOp(op);
    }

    function test_validateUserOp_Single_Native_RevertIf_InvalidAmount() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create and add new Permission for session key
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] = ParamCondition({offset: 0, rule: ComparisonRule.NOT_EQUAL, value: 0});
        Permission memory newPermission = Permission({
            target: bob.pub,
            selector: bytes4(0),
            payableLimit: 10 wei,
            uses: tenUses,
            paramConditions: newConditions
        });
        skv.addPermission(sessionKey.pub, newPermission);

        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation for native transfer
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Set up a single user operation
        PackedUserOperation memory op = _setupSingleUserOp(address(skv), bob.pub, 11 wei, hex"", evs, sessionKey);
        // Expect the operation to revert due to signature error (invalid amount)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Attempt to execute the user operation
        _executeUserOp(op);
    }

    function test_validateUserOp_Batch() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create a new permission and add to session key
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(14))});
        Permission memory newPerm = Permission({
            target: address(counter2),
            selector: TestCounter.changeCount.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: newConditions
        });
        skv.addPermission(sessionKey.pub, newPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](2);
        // Set up execution validations for changeCount and multiTypeCall functions
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        evs[1] = _getExecutionValidation(uint48(2), uint48(4));
        // Encode call data for changeCount and multiTypeCall functions
        bytes memory callData1 = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, uint256(4), true);
        bytes memory callData2 = abi.encodeWithSelector(TestCounter.changeCount.selector, uint256(13));
        // Create an array of executions
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: address(counter1), value: 0, callData: callData1});
        executions[1] = Execution({target: address(counter2), value: 0, callData: callData2});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect event emit
        vm.expectEmit(false, false, false, true);
        emit ReceivedMultiTypeCall(alice.pub, 4, true);
        // Execute the user operation
        _executeUserOp(op);
        // Verify that both counters have been updated correctly
        assertEq(counter2.getCount(), uint256(13), "Counter should be updated");
    }

    function test_validateUserOp_Batch_PayableCallAndNative() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create a new permission for native transfer and add to session key
        ParamCondition[] memory nativeConditions = new ParamCondition[](1);
        nativeConditions[0] = ParamCondition({offset: 0, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: 0});
        Permission memory nativePerm = Permission({
            target: bob.pub,
            selector: bytes4(0),
            payableLimit: 3 wei,
            uses: tenUses,
            paramConditions: nativeConditions
        });
        skv.addPermission(sessionKey.pub, nativePerm);
        // Create a new permission for payable call and add to session key
        ParamCondition[] memory payableConditions = new ParamCondition[](1);
        payableConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(1))});
        Permission memory payablePerm = Permission({
            target: address(counter2),
            selector: TestCounter.payableCall.selector,
            payableLimit: 1 wei,
            uses: tenUses,
            paramConditions: payableConditions
        });
        skv.addPermission(sessionKey.pub, payablePerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](2);
        // Set up execution validations for payableCall and native transfer functions
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        evs[1] = _getExecutionValidation(uint48(2), uint48(4));
        // Encode call data for payableCall function
        bytes memory payableData = abi.encodeWithSelector(TestCounter.payableCall.selector, uint256(1));
        // Create an array of executions
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: bob.pub, value: 3 wei, callData: ""});
        executions[1] = Execution({target: address(counter2), value: 1 wei, callData: payableData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Execute the user operation
        _executeUserOp(op);
        // Verify that both counters have been updated correctly
        assertEq(counter2.getCount(), uint256(1), "Counter should be updated");
        // Bob has a beginning 100 ether balance
        assertEq(bob.pub.balance, 100 ether + 3 wei, "Receiver balance should be increased by 3 wei");
    }

    function test_validateUserOp_Batch_CallAndNative() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create a new permission for native transfer and add to session key
        ParamCondition[] memory nativeConditions = new ParamCondition[](1);
        nativeConditions[0] = ParamCondition({offset: 0, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: 0});
        Permission memory nativePerm = Permission({
            target: bob.pub,
            selector: bytes4(0),
            payableLimit: 13 wei,
            uses: tenUses,
            paramConditions: nativeConditions
        });
        skv.addPermission(sessionKey.pub, nativePerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](2);
        // Set up execution validations for call and native executions
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        evs[1] = _getExecutionValidation(uint48(2), uint48(5));
        // Encode call data for multiTypeCall function
        bytes memory callData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, 5, false);
        // Create an array of executions
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: address(counter1), value: 0, callData: callData});
        executions[1] = Execution({target: bob.pub, value: 13 wei, callData: ""});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect event emit
        vm.expectEmit(false, false, false, true);
        emit ReceivedMultiTypeCall(alice.pub, 5, false);
        // Execute the user operation
        _executeUserOp(op);
        // Verify receiver received funds (Bob has 100 ether starting balance)
        assertEq(bob.pub.balance, 100 ether + 13 wei, "Receiver balance should be increaed by 13 wei");
    }

    function test_validateUserOp_Batch_DecreasesPermissionUsesSamePermission() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](3);
        // Set up execution validations for changeCount and multiTypeCall functions
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        evs[1] = _getExecutionValidation(uint48(2), uint48(4));
        evs[2] = _getExecutionValidation(uint48(2), uint48(4));
        // Encode call data for changeCount and multiTypeCall functions
        bytes memory callData1 = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, uint256(4), true);
        bytes memory callData2 = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, uint256(3), true);
        bytes memory callData3 = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, uint256(2), true);
        // Create an array of executions
        Execution[] memory executions = new Execution[](3);
        executions[0] = Execution({target: address(counter1), value: 0, callData: callData1});
        executions[1] = Execution({target: address(counter1), value: 0, callData: callData2});
        executions[2] = Execution({target: address(counter1), value: 0, callData: callData3});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Execute the user operation
        _executeUserOp(op);
        // Validate permission uses updates (10 - 3 = 7)
        assertEq(skv.getUsesLeft(sessionKey.pub, 0), 7, "Should have decreased by 3");
    }

    function test_validateUserOp_Batch_DecreasesPermissionUsesMultiplePermissions() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create a new permission and add to session key
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(14))});
        Permission memory newPerm = Permission({
            target: address(counter2),
            selector: TestCounter.changeCount.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: newConditions
        });
        skv.addPermission(sessionKey.pub, newPerm);
        // Check session key now has 2 permissions
        Permission[] memory permissions = skv.getSessionKeyPermissions(sessionKey.pub);
        assertEq(permissions.length, 2, "Session key should have 2 permissions");
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](3);
        // Set up execution validations for changeCount and multiTypeCall functions
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        evs[1] = _getExecutionValidation(uint48(2), uint48(4));
        evs[2] = _getExecutionValidation(uint48(2), uint48(3));
        // Encode call data for changeCount and multiTypeCall functions
        bytes memory callData1 = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, uint256(4), true);
        bytes memory callData2 =
            abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, uint256(2), false);
        bytes memory callData3 = abi.encodeWithSelector(TestCounter.changeCount.selector, uint256(13));
        // Create an array of executions
        Execution[] memory executions = new Execution[](3);
        executions[0] = Execution({target: address(counter1), value: 0, callData: callData1});
        executions[1] = Execution({target: address(counter1), value: 0, callData: callData2});
        executions[2] = Execution({target: address(counter2), value: 0, callData: callData3});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect event emit
        // vm.expectEmit(true, false, false, true);
        // emit SKV_PermissionUsed(sessionKey.pub, perms[0], 10, 9);
        // vm.expectEmit(true, false, false, true);
        // emit SKV_PermissionUsed(sessionKey.pub, newPerm, 10, 9);
        // vm.expectEmit(true, false, false, true);
        // emit SKV_PermissionUsed(sessionKey.pub, newPerm, 9, 8);
        // NOTE: It does emit these events in the stack trace but
        // due to UserOp its not picking them up in the test correctly
        // Execute the user operation
        _executeUserOp(op);
        // Verify that both counters have been updated correctly
        assertEq(counter2.getCount(), uint256(13), "Counter should be updated");
        // Validate permission uses updates
        assertEq(skv.getUsesLeft(sessionKey.pub, 0), 8, "Should have decreased by 2");
        assertEq(skv.getUsesLeft(sessionKey.pub, 1), 9, "Should have decreased by 1");
    }

    function test_validateUserOp_Batch_RevertIf_InvalidTarget() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create a new permission for changeCount transfer and add to session key
        ParamCondition[] memory countConditions = new ParamCondition[](1);
        countConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: bytes32(uint256(99))});
        Permission memory countPerm = Permission({
            target: address(counter2),
            selector: TestCounter.changeCount.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: countConditions
        });
        skv.addPermission(sessionKey.pub, countPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](2);
        // Set up execution validations for multiTypeCall and changeCount functions
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        evs[1] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for multiTypeCall and changeCount functions
        bytes memory multiData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, 4, true);
        bytes memory countData = abi.encodeWithSelector(TestCounter.changeCount.selector, 100);
        // Create an array of executions with an invalid target
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: address(counter1), value: 0, callData: multiData});
        executions[1] = Execution({
            target: alice.pub, // Invalid target
            value: 0,
            callData: countData
        });
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);

        // Expect the operation to revert due to signature error (invalid target)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Attempt to execute the user operations
        _executeUserOp(op);
    }

    function test_validateUserOp_Batch_RevertIf_InvalidFunctionSelector() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validations for invalid function
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode invalid call data with unauthorized function selector
        bytes memory invalidData = abi.encodeWithSelector(TestCounter.invalid.selector, alice.pub, uint256(1 ether));
        // Create an array of executions with one valid and one invalid function call
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(counter2), value: 0, callData: invalidData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (invalid function selector)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Attempt to execute the user operations
        _executeUserOp(op);
    }

    function test_validateUserOp_RevertIf_SessionKeyNotYetActive() public validatorInstalled {
        // Define validity period for the session key
        uint48 _validAfter = uint48(3);
        uint48 _validUntil = uint48(4);
        // Set up a session key with future validity period
        SessionData memory sd =
            SessionData({sessionKey: sessionKey.pub, validAfter: _validAfter, validUntil: _validUntil, live: false});
        ParamCondition[] memory conditions = new ParamCondition[](2);
        conditions[0] = ParamCondition({
            offset: 4,
            rule: ComparisonRule.EQUAL,
            value: bytes32(uint256(uint160(address(alice.pub))))
        });
        conditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(5))});
        Permission[] memory perms = new Permission[](1);
        perms[0] = Permission({
            target: address(counter1),
            selector: TestCounter.multiTypeCall.selector,
            payableLimit: 100 wei,
            uses: tenUses,
            paramConditions: conditions
        });
        skv.enableSessionKey(sd, perms);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation parameters
        evs[0] = _getExecutionValidation(uint48(2), _validUntil);
        // Encode the call data for the counter function
        bytes memory callData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, 4, true);
        // Set up a single user operation
        PackedUserOperation memory op =
            _setupSingleUserOp(address(skv), address(counter1), 0, callData, evs, sessionKey);
        // Expect the operation to revert due to signature error (session key not yet active)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Attempt to execute the user operation
        _executeUserOp(op);
    }

    function test_validateUserOp_RevertIf_SessionKeyExpired() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Move the block timestamp past the expiration time
        vm.warp(block.timestamp + 1 days + 1);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation parameters
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode the call data for the counter function
        bytes memory callData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, 4, true);
        // Set up a single user operation
        PackedUserOperation memory op =
            _setupSingleUserOp(address(skv), address(counter1), 0, callData, evs, sessionKey);
        // Expect the operation to revert due to expired session key
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, "AA22 expired or not due"));
        // Attempt to execute the user operation
        _executeUserOp(op);
    }

    function test_validateUserOp_RevertIf_InvalidSigner() public {
        vm.deal(eoa.pub, 10 ether);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Move the block timestamp past the expiration time
        vm.warp(block.timestamp + 1 days + 1);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        // Set up execution validation parameters
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode the call data for the counter function
        bytes memory callData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, 4, true);
        // Set up a single user operation
        PackedUserOperation memory op =
            _setupSingleUserOp(address(skv), address(counter1), 0, callData, evs, sessionKey);
        // Empty signature
        op.signature = hex"";
        // Get hash of UserOp
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = bytes.concat(_ethSign(hash, eoa), abi.encode(evs));
        // Expect the operation to revert due to expired session key
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Attempt to execute the user operation
        _executeUserOp(op);
    }

    // /*//////////////////////////////////////////////////////////////
    //                   TESTS (INTERNAL FUNCTIONS)
    // //////////////////////////////////////////////////////////////*/

    function test_exposed_ExtractExecutionValidationAndSignature() public validatorInstalled {
        // Set up an ExecutionValidation struct
        ExecutionValidation memory ev =
            ExecutionValidation({validAfter: uint48(block.timestamp), validUntil: uint48(block.timestamp + 1 days)});
        // Set up signature components
        bytes memory sig = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));
        // Create and encode an array of ExecutionValidations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = ev;
        // Combine signature components and encoded ExecutionValidations
        bytes memory fullSig = bytes.concat(sig, abi.encode(evs));
        // Call the function to extract ExecutionValidation and signature components
        (ExecutionValidation[] memory resEvs, bytes32 resR, bytes32 resS, uint8 resV) =
            harness.exposed_extractExecutionValidationAndSignature(fullSig);
        // Assert the correctness of the extracted ExecutionValidation
        assertEq(resEvs.length, 1, "Incorrect number of ExecutionValidation");
        assertEq(resEvs[0].validAfter, ev.validAfter, "Incorrect validAfter");
        assertEq(resEvs[0].validUntil, ev.validUntil, "Incorrect validUntil");
        // Assert the correctness of the extracted signature components
        assertEq(resR, bytes32(uint256(1)), "Incorrect r value");
        assertEq(resS, bytes32(uint256(2)), "Incorrect s value");
        assertEq(resV, uint8(27), "Incorrect v value");
    }

    function test_exposed_validatePermission() public validatorInstalled {
        // Set up a session key with future validity period
        SessionData memory sd =
            SessionData({sessionKey: sessionKey.pub, validAfter: validAfter, validUntil: validUntil, live: false});
        ParamCondition[] memory conditions = new ParamCondition[](2);
        conditions[0] = ParamCondition({
            offset: 4,
            rule: ComparisonRule.EQUAL,
            value: bytes32(uint256(uint160(address(alice.pub))))
        });
        conditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(5))});
        Permission[] memory perms = new Permission[](1);
        perms[0] = Permission({
            target: address(counter1),
            selector: TestCounter.multiTypeCall.selector,
            payableLimit: 100 wei,
            uses: tenUses,
            paramConditions: conditions
        });
        harness.enableSessionKey(sd, perms); // Set up execution validation for a valid call
        ExecutionValidation memory ev = _getExecutionValidation(uint48(1), uint48(3));
        bytes memory callData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, 4, true);
        // Test valid permission
        bool result = harness.exposed_validatePermission(address(scw), sd, ev, address(counter1), 0, callData);
        assertTrue(result, "Permission should be valid");
        // Test invalid target
        result = harness.exposed_validatePermission(address(scw), sd, ev, address(counter2), 0, callData);
        assertFalse(result, "Permission should be invalid due to wrong target");
        // Test not compliance with ComparisonRule
        callData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, 6, true);
        result = harness.exposed_validatePermission(address(scw), sd, ev, address(counter1), 0, callData);
        assertFalse(result, "Permission should be invalid due to exceeded spending limit");
        // Test native transfer
        ParamCondition[] memory nativeConditions = new ParamCondition[](1);
        nativeConditions[0] = ParamCondition({offset: 0, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: 0});
        Permission memory nativePerm = Permission({
            target: bob.pub,
            selector: bytes4(0),
            payableLimit: 13 wei,
            uses: tenUses,
            paramConditions: nativeConditions
        });
        harness.addPermission(sessionKey.pub, nativePerm);
        ExecutionValidation memory nativeEv = _getExecutionValidation(uint48(1), uint48(3));
        bytes memory emptyCallData = new bytes(0);
        result = harness.exposed_validatePermission(address(scw), sd, nativeEv, bob.pub, 13 wei, emptyCallData);
        assertTrue(result, "Native transfer should be valid");
    }

    function test_exposed_validateSessionKeyParams() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        harness.enableSessionKey(sd, perms);
        // Set up new Permission and add to session key
        ParamCondition[] memory nativeConditions = new ParamCondition[](1);
        nativeConditions[0] = ParamCondition({offset: 0, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: 0});
        Permission memory nativePerm = Permission({
            target: bob.pub,
            selector: bytes4(0),
            payableLimit: 13 wei,
            uses: tenUses,
            paramConditions: nativeConditions
        });
        harness.addPermission(sessionKey.pub, nativePerm);
        // Create execution validations for two different operations
        ExecutionValidation[] memory evs = new ExecutionValidation[](2);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        evs[1] = _getExecutionValidation(uint48(2), uint48(6));
        // Encode the call data for the counter function
        bytes memory callData = abi.encodeWithSelector(TestCounter.multiTypeCall.selector, alice.pub, 4, true);
        // Create execution structs for the batch operation
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: address(counter1), value: 0, callData: callData});
        executions[1] = Execution({target: bob.pub, value: 13 wei, callData: ""});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Call the exposed function to validate session key parameters
        (bool success, uint48 _validAfter, uint48 _validUntil) =
            harness.exposed_validateSessionKeyParams(sessionKey.pub, op, evs);
        // Assert that the validation succeeds
        assertTrue(success, "Validation should succeed");
        // Assert that validAfter matches the lowest value from executions
        assertEq(_validAfter, uint48(1), "ValidAfter should match lowest");
        // Assert that validUntil matches the highest value from executions
        assertEq(_validUntil, uint48(6), "ValidUntil should match highest");
    }

    function test_exposed_validateSessionKeyParams_InvalidCallType() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        harness.enableSessionKey(sd, perms);
        // Create a user operation with an invalid call type
        bytes memory callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encode(CALLTYPE_STATIC, EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00)),
                ExecutionLib.encodeSingle(alice.pub, 1 wei, "")
            )
        );
        PackedUserOperation memory op = _createUserOp(address(scw), address(skv));
        op.callData = callData;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = _sign(hash, sessionKey);
        // Create execution validation
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(0, 0);
        // Call the exposed function to validate session key parameters
        (bool success, uint48 _validAfter, uint48 _validUntil) =
            harness.exposed_validateSessionKeyParams(sessionKey.pub, op, evs);
        // Assert that the validation fails
        assertFalse(success, "Validation should fail");
        assertEq(_validAfter, 0, "ValidAfter should be 0");
        assertEq(_validUntil, 0, "ValidUntil should be 0");
    }

    // _checkCondition internal function logic check tests
    function test_exposed_checkCondition_testEqualCondition() public {
        bytes32 param = bytes32(uint256(10));
        bytes32 value = bytes32(uint256(10));
        bool result = harness.exposed_checkCondition(param, value, ComparisonRule.EQUAL);
        assertTrue(result);
        param = bytes32(uint256(11));
        result = harness.exposed_checkCondition(param, value, ComparisonRule.EQUAL);
        assertFalse(result);
    }

    function test_exposed_checkCondition_testGreaterThanCondition() public {
        bytes32 param = bytes32(uint256(11));
        bytes32 value = bytes32(uint256(10));
        bool result = harness.exposed_checkCondition(param, value, ComparisonRule.GREATER_THAN);
        assertTrue(result);
        param = bytes32(uint256(10));
        result = harness.exposed_checkCondition(param, value, ComparisonRule.GREATER_THAN);
        assertFalse(result);
    }

    function test_exposed_checkCondition_testLessThanCondition() public {
        bytes32 param = bytes32(uint256(9));
        bytes32 value = bytes32(uint256(10));
        bool result = harness.exposed_checkCondition(param, value, ComparisonRule.LESS_THAN);
        assertTrue(result);
        param = bytes32(uint256(10));
        result = harness.exposed_checkCondition(param, value, ComparisonRule.LESS_THAN);
        assertFalse(result);
    }

    function test_exposed_checkCondition_testGreaterThanOrEqualCondition() public {
        bytes32 param = bytes32(uint256(10));
        bytes32 value = bytes32(uint256(10));
        bool result = harness.exposed_checkCondition(param, value, ComparisonRule.GREATER_THAN_OR_EQUAL);
        assertTrue(result);
        param = bytes32(uint256(11));
        result = harness.exposed_checkCondition(param, value, ComparisonRule.GREATER_THAN_OR_EQUAL);
        assertTrue(result);

        param = bytes32(uint256(9));
        result = harness.exposed_checkCondition(param, value, ComparisonRule.GREATER_THAN_OR_EQUAL);
        assertFalse(result);
    }

    function test_exposed_checkCondition_testLessThanOrEqualCondition() public {
        bytes32 param = bytes32(uint256(10));
        bytes32 value = bytes32(uint256(10));
        bool result = harness.exposed_checkCondition(param, value, ComparisonRule.LESS_THAN_OR_EQUAL);
        assertTrue(result);
        param = bytes32(uint256(9));
        result = harness.exposed_checkCondition(param, value, ComparisonRule.LESS_THAN_OR_EQUAL);
        assertTrue(result);

        param = bytes32(uint256(11));
        result = harness.exposed_checkCondition(param, value, ComparisonRule.LESS_THAN_OR_EQUAL);
        assertFalse(result);
    }

    function test_exposed_checkCondition_testNotEqualCondition() public {
        bytes32 param = bytes32(uint256(11));
        bytes32 value = bytes32(uint256(10));
        bool result = harness.exposed_checkCondition(param, value, ComparisonRule.NOT_EQUAL);
        assertTrue(result);
        param = bytes32(uint256(10));
        result = harness.exposed_checkCondition(param, value, ComparisonRule.NOT_EQUAL);
        assertFalse(result);
    }

    /*//////////////////////////////////////////////////////////////
                           ERC20 BATCH TEST
    //////////////////////////////////////////////////////////////*/

    function test_batchExecutionERC20() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Mint ERC20 tokens to the wallet
        uint256 mintAmount = 1000 * 10 ** 18; // 1000 tokens
        usdt.mint(address(scw), mintAmount);
        // Create permissions for ERC20 approve and transferFrom
        ParamCondition[] memory approveConditions = new ParamCondition[](2);
        approveConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        approveConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(mintAmount)});
        Permission memory approvePerm = Permission({
            target: address(usdt),
            selector: IERC20.approve.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: approveConditions
        });
        ParamCondition[] memory transferFromConditions = new ParamCondition[](3);
        transferFromConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        transferFromConditions[1] = ParamCondition({
            offset: 36,
            rule: ComparisonRule.EQUAL,
            value: bytes32(uint256(uint160(address(alice.pub))))
        });
        transferFromConditions[2] =
            ParamCondition({offset: 68, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(mintAmount)});
        Permission memory transferFromPerm = Permission({
            target: address(usdt),
            selector: IERC20.transferFrom.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: transferFromConditions
        });
        skv.addPermission(sessionKey.pub, approvePerm);
        skv.addPermission(sessionKey.pub, transferFromPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](2);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        evs[1] = _getExecutionValidation(uint48(2), uint48(4));
        // Encode call data for approve and transferFrom functions
        uint256 transferAmount = 500 * 10 ** 18; // 500 tokens
        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, address(scw), transferAmount);
        bytes memory transferFromData =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(scw), alice.pub, transferAmount);
        // Create an array of executions
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: address(usdt), value: 0, callData: approveData});
        executions[1] = Execution({target: address(usdt), value: 0, callData: transferFromData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Execute the user operation
        _executeUserOp(op);
        // Verify that the receiver's balance has been updated correctly
        // Alice had starting balance of 100 USDT
        assertEq(usdt.balanceOf(alice.pub), 100e18 + transferAmount, "Receiver should have received the tokens");
        assertEq(usdt.balanceOf(address(scw)), mintAmount - transferAmount, "Wallet balance should be reduced");
    }

    /*//////////////////////////////////////////////////////////////
                         UNISWAP V2 SWAP TESTING
    //////////////////////////////////////////////////////////////*/

    function test_uniswapV2_swapExactTokensForTokens() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV2), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV2), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        ParamCondition[] memory swapConditions = new ParamCondition[](5);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        swapConditions[2] =
            ParamCondition({offset: 196, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[3] =
            ParamCondition({offset: 228, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[4] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV2),
            selector: TestUniswapV2.swapExactTokensForTokens.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        address[] memory paths = new address[](2);
        paths[0] = address(dai);
        paths[1] = address(link);
        bytes memory callData = abi.encodeWithSelector(
            TestUniswapV2.swapExactTokensForTokens.selector, 10e18, 10e18, paths, address(scw), block.timestamp + 1000
        );
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV2), value: 0, callData: callData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        vm.expectEmit(false, false, false, true);
        emit MockUniswapExchangeEvent(10e18, 11e18, address(dai), address(link));
        // Execute the user operation
        _executeUserOp(op);
        assertEq(dai.balanceOf(address(scw)), 90e18, "Wallet DAI balance should decrease by 10 ether");
        assertEq(link.balanceOf(address(scw)), 11e18, "Wallet LINK balance should increase by 11 ether");
    }

    function test_uniswapV2_swapExactTokensForTokens_RevertIf_IncorrectAmountIn() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV2), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV2), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        ParamCondition[] memory swapConditions = new ParamCondition[](5);
        // Should fail on this condition
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        swapConditions[2] =
            ParamCondition({offset: 196, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[3] =
            ParamCondition({offset: 228, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[4] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV2),
            selector: TestUniswapV2.swapExactTokensForTokens.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        address[] memory paths = new address[](2);
        paths[0] = address(dai);
        paths[1] = address(link);
        bytes memory callData = abi.encodeWithSelector(
            TestUniswapV2.swapExactTokensForTokens.selector,
            // Invalid amountIn value
            11e18,
            10e18,
            paths,
            address(scw),
            block.timestamp + 1000
        );
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV2), value: 0, callData: callData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (invalid amountIn)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV2_swapExactTokensForTokens_RevertIf_IncorrectAmountOut() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV2), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV2), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        ParamCondition[] memory swapConditions = new ParamCondition[](5);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        // Should fail on this condition
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        swapConditions[2] =
            ParamCondition({offset: 196, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[3] =
            ParamCondition({offset: 228, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[4] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV2),
            selector: TestUniswapV2.swapExactTokensForTokens.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        address[] memory paths = new address[](2);
        paths[0] = address(dai);
        paths[1] = address(link);
        bytes memory swapData = abi.encodeWithSelector(
            TestUniswapV2.swapExactTokensForTokens.selector,
            11e18,
            // Invalid amountIn value
            9e18,
            paths,
            address(scw),
            block.timestamp + 1000
        );
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV2), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (invalid amountIn)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV2_swapExactTokensForTokens_RevertIf_incorrectFirstPath() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV2), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV2), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        ParamCondition[] memory swapConditions = new ParamCondition[](5);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        // Should fail on this condition
        swapConditions[2] =
            ParamCondition({offset: 196, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[3] =
            ParamCondition({offset: 228, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[4] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV2),
            selector: TestUniswapV2.swapExactTokensForTokens.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        address[] memory paths = new address[](2);
        // Add invalid first path address
        paths[0] = address(weth);
        paths[1] = address(link);
        bytes memory swapData = abi.encodeWithSelector(
            TestUniswapV2.swapExactTokensForTokens.selector,
            11e18,
            9e18,
            // Invalid first path address
            paths,
            address(scw),
            block.timestamp + 1000
        );
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV2), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (invalid amountIn)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV2_swapExactTokensForTokens_RevertIf_IncorrectSecondPath() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV2), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV2), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        ParamCondition[] memory swapConditions = new ParamCondition[](5);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        swapConditions[2] =
            ParamCondition({offset: 196, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        // Should fail on this condition
        swapConditions[3] =
            ParamCondition({offset: 228, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[4] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV2),
            selector: TestUniswapV2.swapExactTokensForTokens.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        address[] memory paths = new address[](2);
        paths[0] = address(dai);
        // Add invalid second path address
        paths[1] = address(dai);
        bytes memory swapData = abi.encodeWithSelector(
            TestUniswapV2.swapExactTokensForTokens.selector,
            11e18,
            9e18,
            // Invalid second path address
            paths,
            address(scw),
            block.timestamp + 1000
        );
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV2), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (invalid amountIn)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV2_swapExactTokensForTokens_RevertIf_IncorrectToAddress() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV2), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV2), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        ParamCondition[] memory swapConditions = new ParamCondition[](5);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        swapConditions[2] =
            ParamCondition({offset: 196, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[3] =
            ParamCondition({offset: 228, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        // Should fail on this condition
        swapConditions[4] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV2),
            selector: TestUniswapV2.swapExactTokensForTokens.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        address[] memory paths = new address[](2);
        paths[0] = address(dai);
        // Add invalid second path address
        paths[1] = address(dai);
        bytes memory swapData = abi.encodeWithSelector(
            TestUniswapV2.swapExactTokensForTokens.selector,
            11e18,
            9e18,
            paths,
            // Invalid to address
            alice.pub,
            block.timestamp + 1000
        );
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV2), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (invalid amountIn)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV2_swapExactETHForTokens() public validatorInstalled {
        // Swap ETH for WETH
        weth.deposit{value: 10 ether}();
        // Approve Uniswap to spend tokens
        weth.approve(address(uniswapV2), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        ParamCondition[] memory swapConditions = new ParamCondition[](4);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: bytes32(uint256(10 ether))});
        swapConditions[1] =
            ParamCondition({offset: 164, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(weth))))});
        swapConditions[2] =
            ParamCondition({offset: 196, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[3] =
            ParamCondition({offset: 68, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV2),
            selector: TestUniswapV2.swapExactETHForTokens.selector,
            payableLimit: 10 ether,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        address[] memory paths = new address[](2);
        paths[0] = address(weth);
        paths[1] = address(dai);
        bytes memory swapData = abi.encodeWithSelector(
            TestUniswapV2.swapExactETHForTokens.selector, 10 ether, paths, address(scw), block.timestamp + 1000
        );
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV2), value: 10 ether, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        vm.expectEmit(false, false, false, true);
        emit MockUniswapExchangeEvent(10 ether, 11e18, address(weth), address(dai));
        // Execute the user operation
        _executeUserOp(op);
        assertEq(weth.balanceOf(address(scw)), 10 ether, "Wallet WETH balance should decrease by 10 ether");
        assertEq(dai.balanceOf(address(scw)), 11e18, "Wallet LINK balance should increase by 11 ether");
    }

    function test_uniswapV2_swapExactETHForTokens_RevertIf_ExceedsPayableLimit() public validatorInstalled {
        // Swap ETH for WETH
        weth.deposit{value: 10 ether}();
        // Approve Uniswap to spend tokens
        weth.approve(address(uniswapV2), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        ParamCondition[] memory swapConditions = new ParamCondition[](4);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: bytes32(uint256(10 ether))});
        swapConditions[1] =
            ParamCondition({offset: 164, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(weth))))});
        swapConditions[2] =
            ParamCondition({offset: 196, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[3] =
            ParamCondition({offset: 68, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV2),
            selector: TestUniswapV2.swapExactETHForTokens.selector,
            payableLimit: 10 ether,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        address[] memory paths = new address[](2);
        paths[0] = address(weth);
        paths[1] = address(dai);
        bytes memory swapData = abi.encodeWithSelector(
            TestUniswapV2.swapExactETHForTokens.selector, 10 ether, paths, address(scw), block.timestamp + 1000
        );
        // Create an array of executions with payable WETH value over limit set
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV2), value: 11 ether, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (exceed payable limit)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV2_swapExactETHForTokens_RevertIf_IncorrectAmountOut() public validatorInstalled {
        // Swap ETH for WETH
        weth.deposit{value: 10 ether}();
        // Approve Uniswap to spend tokens
        weth.approve(address(uniswapV2), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        ParamCondition[] memory swapConditions = new ParamCondition[](4);
        // Should fail on this condition
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: bytes32(uint256(10 ether))});
        swapConditions[1] =
            ParamCondition({offset: 164, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(weth))))});
        swapConditions[2] =
            ParamCondition({offset: 196, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[3] =
            ParamCondition({offset: 68, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV2),
            selector: TestUniswapV2.swapExactETHForTokens.selector,
            payableLimit: 10 ether,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        address[] memory paths = new address[](2);
        paths[0] = address(weth);
        paths[1] = address(dai);
        bytes memory swapData = abi.encodeWithSelector(
            TestUniswapV2.swapExactETHForTokens.selector,
            // Incorrect amountOut
            9 ether,
            paths,
            address(scw),
            block.timestamp + 1000
        );
        // Create an array of executions with payable WETH value over limit set
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV2), value: 10 ether, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (invalid amountOut)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV2_swapExactETHForTokens_RevertIf_IncorrectPath() public validatorInstalled {
        // Swap ETH for WETH
        weth.deposit{value: 10 ether}();
        // Approve Uniswap to spend tokens
        weth.approve(address(uniswapV2), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        ParamCondition[] memory swapConditions = new ParamCondition[](4);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: bytes32(uint256(10 ether))});
        swapConditions[1] =
            ParamCondition({offset: 164, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(weth))))});
        // Should fail on this condition
        swapConditions[2] =
            ParamCondition({offset: 196, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[3] =
            ParamCondition({offset: 68, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV2),
            selector: TestUniswapV2.swapExactETHForTokens.selector,
            payableLimit: 10 ether,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        address[] memory paths = new address[](2);
        paths[0] = address(weth);
        // Incorrect value for address path
        paths[1] = address(weth);
        bytes memory swapData = abi.encodeWithSelector(
            TestUniswapV2.swapExactETHForTokens.selector, 10 ether, paths, address(scw), block.timestamp + 1000
        );
        // Create an array of executions with payable WETH value over limit set
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV2), value: 10 ether, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect path)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV2_swapExactETHForTokens_RevertIf_IncorrectToAddress() public validatorInstalled {
        // Swap ETH for WETH
        weth.deposit{value: 10 ether}();
        // Approve Uniswap to spend tokens
        weth.approve(address(uniswapV2), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        ParamCondition[] memory swapConditions = new ParamCondition[](4);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.GREATER_THAN_OR_EQUAL, value: bytes32(uint256(10 ether))});
        swapConditions[1] =
            ParamCondition({offset: 164, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(weth))))});
        swapConditions[2] =
            ParamCondition({offset: 196, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        // Should fail on this condition
        swapConditions[3] =
            ParamCondition({offset: 68, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV2),
            selector: TestUniswapV2.swapExactETHForTokens.selector,
            payableLimit: 10 ether,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        address[] memory paths = new address[](2);
        paths[0] = address(weth);
        paths[1] = address(dai);
        bytes memory swapData = abi.encodeWithSelector(
            TestUniswapV2.swapExactETHForTokens.selector,
            10 ether,
            paths,
            // Incorrect 'to' used
            alice.pub,
            block.timestamp + 1000
        );
        // Create an array of executions with payable WETH value over limit set
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV2), value: 10 ether, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect to address)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    /*//////////////////////////////////////////////////////////////
                         UNISWAP V3 SWAP TESTING
    //////////////////////////////////////////////////////////////*/

    function test_uniswapV3_exactOutputSingle() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactOutputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactOutputSingleParams memory params = TestUniswapV3.ExactOutputSingleParams({
            tokenIn: address(dai),
            tokenOut: address(link),
            fee: 3000, // 0.3%
            recipient: address(scw),
            deadline: block.timestamp + 1000,
            amountOut: 10e18,
            amountInMaximum: 11e18,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactOutputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        vm.expectEmit(false, false, false, true);
        emit MockUniswapExchangeEvent(11e18 - 5, 10e18, address(dai), address(link));
        // Execute the user operation
        _executeUserOp(op);
        assertEq(dai.balanceOf(address(scw)), 89e18 + 5, "Wallet DAI balance should decrease by 10e18 + 5");
        assertEq(link.balanceOf(address(scw)), 10e18, "Wallet LINK balance should increase by 10e18");
    }

    function test_uniswapV3_exactOutputSingle_RevertIf_IncorrectTokenIn() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        // Should fail on this condition
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10 ether))});
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactOutputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactOutputSingleParams memory params = TestUniswapV3.ExactOutputSingleParams({
            // Invalid tokenIn
            tokenIn: address(weth),
            tokenOut: address(link),
            fee: 3000, // 0.3%
            recipient: address(scw),
            deadline: block.timestamp + 1000,
            amountOut: 10e18,
            amountInMaximum: 11 ether,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactOutputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect tokenIn)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV3_exactOutputSingle_RevertIf_incorrectTokenOut() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        // Should fail on this condition
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10 ether))});
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactOutputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactOutputSingleParams memory params = TestUniswapV3.ExactOutputSingleParams({
            tokenIn: address(dai),
            // Invalid tokenOut
            tokenOut: address(weth),
            fee: 3000, // 0.3%
            recipient: address(scw),
            deadline: block.timestamp + 1000,
            amountOut: 10 ether,
            amountInMaximum: 11e18,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactOutputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect tokenOut)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV3_exactOutputSingle_RevertIf_IncorrectFee() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        // Should fail on this condition
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10 ether))});
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactOutputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactOutputSingleParams memory params = TestUniswapV3.ExactOutputSingleParams({
            tokenIn: address(dai),
            tokenOut: address(weth),
            fee: 5100, // 0.51%
            recipient: address(scw),
            deadline: block.timestamp + 1000,
            amountOut: 10 ether,
            amountInMaximum: 11e18,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactOutputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect fee)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV3_exactOutputSingle_RevertIf_IncorrectRecipient() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        // Should fail on this condition
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10 ether))});
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactOutputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactOutputSingleParams memory params = TestUniswapV3.ExactOutputSingleParams({
            tokenIn: address(dai),
            tokenOut: address(weth),
            fee: 3000, // 0.3%
            // Invalid recipient
            recipient: alice.pub,
            deadline: block.timestamp + 1000,
            amountOut: 10 ether,
            amountInMaximum: 11e18,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactOutputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect recipient)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV3_exactOutputSingle_RevertIf_IncorrectAmountOut() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        // Should fail on this condition
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10 ether))});
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactOutputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactOutputSingleParams memory params = TestUniswapV3.ExactOutputSingleParams({
            tokenIn: address(dai),
            tokenOut: address(weth),
            fee: 3000, // 0.3%
            recipient: alice.pub,
            deadline: block.timestamp + 1000,
            // Invalid amountOut
            amountOut: 11 ether,
            amountInMaximum: 11e18,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactOutputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect amountOut)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV3_exactOutputSingle_RevertIf_IncorrectAmountInMaximum() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10 ether))});
        // Should fail on this condition
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactOutputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactOutputSingleParams memory params = TestUniswapV3.ExactOutputSingleParams({
            tokenIn: address(dai),
            tokenOut: address(weth),
            fee: 3000, // 0.3%
            recipient: alice.pub,
            deadline: block.timestamp + 1000,
            amountOut: 10 ether,
            // Invalid amountInMaximum
            amountInMaximum: 11e18,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactOutputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect amountInMaximum)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV3_exactInputSingle() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11e18))});
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactInputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactInputSingleParams memory params = TestUniswapV3.ExactInputSingleParams({
            tokenIn: address(dai),
            tokenOut: address(link),
            fee: 3000, // 0.3%
            recipient: address(scw),
            deadline: block.timestamp + 1000,
            amountIn: 11e18,
            amountOutMinimum: 10e18,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactInputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        vm.expectEmit(false, false, false, true);
        emit MockUniswapExchangeEvent(11e18, 10e18 + 5, address(dai), address(link));
        // Execute the user operation
        _executeUserOp(op);
        assertEq(dai.balanceOf(address(scw)), 89e18, "Wallet DAI balance should decrease by 11e18");
        assertEq(link.balanceOf(address(scw)), 10e18 + 5, "Wallet LINK balance should increase by 10e18 + 5 wei");
    }

    function test_uniswapV3_exactInputSingle_RevertIf_InvalidTokenIn() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        // Should fail on this condition
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11 ether))});
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactInputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactInputSingleParams memory params = TestUniswapV3.ExactInputSingleParams({
            // Invalid tokenIn
            tokenIn: address(weth),
            tokenOut: address(link),
            fee: 3000, // 0.3%
            recipient: address(scw),
            deadline: block.timestamp + 1000,
            amountIn: 11 ether,
            amountOutMinimum: 10e18,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactInputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect tokenIn)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV3_exactInputSingle_RevertIf_InvalidTokenOut() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        // Should fail on this condition
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11e18))});
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactInputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactInputSingleParams memory params = TestUniswapV3.ExactInputSingleParams({
            tokenIn: address(dai),
            // Invalid tokenOut
            tokenOut: address(dai),
            fee: 3000, // 0.3%
            recipient: address(scw),
            deadline: block.timestamp + 1000,
            amountIn: 11e18,
            amountOutMinimum: 10e18,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactInputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect tokenOut)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV3_exactInputSingle_RevertIf_InvalidFee() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        // Should fail on this condition
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11e18))});
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactInputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactInputSingleParams memory params = TestUniswapV3.ExactInputSingleParams({
            tokenIn: address(dai),
            tokenOut: address(link),
            // Invalid fee
            fee: 5100, // 0.51%
            recipient: address(scw),
            deadline: block.timestamp + 1000,
            amountIn: 11e18,
            amountOutMinimum: 10e18,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactInputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect fee)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV3_exactInputSingle_RevertIf_InvalidRecipient() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        // Should fail on this condition
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11e18))});
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactInputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactInputSingleParams memory params = TestUniswapV3.ExactInputSingleParams({
            tokenIn: address(dai),
            tokenOut: address(link),
            fee: 3000, // 0.3%
            // Invalid recipient
            recipient: alice.pub,
            deadline: block.timestamp + 1000,
            amountIn: 11e18,
            amountOutMinimum: 10e18,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactInputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect recipient)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV3_exactInputSingle_RevertIf_InvalidAmountIn() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        // Should fail on this condition
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11e18))});
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactInputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactInputSingleParams memory params = TestUniswapV3.ExactInputSingleParams({
            tokenIn: address(dai),
            tokenOut: address(link),
            fee: 3000, // 0.3%
            recipient: alice.pub,
            deadline: block.timestamp + 1000,
            // Invalid recipient
            amountIn: 12e18,
            amountOutMinimum: 10e18,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactInputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect amountIn)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    function test_uniswapV3_exactInputSingle_RevertIf_InvalidAmountOutMinimum() public validatorInstalled {
        // Mint tokens
        dai.mint(address(scw), 100e18);
        link.mint(address(uniswapV3), 100e18);
        // Approve Uniswap to spend tokens
        dai.approve(address(uniswapV3), type(uint256).max);
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Set up swap conditions
        ParamCondition[] memory swapConditions = new ParamCondition[](6);
        swapConditions[0] =
            ParamCondition({offset: 4, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(dai))))});
        swapConditions[1] =
            ParamCondition({offset: 36, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(link))))});
        swapConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(uint160(uint24(5000)))) // 0.5%
        });
        swapConditions[3] =
            ParamCondition({offset: 100, rule: ComparisonRule.EQUAL, value: bytes32(uint256(uint160(address(scw))))});
        swapConditions[4] =
            ParamCondition({offset: 164, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(11e18))});
        // Should fail on this condition
        swapConditions[5] =
            ParamCondition({offset: 196, rule: ComparisonRule.LESS_THAN_OR_EQUAL, value: bytes32(uint256(10e18))});
        Permission memory swapPerm = Permission({
            target: address(uniswapV3),
            selector: TestUniswapV3.exactInputSingle.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: swapConditions
        });
        skv.addPermission(sessionKey.pub, swapPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        TestUniswapV3.ExactInputSingleParams memory params = TestUniswapV3.ExactInputSingleParams({
            tokenIn: address(dai),
            tokenOut: address(link),
            fee: 3000, // 0.3%
            recipient: alice.pub,
            deadline: block.timestamp + 1000,
            amountIn: 11e18,
            // Invalid amountOutMinimum
            amountOutMinimum: 11e18,
            sqrtPriceLimitX96: 0
        });
        bytes memory swapData = abi.encodeWithSelector(TestUniswapV3.exactInputSingle.selector, params);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(uniswapV3), value: 0, callData: swapData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Expect the operation to revert due to signature error (incorrect amountOutMinimum)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Execute the user operation
        _executeUserOp(op);
    }

    /*//////////////////////////////////////////////////////////////
                             NFT PURCHASE
    //////////////////////////////////////////////////////////////*/

    function test_buyingNFT() public validatorInstalled {
        // Set up a session key and permissions
        (SessionData memory sd, Permission[] memory perms) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        ParamCondition[] memory mintConditions = new ParamCondition[](1);
        mintConditions[0] = ParamCondition({
            offset: 4,
            rule: ComparisonRule.EQUAL,
            value: bytes32(uint256(uint160(address(alice.pub))))
        });
        Permission memory mintPerm = Permission({
            target: address(cryptoPunk),
            selector: TestERC721.purchaseNFTToWallet.selector,
            payableLimit: 0.05 ether,
            uses: tenUses,
            paramConditions: mintConditions
        });
        skv.addPermission(sessionKey.pub, mintPerm);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        // Encode call data for swap
        bytes memory mintData = abi.encodeWithSelector(TestERC721.purchaseNFTToWallet.selector, alice.pub);
        // Create an array of executions
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(cryptoPunk), value: 0.05 ether, callData: mintData});
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(address(skv), executions, evs, sessionKey);
        // Get initial native balance of wallet
        uint256 balance = address(scw).balance;
        // Expect the NFT purchased event to be emitted
        vm.expectEmit(true, true, false, true);
        emit TestNFTPuchased(address(scw), alice.pub, 1);
        // Execute the user operation
        _executeUserOp(op);
        // Varify that Alice has been minted NFT and that address(scw) paid for it
        assertEq(cryptoPunk.balanceOf(alice.pub), 1, "Alice should have NFT");
        // Lt as tx cost
        assertLt(address(scw).balance, balance - 0.05 ether);
    }
}
