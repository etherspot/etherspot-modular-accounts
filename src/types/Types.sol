// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "./Constants.sol";

// Custom type for improved developer experience
type ModeCode is bytes32;

type CallType is bytes1;

type ExecType is bytes1;

type ModeSelector is bytes4;

type ModePayload is bytes22;

using {eqModeSelector as ==} for ModeSelector global;
using {eqCallType as ==} for CallType global;
using {eqExecType as ==} for ExecType global;

function eqCallType(CallType a, CallType b) pure returns (bool) {
    return CallType.unwrap(a) == CallType.unwrap(b);
}

function eqExecType(ExecType a, ExecType b) pure returns (bool) {
    return ExecType.unwrap(a) == ExecType.unwrap(b);
}

function eqModeSelector(ModeSelector a, ModeSelector b) pure returns (bool) {
    return ModeSelector.unwrap(a) == ModeSelector.unwrap(b);
}

type ValidAfter is uint48;

type ValidUntil is uint48;

function packValidationData(bool sigFailed, ValidUntil validUntil, ValidAfter validAfter) pure returns (uint256) {
    return (sigFailed ? SIG_VALIDATION_FAILED : SIG_VALIDATION_SUCCESS)
        | (uint256(ValidUntil.unwrap(validUntil)) << 160) | (uint256(ValidAfter.unwrap(validAfter)) << (160 + 48));
}
