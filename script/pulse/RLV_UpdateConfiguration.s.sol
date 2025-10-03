// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ResourceLockValidator} from "../../src/modules/validators/ResourceLockValidator.sol";
import {
    EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS,
    EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS
} from "./utils/PulseConstants.sol";

contract RLV_UpdateConfiguration is Script {
    ResourceLockValidator public resourceLockValidator;

    address public credibleAccountModule = EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        resourceLockValidator = ResourceLockValidator(EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS);

        console2.log("Starting ResourceLockValidator configuration...");

        /*//////////////////////////////////////////////////////////////
                          Set CredibleAccountModule
          //////////////////////////////////////////////////////////////*/

        address currentCAM = resourceLockValidator.getCredibleAccountModule();
        address owner = resourceLockValidator.owner();

        console2.log("Current CredibleAccountModule:", currentCAM);
        console2.log("ResourceLockValidator owner:", owner);

        if (currentCAM != credibleAccountModule) {
            console2.log("Updating CredibleAccountModule to:", credibleAccountModule);
            resourceLockValidator.setCredibleAccountModule(credibleAccountModule);
            console2.log("CredibleAccountModule updated successfully!");
        } else {
            console2.log("CredibleAccountModule already configured correctly");
        }

        /*//////////////////////////////////////////////////////////////
                              Verify Configuration
          //////////////////////////////////////////////////////////////*/

        address finalCAM = resourceLockValidator.getCredibleAccountModule();
        console2.log("Final CredibleAccountModule address:", finalCAM);

        console2.log("ResourceLockValidator configuration completed!");

        vm.stopBroadcast();
    }
}
