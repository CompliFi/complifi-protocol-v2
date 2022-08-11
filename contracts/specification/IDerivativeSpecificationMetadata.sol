// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IDerivativeSpecification.sol";

interface IDerivativeSpecificationMetadata is IDerivativeSpecification {
  /// @notice Symbol of the derivative
  /// @dev Should be resolved through DerivativeSpecificationRegistry contract
  /// @return derivative specification symbol
  function symbol() external view returns (string memory);

  /// @notice Return optional long name of the derivative
  /// @dev Isn't used directly in the protocol
  /// @return long name
  function name() external view returns (string memory);

  /// @notice Optional URI to the derivative specs
  /// @dev Isn't used directly in the protocol
  /// @return URI to the derivative specs
  function baseURI() external view returns (string memory);

  function referencePriceMultiplier() external view returns (uint256);
}
