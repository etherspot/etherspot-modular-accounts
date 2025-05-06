// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {LibClone} from "solady/src/utils/LibClone.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {IModularEtherspotWallet} from "../interfaces/IModularEtherspotWallet.sol";

contract ModularEtherspotWalletFactory is Ownable {
    address public implementation;

    event ModularAccountDeployed(address indexed account, address indexed owner);

    error FactoryStaker_InvalidEPAddress();

    constructor(address _implementation, address _owner) {
        _initializeOwner(_owner);
        implementation = _implementation;
    }

    function createAccount(bytes32 salt, bytes calldata initCode) public payable virtual returns (address) {
        bytes32 _salt = _getSalt(salt, initCode);
        (bool alreadyDeployed, address account) = LibClone.createDeterministicERC1967(msg.value, implementation, _salt);

        if (!alreadyDeployed) {
            address owner = address(uint160(uint256(bytes32(initCode[0:32]))));
            IModularEtherspotWallet(account).initializeAccount(initCode);
            emit ModularAccountDeployed(account, owner);
        }
        return account;
    }

    function getAddress(bytes32 salt, bytes calldata initcode) public view virtual returns (address) {
        bytes32 _salt = _getSalt(salt, initcode);
        return LibClone.predictDeterministicAddressERC1967(implementation, _salt, address(this));
    }

    function _getSalt(bytes32 _salt, bytes calldata initCode) public pure virtual returns (bytes32 salt) {
        salt = keccak256(abi.encodePacked(_salt, initCode));
    }

    function addStake(address _epAddress, uint32 _unstakeDelaySec) external payable onlyOwner {
        if (_epAddress == address(0)) revert FactoryStaker_InvalidEPAddress();
        IEntryPoint(_epAddress).addStake{value: msg.value}(_unstakeDelaySec);
    }

    function unlockStake(address _epAddress) external onlyOwner {
        if (_epAddress == address(0)) revert FactoryStaker_InvalidEPAddress();
        IEntryPoint(_epAddress).unlockStake();
    }

    function withdrawStake(address _epAddress, address payable _withdrawTo) external onlyOwner {
        if (_epAddress == address(0)) revert FactoryStaker_InvalidEPAddress();
        IEntryPoint(_epAddress).withdrawStake(_withdrawTo);
    }

    function setImplementation(address _implementation) external onlyOwner {
        implementation = _implementation;
    }
}
