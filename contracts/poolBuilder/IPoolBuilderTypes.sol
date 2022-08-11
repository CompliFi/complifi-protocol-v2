// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPoolBuilderTypes {
  struct CollateralParams {
    address collateralToken;
    address collateralOracle;
    address collateralOracleIterator;
  }

  struct FeeParams {
    address feeWallet;
    uint256 protocolFee;
  }

  struct Components {
    address poolShareBuilder;
    address traderPortfolioBuilder;
    address underlyingLiquidityValuer;
    address volatilityEvolution;
  }
}
