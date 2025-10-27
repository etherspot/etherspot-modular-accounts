// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {InvoiceManager} from "../../src/invoice_manager/InvoiceManager.sol";
import {EXPECTED_INVOICE_MANAGER_ADDRESS} from "./utils/PulseConstants.sol";

contract IM_UpdateSolverPulseFee is Script {
    InvoiceManager public invoiceManager;

    // Configuration for updating solver's pulse fee
    // Update these values before running the script
    address public solverAddress = 0x7C84F10502FcDea2E403b70feA96a4aE990a34DF; // Update with actual solver address
    uint256 public newPulseFee = 10; // 0 = use default 5 cents, >0 = custom fee amount in cents

    function run() external {
        // using deployer as this also has FEE_MANAGER_ROLE
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        invoiceManager = InvoiceManager(EXPECTED_INVOICE_MANAGER_ADDRESS);

        console2.log("Starting updating solver's pulse fee process...");
        console2.log("InvoiceManager address:", address(invoiceManager));

        /*//////////////////////////////////////////////////////////////
                             Validate Configuration
        //////////////////////////////////////////////////////////////*/

        require(solverAddress != address(0), "Solver address must be set");

        console2.log("Solver address:", solverAddress);
        console2.log("Pulse fee (0 = default):", newPulseFee);

        /*//////////////////////////////////////////////////////////////
                         Update Solver's Pulse Fee
        //////////////////////////////////////////////////////////////*/

        try invoiceManager.updateSolverFee(solverAddress, newPulseFee) {
            console2.log("Successfully updated solver's pulse fee to:", newPulseFee);
        } catch {
            console2.log("Updating solver fee failed for:", solverAddress);
        }

        vm.stopBroadcast();
    }
}
