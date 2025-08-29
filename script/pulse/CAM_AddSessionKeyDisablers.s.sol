// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {CredibleAccountModule} from "../../src/modules/validators/CredibleAccountModule.sol";
import {DEPLOYER, EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS} from "./utils/PulseConstants.sol";

contract CAM_AddSessionKeyDisablers is Script {
    // Add addresses here for those you want to grant SESSION_KEY_DISABLER_ROLE to:
    address[] public sessionKeyDisablers = [0xbc4aECba01E015fb88527AF0c65B37C874b2b1fE];

    function run() external {
        CredibleAccountModule credibleAccountModule = CredibleAccountModule(EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS);
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        /*//////////////////////////////////////////////////////////////
              Add SessionKeyDisablers To CredibleAccountModule
        //////////////////////////////////////////////////////////////*/

        for (uint256 i; i < sessionKeyDisablers.length; ++i) {
            console2.log("Granting SESSION_KEY_DISABLER_ROLE to", sessionKeyDisablers[i]);
            credibleAccountModule.grantSessionKeyDisablerRole(sessionKeyDisablers[i]);
        }
        address[] memory disablerRole = credibleAccountModule.getSessionKeyDisablers();
        console2.log("Addresses with SESSION_KEY_DISABLER_ROLE:", disablerRole.length);
        for (uint256 i; i < disablerRole.length; ++i) {
            console2.log(disablerRole[i]);
        }

        vm.stopBroadcast();
    }
}
