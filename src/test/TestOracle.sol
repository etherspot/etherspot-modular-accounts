// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../interfaces/IOracle.sol";

contract TestOracle is IOracle {
    int256 public price;
    uint8 public decimals;
    uint256 public priceUpdatedAt;
    bool public shouldRevert; // Flag to control reverting

    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimals = _decimals;
        priceUpdatedAt = block.timestamp;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (shouldRevert) {
            revert("Oracle failed");
        }
        return (73786976294838215802, price, priceUpdatedAt, priceUpdatedAt, 73786976294838215802);
    }

    function configurePrice(int256 _price) external {
        price = _price;
        priceUpdatedAt = block.timestamp;
    }

    function configurePriceAndTimestamp(int256 _price, uint256 _updatedAt) external {
        price = _price;
        priceUpdatedAt = _updatedAt;
    }

    function configureDecimals(uint8 _decimals) external {
        decimals = _decimals;
    }

    function configureUpdatedAt(uint256 _updatedAt) external {
        priceUpdatedAt = _updatedAt;
    }

    function configureShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
}
