// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Derivative Specification interface
/// @notice Immutable collection of derivative attributes
/// @dev Created by the derivative's author and published to the DerivativeSpecificationRegistry
interface IDerivativeSpecification {
  /// @notice Proof of a derivative specification
  /// @dev Verifies that contract is a derivative specification
  /// @return true if contract is a derivative specification
  function isDerivativeSpecification() external pure returns (bool);

  /// @notice Set of oracles that are relied upon to measure changes in the state of the world
  /// between the start and the end of the Live period
  /// @dev Should be resolved through OracleRegistry contract
  /// @return oracle symbols
  function underlyingOracleSymbols() external view returns (bytes32[] memory);

  /// @notice Algorithm that, for the type of oracle used by the derivative,
  /// finds the value closest to a given timestamp
  /// @dev Should be resolved through OracleIteratorRegistry contract
  /// @return oracle iterator symbols
  function underlyingOracleIteratorSymbols() external view returns (bytes32[] memory);

  /// @notice Type of collateral that users submit to mint the derivative
  /// @dev Should be resolved through CollateralTokenRegistry contract
  /// @return collateral token symbol
  function collateralTokenSymbol() external view returns (bytes32);

  /// @notice Mapping from the change in the underlying variable (as defined by the oracle)
  /// and the initial collateral split to the final collateral split
  /// @dev Should be resolved through CollateralSplitRegistry contract
  /// @return collateral split symbol
  function collateralSplitSymbol() external view returns (bytes32);

  function denomination(uint256 _settlement, uint256 _referencePrice)
    external
    view
    returns (uint256);

  function referencePrice(uint256 _price, uint256 _position) external view returns (uint256);
}
