// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {ExecutionLib} from "ERC7579/libs/ExecutionLib.sol";
import {ModeLib} from "ERC7579/libs/ModeLib.sol";
import {SentinelListLib as SENTINEL} from "ERC7579/libs/SentinelList.sol";
import {ICredibleAccountModule} from "../../../../src/interfaces/ICredibleAccountModule.sol";
import {IResourceLockValidator} from "../../../../src/interfaces/IResourceLockValidator.sol";
import {ResourceLockValidator} from "../../../../src/modules/validators/ResourceLockValidator.sol";
import {
    ERC1271_INVALID,
    ERC1271_MAGIC_VALUE,
    MODULE_TYPE_HOOK,
    MODULE_TYPE_VALIDATOR
} from "../../../../src/common/Constants.sol";
import {HookType, ResourceLock, TokenData} from "../../../../src/common/Structs.sol";
import {ResourceLockValidatorTestUtils as TestUtils} from "../utils/ResourceLockValidatorTestUtils.sol";

contract ResourceLockValidator_Concrete_Test is TestUtils {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testInit();
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests successful module installation for ResourceLockValidator
    /// @dev Verifies event emission and installation status
    function test_installModule() public {
        // Expect the module installation event to be emitted
        vm.expectEmit({emitter: address(rlv)});
        emit IResourceLockValidator.RLV_ValidatorEnabled(address(scw), eoa.pub);
        // Expect the module installation to succeed
        assertTrue(_installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(eoa.pub)));
    }

    /// @notice Tests module installation reverts when already installed
    /// @dev Expects revert with LinkedList_EntryAlreadyInList error
    function test_installModule_RevertIf_AlreadyInstalled() public {
        // Install module
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(eoa.pub));
        // Expect uninstallation to revert as module already installed
        _toRevert(SENTINEL.LinkedList_EntryAlreadyInList.selector, abi.encode(address(rlv)));
        // Try to execute installation
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(eoa.pub));
    }

    /// @notice Tests successful module uninstallation
    /// @dev Verifies event emission and uninstallation status
    function test_uninstallModule() public {
        // Install module
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(eoa.pub));
        // Expect the module uninstallation event to be emitted
        vm.expectEmit({emitter: address(rlv)});
        emit IResourceLockValidator.RLV_ValidatorDisabled(address(scw));
        // Check module is uninstalled
        assertFalse(_uninstallModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), hex""));
    }

    /// @notice Tests uninstallation reverts when module not installed
    /// @dev Expects revert with RLV_NotInstalled error
    function test_uninstallModule_RevertIf_NotInstalled() public {
        // Prank as EOA
        vm.startPrank(eoa.pub);
        // Expect uninstallation to revert as module not installed
        _toRevert(ResourceLockValidator.RLV_NotInstalled.selector, abi.encode(eoa.pub));
        rlv.onUninstall(hex"");
        vm.stopPrank();
    }

    /// @notice Tests isInitialized returns correct status for different addresses
    /// @dev Verifies both positive and negative initialization checks
    function test_isInitialized() public {
        // Install module
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(eoa.pub));
        // Check module is installed
        assertTrue(rlv.isInitialized(address(scw)));
        assertFalse(rlv.isInitialized(address(eoa.pub)));
    }

    /// @notice Tests isModuleType returns correct type identification
    /// @dev Verifies module type checking for validator type
    function test_isModuleType() public {
        // Install module
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(eoa.pub));
        // Check module type is correct
        assertTrue(rlv.isModuleType(1));
        assertFalse(rlv.isModuleType(2));
    }

    /// @notice Tests direct hash signature validation
    /// @dev Verifies successful validation of EOA-signed direct hash
    function test_isValidSignatureWithSender_DirectHashSignature() public withRequiredModules {
        // Build UserOperation
        PackedUserOperation memory op = _createUserOp(address(scw), address(rlv));
        bytes32 hash = entrypoint.getUserOpHash(op);
        // Direct hash signature
        bytes memory sig = _sign(hash, eoa);
        assertEq(rlv.isValidSignatureWithSender(eoa.pub, hash, sig), ERC1271_MAGIC_VALUE);
    }

    /// @notice Tests direct hash signature validation fails with invalid signer
    /// @dev Verifies rejection of signatures from unauthorized accounts
    function test_isValidSignatureWithSender_DirectHashSignature_RevertIf_InvalidSigner() public withRequiredModules {
        // Build UserOperation
        PackedUserOperation memory op = _createUserOp(address(scw), address(rlv));
        bytes32 hash = entrypoint.getUserOpHash(op);
        // Direct hash signature
        bytes memory sig = _sign(hash, sessionKey);
        assertEq(rlv.isValidSignatureWithSender(eoa.pub, hash, sig), ERC1271_INVALID);
    }

    /// @notice Tests eth-signed message validation
    /// @dev Verifies successful validation of EOA eth-signed messages
    function test_isValidSignatureWithSender_EthSignedMessage() public withRequiredModules {
        // Build UserOperation
        PackedUserOperation memory op = _createUserOp(address(scw), address(rlv));
        bytes32 hash = entrypoint.getUserOpHash(op);
        // Sign the user operation
        bytes memory sig = _ethSign(hash, eoa);
        // Check signature is valid
        assertEq(rlv.isValidSignatureWithSender(eoa.pub, hash, sig), ERC1271_MAGIC_VALUE);
    }

    /// @notice Tests eth-signed message validation fails with invalid signer
    /// @dev Verifies rejection of eth-signed messages from unauthorized accounts
    function test_isValidSignatureWithSender_EthSignedMessage_RevertIf_InvalidSigner() public withRequiredModules {
        // Build UserOperation
        PackedUserOperation memory op = _createUserOp(address(scw), address(rlv));
        bytes32 hash = entrypoint.getUserOpHash(op);
        // Sign the user operation
        bytes memory sig = _ethSign(hash, sessionKey);
        // Prank as EOA
        assertEq(rlv.isValidSignatureWithSender(eoa.pub, hash, sig), ERC1271_INVALID);
    }

    /// @notice Tests direct merkle signature validation
    /// @dev Verifies successful validation of merkle proofs with direct signatures
    function test_isValidSignatureWithSender_DirectMerkleSignature() public withRequiredModules {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Generate proof and merkle root (with ResourceLock hash as leaf)
        (bytes32[] memory proof, bytes32 merkleRoot,) = getTestProof(rlHash, true);
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, eoa);
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        // Check signature is valid and leaf is included in proof
        assertEq(rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig), ERC1271_MAGIC_VALUE);
    }

    /// @notice Tests direct merkle signature validation fails when hash not in proof
    /// @dev Verifies rejection of merkle proofs not containing the target hash
    function test_isValidSignatureWithSender_DirectMerkleSignature_RevertIf_HashNotInProof()
        public
        withRequiredModules
    {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Generate proof and merkle root (with random hash as leaf)
        (bytes32[] memory proof, bytes32 merkleRoot,) = getTestProof(rlHash, false);
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, eoa);
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        // Expect revert as rlHash is not in proof
        _toRevert(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector, hex"");
        rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig);
    }

    /// @notice Tests direct merkle signature validation fails with invalid signer
    /// @dev Verifies rejection of merkle proofs signed by unauthorized accounts
    function test_isValidSignatureWithSender_DirectMerkleSignature_RevertIf_InvalidSigner()
        public
        withRequiredModules
    {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Generate proof and merkle root (with ResourceLock hash as leaf)
        (bytes32[] memory proof, bytes32 merkleRoot,) = getTestProof(rlHash, true);
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, sessionKey);
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        // Check signature is valid and leaf is included in proof
        assertEq(rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig), ERC1271_INVALID);
    }

    /// @notice Tests eth-signed merkle signature validation
    /// @dev Verifies successful validation of merkle proofs with eth-signed signatures
    function test_isValidSignatureWithSender_EthSignedMerkleSignature() public withRequiredModules {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Generate proof and merkle root (with ResourceLock hash as leaf)
        (bytes32[] memory proof, bytes32 merkleRoot,) = getTestProof(rlHash, true);
        // Sign merkle root with eth prefix
        bytes memory sig = _ethSign(merkleRoot, eoa);
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        // Check signature is valid and leaf is included in proof
        assertEq(rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig), ERC1271_MAGIC_VALUE);
    }

    /// @notice Tests eth-signed merkle signature validation fails when hash not in proof
    /// @dev Verifies rejection of eth-signed merkle proofs not containing the target hash
    function test_isValidSignatureWithSender_EthSignedMerkleSignature_RevertIf_HashNotInProof()
        public
        withRequiredModules
    {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Generate proof and merkle root (with random hash as leaf)
        (bytes32[] memory proof, bytes32 merkleRoot,) = getTestProof(rlHash, false);
        // Sign merkle root with eth prefix
        bytes memory sig = _sign(merkleRoot, eoa);
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        // Expect revert as rlHash is not in proof
        _toRevert(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector, hex"");
        rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig);
    }

    /// @notice Tests eth-signed merkle signature validation fails with invalid signer
    /// @dev Verifies rejection of eth-signed merkle proofs from unauthorized accounts
    function test_isValidSignatureWithSender_EthSignedMerkleSignature_RevertIf_InvalidSigner()
        public
        withRequiredModules
    {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Generate proof and merkle root (with ResourceLock hash as leaf)
        (bytes32[] memory proof, bytes32 merkleRoot,) = getTestProof(rlHash, true);
        // Sign merkle root with eth prefix
        bytes memory sig = _ethSign(merkleRoot, sessionKey);
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        // Check signature is valid and leaf is included in proof
        assertEq(rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig), ERC1271_INVALID);
    }

    /// @notice Tests signature validation fails with empty signature
    /// @dev Verifies rejection of empty signature bytes
    function test_isValidSignatureWithSender_RevertIf_EmptySignature() public withRequiredModules {
        // Build UserOperation
        PackedUserOperation memory op = _createUserOp(address(scw), address(rlv));
        bytes32 hash = entrypoint.getUserOpHash(op);
        // Empty signature
        bytes memory sig = hex"";
        _toRevert(bytes4(0), hex"");
        rlv.isValidSignatureWithSender(eoa.pub, hash, sig);
    }

    /// @notice Tests signature validation fails with malformed signature
    /// @dev Verifies rejection of signatures with incorrect format
    function test_isValidSignatureWithSender_RevertIf_MalformedSignature() public withRequiredModules {
        // Build UserOperation
        PackedUserOperation memory op = _createUserOp(address(scw), address(rlv));
        bytes32 hash = entrypoint.getUserOpHash(op);
        // Malformed signature (incorrect length)
        bytes memory sig = hex"1234";
        _toRevert(bytes4(0), hex"");
        rlv.isValidSignatureWithSender(eoa.pub, hash, sig);
    }

    /// @notice Tests signature validation fails with invalid signature length
    /// @dev Verifies rejection of signatures with incorrect length
    function test_isValidSignatureWithSender_RevertIf_InvalidSignatureLength() public withRequiredModules {
        // Build UserOperation
        PackedUserOperation memory op = _createUserOp(address(scw), address(rlv));
        bytes32 hash = entrypoint.getUserOpHash(op);
        // Invalid signature length (65 bytes + 1)
        bytes memory sig = bytes.concat(_sign(hash, eoa), hex"00");
        _toRevert(bytes4(0), hex"");
        rlv.isValidSignatureWithSender(eoa.pub, hash, sig);
    }

    /// @notice Tests signature validation fails with empty proof array
    /// @dev Verifies rejection of merkle proofs with no elements
    function test_isValidSignatureWithSender_RevertIf_EmptyProofArray() public withRequiredModules {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Empty proof array
        bytes32[] memory emptyProof = new bytes32[](0);
        bytes32 merkleRoot = keccak256(abi.encodePacked(rlHash));
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, eoa);
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(emptyProof));
        // Expect revert
        _toRevert(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector, hex"");
        rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig);
    }

    /// @notice Tests signature validation fails with invalid proof length
    /// @dev Verifies rejection of merkle proofs exceeding maximum allowed length
    function test_isValidSignatureWithSender_RevertIf_InvalidProofLength() public withRequiredModules {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Create oversized proof array
        bytes32[] memory oversizedProof = new bytes32[](33); // Typically merkle proofs shouldn't exceed 32 levels
        bytes32 merkleRoot = keccak256(abi.encodePacked(rlHash));
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, eoa);
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(oversizedProof));
        // Expect revert
        _toRevert(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector, hex"");
        rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig);
    }

    /// @notice Tests signature validation fails with malformed proof data
    /// @dev Verifies rejection of merkle proofs with invalid node format
    function test_isValidSignatureWithSender_RevertIf_MalformedProofData() public withRequiredModules {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Create malformed proof with invalid data
        bytes32[] memory malformedProof = new bytes32[](1);
        malformedProof[0] = bytes32(0); // Invalid proof node
        bytes32 merkleRoot = keccak256(abi.encodePacked(rlHash));
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, eoa);
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(malformedProof));
        // Expect revert
        _toRevert(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector, hex"");
        rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig);
    }

    /// @notice Tests UserOperation validation with direct signature
    /// @dev Verifies successful execution of UserOp with direct EOA signature
    function test_validateUserOp_DirectSignature() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Get hash of UserOp
        bytes32 hash = entrypoint.getUserOpHash(op);
        // Direct hash signature
        op.signature = _sign(hash, eoa);
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation fails with invalid direct signature
    /// @dev Verifies rejection of UserOp with unauthorized direct signature
    function test_validateUserOp_DirectSignature_RevertIf_InvalidSigner() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Get hash of UserOp
        bytes32 hash = entrypoint.getUserOpHash(op);
        // Direct hash signature
        op.signature = _sign(hash, sessionKey);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation with eth-signed message
    /// @dev Verifies successful execution of UserOp with eth-signed EOA signature
    function test_validateUserOp_EthSignedMessage() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Get hash of UserOp
        bytes32 hash = entrypoint.getUserOpHash(op);
        // Sign the user operation
        op.signature = _ethSign(hash, eoa);
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation fails with invalid eth-signed message
    /// @dev Verifies rejection of UserOp with unauthorized eth-signed signature
    function test_validateUserOp_EthSignedMessage_RevertIf_InvalidSigner() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Get hash of UserOp
        bytes32 hash = entrypoint.getUserOpHash(op);
        // Sign the user operation
        op.signature = _ethSign(hash, sessionKey);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation with direct merkle signature
    /// @dev Verifies successful execution of UserOp with direct merkle proof signature
    function test_validateUserOp_DirectMerkleSignature() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation with large TokenData array using direct merkle signature
    /// @dev Verifies successful handling of ResourceLock containing 10 token configurations
    function test_validateUserOp_DirectMerkleSignature_LargeTokenData() public withRequiredModules {
        // Create UserOp
        PackedUserOperation memory op = _createUserOp(address(scw), address(rlv));
        // Create TokenData array with 10 entries
        TokenData[] memory tokens = new TokenData[](10);
        for (uint256 i; i < 10; ++i) {
            tokens[i] = TokenData({token: vm.randomAddress(), amount: vm.randomUint()});
        }
        // Create ResourceLock with large TokenData array
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        rl.tokenData = tokens;
        // Generate proof and merkle root
        (bytes32[] memory proof, bytes32 merkleRoot,) = getTestProof(_buildResourceLockHash(rl), true);
        // Create UserOp calldata
        op.callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(cam), 0, abi.encodeWithSelector(cam.enableSessionKey.selector, abi.encode(rl))
                )
            )
        );
        // Sign merkle root with eth prefix
        bytes memory sig = _sign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        _executeUserOp(op);
        // Check locked tokens
        ICredibleAccountModule.LockedToken[] memory locked = cam.getLockedTokensForSessionKey(sessionKey.pub);
        assertEq(locked.length, 10);
        for (uint256 i; i < 10; ++i) {
            assertEq(locked[i].token, tokens[i].token);
            assertEq(locked[i].lockedAmount, tokens[i].amount);
        }
    }

    /// @notice Tests UserOperation validation fails with invalid merkle proof
    /// @dev Verifies rejection of UserOp when merkle proof doesn't contain target hash
    function test_validateUserOp_DirectMerkleSignature_RevertIf_HashNotInProof() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, false);
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, sessionKey);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        _toRevert(
            IEntryPoint.FailedOpWithRevert.selector,
            abi.encode(0, AA23, abi.encodeWithSelector(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector))
        );
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation fails with invalid direct merkle signature
    /// @dev Verifies rejection of UserOp with unauthorized direct merkle signature
    function test_validateUserOp_DirectMerkleSignature_RevertIf_InvalidSigner() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, sessionKey);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation with eth-signed merkle signature
    /// @dev Verifies successful execution of UserOp with eth-signed merkle proof
    function test_validateUserOp_EthSignedMerkleSignature() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root directly
        bytes memory sig = _ethSign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation with large TokenData array using eth-signed merkle signature
    /// @dev Verifies successful handling of ResourceLock containing 10 token configurations
    function test_validateUserOp_EthSignedMerkleSignature_LargeTokenData() public withRequiredModules {
        // Create UserOp
        PackedUserOperation memory op = _createUserOp(address(scw), address(rlv));
        // Create TokenData array with 10 entries
        TokenData[] memory tokens = new TokenData[](10);
        for (uint256 i; i < 10; ++i) {
            tokens[i] = TokenData({token: vm.randomAddress(), amount: vm.randomUint()});
        }
        // Create ResourceLock with large TokenData array
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        rl.tokenData = tokens;
        // Generate proof and merkle root
        (bytes32[] memory proof, bytes32 merkleRoot,) = getTestProof(_buildResourceLockHash(rl), true);
        // Create UserOp calldata
        op.callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(cam), 0, abi.encodeWithSelector(cam.enableSessionKey.selector, abi.encode(rl))
                )
            )
        );
        // Sign merkle root with eth prefix
        bytes memory sig = _ethSign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        _executeUserOp(op);
        // Check locked tokens
        ICredibleAccountModule.LockedToken[] memory locked = cam.getLockedTokensForSessionKey(sessionKey.pub);
        assertEq(locked.length, 10);
        for (uint256 i; i < 10; ++i) {
            assertEq(locked[i].token, tokens[i].token);
            assertEq(locked[i].lockedAmount, tokens[i].amount);
        }
    }

    /// @notice Tests UserOperation validation fails with invalid eth-signed merkle proof
    /// @dev Verifies rejection of UserOp when merkle proof doesn't contain target hash
    function test_validateUserOp_EthSignedMerkleSignature_RevertIf_HashNotInProof() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, false);
        // Sign merkle root directly
        bytes memory sig = _ethSign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        _toRevert(
            IEntryPoint.FailedOpWithRevert.selector,
            abi.encode(0, AA23, abi.encodeWithSelector(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector))
        );
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation fails with invalid eth-signed merkle signature
    /// @dev Verifies rejection of UserOp with unauthorized eth-signed merkle signature
    function test_validateUserOp_EthSignedMerkleSignature_RevertIf_InvalidSigner() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, sessionKey);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), abi.encode(proof));
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
    }
}
