// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {HookMultiPlexer} from "../src/modules/hooks/HookMultiPlexer.sol";

/**
 * @author Etherspot.
 * @title  HookMultiPlexerScript.
 * @dev Deployment script for HookMultiPlexer.
 *
 * To run script: forge script script/HookMultiPlexer.s.sol:HookMultiPlexerScript --broadcast -vvvv --rpc-url <chain name>
 * If error: Failed to get EIP-1559 fees: add --legacy tag
 * For certain chains (currently only mantle and mantle_sepolia): add --skip-simulation tag
 */
contract HookMultiPlexerScript is Script {
    bytes32 public immutable SALT = bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:salt"));

    /*//////////////////////////////////////////////////////////////
                  Replace These Values With Your Own
    //////////////////////////////////////////////////////////////*/
    address public constant DEPLOYER = 0x09FD4F6088f2025427AB1e89257A44747081Ed59;
    address public constant EXPECTED_HMP = 0xDcA918dd23456d321282DF9507F6C09A50522136;

    function run() external {
        HookMultiPlexer hookMultiPlexer;
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console2.log("Starting deployment sequence...");

        /*//////////////////////////////////////////////////////////////
                             Deploy HookMultiPlexer
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying HookMultiPlexer implementation...");
        if (EXPECTED_HMP.code.length == 0) {
            hookMultiPlexer = new HookMultiPlexer{salt: SALT}();
            if (address(hookMultiPlexer) != EXPECTED_HMP) {
                revert("Unexpected HookMultiPlexer address!!!");
            } else {
                console2.log("HookMultiPlexer deployed at address", address(hookMultiPlexer));
            }
        } else {
            console2.log("HookMultiPlexer already deployed at address", EXPECTED_HMP);
        }

        /*//////////////////////////////////////////////////////////////
                              Finishing Deployment
        //////////////////////////////////////////////////////////////*/
        console2.log("Finished deployment sequence!");

        vm.stopBroadcast();
    }
}
