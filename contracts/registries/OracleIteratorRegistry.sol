// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AddressRegistryParent.sol";
import "../oracleIterators/IOracleIterator.sol";

contract OracleIteratorRegistry is AddressRegistryParent {
  function generateKey(address _value) public pure override returns (bytes32 _key) {
    require(IOracleIterator(_value).isOracleIterator(), "Should be oracle iterator");
    return keccak256(abi.encodePacked(IOracleIterator(_value).symbol()));
  }
}
