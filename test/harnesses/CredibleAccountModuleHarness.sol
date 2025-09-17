// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "ERC7579/libs/ModeLib.sol";
import {CredibleAccountModule} from "../../src/modules/validators/CredibleAccountModule.sol";
import "../../src/common/Structs.sol";

contract CredibleAccountModuleHarness is CredibleAccountModule {
    constructor(address _owner, address _hookMultiPlexer) CredibleAccountModule(_owner, _hookMultiPlexer) {}

    function exposed_validateSingleCall(address _sessionKey, bytes calldata _callData) external returns (bool) {
        return _validateSingleCall(_sessionKey, _callData);
    }

    function exposed_validateBatchCall(address _sessionKey, bytes calldata _callData) external returns (bool) {
        return _validateBatchCall(_sessionKey, _callData);
    }

    function exposed_digestSignature(bytes calldata _signatureWithProof)
        external
        pure
        returns (bytes memory signature)
    {
        return _digestSignature(_signatureWithProof);
    }

    function exposed_retrieveLockedBalance(address _wallet, address _token) external returns (uint256) {
        return _retrieveLockedBalance(_wallet, _token);
    }

    function exposed_cumulativeLockedForWallet(address _wallet) external returns (TokenData[] memory) {
        return _cumulativeLockedForWallet(_wallet);
    }
}
