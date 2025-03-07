// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import "../common/Enums.sol";

/**
 * @title IHookMultiPlexer
 * @dev Interface for a module that allows to query SubHooks of a ModularWallet in HookMultiPlexer
 * @author rhinestone.wtf
 */
interface IHookMultiPlexer {
    function getHooks(
        address smartAccount
    ) external view returns (address[] memory hooks);

    function isModuleType(uint256 typeID) external returns (bool);

    function name() external returns (string memory);

    function version() external returns (string memory);

    function hasHook(
        address walletAddress,
        address hookAddress,
        HookType hookType
    ) external returns (bool);
}
