// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import "../../../../src/interfaces/base/IERC7579Account.sol";
import {Execution} from "../../../../src/types/Structs.sol";
import {ExecutionLib} from "../../../../src/libraries/ExecutionLib.sol";
import {ModeLib} from "../../../../src/libraries/ModeLib.sol";
import {
    CALLTYPE_DELEGATECALL,
    EXECTYPE_DEFAULT,
    MODE_DEFAULT,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_HOOK,
    MODULE_TYPE_VALIDATOR
} from "../../../../src/types/Constants.sol";
import {ModePayload} from "../../../../src/types/Types.sol";
import {MockTarget} from "../../../../src/test/mocks/MockTarget.sol";
import {MockDelegateTarget} from "../../../../src/test/mocks/MockDelegateTarget.sol";
import "../../../../src/test/dependencies/EntryPoint.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {ModularEtherspotWalletTestUtils as TestUtils} from "../utils/ModularEtherspotWalletTestUtils.sol";

contract ModularEtherspotWalletEIP7702Test is TestUtils {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotInitializable();
    error OnlyOwnerOrSelf();
    error RequiredModule();
    error LinkedList_InvalidEntry(address entry);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testSetup();
    }

    /*//////////////////////////////////////////////////////////////
                MODULAR ETHERSPOT WALLET EIP-7702 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_executeSingle_Basic() public {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1337);
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(MOCK_TARGET), uint256(0), callData))
        );
        // Get nonce
        uint256 nonce = _getNonce(eoa7702.pub, address(MOCK_VALIDATOR));
        // Get signature
        bytes memory signature = hex"41414141";
        // Create the userOp and add the data
        PackedUserOperation memory op = _createUserOp(eoa7702.pub, address(MOCK_VALIDATOR));
        op.nonce = nonce;
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa7702);
        _actionEIP7702(eoa7702);
        // Create userOps array
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        assertTrue(MOCK_TARGET.value() == 1337);
    }

    function test_initializeAndExecSingle_Basic() public returns (address payable) {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1337);
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: eoa7702.pub,
            value: 0,
            callData: abi.encodeCall(ModularEtherspotWallet.initializeAccount, initData)
        });
        executions[1] = Execution({target: address(MOCK_TARGET), value: 0, callData: callData});
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));
        uint256 nonce = _getNonce(eoa7702.pub, address(MOCK_VALIDATOR));
        // Create the userOp and add the data
        PackedUserOperation memory op = _createUserOp(eoa7702.pub, address(MOCK_VALIDATOR));
        op.nonce = nonce;
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa7702);
        _actionEIP7702(eoa7702);
        // Create userOps array
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        assertTrue(MOCK_TARGET.value() == 1337);
        return eoa7702.pub;
    }

    function test_executeBatch_Basic() public {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1337);
        address target2 = address(0x420);
        uint256 target2Amount = 1 wei;
        // Create the executions
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: address(MOCK_TARGET), value: 0, callData: callData});
        executions[1] = Execution({target: target2, value: target2Amount, callData: ""});
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));
        uint256 nonce = _getNonce(eoa7702.pub, address(MOCK_VALIDATOR));
        // Create the userOp and add the data
        PackedUserOperation memory op = _createUserOp(eoa7702.pub, address(MOCK_VALIDATOR));
        op.nonce = nonce;
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa7702);
        _actionEIP7702(eoa7702);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        assertTrue(MOCK_TARGET.value() == 1337);
        assertTrue(target2.balance == target2Amount);
    }

    function test_executeSingleFromExecutor_Basic() public {
        address acc7702 = test_initializeAndExecSingle_Basic();
        bytes[] memory ret = MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(address(acc7702)),
            address(MOCK_TARGET),
            0,
            abi.encodePacked(MockTarget.setValue.selector, uint256(1338))
        );
        assertEq(ret.length, 1);
        assertEq(abi.decode(ret[0], (uint256)), 1338);
    }

    function test_executeBatchFromExecutor_Basic() public {
        acc7702 = test_initializeAndExecSingle_Basic();
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1338);
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: address(MOCK_TARGET), value: 0, callData: callData});
        executions[1] = Execution({target: address(MOCK_TARGET), value: 0, callData: callData});
        bytes[] memory ret = MOCK_EXECUTOR.execBatch({account: IERC7579Account(address(acc7702)), execs: executions});
        assertEq(ret.length, 2);
        assertEq(abi.decode(ret[0], (uint256)), 1338);
    }

    function test_delegateCall_Basic() public {
        // Create calldata for the account to execute
        (address valueTarget,) = _makePayableAddrAndKey("Value Target");
        uint256 value = 1 ether;
        bytes memory callData = abi.encodeWithSelector(MockDelegateTarget.sendValue.selector, valueTarget, value);
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encode(CALLTYPE_DELEGATECALL, EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00)),
                abi.encodePacked(address(MOCK_DELEGATE_TARGET), callData)
            )
        );
        uint256 nonce = _getNonce(eoa7702.pub, address(MOCK_VALIDATOR));
        PackedUserOperation memory op = _createUserOp(eoa7702.pub, address(MOCK_VALIDATOR));
        op.nonce = nonce;
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa7702);
        _actionEIP7702(eoa7702);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        assertTrue(valueTarget.balance == value);
    }

    function test_delegateCall_fromExecutor() public {
        acc7702 = test_initializeAndExecSingle_Basic();
        // Create calldata for the account to execute
        (address valueTarget,) = _makePayableAddrAndKey("Value Target");
        uint256 value = 1 ether;
        bytes memory callData = abi.encodeWithSelector(MockDelegateTarget.sendValue.selector, valueTarget, value);
        // Execute the delegatecall via the executor
        MOCK_EXECUTOR.execDelegatecall(
            IERC7579Account(address(acc7702)), abi.encodePacked(address(MOCK_DELEGATE_TARGET), callData)
        );
        // Assert that the value was set ie that execution was successful
        assertTrue(valueTarget.balance == value);
    }

    function test_onRedelegation_Basic() public {
        acc7702 = test_initializeAndExecSingle_Basic();
        vm.prank(address(ENTRYPOINT));
        ModularEtherspotWallet(acc7702).installModule(MODULE_TYPE_HOOK, address(MOCK_HOOK), "");
        assertTrue(
            ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(MOCK_VALIDATOR), "")
        );
        assertTrue(ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_EXECUTOR, address(MOCK_EXECUTOR), ""));
        assertTrue(ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_HOOK, address(MOCK_HOOK), ""));
        // storage is cleared
        vm.prank(address(acc7702));
        ModularEtherspotWallet(acc7702).onRedelegation();
        assertFalse(
            ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(MOCK_VALIDATOR), "")
        );
        assertFalse(ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_EXECUTOR, address(MOCK_EXECUTOR), ""));
        assertFalse(ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_HOOK, address(MOCK_HOOK), ""));
        // account is properly initialized to install modules again
        vm.startPrank(address(ENTRYPOINT));
        ModularEtherspotWallet(acc7702).installModule(MODULE_TYPE_VALIDATOR, address(MOCK_VALIDATOR), "");
        ModularEtherspotWallet(acc7702).installModule(MODULE_TYPE_EXECUTOR, address(MOCK_EXECUTOR), "");
        ModularEtherspotWallet(acc7702).installModule(MODULE_TYPE_HOOK, address(MOCK_HOOK), "");
        assertTrue(
            ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(MOCK_VALIDATOR), "")
        );
        assertTrue(ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_EXECUTOR, address(MOCK_EXECUTOR), ""));
        assertTrue(ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_HOOK, address(MOCK_HOOK), ""));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                  COMPLEX - IDEAL MODULES INSTALLED
    //////////////////////////////////////////////////////////////*/

    function test_initializeAndExecSingle_Complex() public returns (address payable) {
        initData = _getComplexInitData(eoa7702);
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1337);
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: eoa7702.pub,
            value: 0,
            callData: abi.encodeCall(ModularEtherspotWallet.initializeAccount, initData)
        });
        executions[1] = Execution({target: address(MOCK_TARGET), value: 0, callData: callData});
        // Encode the call into the cal ldata for the userOp
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));
        uint256 nonce = _getNonce(eoa7702.pub, address(ECDSA_VALIDATOR));
        // Create the userOp and add the data
        PackedUserOperation memory op = _createUserOp(eoa7702.pub, address(ECDSA_VALIDATOR));
        op.nonce = nonce;
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa7702);
        _actionEIP7702(eoa7702);
        // Create userOps array
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        assertTrue(MOCK_TARGET.value() == 1337);
        return eoa7702.pub;
    }

    function test_executeSingle_Complex() public {
        acc7702 = test_initializeAndExecSingle_Complex();
        vm.prank(address(ENTRYPOINT));
        ModularEtherspotWallet(acc7702).installModule(
            MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), abi.encode(MODULE_TYPE_VALIDATOR)
        );
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1337);
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(MOCK_TARGET), uint256(0), callData))
        );
        // Get nonce
        uint256 nonce = _getNonce(acc7702, address(ECDSA_VALIDATOR));
        // Get signature
        bytes memory signature = hex"41414141";
        // Create the userOp and add the data
        PackedUserOperation memory op = _createUserOp(acc7702, address(ECDSA_VALIDATOR));
        op.nonce = nonce;
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa7702);
        // Create userOps array
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        assertTrue(MOCK_TARGET.value() == 1337);
    }

    // @notice: installing CRM as validator as part of batch
    function test_executeBatch_Complex() public {
        acc7702 = test_initializeAndExecSingle_Complex();
        // Create calldata for the account to execute
        bytes memory installCallData = abi.encodeCall(
            ModularEtherspotWallet.installModule,
            (MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), abi.encode(MODULE_TYPE_VALIDATOR))
        );
        bytes memory valueCallData = abi.encodeCall(MockTarget.setValue, 1337);
        address target2 = address(0x420);
        uint256 target2Amount = 1 wei;
        // Create the executions
        Execution[] memory executions = new Execution[](3);
        executions[0] = Execution({target: acc7702, value: 0, callData: installCallData});
        executions[1] = Execution({target: address(MOCK_TARGET), value: 0, callData: valueCallData});
        executions[2] = Execution({target: target2, value: target2Amount, callData: ""});
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));
        uint256 nonce = _getNonce(acc7702, address(ECDSA_VALIDATOR));
        // Create the userOp and add the data
        PackedUserOperation memory op = _createUserOp(acc7702, address(ECDSA_VALIDATOR));
        op.nonce = nonce;
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa7702);
        _actionEIP7702(eoa7702);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        assertTrue(
            ModularEtherspotWallet(acc7702).isModuleInstalled(
                MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), ""
            )
        );
        assertTrue(MOCK_TARGET.value() == 1337);
        assertTrue(target2.balance == target2Amount);
    }

    function test_executeSingleFromExecutor_Complex() public {
        acc7702 = test_initializeAndExecSingle_Complex();
        vm.prank(address(ENTRYPOINT));
        ModularEtherspotWallet(acc7702).installModule(
            MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), abi.encode(MODULE_TYPE_VALIDATOR)
        );
        bytes[] memory ret = MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(address(acc7702)),
            address(MOCK_TARGET),
            0,
            abi.encodePacked(MockTarget.setValue.selector, uint256(1338))
        );
        assertEq(ret.length, 1);
        assertEq(abi.decode(ret[0], (uint256)), 1338);
    }

    function test_executeBatchFromExecutor_Complex() public {
        acc7702 = test_initializeAndExecSingle_Complex();
        bytes memory installCallData = abi.encodeCall(
            ModularEtherspotWallet.installModule,
            (MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), abi.encode(MODULE_TYPE_VALIDATOR))
        );
        bytes memory valueCallData = abi.encodeCall(MockTarget.setValue, 1338);
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: acc7702, value: 0, callData: installCallData});
        executions[1] = Execution({target: address(MOCK_TARGET), value: 0, callData: valueCallData});
        bytes[] memory ret = MOCK_EXECUTOR.execBatch({account: IERC7579Account(address(acc7702)), execs: executions});
        assertTrue(
            ModularEtherspotWallet(acc7702).isModuleInstalled(
                MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), ""
            )
        );
        assertEq(ret.length, 2);
        // Assert that the value was set ie that execution was successful
        assertEq(abi.decode(ret[1], (uint256)), 1338);
    }

    function test_delegateCall_Complex() public {
        // Create calldata for the account to execute
        (address valueTarget,) = _makePayableAddrAndKey("Value Target");
        uint256 value = 1 ether;
        bytes memory callData = abi.encodeWithSelector(MockDelegateTarget.sendValue.selector, valueTarget, value);
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encode(CALLTYPE_DELEGATECALL, EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00)),
                abi.encodePacked(address(MOCK_DELEGATE_TARGET), callData)
            )
        );
        uint256 nonce = _getNonce(eoa7702.pub, address(ECDSA_VALIDATOR));
        PackedUserOperation memory op = _createUserOp(eoa7702.pub, address(ECDSA_VALIDATOR));
        op.nonce = nonce;
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa7702);
        _actionEIP7702(eoa7702);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        assertTrue(valueTarget.balance == value);
    }

    function test_delegateCall_fromExecutor_Complex() public {
        acc7702 = test_initializeAndExecSingle_Complex();
        // Create calldata for the account to execute
        (address valueTarget,) = _makePayableAddrAndKey("Value Target");
        uint256 value = 1 ether;
        bytes memory callData = abi.encodeWithSelector(MockDelegateTarget.sendValue.selector, valueTarget, value);
        // Execute the delegatecall via the executor
        MOCK_EXECUTOR.execDelegatecall(
            IERC7579Account(address(acc7702)), abi.encodePacked(address(MOCK_DELEGATE_TARGET), callData)
        );
        // Assert that the value was set ie that execution was successful
        assertTrue(valueTarget.balance == value);
    }

    function test_onRedelegation_Complex() public {
        acc7702 = test_initializeAndExecSingle_Complex();
        vm.prank(address(ENTRYPOINT));
        ModularEtherspotWallet(acc7702).installModule(
            MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), abi.encode(MODULE_TYPE_VALIDATOR)
        );
        assertTrue(
            ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(ECDSA_VALIDATOR), hex"")
        );
        assertTrue(
            ModularEtherspotWallet(acc7702).isModuleInstalled(
                MODULE_TYPE_VALIDATOR, address(RESOURCE_LOCK_VALIDATOR), hex""
            )
        );
        assertTrue(
            ModularEtherspotWallet(acc7702).isModuleInstalled(
                MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), hex""
            )
        );
        assertTrue(
            ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_EXECUTOR, address(MOCK_EXECUTOR), hex"")
        );
        assertTrue(
            ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_HOOK, address(HOOK_MULTIPLEXER), hex"")
        );
        // storage is cleared
        vm.prank(address(acc7702));
        ModularEtherspotWallet(acc7702).onRedelegation();
        assertFalse(
            ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(ECDSA_VALIDATOR), hex"")
        );
        assertFalse(
            ModularEtherspotWallet(acc7702).isModuleInstalled(
                MODULE_TYPE_VALIDATOR, address(RESOURCE_LOCK_VALIDATOR), hex""
            )
        );
        assertFalse(
            ModularEtherspotWallet(acc7702).isModuleInstalled(
                MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), hex""
            )
        );
        assertFalse(
            ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_EXECUTOR, address(MOCK_EXECUTOR), hex"")
        );
        assertFalse(
            ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_HOOK, address(HOOK_MULTIPLEXER), hex"")
        );
        // account is properly initialized to install modules again (different validator)
        address[] memory owners = new address[](2);
        owners[0] = eoa.pub;
        owners[1] = alice.pub;
        vm.startPrank(address(ENTRYPOINT));
        ModularEtherspotWallet(acc7702).installModule(
            MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), abi.encode(owners)
        );
        ModularEtherspotWallet(acc7702).installModule(MODULE_TYPE_EXECUTOR, address(MOCK_EXECUTOR), "");
        ModularEtherspotWallet(acc7702).installModule(MODULE_TYPE_HOOK, address(MOCK_HOOK), "");
        vm.stopPrank();
        assertTrue(
            ModularEtherspotWallet(acc7702).isModuleInstalled(
                MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), ""
            )
        );
        assertTrue(ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_EXECUTOR, address(MOCK_EXECUTOR), ""));
        assertTrue(ModularEtherspotWallet(acc7702).isModuleInstalled(MODULE_TYPE_HOOK, address(MOCK_HOOK), ""));
    }
}
