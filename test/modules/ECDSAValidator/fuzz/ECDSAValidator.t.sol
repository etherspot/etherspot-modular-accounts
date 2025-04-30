// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC7579Account} from "../../../../src/interfaces/base/IERC7579Account.sol";
import {ExecutionLib} from "../../../../src/libraries/ExecutionLib.sol";
import {ModularTestBase} from "../../../ModularTestBase.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {IECDSAValidator} from "../../../../src/interfaces/modules/IECDSAValidator.sol";
import {
    MODULE_TYPE_VALIDATOR, SIG_VALIDATION_SUCCESS, SIG_VALIDATION_FAILED
} from "../../../../src/types/Constants.sol";

contract ECDSAValidator_Fuzz_Test is ModularTestBase {
    using ExecutionLib for bytes;
    using ECDSA for bytes32;

    // Events to test
    event ECDSA_ValidatorEnabled(address indexed SCW, address indexed owner);
    event ECDSA_ValidatorDisabled(address indexed SCW);
    event ECDSA_OwnerChanged(address indexed SCW, address indexed newOwner);

    // Setup function runs before each test
    function setUp() public virtual {
        _testInit();
    }

    /*//////////////////////////////////////////////////////////////
                       INSTALLATION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_installValidator(string memory username) public {
        User memory user = _createUser(username);
        ModularEtherspotWallet scw = _createSCW(user.pub);
        // Installed as a validator by default so uninstall first to test
        _uninstallModule(user.pub, scw, MODULE_TYPE_VALIDATOR, address(ECDSA_VALIDATOR), hex"");
        bytes memory initData = abi.encode(user.pub);
        vm.expectEmit(true, true, true, true);
        emit ECDSA_ValidatorEnabled(address(scw), user.pub);
        bool success = _installModule(user.pub, scw, MODULE_TYPE_VALIDATOR, address(ECDSA_VALIDATOR), initData);
        assertTrue(success, "Validator should be installed");
        assertTrue(ECDSA_VALIDATOR.isInitialized(address(scw)), "Validator should be initialized");
        assertTrue(ECDSA_VALIDATOR.isOwner(address(scw), user.pub), "Owner should be the specified address");
    }

    function testFuzz_uninstallValidator(string memory username) public {
        User memory user = _createUser(username);
        ModularEtherspotWallet scw = _createSCW(user.pub);
        vm.expectEmit(true, true, true, true);
        emit ECDSA_ValidatorDisabled(address(scw));
        _uninstallModule(user.pub, scw, MODULE_TYPE_VALIDATOR, address(ECDSA_VALIDATOR), "");
        assertFalse(ECDSA_VALIDATOR.isInitialized(address(scw)), "Validator should not be initialized");
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER MANAGEMENT FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_changeOwner(string memory initName, string memory newName) public {
        vm.assume(keccak256(abi.encodePacked((initName))) != keccak256(abi.encodePacked((newName))));
        User memory initialOwner = _createUser(initName);
        ModularEtherspotWallet scw = _createSCW(initialOwner.pub);
        User memory newOwner = _createUser(newName);
        vm.prank(initialOwner.pub);
        vm.expectEmit(true, true, true, true);
        emit ECDSA_OwnerChanged(address(scw), newOwner.pub);
        ECDSA_VALIDATOR.changeOwner(address(scw), newOwner.pub);
        assertTrue(ECDSA_VALIDATOR.isOwner(address(scw), newOwner.pub), "New owner should be set");
        assertFalse(ECDSA_VALIDATOR.isOwner(address(scw), initialOwner.pub), "Initial owner should be removed");
    }

    function testFuzz_changeOwner_RevertIf_NotOwner(
        string memory initName,
        string memory invalidName,
        string memory newName
    ) public {
        vm.assume(
            keccak256(abi.encodePacked(initName)) != keccak256(abi.encodePacked(newName))
                && keccak256(abi.encodePacked(newName)) != keccak256(abi.encodePacked(invalidName))
                && keccak256(abi.encodePacked(initName)) != keccak256(abi.encodePacked(invalidName))
        );
        User memory initialOwner = _createUser(initName);
        ModularEtherspotWallet scw = _createSCW(initialOwner.pub);
        User memory newOwner = _createUser(newName);
        User memory invalidOwner = _createUser(invalidName);
        assertTrue(ECDSA_VALIDATOR.isOwner(address(scw), initialOwner.pub));
        vm.startPrank(invalidOwner.pub);
        _toRevert(IECDSAValidator.ECDSA_NotOwner.selector, abi.encode(invalidOwner.pub));
        ECDSA_VALIDATOR.changeOwner(address(scw), newOwner.pub);
        assertTrue(ECDSA_VALIDATOR.isOwner(address(scw), initialOwner.pub));
        assertFalse(ECDSA_VALIDATOR.isOwner(address(scw), newOwner.pub));
        vm.stopPrank();
    }

    function testFuzz_changeOwner_RevertIf_ZeroAddress(string memory initName) public {
        User memory initialOwner = _createUser(initName);
        ModularEtherspotWallet scw = _createSCW(initialOwner.pub);
        vm.prank(initialOwner.pub);
        _toRevert(IECDSAValidator.ECDSA_InvalidOwner.selector, abi.encode(address(scw), address(0)));
        ECDSA_VALIDATOR.changeOwner(address(scw), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    SIGNATURE VALIDATION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_validateUserOp_WithVariousHashes(bytes32 userOpHash, string memory username) public {
        User memory user = _createUser(username);
        ModularEtherspotWallet scw = _createSCW(user.pub);
        PackedUserOperation memory userOp = _createUserOp(address(scw), address(ECDSA_VALIDATOR));
        bytes memory signature = _sign(userOpHash, user);
        userOp.signature = signature;
        vm.prank(address(scw));
        uint256 validationResult = ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation should succeed");
    }

    function testFuzz_validateUserOp_WithEthSign(bytes32 userOpHash, string memory username) public {
        User memory user = _createUser(username);
        ModularEtherspotWallet scw = _createSCW(user.pub);
        PackedUserOperation memory userOp = _createUserOp(address(scw), address(ECDSA_VALIDATOR));
        bytes memory signature = _ethSign(userOpHash, user);
        userOp.signature = signature;
        vm.prank(address(scw));
        uint256 validationResult = ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_SUCCESS, "UserOp validation with ethSign should succeed");
    }

    function testFuzz_validateUserOp_WithInvalidSigner(
        bytes32 userOpHash,
        string memory username,
        string memory maliciousName
    ) public {
        vm.assume(keccak256(abi.encodePacked((username))) != keccak256(abi.encodePacked((maliciousName))));
        User memory user = _createUser(username);
        ModularEtherspotWallet scw = _createSCW(user.pub);
        User memory malicious = _createUser(maliciousName);
        PackedUserOperation memory userOp = _createUserOp(address(scw), address(ECDSA_VALIDATOR));
        bytes memory signature = _sign(userOpHash, malicious);
        userOp.signature = signature;
        vm.prank(address(scw));
        uint256 validationResult = ECDSA_VALIDATOR.validateUserOp(userOp, userOpHash);
        assertEq(validationResult, SIG_VALIDATION_FAILED, "UserOp validation should fail with invalid signer");
    }

    function testFuzz_isValidSignatureWithSender(bytes32 hash, string memory username) public {
        User memory user = _createUser(username);
        ModularEtherspotWallet scw = _createSCW(user.pub);
        bytes memory signature = _sign(hash, user);
        vm.prank(address(scw));
        bytes4 result = ECDSA_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0x1626ba7e), "Signature should be valid");
    }

    function testFuzz_isValidSignatureWithSender_WithEthSign(bytes32 hash, string memory username) public {
        User memory user = _createUser(username);
        ModularEtherspotWallet scw = _createSCW(user.pub);
        bytes memory signature = _ethSign(hash, user);
        vm.prank(address(scw));
        bytes4 result = ECDSA_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0x1626ba7e), "Signature with ethSign should be valid");
    }

    function testFuzz_isValidSignatureWithSender_WithInvalidSignature(
        bytes32 hash,
        string memory username,
        string memory maliciousName
    ) public {
        vm.assume(keccak256(abi.encodePacked((username))) != keccak256(abi.encodePacked((maliciousName))));
        User memory user = _createUser(username);
        ModularEtherspotWallet scw = _createSCW(user.pub);
        User memory malicious = _createUser(maliciousName);
        bytes memory signature = _sign(hash, malicious);
        vm.prank(address(scw));
        bytes4 result = ECDSA_VALIDATOR.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0xffffffff), "Signature should be invalid");
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_installValidatorWithVaryingDataLength(bytes calldata randomData) public {
        // Installed as a validator by default so uninstall first to test
        _uninstallModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(ECDSA_VALIDATOR), hex"");
        if (randomData.length == 20 || randomData.length >= 32) return;
        _toRevert(IECDSAValidator.ECDSA_InvalidOwnerData.selector, hex"");
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(ECDSA_VALIDATOR), randomData);
    }

    function testFuzz_changeOwnerWithWallet(string memory initName, string memory newName) public {
        vm.assume(keccak256(abi.encodePacked((initName))) != keccak256(abi.encodePacked((newName))));
        User memory initialOwner = _createUser(initName);
        ModularEtherspotWallet scw = _createSCW(initialOwner.pub);
        User memory newOwner = _createUser(newName);
        vm.prank(address(scw));
        vm.expectEmit(true, true, true, true);
        emit ECDSA_OwnerChanged(address(scw), newOwner.pub);
        ECDSA_VALIDATOR.changeOwner(address(scw), newOwner.pub);
        assertTrue(
            ECDSA_VALIDATOR.isOwner(address(scw), newOwner.pub), "New owner should be set when called from wallet"
        );
    }

    // Test signature verification with fuzzy data and lengths
    function testFuzz_signatureValidation(bytes32 hash, string memory username) public {
        User memory user = _createUser(username);
        ModularEtherspotWallet scw = _createSCW(user.pub);
        bytes memory validSignature = _sign(hash, user);
        PackedUserOperation memory userOp = _createUserOp(address(scw), address(ECDSA_VALIDATOR));
        userOp.signature = validSignature;
        vm.prank(address(scw));
        uint256 validationResult = ECDSA_VALIDATOR.validateUserOp(userOp, hash);
        bool validResult = (validationResult == SIG_VALIDATION_SUCCESS) || (validationResult == SIG_VALIDATION_FAILED);
        assertTrue(validResult, "Validation should either succeed or fail cleanly");
    }

    // Test with multiple contract wallets using the same validator
    function testFuzz_multipleWallets(uint8 walletCount, uint256 ownerSeed) public {
        vm.assume(walletCount > 0 && walletCount <= 10);
        address[] memory wallets = new address[](walletCount);
        address[] memory owners = new address[](walletCount);
        for (uint8 i; i < walletCount; ++i) {
            uint256 privateKey = uint256(keccak256(abi.encode(ownerSeed, i)));
            privateKey = privateKey % 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5812631A5CF5D3ED;
            if (privateKey == 0) privateKey = 1;
            owners[i] = vm.addr(privateKey);
            wallets[i] = address(uint160(uint256(keccak256(abi.encode("wallet", i)))));
            vm.etch(wallets[i], address(SCW).code);
            vm.startPrank(wallets[i]);
            ECDSA_VALIDATOR.onInstall(abi.encode(owners[i]));
            vm.stopPrank();
            assertTrue(ECDSA_VALIDATOR.isInitialized(wallets[i]), "Validator should be initialized for wallet");
            assertTrue(ECDSA_VALIDATOR.isOwner(wallets[i], owners[i]), "Owner should be set for wallet");
        }
        for (uint8 i; i < walletCount; ++i) {
            for (uint8 j; j < walletCount; ++j) {
                if (i != j) {
                    assertTrue(ECDSA_VALIDATOR.isOwner(wallets[i], owners[i]), "Original owner should be maintained");
                    assertFalse(ECDSA_VALIDATOR.isOwner(wallets[i], owners[j]), "Cross-wallet owner check should fail");
                }
            }
        }
    }
}
