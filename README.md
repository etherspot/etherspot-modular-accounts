# Etherspot Modular Accounts

[![NPM version][npm-image]][npm-url]
![MIT licensed][license-image]

Smart contract infrastructure for Etherspot Modular Accounts, supporting ERC7579 modular implementations.

## Installation & Setup

Ensure that [Foundry](https://github.com/foundry-rs/foundry) is installed.

```bash
forge install
forge build
forge test
```

## Dependencies

Uses Solidity native dependency manager [Soldeer](https://soldeer.xyz/) as package manager.

To install dependencies:

```bash
forge soldeer install
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

import "@etherspot/modular-accounts/src/wallet/ModularEtherspotWallet.sol";

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

## Addresses

<details>
<summary>v1.0.0</summary>

| Name                                       | Address                                    |
| ------------------------------------------ | ------------------------------------------ |
| ModularEtherspotWallet                     | [0x62Fdd1382b0182F2CC40bAdEa6E5DE0CCb2d6488](https://contractscan.xyz/contract/0x62Fdd1382b0182F2CC40bAdEa6E5DE0CCb2d6488) |
| ModularEtherspotWalletFactory              | [0x38CC0EDdD3a944CA17981e0A19470d2298B8d43a](https://contractscan.xyz/contract/0x38CC0EDdD3a944CA17981e0A19470d2298B8d43a) |
| Bootstrap                                  | [0xCF2808eA7d131d96E5C73Eb0eCD8Dc84D33905C7](https://contractscan.xyz/contract/0xCF2808eA7d131d96E5C73Eb0eCD8Dc84D33905C7) |
| MultipleOwnerECDSAValidator                | [0x0eA25BF9F313344d422B513e1af679484338518E](https://contractscan.xyz/contract/0x0eA25BF9F313344d422B513e1af679484338518E) |
| HookMultiPlexer                            | [0xDcA918dd23456d321282DF9507F6C09A50522136](https://contractscan.xyz/contract/0xDcA918dd23456d321282DF9507F6C09A50522136) |

</details>

<details>
<summary>v2.0.0</summary>

| Name                                       | Address                                    |
| ------------------------------------------ | ------------------------------------------ |
| ModularEtherspotWallet                     | [0x62Fdd1382b0182F2CC40bAdEa6E5DE0CCb2d6488](https://contractscan.xyz/contract/0x62Fdd1382b0182F2CC40bAdEa6E5DE0CCb2d6488) |
| ModularEtherspotWalletFactory              | [0x38CC0EDdD3a944CA17981e0A19470d2298B8d43a](https://contractscan.xyz/contract/0x38CC0EDdD3a944CA17981e0A19470d2298B8d43a) |
| Bootstrap                                  | [0xCF2808eA7d131d96E5C73Eb0eCD8Dc84D33905C7](https://contractscan.xyz/contract/0xCF2808eA7d131d96E5C73Eb0eCD8Dc84D33905C7) |
| MultipleOwnerECDSAValidator                | [0x0eA25BF9F313344d422B513e1af679484338518E](https://contractscan.xyz/contract/0x0eA25BF9F313344d422B513e1af679484338518E) |
| HookMultiPlexer                            | [0xe629A99Fe2fAD23B1dF6Aa680BA6995cfDA885a3](https://contractscan.xyz/contract/0xe629A99Fe2fAD23B1dF6Aa680BA6995cfDA885a3) |
| CredibleAccountModule                      | [0x566f9d697FF95D13643A35B3F11BB4812B2aaF15](https://contractscan.xyz/contract/0x566f9d697FF95D13643A35B3F11BB4812B2aaF15) |
| ResourceLockValidator                      | [0xe8bC0032846DEFDA434B08514034CDccD8db5318](https://contractscan.xyz/contract/0xe8bC0032846DEFDA434B08514034CDccD8db5318) |
| InvoiceManager                             | [0xaedcceEa8D68949739239d877bF2Efa478bc007a](https://contractscan.xyz/contract/0xaedcceEa8D68949739239d877bF2Efa478bc007a) |

</details>
