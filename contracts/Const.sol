// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Const {
  uint8 public constant STANDARD_DECIMALS = 18;
  uint8 public constant BONE_DECIMALS = 26;
  uint256 public constant BONE = 10**BONE_DECIMALS;
  int256 public constant iBONE = int256(BONE);
}
