// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {ModularEtherspotWallet} from "../../src/wallet/ModularEtherspotWallet.sol";

contract ModularEtherspotWalletHarness is ModularEtherspotWallet {
    constructor(IEntryPoint _ep) ModularEtherspotWallet(_ep) {}

    function exposed_isEIP7702Account() external view returns (bool) {
        return _isEIP7702Account();
    }
}
