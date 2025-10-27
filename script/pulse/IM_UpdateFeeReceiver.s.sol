// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {InvoiceManager} from "../../src/invoice_manager/InvoiceManager.sol";
import {EXPECTED_INVOICE_MANAGER_ADDRESS} from "./utils/PulseConstants.sol";

contract IM_UpdateFeeReceiver is Script {
    InvoiceManager public invoiceManager;

    // Configuration for updating pulse fee receiver
    // Update these values before running the script
    address public newFeeReceiver = 0x24D6c5aFBfe04E3231115D9f496DEe837D7F8233;

    function run() external {
        // using deployer as this also has FEE_MANAGER_ROLE
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        invoiceManager = InvoiceManager(EXPECTED_INVOICE_MANAGER_ADDRESS);

        console2.log("Starting updating pulse fee receiver address...");
        console2.log("InvoiceManager address:", address(invoiceManager));

        /*//////////////////////////////////////////////////////////////
                             Validate Configuration
        //////////////////////////////////////////////////////////////*/

        require(newFeeReceiver != address(0), "New fee receiver must be set");

        console2.log("Pulse fee receiver address:", newFeeReceiver);

        /*//////////////////////////////////////////////////////////////
                         Update Solver's Pulse Fee
        //////////////////////////////////////////////////////////////*/

        try invoiceManager.setFeeReceiver(newFeeReceiver) {
            console2.log("Successfully updated the pulse fee receiver address to:", newFeeReceiver);
        } catch {
            console2.log("Updating pulse fee receiver failed for:", newFeeReceiver);
        }

        vm.stopBroadcast();
    }
}
