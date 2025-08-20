    // SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {InvoiceManager} from "../../src/utils/InvoiceManager.sol";
import {EXPECTED_INVOICE_MANAGER_ADDRESS} from "./utils/PulseConstants.sol";

contract IM_RoleManagement is Script {
    InvoiceManager public invoiceManager;

    // Leave array empty if not required
    // Addresses to grant roles to
    address[] public newSettlers;
    address[] public newFeeManagers;
    address[] public newSolverManagers;
    // Addresses to revoke roles from
    address[] public settlersToRevoke;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        invoiceManager = InvoiceManager(EXPECTED_INVOICE_MANAGER_ADDRESS);

        console2.log("Starting InvoiceManager role management operations...");

        /*//////////////////////////////////////////////////////////////
                                Grant Settler Roles
          //////////////////////////////////////////////////////////////*/

        console2.log("Granting SETTLER_ROLE to new addresses...");
        if (newSettlers.length > 0) {
            for (uint256 i; i < newSettlers.length; ++i) {
                address settler = newSettlers[i];
                console2.log("Granting SETTLER_ROLE to:", settler);
                invoiceManager.grantSettlerRole(settler);
            }
        }
        /*//////////////////////////////////////////////////////////////
                              Grant Fee Manager Roles
          //////////////////////////////////////////////////////////////*/

        console2.log("Granting FEE_MANAGER_ROLE to new addresses...");
        if (newFeeManagers.length > 0) {
            for (uint256 i; i < newFeeManagers.length; ++i) {
                address feeManager = newFeeManagers[i];
                console2.log("Granting FEE_MANAGER_ROLE to:", feeManager);
                invoiceManager.grantFeeManagerRole(feeManager);
            }
        }

        /*//////////////////////////////////////////////////////////////
                            Grant Solver Manager Roles
          //////////////////////////////////////////////////////////////*/

        console2.log("Granting SOLVER_MANAGER_ROLE to new addresses...");
        if (newSolverManagers.length > 0) {
            for (uint256 i; i < newSolverManagers.length; ++i) {
                address solverManager = newSolverManagers[i];
                console2.log("Granting SOLVER_MANAGER_ROLE to:", solverManager);
                invoiceManager.grantSolverManagerRole(solverManager);
            }
        }

        /*//////////////////////////////////////////////////////////////
                               Revoke Settler Roles
          //////////////////////////////////////////////////////////////*/

        console2.log("Revoking SETTLER_ROLE from specified addresses...");
        if (settlersToRevoke.length > 0) {
            for (uint256 i; i < settlersToRevoke.length; ++i) {
                address settler = settlersToRevoke[i];
                console2.log("Revoking SETTLER_ROLE from:", settler);
                invoiceManager.revokeSettlerRole(settler);
            }
        }

        console2.log("InvoiceManager role management operations completed!");

        vm.stopBroadcast();
    }
}
