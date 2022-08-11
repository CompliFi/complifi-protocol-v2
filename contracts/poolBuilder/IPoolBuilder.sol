// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IPoolBuilderTypes.sol";

interface IPoolBuilder is IPoolBuilderTypes {
  function buildPool(
    string memory _symbol,
    string memory _name,
    IPoolBuilderTypes.Components memory _components,
    address _exposure,
    IPoolBuilderTypes.FeeParams memory _feeParams,
    IPoolBuilderTypes.CollateralParams memory _collateralParams,
    uint256 _minExitAmount,
    address poolProxyBuilder
  ) external returns (address);

  function createPoolController() external returns (address);
}
