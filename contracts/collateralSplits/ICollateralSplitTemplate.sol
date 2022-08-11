// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICollateralSplitTemplate {
  function splitNominalValue(int256 _normalizedValue) external pure returns (int256);

  function normalize(int256 _u_0, int256 _u_T) external pure returns (int256);

  function range(int256 _split) external returns (uint256);
}
