// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IFactoryStaker} from "./IFactoryStaker.sol";

/// @title IModularEtherspotWalletFactory
/// @author @cryptonoyaiba | Etherspot
/// @notice Interface for the factory contract that deploys new Modular Etherspot Wallets
/// @dev Defines the core functionality for deterministic wallet creation using CREATE2
interface IModularEtherspotWalletFactory is IFactoryStaker {
    /// @notice Emitted when a new modular account is deployed
    /// @param account The address of the newly deployed account
    /// @param owner The initial owner of the account
    event ModularAccountDeployed(address indexed account, address indexed owner);

    /// @notice Returns the implementation address that all proxies will point to
    /// @return The address of the implementation contract
    function implementation() external view returns (address);

    /// @notice Creates a new modular account or returns an existing one
    /// @dev Uses CREATE2 to deploy a proxy pointing to the implementation
    /// @param _owner The initial owner of the account
    /// @param _salt A unique value to determine the account address
    /// @param _initCode The initialization data for the account
    /// @return The address of the deployed or existing account
    function createAccount(address _owner, bytes32 _salt, bytes calldata _initCode)
        external
        payable
        returns (address);

    /// @notice Computes the address of an account before it is deployed
    /// @dev Uses the CREATE2 address computation formula
    /// @param _salt A unique value to determine the account address
    /// @param _initcode The initialization data for the account
    /// @return The computed address of the account
    function getAddress(bytes32 _salt, bytes calldata _initcode) external view returns (address);
}
