// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {InvoiceManager} from "../../src/utils/InvoiceManager.sol";
import {
    DEPLOYER,
    EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS,
    EXPECTED_INVOICE_MANAGER_ADDRESS,
    PULSE_SALT,
    PULSE_TEST_SALT,
    TEST_USDC_BASE_SEPOLIA,
    TEST_USDT_BASE_SEPOLIA
} from "./utils/PulseConstants.sol";

contract PULSE_DeployTestContracts is Script {
    address[] public tokenWhitelist = [TEST_USDC_BASE_SEPOLIA, TEST_USDT_BASE_SEPOLIA];
    address[] public sessionKeyDisablers = [0x7021E9F891972dd9237893e764d505bC7f58d0B9];

    function run() external {
        InvoiceManager invoiceManager;
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        /*//////////////////////////////////////////////////////////////
                            Starting Deployment
        //////////////////////////////////////////////////////////////*/

        console2.log("Starting deployment sequence...");

        /*//////////////////////////////////////////////////////////////
                            Deploy InvoiceManager
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying InvoiceManager...");
        if (EXPECTED_INVOICE_MANAGER_ADDRESS.code.length == 0) {
            invoiceManager = new InvoiceManager{salt: PULSE_SALT}(
                DEPLOYER, EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS, DEPLOYER, DEPLOYER
            );
            if (address(invoiceManager) != EXPECTED_INVOICE_MANAGER_ADDRESS) {
                revert("Unexpected InvoiceManager address!!!");
            } else {
                console2.log("InvoiceManager deployed at address", address(invoiceManager));
            }
        } else {
            console2.log("InvoiceManager already deployed at address", EXPECTED_INVOICE_MANAGER_ADDRESS);
        }

        /*//////////////////////////////////////////////////////////////
                          Token Whitelisting
    //////////////////////////////////////////////////////////////*/

        console2.log("Whitelisting tokens for InvoiceManager...");
        uint256 whitelistedTokensLen = invoiceManager.getWhitelistedTokensCount();

        if (whitelistedTokensLen == 0) {
            invoiceManager.addTokensToWhitelist(tokenWhitelist);
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

        /*//////////////////////////////////////////////////////////////
                              Finishing Deployment
        //////////////////////////////////////////////////////////////*/
        console2.log("Finished deployment sequence!");

        vm.stopBroadcast();
    }
}
