// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {MerkleProofLib} from "solady/src/utils/MerkleProofLib.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC7579Account} from "../../interfaces/base/IERC7579Account.sol";
import {ModeLib} from "../../libraries/ModeLib.sol";
import {ExecutionLib} from "../../libraries/ExecutionLib.sol";
import {IResourceLockValidator} from "../../interfaces/modules/IResourceLockValidator.sol";
import {
    CALLTYPE_SINGLE,
    MODULE_TYPE_VALIDATOR,
    SIG_VALIDATION_SUCCESS,
    SIG_VALIDATION_FAILED,
    ERC1271_MAGIC_VALUE,
    ERC1271_INVALID
} from "../../types/Constants.sol";
import {ResourceLock, TokenData, ValidatorStorage} from "../../types/Structs.sol";
import {CallType, ModeCode} from "../../types/Types.sol";

/// @title ResourceLockValidator
/// @author @cryptonoyaiba | Etherspot
/// @notice A validator module that supports resource locking with Merkle proofs
/// @dev Implements ECDSA signature validation with optional Merkle proof verification
contract ResourceLockValidator is IResourceLockValidator {
    using ECDSA for bytes32;
    using ModeLib for ModeCode;
    using ExecutionLib for bytes;

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct RLVValidatorStorage {
        address owner;
        uint256 nonce;
    }

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps smart account addresses to their validator configuration
    mapping(address => RLVValidatorStorage) public validatorStorage;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to install an already installed validator
    error RLV_AlreadyInstalled(address scw, address eoa);

    /// @notice Thrown when trying to use an uninstalled validator
    error RLV_NotInstalled(address scw);

    /// @notice Thrown when the owner address is invalid
    error RLV_InvalidOwner();

    /// @notice Thrown when a resource lock hash is not in the provided Merkle proof
    error RLV_ResourceLockHashNotInProof();

    /// @notice Thrown when a non-single call type is used
    error RLV_OnlyCallTypeSingle();

    /// @notice Thrown when a nonce missmatch occurs
    error RLV_InvalidNonce(uint256 expectedNonce, uint256 receivedNonce);

    /*//////////////////////////////////////////////////////////////
                        PUBLIC/EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the validator when installed in a smart account
    /// @dev Extracts owner address from installation data
    /// @param _data The installation data containing owner address
    /// @custom:events Emits RLV_ValidatorEnabled when successfully installed
    /// @custom:errors Various errors if initialization parameters are invalid
    function onInstall(bytes calldata _data) external override {
        address owner;
        // Check if data starts with a function selector (bootstrap method)
        if (_data.length >= 4 && _data[0] != 0) {
            if (_data.length >= 24) {
                // Try to extract owner from the last 20 bytes
                owner = address(bytes20(_data[_data.length - 20:]));
                if (owner == address(0)) {
                    bytes calldata actualData = _data[4:];
                    if (actualData.length >= 32) {
                        owner = abi.decode(actualData, (address));
                    }
                }
            }
        } else {
            // Direct method - extract from the end or decode directly
            if (_data.length >= 20) {
                owner = address(bytes20(_data[_data.length - 20:]));
            } else if (_data.length == 32) {
                owner = abi.decode(_data, (address));
            }
        }
        if (owner == address(0)) {
            revert RLV_InvalidOwner();
        }
        if (validatorStorage[msg.sender].owner != address(0)) {
            revert RLV_AlreadyInstalled(msg.sender, validatorStorage[msg.sender].owner);
        }
        validatorStorage[msg.sender].owner = owner;
        emit RLV_ValidatorEnabled(msg.sender, owner);
    }

    /// @notice Cleans up validator data when uninstalled from a smart account
    /// @dev Removes validator configuration for the calling smart account
    /// @param data parameter (required by interface)
    /// @custom:events Emits RLV_ValidatorDisabled when successfully uninstalled
    /// @custom:errors RLV_NotInstalled if not initialized for the smart account
    function onUninstall(bytes calldata data) external override {
        if (!_isInitialized(msg.sender)) revert RLV_NotInstalled(msg.sender);
        delete validatorStorage[msg.sender];
        emit RLV_ValidatorDisabled(msg.sender);
    }

    /// @notice Validates a user operation with either standard signature or Merkle proof
    /// @dev Implements the ERC-4337 validation interface with advanced verification
    /// @param userOp The packed user operation to validate
    /// @param userOpHash The hash of the user operation for signature verification
    /// @return uint256 Validation result (success or failure)
    /// @custom:errors RLV_ResourceLockHashNotInProof if Merkle proof verification fails
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        override
        returns (uint256)
    {
        bytes calldata signature = userOp.signature;
        address walletOwner = validatorStorage[msg.sender].owner;
        // Standard signature length - no proof packing
        if (signature.length == 65) {
            // standard ECDSA recover
            if (walletOwner == ECDSA.recover(userOpHash, signature)) {
                return SIG_VALIDATION_SUCCESS;
            }
            bytes32 sigHash = ECDSA.toEthSignedMessageHash(userOpHash);
            address recoveredSigner = ECDSA.recover(sigHash, signature);
            if (walletOwner != recoveredSigner) return SIG_VALIDATION_FAILED;
            return SIG_VALIDATION_SUCCESS;
        }
        // or if signature.length >= 65 (standard signature length + proof packing)
        ResourceLock memory rl = _getResourceLock(userOp.callData);
        bytes memory ecdsaSignature = signature[0:65];
        bytes32 root = bytes32(signature[65:97]); // 32 bytes
        bytes32[] memory proof = abi.decode(signature[97:], (bytes32[])); // Rest of bytes in signature
        if (!MerkleProofLib.verify(proof, root, _buildResourceLockHash(rl))) {
            revert RLV_ResourceLockHashNotInProof();
        }
        // check proof is signed
        if (walletOwner == ECDSA.recover(root, ecdsaSignature)) {
            _incrementNonce(msg.sender);
            return SIG_VALIDATION_SUCCESS;
        }
        bytes32 sigRoot = ECDSA.toEthSignedMessageHash(root);
        address recoveredMSigner = ECDSA.recover(sigRoot, ecdsaSignature);
        if (walletOwner != recoveredMSigner) return SIG_VALIDATION_FAILED;
        return SIG_VALIDATION_SUCCESS;
    }

    /// @notice ERC-1271 signature validation with Merkle proof support
    /// @dev Implements the ERC-1271 validation interface with advanced verification
    /// @param sender The address of the sender requesting validation (unused)
    /// @param hash The hash of the data that was signed
    /// @param signature The signature to validate (may include Merkle proof)
    /// @return bytes4 Magic value if signature is valid, error value otherwise
    /// @custom:errors RLV_ResourceLockHashNotInProof if Merkle proof verification fails
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        override
        returns (bytes4)
    {
        address walletOwner = validatorStorage[msg.sender].owner;
        if (signature.length == 65) {
            if (walletOwner == ECDSA.recover(hash, signature)) {
                return ERC1271_MAGIC_VALUE;
            }
            bytes32 sigHash = ECDSA.toEthSignedMessageHash(hash);
            address recoveredSigner = ECDSA.recover(sigHash, signature);
            if (walletOwner != recoveredSigner) return ERC1271_INVALID;
            return ERC1271_MAGIC_VALUE;
        }
        bytes memory ecdsaSig = signature[0:65];
        bytes32 root = bytes32(signature[65:97]);
        bytes32[] memory proof = abi.decode(signature[97:], (bytes32[]));
        if (!MerkleProofLib.verify(proof, root, hash)) {
            revert RLV_ResourceLockHashNotInProof();
        }
        // simple ecdsa verification
        if (walletOwner == ECDSA.recover(root, ecdsaSig)) {
            return ERC1271_MAGIC_VALUE;
        }
        bytes32 sigRoot = ECDSA.toEthSignedMessageHash(root);
        address recoveredMSigner = ECDSA.recover(sigRoot, ecdsaSig);
        if (walletOwner != recoveredMSigner) return ERC1271_INVALID;
        return ERC1271_MAGIC_VALUE;
    }

    /// @notice Checks if this module supports the specified module type
    /// @param typeID The module type identifier to check
    /// @return bool True if this module is a validator module
    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == MODULE_TYPE_VALIDATOR;
    }

    /// @notice Checks if the module is initialized for a specific smart account
    /// @param smartAccount Address of the smart account to check
    /// @return bool True if the module is initialized, false otherwise
    function isInitialized(address smartAccount) external view override returns (bool) {
        return _isInitialized(smartAccount);
    }

    /// @notice Returns nonce for specific smart account
    /// @param smartAccount Address of the smart account to check
    /// @return uint256 Current unused nonce
    function getNonce(address smartAccount) external view returns (uint256) {
        return validatorStorage[smartAccount].nonce;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL/PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if the validator is initialized for a smart account
    /// @param _smartAccount The address of the smart account
    /// @return bool True if initialized, false otherwise
    function _isInitialized(address _smartAccount) internal view returns (bool) {
        return validatorStorage[_smartAccount].owner != address(0);
    }

    /// @notice Extracts array information from calldata
    /// @dev Helper function to navigate complex calldata structures
    /// @param _data The calldata to extract information from
    /// @return offset The offset of the array in the calldata
    /// @return length The length of the array
    function _getArrayInfo(bytes calldata _data) internal pure returns (uint256 offset, uint256 length) {
        offset = uint256(bytes32(_data[260:292]));
        length = uint256(bytes32(_data[100 + offset:132 + offset]));
    }

    /// @notice Extracts a single TokenData struct from calldata
    /// @dev Helper function to decode token data from calldata
    /// @param _data The calldata to extract from
    /// @param basePos The base position in the calldata
    /// @return TokenData The extracted token data
    function _getSingleTokenData(bytes calldata _data, uint256 basePos) internal pure returns (TokenData memory) {
        return TokenData({
            token: address(uint160(uint256(bytes32(_data[basePos:basePos + 32])))),
            amount: uint256(bytes32(_data[basePos + 32:basePos + 64]))
        });
    }

    /// @notice Extracts a ResourceLock struct from user operation calldata
    /// @dev Parses complex calldata to extract resource lock information
    /// @param _callData The calldata from the user operation
    /// @return ResourceLock The extracted resource lock data
    /// @custom:errors RLV_OnlyCallTypeSingle if the call type is not single
    function _getResourceLock(bytes calldata _callData) internal view returns (ResourceLock memory) {
        if (bytes4(_callData[:4]) == IERC7579Account.execute.selector) {
            (CallType calltype,,,) = ModeLib.decode(ModeCode.wrap(bytes32(_callData[4:36])));
            if (calltype == CALLTYPE_SINGLE) {
                (,, bytes calldata execData) = ExecutionLib.decodeSingle(_callData[100:]);
                (uint256 arrayOffset, uint256 arrayLength) = _getArrayInfo(execData);
                TokenData[] memory td = new TokenData[](arrayLength);
                for (uint256 i; i < arrayLength; ++i) {
                    td[i] = _getSingleTokenData(execData, 132 + arrayOffset + (i * 64));
                }
                address scw = address(uint160(uint256(bytes32(execData[132:164]))));
                uint256 expectedNonce = validatorStorage[scw].nonce;
                uint256 receivedNonce = uint256(bytes32(execData[292:324]));
                if (receivedNonce != expectedNonce) {
                    revert RLV_InvalidNonce(expectedNonce, receivedNonce);
                }
                return ResourceLock({
                    chainId: uint256(bytes32(execData[100:132])),
                    smartWallet: scw,
                    sessionKey: address(uint160(uint256(bytes32(execData[164:196])))),
                    validAfter: uint48(uint256(bytes32(execData[196:228]))),
                    validUntil: uint48(uint256(bytes32(execData[228:260]))),
                    tokenData: td,
                    nonce: validatorStorage[scw].nonce
                });
            }
            revert RLV_OnlyCallTypeSingle();
        }
    }

    /// @notice Builds a unique hash for a resource lock
    /// @dev Combines chain ID, wallet, session key, validity period, token data, and nonce into a single hash
    /// @param _lock The ResourceLock struct containing all lock parameters
    /// @return bytes32 The unique hash representing this resource lock
    function _buildResourceLockHash(ResourceLock memory _lock) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _lock.chainId,
                _lock.smartWallet,
                _lock.sessionKey,
                _lock.validAfter,
                _lock.validUntil,
                _hashTokenData(_lock.tokenData),
                _lock.nonce
            )
        );
    }

    /// @notice Creates a hash of token data array
    /// @dev Efficiently hashes an array of TokenData structs into a single bytes32 value
    /// @param _data Array of TokenData structs containing token addresses and amounts
    /// @return bytes32 Hash of the encoded token data array
    function _hashTokenData(TokenData[] memory _data) internal pure returns (bytes32) {
        return keccak256(abi.encode(_data));
    }

    /// @notice Increments nonce for a smart account
    /// @param _smartAccount Address of the smart account to increment nonce for
    /// @return uint256 Returns latest unused nonce
    function _incrementNonce(address _smartAccount) internal returns (uint256) {
        uint256 newNonce = validatorStorage[_smartAccount].nonce + 1;
        validatorStorage[_smartAccount].nonce = newNonce;
        emit RLV_NonceUpdated(_smartAccount, newNonce);
        return newNonce;
    }
}
