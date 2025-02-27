// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "ERC7579/interfaces/IERC7579Account.sol";
import {CALLTYPE_SINGLE} from "ERC7579/libs/ModeLib.sol";
import "ERC7579/test/dependencies/EntryPoint.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {CredibleAccountModuleHarness} from "../../../harnesses/CredibleAccountModuleHarness.sol";
import "../../../../src/common/Enums.sol";
import "../../../../src/common/Structs.sol";
import "../../../ModularTestBase.sol";

contract CredibleAccountModuleTestUtils is ModularTestBase {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Contract instances
    CredibleAccountModuleHarness internal harness;

    // Test addresses and keys
    User solver;
    User otherSessionKey;

    // Test variables
    bytes internal constant PROOF = hex"1234567890abcdef";
    uint48 internal validAfter = uint48(block.timestamp);
    uint48 internal validUntil = uint48(block.timestamp + 1 days);
    address[3] internal tokens = [address(usdc), address(dai), address(usdt)];
    uint256[3] internal amounts = [100e6, 200e18, 300e18];

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier withRequiredModules() {
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(moecdsav), hex"");
        _installHookViaMultiplexer(scw, address(cam), HookType.GLOBAL);
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(cam), abi.encode(MODULE_TYPE_VALIDATOR));
        vm.startPrank(address(scw));
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
        harness = new CredibleAccountModuleHarness(address(pv), address(hmp));
        vm.startPrank(address(scw));
        // Set up test variables
        tokens = [address(usdc), address(dai), address(usdt)];
        amounts = [100e6, 200e18, 300e18];
        // Mint and approve tokens
        usdc.mint(address(scw), amounts[0]);
        usdc.approve(address(scw), amounts[0]);
        dai.mint(address(scw), amounts[1]);
        dai.approve(address(scw), amounts[1]);
        usdt.mint(address(scw), amounts[2]);
        usdt.approve(address(scw), amounts[2]);
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
        cam.enableSessionKey(rl);
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
        bytes32 hash = entrypoint.getUserOpHash(op);
        bytes memory sig = _ethSign(hash, _user);
        if (_validator == address(cam)) {
            bytes memory proofSig = abi.encodePacked(sig, PROOF);
            op.signature = proofSig;
            return (op, hash);
        }
        op.signature = sig;
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
        batch[0] = Execution({target: address(usdc), value: 0, callData: usdcData});
        batch[1] = Execution({target: address(dai), value: 0, callData: daiData});
        batch[2] = Execution({target: address(usdt), value: 0, callData: usdtData});
        bytes memory opCalldata =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(batch)));
        (PackedUserOperation memory op,) =
            _createUserOpWithSignature(sessionKey, address(_scw), address(cam), opCalldata);
        // Execute the user operation
        _executeUserOp(op);
    }
}
