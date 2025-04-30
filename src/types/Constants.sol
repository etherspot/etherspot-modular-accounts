// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CallType, ExecType, ModeSelector} from "./Types.sol";

/*//////////////////////////////////////////////////////////////
                          ENTRYPOINT
//////////////////////////////////////////////////////////////*/

address constant ENTRYPOINT_7_ADDR = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

/*//////////////////////////////////////////////////////////////
                      ERC-1271 CONSTANTS
//////////////////////////////////////////////////////////////*/

bytes4 constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
bytes4 constant ERC1271_INVALID = 0xffffffff;

/*//////////////////////////////////////////////////////////////
                      ERC-4227 CONSTANTS
//////////////////////////////////////////////////////////////*/

uint256 constant SIG_VALIDATION_SUCCESS = 0;
uint256 constant SIG_VALIDATION_FAILED = 1;

/*//////////////////////////////////////////////////////////////
                      ERC-7579 CONSTANTS
//////////////////////////////////////////////////////////////*/

// Module Types
uint256 constant MODULE_TYPE_VALIDATOR = 1;
uint256 constant MODULE_TYPE_EXECUTOR = 2;
uint256 constant MODULE_TYPE_FALLBACK = 3;
uint256 constant MODULE_TYPE_HOOK = 4;
uint256 constant MODULE_TYPE_PREVALIDATION_HOOK_ERC1271 = 8;
uint256 constant MODULE_TYPE_PREVALIDATION_HOOK_ERC4337 = 9;
// CallTypes
// Default CallType
CallType constant CALLTYPE_SINGLE = CallType.wrap(0x00);
// Batched CallType
CallType constant CALLTYPE_BATCH = CallType.wrap(0x01);
// @dev Implementing delegatecall is OPTIONAL!
// implement delegatecall with extreme care.
CallType constant CALLTYPE_STATIC = CallType.wrap(0xFE);
CallType constant CALLTYPE_DELEGATECALL = CallType.wrap(0xFF);
// @dev default behavior is to revert on failure
// To allow very simple accounts to use mode encoding, the default behavior is to revert on failure
// Since this is value 0x00, no additional encoding is required for simple accounts
ExecType constant EXECTYPE_DEFAULT = ExecType.wrap(0x00);
// @dev account may elect to change execution behavior. For example "try exec" / "allow fail"
ExecType constant EXECTYPE_TRY = ExecType.wrap(0x01);
// Mode Selectors
ModeSelector constant MODE_DEFAULT = ModeSelector.wrap(bytes4(0x00000000));

/*//////////////////////////////////////////////////////////////
                      EIP-7702 CONSTANTS
//////////////////////////////////////////////////////////////*/

bytes3 constant EIP7702_PREFIX = bytes3(0xef0100);

/*//////////////////////////////////////////////////////////////
                        STORAGE SLOTS
//////////////////////////////////////////////////////////////*/

// keccak256(abi.encode(uint256(keccak256("etherspot.storage.modular")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant ETHERSPOT_STORAGE_SLOT = 0x3aa3b99b0911678ba283157527a71981a89104231b02d221684ae2f65a794400;
// keccak256(abi.encode(uint256(keccak256(bytes("InteroperableDelegatedAccount.ERC.Storage"))) - 1)) & ~bytes32(uint256(0xff));
bytes32 constant ERC7779_STORAGE_BASE = 0xc473de86d0138e06e4d4918a106463a7cc005258d2e21915272bcb4594c18900;
// keccak256('eip1967.proxy.implementation')) - 1)
bytes32 constant ERC1967_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
// keccak256(abi.encode(uint256(keccak256("initializable.transient.etherspot")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant INIT_SLOT = 0x0d5e24cdb02b56399be03051e6d46add43ca78936015dbbc6258f4f01cc68400;
