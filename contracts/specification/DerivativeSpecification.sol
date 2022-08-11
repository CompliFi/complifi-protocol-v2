// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IDerivativeSpecificationMetadata.sol";
import "../Const.sol";

contract DerivativeSpecification is IDerivativeSpecificationMetadata, Const {
  function isDerivativeSpecification() external pure override returns (bool) {
    return true;
  }

  string internal symbol_;
  string internal name_;
  string private baseURI_;

  bytes32[] internal underlyingOracleSymbols_;
  bytes32[] internal underlyingOracleIteratorSymbols_;

  bytes32 internal collateralTokenSymbol_;

  bytes32 internal collateralOracleSymbol_;

  bytes32 internal collateralSplitSymbol_;

  uint256 internal denomination_;

  uint256 internal referencePriceMultiplier_;

  function symbol() external view virtual override returns (string memory) {
    return symbol_;
  }

  function name() external view virtual override returns (string memory) {
    return name_;
  }

  function baseURI() external view virtual override returns (string memory) {
    return baseURI_;
  }

  function underlyingOracleSymbols() external view virtual override returns (bytes32[] memory) {
    return underlyingOracleSymbols_;
  }

  function underlyingOracleIteratorSymbols()
    external
    view
    virtual
    override
    returns (bytes32[] memory)
  {
    return underlyingOracleIteratorSymbols_;
  }

  function collateralTokenSymbol() external view virtual override returns (bytes32) {
    return collateralTokenSymbol_;
  }

  function collateralSplitSymbol() external view virtual override returns (bytes32) {
    return collateralSplitSymbol_;
  }

  function referencePriceMultiplier() external view virtual override returns (uint256) {
    return referencePriceMultiplier_;
  }

  function denomination(uint256 _settlement, uint256 _referencePrice)
    external
    view
    virtual
    override
    returns (uint256)
  {
    return denomination_;
  }

  function referencePrice(uint256 _price, uint256 _position)
    external
    view
    virtual
    override
    returns (uint256)
  {
    return (((_price * _position) / BONE) / referencePriceMultiplier_) * referencePriceMultiplier_;
  }

  constructor(
    string memory _name,
    string memory _symbol,
    bytes32[] memory _underlyingOracleSymbols,
    bytes32[] memory _underlyingOracleIteratorSymbols,
    bytes32 _collateralTokenSymbol,
    bytes32 _collateralSplitSymbol,
    uint256 _denomination,
    uint256 _referencePriceMultiplier,
    string memory _baseURI
  ) {
    name_ = _name;
    symbol_ = _symbol;
    underlyingOracleSymbols_ = _underlyingOracleSymbols;
    underlyingOracleIteratorSymbols_ = _underlyingOracleIteratorSymbols;

    collateralTokenSymbol_ = _collateralTokenSymbol;
    collateralSplitSymbol_ = _collateralSplitSymbol;
    denomination_ = _denomination;
    referencePriceMultiplier_ = _referencePriceMultiplier;
    baseURI_ = _baseURI;
  }
}
