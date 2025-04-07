// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {IStakeManager} from "ERC4337/interfaces/IStakeManager.sol";
import {Bootstrap} from "../src/utils/Bootstrap.sol";
import {ModularEtherspotWallet} from "../src/wallet/ModularEtherspotWallet.sol";
import {ModularEtherspotWalletFactory} from "../src/factory/ModularEtherspotWalletFactory.sol";
import {ECDSAValidator} from "../src/modules/validators/ECDSAValidator.sol";
import {MultipleOwnerECDSAValidator} from "../src/modules/validators/MultipleOwnerECDSAValidator.sol";
import {GuardianRecoveryValidator} from "../src/modules/validators/GuardianRecoveryValidator.sol";
import {CredibleAccountValidator} from "../src/modules/validators/CredibleAccountValidator.sol";
import {ResourceLockValidator} from "../src/modules/validators/ResourceLockValidator.sol";
import {HookMultiPlexer} from "../src/modules/hooks/HookMultiPlexer.sol";
import {CredibleAccountHook} from "../src/modules/hooks/CredibleAccountHook.sol";

/// @author Etherspot.
/// @title  DeployAllAndSetupScript.
/// @dev Deployment script for all modular contracts. Deploys:
/// ModularEtherspotWallet,
/// ModularEtherspotWalletFactory,
/// Bootstrap,
/// ECDSAValidator,
/// MultipleOwnerECDSAValidator,
/// GuardianRecoveryValidator,
/// CredibleAccountValidator,
/// ResourceLockValidator,
/// HookMultiPlexer,
/// CredibleAccountHook
/// Stakes factory contract with EntryPoint.

/// To run script: forge script script/DeployAllAndSetup.s.sol:DeployAllAndSetupScript --broadcast -vvvv --rpc-url <chain name>
/// If error: Failed to get EIP-1559 fees: add --legacy tag
/// For certain chains (currently only mantle and mantle_sepolia): add --skip-simulation tag

contract DeployAllAndSetupScript is Script {
    bytes32 public immutable SALT = bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:salt"));
    address public constant ENTRY_POINT_07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    /*//////////////////////////////////////////////////////////////
                  Replace These Values With Your Own
    //////////////////////////////////////////////////////////////*/
    address public constant DEPLOYER = 0x09FD4F6088f2025427AB1e89257A44747081Ed59;
    address public constant EXPECTED_IMPLEMENTATION = 0x0000000000000000000000000000000000000000;
    address public constant EXPECTED_FACTORY = 0x0000000000000000000000000000000000000000;
    address public constant EXPECTED_BOOTSTRAP = 0x0000000000000000000000000000000000000000;
    address public constant EXPECTED_ECDSA_VALIDATOR = 0x0000000000000000000000000000000000000000;
    address public constant EXPECTED_MULTIPLE_OWNER_ECDSA_VALIDATOR = 0x0000000000000000000000000000000000000000;
    address public constant EXPECTED_GUARDIAN_RECOVERY_VALIDATOR = 0x0000000000000000000000000000000000000000;
    address public constant EXPECTED_RESOURCE_LOCK_VALIDATOR = 0x0000000000000000000000000000000000000000;
    address public constant EXPECTED_HOOK_MULTIPLEXER_ADDRESS = 0x0000000000000000000000000000000000000000;
    address public constant EXPECTED_CA_VALIDATOR_ADDRESS = 0x0000000000000000000000000000000000000000;
    address public constant EXPECTED_CA_HOOK_ADDRESS = 0x0000000000000000000000000000000000000000;

    uint256 public constant FACTORY_STAKE = 1e16;

    function run() external {
        IEntryPoint entryPoint = IEntryPoint(ENTRY_POINT_07);
        ModularEtherspotWallet implementation;
        ModularEtherspotWalletFactory factory;
        Bootstrap bootstrap;
        ECDSAValidator ecdsaValidator;
        MultipleOwnerECDSAValidator multipleOwnerECDSAValidator;
        GuardianRecoveryValidator guardianRecoveryValidator;
        ResourceLockValidator resourceLockValidator;
        CredibleAccountValidator credibleAccountValidator;
        HookMultiPlexer hookMultiPlexer;
        CredibleAccountHook credibleAccountHook;
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        /*//////////////////////////////////////////////////////////////
                            Starting Deployment
        //////////////////////////////////////////////////////////////*/
        console2.log("Starting deployment sequence...");

        /*//////////////////////////////////////////////////////////////
                        Deploy ModularEtherspotWallet
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying ModularEtherspotWallet implementation...");
        // if (EXPECTED_IMPLEMENTATION.code.length == 0) {
        implementation = new ModularEtherspotWallet(entryPoint);
        // if (address(implementation) != EXPECTED_IMPLEMENTATION) {
        //     revert("Unexpected wallet implementation address!!!");
        // } else {
        console2.log("Wallet implementation deployed at address", address(implementation));
        //     }
        // } else {
        //     console2.log("Wallet implementation already deployed at address", EXPECTED_IMPLEMENTATION);
        // }

        /*//////////////////////////////////////////////////////////////
                      Deploy ModularEtherspotWalletFactory
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying ModularEtherspotWalletFactory...");
        // if (EXPECTED_FACTORY.code.length == 0) {
        factory = new ModularEtherspotWalletFactory(EXPECTED_IMPLEMENTATION, DEPLOYER);
        // if (address(factory) != EXPECTED_FACTORY) {
        //     revert("Unexpected wallet factory address!!!");
        // } else {
        console2.log("Wallet factory deployed at address", address(factory));
        //     }
        // } else {
        //     console2.log("Wallet factory already deployed at address", EXPECTED_FACTORY);
        // }

        /*//////////////////////////////////////////////////////////////
              Stake ModularEtherspotWalletFactory With EntryPoint
        //////////////////////////////////////////////////////////////*/
        console2.log("Staking factory contract with EntryPoint...");
        factory.addStake{value: FACTORY_STAKE}(address(entryPoint), 86400);
        IStakeManager.DepositInfo memory info = entryPoint.getDepositInfo(EXPECTED_FACTORY);
        console2.log("Staked amount:", info.stake);
        console2.log("Factory staked!");

        /*//////////////////////////////////////////////////////////////
                              Deploy Bootstrap
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying Bootstrap...");
        // if (EXPECTED_BOOTSTRAP.code.length == 0) {
        bootstrap = new Bootstrap();
        // if (address(bootstrap) != EXPECTED_BOOTSTRAP) {
        //     revert("Unexpected bootstrap address!!!");
        // } else {
        console2.log("Bootstrap deployed at address", address(bootstrap));
        //     }
        // } else {
        //     console2.log("Bootstrap already deployed at address", EXPECTED_BOOTSTRAP);
        // }

        /*//////////////////////////////////////////////////////////////
                            Deploy ECDSAValidator
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying ECDSAValidator...");
        // if (EXPECTED_ECDSA_VALIDATOR.code.length == 0) {
        ecdsaValidator = new ECDSAValidator();
        // if (address(ecdsaValidator) != EXPECTED_ECDSA_VALIDATOR) {
        //     revert("Unexpected ECDSAValidator address!!!");
        // } else {
        console2.log("ECDSAValidator deployed at address", address(ecdsaValidator));
        //     }
        // } else {
        //     console2.log("ECDSAValidator already deployed at address", EXPECTED_ECDSA_VALIDATOR);
        // }

        /*//////////////////////////////////////////////////////////////
                     Deploy MultipleOwnerECDSAValidator
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying MultipleOwnerECDSAValidator...");
        // if (EXPECTED_MULTIPLE_OWNER_ECDSA_VALIDATOR.code.length == 0) {
        multipleOwnerECDSAValidator = new MultipleOwnerECDSAValidator();
        // if (address(multipleOwnerECDSAValidator) != EXPECTED_MULTIPLE_OWNER_ECDSA_VALIDATOR) {
        //     revert("Unexpected MultipleOwnerECDSAValidator address!!!");
        // } else {
        console2.log("MultipleOwnerECDSAValidator deployed at address", address(multipleOwnerECDSAValidator));
        //     }
        // } else {
        //     console2.log(
        //         "MultipleOwnerECDSAValidator already deployed at address", EXPECTED_MULTIPLE_OWNER_ECDSA_VALIDATOR
        //     );
        // }

        /*//////////////////////////////////////////////////////////////
                        Deploy GuardianRecoveryValidator
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying GuardianRecoveryValidator...");
        // if (EXPECTED_GUARDIAN_RECOVERY_VALIDATOR.code.length == 0) {
        guardianRecoveryValidator = new GuardianRecoveryValidator();
        // if (address(guardianRecoveryValidator) != EXPECTED_GUARDIAN_RECOVERY_VALIDATOR) {
        //     revert("Unexpected GuardianRecoveryValidator address!!!");
        // } else {
        console2.log("GuardianRecoveryValidator deployed at address", address(guardianRecoveryValidator));
        //     }
        // } else {
        //     console2.log("GuardianRecoveryValidator already deployed at address", EXPECTED_GUARDIAN_RECOVERY_VALIDATOR);
        // }

        /*//////////////////////////////////////////////////////////////
                        Deploy ResourceLockValidator
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying ResourceLockValidator...");
        // if (EXPECTED_RESOURCE_LOCK_VALIDATOR.code.length == 0) {
        resourceLockValidator = new ResourceLockValidator();
        // if (address(resourceLockValidator) != EXPECTED_RESOURCE_LOCK_VALIDATOR) {
        //     revert("Unexpected ResourceLockValidator address!!!");
        // } else {
        console2.log("ResourceLockValidator deployed at address", address(resourceLockValidator));
        //     }
        // } else {
        //     console2.log("ResourceLockValidator already deployed at address", EXPECTED_RESOURCE_LOCK_VALIDATOR);
        // }

        /*//////////////////////////////////////////////////////////////
                            Deploy HookMultiPlexer
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying HookMultiPlexer...");
        // if (EXPECTED_HOOK_MULTIPLEXER_ADDRESS.code.length == 0) {
        hookMultiPlexer = new HookMultiPlexer();
        // if (address(hookMultiPlexer) != EXPECTED_HOOK_MULTIPLEXER_ADDRESS) {
        //     revert("Unexpected HookMultiPlexer address!!!");
        // } else {
        console2.log("HookMultiPlexer deployed at address", address(hookMultiPlexer));
        //     }
        // } else {
        //     console2.log("HookMultiPlexer already deployed at address", EXPECTED_HOOK_MULTIPLEXER_ADDRESS);
        // }

        /*//////////////////////////////////////////////////////////////
                      Deploy CredibleAccountValidator
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying CredibleAccountValidator...");
        // if (EXPECTED_CA_VALIDATOR_ADDRESS.code.length == 0) {
        credibleAccountValidator = new CredibleAccountValidator(DEPLOYER, hookMultiPlexer);
        // if (address(credibleAccountValidator) != EXPECTED_CA_VALIDATOR_ADDRESS) {
        //     revert("Unexpected CredibleAccountValidator address!!!");
        // } else {
        console2.log("CredibleAccountValidator deployed at address", address(credibleAccountValidator));
        //     }
        // } else {
        //     console2.log("CredibleAccountValidator already deployed at address", EXPECTED_CA_VALIDATOR_ADDRESS);
        // }

        /*//////////////////////////////////////////////////////////////
                          Deploy CredibleAccountHook
        //////////////////////////////////////////////////////////////*/

        console2.log("Deploying CredibleAccountHook...");
        // if (EXPECTED_CA_HOOK_ADDRESS.code.length == 0) {
        credibleAccountHook = new CredibleAccountHook(credibleAccountValidator);
        // if (address(credibleAccountHook) != EXPECTED_CA_HOOK_ADDRESS) {
        //     revert("Unexpected CredibleAccountHook address!!!");
        // } else {
        console2.log("CredibleAccountHook deployed at address", address(credibleAccountHook));
        //     }
        // } else {
        //     console2.log("CredibleAccountHook already deployed at address", EXPECTED_CA_HOOK_ADDRESS);
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
