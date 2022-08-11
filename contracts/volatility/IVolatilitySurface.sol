// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVolatilitySurface {
  function calcSigmaATM(bytes16 _omega, bytes16 _ttm) external view returns (bytes16);

  function calcSigmaATMReverted(bytes16 _sigmaTTM, bytes16 _ttm) external view returns (bytes16);

  function calcSigma(
    bytes16 _sigmaATM,
    bytes16 _mu,
    bytes16 _ttm
  ) external view returns (bytes16);

  function calcSigmaReverted(
    bytes16 _sigma,
    bytes16 _mu,
    bytes16 _ttm
  ) external view returns (bytes16);
}
