// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {MerkleProofLib} from "solady/src/utils/MerkleProofLib.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import "ERC7579/libs/ModeLib.sol";
import "ERC7579/libs/ExecutionLib.sol";
import {IResourceLockValidator} from "../../interfaces/IResourceLockValidator.sol";
import {ICredibleAccountModule} from "../../interfaces/ICredibleAccountModule.sol";
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
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SignatureCheckerLib for address;

    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable owner;
    address public credibleAccountModule;

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
    mapping(address scw => EnumerableSet.AddressSet) private authorizedSessionKeys;
    mapping(address wallet => EnumerableSet.Bytes32Set) private consumedBidHashes;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error RLV_AlreadyInstalled(address scw, address eoa);
    error RLV_NotInstalled(address scw);
    error RLV_InvalidOwner();
    error RLV_InvalidCredibleAccountModule();
    error RLV_CredibleAccountModuleNotSet();
    error RLV_InvalidDataLength();
    error RLV_ResourceLockHashNotInProof();
    error RLV_InvalidTarget(address target);
    error RLV_InvalidSelector(bytes4 selector);
    error RLV_NonZeroValue(uint256 value);
    error RLV_InvalidCallType();
    error RLV_InvalidBatchLength(uint256 batchLength);
    error RLV_BidHashAlreadyConsumed(bytes32 bidHash);
    error RLV_SessionKeyAlreadyAuthorized(address sessionKey);
    error RLV_InvalidUserOpSender();

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (msg.sender != owner) revert RLV_InvalidOwner();
        _;
    }

    modifier onlyCredibleAccountModuleOrOwner() {
        if (credibleAccountModule == address(0)) revert RLV_CredibleAccountModuleNotSet();
        if (msg.sender != credibleAccountModule && msg.sender != owner) revert RLV_InvalidCredibleAccountModule();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) {
        if (_owner == address(0)) revert RLV_InvalidOwner();
        owner = _owner;
    }

    /*//////////////////////////////////////////////////////////////
                      PUBLIC/EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc IResourceLockValidator
    function onInstall(bytes calldata _data) external override {
        if (_data.length < 20) revert RLV_InvalidDataLength();
        address wallet = address(bytes20(_data[_data.length - 20:]));
        if (validatorStorage[msg.sender].enabled) {
            revert RLV_AlreadyInstalled(msg.sender, validatorStorage[msg.sender].owner);
        }
        validatorStorage[msg.sender].owner = wallet;
        validatorStorage[msg.sender].enabled = true;
        emit RLV_ValidatorEnabled(msg.sender, wallet);
    }

    // @inheritdoc IResourceLockValidator
    function onUninstall(bytes calldata) external override {
        if (!_isInitialized(msg.sender)) revert RLV_NotInstalled(msg.sender);
        delete consumedBidHashes[msg.sender];
        delete validatorStorage[msg.sender];
        emit RLV_ValidatorDisabled(msg.sender);
    }

    // @inheritdoc IResourceLockValidator
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        override
        returns (uint256)
    {
        if (credibleAccountModule == address(0)) revert RLV_CredibleAccountModuleNotSet();
        bytes calldata signature = userOp.signature;
        address walletOwner = validatorStorage[msg.sender].owner;
        if (msg.sender != userOp.sender) {
            revert RLV_InvalidUserOpSender();
        }
        ResourceLock memory rl = _getResourceLock(userOp.callData);
        // Nonce validation
        bytes memory ecdsaSignature = signature[0:65];
        bytes32 root = bytes32(signature[65:97]); // 32 bytes
        bytes32[] memory proof;
        if (signature.length > 97) {
            // Calculate how many proof elements we have
            uint256 proofCount = (signature.length - 97) / 32;
            // Create an array of the right size
            proof = new bytes32[](proofCount);
            // Extract each proof element
            for (uint256 i; i < proofCount; ++i) {
                uint256 startPos = 97 + (i * 32);
                proof[i] = bytes32(signature[startPos:startPos + 32]);
            }
        } else {
            // Empty proof
            proof = new bytes32[](0);
        }
        if (!MerkleProofLib.verify(proof, root, _buildResourceLockHash(rl))) {
            revert RLV_ResourceLockHashNotInProof();
        }
        if (consumedBidHashes[userOp.sender].contains(rl.bidHash)) {
            revert RLV_BidHashAlreadyConsumed(rl.bidHash);
        }
        if (authorizedSessionKeys[userOp.sender].contains(rl.sessionKey)) {
            revert RLV_SessionKeyAlreadyAuthorized(rl.sessionKey);
        }
        // check proof is signed
        if (walletOwner.isValidSignatureNow(root, ecdsaSignature)) {
            authorizedSessionKeys[userOp.sender].add(rl.sessionKey);
            consumedBidHashes[userOp.sender].add(rl.bidHash);
            return SIG_VALIDATION_SUCCESS;
        }
        bytes32 sigRoot = ECDSA.toEthSignedMessageHash(root);
        if (walletOwner.isValidSignatureNow(sigRoot, ecdsaSignature)) {
            authorizedSessionKeys[userOp.sender].add(rl.sessionKey);
            consumedBidHashes[userOp.sender].add(rl.bidHash);
            return SIG_VALIDATION_SUCCESS;
        }
        return SIG_VALIDATION_FAILED;
    }

    // @inheritdoc IResourceLockValidator
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        override
        returns (bytes4)
    {
        address walletOwner = validatorStorage[msg.sender].owner;
        bytes memory ecdsaSig = signature[0:65];
        bytes32 root = bytes32(signature[65:97]);
        bytes32[] memory proof;
        if (signature.length > 97) {
            // Calculate how many proof elements we have
            uint256 proofCount = (signature.length - 97) / 32;
            // Create an array of the right size
            proof = new bytes32[](proofCount);
            // Extract each proof element
            for (uint256 i; i < proofCount; ++i) {
                uint256 startPos = 97 + (i * 32);
                proof[i] = bytes32(signature[startPos:startPos + 32]);
            }
        } else {
            // Empty proof
            proof = new bytes32[](0);
        }
        if (!MerkleProofLib.verify(proof, root, hash)) {
            revert RLV_ResourceLockHashNotInProof();
        }
        // simple ecdsa verification
        if (walletOwner.isValidSignatureNow(root, ecdsaSig)) {
            return ERC1271_MAGIC_VALUE;
        }
        bytes32 sigRoot = ECDSA.toEthSignedMessageHash(root);
        if (walletOwner.isValidSignatureNow(sigRoot, ecdsaSig)) {
            return ERC1271_MAGIC_VALUE;
        }
        return ERC1271_INVALID;
    }

    // @inheritdoc IResourceLockValidator
    function getCredibleAccountModule() external view returns (address) {
        return credibleAccountModule;
    }

    // @inheritdoc IResourceLockValidator
    function setCredibleAccountModule(address _credibleAccountModule) external onlyOwner {
        if (_credibleAccountModule == address(0)) revert RLV_InvalidCredibleAccountModule();
        credibleAccountModule = _credibleAccountModule;
    }

    // @inheritdoc IResourceLockValidator
    function isConsumedBidHash(address _wallet, bytes32 _bidHash) external view returns (bool) {
        return consumedBidHashes[_wallet].contains(_bidHash);
    }

    // @inheritdoc IResourceLockValidator
    function isSessionKeyAuthorized(address _scw, address _sessionKey) external view returns (bool) {
        return authorizedSessionKeys[_scw].contains(_sessionKey);
    }

    // @inheritdoc IResourceLockValidator
    function removeSessionKeyAuthorization(address _scw, address _sessionKey)
        external
        onlyCredibleAccountModuleOrOwner
    {
        authorizedSessionKeys[_scw].remove(_sessionKey);
    }

    // @inheritdoc IResourceLockValidator
    function getAuthorizedSessionKeys(address _scw) external view returns (address[] memory) {
        return authorizedSessionKeys[_scw].values();
    }

    // @inheritdoc IResourceLockValidator
    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == MODULE_TYPE_VALIDATOR;
    }

    // @inheritdoc IResourceLockValidator
    function isInitialized(address smartAccount) external view override returns (bool) {
        return _isInitialized(smartAccount);
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL/PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if the validator is initialized for a given smart account
    /// @dev Returns the enabled status from the validator storage mapping
    /// @param _smartAccount The smart account address to check initialization for
    /// @return True if the validator is enabled for the smart account, false otherwise
    function _isInitialized(address _smartAccount) internal view returns (bool) {
        return validatorStorage[_smartAccount].enabled;
    }

    /// @notice Extracts array offset and length information from encoded call data
    /// @dev Parses specific byte positions to retrieve dynamic array metadata for token data
    /// @param _data The encoded call data containing array information
    /// @return offset The offset position where the array data begins
    /// @return length The number of elements in the array
    function _getArrayInfo(bytes calldata _data) internal pure returns (uint256 offset, uint256 length) {
        offset = uint256(bytes32(_data[292:324]));
        length = uint256(bytes32(_data[100 + offset:132 + offset]));
    }

    /// @notice Extracts a single TokenData struct from encoded call data at a specific position
    /// @dev Decodes token address and amount from 64 bytes of data (32 bytes each)
    /// @param _data The encoded call data containing token information
    /// @param _basePos The starting position in the data to read from
    /// @return TokenData struct containing the token address and amount
    function _getSingleTokenData(bytes calldata _data, uint256 _basePos) internal pure returns (TokenData memory) {
        return TokenData({
            token: address(uint160(uint256(bytes32(_data[_basePos:_basePos + 32])))),
            amount: uint256(bytes32(_data[_basePos + 32:_basePos + 64]))
        });
    }

    /// @notice Dynamically extracts resource lock data from user operation call data
    /// @dev Parses call data to extract ResourceLock parameters for both single and batch executions
    /// @param _callData The call data from the user operation to parse
    /// @return ResourceLock struct containing extracted session key parameters
    /// @custom:validation Validates call data format, target address, value, and function selector
    /// @custom:supports CALLTYPE_SINGLE and CALLTYPE_BATCH execution modes
    function _getResourceLock(bytes calldata _callData) internal view returns (ResourceLock memory) {
        if (bytes4(_callData[:4]) == IERC7579Account.execute.selector) {
            (CallType calltype,,,) = ModeLib.decode(ModeCode.wrap(bytes32(_callData[4:36])));
            if (calltype == CALLTYPE_SINGLE) {
                (address target, uint256 value, bytes calldata execData) = ExecutionLib.decodeSingle(_callData[100:]);
                if (target != address(credibleAccountModule)) {
                    revert RLV_InvalidTarget(target);
                }
                if (value != 0) {
                    revert RLV_NonZeroValue(value);
                }
                if (bytes4(execData[:4]) != ICredibleAccountModule.enableSessionKey.selector) {
                    revert RLV_InvalidSelector(bytes4(execData[:4]));
                }
                (uint256 arrayOffset, uint256 arrayLength) = _getArrayInfo(execData);
                TokenData[] memory td = new TokenData[](arrayLength);
                for (uint256 i; i < arrayLength; ++i) {
                    td[i] = _getSingleTokenData(execData, 132 + arrayOffset + (i * 64));
                }
                address scw = address(uint160(uint256(bytes32(execData[132:164]))));
                return ResourceLock({
                    chainId: uint256(bytes32(execData[100:132])),
                    smartWallet: scw,
                    sessionKey: address(uint160(uint256(bytes32(execData[164:196])))),
                    validAfter: uint48(uint256(bytes32(execData[196:228]))),
                    validUntil: uint48(uint256(bytes32(execData[228:260]))),
                    bidHash: bytes32(execData[260:292]),
                    tokenData: td
                });
            } else if (calltype == CALLTYPE_BATCH) {
                // NOTE: If batch call then it will should only contain a single UserOperation
                // so hardcoded values will hold here
                Execution[] calldata batchExecs = ExecutionLib.decodeBatch(_callData[100:]);
                for (uint256 i; i < batchExecs.length; ++i) {
                    if (batchExecs.length != 1) {
                        revert RLV_InvalidBatchLength(batchExecs.length);
                    }
                    if (batchExecs[0].target != address(credibleAccountModule)) {
                        revert RLV_InvalidTarget(batchExecs[0].target);
                    }
                    if (batchExecs[0].value != 0) {
                        revert RLV_NonZeroValue(batchExecs[0].value);
                    }
                    if (bytes4(batchExecs[i].callData[:4]) == bytes4(ICredibleAccountModule.enableSessionKey.selector))
                    {
                        bytes calldata lockData = batchExecs[i].callData;
                        uint256 dataOffset = 68; // Skip function selector + 64 bytes
                        uint256 arrayStart = dataOffset + 256;
                        uint256 tokenDataLength = uint256(bytes32(lockData[arrayStart:arrayStart + 32]));
                        TokenData[] memory td = new TokenData[](tokenDataLength);
                        for (uint256 j; j < tokenDataLength; ++j) {
                            uint256 tokenEntryStart = arrayStart + 32 + (j * 64);
                            address token =
                                address(uint160(uint256(bytes32(lockData[tokenEntryStart:tokenEntryStart + 32]))));
                            uint256 amount = uint256(bytes32(lockData[tokenEntryStart + 32:tokenEntryStart + 64]));
                            td[j] = TokenData({token: token, amount: amount});
                        }
                        return ResourceLock({
                            chainId: uint256(bytes32(lockData[dataOffset + 32:dataOffset + 64])),
                            smartWallet: address(uint160(uint256(bytes32(lockData[dataOffset + 64:dataOffset + 96])))),
                            sessionKey: address(uint160(uint256(bytes32(lockData[dataOffset + 96:dataOffset + 128])))),
                            validAfter: uint48(uint256(bytes32(lockData[dataOffset + 128:dataOffset + 160]))),
                            validUntil: uint48(uint256(bytes32(lockData[dataOffset + 160:dataOffset + 192]))),
                            bidHash: bytes32(lockData[dataOffset + 192:dataOffset + 224]),
                            tokenData: td
                        });
                    }
                    revert RLV_InvalidSelector(bytes4(batchExecs[i].callData[:4]));
                }
            } else {
                revert RLV_InvalidCallType();
            }
        }
        revert RLV_InvalidSelector(bytes4(_callData[:4]));
    }

    /// @notice Builds a unique hash for a resource lock
    /// @dev Combines chain ID, wallet, session key, validity period, token data, and bid hash into a single hash
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
                _lock.bidHash,
                abi.encode(_lock.tokenData)
            )
        );
    }
}
