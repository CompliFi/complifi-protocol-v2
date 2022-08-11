// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPoolProxyBuilder {
  function buildPoolProxy(address _poolController) external returns (address);
}
