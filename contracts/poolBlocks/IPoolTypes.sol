// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../specification/IDerivativeSpecification.sol";
import "../collateralSplits/ICollateralSplit.sol";
import "../volatility/IVolatilityEvolution.sol";
import "../IUnderlyingLiquidityValuer.sol";

interface IPoolTypes {
  enum PriceType {
    mid,
    ask,
    bid
  }

  enum Side {
    Primary,
    Complement,
    Empty,
    Both
  }

  enum Mode {
    Temp,
    Reinvest
  }

  struct Sequence {
    Mode mode;
    Side side;
    uint256 settlementDelta;
    uint256 strikePosition;
  }

  struct DerivativeConfig {
    IDerivativeSpecification specification;
    address[] underlyingOracles;
    address[] underlyingOracleIterators;
    address collateralToken;
    ICollateralSplit collateralSplit;
  }

  struct Derivative {
    DerivativeConfig config;
    address terms;
    Sequence sequence;
    DerivativeParams params;
  }

  struct DerivativeParams {
    uint256 priceReference;
    uint256 settlement;
    uint256 denomination;
  }

  struct Vintage {
    Pair rollRate;
    Pair releaseRate;
    uint256 priceReference;
  }

  struct Pair {
    uint256 primary;
    uint256 complement;
  }

  struct PoolSnapshot {
    Derivative[] derivatives;
    address exposureAddress;
    uint256 collateralLocked;
    uint256 collateralFree;
    Pair[] derivativePositions;
    IVolatilityEvolution volatilityEvolution;
    IUnderlyingLiquidityValuer underlyingLiquidityValuer;
  }

  struct PricePair {
    int256 primary;
    int256 complement;
  }

  struct OtherPrices {
    int256 collateral;
    int256 underlying;
    uint256 volatilityRoundHint;
  }

  struct SettlementValues {
    Pair value;
    uint256 underlyingPrice;
  }

  struct RolloverTrade {
    Pair inward;
    Pair outward;
  }

  struct DerivativeSettlement {
    uint256 settlement;
    Pair value;
    Pair position;
  }

  struct PoolSharePriceHints {
    bool hintLess;
    uint256 collateralPrice;
    uint256[] underlyingRoundHintsIndexed;
    uint256 volatilityRoundHint;
  }

  struct PoolBalance {
    uint256 collateralLocked;
    uint256 collateralFree;
    uint256 releasedWinnings;
    uint256 releasedLiquidityTotal;
  }

  struct RolloverHints {
    uint256 derivativeIndex;
    uint256 collateralRoundHint;
    uint256[] underlyingRoundHintsIndexed;
    uint256 volatilityRoundHint;
  }
}
