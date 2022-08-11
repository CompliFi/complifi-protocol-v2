// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./CollateralSplitParent.sol";

contract CallOptionSplit is CollateralSplitParent {
  function symbol() external pure override returns (string memory) {
    return "CallOption";
  }

  function splitNominalValue(int256 _normalizedValue) public pure override returns (int256) {
    if (_normalizedValue > 0) {
      return (iBONE * _normalizedValue) / (iBONE + _normalizedValue);
    } else {
      return 0;
    }
  }
}
