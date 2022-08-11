// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./IPoolProxyBuilder.sol";

contract PoolProxyBuilder is IPoolProxyBuilder {
  function buildPoolProxy(address _poolController) public override returns (address) {
    return address(new ERC1967Proxy(_poolController, new bytes(0)));
  }
}
