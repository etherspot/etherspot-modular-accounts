// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {HookMultiPlexer} from "../../src/modules/hooks/HookMultiPlexer.sol";
import {CredibleAccountModule} from "../../src/modules/validators/CredibleAccountModule.sol";
import {ResourceLockValidator} from "../../src/modules/validators/ResourceLockValidator.sol";
import {InvoiceManager} from "../../src/utils/InvoiceManager.sol";
import {
    DEPLOYER,
    PULSE_TEST_SALT,
    TESTING_CREDIBLE_ACCOUNT_MODULE_ADDRESS,
    TESTING_HOOK_MULTIPLEXER_ADDRESS,
    TESTING_INVOICE_MANAGER_ADDRESS,
    TESTING_RESOURCE_LOCK_VALIDATOR_ADDRESS,
    TEST_USDC_BASE_SEPOLIA,
    TEST_USDT_BASE_SEPOLIA,
    TEST_USDC_SEPOLIA,
    TEST_USDT_SEPOLIA
} from "./utils/PulseConstants.sol";

contract PULSE_DeployTestContracts is Script {
    address[] public INVOICE_MANAGER_WHITELISTED_TOKENS = [TEST_USDC_BASE_SEPOLIA, TEST_USDT_BASE_SEPOLIA];
    address[] public sessionKeyDisablers = [0x7021E9F891972dd9237893e764d505bC7f58d0B9];

    function run() external {
        HookMultiPlexer hookMultiPlexer;
        CredibleAccountModule credibleAccountModule;
        ResourceLockValidator resourceLockValidator;
        InvoiceManager invoiceManager;
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        /*//////////////////////////////////////////////////////////////
                            Starting Deployment
        //////////////////////////////////////////////////////////////*/

        console2.log("Starting deployment sequence...");

        /*//////////////////////////////////////////////////////////////
                            Deploy HookMultiPlexer
        //////////////////////////////////////////////////////////////*/

        console2.log("Using existing HookMultiPlexer deployed at:", TESTING_HOOK_MULTIPLEXER_ADDRESS);

        /*//////////////////////////////////////////////////////////////
                      Deploy CredibleAccountModule
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying CredibleAccountModule...");
        if (TESTING_CREDIBLE_ACCOUNT_MODULE_ADDRESS.code.length == 0) {
            credibleAccountModule =
                new CredibleAccountModule{salt: PULSE_TEST_SALT}(DEPLOYER, TESTING_HOOK_MULTIPLEXER_ADDRESS);
            if (address(credibleAccountModule) != TESTING_CREDIBLE_ACCOUNT_MODULE_ADDRESS) {
                revert("Unexpected CredibleAccountModule address!!!");
            } else {
                console2.log("CredibleAccountModule deployed at address", address(credibleAccountModule));
            }
        } else {
            console2.log("CredibleAccountModule already deployed at address", TESTING_CREDIBLE_ACCOUNT_MODULE_ADDRESS);
        }

        /*//////////////////////////////////////////////////////////////
                        Deploy ResourceLockValidator
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying ResourceLockValidator...");
        if (TESTING_RESOURCE_LOCK_VALIDATOR_ADDRESS.code.length == 0) {
            resourceLockValidator = new ResourceLockValidator{salt: PULSE_TEST_SALT}(DEPLOYER);
            if (address(resourceLockValidator) != TESTING_RESOURCE_LOCK_VALIDATOR_ADDRESS) {
                revert("Unexpected ResourceLockValidator address!!!");
            } else {
                console2.log("ResourceLockValidator deployed at address", address(resourceLockValidator));
            }
        } else {
            console2.log("ResourceLockValidator already deployed at address", TESTING_RESOURCE_LOCK_VALIDATOR_ADDRESS);
        }

        /*//////////////////////////////////////////////////////////////
                            Deploy InvoiceManager
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying InvoiceManager...");
        if (TESTING_INVOICE_MANAGER_ADDRESS.code.length == 0) {
            invoiceManager =
                new InvoiceManager{salt: PULSE_TEST_SALT}(DEPLOYER, address(credibleAccountModule), DEPLOYER, DEPLOYER);
            if (address(invoiceManager) != TESTING_INVOICE_MANAGER_ADDRESS) {
                revert("Unexpected InvoiceManager address!!!");
            } else {
                console2.log("InvoiceManager deployed at address", address(invoiceManager));
            }
        } else {
            console2.log("InvoiceManager already deployed at address", TESTING_INVOICE_MANAGER_ADDRESS);
        }

        /*//////////////////////////////////////////////////////////////
        CredibleAccountModule/ResourceLockValidator/InvoiceManager Setup
        //////////////////////////////////////////////////////////////*/

        console2.log("Setting up CredibleAccountModule and ResourceLockValidator...");
        address camSetup = credibleAccountModule.resourceLockValidator();
        address imSetup = credibleAccountModule.invoiceManager();
        address rlvSetup = resourceLockValidator.credibleAccountModule();
        uint256 whitelistedTokensLen = invoiceManager.getWhitelistedTokensCount();
        if (camSetup != TESTING_RESOURCE_LOCK_VALIDATOR_ADDRESS && imSetup != TESTING_INVOICE_MANAGER_ADDRESS) {
            credibleAccountModule.configure(address(resourceLockValidator), address(invoiceManager));
        } else {
            console2.log("The CredibleAccountModule has already been setup");
        }
        if (rlvSetup != TESTING_CREDIBLE_ACCOUNT_MODULE_ADDRESS) {
            resourceLockValidator.setCredibleAccountModule(address(credibleAccountModule));
        } else {
            console2.log("The ResourceLockValidator has already been setup");
        }
        if (whitelistedTokensLen == 0) {
            invoiceManager.addTokensToWhitelist(INVOICE_MANAGER_WHITELISTED_TOKENS);
            uint256 newLen = invoiceManager.getWhitelistedTokensCount();
            if (newLen > 0) {
                console2.log("Tokens have been whitelisted in InvoiceManager:");
                address[] memory wlTokens = invoiceManager.getWhitelistedTokens();
                for (uint256 j; j < newLen; ++j) {
                    console2.log("Whitelisted token:", wlTokens[j]);
                }
            } else {
                console2.log("Whitelisting tokens on InvoiceManager failed!");
            }
        } else {
            console2.log("The InvoiceManager has already been setup with whitelisted tokens");
        }
        console2.log("CredibleAccountModule, ResourceLockValidator and InvoiceManager setup complete!");

        /*//////////////////////////////////////////////////////////////
            Optional: Add SessionKeyDisablers To CredibleAccountModule
        //////////////////////////////////////////////////////////////*/

        console2.log("Granting SESSION_KEY_DISABLER_ROLE...");
        if (sessionKeyDisablers.length > 0) {
            for (uint256 i; i < sessionKeyDisablers.length; ++i) {
                console2.log("Granting SESSION_KEY_DISABLER_ROLE to", sessionKeyDisablers[i]);
                credibleAccountModule.grantSessionKeyDisablerRole(sessionKeyDisabler);
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
