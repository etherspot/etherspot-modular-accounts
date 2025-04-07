// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC7579Account} from "../../../../src/interfaces/base/IERC7579Account.sol";
import {ModularTestBase} from "../../../ModularTestBase.sol";
import {IMultipleOwnerECDSAValidator} from "../../../../src/interfaces/modules/IMultipleOwnerECDSAValidator.sol";
import {
    MODULE_TYPE_VALIDATOR, SIG_VALIDATION_SUCCESS, SIG_VALIDATION_FAILED
} from "../../../../src/types/Constants.sol";

contract MultipleOwnerECDSAValidator_Concrete_Test is ModularTestBase {
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
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        bytes memory initData = abi.encode(owners);
        bool success =
            _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        assertTrue(success, "Validator should be installed");
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isInitialized(address(SCW)), "Validator should be initialized");
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), eoa.pub), "EOA should be the owner");
    }

    function test_installValidator_WithMultipleOwners() public {
        address[] memory owners = new address[](3);
        owners[0] = eoa.pub;
        owners[1] = alice.pub;
        owners[2] = bob.pub;
        bytes memory initData = abi.encode(owners);
        bool success =
            _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        assertTrue(success, "Validator should be installed");
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), eoa.pub), "EOA should be an owner");
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), alice.pub), "Alice should be an owner");
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), bob.pub), "Bob should be an owner");
    }

    function test_installValidator_RevertIf_InvalidOwnerData() public {
        bytes memory initData = abi.encode(0);
        _toRevert(IMultipleOwnerECDSAValidator.MOECDSA_InvalidOwnerData.selector, hex"");
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
    }

    function test_installValidator_RevertIf_ZeroAddressOwner() public {
        address[] memory owners = new address[](1);
        owners[0] = zero.pub;
        bytes memory initData = abi.encode(owners);
        _toRevert(IMultipleOwnerECDSAValidator.MOECDSA_AddingInvalidOwner.selector, abi.encode(address(SCW), zero.pub));
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
    }

    function test_uninstallValidator() public {
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isInitialized(address(SCW)), "Validator should be initialized");
        _uninstallModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), "");
        assertFalse(MULTIPLE_OWNER_ECDSA_VALIDATOR.isInitialized(address(SCW)), "Validator should not be initialized");
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addOwner() public {
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(eoa.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.addOwner.selector, address(SCW), alice.pub)
        );
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), alice.pub), "Alice should be an owner");
    }

    function test_addOwner_RevertIf_NonOwner() public {
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(alice.pub);
        _toRevert(IMultipleOwnerECDSAValidator.MOECDSA_NotOwner.selector, abi.encode(alice.pub));
        MULTIPLE_OWNER_ECDSA_VALIDATOR.addOwner(address(SCW), alice.pub);
    }

    function test_addOwner_RevertIf_ExistingOwner() public {
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(eoa.pub);
        _toRevert(IMultipleOwnerECDSAValidator.MOECDSA_AddingInvalidOwner.selector, abi.encode(address(SCW), eoa.pub));
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.addOwner.selector, address(SCW), eoa.pub)
        );
    }

    function test_removeOwner() public {
        address[] memory owners = new address[](2);
        owners[0] = eoa.pub;
        owners[1] = alice.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(eoa.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.removeOwner.selector, address(SCW), alice.pub)
        );
        assertFalse(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), alice.pub), "Alice should not be an owner");
    }

    function test_removeOwner_RevertIf_LastOwner() public {
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(eoa.pub);
        _toRevert(IMultipleOwnerECDSAValidator.MOECDSA_CannotRemoveLastOwner.selector, abi.encode(address(SCW)));
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.removeOwner.selector, address(SCW), eoa.pub)
        );
    }

    /*//////////////////////////////////////////////////////////////
                     SIGNATURE VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_validateUserOp() public {
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(MULTIPLE_OWNER_ECDSA_VALIDATOR));
        bytes32 userOpHash = keccak256(abi.encode("test userop hash"));
        userOp.signature = _sign(userOpHash, eoa);
        vm.prank(address(SCW)); // The validator expects msg.sender to be the account
        uint256 validationResult = MULTIPLE_OWNER_ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation should succeed");
    }

    function test_validateUserOp_UsingAnotherOwner() public {
        address[] memory owners = new address[](2);
        owners[0] = eoa.pub;
        owners[1] = alice.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(MULTIPLE_OWNER_ECDSA_VALIDATOR));
        bytes32 userOpHash = keccak256(abi.encode("test userop hash"));
        userOp.signature = _sign(userOpHash, alice);
        vm.prank(address(SCW)); // The validator expects msg.sender to be the account
        uint256 validationResult = MULTIPLE_OWNER_ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation should succeed");
    }

    function test_validateUserOp_WithEthSign() public {
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(MULTIPLE_OWNER_ECDSA_VALIDATOR));
        bytes32 userOpHash = keccak256(abi.encode("test userop hash"));
        userOp.signature = _ethSign(userOpHash, eoa);
        vm.prank(address(SCW));
        uint256 validationResult = MULTIPLE_OWNER_ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation with ethSign should succeed");
    }

    function test_validateUserOp_RevertIf_InvalidSigner() public {
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(MULTIPLE_OWNER_ECDSA_VALIDATOR));
        bytes32 userOpHash = keccak256(abi.encode("test userop hash"));
        userOp.signature = _sign(userOpHash, alice);
        vm.prank(address(SCW));
        uint256 validationResult = MULTIPLE_OWNER_ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_FAILED, "UserOp validation should fail with invalid signer");
    }

    function test_isValidSignatureWithSender() public {
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        bytes32 hash = keccak256(abi.encode("test message"));
        bytes memory signature = _sign(hash, eoa);
        vm.prank(address(SCW));
        bytes4 result = MULTIPLE_OWNER_ECDSA_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0x1626ba7e), "Signature should be valid");
    }

    function test_isValidSignatureWithSender_WithEthSign() public {
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        bytes32 hash = keccak256(abi.encode("test message"));
        bytes memory signature = _ethSign(hash, eoa);
        vm.prank(address(SCW));
        bytes4 result = MULTIPLE_OWNER_ECDSA_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0x1626ba7e), "Signature with ethSign should be valid");
    }

    function test_isValidSignatureWithSender_RevertIf_InvalidSignature() public {
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        bytes32 hash = keccak256(abi.encode("test message"));
        bytes memory signature = _sign(hash, alice);
        vm.prank(address(SCW));
        bytes4 result = MULTIPLE_OWNER_ECDSA_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0xffffffff), "Signature should be invalid");
    }
}
