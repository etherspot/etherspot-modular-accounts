// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {ExecutionLib} from "ERC7579/libs/ExecutionLib.sol";
import {ModeLib} from "ERC7579/libs/ModeLib.sol";
import {ModularTestBase} from "../../../ModularTestBase.sol";
import "../../../../src/common/Constants.sol";
import "../../../../src/common/Enums.sol";
import "../../../../src/common/Structs.sol";

contract ResourceLockValidatorTestUtils is ModularTestBase {
    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier withRequiredModules() {
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(moecdsav), hex"");
        _installHookViaMultiplexer(scw, address(cam), HookType.GLOBAL);
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(cam), abi.encode(MODULE_TYPE_VALIDATOR));
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(rlv), abi.encode(eoa.pub));
        vm.startPrank(address(scw));
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
        op = _createUserOp(_scw, address(rlv));
        // Create ResourceLock and generate proof
        rl = _generateResourceLock(_scw, _user.pub);
        (proof, root,) = getTestProof(_buildResourceLockHash(rl), _validProof);
        // Set up calldata
        op.callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(cam), 0, abi.encodeWithSelector(cam.enableSessionKey.selector, abi.encode(rl))
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
        td[0] = TokenData({token: address(usdt), amount: 100});
        td[1] = TokenData({token: address(dai), amount: 200});
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
