// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IModule} from "./IModule.sol";

interface IPreValidationHookERC1271 is IModule {
    function preValidationHookERC1271(address sender, bytes32 hash, bytes calldata data)
        external
        view
        returns (bytes32 hookHash, bytes memory hookSignature);
}

interface IPreValidationHookERC4337 is IModule {
    function preValidationHookERC4337(
        PackedUserOperation calldata userOp,
        uint256 missingAccountFunds,
        bytes32 userOpHash
    ) external returns (bytes32 hookHash, bytes memory hookSignature);
}
