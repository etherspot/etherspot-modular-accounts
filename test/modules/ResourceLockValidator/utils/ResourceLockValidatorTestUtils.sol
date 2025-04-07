// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "../../../../src/interfaces/base/IERC7579Account.sol";
import {ExecutionLib} from "../../../../src/libraries/ExecutionLib.sol";
import {ModeLib} from "../../../../src/libraries/ModeLib.sol";
import {ModularTestBase} from "../../../ModularTestBase.sol";
import {MODULE_TYPE_VALIDATOR} from "../../../../src/types/Constants.sol";
import {HookType} from "../../../../src/types/Enums.sol";
import {ResourceLock, TokenData} from "../../../../src/types/Structs.sol";

contract ResourceLockValidatorTestUtils is ModularTestBase {
    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier withRequiredModules() {
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), abi.encode(owners));
        _installHookViaMultiplexer(SCW, address(CREDIBLE_ACCOUNT_HOOK), HookType.GLOBAL);
        _installModule(
            eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), abi.encode(MODULE_TYPE_VALIDATOR)
        );
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(RESOURCE_LOCK_VALIDATOR), abi.encode(eoa.pub));
        vm.startPrank(address(SCW));
        _;
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createUserOpWithResourceLock(address _scw, User memory _user, bool _validProof)
        internal
        returns (PackedUserOperation memory op, ResourceLock memory rl, bytes32[] memory proof, bytes32 root)
    {
        // Create base UserOp
        op = _createUserOp(_scw, address(RESOURCE_LOCK_VALIDATOR));
        // Create ResourceLock and generate proof
        rl = _generateResourceLock(_scw, _user.pub);
        (proof, root,) = getTestProof(_buildResourceLockHash(rl), _validProof);
        // Set up calldata
        op.callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(CREDIBLE_ACCOUNT_VALIDATOR),
                    0,
                    abi.encodeWithSelector(CREDIBLE_ACCOUNT_VALIDATOR.enableSessionKey.selector, abi.encode(rl))
                )
            )
        );
        return (op, rl, proof, root);
    }

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

    function _hashTokenData(TokenData[] memory _data) internal pure returns (bytes32) {
        return keccak256(abi.encode(_data));
    }

    function _generateResourceLock(address _scw, address _sk) internal view returns (ResourceLock memory) {
        TokenData[] memory td = new TokenData[](2);
        td[0] = TokenData({token: address(USDT), amount: 100});
        td[1] = TokenData({token: address(DAI), amount: 200});
        ResourceLock memory rl = ResourceLock({
            chainId: 42161,
            smartWallet: _scw,
            sessionKey: _sk,
            validAfter: 1732176210,
            validUntil: 1732435407,
            tokenData: td,
            nonce: 14
        });
        return rl;
    }
}
