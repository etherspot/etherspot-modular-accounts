// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {IStakeManager} from "ERC4337/interfaces/IStakeManager.sol";
import {ModularEtherspotWalletFactory} from "../src/wallet/ModularEtherspotWalletFactory.sol";

/**
 * @author Etherspot.
 * @title  WithdrawFactoryStakeScript.
 * @dev Withdraws stake from EntryPoint for ModularEtherspotWalletFactory.
 */

contract UnlockFactoryStakeScript is Script {
    address payable constant DEPLOYER =
        payable(0x09FD4F6088f2025427AB1e89257A44747081Ed59);
    address constant ENTRY_POINT_07 =
        0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    address payable constant FACTORY =
        payable(0x2A40091f044e48DEB5C0FCbc442E443F3341B451);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("Unlocking stake from old factory...");
        ModularEtherspotWalletFactory factory = ModularEtherspotWalletFactory(
            FACTORY
        );
        IEntryPoint entryPoint = IEntryPoint(ENTRY_POINT_07);

        factory.unlockStake(ENTRY_POINT_07);

        IStakeManager.DepositInfo memory info = entryPoint.getDepositInfo(
            address(factory)
        );

        console2.log("Staked amount:", info.stake);
        console2.log("Unlocked? (should not be 0):", info.withdrawTime);

        vm.stopBroadcast();
    }
}
