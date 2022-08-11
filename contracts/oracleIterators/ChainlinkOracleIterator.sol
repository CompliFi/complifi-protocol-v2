// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./IOracleIterator.sol";
import "../Const.sol";

contract ChainlinkOracleIterator is IOracleIterator, Const {
  uint256 private constant PHASE_OFFSET = 64;
  int256 public constant NEGATIVE_INFINITY = type(int256).min;
  uint256 private constant MAX_ITERATION = 100;

  function isOracleIterator() external pure override returns (bool) {
    return true;
  }

  function symbol() external pure override returns (string memory) {
    return "ChainlinkIterator";
  }

  function convertToBoneDecimals(AggregatorV3Interface oracle, int256 value)
    internal
    view
    returns (int256)
  {
    return value * int256(10**(BONE_DECIMALS - oracle.decimals()));
  }

  function getRound(
    address _oracle,
    uint256 _timestamp,
    uint256 _roundHint
  )
    external
    view
    override
    returns (
      uint80 roundId,
      int256 value,
      uint256 timestamp
    )
  {
    require(_timestamp > 0, "Zero timestamp");
    require(_oracle != address(0), "Zero oracle");
    AggregatorV3Interface oracle = AggregatorV3Interface(_oracle);

    uint80 latestRoundId;
    (latestRoundId, , , , ) = oracle.latestRoundData();

    uint80 roundHint = uint80(_roundHint);
    if (roundHint == 0) {
      return getIteratedAnswer(oracle, _timestamp, latestRoundId);
    }

    uint256 phaseId;
    (phaseId, ) = parseIds(latestRoundId);

    if (checkSamePhase(roundHint, phaseId)) {
      return getHintedAnswer(oracle, _timestamp, roundHint, latestRoundId);
    }

    (roundId, value, timestamp) = getIteratedAnswer(oracle, _timestamp, latestRoundId);
    if (value == NEGATIVE_INFINITY) {
      return getHintedAnswer(oracle, _timestamp, roundHint, latestRoundId);
    }
    return (roundId, value, timestamp);
  }

  function getHintedAnswer(
    AggregatorV3Interface _oracle,
    uint256 _timestamp,
    uint80 _roundHint,
    uint256 _latestRoundId
  )
    internal
    view
    returns (
      uint80,
      int256,
      uint256
    )
  {
    int256 hintAnswer;
    uint256 hintTimestamp;
    (, hintAnswer, , hintTimestamp, ) = _oracle.getRoundData(_roundHint);

    require(hintTimestamp > 0 && hintTimestamp <= _timestamp, "Incorrect hint");

    if (_roundHint + 1 > _latestRoundId) {
      return (_roundHint, convertToBoneDecimals(_oracle, hintAnswer), hintTimestamp);
    }

    uint256 timestampNext;
    (, , , timestampNext, ) = _oracle.getRoundData(_roundHint + 1);
    if (timestampNext == 0 || timestampNext > _timestamp) {
      return (_roundHint, convertToBoneDecimals(_oracle, hintAnswer), hintTimestamp);
    }

    return (0, NEGATIVE_INFINITY, 0);
  }

  function getIteratedAnswer(
    AggregatorV3Interface _oracle,
    uint256 _timestamp,
    uint80 _latestRoundId
  )
    internal
    view
    returns (
      uint80,
      int256,
      uint256
    )
  {
    uint256 roundTimestamp = 0;
    int256 roundAnswer = 0;
    uint80 roundId = _latestRoundId;

    for (uint256 i = 0; i < MAX_ITERATION; i++) {
      (, roundAnswer, , roundTimestamp, ) = _oracle.getRoundData(roundId);
      roundId = roundId - 1;
      if (roundTimestamp <= _timestamp) {
        return (roundId, convertToBoneDecimals(_oracle, roundAnswer), roundTimestamp);
      }
      if (roundId == 0) {
        return (0, NEGATIVE_INFINITY, 0);
      }
    }

    return (0, NEGATIVE_INFINITY, 0);
  }

  function checkSamePhase(uint80 _roundHint, uint256 _phase) internal pure returns (bool) {
    uint256 currentPhaseId;
    (currentPhaseId, ) = parseIds(_roundHint);
    return currentPhaseId == _phase;
  }

  function parseIds(uint256 _roundId) internal pure returns (uint16, uint64) {
    uint16 phaseId = uint16(_roundId >> PHASE_OFFSET);
    uint64 aggregatorRoundId = uint64(_roundId);

    return (phaseId, aggregatorRoundId);
  }
}
