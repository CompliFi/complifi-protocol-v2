// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AddressRegistryParent.sol";
import "../collateralSplits/ICollateralSplit.sol";

contract CollateralSplitRegistry is AddressRegistryParent {
  function generateKey(address _value) public pure override returns (bytes32 _key) {
    require(ICollateralSplit(_value).isCollateralSplit(), "Should be collateral split");
    return keccak256(abi.encodePacked(ICollateralSplit(_value).symbol()));
  }
}
