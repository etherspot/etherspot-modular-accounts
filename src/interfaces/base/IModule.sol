// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IModule {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error AlreadyInitialized(address smartAccount);
    error NotInitialized(address smartAccount);

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function onInstall(bytes calldata data) external;

    function onUninstall(bytes calldata data) external;

    function isModuleType(uint256 moduleTypeId) external view returns (bool);

    function isInitialized(address smartAccount) external view returns (bool);
}
