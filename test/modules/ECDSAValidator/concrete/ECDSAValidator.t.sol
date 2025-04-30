// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC7579Account} from "../../../../src/interfaces/base/IERC7579Account.sol";
import {ExecutionLib} from "../../../../src/libraries/ExecutionLib.sol";
import {ModularTestBase} from "../../../ModularTestBase.sol";
import {IECDSAValidator} from "../../../../src/interfaces/modules/IECDSAValidator.sol";
import {
    MODULE_TYPE_VALIDATOR, SIG_VALIDATION_SUCCESS, SIG_VALIDATION_FAILED
} from "../../../../src/types/Constants.sol";

contract ECDSAValidator_Concrete_Test is ModularTestBase {
    using ExecutionLib for bytes;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        _testInit();
    }

    /*//////////////////////////////////////////////////////////////
                           INSTALLATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_installValidator() public {
        assertTrue(ECDSA_VALIDATOR.isInitialized(address(SCW)), "Validator should be initialized");
        assertTrue(ECDSA_VALIDATOR.isOwner(address(SCW), eoa.pub), "EOA should be the owner");
    }

    function test_uninstallValidator() public {
        assertTrue(ECDSA_VALIDATOR.isInitialized(address(SCW)), "Validator should be initialized");
        _uninstallModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(ECDSA_VALIDATOR), "");
        assertFalse(ECDSA_VALIDATOR.isInitialized(address(SCW)), "Validator should not be initialized");
    }

    /*//////////////////////////////////////////////////////////////
                         OWNER MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_changeOwner() public {
        vm.prank(eoa.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(ECDSA_VALIDATOR.changeOwner.selector, address(SCW), alice.pub)
        );
        assertTrue(ECDSA_VALIDATOR.isOwner(address(SCW), alice.pub), "Alice should be the new owner");
        assertFalse(ECDSA_VALIDATOR.isOwner(address(SCW), eoa.pub), "EOA should no longer be the owner");
    }

    function test_changeOwner_RevertIf_NonOwner() public {
        vm.prank(alice.pub);
        _toRevert(IECDSAValidator.ECDSA_NotOwner.selector, abi.encode(alice.pub));
        ECDSA_VALIDATOR.changeOwner(address(SCW), bob.pub);
    }

    function test_changeOwner_RevertIf_ZeroAddress() public {
        vm.prank(eoa.pub);
        _toRevert(IECDSAValidator.ECDSA_InvalidOwner.selector, abi.encode(address(SCW), zero.pub));
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(ECDSA_VALIDATOR.changeOwner.selector, address(SCW), zero.pub)
        );
    }

    function test_changeOwner_ViaAccount() public {
        vm.prank(eoa.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(ECDSA_VALIDATOR.changeOwner.selector, address(SCW), alice.pub)
        );
        assertTrue(ECDSA_VALIDATOR.isOwner(address(SCW), alice.pub), "Alice should be the new owner");
    }

    /*//////////////////////////////////////////////////////////////
                       SIGNATURE VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_validateUserOp() public {
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(ECDSA_VALIDATOR));
        bytes32 userOpHash = keccak256(abi.encode("test userop hash"));
        userOp.signature = _sign(userOpHash, eoa);
        vm.prank(address(SCW));
        uint256 validationResult = ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation should succeed");
    }

    function test_validateUserOp_WithEthSign() public {
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(ECDSA_VALIDATOR));
        bytes32 userOpHash = keccak256(abi.encode("test userop hash"));
        userOp.signature = _ethSign(userOpHash, eoa);
        vm.prank(address(SCW));
        uint256 validationResult = ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation with ethSign should succeed");
    }

    function test_validateUserOp_RevertIf_InvalidSigner() public {
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(ECDSA_VALIDATOR));
        bytes32 userOpHash = keccak256(abi.encode("test userop hash"));
        userOp.signature = _sign(userOpHash, alice);
        vm.prank(address(SCW));
        uint256 validationResult = ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_FAILED, "UserOp validation should fail with invalid signer");
    }

    function test_validateUserOp_AfterOwnerChange() public {
        vm.prank(eoa.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(ECDSA_VALIDATOR.changeOwner.selector, address(SCW), alice.pub)
        );
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(ECDSA_VALIDATOR));
        bytes32 userOpHash = keccak256(abi.encode("test userop hash"));
        userOp.signature = _sign(userOpHash, alice);
        vm.prank(address(SCW));
        uint256 validationResult = ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "New owner signature should validate");
    }

    function test_isValidSignatureWithSender() public {
        bytes32 hash = keccak256(abi.encode("test message"));
        bytes memory signature = _sign(hash, eoa);
        vm.prank(address(SCW));
        bytes4 result = ECDSA_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0x1626ba7e), "Signature should be valid");
    }

    function test_isValidSignatureWithSender_WithEthSign() public {
        bytes32 hash = keccak256(abi.encode("test message"));
        bytes memory signature = _ethSign(hash, eoa);
        vm.prank(address(SCW));
        bytes4 result = ECDSA_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0x1626ba7e), "Signature with ethSign should be valid");
    }

    function test_isValidSignatureWithSender_RevertIf_InvalidSignature() public {
        bytes32 hash = keccak256(abi.encode("test message"));
        bytes memory signature = _sign(hash, alice);
        vm.prank(address(SCW));
        bytes4 result = ECDSA_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0xffffffff), "Signature should be invalid");
    }
}
