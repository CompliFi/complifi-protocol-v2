// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./CollateralSplitParent.sol";

contract StableSplit is CollateralSplitParent {
  function symbol() external pure override returns (string memory) {
    return "Stab";
  }

  function splitNominalValue(int256 _normalizedValue) public pure override returns (int256) {
    if (_normalizedValue <= -(iBONE / 2)) {
      return iBONE;
    } else {
      return (iBONE * iBONE) / (2 * (iBONE + _normalizedValue));
    }
  }
}
