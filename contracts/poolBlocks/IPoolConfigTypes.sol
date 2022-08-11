// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../portfolio/ITraderPortfolio.sol";
import "../exposure/IExposure.sol";
import "../oracleIterators/IOracleIterator.sol";
import "../volatility/IVolatilityEvolution.sol";
import "../share/IERC20MintedBurnable.sol";
import "../IUnderlyingLiquidityValuer.sol";

interface IPoolConfigTypes {
  struct PoolConfig {
    uint256 minExitAmount; //100USD in collateral
    uint256 protocolFee;
    address feeWallet;
    IERC20 collateralToken;
    address collateralOracle;
    IOracleIterator collateralOracleIterator;
    IVolatilityEvolution volatilityEvolution;
    IUnderlyingLiquidityValuer underlyingLiquidityValuer;
    IExposure exposure;
    IERC20MintedBurnable poolShare;
    ITraderPortfolio traderPortfolio;
    uint8 collateralDecimals;
  }
}
