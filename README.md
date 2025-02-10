# Etherspot Prime Contracts

[![NPM version][npm-image]][npm-url]
![MIT licensed][license-image]

Smart contract infrastructure for Etherspot Modular Accounts, supporting ERC7579 modular implementations.

## Installation & Setup

Ensure that (Foundry)[https://github.com/foundry-rs/foundry] is installed.

```
forge install
forge build
forge test
```

## ERC7579 Modular Contract Deployments

### Prerequisites

Set up your `.env` file following the example found in `.env.example`.

### Deployments

Can be found in `/script` folder.
There are scripts for individual contract deployments and for staking/unstaking the wallet factory.
There is also an all in one script to deploy all required contracts and stake the wallet factory.

To run all in one script:

`forge script script/DeployAllAndSetup.s.sol:DeployAllAndSetupScript --broadcast -vvvv --rpc-url <NETWORK_NAME>`

For individual deployment scripts (example):

`forge script script/ModularEtherspotWallet.s.sol:ModularEtherspotWalletScript --broadcast -vvvv --rpc-url <NETWORK_NAME>`


### Test Suite

`forge test`

### Solidity Usage

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@etherspot/prime-contracts/src/modular-etherspot-wallet/wallet/ModularEtherspotWallet.sol";

// ...
```

## Documentation

- [ERC4337 Specification](https://eips.ethereum.org/EIPS/eip-4337)
- [ERC7579 Specification](https://eips.ethereum.org/EIPS/eip-7579)
- [Integration Guide](https://docs.etherspot.dev)

## License

MIT

[npm-image]: https://badge.fury.io/js/%40etherspot%2Flite-contracts.svg
[npm-url]: https://npmjs.org/package/@etherspot/lite-contracts
[license-image]: https://img.shields.io/badge/license-MIT-blue.svg
