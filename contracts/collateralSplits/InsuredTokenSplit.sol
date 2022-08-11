// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./CollateralSplitParent.sol";

contract InsuredTokenSplit is CollateralSplitParent {
  int256 public constant ZER0_POINT_EIGHT = iBONE * 8 / 10;

  function symbol() external pure override returns (string memory) {
    return "InsuredToken";
  }

  function splitNominalValue(int256 _normalizedValue) public pure override returns (int256) {
    if (_normalizedValue <= -(iBONE / 5)) { // <= -0.2
      return iBONE; // 1
    } else if (_normalizedValue >= 0 ) { // >= 0
      return ZER0_POINT_EIGHT; // 0.8
    } else {
      return (ZER0_POINT_EIGHT * iBONE) / (iBONE + _normalizedValue); // 0.8 / (1 + normalizedValue)
    }
  }
}
