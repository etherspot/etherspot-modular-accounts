// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Initializable} from "../libraries/Initializable.sol";

/// @title ModularEtherspotWalletProxy
/// @author @cryptonoyaiba | Etherspot
/// @notice Proxy contract for Etherspot's modular smart contract wallet implementation
/// @dev Implements the ERC-1967 proxy pattern with initialization protection
contract ModularEtherspotWalletProxy is Proxy {
    /// @notice Constructs a new proxy instance pointing to the implementation
    /// @dev Sets the implementation address and calls the initialization function
    /// @param _impl The address of the implementation contract
    /// @param _data The initialization data to be passed to the implementation
    constructor(address _impl, bytes memory _data) payable {
        Initializable._setInitializable();
        ERC1967Utils.upgradeToAndCall(_impl, _data);
    }

    /// @notice Returns the current implementation address
    /// @dev Overrides the Proxy._implementation function
    /// @return The address of the current implementation contract
    function _implementation() internal view virtual override returns (address) {
        return ERC1967Utils.getImplementation();
    }
}
