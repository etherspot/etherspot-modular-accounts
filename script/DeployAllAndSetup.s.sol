// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {IStakeManager} from "ERC4337/interfaces/IStakeManager.sol";
import {Bootstrap} from "ERC7579/utils/Bootstrap.sol";
import {ModularEtherspotWallet} from "../src/wallet/ModularEtherspotWallet.sol";
import {ModularEtherspotWalletFactory} from "../src/wallet/ModularEtherspotWalletFactory.sol";
import {MultipleOwnerECDSAValidator} from "../src/modules/validators/MultipleOwnerECDSAValidator.sol";
import {HookMultiPlexer} from "../src/modules/hooks/HookMultiPlexer.sol";

/**
 * @author Etherspot.
 * @title  DeployAllAndSetupScript.
 * @dev Deployment script for all modular contracts. Deploys:
 * ModularEtherspotWallet implementation, ModularEtherspotWalletFactory, Bootstrap, MultipleOwnerECDSAValidator, HookMultiPlexer.
 * Stakes factory contract with EntryPoint.
 *
 * To run script: forge script script/DeployAllAndSetup.s.sol:DeployAllAndSetupScript --broadcast -vvvv --rpc-url <chain name>
 * If error: Failed to get EIP-1559 fees: add --legacy tag
 * For certain chains (currently only mantle and mantle_sepolia): add --skip-simulation tag
 */
contract DeployAllAndSetupScript is Script {
    bytes32 public immutable SALT = bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:salt"));
    address public constant ENTRY_POINT_07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    /*//////////////////////////////////////////////////////////////
                  Replace These Values With Your Own
    //////////////////////////////////////////////////////////////*/
    address public constant DEPLOYER = 0x09FD4F6088f2025427AB1e89257A44747081Ed59;
    address public constant EXPECTED_IMPLEMENTATION = 0x62Fdd1382b0182F2CC40bAdEa6E5DE0CCb2d6488;
    address public constant EXPECTED_FACTORY = 0x38CC0EDdD3a944CA17981e0A19470d2298B8d43a;
    address public constant EXPECTED_BOOTSTRAP = 0xCF2808eA7d131d96E5C73Eb0eCD8Dc84D33905C7;
    address public constant EXPECTED_MULTIPLE_OWNER_ECDSA_VALIDATOR = 0x0eA25BF9F313344d422B513e1af679484338518E;
    address public constant EXPECTED_HMP = 0xDcA918dd23456d321282DF9507F6C09A50522136;
    uint256 public constant FACTORY_STAKE = 1e16;
    uint256 public constant ROOTSTOCK_FACTORY_STAKE = 15000000000000;

    function run() external {
        IEntryPoint entryPoint = IEntryPoint(ENTRY_POINT_07);
        ModularEtherspotWallet implementation;
        ModularEtherspotWalletFactory factory;
        Bootstrap bootstrap;
        MultipleOwnerECDSAValidator multipleOwnerECDSAValidator;
        HookMultiPlexer hookMultiPlexer;
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console2.log("Starting deployment sequence...");

        /*//////////////////////////////////////////////////////////////
                        Deploy ModularEtherspotWallet
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying ModularEtherspotWallet implementation...");
        if (EXPECTED_IMPLEMENTATION.code.length == 0) {
            implementation = new ModularEtherspotWallet{salt: SALT}();
            if (address(implementation) != EXPECTED_IMPLEMENTATION) {
                revert("Unexpected wallet implementation address!!!");
            } else {
                console2.log("Wallet implementation deployed at address", address(implementation));
            }
        } else {
            console2.log("Wallet implementation already deployed at address", EXPECTED_IMPLEMENTATION);
        }

        /*//////////////////////////////////////////////////////////////
                      Deploy ModularEtherspotWalletFactory
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying ModularEtherspotWalletFactory...");
        if (EXPECTED_FACTORY.code.length == 0) {
            factory = new ModularEtherspotWalletFactory{salt: SALT}(EXPECTED_IMPLEMENTATION, DEPLOYER);
            if (address(factory) != EXPECTED_FACTORY) {
                revert("Unexpected wallet factory address!!!");
            } else {
                console2.log("Wallet factory deployed at address", address(factory));
            }
        } else {
            console2.log("Wallet factory already deployed at address", EXPECTED_FACTORY);
        }

        /*//////////////////////////////////////////////////////////////
                              Deploy Bootstrap
        //////////////////////////////////////////////////////////////*/
        if (EXPECTED_BOOTSTRAP.code.length == 0) {
            bootstrap = new Bootstrap{salt: SALT}();
            if (address(bootstrap) != EXPECTED_BOOTSTRAP) {
                revert("Unexpected bootstrap address!!!");
            } else {
                console2.log("Bootstrap deployed at address", address(bootstrap));
            }
        } else {
            console2.log("Bootstrap already deployed at address", EXPECTED_BOOTSTRAP);
        }

        /*//////////////////////////////////////////////////////////////
                     Deploy MultipleOwnerECDSAValidator
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying MultipleOwnerECDSAValidator...");
        if (EXPECTED_MULTIPLE_OWNER_ECDSA_VALIDATOR.code.length == 0) {
            multipleOwnerECDSAValidator = new MultipleOwnerECDSAValidator{salt: SALT}();
            if (address(multipleOwnerECDSAValidator) != EXPECTED_MULTIPLE_OWNER_ECDSA_VALIDATOR) {
                revert("Unexpected MultipleOwnerECDSAValidator address!!!");
            } else {
                console2.log("MultipleOwnerECDSAValidator deployed at address", address(multipleOwnerECDSAValidator));
            }
        } else {
            console2.log(
                "MultipleOwnerECDSAValidator already deployed at address", EXPECTED_MULTIPLE_OWNER_ECDSA_VALIDATOR
            );
        }

        /*//////////////////////////////////////////////////////////////
                             Deploy HookMultiPlexer
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying HookMultiPlexer implementation...");
        if (EXPECTED_HMP.code.length == 0) {
            hookMultiPlexer = new HookMultiPlexer{salt: SALT}();
            if (address(hookMultiPlexer) != EXPECTED_HMP) {
                revert("Unexpected HookMultiPlexer address!!!");
            } else {
                console2.log("HookMultiPlexer deployed at address", address(hookMultiPlexer));
            }
        } else {
            console2.log("HookMultiPlexer already deployed at address", EXPECTED_HMP);
        }

        /*//////////////////////////////////////////////////////////////
              Stake ModularEtherspotWalletFactory With EntryPoint
        //////////////////////////////////////////////////////////////*/
        console2.log("Staking factory contract with EntryPoint...");
        factory.addStake{value: FACTORY_STAKE}(address(entryPoint), 86400);
        IStakeManager.DepositInfo memory info = entryPoint.getDepositInfo(EXPECTED_FACTORY);
        console2.log("Staked amount:", info.stake);
        console2.log("Factory staked!");

        /*//////////////////////////////////////////////////////////////
                              Finishing Deployment
        //////////////////////////////////////////////////////////////*/
        console2.log("Finished deployment sequence!");

        vm.stopBroadcast();
    }
}
