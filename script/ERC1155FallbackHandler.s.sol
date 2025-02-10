// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1155FallbackHandler} from "../src/modules/fallbacks/ERC1155FallbackHandler.sol";

/**
 * @author Etherspot.
 * @title  ERC1155FallbackHandlerScript.
 * @dev Deployment script for ERC1155FallbackHandler. Deploys:
 * ERC1155FallbackHandler.
 */

contract ERC1155FallbackHandlerScript is Script {
    bytes32 public immutable SALT =
        bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:salt"));
    address public constant DEPLOYER =
        0x09FD4F6088f2025427AB1e89257A44747081Ed59;
    address public constant EXPECTED_ERC1155_FALLBACK_HANDLER = address(0);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("Starting deployment sequence...");

        /*//////////////////////////////////////////////////////////////
                        Deploy ModularEtherspotWallet
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying ModularEtherspotWallet implementation...");
        if (EXPECTED_ERC1155_FALLBACK_HANDLER.code.length == 0) {
            ERC1155FallbackHandler erc1155Fallback = new ERC1155FallbackHandler{
                salt: SALT
            }();
            if (address(erc1155Fallback) != EXPECTED_ERC1155_FALLBACK_HANDLER) {
                revert("Unexpected ERC1155 fallback handler address!!!");
            } else {
                console2.log(
                    "ERC1155 fallback handler deployed at address",
                    address(erc1155Fallback)
                );
                // bytes memory implCode = address(erc1155Fallback).code;
                // console2.logBytes(implCode);
            }
        } else {
            console2.log(
                "ERC1155 fallback handler already deployed at address",
                EXPECTED_ERC1155_FALLBACK_HANDLER
            );
        }

        console2.log("Finished deployment sequence!");

        vm.stopBroadcast();
    }
}
