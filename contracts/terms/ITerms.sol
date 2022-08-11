// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ITermsTypes.sol";

interface ITerms is ITermsTypes {

  function version() external returns (uint256);

  function instrumentType() external returns (string memory);

  function calculatePrice(
    uint256 _pointInTime,
    Derivative memory _derivative,
    Side _side,
    PriceType _price,
    OtherPrices memory otherPrices,
    IVolatilityEvolution _volatilityEvolution
  ) external returns (PricePair memory);

  function calculateRolloverTrade(
    PoolSnapshot memory snapshot,
    uint256 derivativeIndex,
    IPoolTypes.DerivativeSettlement memory derivativeSettlement,
    OtherPrices memory otherPrices
  ) external returns (RolloverTrade memory positions);

  function calculateOutAmount(
    PoolSnapshot memory snapshot,
    uint256 inAmount,
    uint256 derivativeIndex,
    Side _side,
    bool _poolReceivesCollateral,
    OtherPrices memory otherPrices
  ) external returns (uint256 outAmount);
}
