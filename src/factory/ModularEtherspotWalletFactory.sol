// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IModularEtherspotWalletFactory} from "../interfaces/factory/IModularEtherspotWalletFactory.sol";
import {IModularEtherspotWallet} from "../interfaces/wallet/IModularEtherspotWallet.sol";
import {ModularEtherspotWalletProxy} from "../utils/ModularEtherspotWalletProxy.sol";
import {FactoryStaker} from "./FactoryStaker.sol";

/// @title ModularEtherspotWalletFactory
/// @author @cryptonoyaiba | Etherspot
/// @notice Factory contract for deploying new Modular Etherspot Wallets
/// @dev Uses CREATE2 for deterministic address generation and inherits staking functionality
contract ModularEtherspotWalletFactory is IModularEtherspotWalletFactory, FactoryStaker {
    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The implementation address that all proxies will point to
    address public immutable implementation;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the factory with an implementation address and owner
    /// @param _implementation The address of the implementation contract
    /// @param _owner The address that will own this factory
    constructor(address _implementation, address _owner) FactoryStaker(_owner) {
        implementation = _implementation;
    }

    /*//////////////////////////////////////////////////////////////
                           PUBLIC/EXTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new modular account or returns an existing one
    /// @dev Uses CREATE2 to deploy a proxy pointing to the implementation
    /// @param _owner The initial owner of the account
    /// @param _salt A unique value to determine the account address
    /// @param _initCode The initialization data for the account
    /// @return The address of the deployed or existing account
    function createAccount(address _owner, bytes32 _salt, bytes calldata _initCode)
        public
        payable
        virtual
        returns (address)
    {
        address predictedAddress = getAddress(_salt, _initCode);
        if (predictedAddress.code.length > 0) {
            return predictedAddress; // Return existing contract instead of failing
        }
        address account = address(
            new ModularEtherspotWalletProxy{salt: _salt, value: msg.value}(
                implementation, abi.encodeCall(IModularEtherspotWallet.initializeAccount, _initCode)
            )
        );
        emit ModularAccountDeployed(account, _owner);
        return account;
    }

    /// @notice Computes the address of an account before it is deployed
    /// @dev Uses the CREATE2 address computation formula
    /// @param _salt A unique value to determine the account address
    /// @param _initcode The initialization data for the account
    /// @return The computed address of the account
    function getAddress(bytes32 _salt, bytes calldata _initcode) public view virtual returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                _salt,
                keccak256(
                    abi.encodePacked(
                        type(ModularEtherspotWalletProxy).creationCode,
                        abi.encode(implementation, abi.encodeCall(IModularEtherspotWallet.initializeAccount, _initcode))
                    )
                )
            )
        );
        return address(uint160(uint256(hash)));
    }
}
