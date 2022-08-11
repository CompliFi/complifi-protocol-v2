// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../Const.sol";
import "./ISettableFeed.sol";

contract SettableFeed is ISettableFeed, Const, AccessControl {
  // An error specific to the Aggregator V3 Interface, to prevent possible
  // confusion around accidentally reading unset values as reported values.
  string private constant V3_NO_DATA_ERROR = "No data present";

  bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

  struct Round {
    int256 answer;
    uint256 timestamp;
  }

  uint80 public latestRoundId;
  mapping(uint80 => Round) internal rounds;

  constructor() {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(SETTER_ROLE, msg.sender);
  }

  function decimals() external view virtual override returns (uint8) {
    return BONE_DECIMALS;
  }

  function description() external pure virtual override returns (string memory) {
    return "";
  }

  function version() external pure virtual override returns (uint256) {
    return 1;
  }

  function setLatestRoundData(int256 _answer, uint256 _timestamp)
    public
    virtual
    override
    onlyRole(SETTER_ROLE)
  {
    require(_timestamp != 0, "ZEROTIME");
    latestRoundId += 1;
    emit NewRound(latestRoundId, msg.sender, _timestamp);
    emit AnswerUpdated(_answer, latestRoundId, _timestamp);
    rounds[latestRoundId] = Round(_answer, _timestamp);
  }

  // getRoundData and latestRoundData should both raise "No data present"
  // if they do not have data to report, instead of returning unset values
  // which could be misinterpreted as actual reported values.
  function getRoundData(uint80 _roundId)
    external
    view
    override
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    Round memory round = rounds[_roundId];
    require(round.timestamp != 0, V3_NO_DATA_ERROR);
    roundId = _roundId;
    answer = round.answer;
    startedAt = round.timestamp;
    updatedAt = round.timestamp;
    answeredInRound = _roundId;
  }

  function latestRoundData()
    external
    view
    override
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    Round memory round = rounds[latestRoundId];
    roundId = latestRoundId;
    answer = round.answer;
    startedAt = round.timestamp;
    updatedAt = round.timestamp;
    answeredInRound = latestRoundId;
  }

  function latestAnswer() external view override returns (int256) {
    Round memory round = rounds[latestRoundId];
    return round.answer;
  }

  function latestTimestamp() external view override returns (uint256) {
    Round memory round = rounds[latestRoundId];
    return round.timestamp;
  }

  function latestRound() external view override returns (uint256) {
    return latestRoundId;
  }

  function getAnswer(uint256 roundId) external view override returns (int256) {
    Round memory round = rounds[uint80(roundId)];
    return round.answer;
  }

  function getTimestamp(uint256 roundId) external view override returns (uint256) {
    Round memory round = rounds[uint80(roundId)];
    return round.timestamp;
  }
}
