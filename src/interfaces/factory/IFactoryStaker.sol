// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @title IFactoryStaker
/// @author @cryptonoyaiba | Etherspot
/// @notice Interface for managing staking operations with ERC-4337 EntryPoint
/// @dev Defines functions for adding, unlocking, and withdrawing stakes
interface IFactoryStaker {
    /// @notice Thrown when an invalid EntryPoint address is provided
    error FactoryStaker_InvalidEPAddress();

    /// @notice Adds stake to the EntryPoint contract
    /// @dev Only callable by the owner
    /// @param _epAddress The address of the EntryPoint contract
    /// @param _unstakeDelaySec The delay in seconds before the stake can be withdrawn
    /// @custom:security The value sent with this transaction will be staked
    function addStake(address _epAddress, uint32 _unstakeDelaySec) external payable;

    /// @notice Initiates the unlocking process for staked funds
    /// @dev Only callable by the owner
    /// @param _epAddress The address of the EntryPoint contract
    /// @custom:security This starts the unstake delay period
    function unlockStake(address _epAddress) external;

    /// @notice Withdraws staked funds after the delay period
    /// @dev Only callable by the owner after unlockStake has been called and the delay has passed
    /// @param _epAddress The address of the EntryPoint contract
    /// @param _withdrawTo The address to send the withdrawn stake to
    function withdrawStake(address _epAddress, address payable _withdrawTo) external;
}
