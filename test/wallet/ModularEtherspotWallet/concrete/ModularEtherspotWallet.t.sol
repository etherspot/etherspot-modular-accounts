// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import "../../../../src/interfaces/base/IERC7579Account.sol";
import {ExecutionLib} from "../../../../src/libraries/ExecutionLib.sol";
import {ModeLib} from "../../../../src/libraries/ModeLib.sol";
import {
    CALLTYPE_DELEGATECALL,
    EXECTYPE_DEFAULT,
    MODE_DEFAULT,
    MODULE_TYPE_VALIDATOR
} from "../../../../src/types/Constants.sol";
import {Execution} from "../../../../src/types/Structs.sol";
import {ModePayload} from "../../../../src/types/Types.sol";
import {MockTarget} from "../../../../src/test/mocks/MockTarget.sol";
import {MockDelegateTarget} from "../../../../src/test/mocks/MockDelegateTarget.sol";
import "../../../../src/test/dependencies/EntryPoint.sol";
import {ModularEtherspotWalletTestUtils as TestUtils} from "../utils/ModularEtherspotWalletTestUtils.sol";

contract ModularEtherspotWalletTest is TestUtils {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidCaller();
    error NotInitializable();
    error OnlyOwnerOrSelf();
    error RequiredModule();
    error LinkedList_InvalidEntry(address entry);
    error CannotRemoveLastValidator();
    error InvalidImplementationAddress();

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testSetup();
    }

    /*//////////////////////////////////////////////////////////////
                    MODULAR ETHERSPOT WALLET TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initializeAccountRevert() public {
        _toRevert(NotInitializable.selector, hex"");
        IMPLEMENTATION.initializeAccount("0x00");
    }

    function test_executeSingle() public returns (address) {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1337);
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(MOCK_TARGET), uint256(0), callData))
        );
        // Create and sign UserOp
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ECDSA_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa);
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        assertTrue(MOCK_TARGET.value() == 1337);
    }

    function test_executeBatch() public {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1337);
        // Create the executions
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: address(MOCK_TARGET), value: 0, callData: callData});
        executions[1] = Execution({target: bob.pub, value: 1 wei, callData: ""});
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));
        // Create and sign UserOp
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ECDSA_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa);
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        // Bob starts with initial balance of 100 ether
        assertTrue(MOCK_TARGET.value() == 1337);
        assertTrue(bob.pub.balance == 100 ether + 1 wei);
    }

    function test_executeSingle_FromExecutor() public {
        bytes[] memory ret = MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(address(SCW)),
            address(MOCK_TARGET),
            0,
            abi.encodePacked(MockTarget.setValue.selector, uint256(1338))
        );
        assertEq(ret.length, 1);
        assertEq(abi.decode(ret[0], (uint256)), 1338);
    }

    function test_executeBatch_FromExecutor() public {
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1338);
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({target: address(MOCK_TARGET), value: 0, callData: callData});
        executions[1] = Execution({target: address(MOCK_TARGET), value: 0, callData: callData});
        bytes[] memory ret = MOCK_EXECUTOR.execBatch({account: IERC7579Account(address(SCW)), execs: executions});
        assertEq(ret.length, 2);
        assertEq(abi.decode(ret[0], (uint256)), 1338);
    }

    function test_delegateCall() public {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeWithSelector(MockDelegateTarget.sendValue.selector, bob.pub, 1 ether);
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encode(CALLTYPE_DELEGATECALL, EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00)),
                abi.encodePacked(address(MOCK_DELEGATE_TARGET), callData)
            )
        );
        // Create and sign UserOp
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ECDSA_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa);
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        // Assert that the value was set ie that execution was successful
        // Bob has starting balance of 100 ether
        assertTrue(bob.pub.balance == 100 ether + 1 ether);
    }

    function test_delegateCall_FromExecutor() public {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeWithSelector(MockDelegateTarget.sendValue.selector, bob.pub, 1 ether);
        // Execute the delegatecall via the executor
        bytes[] memory ret = MOCK_EXECUTOR.execDelegatecall(
            IERC7579Account(address(SCW)), abi.encodePacked(MOCK_DELEGATE_TARGET, callData)
        );
        // Assert that the value was set ie that execution was successful
        // Bob has initial balance of 100 ether
        assertTrue(bob.pub.balance == 100 ether + 1 ether);
    }

    function test_execute_FromAnotherOwner() public {
        // Install MultipleOwnerECDSAValidator
        address[] memory owners = new address[](1);
        owners[0] = eoa.pub;
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MULTIPLE_OWNER_ECDSA_VALIDATOR), abi.encode(owners));
        // Add Alice as an owner
        vm.prank(eoa.pub);
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(address(SCW)),
            address(MULTIPLE_OWNER_ECDSA_VALIDATOR),
            0,
            abi.encodeWithSelector(MULTIPLE_OWNER_ECDSA_VALIDATOR.addOwner.selector, address(SCW), alice.pub)
        );
        // Verify Alice is an owner
        assertTrue(MULTIPLE_OWNER_ECDSA_VALIDATOR.isOwner(address(SCW), alice.pub));
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1337);
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(MOCK_TARGET), uint256(0), callData))
        );
        PackedUserOperation memory op = _createUserOp(address(SCW), address(MULTIPLE_OWNER_ECDSA_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, alice);
        _executeUserOp(op);
        assertTrue(MOCK_TARGET.value() == 1337);
    }

    function test_execute_RevertIf_FromNonOwner() public {
        // Create calldata for the account to execute
        bytes memory callData = abi.encodeCall(MockTarget.setValue, 1337);
        // Encode the call into the calldata for the userOp
        bytes memory opCalldata = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(MOCK_TARGET), uint256(0), callData))
        );
        // Create and sign UserOp
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ECDSA_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, malicious);
        _toRevert(IEntryPoint.FailedOp.selector, abi.encode(0, AA24));
        // Send the userOp to the entrypoint
        _executeUserOp(op);
    }

    function test_paginateExecutors() public {
        // Paginate from sentinel (start node) and expect the 1 default executor
        (address[] memory results, address next) = SCW.getExecutorsPaginated(address(0x1), 1);
        assertTrue(results.length == 1);
        assertEq(results[0], address(MOCK_EXECUTOR));
        assertEq(next, address(0x1));
        // Paginate from the default executor and expect no results
        (address[] memory results2, address next2) = SCW.getExecutorsPaginated(address(MOCK_EXECUTOR), 1);
        assertTrue(results2.length == 0);
        assertEq(next2, address(0x1));
        // Expect the revert with the encoded reason
        _toRevert(LinkedList_InvalidEntry.selector, abi.encode(address(this)));
        SCW.getExecutorsPaginated(address(this), 1);
    }

    function test_uninstallValidator_RevertIf_CannotRemoveLastValidator() public {
        // Check account can't be bricked by removing the last validator
        _uninstallModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(MOCK_VALIDATOR), hex"");
        address prevValidator = _getPrevValidator(SCW, address(MOCK_VALIDATOR));
        // Execute the module installation
        vm.startPrank(eoa.pub);
        _toRevert(CannotRemoveLastValidator.selector, hex"");
        MOCK_EXECUTOR.executeViaAccount(
            IERC7579Account(SCW),
            address(SCW),
            0,
            abi.encodeWithSelector(
                SCW.uninstallModule.selector,
                MODULE_TYPE_VALIDATOR,
                address(ECDSA_VALIDATOR),
                abi.encode(prevValidator, hex"")
            )
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              FALLBACKS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow minting ERC1155 token to modular wallet
    function test_receiveERC1155() public {
        // Prank as eoa.pub
        vm.startPrank(eoa.pub);
        // Mint enjin (and check balance)
        ENJIN.mint(address(eoa.pub), 100, 1, hex"");
        assertEq(ENJIN.balanceOf(address(eoa.pub), 100), 1);
        // Attempt to transfer (and check balances)
        ENJIN.safeTransferFrom(address(eoa.pub), address(SCW), 100, 1, hex"");
        assertEq(ENJIN.balanceOf(address(eoa.pub), 100), 0);
        assertEq(ENJIN.balanceOf(address(SCW), 100), 1);
        vm.stopPrank();
    }

    /// @dev Should allow direct minting of ERC1155 token to modular wallet
    function test_mintERC1155() public {
        // Mint directly to the wallet
        ENJIN.mint(address(SCW), 100, 1, hex"");
        // Check balance
        assertEq(ENJIN.balanceOf(address(SCW), 100), 1);
    }

    /// @dev Should allow minting multiple ERC1155 tokens to modular wallet
    function test_mintERC1155_multipleTokens() public {
        // Mint enjin (and check balance)
        ENJIN.mint(address(SCW), 100, 1, hex"");
        assertEq(ENJIN.balanceOf(address(SCW), 100), 1);
        // Mint axie (and check balance)
        AXIE.mint(address(SCW), 200, 1, hex"");
        assertEq(AXIE.balanceOf(address(SCW), 200), 1);
    }

    /// @dev Should allow batch minting of ERC1155 token to modular wallet
    function test_mintBatchERC1155() public {
        vm.startPrank(eoa.pub);
        // Mint batch
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 100;
        ids[1] = 101;
        amounts[0] = 1;
        amounts[1] = 10000;
        ENJIN.batchMint(address(SCW), ids, amounts, hex"");
        // Check balances
        address[] memory owners = new address[](2);
        owners[0] = address(SCW);
        owners[1] = address(SCW);
        uint256[] memory balances = ENJIN.balanceOfBatch(owners, ids);
        assertEq(balances[0], 1);
        assertEq(balances[1], 10000);
        vm.stopPrank();
    }

    /// @dev Should allow batch minting of multiple ERC1155 tokens to modular wallet
    function test_mintBatchERC1155_multipleTokens() public {
        // Mint batch enjin
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 100;
        ids[1] = 101;
        amounts[0] = 1;
        amounts[1] = 10000;
        ENJIN.batchMint(address(SCW), ids, amounts, hex"");
        // Check balances
        address[] memory owners = new address[](2);
        owners[0] = address(SCW);
        owners[1] = address(SCW);
        uint256[] memory balances = ENJIN.balanceOfBatch(owners, ids);
        assertEq(balances[0], 1);
        assertEq(balances[1], 10000);
        // Mint batch axie
        ids[0] = 200;
        ids[1] = 201;
        AXIE.batchMint(address(SCW), ids, amounts, hex"");
        // Check balances
        balances = AXIE.balanceOfBatch(owners, ids);
        assertEq(balances[0], 1);
        assertEq(balances[1], 10000);
    }

    /// @dev Should allow receiving batch of ERC1155 token to modular wallet
    function test_receiveBatchERC1155() public {
        // Prank as eoa.pub
        vm.startPrank(eoa.pub);
        // Mint batch
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 100;
        ids[1] = 101;
        amounts[0] = 1;
        amounts[1] = 10000;
        ENJIN.batchMint(address(eoa.pub), ids, amounts, hex"");
        // Check balances
        address[] memory owners = new address[](2);
        owners[0] = address(eoa.pub);
        owners[1] = address(eoa.pub);
        uint256[] memory eoaBalances = ENJIN.balanceOfBatch(owners, ids);
        assertEq(eoaBalances[0], 1);
        assertEq(eoaBalances[1], 10000);
        // Attempt to transfer
        ENJIN.safeBatchTransferFrom(address(eoa.pub), address(SCW), ids, amounts, hex"");
        // Check balances
        eoaBalances = ENJIN.balanceOfBatch(owners, ids);
        owners[0] = address(SCW);
        owners[1] = address(SCW);
        uint256[] memory scwBalances = ENJIN.balanceOfBatch(owners, ids);
        assertEq(eoaBalances[0], 0);
        assertEq(eoaBalances[1], 0);
        assertEq(scwBalances[0], 1);
        assertEq(scwBalances[1], 10000);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              UPGRADING
    //////////////////////////////////////////////////////////////*/

    function test_proxiableUUIDSlot() public {
        bytes32 slot = IMPLEMENTATION.proxiableUUID();
        assertEq(slot, 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc, "Proxiable UUID mismatch");
    }

    function test_currentImplementationAddress() public {
        address currentImplementation = SCW.getImplementation();
        assertEq(currentImplementation, address(IMPLEMENTATION), "Current implementation address mismatch");
    }

    function test_upgradeImplementation() public {
        ModularEtherspotWallet newImpl = new ModularEtherspotWallet(ENTRYPOINT);
        bytes memory callData =
            abi.encodeWithSelector(ModularEtherspotWallet.upgradeToAndCall.selector, address(newImpl), "");
        Execution[] memory execution = new Execution[](1);
        execution[0] = Execution(address(SCW), 0, callData);
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(execution)));
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ECDSA_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa);
        // Send the userOp to the entrypoint
        _executeUserOp(op);
        address newImplementation = SCW.getImplementation();
        assertEq(newImplementation, address(newImpl), "New implementation address mismatch");
    }

    function test_upgradeImplementation_RevertIf_InvalidCaller() public {
        ModularEtherspotWallet newImpl = new ModularEtherspotWallet(ENTRYPOINT);
        _toRevert(InvalidCaller.selector, hex"");
        SCW.upgradeToAndCall(address(newImpl), hex"");
    }

    function test_upgradeImplementation_RevertIf_InvalidAddress() public {
        bytes memory callData = abi.encodeWithSelector(ModularEtherspotWallet.upgradeToAndCall.selector, address(0), "");
        Execution[] memory execution = new Execution[](1);
        execution[0] = Execution(address(SCW), 0, callData);
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(execution)));
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ECDSA_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa);
        _revertUserOpEvent(hash, op.nonce, InvalidImplementationAddress.selector, hex"");
        _executeUserOp(op);
    }

    function test_upgradeImplementation_RevertIf_ImplementationNotAContract() public {
        bytes memory callData =
            abi.encodeWithSelector(ModularEtherspotWallet.upgradeToAndCall.selector, alice.pub, hex"");
        Execution[] memory execution = new Execution[](1);
        execution[0] = Execution(address(SCW), 0, callData);
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(execution)));
        PackedUserOperation memory op = _createUserOp(address(SCW), address(ECDSA_VALIDATOR));
        op.callData = opCalldata;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, eoa);
        _revertUserOpEvent(hash, op.nonce, InvalidImplementationAddress.selector, hex"");
        _executeUserOp(op);
    }

    function test_upgradeSmartAccount_Lifecycle() public {
        test_proxiableUUIDSlot();
        test_currentImplementationAddress();
        test_upgradeImplementation();
    }
}
