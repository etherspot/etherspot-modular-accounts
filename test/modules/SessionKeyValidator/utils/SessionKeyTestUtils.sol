// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "ERC7579/test/dependencies/EntryPoint.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import "ERC7579/libs/ModeLib.sol";
import {ExecutionValidation, ParamCondition, Permission, SessionData} from "../../../../src/common/Structs.sol";
import {ComparisonRule} from "../../../../src/common/Enums.sol";
import {SessionKeyValidatorHarness} from "../../../harnesses/SessionKeyValidatorHarness.sol";
import {TestCounter} from "../../../../src/test/TestCounter.sol";
import {TestERC721} from "../../../../src/test/TestERC721.sol";
import {TestUniswapV3} from "../../../../src/test/TestUniswapV3.sol";
import "../../../ModularTestBase.sol";

contract SessionKeyTestUtils is ModularTestBase {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Contract instances
    SessionKeyValidatorHarness internal harness;
    TestCounter internal counter1;
    TestCounter internal counter2;
    TestERC721 internal cryptoPunk;
    TestUniswapV3 internal uniswapV3;

    // Test variables
    uint48 internal immutable validAfter = uint48(block.timestamp);
    uint48 internal immutable validUntil = uint48(block.timestamp + 1 days);
    uint256 internal immutable numberPermissions = 4;
    uint256 internal immutable tenUses = 10;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier validatorInstalled() {
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_VALIDATOR,
            address(skv),
            hex""
        );
        vm.startPrank(address(scw));
        _;
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        TEST HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _testSetup() internal {
        _testInit();
        harness = new SessionKeyValidatorHarness();
        counter1 = new TestCounter();
        counter2 = new TestCounter();
        cryptoPunk = new TestERC721();
        uniswapV3 = new TestUniswapV3(weth);
    }

    function _getSessionKeyAndPermissions(
        User memory _sessionKey
    ) internal view returns (SessionData memory, Permission[] memory) {
        SessionData memory sd = SessionData({
            sessionKey: _sessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            live: false
        });
        ParamCondition[] memory conditions = new ParamCondition[](2);
        conditions[0] = ParamCondition({
            offset: 4,
            rule: ComparisonRule.EQUAL,
            value: bytes32(uint256(uint160(address(alice.pub))))
        });
        conditions[1] = ParamCondition({
            offset: 36,
            rule: ComparisonRule.LESS_THAN_OR_EQUAL,
            value: bytes32(uint256(5))
        });
        Permission[] memory perms = new Permission[](1);
        perms[0] = Permission({
            target: address(counter1),
            selector: TestCounter.multiTypeCall.selector,
            payableLimit: 100 wei,
            uses: tenUses,
            paramConditions: conditions
        });
        return (sd, perms);
    }

    function _getExecutionValidation(
        uint48 _validAfter,
        uint48 _validUntil
    ) internal pure returns (ExecutionValidation memory) {
        return
            ExecutionValidation({
                validAfter: _validAfter,
                validUntil: _validUntil
            });
    }

    function _setupSingleUserOp(
        address _validator,
        address _target,
        uint256 _amount,
        bytes memory _callData,
        ExecutionValidation[] memory _execValidations,
        User memory _user
    ) internal view returns (PackedUserOperation memory) {
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(_target, _amount, _callData)
            )
        );
        PackedUserOperation memory op = _createUserOp(address(scw), _validator);
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = bytes.concat(
            _ethSign(hash, _user),
            abi.encode(_execValidations)
        );
        return op;
    }

    function _setupBatchUserOp(
        address _validator,
        Execution[] memory _execs,
        ExecutionValidation[] memory _execValidations,
        User memory _user
    ) internal view returns (PackedUserOperation memory) {
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(_execs))
        );
        PackedUserOperation memory op = _createUserOp(address(scw), _validator);
        op.callData = opCalldata;
        bytes32 hash = entrypoint.getUserOpHash(op);
        op.signature = bytes.concat(
            _ethSign(hash, _user),
            abi.encode(_execValidations)
        );
        return op;
    }
}
