// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {CredibleAccountModule} from "../../src/modules/validators/CredibleAccountModule.sol";
import {
    EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS,
    EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS,
    EXPECTED_INVOICE_MANAGER_ADDRESS
} from "./utils/PulseConstants.sol";

contract CAM_UpdateConfiguration is Script {
    CredibleAccountModule public credibleAccountModule;

    address public resourceLockValidator = EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS;
    address public invoiceManager = EXPECTED_INVOICE_MANAGER_ADDRESS;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        credibleAccountModule = CredibleAccountModule(EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS);

        console2.log("Starting CredibleAccountModule configuration...");

        /*//////////////////////////////////////////////////////////////
                            Initial Configuration
          //////////////////////////////////////////////////////////////*/

        address currentRLV = credibleAccountModule.resourceLockValidator();
        address currentIM = credibleAccountModule.invoiceManager();

        console2.log("Current ResourceLockValidator:", currentRLV);
        console2.log("Current InvoiceManager:", currentIM);

        if (currentRLV == address(0) || currentIM == address(0)) {
            console2.log("Configuring CredibleAccountModule with:");
            console2.log("ResourceLockValidator:", resourceLockValidator);
            console2.log("InvoiceManager:", invoiceManager);

            credibleAccountModule.configure(resourceLockValidator, invoiceManager);
            console2.log("CredibleAccountModule configured successfully!");
        } else if (currentRLV != resourceLockValidator || currentIM != invoiceManager) {
            console2.log("Updating CredibleAccountModule with:");
            console2.log("ResourceLockValidator:", resourceLockValidator);
            console2.log("InvoiceManager:", invoiceManager);

            credibleAccountModule.configure(resourceLockValidator, invoiceManager);
            console2.log("CredibleAccountModule configuration updated successfully!");
        } else {
            console2.log("CredibleAccountModule already configured");
        }

        /*//////////////////////////////////////////////////////////////
                              Verify Configuration
        //////////////////////////////////////////////////////////////*/

        address finalRLV = credibleAccountModule.resourceLockValidator();
        address finalIM = credibleAccountModule.invoiceManager();

        console2.log("Final configuration:");
        console2.log("ResourceLockValidator:", finalRLV);
        console2.log("InvoiceManager:", finalIM);

        // Verify constants
        uint256 maxSessionKeys = credibleAccountModule.MAX_SESSION_KEYS();
        uint256 maxLockedTokens = credibleAccountModule.MAX_LOCKED_TOKENS();
        uint256 timeBuffer = credibleAccountModule.DISABLE_SESSION_KEY_TIME_BUFFER();

        console2.log("Configuration constants:");
        console2.log("MAX_SESSION_KEYS:", maxSessionKeys);
        console2.log("MAX_LOCKED_TOKENS:", maxLockedTokens);
        console2.log("DISABLE_SESSION_KEY_TIME_BUFFER:", timeBuffer);

        console2.log("CredibleAccountModule configuration completed!");

        vm.stopBroadcast();
    }
}
