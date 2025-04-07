// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IValidator} from "../../interfaces/base/IValidator.sol";
import {MODULE_TYPE_VALIDATOR, SIG_VALIDATION_SUCCESS} from "../../types/Constants.sol";

contract MockValidator is IValidator {
    function onInstall(bytes calldata data) external override {}

    function onUninstall(bytes calldata data) external override {}

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        override
        returns (uint256)
    {
        bytes4 execSelector = bytes4(userOp.callData[:4]);

        return SIG_VALIDATION_SUCCESS;
    }

    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata data)
        external
        view
        override
        returns (bytes4)
    {}

    function isModuleType(uint256 moduleTypeId) external view returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }

    function isInitialized(address smartAccount) external view returns (bool) {
        return false;
    }
}
