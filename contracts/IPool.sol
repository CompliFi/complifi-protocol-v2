// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./poolBlocks/IPoolTypes.sol";
import "./poolBlocks/IPoolConfigTypes.sol";
import "./poolBlocks/RedemptionQueue.sol";

interface IPool is IPoolTypes {
  function addDerivative(
    DerivativeConfig memory derivativeImplementation,
    address _termsOfTrade,
    Sequence memory sequence,
    uint256 pRef,
    uint256 settlement
  ) external returns (uint256 derivativeIndex);

  // pool config
  function changeProtocolFee(uint256 _protocolFee) external;

  function changeMinExitAmount(uint256 _minExitAmount) external;

  function changeFeeWallet(address _feeWallet) external;

  function changeVolatilityEvolution(address _volatilityEvolution) external;

  function changeExposure(address _exposure) external;

  function changeCollateralOracleIterator(address _collateralOracleIterator) external;

  function changeUnderlyingLiquidityValuer(address _underlyingLiquidityValuer) external;

  // derivative params
  function changeDerivativeMode(uint256 derivativeIndex, Mode mode) external;

  function changeDerivativeSide(uint256 derivativeIndex, Side side) external;

  function changeDerivativeTerms(uint256 derivativeIndex, address terms) external;

  function changeDerivativeSettlementDelta(uint256 _derivativeIndex, uint256 _settlementDelta) external;

  function getCollateralValue() external view returns (uint256);

  //READ
  function getPoolSharePrice() external view returns (uint256);

  function getDerivativePrice(uint256 _derivativeIndex) external view returns (PricePair memory);

  function getCollateralExposureLimit() external view returns (uint256);

  function getPortfolioBy(address user) external view returns (uint256);

  function checkPortfolioOf(address user) external view returns (bool);

  function derivativeBalanceOf(uint256 portfolioId, uint256 derivativeIndex)
    external
    view
    returns (Pair memory);

  function derivativeVintageIndexOf(uint256 portfolioId, uint256 derivativeIndex)
    external
    view
    returns (uint256);

  function getDerivatives() external view returns (Derivative[] memory);

  function getDerivativeIndex() external view returns (uint256);

  function getDerivative(uint256 derivativeIndex) external view returns (Derivative memory);

  function getDerivativeVintages(uint256 derivativeIndex) external view returns (Vintage[] memory);

  function getDerivativeVintageIndex(uint256 derivativeIndex) external view returns (uint256);

  function getDerivativeVintage(uint256 derivativeIndex, uint256 vintageIndex)
    external
    view
    returns (Vintage memory);

  function getBalance() external view returns (PoolBalance memory);

  function getConfig() external view returns (IPoolConfigTypes.PoolConfig memory);

  function releasedLiquidityOf(address owner) external view returns (uint256);

  function getAllRedemptionRequests() external view returns (RedemptionQueue.Request[] memory);

  function paused() external view returns (bool);
}
