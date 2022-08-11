// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../poolBlocks/IPoolTypes.sol";

interface IExposure is IPoolTypes {
  function calcExposure(
    Derivative[] memory derivatives,
    Pair[] memory positions,
    uint256 collateralAmount
  ) external view returns (uint256);

  function calcCollateralExposureLimit(
    Derivative[] memory derivatives,
    Pair[] memory positions
  ) external view returns (uint256);

  function calcInputPercent(
    uint256 derivativeIndex,
    Derivative[] memory derivatives,
    Pair[] memory positions,
    uint256 collateralFreeAmount,
    uint256 inDerivativeAmountNew,
    uint256 outDerivativeAmountNew,
    uint256 collateralAmountNew
  ) external view returns (bytes16 percent);

  function getCoefficients(
    address[] memory _underlyings
  ) external view returns(uint256[4][] memory coefficients);

  function getWeight(
    uint256 _derivativeIndex
  ) external view returns(uint256);
}
