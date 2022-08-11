// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./CollateralSplitParent.sol";

contract x1Split is CollateralSplitParent {
  function symbol() external pure override returns (string memory) {
    return "x1";
  }

  function splitNominalValue(int256 _normalizedValue) public pure override returns (int256) {
    return (iBONE + _normalizedValue) / 2;
  }
}
