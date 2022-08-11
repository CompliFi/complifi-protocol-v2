// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AddressRegistryParent.sol";
import "../specification/IDerivativeSpecificationMetadata.sol";

contract DerivativeSpecificationRegistry is AddressRegistryParent {
  mapping(bytes32 => bool) internal _uniqueFieldsHashMap;

  function generateKey(address _value) public view override returns (bytes32 _key) {
    return keccak256(abi.encodePacked(IDerivativeSpecificationMetadata(_value).symbol()));
  }

  function _check(bytes32 _key, address _value) internal virtual override {
    super._check(_key, _value);
    IDerivativeSpecificationMetadata derivative = IDerivativeSpecificationMetadata(_value);
    require(derivative.isDerivativeSpecification(), "Should be derivative specification");

    bytes32 uniqueFieldsHash = keccak256(
      abi.encode(
        derivative.underlyingOracleSymbols(),
        derivative.underlyingOracleIteratorSymbols(),
        derivative.collateralTokenSymbol(),
        derivative.collateralSplitSymbol(),
        derivative.referencePriceMultiplier()
      )
    );

    require(!_uniqueFieldsHashMap[uniqueFieldsHash], "Same spec params");

    _uniqueFieldsHashMap[uniqueFieldsHash] = true;
  }
}
