// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {ExecutionLib} from "ERC7579/libs/ExecutionLib.sol";
import {ModeLib} from "ERC7579/libs/ModeLib.sol";
import {ModularTestBase} from "../../../ModularTestBase.sol";
import {ICredibleAccountModule} from "../../../../src/interfaces/ICredibleAccountModule.sol";
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

    function _createUserOpBatchWithResourceLock(address _scw, User memory _user, bool _validProof)
        internal
        view
        returns (PackedUserOperation memory userOp, ResourceLock memory rl, bytes32[] memory proof, bytes32 root)
    {
        PackedUserOperation memory op = _createUserOp(_scw, address(rlv));
        rl = _generateResourceLock(_scw, _user.pub);
        (proof, root,) = getTestProof(_buildResourceLockHash(rl), _validProof);
        bytes memory callData = abi.encodeWithSelector(cam.enableSessionKey.selector, abi.encode(rl));
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({target: address(cam), value: 0, callData: callData});
        op.callData =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));
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
                _lock.bidHash,
                abi.encode(_lock.tokenData)
            )
        );
    }

    function _generateResourceLock(address _scw, address _sk) internal view returns (ResourceLock memory) {
        TokenData[] memory td = new TokenData[](2);
        td[0] = TokenData({token: address(usdt), amount: 100});
        td[1] = TokenData({token: address(dai), amount: 200});
        ResourceLock memory rl = ResourceLock({
            chainId: block.chainid,
            smartWallet: _scw,
            sessionKey: _sk,
            validAfter: 1732176210,
            validUntil: 1732435407,
            bidHash: DUMMY_BID_HASH,
            tokenData: td
        });
        return rl;
    }

    /// @notice Helper function to create callData with invalid target
    function _createCallDataWithInvalidTarget(address invalidTarget) internal view returns (bytes memory) {
        // Create execution data for enableSessionKey
        bytes memory execData = abi.encodeWithSelector(
            ICredibleAccountModule.enableSessionKey.selector,
            abi.encode(_generateResourceLock(address(scw), sessionKey.pub))
        );
        // Create single execution with invalid target
        bytes memory execution = ExecutionLib.encodeSingle(invalidTarget, 0, execData);
        // Create full callData with execute selector and mode
        return abi.encodeWithSelector(IERC7579Account.execute.selector, ModeLib.encodeSimpleSingle(), execution);
    }

    /// @notice Helper function to create callData with non-zero value
    function _createCallDataWithNonZeroValue(uint256 value) internal view returns (bytes memory) {
        // Create execution data for enableSessionKey
        bytes memory execData = abi.encodeWithSelector(
            ICredibleAccountModule.enableSessionKey.selector,
            abi.encode(_generateResourceLock(address(scw), sessionKey.pub))
        );
        // Create single execution with non-zero value
        bytes memory execution = ExecutionLib.encodeSingle(address(cam), value, execData);
        // Create full callData with execute selector and mode
        return abi.encodeWithSelector(IERC7579Account.execute.selector, ModeLib.encodeSimpleSingle(), execution);
    }

    /// @notice Helper function to create callData with invalid selector
    function _createCallDataWithInvalidSelector(bytes4 invalidSelector) internal view returns (bytes memory) {
        // Create execution data with invalid selector
        bytes memory execData =
            abi.encodeWithSelector(invalidSelector, abi.encode(_generateResourceLock(address(scw), sessionKey.pub)));
        // Create single execution
        bytes memory execution = ExecutionLib.encodeSingle(address(cam), 0, execData);
        // Create full callData with execute selector and mode
        return abi.encodeWithSelector(IERC7579Account.execute.selector, ModeLib.encodeSimpleSingle(), execution);
    }

    /// @notice Helper function to create batch callData with multiple executions (invalid)
    function _createCallDataWithMultipleBatchExecutions() internal view returns (bytes memory) {
        // Create first execution with enableSessionKey
        bytes memory execData1 = abi.encodeWithSelector(
            ICredibleAccountModule.enableSessionKey.selector,
            abi.encode(_generateResourceLock(address(scw), sessionKey.pub))
        );
        // Create second execution (dummy execution to make batch invalid)
        bytes memory execData2 = abi.encodeWithSelector(
            ICredibleAccountModule.enableSessionKey.selector,
            abi.encode(_generateResourceLock(address(scw), sessionKey.pub))
        );
        // Create array of executions (2 executions - this should be invalid)
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: address(cam), value: 0, callData: execData1});
        executions[1] = Execution({target: address(cam), value: 0, callData: execData2});
        // Encode batch execution
        bytes memory batchExecution = ExecutionLib.encodeBatch(executions);
        // Create full callData with execute selector and batch mode
        return abi.encodeWithSelector(IERC7579Account.execute.selector, ModeLib.encodeSimpleBatch(), batchExecution);
    }

    /// @notice Helper function to create batch callData with invalid target
    function _createBatchCallDataWithInvalidTarget(address invalidTarget) internal view returns (bytes memory) {
        // Create execution data for enableSessionKey
        bytes memory execData = abi.encodeWithSelector(
            ICredibleAccountModule.enableSessionKey.selector,
            abi.encode(_generateResourceLock(address(scw), sessionKey.pub))
        );
        // Create single execution array with invalid target
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({
            target: invalidTarget, // Invalid target
            value: 0,
            callData: execData
        });
        // Encode batch execution
        bytes memory batchExecution = ExecutionLib.encodeBatch(executions);
        // Create full callData with execute selector and batch mode
        return abi.encodeWithSelector(IERC7579Account.execute.selector, ModeLib.encodeSimpleBatch(), batchExecution);
    }

    /// @notice Helper function to create batch callData with non-zero value
    function _createBatchCallDataWithNonZeroValue(uint256 value) internal view returns (bytes memory) {
        // Create execution data for enableSessionKey
        bytes memory execData = abi.encodeWithSelector(
            ICredibleAccountModule.enableSessionKey.selector,
            abi.encode(_generateResourceLock(address(scw), sessionKey.pub))
        );
        // Create single execution array with non-zero value
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({
            target: address(cam),
            value: value, // Non-zero value (should be invalid)
            callData: execData
        });
        // Encode batch execution
        bytes memory batchExecution = ExecutionLib.encodeBatch(executions);
        // Create full callData with execute selector and batch mode
        return abi.encodeWithSelector(IERC7579Account.execute.selector, ModeLib.encodeSimpleBatch(), batchExecution);
    }

    /// @notice Helper function to create callData with specific ResourceLock
    function _createCallDataWithResourceLock(ResourceLock memory rl) internal view returns (bytes memory) {
        // Create execution data for enableSessionKey
        bytes memory execData = abi.encodeWithSelector(ICredibleAccountModule.enableSessionKey.selector, abi.encode(rl));
        // Create single execution
        bytes memory execution = ExecutionLib.encodeSingle(address(cam), 0, execData);
        // Create full callData with execute selector and mode
        return abi.encodeWithSelector(IERC7579Account.execute.selector, ModeLib.encodeSimpleSingle(), execution);
    }
}
