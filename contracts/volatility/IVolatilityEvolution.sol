// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IVolatilitySurface.sol";
import "../utility/ISettableFeed.sol";
import "../oracleIterators/IOracleIterator.sol";

interface IVolatilityEvolution {
  struct UnderlyingParams {
    IVolatilitySurface surface;
    ISettableFeed feed;
    IOracleIterator feedIterator;
    bytes16 omegaTarget;
    bytes16 omegaMin;
    bytes16 omegaMax;
    bytes16 deltaOmegaMin;
    bytes16 deltaOmegaMax;
    bytes16 sigmaMin;
    bytes16 sigmaMax;
    bytes16 thetaConv;
  }

  struct VolatilityParams {
    bytes16 ttm;
    bytes16 mu;
    bytes16 sigma;
    bytes16 omegaCurrent;
  }

  function calculateVolatility(
    uint256 _pointInTime,
    address _underlying,
    bytes16 _ttm,
    bytes16 _mu,
    uint256 omegaRoundHint
  ) external view returns (bytes16 sigma, bytes16 omega);

  function updateVolatility(
    uint256 _pointInTime,
    VolatilityParams memory _volParams,
    address _underlying,
    bytes16 _underlyingPrice,
    bytes16 _strike,
    bytes16 _priceNorm,
    bool _buyPrimary
  ) external;
}
