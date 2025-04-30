// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../../src/interfaces/base/IERC7579Account.sol";
import {ExecutionLib} from "../../../../src/libraries/ExecutionLib.sol";
import {ModeLib} from "../../../../src/libraries/ModeLib.sol";
import "../../../../src/test/dependencies/EntryPoint.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {CALLTYPE_SINGLE, MODULE_TYPE_VALIDATOR} from "../../../../src/types/Constants.sol";
import {HookType} from "../../../../src/types/Enums.sol";
import {Execution, ResourceLock, TokenData} from "../../../../src/types/Structs.sol";
import "../../../ModularTestBase.sol";

contract CredibleAccountTestUtils is ModularTestBase {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Test addresses and keys
    User solver;
    User otherSessionKey;

    // Test variables
    uint48 internal validAfter = uint48(block.timestamp);
    uint48 internal validUntil = uint48(block.timestamp + 1 days);
    address[3] internal tokens = [address(USDC), address(DAI), address(USDT)];
    uint256[3] internal amounts = [100e6, 200e18, 300e18];

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier withRequiredModules() {
        _installHookViaMultiplexer(SCW, address(CREDIBLE_ACCOUNT_HOOK), HookType.GLOBAL);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(CREDIBLE_ACCOUNT_VALIDATOR), hex"");
        vm.startPrank(address(SCW));
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        TEST HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _testSetup() internal {
        // Set up contracts and wallet
        _testInit();
        solver = _createUser("Solver");
        otherSessionKey = _createUser("Other Session Key");
        vm.startPrank(address(SCW));
        // Set up test variables
        tokens = [address(USDC), address(DAI), address(USDT)];
        amounts = [100e6, 200e18, 300e18];
        // Mint and approve tokens
        USDC.mint(address(SCW), amounts[0]);
        USDC.approve(address(SCW), amounts[0]);
        DAI.mint(address(SCW), amounts[1]);
        DAI.approve(address(SCW), amounts[1]);
        USDT.mint(address(SCW), amounts[2]);
        USDT.approve(address(SCW), amounts[2]);
        vm.stopPrank();
    }

    function _createResourceLock(address _scw) internal view returns (bytes memory) {
        TokenData[] memory td = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            td[i] = TokenData(tokens[i], amounts[i]);
        }
        ResourceLock memory rl = ResourceLock({
            chainId: 42161, // Arbitrum
            smartWallet: _scw,
            sessionKey: sessionKey.pub,
            validAfter: validAfter,
            validUntil: validUntil,
            tokenData: td,
            nonce: 1
        });
        return abi.encode(rl);
    }

    function _enableSessionKey(address _scw) internal {
        bytes memory rl = _createResourceLock(_scw);
        CREDIBLE_ACCOUNT_VALIDATOR.enableSessionKey(rl);
    }

    function _createTokenTransferExecution(address _recipient, uint256 _amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IERC20.transfer.selector, _recipient, _amount);
    }

    function _createTokenTransferFromExecution(address _from, address _recipient, uint256 _amount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(IERC20.transferFrom.selector, _from, _recipient, _amount);
    }

    function _createUserOpWithSignature(User memory _user, address _scw, address _validator, bytes memory _callData)
        internal
        view
        returns (PackedUserOperation memory, bytes32)
    {
        PackedUserOperation memory op = _createUserOp(_scw, _validator);
        op.callData = _callData;
        bytes32 hash = ENTRYPOINT.getUserOpHash(op);
        op.signature = _ethSign(hash, _user);
        return (op, hash);
    }

    function _claimTokensBySolver(
        User memory _user,
        ModularEtherspotWallet _scw,
        uint256 _usdc,
        uint256 _dai,
        uint256 _usdt
    ) internal {
        bytes memory usdcData = _createTokenTransferFromExecution(address(_scw), solver.pub, _usdc);
        bytes memory daiData = _createTokenTransferFromExecution(address(_scw), solver.pub, _dai);
        bytes memory usdtData = _createTokenTransferFromExecution(address(_scw), solver.pub, _usdt);
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution({target: address(USDC), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(DAI), value: 0, callData: daiData});
        batch[2] = Execution({target: address(USDT), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(_scw), address(CREDIBLE_ACCOUNT_VALIDATOR), opCalldata);
        // Execute the user operation
        _executeUserOp(op);
    }
}
