// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC7579Account} from "../../../../src/interfaces/base/IERC7579Account.sol";
import {ExecutionLib} from "../../../../src/libraries/ExecutionLib.sol";
import {ModularTestBase} from "../../../ModularTestBase.sol";
import {IMultipleOwnerECDSAValidator} from "../../../../src/interfaces/modules/IMultipleOwnerECDSAValidator.sol";
import {
    MODULE_TYPE_VALIDATOR, SIG_VALIDATION_SUCCESS, SIG_VALIDATION_FAILED
} from "../../../../src/types/Constants.sol";

contract MultipleOwnerECDSAValidator_Fuzz_Test is ModularTestBase {
    using ExecutionLib for bytes;
    using ECDSA for bytes32;

    // Events to test
    event MOECDSA_ValidatorEnabled(address indexed scw);
    event MOECDSA_ValidatorDisabled(address indexed scw);
    event MOECDSA_ValidatorOwnerAdded(address indexed scw, address indexed owner);
    event MOECDSA_ValidatorOwnerRemoved(address indexed scw, address indexed owner);

    // Setup function runs before each test
    function setUp() public virtual {
        _testInit();
    }

    /*//////////////////////////////////////////////////////////////
                       INSTALLATION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_installValidator(string memory username) public {
        User memory user = _createUser(username);
        address[] memory owners = new address[](1);
        owners[0] = user.pub;
        bytes memory initData = abi.encode(owners);
        vm.expectEmit(true, true, true, true);
        emit MOECDSA_ValidatorOwnerAdded(address(SCW), user.pub);
        vm.expectEmit(true, true, true, true);
        emit MOECDSA_ValidatorEnabled(address(SCW));
        bool success =
            _installModule(user.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        assertTrue(success, "Validator should be installed");
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isInitialized(address(SCW)), "Validator should be initialized");
        assertTrue(
            MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), user.pub), "Owner should be the specified address"
        );
    }

    function testFuzz_installValidator_WithMultipleOwners(string memory name1, string memory name2, string memory name3)
        public
    {
        vm.assume(
            keccak256(bytes(name1)) != keccak256(bytes(name2)) && keccak256(bytes(name1)) != keccak256(bytes(name3))
                && keccak256(bytes(name2)) != keccak256(bytes(name3))
        );
        User memory user1 = _createUser(name1);
        User memory user2 = _createUser(name2);
        User memory user3 = _createUser(name3);
        address[] memory owners = new address[](3);
        owners[0] = user1.pub;
        owners[1] = user2.pub;
        owners[2] = user3.pub;
        bytes memory initData = abi.encode(owners);
        bool success =
            _installModule(user1.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        assertTrue(success, "Validator should be installed");
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), user1.pub), "User1 should be an owner");
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), user2.pub), "User2 should be an owner");
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), user3.pub), "User3 should be an owner");
    }

    function testFuzz_installValidator_RevertIf_InvalidOwnerCount(uint256 invalidCount) public {
        vm.assume(invalidCount == 0);
        bytes memory initData = abi.encode(invalidCount);
        _toRevert(IMultipleOwnerECDSAValidator.MOECDSA_InvalidOwnerData.selector, hex"");
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
    }

    function testFuzz_installValidator_RevertIf_ZeroAddressOwner() public {
        address[] memory owners = new address[](1);
        owners[0] = zero.pub;
        bytes memory initData = abi.encode(owners);
        _toRevert(
            IMultipleOwnerECDSAValidator.MOECDSA_AddingInvalidOwner.selector, abi.encode(address(SCW), address(0))
        );
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
    }

    function testFuzz_uninstallValidator(string memory username) public {
        User memory user = _createUser(username);
        address[] memory owners = new address[](1);
        owners[0] = user.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(user.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.expectEmit(true, true, true, true);
        emit MOECDSA_ValidatorDisabled(address(SCW));
        _uninstallModule(user.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), "");
        assertFalse(MULTIPLE_OWNER_ECDSA_VALIDATOR.isInitialized(address(SCW)), "Validator should not be initialized");
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER MANAGEMENT FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_addOwner(string memory initName, string memory newName) public {
        vm.assume(keccak256(bytes(initName)) != keccak256(bytes(newName)));
        User memory initialOwner = _createUser(initName);
        User memory newOwner = _createUser(newName);
        address[] memory owners = new address[](1);
        owners[0] = initialOwner.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(initialOwner.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(initialOwner.pub);
        vm.expectEmit(true, true, true, true);
        emit MOECDSA_ValidatorOwnerAdded(address(SCW), newOwner.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.addOwner.selector, address(SCW), newOwner.pub)
        );
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), newOwner.pub), "New owner should be set");
    }

    function testFuzz_addOwner_RevertIf_NotOwner(
        string memory initName,
        string memory maliciousName,
        string memory newName
    ) public {
        vm.assume(
            keccak256(bytes(initName)) != keccak256(bytes(maliciousName))
                && keccak256(bytes(initName)) != keccak256(bytes(newName))
                && keccak256(bytes(maliciousName)) != keccak256(bytes(newName))
        );
        User memory initialOwner = _createUser(initName);
        User memory malicious = _createUser(maliciousName);
        User memory newOwner = _createUser(newName);
        address[] memory owners = new address[](1);
        owners[0] = initialOwner.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(initialOwner.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(malicious.pub);
        _toRevert(IMultipleOwnerECDSAValidator.MOECDSA_NotOwner.selector, abi.encode(malicious.pub));
        MULTIPLE_OWNER_ECDSA_VALIDATOR.addOwner(address(SCW), newOwner.pub);
    }

    function testFuzz_addOwner_RevertIf_ZeroAddress(string memory initName) public {
        User memory initialOwner = _createUser(initName);
        address[] memory owners = new address[](1);
        owners[0] = initialOwner.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(initialOwner.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(initialOwner.pub);
        _toRevert(
            IMultipleOwnerECDSAValidator.MOECDSA_AddingInvalidOwner.selector, abi.encode(address(SCW), address(0))
        );
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.addOwner.selector, address(SCW), address(0))
        );
    }

    function testFuzz_addOwner_RevertIf_ExistingOwner(string memory initName) public {
        User memory initialOwner = _createUser(initName);
        address[] memory owners = new address[](1);
        owners[0] = initialOwner.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(initialOwner.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(initialOwner.pub);
        _toRevert(
            IMultipleOwnerECDSAValidator.MOECDSA_AddingInvalidOwner.selector, abi.encode(address(SCW), initialOwner.pub)
        );
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.addOwner.selector, address(SCW), initialOwner.pub)
        );
    }

    function testFuzz_removeOwner(string memory initName, string memory secondName) public {
        vm.assume(keccak256(bytes(initName)) != keccak256(bytes(secondName)));
        User memory initialOwner = _createUser(initName);
        User memory secondOwner = _createUser(secondName);
        address[] memory owners = new address[](2);
        owners[0] = initialOwner.pub;
        owners[1] = secondOwner.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(initialOwner.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(initialOwner.pub);
        vm.expectEmit(true, true, true, true);
        emit MOECDSA_ValidatorOwnerRemoved(address(SCW), secondOwner.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.removeOwner.selector, address(SCW), secondOwner.pub)
        );
        assertFalse(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), secondOwner.pub), "Owner should be removed");
    }

    function testFuzz_removeOwner_RevertIf_NotOwner(
        string memory initName,
        string memory secondName,
        string memory maliciousName
    ) public {
        vm.assume(
            keccak256(bytes(initName)) != keccak256(bytes(secondName))
                && keccak256(bytes(initName)) != keccak256(bytes(maliciousName))
                && keccak256(bytes(secondName)) != keccak256(bytes(maliciousName))
        );
        User memory initialOwner = _createUser(initName);
        User memory secondOwner = _createUser(secondName);
        User memory malicious = _createUser(maliciousName);
        address[] memory owners = new address[](2);
        owners[0] = initialOwner.pub;
        owners[1] = secondOwner.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(initialOwner.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(malicious.pub);
        _toRevert(IMultipleOwnerECDSAValidator.MOECDSA_NotOwner.selector, abi.encode(malicious.pub));
        MULTIPLE_OWNER_ECDSA_VALIDATOR.removeOwner(address(SCW), secondOwner.pub);
    }

    function testFuzz_removeOwner_RevertIf_LastOwner(string memory initName) public {
        User memory initialOwner = _createUser(initName);
        address[] memory owners = new address[](1);
        owners[0] = initialOwner.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(initialOwner.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(initialOwner.pub);
        _toRevert(IMultipleOwnerECDSAValidator.MOECDSA_CannotRemoveLastOwner.selector, abi.encode(address(SCW)));
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.removeOwner.selector, address(SCW), initialOwner.pub)
        );
    }

    function testFuzz_removeOwner_RevertIf_InvalidOwner(
        string memory initName,
        string memory secondName,
        string memory thirdName
    ) public {
        vm.assume(
            keccak256(bytes(initName)) != keccak256(bytes(secondName))
                && keccak256(bytes(initName)) != keccak256(bytes(thirdName))
                && keccak256(bytes(secondName)) != keccak256(bytes(thirdName))
        );
        User memory initialOwner = _createUser(initName);
        User memory secondOwner = _createUser(secondName);
        User memory nonOwner = _createUser(thirdName);
        address[] memory owners = new address[](2);
        owners[0] = initialOwner.pub;
        owners[1] = secondOwner.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(initialOwner.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(initialOwner.pub);
        _toRevert(
            IMultipleOwnerECDSAValidator.MOECDSA_RemovingInvalidOwner.selector, abi.encode(address(SCW), nonOwner.pub)
        );
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.removeOwner.selector, address(SCW), nonOwner.pub)
        );
    }

    /*//////////////////////////////////////////////////////////////
                    SIGNATURE VALIDATION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_validateUserOp_WithVariousHashes(bytes32 userOpHash, string memory username) public {
        User memory user = _createUser(username);
        address[] memory owners = new address[](1);
        owners[0] = user.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(user.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(MULTIPLE_OWNER_ECDSA_VALIDATOR));
        bytes memory signature = _sign(userOpHash, user);
        userOp.signature = signature;
        vm.prank(address(SCW));
        uint256 validationResult = MULTIPLE_OWNER_ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation should succeed");
    }

    function testFuzz_validateUserOp_WithEthSign(bytes32 userOpHash, string memory username) public {
        User memory user = _createUser(username);
        address[] memory owners = new address[](1);
        owners[0] = user.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(user.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(MULTIPLE_OWNER_ECDSA_VALIDATOR));
        bytes memory signature = _ethSign(userOpHash, user);
        userOp.signature = signature;
        vm.prank(address(SCW));
        uint256 validationResult = MULTIPLE_OWNER_ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation with ethSign should succeed");
    }

    function testFuzz_validateUserOp_WithMultipleOwners(
        bytes32 userOpHash,
        string memory name1,
        string memory name2,
        string memory name3,
        uint8 signerIndex
    ) public {
        vm.assume(
            keccak256(bytes(name1)) != keccak256(bytes(name2)) && keccak256(bytes(name1)) != keccak256(bytes(name3))
                && keccak256(bytes(name2)) != keccak256(bytes(name3))
        );
        signerIndex = uint8(bound(signerIndex, 0, 2)); // Use 0, 1, or 2 to select a signer
        User memory user1 = _createUser(name1);
        User memory user2 = _createUser(name2);
        User memory user3 = _createUser(name3);
        address[] memory owners = new address[](3);
        owners[0] = user1.pub;
        owners[1] = user2.pub;
        owners[2] = user3.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(user1.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(MULTIPLE_OWNER_ECDSA_VALIDATOR));
        User memory signer;
        if (signerIndex == 0) {
            signer = user1;
        } else if (signerIndex == 1) {
            signer = user2;
        } else {
            signer = user3;
        }
        userOp.signature = _sign(userOpHash, signer);
        vm.prank(address(SCW));
        uint256 validationResult = MULTIPLE_OWNER_ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation should succeed with any valid owner");
    }

    function testFuzz_validateUserOp_RevertIf_InvalidSigner(
        bytes32 userOpHash,
        string memory ownerName,
        string memory maliciousName
    ) public {
        vm.assume(keccak256(bytes(ownerName)) != keccak256(bytes(maliciousName)));
        User memory owner = _createUser(ownerName);
        User memory malicious = _createUser(maliciousName);
        address[] memory owners = new address[](1);
        owners[0] = owner.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(MULTIPLE_OWNER_ECDSA_VALIDATOR));
        bytes memory signature = _sign(userOpHash, malicious);
        userOp.signature = signature;
        vm.prank(address(SCW));
        uint256 validationResult = MULTIPLE_OWNER_ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_FAILED, "UserOp validation should fail with invalid signer");
    }

    /*//////////////////////////////////////////////////////////////
                    ERC-1271 VALIDATION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_isValidSignatureWithSender(bytes32 hash, string memory username) public {
        User memory user = _createUser(username);
        address[] memory owners = new address[](1);
        owners[0] = user.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(user.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        bytes memory signature = _sign(hash, user);
        vm.prank(address(SCW));
        bytes4 result = MULTIPLE_OWNER_ECDSA_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0x1626ba7e), "Signature should be valid");
    }

    function testFuzz_isValidSignatureWithSender_WithEthSign(bytes32 hash, string memory username) public {
        User memory user = _createUser(username);
        address[] memory owners = new address[](1);
        owners[0] = user.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(user.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        bytes memory signature = _ethSign(hash, user);
        vm.prank(address(SCW));
        bytes4 result = MULTIPLE_OWNER_ECDSA_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0x1626ba7e), "Signature with ethSign should be valid");
    }

    function testFuzz_isValidSignatureWithSender_WithMultipleOwners(
        bytes32 hash,
        string memory name1,
        string memory name2,
        string memory name3,
        uint8 signerIndex
    ) public {
        vm.assume(
            keccak256(bytes(name1)) != keccak256(bytes(name2)) && keccak256(bytes(name1)) != keccak256(bytes(name3))
                && keccak256(bytes(name2)) != keccak256(bytes(name3))
        );
        signerIndex = uint8(bound(signerIndex, 0, 2)); // Use 0, 1, or 2 to select a signer
        User memory user1 = _createUser(name1);
        User memory user2 = _createUser(name2);
        User memory user3 = _createUser(name3);
        address[] memory owners = new address[](3);
        owners[0] = user1.pub;
        owners[1] = user2.pub;
        owners[2] = user3.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(user1.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        User memory signer;
        if (signerIndex == 0) {
            signer = user1;
        } else if (signerIndex == 1) {
            signer = user2;
        } else {
            signer = user3;
        }
        bytes memory signature = _sign(hash, signer);
        vm.prank(address(SCW));
        bytes4 result = MULTIPLE_OWNER_ECDSA_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0x1626ba7e), "Signature should be valid with any owner");
    }

    function testFuzz_isValidSignatureWithSender_RevertIf_InvalidSignature(
        bytes32 hash,
        string memory ownerName,
        string memory maliciousName
    ) public {
        vm.assume(keccak256(bytes(ownerName)) != keccak256(bytes(maliciousName)));
        User memory owner = _createUser(ownerName);
        User memory malicious = _createUser(maliciousName);
        address[] memory owners = new address[](1);
        owners[0] = owner.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(owner.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        bytes memory signature = _sign(hash, malicious);
        vm.prank(address(SCW));
        bytes4 result = MULTIPLE_OWNER_ECDSA_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0xffffffff), "Signature should be invalid");
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_signatureValidation(bytes32 hash, string memory username, uint8 vModifier) public {
        User memory user = _createUser(username);
        address[] memory owners = new address[](1);
        owners[0] = user.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(user.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        bytes memory validSignature = _sign(hash, user);
        // Make a modified signature by changing only the v value
        bytes memory modifiedSignature = new bytes(65);
        for (uint256 i; i < 65; ++i) {
            if (i == 64) {
                // Modify the v value (byte 64) but keep it in valid range (27-28)
                uint8 originalV = uint8(validSignature[i]);
                uint8 newV = ((originalV - 27) ^ (vModifier % 2)) + 27;
                modifiedSignature[i] = bytes1(newV);
            } else {
                modifiedSignature[i] = validSignature[i];
            }
        }
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(MULTIPLE_OWNER_ECDSA_VALIDATOR));
        userOp.signature = modifiedSignature;
        vm.prank(address(SCW));
        uint256 validationResult = MULTIPLE_OWNER_ECDSA_VALIDATOR.validateUserOp(userOp, hash);
        if (vModifier % 2 == 0) {
            // If we didn't change v, it should still be valid
            assertEq(validationResult, SIG_VALIDATION_SUCCESS, "Valid signature should succeed");
        } else {
            // If we changed v, it should fail
            assertEq(validationResult, SIG_VALIDATION_FAILED, "Modified signature should fail");
        }
    }

    function testFuzz_ownerRotation(string memory name1, string memory name2, string memory name3, string memory name4)
        public
    {
        vm.assume(
            keccak256(bytes(name1)) != keccak256(bytes(name2)) && keccak256(bytes(name1)) != keccak256(bytes(name3))
                && keccak256(bytes(name1)) != keccak256(bytes(name4)) && keccak256(bytes(name2)) != keccak256(bytes(name3))
                && keccak256(bytes(name2)) != keccak256(bytes(name4)) && keccak256(bytes(name3)) != keccak256(bytes(name4))
        );
        User memory user1 = _createUser(name1);
        User memory user2 = _createUser(name2);
        User memory user3 = _createUser(name3);
        User memory user4 = _createUser(name4);
        address[] memory owners = new address[](2);
        owners[0] = user1.pub;
        owners[1] = user2.pub;
        bytes memory initData = abi.encode(owners);
        _installModule(user1.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        vm.prank(user1.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.addOwner.selector, address(SCW), user3.pub)
        );
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), user3.pub), "User3 should be added");
        vm.prank(user2.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.removeOwner.selector, address(SCW), user1.pub)
        );
        assertFalse(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), user1.pub), "User1 should be removed");
        vm.prank(user3.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.addOwner.selector, address(SCW), user4.pub)
        );
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), user4.pub), "User4 should be added");
        bytes32 testHash = keccak256("test message");
        bytes memory signature = _sign(testHash, user4);
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(MULTIPLE_OWNER_ECDSA_VALIDATOR));
        userOp.signature = signature;
        vm.prank(address(SCW));
        uint256 validationResult = MULTIPLE_OWNER_ECDSA_VALIDATOR.validateUserOp(userOp, testHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "New owner signature should be valid");
        bytes memory invalidSignature = _sign(testHash, user1);
        userOp.signature = invalidSignature;
        vm.prank(address(SCW));
        validationResult = MULTIPLE_OWNER_ECDSA_VALIDATOR.validateUserOp(userOp, testHash);
        assertEq(validationResult, SIG_VALIDATION_FAILED, "Removed owner signature should be invalid");
    }

    function testFuzz_multipleOwners_WithDifferentSignatures(bytes32 hash, uint8 ownerCount) public {
        ownerCount = uint8(bound(ownerCount, 2, 5));
        User[] memory users = new User[](ownerCount);
        address[] memory owners = new address[](ownerCount);
        for (uint8 i; i < ownerCount; ++i) {
            users[i] = _createUser(string(abi.encodePacked("user", i)));
            owners[i] = users[i].pub;
        }
        bytes memory initData = abi.encode(owners);
        _installModule(owners[0], SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), initData);
        for (uint8 i; i < ownerCount; ++i) {
            bytes memory signature = _sign(hash, users[i]);
            PackedUserOperation memory userOp = _createUserOp(address(SCW), address(MULTIPLE_OWNER_ECDSA_VALIDATOR));
            userOp.signature = signature;
            vm.prank(address(SCW));
            uint256 validationResult = MULTIPLE_OWNER_ECDSA_VALIDATOR.validateUserOp(userOp, hash);
            assertEq(
                validationResult,
                SIG_VALIDATION_SUCCESS,
                string(abi.encodePacked("Signature from owner ", i, " should be valid"))
            );
        }
    }

    function testFuzz_multipleWallets(uint8 walletCount, uint256 ownerSeed) public {
        walletCount = uint8(bound(walletCount, 1, 5));
        address[] memory wallets = new address[](walletCount);
        address[] memory owners = new address[](walletCount);
        for (uint8 i; i < walletCount; ++i) {
            uint256 privateKey = uint256(keccak256(abi.encode(ownerSeed, i)));
            privateKey = bound(privateKey, 1, type(uint256).max - 1); // Ensure valid private key
            owners[i] = vm.addr(privateKey);
            wallets[i] = address(uint160(uint256(keccak256(abi.encode("wallet", i)))));
            vm.etch(wallets[i], address(SCW).code);
            vm.startPrank(wallets[i]);
            address[] memory walletsOwners = new address[](1);
            walletsOwners[0] = owners[i];
            bytes memory initData = abi.encode(walletsOwners);
            MULTIPLE_OWNER_ECDSA_VALIDATOR.onInstall(initData);
            vm.stopPrank();
            assertTrue(
                MULTIPLE_OWNER_ECDSA_VALIDATOR.isInitialized(wallets[i]), "Validator should be initialized for wallet"
            );
            assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(wallets[i], owners[i]), "Owner should be set for wallet");
        }
        for (uint8 i; i < walletCount; ++i) {
            for (uint8 j; j < walletCount; ++j) {
                if (i != j) {
                    assertTrue(
                        MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(wallets[i], owners[i]),
                        "Original owner should be maintained"
                    );
                    assertFalse(
                        MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(wallets[i], owners[j]),
                        "Cross-wallet owner check should fail"
                    );
                }
            }
        }
    }

    function testFuzz_validateWithInvalidModule(bytes32 hash, string memory username) public {
        User memory user = _createUser(username);
        PackedUserOperation memory userOp = _createUserOp(address(SCW), address(MULTIPLE_OWNER_ECDSA_VALIDATOR));
        bytes memory signature = _sign(hash, user);
        userOp.signature = signature;
        vm.prank(address(SCW));
        uint256 validationResult = MULTIPLE_OWNER_ECDSA_VALIDATOR.validateUserOp(userOp, hash);
        assertEq(validationResult, SIG_VALIDATION_FAILED, "UserOp should fail with uninstalled validator");
    }
}
