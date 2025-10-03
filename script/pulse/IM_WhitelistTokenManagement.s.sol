// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {InvoiceManager} from "../../src/invoice_manager/InvoiceManager.sol";
import {EXPECTED_INVOICE_MANAGER_ADDRESS, USDC_GNOSIS, USDC_OPTIMISM} from "./utils/PulseConstants.sol";

contract IM_WhitelistTokenManagement is Script {
    InvoiceManager public invoiceManager;

    // Tokens to add to whitelist
    // Leave empty to skip
    address[] public tokensToAdd = [USDC_OPTIMISM];

    // Tokens to remove from whitelist
    // Leave empty to skip
    address[] public tokensToRemove = [USDC_GNOSIS];

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        invoiceManager = InvoiceManager(EXPECTED_INVOICE_MANAGER_ADDRESS);

        console2.log("Starting InvoiceManager token management...");

        /*//////////////////////////////////////////////////////////////
                            Current Whitelist Status
          //////////////////////////////////////////////////////////////*/

        console2.log("Current whitelist status:");
        address[] memory currentTokens = invoiceManager.getWhitelistedTokens();
        console2.log("Total whitelisted tokens:", currentTokens.length);

        for (uint256 i; i < currentTokens.length; ++i) {
            console2.log("  Token:", currentTokens[i]);
        }

        console2.log("");

        /*//////////////////////////////////////////////////////////////
                            Add Tokens to Whitelist
          //////////////////////////////////////////////////////////////*/

        if (tokensToAdd.length > 0) {
            console2.log("Adding tokens to whitelist...");

            for (uint256 i; i < tokensToAdd.length; ++i) {
                address token = tokensToAdd[i];
                bool isAlreadyWhitelisted = invoiceManager.isTokenWhitelisted(token);

                if (!isAlreadyWhitelisted) {
                    console2.log("Adding token:", token);
                    invoiceManager.addTokenToWhitelist(token);
                    console2.log("Token added successfully");
                } else {
                    console2.log("Token already whitelisted:", token);
                }
            }
        }

        /*//////////////////////////////////////////////////////////////
                          Remove Tokens from Whitelist
          //////////////////////////////////////////////////////////////*/

        if (tokensToRemove.length > 0) {
            console2.log("Removing tokens from whitelist...");

            for (uint256 i; i < tokensToRemove.length; ++i) {
                address token = tokensToRemove[i];
                bool isWhitelisted = invoiceManager.isTokenWhitelisted(token);

                if (isWhitelisted) {
                    console2.log("Removing token:", token);
                    invoiceManager.removeTokenFromWhitelist(token);
                    console2.log("Token removed successfully");
                } else {
                    console2.log("Token not whitelisted:", token);
                }
            }
        }

        /*//////////////////////////////////////////////////////////////
                            Final Whitelist Status
          //////////////////////////////////////////////////////////////*/

        console2.log("Final whitelist status:");
        address[] memory finalTokens = invoiceManager.getWhitelistedTokens();
        console2.log("Total whitelisted tokens:", finalTokens.length);

        for (uint256 i; i < finalTokens.length; ++i) {
            console2.log("  Token:", finalTokens[i]);
        }

        console2.log("InvoiceManager token management completed!");

        vm.stopBroadcast();
    }
}
