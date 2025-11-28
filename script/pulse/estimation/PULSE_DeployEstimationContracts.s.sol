// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {HookMultiPlexer} from "../../../src/modules/hooks/HookMultiPlexer.sol";
import {CredibleAccountModule} from "../../../src/test/estimation/CredibleAccountModuleEstimation.sol";
import {ResourceLockValidator} from "../../../src/test/estimation/ResourceLockValidatorEstimation.sol";
import {InvoiceManager} from "../../../src/invoice_manager/InvoiceManager.sol";
import {
    DAI_ARBITRUM,
    DAI_BASE,
    DAI_BSC,
    DAI_ETHEREUM,
    DAI_OPTIMISM,
    DAI_POLYGON,
    DEPLOYER,
    PULSE_TEST_SALT,
    ESTIMATION_CREDIBLE_ACCOUNT_MODULE_ADDRESS,
    TESTING_HOOK_MULTIPLEXER_ADDRESS,
    ESTIMATION_INVOICE_MANAGER_ADDRESS,
    ESTIMATION_RESOURCE_LOCK_VALIDATOR_ADDRESS,
    USDC_ARBITRUM,
    USDC_BASE,
    USDC_BSC,
    USDC_ETHEREUM,
    USDC_GNOSIS,
    USDC_OPTIMISM,
    USDC_POLYGON,
    USDCE_ARBITRUM,
    USDCE_BSC,
    USDCE_GNOSIS,
    USDCE_OPTIMISM,
    USDCE_POLYGON,
    USDT_ARBITRUM,
    USDT_BSC,
    USDT_ETHEREUM,
    USDT_ETHEREUM,
    USDT_GNOSIS,
    USDT_OPTIMISM,
    USDT_POLYGON
} from "../utils/PulseConstants.sol";

contract PULSE_DeployEstimationContracts is Script {
    address[] public INVOICE_MANAGER_WHITELISTED_TOKENS = [USDC_POLYGON];
    address[] public sessionKeyDisablers = [0xb63D98DC1e8095a45791549A8326504b26e4A21c];
    address[] public settlerRole = [0xb63D98DC1e8095a45791549A8326504b26e4A21c];

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
        if (ESTIMATION_CREDIBLE_ACCOUNT_MODULE_ADDRESS.code.length == 0) {
            credibleAccountModule =
                new CredibleAccountModule{salt: PULSE_TEST_SALT}(DEPLOYER, TESTING_HOOK_MULTIPLEXER_ADDRESS);
            if (address(credibleAccountModule) != ESTIMATION_CREDIBLE_ACCOUNT_MODULE_ADDRESS) {
                revert("Unexpected CredibleAccountModule address!!!");
            } else {
                console2.log("CredibleAccountModule deployed at address", address(credibleAccountModule));
            }
        } else {
            console2.log(
                "CredibleAccountModule already deployed at address", ESTIMATION_CREDIBLE_ACCOUNT_MODULE_ADDRESS
            );
        }

        /*//////////////////////////////////////////////////////////////
                        Deploy ResourceLockValidator
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying ResourceLockValidator...");
        if (ESTIMATION_RESOURCE_LOCK_VALIDATOR_ADDRESS.code.length == 0) {
            resourceLockValidator = new ResourceLockValidator{salt: PULSE_TEST_SALT}(DEPLOYER);
            if (address(resourceLockValidator) != ESTIMATION_RESOURCE_LOCK_VALIDATOR_ADDRESS) {
                revert("Unexpected ResourceLockValidator address!!!");
            } else {
                console2.log("ResourceLockValidator deployed at address", address(resourceLockValidator));
            }
        } else {
            console2.log(
                "ResourceLockValidator already deployed at address", ESTIMATION_RESOURCE_LOCK_VALIDATOR_ADDRESS
            );
        }

        /*//////////////////////////////////////////////////////////////
                            Deploy InvoiceManager
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying InvoiceManager...");
        if (ESTIMATION_INVOICE_MANAGER_ADDRESS.code.length == 0) {
            invoiceManager =
                new InvoiceManager{salt: PULSE_TEST_SALT}(DEPLOYER, address(credibleAccountModule), DEPLOYER, DEPLOYER);
            if (address(invoiceManager) != ESTIMATION_INVOICE_MANAGER_ADDRESS) {
                revert("Unexpected InvoiceManager address!!!");
            } else {
                console2.log("InvoiceManager deployed at address", address(invoiceManager));
            }
        } else {
            console2.log("InvoiceManager already deployed at address", ESTIMATION_INVOICE_MANAGER_ADDRESS);
        }

        /*//////////////////////////////////////////////////////////////
        CredibleAccountModule/ResourceLockValidator/InvoiceManager Setup
        //////////////////////////////////////////////////////////////*/

        console2.log("Setting up CredibleAccountModule and ResourceLockValidator...");
        address camSetup = credibleAccountModule.resourceLockValidator();
        address imSetup = credibleAccountModule.invoiceManager();
        address rlvSetup = resourceLockValidator.credibleAccountModule();
        uint256 whitelistedTokensLen = invoiceManager.getWhitelistedTokensCount();
        if (camSetup != ESTIMATION_RESOURCE_LOCK_VALIDATOR_ADDRESS && imSetup != ESTIMATION_INVOICE_MANAGER_ADDRESS) {
            credibleAccountModule.configure(address(resourceLockValidator), address(invoiceManager));
        } else {
            console2.log("The CredibleAccountModule has already been setup");
        }
        if (rlvSetup != ESTIMATION_CREDIBLE_ACCOUNT_MODULE_ADDRESS) {
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
                credibleAccountModule.grantSessionKeyDisablerRole(sessionKeyDisablers[i]);
            }
            address[] memory disablerRole = credibleAccountModule.getSessionKeyDisablers();
            console2.log("Addresses with SESSION_KEY_DISABLER_ROLE:", disablerRole.length);
            for (uint256 i; i < disablerRole.length; ++i) {
                console2.log(disablerRole[i]);
            }
        }

        /*//////////////////////////////////////////////////////////////
                Optional: Add SettlerRole To InvoiceManager
        //////////////////////////////////////////////////////////////*/

        console2.log("Granting SETTLER_ROLE to addresses...");
        if (settlerRole.length > 0) {
            for (uint256 i; i < settlerRole.length; ++i) {
                address settler = settlerRole[i];
                console2.log("Granting SETTLER_ROLE to:", settler);
                invoiceManager.grantSettlerRole(settler);
            }
        }

        /*//////////////////////////////////////////////////////////////
                              Finishing Deployment
        //////////////////////////////////////////////////////////////*/
        console2.log("Finished deployment sequence!");

        vm.stopBroadcast();
    }
}
