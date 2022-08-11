// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../utility/SettableFeed.sol";

contract ConstantFeed is SettableFeed {
  uint8 private decimals_;

  constructor(uint8 _decimals) {
    decimals_ = _decimals;
  }

  function decimals() external view override returns (uint8) {
    return decimals_;
  }

  function description() external pure override returns (string memory) {
    return "Constant Price Feed";
  }

  function version() external pure override returns (uint256) {
    return 1;
  }
}
