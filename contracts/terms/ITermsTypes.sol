// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IRepricerTypes.sol";
import "../poolBlocks/IPoolTypes.sol";

interface ITermsTypes is IPoolTypes, IRepricerTypes {
  struct VolatilityInputs {
    bytes16 ttm;
    bytes16 mu;
  }

  struct TradePrices {
    bytes16 derivative;
    bytes16 inward;
    bytes16 outward;
    DerivativePricesBytes16 derivativePrices;
  }

  struct TradeAmounts {
    bytes16 inward;
    bytes16 outward;
  }

  struct RolloverInputs {
    PairBytes16 price;
    PairBytes16 amount;
    PairBytes16 valueAllowed;
    bytes16 collateralAmount;
    bytes16 percentLiq;
  }

  struct FeeParams {
    uint256 baseFee;
    uint256 maxFee;
    uint256 rollFee;
    uint256 feeAmpPrimary;
    uint256 feeAmpComplement;
  }

  struct DerivativePricesBytes16 {
    PairBytes16 pair;
    VolatilityInputs inputs;
    bytes16 sigma;
    bytes16 omega;
  }

  struct OtherPricesBytes16 {
    bytes16 collateral;
    bytes16 underlying;
    uint256 volatilityRoundHint;
  }

  struct DerivativeSettlementBytes16 {
    uint256 settlement;
    PairBytes16 value;
    PairBytes16 position;
  }

  struct RolloverTradeBytes16 {
    PairBytes16 inward;
    PairBytes16 outward;
    bytes16 percentExp;
  }
}
