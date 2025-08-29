// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {InvoiceManager} from "../../src/utils/InvoiceManager.sol";
import {EXPECTED_INVOICE_MANAGER_ADDRESS} from "./utils/PulseConstants.sol";

contract IM_SolverOnboard is Script {
    InvoiceManager public invoiceManager;

    // Configuration for solver onboarding
    // Update these values before running the script
    address public solverAddress = 0x7C84F10502FcDea2E403b70feA96a4aE990a34DF; // Update with actual solver address
    string public solverName = "PULSE_SOLVER"; // Update with solver name
    uint256 public pulseFee = 0; // 0 = use default 5 cents, >0 = custom fee amount in cents

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        invoiceManager = InvoiceManager(EXPECTED_INVOICE_MANAGER_ADDRESS);

        console2.log("Starting solver onboarding process...");
        console2.log("InvoiceManager address:", address(invoiceManager));

        /*//////////////////////////////////////////////////////////////
                          Validate Configuration
          //////////////////////////////////////////////////////////////*/

        require(solverAddress != address(0), "Solver address must be set");
        require(bytes(solverName).length > 0, "Solver name must be set");

        console2.log("Solver address:", solverAddress);
        console2.log("Solver name:", solverName);
        console2.log("Pulse fee (0 = default):", pulseFee);

        /*//////////////////////////////////////////////////////////////
                          Check if Solver Already Exists
          //////////////////////////////////////////////////////////////*/

        try invoiceManager.getSolverData(solverAddress) returns (
            string memory existingName,
            bool isActive,
            uint256 successfulSettlements,
            uint256 activeInvoices,
            uint256 existingPulseFee
        ) {
            if (bytes(existingName).length > 0) {
                console2.log("Solver already exists - skipping onboarding");
                vm.stopBroadcast();
                return;
            }
        } catch {
            // Solver doesn't exist, proceed with onboarding
        }

        /*//////////////////////////////////////////////////////////////
                          Onboard Solver
          //////////////////////////////////////////////////////////////*/

        console2.log("Onboarding solver...");

        invoiceManager.onboardSolver(solverAddress, solverName, pulseFee);

        console2.log("Successfully onboarded solver!");

        vm.stopBroadcast();
    }
}
