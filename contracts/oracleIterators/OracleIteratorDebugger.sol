// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IOracleIterator.sol";

contract OracleIteratorDebugger {
  int256 public answer;

  function updateAnswer(
    address _oracleIterator,
    address _oracle,
    uint256 _timestamp,
    uint256[] memory _roundHints
  ) public {
    require(_timestamp > 0, "Zero timestamp");
    require(_oracle != address(0), "Zero oracle");
    require(_oracleIterator != address(0), "Zero oracle iterator");

    IOracleIterator oracleIterator = IOracleIterator(_oracleIterator);
    (, answer, ) = oracleIterator.getRound(_oracle, _timestamp, _roundHints[0]);
  }

  function getRound(
    address _oracleIterator,
    address _oracle,
    uint256 _timestamp,
    uint256[] memory _roundHints
  )
    public
    view
    returns (
      uint80 roundId,
      int256 value,
      uint256 timestamp
    )
  {
    require(_timestamp > 0, "Zero timestamp");
    require(_oracle != address(0), "Zero oracle");
    require(_oracleIterator != address(0), "Zero oracle iterator");

    IOracleIterator oracleIterator = IOracleIterator(_oracleIterator);
    return oracleIterator.getRound(_oracle, _timestamp, _roundHints[0]);
  }
}
