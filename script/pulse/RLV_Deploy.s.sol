// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ResourceLockValidator} from "../../src/modules/validators/ResourceLockValidator.sol";
import {
    DEPLOYER,
    EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS,
    EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS,
    PULSE_SALT,
    PULSE_TEST_SALT
} from "./utils/PulseConstants.sol";

contract RLV_Deploy is Script {
    bytes32 public immutable SALT = bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:salt"));

    function run() external {
        ResourceLockValidator resourceLockValidator;
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        /*//////////////////////////////////////////////////////////////
                            Starting Deployment
        //////////////////////////////////////////////////////////////*/

        console2.log("Starting deployment sequence...");

        /*//////////////////////////////////////////////////////////////
                        Deploy ResourceLockValidator
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying ResourceLockValidator...");
        if (EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS.code.length == 0) {
            resourceLockValidator = new ResourceLockValidator{salt: PULSE_SALT}(DEPLOYER);
            if (address(resourceLockValidator) != EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS) {
                revert("Unexpected ResourceLockValidator address!!!");
            } else {
                console2.log("ResourceLockValidator deployed at address", address(resourceLockValidator));
            }
        } else {
            console2.log("ResourceLockValidator already deployed at address", EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS);
        }

        /*//////////////////////////////////////////////////////////////
                                Configuration
        //////////////////////////////////////////////////////////////*/

        console2.log("Configuring ResourceLockValidator...");
        address rlvSetup = resourceLockValidator.credibleAccountModule();
        if (rlvSetup != EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS) {
            resourceLockValidator.setCredibleAccountModule(EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS);
        } else {
            console2.log("The ResourceLockValidator has already been setup");
        }
        console2.log("ResourceLockValidator configuration complete!");

        /*//////////////////////////////////////////////////////////////
                              Finishing Deployment
        //////////////////////////////////////////////////////////////*/
        console2.log("Finished deployment sequence!");

        vm.stopBroadcast();
    }
}
