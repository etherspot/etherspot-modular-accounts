// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {MerkleProofLib} from "solady/src/utils/MerkleProofLib.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import "ERC7579/libs/ModeLib.sol";
import "ERC7579/libs/ExecutionLib.sol";
import {IResourceLockValidator} from "../../interfaces/IResourceLockValidator.sol";
import {ResourceLock, TokenData} from "../../common/Structs.sol";
import {
    MODULE_TYPE_VALIDATOR,
    SIG_VALIDATION_SUCCESS,
    SIG_VALIDATION_FAILED,
    ERC1271_MAGIC_VALUE,
    ERC1271_INVALID
} from "../../common/Constants.sol";

contract ResourceLockValidator is IResourceLockValidator {
    using ECDSA for bytes32;
    using ModeLib for ModeCode;
    using ExecutionLib for bytes;

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct ValidatorStorage {
        address owner;
        bool enabled;
    }

    /*//////////////////////////////////////////////////////////////
                               MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(address => ValidatorStorage) public validatorStorage;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error RLV_AlreadyInstalled(address scw, address eoa);
    error RLV_NotInstalled(address scw);
    error RLV_ResourceLockHashNotInProof();
    error RLV_OnlyCallTypeSingle();

    /*//////////////////////////////////////////////////////////////
                      PUBLIC/EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function onInstall(bytes calldata _data) external override {
        address owner = address(bytes20(_data[_data.length - 20:]));
        if (validatorStorage[msg.sender].enabled) {
            revert RLV_AlreadyInstalled(msg.sender, validatorStorage[msg.sender].owner);
        }
        validatorStorage[msg.sender].owner = owner;
        validatorStorage[msg.sender].enabled = true;
        emit RLV_ValidatorEnabled(msg.sender, owner);
    }

    function onUninstall(bytes calldata) external override {
        if (!_isInitialized(msg.sender)) revert RLV_NotInstalled(msg.sender);
        delete validatorStorage[msg.sender];
        emit RLV_ValidatorDisabled(msg.sender);
    }

    // TODO: Need to figure out how to unpack resource lock data and hash
    // from UserOperation
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
            return SIG_VALIDATION_SUCCESS;
        }
        bytes32 sigRoot = ECDSA.toEthSignedMessageHash(root);
        address recoveredMSigner = ECDSA.recover(sigRoot, ecdsaSignature);
        if (walletOwner != recoveredMSigner) return SIG_VALIDATION_FAILED;
        return SIG_VALIDATION_SUCCESS;
    }

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

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == MODULE_TYPE_VALIDATOR;
    }

    function isInitialized(address smartAccount) external view override returns (bool) {
        return _isInitialized(smartAccount);
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL/PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _isInitialized(address _smartAccount) internal view returns (bool) {
        return validatorStorage[_smartAccount].enabled;
    }

    function _getArrayInfo(bytes calldata _data) internal pure returns (uint256 offset, uint256 length) {
        offset = uint256(bytes32(_data[260:292]));
        length = uint256(bytes32(_data[100 + offset:132 + offset]));
    }

    function _getSingleTokenData(bytes calldata _data, uint256 basePos) internal pure returns (TokenData memory) {
        return TokenData({
            token: address(uint160(uint256(bytes32(_data[basePos:basePos + 32])))),
            amount: uint256(bytes32(_data[basePos + 32:basePos + 64]))
        });
    }

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
                return ResourceLock({
                    chainId: uint256(bytes32(execData[100:132])),
                    smartWallet: address(uint160(uint256(bytes32(execData[132:164])))),
                    sessionKey: address(uint160(uint256(bytes32(execData[164:196])))),
                    validAfter: uint48(uint256(bytes32(execData[196:228]))),
                    validUntil: uint48(uint256(bytes32(execData[228:260]))),
                    tokenData: td,
                    nonce: uint256(bytes32(execData[292:324]))
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
}
