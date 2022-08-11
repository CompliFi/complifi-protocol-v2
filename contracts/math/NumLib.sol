// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library NumLib {
  uint8 public constant STANDARD_DECIMALS = 18;
  uint8 public constant BONE_DECIMALS = 26;
  uint256 public constant BONE = 10**BONE_DECIMALS;
  int256 public constant iBONE = int256(BONE);

  function add(uint256 a, uint256 b) public pure returns (uint256 c) {
    c = a + b;
    require(c >= a, "ADD_OVERFLOW");
  }

  function sub(uint256 a, uint256 b) public pure returns (uint256 c) {
    bool flag;
    (c, flag) = subSign(a, b);
    require(!flag, "SUB_UNDERFLOW");
  }

  function subSign(uint256 a, uint256 b) public pure returns (uint256, bool) {
    if (a >= b) {
      return (a - b, false);
    } else {
      return (b - a, true);
    }
  }

  function mul(uint256 a, uint256 b) public pure returns (uint256 c) {
    uint256 c0 = a * b;
    require(a == 0 || c0 / a == b, "MUL_OVERFLOW");
    uint256 c1 = c0 + (BONE / 2);
    require(c1 >= c0, "MUL_OVERFLOW");
    c = c1 / BONE;
  }

  function div(uint256 a, uint256 b) public pure returns (uint256 c) {
    require(b != 0, "DIV_ZERO");
    uint256 c0 = a * BONE;
    require(a == 0 || c0 / a == BONE, "DIV_public"); // mul overflow
    uint256 c1 = c0 + (b / 2);
    require(c1 >= c0, "DIV_public"); //  add require
    c = c1 / b;
  }

  function min(uint256 first, uint256 second) public pure returns (uint256) {
    if (first < second) {
      return first;
    }
    return second;
  }
}
