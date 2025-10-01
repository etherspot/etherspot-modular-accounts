// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {HookMultiPlexer} from "../src/modules/hooks/HookMultiPlexer.sol";
import {CredibleAccountModule} from "../src/modules/validators/CredibleAccountModule.sol";
import {ResourceLockValidator} from "../src/modules/validators/ResourceLockValidator.sol";

contract CredibleAccountSetupScript is Script {
    bytes32 public immutable SALT = bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:salt"));
    bytes32 public immutable TEST_SALT = bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:test_salt"));
    address public constant DEPLOYER = 0x09FD4F6088f2025427AB1e89257A44747081Ed59;
    address public constant EXPECTED_HOOK_MULTIPLEXER_ADDRESS = 0xe629A99Fe2fAD23B1dF6Aa680BA6995cfDA885a3;
    address public constant EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS = 0xc34D2E2D9Fa0aDbCd801F13563A1423858751A12;
    address public constant EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS = 0x08B42e03c1beC06caa3811F503EBF2D58CaccE94;

    function run() external {
        HookMultiPlexer hookMultiPlexer;
        CredibleAccountModule credibleAccountModule;
        ResourceLockValidator resourceLockValidator;
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
        if (EXPECTED_HOOK_MULTIPLEXER_ADDRESS.code.length == 0) {
            hookMultiPlexer = new HookMultiPlexer{salt: SALT}();
            if (address(hookMultiPlexer) != EXPECTED_HOOK_MULTIPLEXER_ADDRESS) {
                revert("Unexpected HookMultiPlexer address!!!");
            } else {
                console2.log("HookMultiPlexer deployed at address", address(hookMultiPlexer));
            }
        } else {
            console2.log("HookMultiPlexer already deployed at address", EXPECTED_HOOK_MULTIPLEXER_ADDRESS);
        }

        /*//////////////////////////////////////////////////////////////
                      Deploy CredibleAccountModule
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying CredibleAccountModule...");
        if (EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS.code.length == 0) {
            credibleAccountModule = new CredibleAccountModule{salt: SALT}(DEPLOYER, address(hookMultiPlexer));
            if (address(credibleAccountModule) != EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS) {
                revert("Unexpected CredibleAccountModule address!!!");
            } else {
                console2.log("CredibleAccountModule deployed at address", address(credibleAccountModule));
            }
        } else {
            console2.log("CredibleAccountModule already deployed at address", EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS);
        }

        /*//////////////////////////////////////////////////////////////
                        Deploy ResourceLockValidator
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying ResourceLockValidator...");
        if (EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS.code.length == 0) {
            resourceLockValidator = new ResourceLockValidator{salt: SALT}(DEPLOYER);
            if (address(resourceLockValidator) != EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS) {
                revert("Unexpected ResourceLockValidator address!!!");
            } else {
                console2.log("ResourceLockValidator deployed at address", address(resourceLockValidator));
            }
        } else {
            console2.log("ResourceLockValidator already deployed at address", EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS);
        }

        /*//////////////////////////////////////////////////////////////
                CredibleAccountModule/ResourceLockValidator Setup
        //////////////////////////////////////////////////////////////*/

        console2.log("Setting up CredibleAccountModule and ResourceLockValidator...");
        address camSetup = credibleAccountModule.resourceLockValidator();
        address rlvSetup = resourceLockValidator.credibleAccountModule();
        if (camSetup == address(0)) {
            credibleAccountModule.setResourceLockValidator(address(resourceLockValidator));
        } else {
            console2.log("The CredibleAccountModule has already been setup");
        }
        if (rlvSetup == address(0)) {
            resourceLockValidator.setCredibleAccountModule(address(credibleAccountModule));
        } else {
            console2.log("The ResourceLockValidator has already been setup");
        }
        console2.log("CredibleAccountModule and ResourceLockValidator setup complete!");

        /*//////////////////////////////////////////////////////////////
                              Finishing Deployment
        //////////////////////////////////////////////////////////////*/
        console2.log("Finished deployment sequence!");

        vm.stopBroadcast();
    }
}
