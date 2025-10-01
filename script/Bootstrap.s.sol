// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Bootstrap} from "../src/utils/Bootstrap.sol";

/**
 * @author Etherspot.
 * @title BootstrapScript.
 * @dev Deployment script for Bootstrap.
 */
contract BootstrapScript is Script {
    bytes32 public immutable SALT = bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:salt"));
    address public constant EXPECTED_BOOTSTRAP = 0x8B8AD39700EB6f5903aAC9Cc34b6D28ae69D170B;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console2.log("Starting deployment sequence...");

        /*//////////////////////////////////////////////////////////////
                              Deploy Bootstrap
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying Bootstrap...");
        if (EXPECTED_BOOTSTRAP.code.length == 0) {
            Bootstrap bootstrap = new Bootstrap{salt: SALT}();
            if (address(bootstrap) != EXPECTED_BOOTSTRAP) {
                revert("Unexpected bootstrap address!!!");
            } else {
                console2.log("Bootstrap deployed at address", address(bootstrap));
            }
        } else {
            console2.log("Bootstrap already deployed at address", EXPECTED_BOOTSTRAP);
        }
        console2.log("Finished deployment sequence!");

        vm.stopBroadcast();
    }
}
