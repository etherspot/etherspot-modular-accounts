// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {CredibleAccountModule} from "../../src/modules/validators/CredibleAccountModule.sol";
import {EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS} from "./utils/ScriptConstants.sol";

contract CAM_SessionKeyMaintenance is Script {
    CredibleAccountModule public credibleAccountModule;

    // Wallets to check for expired session keys
    address[] public walletsToClean = [
        0x1111111111111111111111111111111111111111,
        0x2222222222222222222222222222222222222222,
        0x3333333333333333333333333333333333333333
    ];

    // Emergency session keys to disable
    address[] public emergencyDisableKeys;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        credibleAccountModule = CredibleAccountModule(EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS);

        console2.log("Starting CredibleAccountModule session key maintenance...");

        /*//////////////////////////////////////////////////////////////
                          Clean Expired Session Keys
          //////////////////////////////////////////////////////////////*/

        console2.log("Checking wallets for expired session keys...");

        if (walletsToClean.length > 0) {
            for (uint256 i; i < walletsToClean.length; ++i) {
                address wallet = walletsToClean[i];
                console2.log("Checking wallet:", wallet);

                address[] memory expiredKeys = credibleAccountModule.getExpiredSessionKeysForWallet(wallet);

                if (expiredKeys.length > 0) {
                    console2.log("Found", expiredKeys.length, "expired session keys");
                    console2.log("Batch disabling expired session keys...");

                    credibleAccountModule.batchDisableSessionKeys(expiredKeys);
                    console2.log("Expired session keys disabled for wallet:", wallet);
                } else {
                    console2.log("No expired session keys found for wallet:", wallet);
                }
            }
        }

        /*//////////////////////////////////////////////////////////////
                        Emergency Disable Session Keys
          //////////////////////////////////////////////////////////////*/

        if (emergencyDisableKeys.length > 0) {
            console2.log("Emergency disabling session keys...");

            for (uint256 i; i < emergencyDisableKeys.length; ++i) {
                address sessionKey = emergencyDisableKeys[i];
                console2.log("Emergency disabling session key:", sessionKey);

                try credibleAccountModule.emergencyDisableSessionKey(sessionKey) {
                    console2.log("Session key disabled successfully");
                } catch {
                    console2.log("Session key not found or already disabled");
                }
            }
        }

        /*//////////////////////////////////////////////////////////////
                               Report Statistics
          //////////////////////////////////////////////////////////////*/

        console2.log("Generating maintenance report...");

        for (uint256 i; i < walletsToClean.length; ++i) {
            address wallet = walletsToClean[i];
            address[] memory liveKeys = credibleAccountModule.getLiveSessionKeysForWallet(wallet);
            address[] memory expiredKeys = credibleAccountModule.getExpiredSessionKeysForWallet(wallet);

            console2.log("Wallet:", wallet);
            console2.log("  Live session keys:", liveKeys.length);
            console2.log("  Expired session keys:", expiredKeys.length);
        }

        console2.log("Session key maintenance completed!");

        vm.stopBroadcast();
    }
}
