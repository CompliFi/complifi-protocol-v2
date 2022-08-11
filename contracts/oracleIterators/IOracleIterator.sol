// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOracleIterator {
  /// @notice Proof of oracle iterator contract
  /// @dev Verifies that contract is a oracle iterator contract
  /// @return true if contract is a oracle iterator contract
  function isOracleIterator() external pure returns (bool);

  /// @notice Symbol of the oracle iterator
  /// @dev Should be resolved through OracleIteratorRegistry contract
  /// @return oracle iterator symbol
  function symbol() external pure returns (string memory);

  /// @notice Algorithm that, for the type of oracle used by the derivative,
  //  finds the value closest to a given timestamp
  /// @param _oracle iteratable oracle through
  /// @param _timestamp a given timestamp
  /// @param _roundHint specified a round for a given timestamp
  /// @return roundId the roundId closest to a given timestamp
  /// @return value the value closest to a given timestamp
  /// @return timestamp the timestamp closest to a given timestamp
  function getRound(
    address _oracle,
    uint256 _timestamp,
    uint256 _roundHint
  )
    external
    view
    returns (
      uint80 roundId,
      int256 value,
      uint256 timestamp
    );
}
