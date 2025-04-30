// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CredibleAccountValidator} from "../validators/CredibleAccountValidator.sol";
import {IHook} from "../../interfaces/base/IHook.sol";
import {IModuleManager} from "../../interfaces/core/IModuleManager.sol";
import {MODULE_TYPE_HOOK} from "../../types/Constants.sol";
import {TokenData} from "../../types/Structs.sol";

contract CredibleAccountHook is IHook {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/

    CredibleAccountValidator public immutable caValidator;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct HookStorage {
        address owner;
    }

    /*//////////////////////////////////////////////////////////////
                               MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(address => HookStorage) public hookStorage;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error CredibleAccountHook_InsufficientUnlockedBalance(address token);
    error CredibleAccountHook_InvalidData();
    error CredibleAccountHook_UninstallCredibleAccountValidatorFirst();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(CredibleAccountValidator _caValidator) {
        caValidator = _caValidator;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC/EXTERNAL
    //////////////////////////////////////////////////////////////*/

    function onInstall(bytes calldata data) external override {
        if (data.length < 32) {
            revert CredibleAccountHook_InvalidData();
        }
        address scw = address(bytes20(data[12:32]));
        if (_isInitialized(scw)) revert AlreadyInitialized(scw);
        hookStorage[scw].owner = msg.sender;
    }

    function onUninstall(bytes calldata data) external override {
        if (data.length < 32) {
            revert CredibleAccountHook_InvalidData();
        }
        address scw = address(bytes20(data[12:32]));
        if (!_isInitialized(scw)) revert NotInitialized(scw);
        // note: problem is hook multiplexer is msg.sender
        if (IModuleManager(scw).isValidatorInstalled(address(caValidator))) {
            revert CredibleAccountHook_UninstallCredibleAccountValidatorFirst();
        }
        delete hookStorage[scw];
    }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == MODULE_TYPE_HOOK;
    }

    function isInitialized(address smartAccount) external view override returns (bool) {
        return _isInitialized(smartAccount);
    }

    function preCheck(address msgSender, uint256 msgValue, bytes calldata msgData)
        external
        override
        returns (bytes memory hookData)
    {
        (address sender,) = abi.decode(msgData, (address, bytes));
        return abi.encode(sender, caValidator.getLockedTokenBalances(sender));
    }

    function postCheck(bytes calldata hookData) external {
        if (hookData.length == 0) return;
        (address sender, TokenData[] memory preCheckBalances) = abi.decode(hookData, (address, TokenData[]));
        for (uint256 i; i < preCheckBalances.length;) {
            address token = preCheckBalances[i].token;
            uint256 preCheckLocked = preCheckBalances[i].amount;
            uint256 walletBalance = _walletTokenBalance(sender, token);
            uint256 postCheckLocked = caValidator.getLockedBalance(sender, token);
            if (walletBalance < preCheckLocked && walletBalance < postCheckLocked) {
                revert CredibleAccountHook_InsufficientUnlockedBalance(token);
            }
            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL/PRIVATE
    //////////////////////////////////////////////////////////////*/

    function _isInitialized(address smartAccount) internal view returns (bool) {
        return hookStorage[smartAccount].owner != address(0);
    }

    function _walletTokenBalance(address _wallet, address _token) internal view returns (uint256) {
        return IERC20(_token).balanceOf(_wallet);
    }
}
