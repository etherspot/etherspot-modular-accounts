// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {ExecutionLib} from "ERC7579/libs/ExecutionLib.sol";
import {ModeLib} from "ERC7579/libs/ModeLib.sol";
import {SentinelListLib as SENTINEL} from "ERC7579/libs/SentinelList.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
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
    function test_installModule_revertIf_alreadyInstalled() public {
        // Install module
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(eoa.pub));
        // Expect uninstallation to revert as module already installed
        _toRevert(SENTINEL.LinkedList_EntryAlreadyInList.selector, abi.encode(address(rlv)));
        // Try to execute installation
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(eoa.pub));
    }

    /// @notice Tests that onInstall reverts when provided with empty data
    /// @dev Verifies the RLV_InvalidDataLength error is thrown for zero-length input data
    function test_onInstall_revertsWhen_emptyData() public {
        // Create empty data array
        bytes memory emptyData = "";
        // Expect revert with specific error when installing with empty data
        _toRevert(ResourceLockValidator.RLV_InvalidDataLength.selector, hex"");
        vm.prank(address(scw));
        rlv.onInstall(emptyData);
    }

    /// @notice Tests that onInstall reverts when provided with insufficient data length
    /// @dev Verifies the RLV_InvalidDataLength error is thrown for data shorter than required 20 bytes
    function test_onInstall_revertsWhen_dataLengthNineteenBytes() public {
        // Create data array with 19 bytes (1 byte short of minimum requirement)
        bytes memory shortData = new bytes(19);
        // Expect revert with specific error when installing with insufficient data
        _toRevert(ResourceLockValidator.RLV_InvalidDataLength.selector, hex"");
        vm.prank(address(scw));
        rlv.onInstall(shortData);
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
    function test_uninstallModule_revertIf_notInstalled() public {
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
        assertTrue(rlv.isModuleType(uint256(MODULE_TYPE_VALIDATOR)));
        assertFalse(rlv.isModuleType(uint256(MODULE_TYPE_HOOK)));
    }

    /// @notice Tests getCredibleAccountModule returns correct address
    function test_getCredibleAccountModule() public {
        // Install module
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(eoa.pub));
        // Check module address is correct
        assertEq(rlv.getCredibleAccountModule(), address(cam));
    }

    /// @notice Tests setCredibleAccountModule sets correct address
    function test_setCredibleAccountModule() public {
        // Install module
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(eoa.pub));
        // Set credible account module
        address newCAM = address(0x1234567890123456789012345678901234567890);
        vm.prank(deployer.pub);
        rlv.setCredibleAccountModule(newCAM);
        // Check module address is correct
        assertEq(rlv.getCredibleAccountModule(), newCAM);
    }

    /// @notice Tests setCredibleAccountModule reverts when not owner
    function test_setCredibleAccountModule_revertWhen_noOwner() public {
        // Install module
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(eoa.pub));
        // Set credible account module
        _toRevert(ResourceLockValidator.RLV_InvalidOwner.selector, hex"");
        vm.prank(alice.pub);
        rlv.setCredibleAccountModule(address(cam));
        // Check module address is correct
        assertEq(rlv.getCredibleAccountModule(), address(cam));
    }

    /// @notice Tests direct merkle signature validation
    /// @dev Verifies successful validation of merkle proofs with direct signatures
    function test_isValidSignatureWithSender_directMerkleSignature() public withRequiredModules {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Generate proof and merkle root (with ResourceLock hash as leaf)
        (bytes32[] memory proof, bytes32 merkleRoot,) = getTestProof(rlHash, true);
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, eoa);
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        // Check signature is valid and leaf is included in proof
        assertEq(rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig), ERC1271_MAGIC_VALUE);
    }

    /// @notice Tests direct merkle signature validation fails when hash not in proof
    /// @dev Verifies rejection of merkle proofs not containing the target hash
    function test_isValidSignatureWithSender_directMerkleSignature_revertIf_hashNotInProof()
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
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        // Expect revert as rlHash is not in proof
        _toRevert(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector, hex"");
        rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig);
    }

    /// @notice Tests direct merkle signature validation fails with invalid signer
    /// @dev Verifies rejection of merkle proofs signed by unauthorized accounts
    function test_isValidSignatureWithSender_directMerkleSignature_revertIf_invalidSigner()
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
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        // Check signature is valid and leaf is included in proof
        assertEq(rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig), ERC1271_INVALID);
    }

    /// @notice Tests eth-signed merkle signature validation
    /// @dev Verifies successful validation of merkle proofs with eth-signed signatures
    function test_isValidSignatureWithSender_ethSignedMerkleSignature() public withRequiredModules {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Generate proof and merkle root (with ResourceLock hash as leaf)
        (bytes32[] memory proof, bytes32 merkleRoot,) = getTestProof(rlHash, true);
        // Sign merkle root with eth prefix
        bytes memory sig = _ethSign(merkleRoot, eoa);
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        // Check signature is valid and leaf is included in proof
        assertEq(rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig), ERC1271_MAGIC_VALUE);
    }

    /// @notice Tests eth-signed merkle signature validation fails when hash not in proof
    /// @dev Verifies rejection of eth-signed merkle proofs not containing the target hash
    function test_isValidSignatureWithSender_ethSignedMerkleSignature_revertIf_hashNotInProof()
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
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        // Expect revert as rlHash is not in proof
        _toRevert(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector, hex"");
        rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig);
    }

    /// @notice Tests eth-signed merkle signature validation fails with invalid signer
    /// @dev Verifies rejection of eth-signed merkle proofs from unauthorized accounts
    function test_isValidSignatureWithSender_ethSignedMerkleSignature_revertIf_invalidSigner()
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
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        // Check signature is valid and leaf is included in proof
        assertEq(rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig), ERC1271_INVALID);
    }

    /// @notice Tests signature validation fails with empty signature
    /// @dev Verifies rejection of empty signature bytes
    function test_isValidSignatureWithSender_revertIf_emptySignature() public withRequiredModules {
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
    function test_isValidSignatureWithSender_revertIf_malformedSignature() public withRequiredModules {
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
    function test_isValidSignatureWithSender_revertIf_invalidSignatureLength() public withRequiredModules {
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
    function test_isValidSignatureWithSender_revertIf_emptyProofArray() public withRequiredModules {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Empty proof array
        bytes32[] memory emptyProof = new bytes32[](0);
        bytes32 merkleRoot = keccak256(abi.encodePacked(rlHash));
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, eoa);
        bytes memory compositeSig = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(emptyProof));
        // Expect revert
        _toRevert(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector, hex"");
        rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig);
    }

    /// @notice Tests signature validation fails with invalid proof length
    /// @dev Verifies rejection of merkle proofs exceeding maximum allowed length
    function test_isValidSignatureWithSender_revertIf_invalidProofLength() public withRequiredModules {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Create oversized proof array
        bytes32[] memory oversizedProof = new bytes32[](33); // Typically merkle proofs shouldn't exceed 32 levels
        bytes32 merkleRoot = keccak256(abi.encodePacked(rlHash));
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, eoa);
        bytes memory compositeSig =
            bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(oversizedProof));
        // Expect revert
        _toRevert(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector, hex"");
        rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig);
    }

    /// @notice Tests signature validation fails with malformed proof data
    /// @dev Verifies rejection of merkle proofs with invalid node format
    function test_isValidSignatureWithSender_revertIf_malformedProofData() public withRequiredModules {
        // Create ResourceLock and hash of ResourceLock
        ResourceLock memory rl = _generateResourceLock(address(scw), sessionKey.pub);
        bytes32 rlHash = _buildResourceLockHash(rl);
        // Create malformed proof with invalid data
        bytes32[] memory malformedProof = new bytes32[](1);
        malformedProof[0] = bytes32(0); // Invalid proof node
        bytes32 merkleRoot = keccak256(abi.encodePacked(rlHash));
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, eoa);
        bytes memory compositeSig =
            bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(malformedProof));
        // Expect revert
        _toRevert(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector, hex"");
        rlv.isValidSignatureWithSender(eoa.pub, rlHash, compositeSig);
    }

    /// @notice Tests UserOperation validation with direct merkle signature
    /// @dev Verifies successful execution of UserOp with direct merkle proof signature
    function test_validateUserOp_directMerkleSignature() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        _executeUserOp(op);
    }

    /// @notice Tests batch UserOperation validation with direct merkle signature
    /// @dev Verifies successful execution of UserOp batch with direct merkle proof signature
    function test_validateUserOp_batch_directMerkleSignature() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpBatchWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation with large TokenData array using direct merkle signature
    /// @dev Verifies successful handling of ResourceLock containing 5 token configurations
    function test_validateUserOp_directMerkleSignature_largeTokenData() public withRequiredModules {
        // Create UserOp
        PackedUserOperation memory op = _createUserOp(address(scw), address(rlv));
        // Create TokenData array with 10 entries
        TokenData[] memory tokens = new TokenData[](5);
        for (uint256 i; i < 5; ++i) {
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
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        _executeUserOp(op);
        // Check locked tokens
        ICredibleAccountModule.LockedToken[] memory locked = cam.getLockedTokensForSessionKey(sessionKey.pub);
        assertEq(locked.length, 5);
        for (uint256 i; i < 5; ++i) {
            assertEq(locked[i].token, tokens[i].token);
            assertEq(locked[i].lockedAmount, tokens[i].amount);
        }
    }

    /// @notice Tests UserOperation validation fails with invalid merkle proof
    /// @dev Verifies rejection of UserOp when merkle proof doesn't contain target hash
    function test_validateUserOp_directMerkleSignature_revertIf_hashNotInProof() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, false);
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, sessionKey);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        _toRevert(
            IEntryPoint.FailedOpWithRevert.selector,
            abi.encode(0, AA23, abi.encodeWithSelector(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector))
        );
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation fails with invalid direct merkle signature
    /// @dev Verifies rejection of UserOp with unauthorized direct merkle signature
    function test_validateUserOp_directMerkleSignature_revertIf_invalidSigner() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, sessionKey);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation with eth-signed merkle signature
    /// @dev Verifies successful execution of UserOp with eth-signed merkle proof
    function test_validateUserOp_ethSignedMerkleSignature() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root directly
        bytes memory sig = _ethSign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation batch validation with eth-signed merkle signature
    /// @dev Verifies successful execution of UserOp batch with eth-signed merkle proof
    function test_validateUserOp_batch_ethSignedMerkleSignature() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpBatchWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root directly
        bytes memory sig = _ethSign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation with large TokenData array using eth-signed merkle signature
    /// @dev Verifies successful handling of ResourceLock containing 5 token configurations
    function test_validateUserOp_ethSignedMerkleSignature_largeTokenData() public withRequiredModules {
        // Create UserOp
        PackedUserOperation memory op = _createUserOp(address(scw), address(rlv));
        // Create TokenData array with 10 entries
        TokenData[] memory tokens = new TokenData[](5);
        for (uint256 i; i < 5; ++i) {
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
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        _executeUserOp(op);
        // Check locked tokens
        ICredibleAccountModule.LockedToken[] memory locked = cam.getLockedTokensForSessionKey(sessionKey.pub);
        assertEq(locked.length, 5);
        for (uint256 i; i < 5; ++i) {
            assertEq(locked[i].token, tokens[i].token);
            assertEq(locked[i].lockedAmount, tokens[i].amount);
        }
    }

    /// @notice Tests UserOperation validation fails with invalid eth-signed merkle proof
    /// @dev Verifies rejection of UserOp when merkle proof doesn't contain target hash
    function test_validateUserOp_ethSignedMerkleSignature_revertIf_hashNotInProof() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, false);
        // Sign merkle root directly
        bytes memory sig = _ethSign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        _toRevert(
            IEntryPoint.FailedOpWithRevert.selector,
            abi.encode(0, AA23, abi.encodeWithSelector(ResourceLockValidator.RLV_ResourceLockHashNotInProof.selector))
        );
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation fails with invalid eth-signed merkle signature
    /// @dev Verifies rejection of UserOp with unauthorized eth-signed merkle signature
    function test_validateUserOp_ethSignedMerkleSignature_revertIf_invalidSigner() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root directly
        bytes memory sig = _sign(merkleRoot, sessionKey);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
    }

    // NOTE: This test is for testing specific signatures to check correct unpacking
    // Replace the op.signature with your own, add logs and run test
    // Test will fail with RLV_ResourceLockHashNotInProof()
    function test_signature_unpacking() public withRequiredModules {
        vm.skip(true);
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Use predefined sig
        op.signature =
            hex"137ad66810b0325f2820c1f9160c2076a1607e5fd7010c4b02368b3905bccef1222086c638e9d828464dcc6330517430cd93516969b23612e3e41199f65950621b4a2c9276c86b3c670b424ab981c89c53f858e870f31a2999cf52353837897362bc36789e7a1e281436464229828f817d6612f7b477d66591ff96a9e064bcc98a";
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation fails with invalid target address in single call
    /// @dev Verifies rejection of UserOp when target is not the credibleAccountModule
    function test_validateUserOp_single_revertIf_invalidTarget() public withRequiredModules {
        // Create UserOp with ResourceLock but modify target to invalid address
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);

        // Modify the callData to have an invalid target (use address(0) as invalid target)
        bytes memory invalidCallData = _createCallDataWithInvalidTarget(address(0));
        op.callData = invalidCallData;

        // Sign merkle root with EOA
        bytes memory sig = _sign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));

        _toRevert(
            IEntryPoint.FailedOpWithRevert.selector,
            abi.encode(0, AA23, abi.encodeWithSelector(ResourceLockValidator.RLV_InvalidTarget.selector, address(0)))
        );
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation fails with non-zero value in single call
    /// @dev Verifies rejection of UserOp when value is not zero
    function test_validateUserOp_single_revertIf_nonZeroValue() public withRequiredModules {
        // Create UserOp with ResourceLock but modify value to non-zero
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);

        // Modify the callData to have non-zero value
        bytes memory invalidCallData = _createCallDataWithNonZeroValue(1 ether);
        op.callData = invalidCallData;

        // Sign merkle root with EOA
        bytes memory sig = _sign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));

        _toRevert(
            IEntryPoint.FailedOpWithRevert.selector,
            abi.encode(0, AA23, abi.encodeWithSelector(ResourceLockValidator.RLV_NonZeroValue.selector, 1 ether))
        );
        _executeUserOp(op);
    }

    /// @notice Tests UserOperation validation fails with invalid selector in single call
    /// @dev Verifies rejection of UserOp when function selector is not enableSessionKey
    function test_validateUserOp_single_revertIf_invalidSelector() public withRequiredModules {
        // Create UserOp with ResourceLock but modify selector to invalid one
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);

        // Modify the callData to have invalid selector (use transfer selector as example)
        bytes memory invalidCallData = _createCallDataWithInvalidSelector(IERC20.transfer.selector);
        op.callData = invalidCallData;

        // Sign merkle root with EOA
        bytes memory sig = _sign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));

        _toRevert(
            IEntryPoint.FailedOpWithRevert.selector,
            abi.encode(
                0,
                AA23,
                abi.encodeWithSelector(ResourceLockValidator.RLV_InvalidSelector.selector, IERC20.transfer.selector)
            )
        );
        _executeUserOp(op);
    }

    /// @notice Tests batch UserOperation validation fails with invalid batch length
    /// @dev Verifies rejection of UserOp when batch contains more than one execution
    function test_validateUserOp_batch_revertIf_invalidBatchLength() public withRequiredModules {
        // Create UserOp with ResourceLock but modify batch to have multiple executions
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpBatchWithResourceLock(address(scw), sessionKey, true);

        // Modify the callData to have multiple batch executions
        bytes memory invalidCallData = _createCallDataWithMultipleBatchExecutions();
        op.callData = invalidCallData;

        // Sign merkle root with EOA
        bytes memory sig = _sign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));

        _toRevert(
            IEntryPoint.FailedOpWithRevert.selector,
            abi.encode(0, AA23, abi.encodeWithSelector(ResourceLockValidator.RLV_InvalidBatchLength.selector, 2))
        );
        _executeUserOp(op);
    }

    /// @notice Tests batch UserOperation validation fails with invalid target address
    /// @dev Verifies rejection of UserOp when batch target is not the credibleAccountModule
    function test_validateUserOp_batch_revertIf_invalidTarget() public withRequiredModules {
        // Create UserOp with ResourceLock but modify batch target to invalid address
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpBatchWithResourceLock(address(scw), sessionKey, true);

        // Modify the callData to have invalid target in batch
        bytes memory invalidCallData = _createBatchCallDataWithInvalidTarget(address(0));
        op.callData = invalidCallData;

        // Sign merkle root with EOA
        bytes memory sig = _sign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));

        _toRevert(
            IEntryPoint.FailedOpWithRevert.selector,
            abi.encode(0, AA23, abi.encodeWithSelector(ResourceLockValidator.RLV_InvalidTarget.selector, address(0)))
        );
        _executeUserOp(op);
    }

    /// @notice Tests batch UserOperation validation fails with non-zero value
    /// @dev Verifies rejection of UserOp when batch execution has non-zero value
    function test_validateUserOp_batch_revertIf_nonZeroValue() public withRequiredModules {
        // Create UserOp with ResourceLock but modify batch value to non-zero
        (PackedUserOperation memory op,, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpBatchWithResourceLock(address(scw), sessionKey, true);

        // Modify the callData to have non-zero value in batch
        bytes memory invalidCallData = _createBatchCallDataWithNonZeroValue(1 ether);
        op.callData = invalidCallData;

        // Sign merkle root with EOA
        bytes memory sig = _sign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));

        _toRevert(
            IEntryPoint.FailedOpWithRevert.selector,
            abi.encode(0, AA23, abi.encodeWithSelector(ResourceLockValidator.RLV_NonZeroValue.selector, 1 ether))
        );
        _executeUserOp(op);
    }

    /// @notice Tests that bidHash is properly recorded after successful validation
    /// @dev Verifies bidHash is marked as consumed after UserOp execution
    function test_validateUserOp_recordsBidHashAfterSuccess() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op, ResourceLock memory rl, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root with EOA
        bytes memory sig = _sign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        // Verify bidHash is not consumed before execution
        assertFalse(rlv.isConsumedBidHash(address(scw), rl.bidHash));
        // Execute UserOp successfully
        _executeUserOp(op);
        // Verify bidHash is now marked as consumed
        assertTrue(rlv.isConsumedBidHash(address(scw), rl.bidHash));
    }

    /// @notice Tests that validation fails when bidHash is already consumed
    /// @dev Verifies rejection of UserOp with previously used bidHash
    function test_validateUserOp_revertIf_bidHashAlreadyConsumed() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op, ResourceLock memory rl, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root with EOA
        bytes memory sig = _sign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        // Execute UserOp first time (should succeed)
        _executeUserOp(op);
        // Verify bidHash is consumed
        assertTrue(rlv.isConsumedBidHash(address(scw), rl.bidHash));
        // Try to execute same UserOp again (should fail)
        _toRevert(
            IEntryPoint.FailedOpWithRevert.selector,
            abi.encode(
                0,
                "AA23 reverted",
                abi.encodeWithSelector(ResourceLockValidator.RLV_BidHashAlreadyConsumed.selector, rl.bidHash)
            )
        );
        _executeUserOp(op);
    }

    /// @notice Tests bidHash recording with eth-signed message validation
    /// @dev Verifies bidHash is recorded when using eth-signed message path
    function test_validateUserOp_recordsBidHashWithEthSignedMessage() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op, ResourceLock memory rl, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root with eth-signed message
        bytes memory sig = _ethSign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        // Verify bidHash is not consumed before execution
        assertFalse(rlv.isConsumedBidHash(address(scw), rl.bidHash));
        // Execute UserOp successfully
        _executeUserOp(op);
        // Verify bidHash is now marked as consumed
        assertTrue(rlv.isConsumedBidHash(address(scw), rl.bidHash));
    }

    /// @notice Tests bidHash consumption with batch UserOperation
    /// @dev Verifies bidHash recording works with batch operations
    function test_validateUserOp_batch_recordsBidHash() public withRequiredModules {
        // Create batch UserOp with ResourceLock
        (PackedUserOperation memory op, ResourceLock memory rl, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpBatchWithResourceLock(address(scw), sessionKey, true);
        // Sign merkle root with EOA
        bytes memory sig = _sign(merkleRoot, eoa);
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        // Verify bidHash is not consumed before execution
        assertFalse(rlv.isConsumedBidHash(address(scw), rl.bidHash));
        // Execute UserOp successfully
        _executeUserOp(op);
        // Verify bidHash is now marked as consumed
        assertTrue(rlv.isConsumedBidHash(address(scw), rl.bidHash));
    }

    /// @notice Tests that bidHash consumption happens only after successful validation
    /// @dev Verifies bidHash is not marked as consumed if validation fails for other reasons
    function test_validateUserOp_doesNotRecordBidHashOnValidationFailure() public withRequiredModules {
        // Create UserOp with ResourceLock
        (PackedUserOperation memory op, ResourceLock memory rl, bytes32[] memory proof, bytes32 merkleRoot) =
            _createUserOpWithResourceLock(address(scw), sessionKey, true);
        // Sign with wrong key (should cause validation failure)
        bytes memory sig = _sign(merkleRoot, sessionKey); // Wrong signer
        op.signature = bytes.concat(sig, abi.encodePacked(merkleRoot), _packProofForSignature(proof));
        // Verify bidHash is not consumed before execution
        assertFalse(rlv.isConsumedBidHash(address(scw), rl.bidHash));
        // Execute UserOp (should fail validation)
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        _executeUserOp(op);
        // Verify bidHash is still not consumed after failed validation
        assertFalse(rlv.isConsumedBidHash(address(scw), rl.bidHash));
    }
}
