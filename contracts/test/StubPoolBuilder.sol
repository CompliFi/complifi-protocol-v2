// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../poolBuilder/IPoolBuilder.sol";
import "../poolBuilder/IPoolProxyBuilder.sol";
import "./StubPool.sol";

contract StubPoolBuilder is IPoolBuilder {
  function buildPool(
    string memory _symbol,
    string memory _name,
    IPoolBuilderTypes.Components memory _components,
    address _exposure,
    IPoolBuilderTypes.FeeParams memory _feeParams,
    IPoolBuilderTypes.CollateralParams memory _collateralParams,
    uint256 _minExitAmount,
    address _poolProxyBuilder
  ) public override returns (address) {
    address controller = createPoolController();

    Pool poolProxy = Pool(IPoolProxyBuilder(_poolProxyBuilder).buildPoolProxy(controller));

    poolProxy.initialize(
      _name,
      _symbol,
      _components,
      _exposure,
      _feeParams,
      _collateralParams,
      _minExitAmount
    );

    poolProxy.transferOwnership(msg.sender);
    return address(poolProxy);
  }

  function createPoolController() public override returns (address) {
    return address(new StubPool());
  }

}
