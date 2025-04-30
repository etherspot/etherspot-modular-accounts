// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../../../src/libraries/BootstrapLib.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {ModularTestBase} from "../../../ModularTestBase.sol";
import {EIP7702_PREFIX} from "../../../../src/types/Constants.sol";
import {SigHookInit} from "../../../../src/types/Structs.sol";
import {TestERC1155} from "../../../../src/test/TestERC1155.sol";

contract ModularEtherspotWalletTestUtils is ModularTestBase {
    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    TestERC1155 ENJIN;
    TestERC1155 AXIE;
    User internal eoa7702;
    bytes internal initData;
    address payable internal acc7702;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function _testSetup() internal {
        _testInit();
        ENJIN = new TestERC1155();
        AXIE = new TestERC1155();
        eoa7702 = _createUser("EOA 7702");
        initData = _getBasicInitData();
    }

    /*//////////////////////////////////////////////////////////////
                           EIP-7702 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _actionEIP7702(User memory _user) internal {
        vm.etch(_user.pub, abi.encodePacked(EIP7702_PREFIX, bytes20(address(IMPLEMENTATION))));
    }

    function _getAddress(bytes memory _initData) internal returns (address) {
        return FACTORY.getAddress(TEST_SALT, _initData);
    }

    function _getBasicInitData() internal returns (bytes memory _initData) {
        // Create config for initial modules
        BootstrapConfig[] memory validators = BootstrapLib._buildArrayConfig(address(MOCK_VALIDATOR), hex"");
        BootstrapConfig[] memory executors = BootstrapLib._buildArrayConfig(address(MOCK_EXECUTOR), hex"");
        BootstrapConfig memory hook = BootstrapLib._buildEmptySingleConfig();
        BootstrapConfig[] memory fallbacks = BootstrapLib._buildEmptyArrayConfig();
        // Create initData
        _initData = BOOTSTRAP.getInitializationCalldata(validators, executors, hook, fallbacks);
    }

    // NOTE: In ideal flow we would like installed:
    // - Validator: an ECDSA validator, ResourceLockValidator, CredibleAccountModule as validator
    // - Hook: HookMultiplexer with CredibleAccountModule as hook
    // - Due to limitations on how you install CredibleAccountModule via Bootstrap
    //   we can install during init and will have to be installed post init
    function _getComplexInitData(User memory _user) internal returns (bytes memory _initData) {
        // Setup data for HMP
        address[] memory globalHooks = new address[](1);
        globalHooks[0] = address(CREDIBLE_ACCOUNT_HOOK);
        address[] memory valueHooks = new address[](0);
        address[] memory delegatecallHooks = new address[](0);
        SigHookInit[] memory sigHooks = new SigHookInit[](0);
        SigHookInit[] memory targetSigHooks = new SigHookInit[](0);
        bytes memory hmpData = abi.encode(globalHooks, valueHooks, delegatecallHooks, sigHooks, targetSigHooks);
        // Create config for initial modules
        address[] memory validatorAddresses = new address[](2);
        validatorAddresses[0] = address(ECDSA_VALIDATOR);
        validatorAddresses[1] = address(RESOURCE_LOCK_VALIDATOR);
        bytes[] memory validatorData = new bytes[](2);
        validatorData[0] = abi.encode(_user.pub);
        validatorData[1] = abi.encode(_user.pub);
        BootstrapConfig[] memory validators = BootstrapLib._buildMultipleConfigs(validatorAddresses, validatorData);
        BootstrapConfig[] memory executors = BootstrapLib._buildArrayConfig(address(MOCK_EXECUTOR), hex"");
        BootstrapConfig memory hook = BootstrapLib._buildSingleConfig(address(HOOK_MULTIPLEXER), hmpData);
        BootstrapConfig[] memory fallbacks = BootstrapLib._buildEmptyArrayConfig();
        // Create initData
        _initData = BOOTSTRAP.getInitializationCalldata(validators, executors, hook, fallbacks);
    }
}
