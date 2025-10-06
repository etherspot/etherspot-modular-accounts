// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {LibSort} from "solady/src/utils/LibSort.sol";
import {IHook, IModule, MODULE_TYPE_HOOK} from "ERC7579/interfaces/IERC7579Module.sol";
import {Execution} from "ERC7579/libs/ExecutionLib.sol";
import {HookMultiPlexerLib} from "../../libraries/HookMultiPlexerLib.sol";
import {IHookMultiPlexer} from "../../interfaces/IHookMultiPlexer.sol";
import {TrustedForwarder} from "../../utils/TrustedForwarder.sol";
import "../../common/Enums.sol";
import "../../common/Structs.sol";

/// @title HookMultiPlexer (Modified Version)
/// @dev A module that allows adding multiple hooks to a smart account.
///      This contract is based on the original implementation by rhinestone.wtf,
///      with modifications made by etherspot to extend its functionality.
/// @author Original: rhinestone.wtf
/// @author Modified by: etherspot
/// @notice This contract is licensed under AGPL-3.0-only.
///         Modifications have been made from the original version.
///         See https://www.gnu.org/licenses/agpl-3.0.html for full license text.

contract HookMultiPlexer is IHook, IHookMultiPlexer, TrustedForwarder {
    using HookMultiPlexerLib for *;
    using LibSort for uint256[];
    using LibSort for address[];

    error UnsupportedHookType(HookType hookType);
    error InvalidDataLength(uint256 dataLength);
    error CannotUninstall();

    event HookAdded(address indexed account, address indexed hook, HookType hookType);
    event SigHookAdded(address indexed account, address indexed hook, HookType hookType, bytes4 sig);

    event HookRemoved(address indexed account, address indexed hook, HookType hookType);
    event SigHookRemoved(address indexed account, address indexed hook, HookType hookType, bytes4 sig);
    event AccountInitialized(address indexed account);
    event AccountUninitialized(address indexed account);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          Storage                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    mapping(address account => Config config) internal accountConfig;

    constructor() {}

    modifier onlySupportedHookType(HookType hookType) {
        if (uint8(hookType) <= uint8(HookType.TARGET_SIG)) {
            _;
        } else {
            revert UnsupportedHookType(hookType);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           CONFIG                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * Initializes the module with the hooks
     * @dev data is encoded as follows: abi.encode(
     *      address[] globalHooks,
     *      address[] valueHooks,
     *      address[] delegatecallHooks,
     *      SigHookInit[] sigHooks,
     *      SigHookInit[] targetSigHooks
     * )
     *
     * @param data encoded data containing the hooks
     */
    function onInstall(bytes calldata data) external override {
        // validate the minimum length of the data
        if (data.length < 68) {
            revert InvalidDataLength(data.length);
        }

        // here skip 4 bytes of functionSelector and 32 bytes of offset and 32 bytes of length
        // the actual data starts from 68th byte
        bytes calldata actualData = data[68:];

        // check if the module is already initialized and revert if it is
        if (isInitialized(msg.sender)) revert AlreadyInitialized(msg.sender);

        // decode the hook arrays
        (
            address[] calldata globalHooks,
            address[] calldata valueHooks,
            address[] calldata delegatecallHooks,
            SigHookInit[] calldata sigHooks,
            SigHookInit[] calldata targetSigHooks
        ) = actualData.decodeOnInstall();

        // cache the storage config
        Config storage $config = $getConfig({account: msg.sender});

        globalHooks.requireSortedAndUnique();
        $config.hooks[HookType.GLOBAL] = globalHooks;

        // call remove Hook for each subHook (of HookType GLOBAL) in $config.hooks[HookType.GLOBAL]
        // loop through all the hooks of type HookType.GLOBAL and call remove Hook on them
        uint256 length = $config.hooks[HookType.GLOBAL].length;
        for (uint256 i; i < length; ++i) {
            address hookAddress = $config.hooks[HookType.GLOBAL][i];
            IHook(hookAddress).onInstall(abi.encode(MODULE_TYPE_HOOK, msg.sender));
        }

        valueHooks.requireSortedAndUnique();
        $config.hooks[HookType.VALUE] = valueHooks;

        delegatecallHooks.requireSortedAndUnique();
        $config.hooks[HookType.DELEGATECALL] = delegatecallHooks;

        // storeSelectorHooks function is used to uniquify and sstore sig specific hooks
        $config.sigHooks[HookType.SIG].storeSelectorHooks(sigHooks);
        $config.sigHooks[HookType.TARGET_SIG].storeSelectorHooks(targetSigHooks);

        $config.initialized = true;

        emit AccountInitialized(msg.sender);
    }

    /**
     * Uninstalls the module
     */
    function onUninstall(bytes calldata) external override {
        revert CannotUninstall();
    }

    /**
     * Checks if the module is initialized
     * @dev short curcuiting the check for efficiency
     *
     * @param smartAccount address of the smart account
     *
     * @return true if the module is initialized, false otherwise
     */
    function isInitialized(address smartAccount) public view returns (bool) {
        Config storage $config = $getConfig({account: smartAccount});
        return $config.initialized;
    }

    /**
     * Returns the hooks for the account
     * @dev this function is not optimized and should only be used when calling from offchain
     *
     * @param smartAccount address of the account
     *
     * @return hooks array of hooks
     */
    function getHooks(address smartAccount) external view returns (address[] memory hooks) {
        // cache the storage config
        Config storage $config = $getConfig({account: smartAccount});

        // get the global hooks
        hooks = $config.hooks[HookType.GLOBAL];
        // get the delegatecall hooks
        hooks.join($config.hooks[HookType.DELEGATECALL]);
        // get the value hooks
        hooks.join($config.hooks[HookType.VALUE]);

        hooks.join($config.sigHooks[HookType.SIG]);
        hooks.join($config.sigHooks[HookType.TARGET_SIG]);

        // sort the hooks
        hooks.insertionSort();
        // uniquify the hooks
        hooks.uniquifySorted();
    }

    function hasHook(address walletAddress, address hookAddress, HookType hookType) external view returns (bool) {
        Config storage $config = $getConfig({account: walletAddress});
        return $config.hooks[hookType].contains(hookAddress);
    }

    /**
     * Adds a hook to the account
     * @dev this function will not revert if the hook is already added
     *
     * @param hook address of the hook
     * @param hookType type of the hook
     */
    function addHook(address hook, HookType hookType) external onlySupportedHookType(hookType) {
        // check if the module is initialized and revert if it is not
        if (!isInitialized(msg.sender)) revert NotInitialized(msg.sender);

        // call `onInstall` on the hook
        IHook(hook).onInstall(abi.encode(MODULE_TYPE_HOOK, msg.sender));

        // store subhook
        $getConfig({account: msg.sender}).hooks[hookType].push(hook);

        emit HookAdded(msg.sender, hook, hookType);
    }

    /**
     * Adds a sig hook to the account
     * @dev this function will not revert if the hook is already added
     *
     * @param hook address of the hook
     * @param sig bytes4 of the sig
     * @param hookType type of the hook
     */
    function addSigHook(address hook, bytes4 sig, HookType hookType) external onlySupportedHookType(hookType) {
        // check if the module is initialized and revert if it is not
        if (!isInitialized(msg.sender)) revert NotInitialized(msg.sender);

        // cache the storage config
        Config storage $config = $getConfig({account: msg.sender});

        $config.sigHooks[hookType].sigHooks[sig].push(hook);
        $config.sigHooks[hookType].allSigs.pushUnique(sig);

        emit SigHookAdded(msg.sender, hook, hookType, sig);
    }

    /**
     * Removes a hook from the account
     *
     * @param hook address of the hook
     * @param hookType type of the hook
     */
    function removeHook(address hook, HookType hookType) external {
        _removeHook(hook, hookType);
    }

    function _removeHook(address hook, HookType hookType) internal {
        // call onUnInstall for the hook (data should have ModuleType as Hook
        // and msg.sender set while calling onUnInstall as deinitData)
        IHook(hook).onUninstall(abi.encode(MODULE_TYPE_HOOK, msg.sender));

        // cache the storage config
        Config storage $config = $getConfig({account: msg.sender});
        $config.hooks[hookType].popAddress(hook);
        emit HookRemoved(msg.sender, hook, hookType);
    }

    /**
     * Removes a sig hook from the account
     *
     * @param hook address of the hook
     * @param sig bytes4 of the sig
     * @param hookType type of the hook
     */
    function removeSigHook(address hook, bytes4 sig, HookType hookType) external {
        // check if the module is initialized and revert if it is not
        if (!isInitialized(msg.sender)) revert NotInitialized(msg.sender);

        // cache the storage config
        Config storage $config = $getConfig({account: msg.sender});
        SignatureHooks storage $sigHooks = $config.sigHooks[hookType];

        uint256 length = $sigHooks.sigHooks[sig].length;
        $sigHooks.sigHooks[sig].popAddress(hook);
        if (length == 1) {
            $sigHooks.allSigs.popBytes4(sig);
        }
        emit SigHookRemoved(msg.sender, hook, hookType, sig);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      MODULE LOGIC                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * Checks if the transaction is valid
     * @dev this function is called before the transaction is executed
     *
     * @param msgSender address of the sender
     * @param msgValue value of the transaction
     * @param msgData data of the transaction
     *
     * @return hookData data of the hooks
     */
    function preCheck(address msgSender, uint256 msgValue, bytes calldata msgData)
        external
        virtual
        override
        returns (bytes memory hookData)
    {
        // cache the storage config
        Config storage $config = $getConfig({account: msg.sender});
        // get the call data selector
        bytes4 callDataSelector = bytes4(msgData[:4]);

        address[] memory hooks = $config.hooks[HookType.GLOBAL];
        hooks.join($config.sigHooks[HookType.SIG].sigHooks[callDataSelector]);

        // if the msgData that is hooked contains an execution
        //          (see IERC7579 execute() and executeFromExecutor())
        // we have to inspect the execution data, and if relevant, add:
        //  - value hooks
        //  - target sig hooks
        //  - delegatecall hooks
        // should the msgData not be an execution (i.e. IERC7579 installModule() or fallback Module
        // this can be skipped
        if (callDataSelector.isExecution()) {
            hooks.appendExecutionHook({$config: $config, msgData: msgData});
        }

        // sort the hooks
        hooks.insertionSort();
        // uniquify the hooks
        hooks.uniquifySorted();
        // call all subhooks and return the subhooks with their context datas
        return abi.encode(hooks.preCheckSubHooks({msgSender: msgSender, msgValue: msgValue, msgData: msgData}));
    }

    /**
     * Checks if the transaction is valid
     * @dev this function is called after the transaction is executed
     *
     * @param hookData data of the hooks
     */
    function postCheck(bytes calldata hookData) external override {
        // create the hooks and contexts array
        HookAndContext[] calldata hooksAndContexts;
        // decode the hookData
        assembly ("memory-safe") {
            let dataPointer := add(hookData.offset, calldataload(hookData.offset))
            hooksAndContexts.offset := add(dataPointer, 0x20)
            hooksAndContexts.length := calldataload(dataPointer)
        }
        // get the length of the hooks
        uint256 length = hooksAndContexts.length;

        for (uint256 i = length; i > 0; --i) {
            HookAndContext calldata hookAndContext = hooksAndContexts[i - 1];
            hookAndContext.hook.postCheckSubHook({preCheckContext: hookAndContext.context});
        }
    }

    /**
     * Gets the config for the account
     *
     * @param account address of the account
     *
     * @return config storage config
     */
    function $getConfig(address account) internal view returns (Config storage) {
        return accountConfig[account];
    }

    /**
     * Returns the type of the module
     *
     * @param typeID type of the module
     *
     * @return true if the type is a module type, false otherwise
     */
    function isModuleType(uint256 typeID) external pure virtual override(IHookMultiPlexer, IModule) returns (bool) {
        return typeID == MODULE_TYPE_HOOK;
    }

    /**
     * Returns the name of the module
     *
     * @return name of the module
     */
    function name() external pure virtual returns (string memory) {
        return "EtherspotHookMultiPlexer";
    }

    /**
     * Returns the version of the module
     *
     * @return version of the module
     */
    function version() external pure virtual returns (string memory) {
        return "2.0.0";
    }
}
