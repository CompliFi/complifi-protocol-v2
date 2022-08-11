// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUnderlyingLiquidityValuer {
  function getUnderlyingLiquidityValue(address underlying) external returns (uint256 liquidityValue);
}
