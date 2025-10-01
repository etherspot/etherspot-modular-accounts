// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// ERC-1271 constants
bytes4 constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
bytes4 constant ERC1271_INVALID = 0xffffffff;

// ERC-4337 constants
uint256 constant SIG_VALIDATION_SUCCESS = 0;
uint256 constant SIG_VALIDATION_FAILED = 1;

// ERC-7579 constants
uint256 constant MODULE_TYPE_VALIDATOR = 1;
uint256 constant MODULE_TYPE_EXECUTOR = 2;
uint256 constant MODULE_TYPE_FALLBACK = 3;
uint256 constant MODULE_TYPE_HOOK = 4;
