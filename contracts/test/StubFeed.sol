// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../utility/SettableFeed.sol";

contract StubFeed is SettableFeed {

  bool public updatable;

  uint8 private decimals_;

  constructor(uint8 _decimals, bool _updatable) {
    decimals_ = _decimals;
    updatable = _updatable;
  }

  function setLatestRoundData(int256 _answer, uint256 _timestamp) public override {
    if (updatable) {
      super.setLatestRoundData(_answer, _timestamp);
    }
  }

  function decimals() external view override returns (uint8) {
    return decimals_;
  }

  function description() external pure override returns (string memory) {
    return "Stub Price Feed";
  }

  function version() external pure override returns (uint256) {
    return 3;
  }
}
