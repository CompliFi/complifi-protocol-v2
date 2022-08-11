// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

interface ISettableFeed is AggregatorV2V3Interface {
  function setLatestRoundData(int256 _answer, uint256 _timestamp) external;
}
