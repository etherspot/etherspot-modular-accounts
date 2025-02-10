// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../../erc7579-ref-impl/interfaces/IERC7579Module.sol";

contract ERC1155FallbackHandler is IFallback {
    /*//////////////////////////////////////////////////////////////
                               MAPPINGS
    //////////////////////////////////////////////////////////////*/
    mapping(address => bool) private _initialized;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ERC1155FallbackHandlerInstalled(address account);
    event ERC1155FallbackHandlerUninstalled(address account);
    event ERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes data
    );
    event ERC1155BatchReceived(
        address operator,
        address from,
        uint256[] ids,
        uint256[] values,
        bytes data
    );

    /*//////////////////////////////////////////////////////////////
                               EXTERNAL
    //////////////////////////////////////////////////////////////*/

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4) {
        emit ERC1155Received(operator, from, id, value, data);
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4) {
        emit ERC1155BatchReceived(operator, from, ids, values, data);
        return this.onERC1155BatchReceived.selector;
    }

    function onInstall(bytes calldata data) external {
        emit ERC1155FallbackHandlerInstalled(msg.sender);
        _initialized[msg.sender] = true;
    }
    function onUninstall(bytes calldata data) external {
        emit ERC1155FallbackHandlerUninstalled(msg.sender);
        _initialized[msg.sender] = false;
    }

    function isModuleType(uint256 moduleTypeId) external view returns (bool) {
        return moduleTypeId == MODULE_TYPE_FALLBACK;
    }

    function isInitialized(address smartAccount) external view returns (bool) {
        return _initialized[msg.sender];
    }
}
