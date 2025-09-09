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
| ModularEtherspotWallet                     | [0x339eAB59e54fE25125AceC3225254a0cBD305A7b](https://contractscan.xyz/contract/0x339eAB59e54fE25125AceC3225254a0cBD305A7b) |
| ModularEtherspotWalletFactory              | [0x2A40091f044e48DEB5C0FCbc442E443F3341B451](https://contractscan.xyz/contract/0x2A40091f044e48DEB5C0FCbc442E443F3341B451) |
| Bootstrap                                  | [0x0D5154d7751b6e2fDaa06F0cC9B400549394C8AA](https://contractscan.xyz/contract/0x0D5154d7751b6e2fDaa06F0cC9B400549394C8AA) |
| MultipleOwnerECDSAValidator                | [0x0740Ed7c11b9da33d9C80Bd76b826e4E90CC1906](https://contractscan.xyz/contract/0x0740Ed7c11b9da33d9C80Bd76b826e4E90CC1906) |

</details>

## ResourceLock Claim Process

1. ResourceLock made on the SmartWallet is uniquely identified by sessionKey
2. ResourceLock claim is initiated by the WalletUser by making a UserOp with transactionObjects
   - approve ERC20 token amount locked 
   - call `generateClaim` function on `CredibleAccountModule` contract
3. UserOp execution will complete these state changes on smart-contract:
   - Updates the claimed amount for the specified token in the session
   - Transfers the claimed amount from walletAddress to invoiceManager
   - InvoiceManager to Credits tokens to a specific invoice, recording that tokens have been received
     Only accounts with CREDIBLE_ACCOUNT_ROLE can credit tokens. This function is part
     of the two-phase settlement process where tokens must be credited before settlement.

## Settle Invoice Process

1. Settles an invoice by transferring tokens to solver and fees to fee receiver
2. Settle-Invoice is the last stage of the claim process
3. Calculates fees based on snapshotted fee amount from invoice creation
4. Deletes all invoice data after successful settlement

Smart contract function: `settleInvoice`
Caller: OrchestratorWallet with SETTLER_ROLE role or linkedWallet in invoiceData
CallType: UserOperation with function call `settleInvoice`


