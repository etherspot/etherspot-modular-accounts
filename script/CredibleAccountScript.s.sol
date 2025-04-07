// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC7484} from "../src/interfaces/ercs/IERC7484.sol";
import {HookMultiPlexer} from "../src/modules/hooks/HookMultiPlexer.sol";
import {CredibleAccountValidator} from "../src/modules/validators/CredibleAccountValidator.sol";
import {CredibleAccountHook} from "../src/modules/hooks/CredibleAccountHook.sol";

contract CredibleAccountSetupScript is Script {
    bytes32 public immutable SALT = bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:salt"));
    address public constant DEPLOYER = 0x09FD4F6088f2025427AB1e89257A44747081Ed59;
    address public constant ERC7484_REGISTRY_ADDRESS = 0x000000000069E2a187AEFFb852bF3cCdC95151B2; // on Sepolia
    address public constant EXPECTED_MULTIPLEXER_ADDRESS = 0x0000000000000000000000000000000000000000;
    address public constant EXPECTED_VALIDATOR_ADDRESS = 0x0000000000000000000000000000000000000000;
    address public constant EXPECTED_HOOK_ADDRESS = 0x0000000000000000000000000000000000000000;

    function run() external {
        IERC7484 erc7484Registry = IERC7484(ERC7484_REGISTRY_ADDRESS);
        HookMultiPlexer hookMultiPlexer;
        CredibleAccountValidator credibleAccountValidator;
        CredibleAccountHook credibleAccountHook;
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        /*//////////////////////////////////////////////////////////////
                            Starting Deployment
        //////////////////////////////////////////////////////////////*/

        console2.log("Starting deployment sequence...");

        /*//////////////////////////////////////////////////////////////
                            Deploy HookMultiPlexer
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying HookMultiPlexer...");
        // if (EXPECTED_MULTIPLEXER_ADDRESS.code.length == 0) {
        hookMultiPlexer = new HookMultiPlexer{salt: SALT}();
        // if (address(hookMultiPlexer) != EXPECTED_MULTIPLEXER_ADDRESS) {
        //     revert("Unexpected HookMultiPlexer address!!!");
        // } else {
        console2.log("HookMultiPlexer deployed at address", address(hookMultiPlexer));
        //     }
        // } else {
        //     console2.log("HookMultiPlexer already deployed at address", EXPECTED_MULTIPLEXER_ADDRESS);
        // }

        /*//////////////////////////////////////////////////////////////
                      Deploy CredibleAccountValidator
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying CredibleAccountValidator...");
        // if (EXPECTED_VALIDATOR_ADDRESS.code.length == 0) {
        credibleAccountValidator = new CredibleAccountValidator{salt: SALT}(DEPLOYER, hookMultiPlexer);
        // if (address(credibleAccountValidator) != EXPECTED_VALIDATOR_ADDRESS) {
        //     revert("Unexpected CredibleAccountValidator address!!!");
        // } else {
        console2.log("CredibleAccountValidator deployed at address", address(credibleAccountValidator));
        //     }
        // } else {
        //     console2.log("CredibleAccountValidator already deployed at address", EXPECTED_VALIDATOR_ADDRESS);
        // }

        /*//////////////////////////////////////////////////////////////
                          Deploy CredibleAccountHook
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying CredibleAccountHook...");
        // if (EXPECTED_HOOK_ADDRESS.code.length == 0) {
        credibleAccountHook = new CredibleAccountHook{salt: SALT}(credibleAccountValidator);
        // if (address(credibleAccountHook) != EXPECTED_HOOK_ADDRESS) {
        //     revert("Unexpected CredibleAccountHook address!!!");
        // } else {
        console2.log("CredibleAccountHook deployed at address", address(credibleAccountHook));
        //     }
        // } else {
        //     console2.log("CredibleAccountHook already deployed at address", EXPECTED_HOOK_ADDRESS);
        // }

        /*//////////////////////////////////////////////////////////////
                  Initialization of CredibleAccountValidator
        //////////////////////////////////////////////////////////////*/

        console2.log("Initializing CredibleAccountValidator...");
        credibleAccountValidator.initialize(credibleAccountHook);
        console2.log(
            "CredibleAccountValidator initialized?",
            address(credibleAccountValidator.caHook()) == address(credibleAccountHook)
        );

        /*//////////////////////////////////////////////////////////////
                              Finishing Deployment
        //////////////////////////////////////////////////////////////*/
        console2.log("Finished deployment sequence!");

        vm.stopBroadcast();
    }
}
