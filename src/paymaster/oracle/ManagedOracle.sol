// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IOracle} from "../../interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ManagedOracle
 * @dev Managed price feed oracle with owner-controlled price updates
 */
contract ManagedOracle is IOracle, Ownable {
    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Current asset price in 8 decimals
    int256 private currentPrice;

    /// @notice Timestamp of last price update
    uint256 public lastUpdated;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emitted when price is manually updated
     * @param newPrice The updated price value
     * @param timestamp When the update occurred
     */
    event ManagedOracle_PriceUpdated(int256 indexed newPrice, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Thrown when attempting to set invalid price
    error ManagedOracle_InvalidPriceValue();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Initialize the price controller
     * @param _initialPrice Starting price value
     * @param _admin Address that can update prices
     */
    constructor(int256 _initialPrice, address _admin) Ownable(_admin) {
        _updatePrice(_initialPrice);
    }

    /*//////////////////////////////////////////////////////////////
                      PUBLIC/EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the current price (owner only)
     * @param _newPrice New price to set
     */
    function updatePrice(int256 _newPrice) external onlyOwner {
        _updatePrice(_newPrice);
    }

    /**
     * @notice Get the current price value
     * @return Current price
     */
    function getCurrentPrice() external view returns (int256) {
        return currentPrice;
    }

    /**
     * @notice Returns the number of decimals for the price
     * @return Number of decimals (always 8)
     */
    function decimals() external pure override returns (uint8) {
        return 8;
    }

    /**
     * @notice Get latest round data (Chainlink compatible)
     * @return roundId Round identifier
     * @return answer Current price
     * @return startedAt Round start time
     * @return updatedAt Last update time
     * @return answeredInRound Answered in round
     */
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (uint80(0), currentPrice, 0, block.timestamp, uint80(0));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to update price with validation
     * @param _newPrice Price value to set
     */
    function _updatePrice(int256 _newPrice) internal {
        if (_newPrice <= 0) {
            revert ManagedOracle_InvalidPriceValue();
        }

        currentPrice = _newPrice;
        lastUpdated = block.timestamp;

        emit ManagedOracle_PriceUpdated(_newPrice, block.timestamp);
    }
}
