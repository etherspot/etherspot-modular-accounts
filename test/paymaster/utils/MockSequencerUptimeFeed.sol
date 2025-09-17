// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AggregatorV2V3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";

contract MockSequencerUptimeFeed is AggregatorV2V3Interface {
    int256 public answer; // 0 = up, 1 = down
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public roundId;
    uint80 public answeredInRound;

    uint8 public decimals = 0;
    string public description = "L2 Sequencer Uptime";
    uint256 public version = 1;

    constructor() {
        // Default to sequencer up
        answer = 0;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        roundId = 1;
        answeredInRound = 1;
    }

    function setSequencerUp() external {
        answer = 0;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        roundId++;
        answeredInRound = roundId;
    }

    function setSequencerDown() external {
        answer = 1;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        roundId++;
        answeredInRound = roundId;
    }

    function setSequencerUpWithTimestamp(uint256 _startedAt) external {
        answer = 0;
        startedAt = _startedAt;
        updatedAt = block.timestamp;
        roundId++;
        answeredInRound = roundId;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    // Implement other required functions
    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert("Not implemented");
    }

    function latestAnswer() external view returns (int256) {
        return answer;
    }

    function latestTimestamp() external view returns (uint256) {
        return updatedAt;
    }

    function latestRound() external view returns (uint256) {
        return roundId;
    }

    function getAnswer(uint256) external pure returns (int256) {
        revert("Not implemented");
    }

    function getTimestamp(uint256) external pure returns (uint256) {
        revert("Not implemented");
    }
}
