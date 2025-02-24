// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {IStakeManager} from "ERC4337/interfaces/IStakeManager.sol";
import {ModularEtherspotWallet} from "../src/wallet/ModularEtherspotWallet.sol";
import {ModularEtherspotWalletFactory} from "../src/wallet/ModularEtherspotWalletFactory.sol";
import {Bootstrap} from "../src/erc7579-ref-impl/utils/Bootstrap.sol";
import {MultipleOwnerECDSAValidator} from "../src/modules/validators/MultipleOwnerECDSAValidator.sol";

/**
 * @author Etherspot.
 * @title  NonDeterministicDeployAllAndSetupScript.
 * @dev Non-deterministic deployment script for all modular contracts. Deploys:
 * ModularEtherspotWallet implementation, ModularEtherspotWalletFactory, Bootstrap and MultipleOwnerECDSAValidator.
 * Stakes factory contract with EntryPoint.
 *
 * To run script: forge script script/NonDeterministicDeployAllAndSetup.s.sol:NonDeterministicDeployAllAndSetupScript --broadcast -vvvv --rpc-url <chain name>
 * If error: Failed to get EIP-1559 fees: add --legacy tag
 * For certain chains (currently only mantle and mantle_sepolia): add --skip-simulation tag
 */
contract NonDeterministicDeployAllAndSetupScript is Script {
    address public constant ENTRY_POINT_07 = 0xe1078568F094308749AE9833ba8160b9E8bd909f;

    /*//////////////////////////////////////////////////////////////
                  Replace These Values With Your Own
    //////////////////////////////////////////////////////////////*/
    address public constant DEPLOYER = 0x09FD4F6088f2025427AB1e89257A44747081Ed59;
    uint256 public constant FACTORY_STAKE = 1e16;

    function run() external {
        IEntryPoint entryPoint = IEntryPoint(ENTRY_POINT_07);
        ModularEtherspotWallet implementation;
        ModularEtherspotWalletFactory factory;
        Bootstrap bootstrap;
        MultipleOwnerECDSAValidator multipleOwnerECDSAValidator;
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console2.log("Starting non-deterministic deployment sequence...");

        /*//////////////////////////////////////////////////////////////
                        Deploy ModularEtherspotWallet
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying ModularEtherspotWallet implementation...");
        implementation = new ModularEtherspotWallet();
        console2.log("Wallet implementation deployed at address", address(implementation));

        /*//////////////////////////////////////////////////////////////
                      Deploy ModularEtherspotWalletFactory
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying ModularEtherspotWalletFactory...");
        factory = new ModularEtherspotWalletFactory(address(implementation), DEPLOYER);
        console2.log("Wallet factory deployed at address", address(factory));

        /*//////////////////////////////////////////////////////////////
                              Deploy Bootstrap
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying Bootstrap...");
        bootstrap = new Bootstrap();
        console2.log("Bootstrap deployed at address", address(bootstrap));

        /*//////////////////////////////////////////////////////////////
                     Deploy MultipleOwnerECDSAValidator
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying MultipleOwnerECDSAValidator...");
        multipleOwnerECDSAValidator = new MultipleOwnerECDSAValidator();
        console2.log("MultipleOwnerECDSAValidator deployed at address", address(multipleOwnerECDSAValidator));

        /*//////////////////////////////////////////////////////////////
              Stake ModularEtherspotWalletFactory With EntryPoint
        //////////////////////////////////////////////////////////////*/
        console2.log("Staking factory contract with EntryPoint...");
        factory.addStake{value: FACTORY_STAKE}(address(entryPoint), 86400);
        IStakeManager.DepositInfo memory info = entryPoint.getDepositInfo(address(factory));
        console2.log("Staked amount:", info.stake);
        console2.log("Factory staked!");

        /*//////////////////////////////////////////////////////////////
                              Finishing Deployment
        //////////////////////////////////////////////////////////////*/
        console2.log("Finished deployment sequence!");

        vm.stopBroadcast();
    }
}
