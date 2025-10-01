// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ResourceLockValidator} from "../src/modules/validators/ResourceLockValidator.sol";

contract ResourceLockValidatorSetupScript is Script {
    bytes32 public immutable SALT = bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:salt"));
    bytes32 public immutable TEST_SALT = bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:test_salt"));
    address public constant DEPLOYER = 0x09FD4F6088f2025427AB1e89257A44747081Ed59;
    address public constant EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS = 0x0000000000000000000000000000000000000000;
    address public constant DEPLOYED_CREDIBLE_ACCOUNT_MODULE_ADDRESS = 0xC7286cFD9FaD8aaDa0647B91a07Fa9ECdbadAcA1;

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
        // // if (EXPECTED_RESOURCE_LOCK_VALIDATOR.code.length == 0) {
        resourceLockValidator = new ResourceLockValidator{salt: TEST_SALT}(DEPLOYER);
        // // if (address(resourceLockValidator) != EXPECTED_RESOURCE_LOCK_VALIDATOR) {
        // //     revert("Unexpected ResourceLockValidator address!!!");
        // // } else {
        console2.log("ResourceLockValidator deployed at address", address(resourceLockValidator));
        // //     }
        // // } else {
        // //     console2.log("ResourceLockValidator already deployed at address", EXPECTED_RESOURCE_LOCK_VALIDATOR);
        // // }

        /*//////////////////////////////////////////////////////////////
                              Finishing Deployment
        //////////////////////////////////////////////////////////////*/
        console2.log("Finished deployment sequence!");

        vm.stopBroadcast();
    }
}
