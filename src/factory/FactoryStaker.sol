// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {IFactoryStaker} from "../interfaces/factory/IFactoryStaker.sol";

/// @title FactoryStaker
/// @author @cryptonoyaiba | Etherspot
/// @notice Manages staking operations for wallet factories with ERC-4337 EntryPoint
/// @dev Allows the owner to add, unlock, and withdraw stakes from the EntryPoint
contract FactoryStaker is IFactoryStaker, Ownable {
    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with an owner
    /// @param _owner The address that will own this contract
    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    /*//////////////////////////////////////////////////////////////
                           PUBLIC/EXTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds stake to the EntryPoint contract
    /// @dev Only callable by the owner
    /// @param _epAddress The address of the EntryPoint contract
    /// @param _unstakeDelaySec The delay in seconds before the stake can be withdrawn
    /// @custom:security The value sent with this transaction will be staked
    function addStake(address _epAddress, uint32 _unstakeDelaySec) external payable onlyOwner {
        if (_epAddress == address(0)) revert FactoryStaker_InvalidEPAddress();
        IEntryPoint(_epAddress).addStake{value: msg.value}(_unstakeDelaySec);
    }

    /// @notice Initiates the unlocking process for staked funds
    /// @dev Only callable by the owner
    /// @param _epAddress The address of the EntryPoint contract
    /// @custom:security This starts the unstake delay period
    function unlockStake(address _epAddress) external onlyOwner {
        if (_epAddress == address(0)) revert FactoryStaker_InvalidEPAddress();
        IEntryPoint(_epAddress).unlockStake();
    }

    /// @notice Withdraws staked funds after the delay period
    /// @dev Only callable by the owner after unlockStake has been called and the delay has passed
    /// @param _epAddress The address of the EntryPoint contract
    /// @param _withdrawTo The address to send the withdrawn stake to
    function withdrawStake(address _epAddress, address payable _withdrawTo) external onlyOwner {
        if (_epAddress == address(0)) revert FactoryStaker_InvalidEPAddress();
        IEntryPoint(_epAddress).withdrawStake(_withdrawTo);
    }
}
