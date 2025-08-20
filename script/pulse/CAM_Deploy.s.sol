// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {CredibleAccountModule} from "../../src/modules/validators/CredibleAccountModule.sol";
import {ResourceLockValidator} from "../../src/modules/validators/ResourceLockValidator.sol";
import {InvoiceManager} from "../../src/utils/InvoiceManager.sol";
import {
    DEPLOYER,
    PULSE_SALT,
    PULSE_TEST_SALT,
    EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS,
    EXPECTED_HOOK_MULTIPLEXER_ADDRESS,
    EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS,
    EXPECTED_INVOICE_MANAGER_ADDRESS
} from "./utils/PulseConstants.sol";

contract CAM_Deploy is Script {
    address[] public sessionKeyDisablers = [0x7021E9F891972dd9237893e764d505bC7f58d0B9];

    function run() external {
        CredibleAccountModule credibleAccountModule;
        ResourceLockValidator resourceLockValidator;
        InvoiceManager invoiceManager;
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        /*//////////////////////////////////////////////////////////////
                            Starting Deployment
        //////////////////////////////////////////////////////////////*/

        console2.log("Starting deployment sequence...");
        resourceLockValidator = ResourceLockValidator(EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS);
        invoiceManager = InvoiceManager(EXPECTED_INVOICE_MANAGER_ADDRESS);

        /*//////////////////////////////////////////////////////////////
                            Deploy HookMultiPlexer
        //////////////////////////////////////////////////////////////*/

        console2.log("Using existing HookMultiPlexer deployed at:", EXPECTED_HOOK_MULTIPLEXER_ADDRESS);

        /*//////////////////////////////////////////////////////////////
                      Deploy CredibleAccountModule
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying CredibleAccountModule...");
        if (EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS.code.length == 0) {
            credibleAccountModule =
                new CredibleAccountModule{salt: PULSE_SALT}(DEPLOYER, EXPECTED_HOOK_MULTIPLEXER_ADDRESS);
            if (address(credibleAccountModule) != EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS) {
                revert("Unexpected CredibleAccountModule address!!!");
            } else {
                console2.log("CredibleAccountModule deployed at address", address(credibleAccountModule));
            }
        } else {
            console2.log("CredibleAccountModule already deployed at address", EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS);
        }

        /*//////////////////////////////////////////////////////////////
                              Configuration
      //////////////////////////////////////////////////////////////*/

        console2.log("Configuring CredibleAccountModule...");
        address camSetup = credibleAccountModule.resourceLockValidator();
        address imSetup = credibleAccountModule.invoiceManager();
        if (camSetup != EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS && imSetup != EXPECTED_INVOICE_MANAGER_ADDRESS) {
            credibleAccountModule.configure(address(resourceLockValidator), address(invoiceManager));
        } else {
            console2.log("CredibleAccountModule has already been configured");
        }
        console2.log("CredibleAccountModule configuration complete!");

        /*//////////////////////////////////////////////////////////////
            Optional: Add SessionKeyDisablers To CredibleAccountModule
        //////////////////////////////////////////////////////////////*/

        console2.log("Granting SESSION_KEY_DISABLER_ROLE...");
        if (sessionKeyDisablers.length > 0) {
            for (uint256 i; i < sessionKeyDisablers.length; ++i) {
                console2.log("Granting SESSION_KEY_DISABLER_ROLE to", sessionKeyDisablers[i]);
                credibleAccountModule.grantSessionKeyDisablerRole(sessionKeyDisablers[i]);
            }
            address[] memory disablerRole = credibleAccountModule.getSessionKeyDisablers();
            console2.log("Addresses with SESSION_KEY_DISABLER_ROLE:", disablerRole.length);
            for (uint256 i; i < disablerRole.length; ++i) {
                console2.log(disablerRole[i]);
            }
        }

        /*//////////////////////////////////////////////////////////////
                              Finishing Deployment
        //////////////////////////////////////////////////////////////*/
        console2.log("Finished deployment sequence!");

        vm.stopBroadcast();
    }
}
