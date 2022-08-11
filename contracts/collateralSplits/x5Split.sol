// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./CollateralSplitParent.sol";

contract x5Split is CollateralSplitParent {
  function symbol() external pure override returns (string memory) {
    return "x5";
  }

  function splitNominalValue(int256 _normalizedValue) public pure override returns (int256) {
    if (_normalizedValue <= -(iBONE / 5)) {
      return 0;
    } else if (_normalizedValue > -(iBONE / 5) && _normalizedValue < iBONE / 5) {
      return (iBONE + _normalizedValue * 5) / 2;
    } else {
      return iBONE;
    }
  }
}
