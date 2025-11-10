// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {InvoiceManager} from "../../src/invoice_manager/InvoiceManager.sol";
import {ISolverManager} from "../../src/interfaces/ISolverManager.sol";
import {EXPECTED_INVOICE_MANAGER_ADDRESS} from "./utils/PulseConstants.sol";

contract IM_SolverOnboard is Script {
    InvoiceManager public invoiceManager;

    // Configuration for solver onboarding
    // Update these values before running the script
    address public executionAddress = 0x7C84F10502FcDea2E403b70feA96a4aE990a34DF; // Solver execution address (receives repayment)
    address public feeAddress = 0x7C84F10502FcDea2E403b70feA96a4aE990a34DF; // Solver fee address (can be same as execution)
    address public orchestratorReceiver = 0x0000000000000000000000000000000000000000; // Update with orchestrator address
    string public solverName = "PULSE_SOLVER";

    // Orchestrator fee configuration
    ISolverManager.FeeType public orchestratorFeeType = ISolverManager.FeeType.PERCENTAGE; // FIXED or PERCENTAGE
    uint256 public orchestratorFeeValue = 50; // 50 basis points = 0.5% (or cents if FIXED)

    // Solver fee configuration
    ISolverManager.FeeType public solverFeeType = ISolverManager.FeeType.PERCENTAGE; // FIXED or PERCENTAGE
    uint256 public solverFeeValue = 20; // 20 basis points = 0.2% (or cents if FIXED)

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        invoiceManager = InvoiceManager(EXPECTED_INVOICE_MANAGER_ADDRESS);

        console2.log("Starting solver onboarding process...");
        console2.log("InvoiceManager address:", address(invoiceManager));

        /*//////////////////////////////////////////////////////////////
                          Validate Configuration
          //////////////////////////////////////////////////////////////*/

        require(executionAddress != address(0), "Execution address must be set");
        require(feeAddress != address(0), "Fee address must be set");
        require(orchestratorReceiver != address(0), "Orchestrator receiver must be set");
        require(bytes(solverName).length > 0, "Solver name must be set");

        console2.log("Execution address:", executionAddress);
        console2.log("Fee address:", feeAddress);
        console2.log("Orchestrator receiver:", orchestratorReceiver);
        console2.log("Solver name:", solverName);
        console2.log(
            "Orchestrator fee type:", orchestratorFeeType == ISolverManager.FeeType.FIXED ? "FIXED" : "PERCENTAGE"
        );
        console2.log("Orchestrator fee value:", orchestratorFeeValue);
        console2.log("Solver fee type:", solverFeeType == ISolverManager.FeeType.FIXED ? "FIXED" : "PERCENTAGE");
        console2.log("Solver fee value:", solverFeeValue);

        /*//////////////////////////////////////////////////////////////
                          Check if Solver Already Exists
          //////////////////////////////////////////////////////////////*/

        try invoiceManager.getSolverData(executionAddress) returns (ISolverManager.Solver memory solverData) {
            if (bytes(solverData.name).length > 0) {
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

        invoiceManager.onboardSolver(
            executionAddress,
            feeAddress,
            orchestratorReceiver,
            solverName,
            orchestratorFeeType,
            orchestratorFeeValue,
            solverFeeType,
            solverFeeValue
        );

        console2.log("Successfully onboarded solver!");

        vm.stopBroadcast();
    }
}
