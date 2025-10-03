// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AggregatorV2V3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";

contract MockFailingSequencerFeed is AggregatorV2V3Interface {
    uint8 public decimals = 0;
    string public description = "Failing Feed";
    uint256 public version = 1;

    function latestRoundData() external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert("Feed failure");
    }

    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert("Not implemented");
    }

    function latestAnswer() external pure returns (int256) {
        revert("Not implemented");
    }

    function latestTimestamp() external pure returns (uint256) {
        revert("Not implemented");
    }

    function latestRound() external pure returns (uint256) {
        revert("Not implemented");
    }

    function getAnswer(uint256) external pure returns (int256) {
        revert("Not implemented");
    }

    function getTimestamp(uint256) external pure returns (uint256) {
        revert("Not implemented");
    }
}
