// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC20SessionKeyValidator} from "../src/modules/validators/ERC20SessionKeyValidator.sol";

/**
 * @author Etherspot.
 * @title  ERC20SessionKeyValidatorScript.
 * @dev Deployment script for ERC20SessionKeyValidator.
 */

contract ERC20SessionKeyValidatorScript is Script {
    bytes32 public immutable SALT =
        bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:salt"));
    address public constant EXPECTED_ERC20_SESSION_KEY_VALIDATOR =
        0x60Da6Cc14d817a88DC354d6dB6314DCD41b7aA54;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("Starting deployment sequence...");

        /*//////////////////////////////////////////////////////////////
                         Deploy ERC20SessionKeyValidator
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying ERC20SessionKeyValidator...");
        if (EXPECTED_ERC20_SESSION_KEY_VALIDATOR.code.length == 0) {
            ERC20SessionKeyValidator erc20SessionKeyValidator = new ERC20SessionKeyValidator{
                    salt: SALT
                }();
            if (
                address(erc20SessionKeyValidator) !=
                EXPECTED_ERC20_SESSION_KEY_VALIDATOR
            ) {
                revert("Unexpected wallet implementation address!!!");
            } else {
                console2.log(
                    "ERC20SessionKeyValidator deployed at address",
                    address(erc20SessionKeyValidator)
                );
            }
        } else {
            console2.log(
                "Already deployed at address",
                EXPECTED_ERC20_SESSION_KEY_VALIDATOR
            );
        }
        // bytes memory valCode = address(erc20SessionKeyValidator).code;
        // console2.logBytes(valCode);

        console2.log("Finished deployment sequence!");

        vm.stopBroadcast();
    }
}
