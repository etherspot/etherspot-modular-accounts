// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {ExecutionLib} from "ERC7579/libs/ExecutionLib.sol";
import {ModeLib} from "ERC7579/libs/ModeLib.sol";
import "ERC7579/test/dependencies/EntryPoint.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {SessionKeyValidator} from "../../../../src/modules/validators/SessionKeyValidator.sol";
import {ExecutionValidation, ParamCondition, Permission, SessionData} from "../../../../src/common/Structs.sol";
import {ComparisonRule} from "../../../../src/common/Enums.sol";
import {TestCounter} from "../../../../src/test/TestCounter.sol";
import {SessionKeyTestUtils as TestUtils} from "../utils/SessionKeyTestUtils.sol";

contract SessionKeyValidator_Fuzz_Test is TestUtils {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SKV_SessionKeyEnabled(
        address indexed sessionKey,
        address indexed wallet
    );
    event SKV_SessionKeyDisabled(
        address indexed sessionKey,
        address indexed wallet
    );
    event SKV_SessionKeyPauseToggled(
        address indexed sessionKey,
        address indexed wallet,
        bool live
    );
    event SKV_PermissionUsesUpdated(
        address indexed sessionKey,
        uint256 index,
        uint256 previousUses,
        uint256 newUses
    );
    event SKV_SessionKeyValidUntilUpdated(
        address indexed sessionKey,
        address indexed wallet,
        uint48 newValidUntil
    );

    // From TestCounter contract
    event ReceivedMultiTypeCall(address addr, uint256 num, bool boolVal);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testSetup();
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_enableSessionKey(
        uint48 _validAfter,
        uint48 _validUntil,
        uint256 _uses,
        address _target,
        bytes4 _selector,
        uint256 _payableLimit,
        uint256 _offset,
        bytes32 _value
    ) public validatorInstalled {
        // Assume valid input parameters
        vm.assume(_target != address(0));
        vm.assume(_validAfter > block.timestamp);
        vm.assume(_validUntil > _validAfter);
        vm.assume(_uses > 0 && _uses <= 1000);
        (
            SessionData memory sd,
            Permission[] memory perms
        ) = _getSessionKeyAndPermissions(sessionKey);
        sd.validAfter = _validAfter;
        sd.validUntil = _validUntil;
        perms[0].target = _target;
        perms[0].selector = _selector;
        perms[0].payableLimit = _payableLimit;
        perms[0].uses = _uses;
        perms[0].paramConditions[0].offset = _offset;
        perms[0].paramConditions[0].value = _value;
        // Expect the SessionKeyEnabled event to be emitted
        vm.expectEmit(true, true, false, true);
        emit SKV_SessionKeyEnabled(sessionKey.pub, address(scw));
        skv.enableSessionKey(sd, perms);
        // Retrieve the session key data
        SessionData memory data = skv.getSessionKeyData(sessionKey.pub);
        // Verify session key data
        assertEq(
            data.validAfter,
            _validAfter,
            "ValidAfter should match the set value"
        );
        assertEq(
            data.validUntil,
            _validUntil,
            "ValidUntil should match the set value"
        );
        assertTrue(data.live, "Session key should be live after enabling");
        // Verify session key Permission
        Permission[] memory permissions = skv.getSessionKeyPermissions(
            sessionKey.pub
        );
        assertEq(
            permissions.length,
            perms.length,
            "Permission length should match"
        );
        for (uint256 i; i < perms.length; ++i) {
            Permission memory perm = permissions[i];
            Permission memory expectedPerm = perms[i];
            assertEq(perm.target, expectedPerm.target, "Target should match");
            assertEq(
                perm.selector,
                expectedPerm.selector,
                "Selector should match"
            );
            assertEq(
                perm.payableLimit,
                expectedPerm.payableLimit,
                "PayableLimit should match"
            );
            assertEq(
                perm.uses,
                expectedPerm.uses,
                "Uses should match the set value"
            );
            for (uint256 j; j < expectedPerm.paramConditions.length; ++j) {
                ParamCondition memory condition = permissions[i]
                    .paramConditions[j];
                ParamCondition memory expectedCondition = expectedPerm
                    .paramConditions[j];
                assertEq(
                    condition.offset,
                    expectedCondition.offset,
                    "Offset should match"
                );
                assertEq(
                    uint8(condition.rule),
                    uint8(expectedCondition.rule),
                    "Rule should match"
                );
                assertEq(
                    condition.value,
                    expectedCondition.value,
                    "Value should match"
                );
            }
        }
        // Verify associated session keys
        address[] memory associatedKeys = skv.getSessionKeysByWallet();
        assertEq(
            associatedKeys.length,
            1,
            "Should have one associated session key"
        );
        assertEq(
            associatedKeys[0],
            sessionKey.pub,
            "Associated session key should match the enabled key"
        );
        vm.stopPrank();
    }

    function testFuzz_toggleSessionKeyPause(
        uint8 _toggleCount
    ) public validatorInstalled {
        // Assume a reasonable number of toggles
        vm.assume(_toggleCount > 0 && _toggleCount <= 100);
        // Set up the original session key
        (
            SessionData memory sd,
            Permission[] memory perms
        ) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Initialize expected state (session key starts as active)
        bool expectedState = true;
        // Perform multiple toggles
        for (uint8 i; i < _toggleCount; ++i) {
            // Flip the expected state
            expectedState = !expectedState;
            // Expect the SKV_SessionKeyPauseToggled event to be emitted
            vm.expectEmit(false, false, false, true);
            emit SKV_SessionKeyPauseToggled(
                sessionKey.pub,
                address(scw),
                expectedState
            );
            // Toggle the session key pause state
            skv.toggleSessionKeyPause(sessionKey.pub);
            // Verify that the session key's live state matches the expected state
            assertEq(
                skv.isSessionLive(sessionKey.pub),
                expectedState,
                "Session key live state should match expected state after toggle"
            );
        }
        vm.stopPrank();
    }

    function testFuzz_getSessionKeysByWallet(
        uint8 _keyCount
    ) public validatorInstalled {
        // Assume a reasonable number of session keys
        vm.assume(_keyCount > 0 && _keyCount <= 10);
        // Create and set up multiple session keys
        string[] memory ids = new string[](_keyCount);
        for (uint8 i; i < _keyCount; ++i) {
            ids[i] = string(abi.encode(i));
        }
        address[] memory sessionKeys = new address[](_keyCount);
        for (uint8 i; i < _keyCount; ++i) {
            // Generate a unique session key address
            User memory newSessionKey = _createUser(ids[i]);
            // address newSessionKey = address(
            //     uint160(uint(keccak256(abi.encodePacked(i, block.timestamp))))
            // );
            sessionKeys[i] = newSessionKey.pub;
            // Set up the original session key
            (
                SessionData memory sd,
                Permission[] memory perms
            ) = _getSessionKeyAndPermissions(newSessionKey);
            skv.enableSessionKey(sd, perms);
        }
        // Retrieve the session keys associated with the wallet
        address[] memory retrievedKeys = skv.getSessionKeysByWallet();
        // Verify the number of retrieved session keys
        assertEq(
            retrievedKeys.length,
            _keyCount,
            "Number of retrieved session keys should match the expected count"
        );
        // Verify each retrieved session key
        for (uint8 i; i < retrievedKeys.length; ++i) {
            assertEq(
                retrievedKeys[i],
                sessionKeys[i],
                string(
                    abi.encodePacked(
                        "Session key at index ",
                        i,
                        " should match the expected session key address"
                    )
                )
            );
        }
        vm.stopPrank();
    }

    function testFuzz_getSessionKeyPermissions(
        uint8 _numPermissions
    ) public validatorInstalled {
        // Bound the number of permissions between 1 and 10
        _numPermissions = uint8(bound(_numPermissions, 1, 10));
        // Initialize arrays for session key parameters
        address[] memory _targets = new address[](_numPermissions);
        bytes4[] memory _selectors = new bytes4[](_numPermissions);
        uint256[] memory _payableLimits = new uint256[](_numPermissions);
        uint256[] memory _uses = new uint256[](_numPermissions);
        ParamCondition[][] memory _paramConditions = new ParamCondition[][](
            _numPermissions
        );
        // Generate random values for session key parameters
        for (uint8 i; i < _numPermissions; i++) {
            _targets[i] = address(uint160(i + 1));
            _selectors[i] = bytes4(uint32(i + 1));
            _payableLimits[i] = i + 1;
            _uses[i] = i + 1;
            // Create a single ParamCondition for each permission
            ParamCondition[] memory conditions = new ParamCondition[](1);
            conditions[0] = ParamCondition({
                offset: i + 2,
                rule: ComparisonRule.LESS_THAN_OR_EQUAL,
                value: keccak256(
                    abi.encodePacked(i, block.timestamp, msg.sender)
                )
            });
            _paramConditions[i] = conditions;
        }
        // Set up the session key with the generated parameters
        SessionData memory sd = SessionData({
            sessionKey: sessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            live: true
        });
        Permission[] memory perms = new Permission[](_numPermissions);
        for (uint8 i; i < _numPermissions; i++) {
            perms[i] = Permission({
                target: _targets[i],
                selector: _selectors[i],
                payableLimit: _payableLimits[i],
                uses: _uses[i],
                paramConditions: _paramConditions[i]
            });
        }
        skv.enableSessionKey(sd, perms);
        // Retrieve the permissions for the session key
        Permission[] memory permissions = skv.getSessionKeyPermissions(
            sessionKey.pub
        );
        // Verify the number of permissions
        assertEq(
            permissions.length,
            _numPermissions,
            "Number of permissions should match"
        );
        // Verify each permission
        for (uint8 i; i < _numPermissions; i++) {
            assertEq(permissions[i].target, _targets[i], "Target should match");
            assertEq(
                permissions[i].selector,
                _selectors[i],
                "Selector should match"
            );
            assertEq(
                permissions[i].payableLimit,
                _payableLimits[i],
                "Payable limit should match"
            );
            assertEq(permissions[i].uses, _uses[i], "Uses should match");
            assertEq(
                permissions[i].paramConditions.length,
                1,
                "Number of param conditions should be 1"
            );
            assertEq(
                permissions[i].paramConditions[0].offset,
                i + 2,
                "Offset should match"
            );
            assertEq(
                uint8(permissions[i].paramConditions[0].rule),
                uint8(ComparisonRule.LESS_THAN_OR_EQUAL),
                "Rule should match"
            );
            assertEq(
                permissions[i].paramConditions[0].value,
                keccak256(abi.encodePacked(i, block.timestamp, msg.sender)),
                "Value should match"
            );
        }
    }

    function testFuzz_addPermission(
        address _target,
        bytes4 _selector,
        uint256 _payableLimit,
        uint256 _offset,
        uint8 _rule,
        bytes32 _value
    ) public validatorInstalled {
        // Assume valid input parameters
        vm.assume(_target != address(0));
        vm.assume(_selector != bytes4(0));
        vm.assume(_payableLimit > 0);
        vm.assume(_offset > 0);
        vm.assume(_rule <= uint8(type(ComparisonRule).max));
        // Set up a session key with initial permissions
        (
            SessionData memory sd,
            Permission[] memory perms
        ) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Get the initial number of permissions
        uint256 initialPermissionCount = skv
            .getSessionKeyPermissions(sessionKey.pub)
            .length;
        // Add the new permission
        ComparisonRule rule = ComparisonRule(_rule);
        ParamCondition[] memory paramConditions = new ParamCondition[](1);
        paramConditions[0] = ParamCondition({
            offset: _offset,
            rule: rule,
            value: _value
        });
        skv.addPermission(
            sessionKey.pub,
            Permission({
                target: _target,
                selector: _selector,
                payableLimit: _payableLimit,
                uses: tenUses,
                paramConditions: paramConditions
            })
        );
        // Retrieve updated session key permissions
        Permission[] memory updatedPermissions = skv.getSessionKeyPermissions(
            sessionKey.pub
        );
        // Verify the number of permissions has increased
        assertEq(
            updatedPermissions.length,
            initialPermissionCount + 1,
            "Number of permissions should increase by 1"
        );
        // Verify the new permission details
        Permission memory newPermission = updatedPermissions[
            initialPermissionCount
        ];
        assertEq(
            newPermission.target,
            _target,
            "New permission target should match"
        );
        assertEq(
            newPermission.selector,
            _selector,
            "New permission selector should match"
        );
        assertEq(
            newPermission.payableLimit,
            _payableLimit,
            "New permission payable limit should match"
        );
        assertEq(
            newPermission.uses,
            tenUses,
            "New permission payable limit should match"
        );
        assertEq(
            newPermission.paramConditions.length,
            1,
            "New permission should have one param condition"
        );
        assertEq(
            newPermission.paramConditions[0].offset,
            _offset,
            "New permission offset should match"
        );
        assertEq(
            uint8(newPermission.paramConditions[0].rule),
            _rule,
            "New permission rule should match"
        );
        assertEq(
            newPermission.paramConditions[0].value,
            _value,
            "New permission value should match"
        );
    }
    function testFuzz_removePermission(
        uint8 _permissionIndexToRemove
    ) public validatorInstalled {
        // Set up a session key with initial permissions
        (
            SessionData memory sd,
            Permission[] memory perms
        ) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Get the initial number of permissions
        uint256 initialPermissionCount = skv
            .getSessionKeyPermissions(sessionKey.pub)
            .length;
        // Bound the permission index to remove within the valid range
        _permissionIndexToRemove = uint8(
            bound(_permissionIndexToRemove, 0, initialPermissionCount - 1)
        );
        // Remove the permission at the fuzzed index
        skv.removePermission(sessionKey.pub, _permissionIndexToRemove);
        // Retrieve updated session key permissions
        Permission[] memory updatedPermissions = skv.getSessionKeyPermissions(
            sessionKey.pub
        );
        // Verify the number of permissions has decreased by 1
        assertEq(
            updatedPermissions.length,
            initialPermissionCount - 1,
            "Number of permissions should decrease by 1"
        );
        // Verify that the removed permission is no longer present
        for (uint256 i; i < updatedPermissions.length; ++i) {
            assertTrue(
                i != _permissionIndexToRemove ||
                    updatedPermissions[i].target !=
                    perms[_permissionIndexToRemove].target ||
                    updatedPermissions[i].selector !=
                    perms[_permissionIndexToRemove].selector,
                "Removed permission should not be present"
            );
        }
    }

    function testFuzz_modifyPermission(
        address _newTarget,
        bytes4 _newSelector,
        uint256 _newPayableLimit,
        uint256 _newUses,
        uint8 _paramOffset,
        uint8 _paramRule,
        bytes32 _paramValue
    ) public validatorInstalled {
        vm.assume(_newTarget != address(0));
        vm.assume(_newPayableLimit <= type(uint256).max);
        // payableLimit and selector cannot be 0
        vm.assume(
            _newPayableLimit != 0 && _newSelector != bytes4(0) && _newUses != 0
        );
        vm.assume(_paramRule <= uint8(type(ComparisonRule).max));
        (
            SessionData memory sd,
            Permission[] memory perms
        ) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] = ParamCondition({
            offset: _paramOffset,
            rule: ComparisonRule(_paramRule),
            value: _paramValue
        });
        skv.modifyPermission(
            sessionKey.pub,
            0,
            _newTarget,
            _newSelector,
            _newPayableLimit,
            _newUses,
            newConditions
        );
        Permission[] memory modifiedPerms = skv.getSessionKeyPermissions(
            sessionKey.pub
        );
        assertEq(modifiedPerms[0].target, _newTarget);
        assertEq(
            modifiedPerms[0].selector,
            _newSelector,
            "selector doesnt match"
        );
        assertEq(modifiedPerms[0].payableLimit, _newPayableLimit);
        assertEq(modifiedPerms[0].uses, _newUses);
        assertEq(modifiedPerms[0].paramConditions.length, 1);
        assertEq(modifiedPerms[0].paramConditions[0].offset, _paramOffset);
        assertEq(uint8(modifiedPerms[0].paramConditions[0].rule), _paramRule);
        assertEq(modifiedPerms[0].paramConditions[0].value, _paramValue);
    }

    function testFuzz_modifyPermission_completeAndPartialModification(
        address _newTarget,
        bytes4 _newSelector,
        uint256 _newPayableLimit,
        uint256 _newUses,
        uint8 _paramOffset,
        uint8 _paramRule,
        bytes32 _paramValue,
        uint8 _modificationMask
    ) public validatorInstalled {
        vm.assume(_newTarget != address(0));
        vm.assume(_newPayableLimit <= type(uint256).max);
        vm.assume(_paramRule <= uint8(type(ComparisonRule).max));
        // Set up initial session key and permissions
        (
            SessionData memory sd,
            Permission[] memory perms
        ) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        Permission memory originalPerm = perms[0];
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] = ParamCondition({
            offset: _paramOffset,
            rule: ComparisonRule(_paramRule),
            value: _paramValue
        });
        // Use _modificationMask to determine which fields to modify
        address targetToUse = (_modificationMask & 1) != 0
            ? _newTarget
            : originalPerm.target;
        bytes4 selectorToUse;
        if ((_modificationMask & 2) != 0) {
            vm.assume(_newSelector != bytes4(0));
            selectorToUse = _newSelector;
        } else {
            selectorToUse = originalPerm.selector;
        }
        uint256 payableLimitToUse;
        if ((_modificationMask & 4) != 0) {
            vm.assume(_newPayableLimit != 0);
            payableLimitToUse = _newPayableLimit;
        } else {
            payableLimitToUse = originalPerm.payableLimit;
        }
        uint256 usesToUse;
        if ((_modificationMask & 8) != 0) {
            vm.assume(_newUses != 0);
            usesToUse = _newUses;
        } else {
            usesToUse = originalPerm.uses;
        }
        ParamCondition[] memory conditionsToUse = (_modificationMask & 16) != 0
            ? newConditions
            : new ParamCondition[](0);

        skv.modifyPermission(
            sessionKey.pub,
            0,
            targetToUse,
            selectorToUse,
            payableLimitToUse,
            usesToUse,
            conditionsToUse
        );
        Permission[] memory modifiedPerms = skv.getSessionKeyPermissions(
            sessionKey.pub
        );
        assertEq(modifiedPerms[0].target, targetToUse, "target doesn't match");
        assertEq(
            modifiedPerms[0].selector,
            (_modificationMask & 2) != 0
                ? selectorToUse
                : originalPerm.selector,
            "selector doesn't match"
        );
        assertEq(
            modifiedPerms[0].payableLimit,
            (_modificationMask & 4) != 0
                ? payableLimitToUse
                : originalPerm.payableLimit,
            "payableLimit doesn't match"
        );
        assertEq(
            modifiedPerms[0].uses,
            (_modificationMask & 8) != 0 ? usesToUse : originalPerm.uses,
            "uses doesn't match"
        );
        if ((_modificationMask & 16) != 0) {
            assertEq(
                modifiedPerms[0].paramConditions.length,
                1,
                "paramConditions length doesn't match"
            );
            assertEq(
                modifiedPerms[0].paramConditions[0].offset,
                _paramOffset,
                "paramConditions offset doesn't match"
            );
            assertEq(
                uint8(modifiedPerms[0].paramConditions[0].rule),
                _paramRule,
                "paramConditions rule doesn't match"
            );
            assertEq(
                modifiedPerms[0].paramConditions[0].value,
                _paramValue,
                "paramConditions value doesn't match"
            );
        } else {
            assertEq(
                modifiedPerms[0].paramConditions.length,
                originalPerm.paramConditions.length,
                "paramConditions length doesn't match"
            );
        }
    }

    function testFuzz_rotateSessionKey(
        address _newSessionKey,
        uint48 _validAfter,
        uint48 _validUntil,
        bool _live,
        uint256 _uses,
        uint256 _paramValue
    ) public validatorInstalled {
        // Set up initial session key and permissions
        (
            SessionData memory sd,
            Permission[] memory perms
        ) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Assume and bound fuzzed inputs
        vm.assume(
            _newSessionKey != address(0) && _newSessionKey != sessionKey.pub
        );
        _validAfter = uint48(
            bound(_validAfter, block.timestamp, block.timestamp + 365 days)
        );
        _validUntil = uint48(
            bound(_validUntil, _validAfter + 1 days, _validAfter + 365 days)
        );
        _uses = bound(_uses, 1, 1000);
        _paramValue = bound(_paramValue, 0, type(uint256).max);
        SessionData memory newSd = SessionData({
            sessionKey: _newSessionKey,
            validAfter: _validAfter,
            validUntil: _validUntil,
            live: _live
        });
        ParamCondition[] memory newConditions = new ParamCondition[](1);
        newConditions[0] = ParamCondition({
            offset: 4,
            rule: ComparisonRule.GREATER_THAN_OR_EQUAL,
            value: bytes32(_paramValue)
        });
        Permission[] memory newPerms = new Permission[](1);
        newPerms[0] = Permission({
            target: address(counter2),
            selector: TestCounter.changeCount.selector,
            payableLimit: 0,
            uses: _uses,
            paramConditions: newConditions
        });
        skv.rotateSessionKey(sessionKey.pub, newSd, newPerms);
        assertTrue(
            skv.getSessionKeyData(_newSessionKey).validUntil > 0,
            "New session key should be valid after rotation"
        );
        // Expect the function call to revert with SKV_SessionKeyDoesNotExist error
        // when trying to get SessionData for disabled session key
        _toRevert(
            SessionKeyValidator.SKV_SessionKeyDoesNotExist.selector,
            abi.encode(sessionKey.pub)
        );
        skv.getSessionKeyData(sessionKey.pub);
        // Verify new session key data
        SessionData memory rotatedData = skv.getSessionKeyData(_newSessionKey);
        assertEq(
            rotatedData.sessionKey,
            _newSessionKey,
            "Session key address should match"
        );
        assertEq(
            rotatedData.validAfter,
            _validAfter,
            "Valid after should match"
        );
        assertEq(
            rotatedData.validUntil,
            _validUntil,
            "Valid until should match"
        );
        assertEq(
            rotatedData.live,
            true,
            "Live status should be true after rotation"
        );
        // Verify new permissions
        Permission[] memory rotatedPerms = skv.getSessionKeyPermissions(
            _newSessionKey
        );
        assertEq(rotatedPerms.length, 1, "Should have one permission");
        assertEq(
            rotatedPerms[0].target,
            address(counter2),
            "Target should match"
        );
        assertEq(
            rotatedPerms[0].selector,
            TestCounter.changeCount.selector,
            "Selector should match"
        );
        assertEq(rotatedPerms[0].payableLimit, 0, "Payable limit should match");
        assertEq(rotatedPerms[0].uses, _uses, "Uses should match");
        assertEq(
            rotatedPerms[0].paramConditions.length,
            1,
            "Should have one param condition"
        );
        assertEq(
            rotatedPerms[0].paramConditions[0].offset,
            4,
            "Offset should match"
        );
        assertEq(
            uint8(rotatedPerms[0].paramConditions[0].rule),
            uint8(ComparisonRule.GREATER_THAN_OR_EQUAL),
            "Rule should match"
        );
        assertEq(
            rotatedPerms[0].paramConditions[0].value,
            bytes32(_paramValue),
            "Value should match"
        );
        vm.stopPrank();
    }

    function testFuzz_updateUses(uint256 _uses) public validatorInstalled {
        // Assume a different number of uses than the initial value
        vm.assume(_uses != tenUses);
        // Set up a session key with initial permissions and uses
        (
            SessionData memory sd,
            Permission[] memory perms
        ) = _getSessionKeyAndPermissions(sessionKey);
        skv.enableSessionKey(sd, perms);
        // Expect the SKV_SessionKeyUsesUpdated event to be emitted
        vm.expectEmit(true, false, false, true);
        emit SKV_PermissionUsesUpdated(sessionKey.pub, 0, tenUses, _uses);
        // Update the number of uses for the session key
        skv.updateUses(sessionKey.pub, 0, _uses);
        // Verify that the number of uses has been updated correctly
        assertEq(
            skv.getSessionKeyPermissions(sessionKey.pub)[0].uses,
            _uses,
            "Uses should be updated"
        );
        vm.stopPrank();
    }

    function testFuzz_updateValidUntil(
        uint48 initialValidUntil,
        uint48 newValidUntil
    ) public validatorInstalled {
        // Assume initial validUntil is in the future
        vm.assume(initialValidUntil > block.timestamp);
        // Assume new validUntil is later than the initial one
        vm.assume(newValidUntil > initialValidUntil);
        // Set up a session key with initial permissions and validity period
        (
            SessionData memory sd,
            Permission[] memory perms
        ) = _getSessionKeyAndPermissions(sessionKey);
        sd.validUntil = initialValidUntil;
        skv.enableSessionKey(sd, perms);
        // Expect the SKV_SessionKeyValidUntilUpdated event to be emitted
        vm.expectEmit(true, true, false, true);
        emit SKV_SessionKeyValidUntilUpdated(
            sessionKey.pub,
            address(scw),
            newValidUntil
        );
        // Update the validUntil timestamp for the session key
        skv.updateValidUntil(sessionKey.pub, newValidUntil);
        // Retrieve updated session key data
        SessionData memory updatedData = skv.getSessionKeyData(sessionKey.pub);
        // Verify that the validUntil timestamp has been updated correctly
        assertEq(
            updatedData.validUntil,
            newValidUntil,
            "ValidUntil should be updated to new value"
        );
    }

    function testFuzz_executeSingle(
        address _testAddress,
        uint256 _testUint,
        bool _testBool
    ) public validatorInstalled {
        // Set up a session key and permissions
        SessionData memory sd = SessionData({
            sessionKey: sessionKey.pub,
            validAfter: uint48(block.timestamp),
            validUntil: uint48(block.timestamp + 1 days),
            live: true
        });
        ParamCondition[] memory paramConditions = new ParamCondition[](3);
        paramConditions[0] = ParamCondition({
            offset: 4,
            rule: ComparisonRule.EQUAL,
            value: bytes32(uint256(uint160(_testAddress)))
        });
        paramConditions[1] = ParamCondition({
            offset: 36,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(_testUint)
        });
        paramConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.EQUAL,
            value: _testBool ? bytes32(uint256(1)) : bytes32(uint256(0))
        });
        Permission[] memory perms = new Permission[](1);
        perms[0] = Permission({
            target: address(counter1),
            selector: TestCounter.multiTypeCall.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: paramConditions
        });
        skv.enableSessionKey(sd, perms);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));

        // Encode the call data for the counter function
        bytes memory callData = abi.encodeWithSelector(
            TestCounter.multiTypeCall.selector,
            _testAddress,
            _testUint,
            _testBool
        );
        // Set up a single user operation
        PackedUserOperation memory userOp = _setupSingleUserOp(
            address(skv),
            address(counter1),
            0,
            callData,
            evs,
            sessionKey
        );
        // Expect event emit
        vm.expectEmit(false, false, false, true);
        emit ReceivedMultiTypeCall(_testAddress, _testUint, _testBool);
        // Execute the user operation
        _executeUserOp(userOp);
        vm.stopPrank();
    }

    function testFuzz_executeSingle_Native(
        uint256 _transferAmount,
        uint256 _payableLimit
    ) public validatorInstalled {
        // Bound the transfer amount and payable limit
        _transferAmount = bound(_transferAmount, 1 wei, 30 ether);
        _payableLimit = bound(_payableLimit, _transferAmount, 30 ether);
        vm.deal(eoa.pub, _transferAmount);
        // Set up a session key and permissions
        SessionData memory sd = SessionData({
            sessionKey: sessionKey.pub,
            validAfter: uint48(block.timestamp),
            validUntil: uint48(block.timestamp + 1 days),
            live: true
        });
        Permission[] memory perms = new Permission[](1);
        perms[0] = Permission({
            target: bob.pub,
            selector: bytes4(0),
            payableLimit: _payableLimit,
            uses: tenUses,
            paramConditions: new ParamCondition[](1)
        });
        perms[0].paramConditions[0] = ParamCondition({
            offset: 0,
            rule: ComparisonRule.NOT_EQUAL,
            value: 0
        });
        skv.enableSessionKey(sd, perms);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](1);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        PackedUserOperation memory op = _setupSingleUserOp(
            address(skv),
            bob.pub,
            _transferAmount,
            hex"",
            evs,
            sessionKey
        );
        // Execute the user operation
        _executeUserOp(op);
        // Verify that the receiver's balance has been updated correctly
        // Bob has initial balance of 100 ether
        console2.log("bob balance", bob.pub.balance);
        console2.log("transferAmount", _transferAmount);
        console2.log("balance should be", 100 ether + _transferAmount);
        assertEq(
            bob.pub.balance,
            100 ether + _transferAmount,
            "Receiver balance should match transferred amount"
        );
        // Verify that the session key uses has decreased
        uint256 usesLeft = skv.getUsesLeft(sessionKey.pub, 0);
        assertEq(
            usesLeft,
            tenUses - 1,
            "Session key uses should be decremented"
        );
        vm.stopPrank();
    }

    function testFuzz_executeBatch(
        address _testAddress,
        uint256 _testUint,
        bool _testBool,
        uint256 _countValue
    ) public validatorInstalled {
        // Bound the input values
        vm.assume(_testUint <= type(uint256).max - 1);
        _countValue = bound(_countValue, 0, 14);
        // Set up a session key and permissions
        SessionData memory sd = SessionData({
            sessionKey: sessionKey.pub,
            validAfter: uint48(block.timestamp),
            validUntil: uint48(block.timestamp + 1 days),
            live: true
        });
        Permission[] memory perms = new Permission[](2);
        // Permission for multiTypeCall function
        perms[0] = Permission({
            target: address(counter1),
            selector: TestCounter.multiTypeCall.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: new ParamCondition[](3)
        });
        perms[0].paramConditions[0] = ParamCondition({
            offset: 4,
            rule: ComparisonRule.EQUAL,
            value: bytes32(uint256(uint160(_testAddress)))
        });
        perms[0].paramConditions[1] = ParamCondition({
            offset: 36,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(_testUint)
        });
        perms[0].paramConditions[2] = ParamCondition({
            offset: 68,
            rule: ComparisonRule.EQUAL,
            value: _testBool ? bytes32(uint256(1)) : bytes32(uint256(0))
        });
        // Permission for changeCount function
        perms[1] = Permission({
            target: address(counter2),
            selector: TestCounter.changeCount.selector,
            payableLimit: 0,
            uses: tenUses,
            paramConditions: new ParamCondition[](1)
        });
        perms[1].paramConditions[0] = ParamCondition({
            offset: 4,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(14))
        });
        skv.enableSessionKey(sd, perms);
        // Create an array of execution validations
        ExecutionValidation[] memory evs = new ExecutionValidation[](2);
        evs[0] = _getExecutionValidation(uint48(1), uint48(3));
        evs[1] = _getExecutionValidation(uint48(2), uint48(4));

        // Encode call data for multiTypeCall and changeCount functions
        bytes memory callData1 = abi.encodeWithSelector(
            TestCounter.multiTypeCall.selector,
            _testAddress,
            _testUint,
            _testBool
        );
        bytes memory callData2 = abi.encodeWithSelector(
            TestCounter.changeCount.selector,
            _countValue
        );
        // Create an array of executions
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: address(counter1),
            value: 0,
            callData: callData1
        });
        executions[1] = Execution({
            target: address(counter2),
            value: 0,
            callData: callData2
        });
        // Set up a batch user operation
        PackedUserOperation memory op = _setupBatchUserOp(
            address(skv),
            executions,
            evs,
            sessionKey
        );
        // Expect event emit
        vm.expectEmit(false, false, false, true);
        emit ReceivedMultiTypeCall(_testAddress, _testUint, _testBool);
        // Execute the user operation
        _executeUserOp(op);
        // Verify that both counters have been updated correctly
        assertEq(counter2.getCount(), _countValue, "Counter should be updated");
        vm.stopPrank();
    }
}
