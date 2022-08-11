// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PoolState.sol";
import "./IPoolTypes.sol";
import "../terms/ITermsTypes.sol";
import "../terms/ITerms.sol";
import "../math/NumLib.sol";

//import "hardhat/console.sol";

library PoolRolloverLogic {
  using PoolState for PoolState.State;
  using RedemptionQueue for RedemptionQueue.Queue;

  uint256 public constant HINTS_FREE_ROLLOVER_MAX = 3;

  event FailedRollover(uint256 chainDerivativeIndex, uint256 inDerivativeIndex);

  event RolledOverDerivative(
    uint256 indexed derivativeIndex,
    uint256 indexed timestamp,
    uint256 indexed settlement,
    IPoolTypes.Pair poolPosition,
    IPoolTypes.Pair newPoolPosition,
    uint256 newVintageIndex,
    IPoolTypes.Vintage newVintage,
    IPoolTypes.DerivativeParams newDerivativeParams,
    IPoolTypes.SettlementValues settlementValues,
    IPoolTypes.RolloverTrade rolloverTrade
  );

  event ProcessedRedemptionQueueItem(
    address indexed user,
    uint256 indexed requestTimestamp,
    uint256 timestamp,
    uint256 processedAmount,
    uint256 releasedLiquidity,
    bool fullyProcessed,
    uint256 collateralExposureLimit,
    uint256 exitRatio,
    uint256 poolSharePrice
  );

  // A
  function processRedemptionQueueAt(
    PoolState.State storage _state,
    uint256 _pointInTime,
    IPoolTypes.PoolSharePriceHints memory _poolSharePriceHints
  ) public returns (bool) {
    if (_state.redemptionQueue.empty() || _state.redemptionQueue.get().time > _pointInTime)
      return true; //empty queue

    uint256 collateralExposureLimit = PoolState.toStandard(
      _state.config.exposure.calcCollateralExposureLimit(
        _state.liveSet,
        _state.getDerivativePoolPositionsBonified()
      )
    );

    uint256 collateralAvailable = _state.balance.collateralFree <= collateralExposureLimit
      ? 0
      : _state.balance.collateralFree - collateralExposureLimit;

    if (collateralAvailable == 0) return false;

    (uint256 poolSharePrice, uint256 poolDerivativesValue) = _state.calculatePoolSharePrice(_pointInTime, _poolSharePriceHints);
    if (poolSharePrice == 0) return false;

    uint256 exitRatio = (poolSharePrice * NumLib.BONE) / _poolSharePriceHints.collateralPrice;

    return
      releaseLiquidity(_state, _pointInTime, exitRatio, collateralExposureLimit, poolSharePrice, poolDerivativesValue, _poolSharePriceHints.collateralPrice);
  }

  struct VarsRL {
    uint256 collateralAvailable;
    uint256 beingBurned;
    uint256 deltaReleasedLiquidity;
    bool fullyExecuted;
    uint256 deltaReleasedLiquidityValue;
    uint256 poolSharePriceAfter;
  }

  function releaseLiquidity(
    PoolState.State storage _state,
    uint256 _pointInTime,
    uint256 _exitRatio,
    uint256 _collateralExposureLimit,
    uint256 _poolSharePrice,
    uint256 _poolDerivativesValue,
    uint256 _collateralPrice
  ) internal returns (bool) {
    while (_state.balance.collateralFree > _collateralExposureLimit) {
      VarsRL memory vars;

      RedemptionQueue.Request storage request = _state.redemptionQueue.get();
      if (_state.redemptionQueue.empty() || request.time > _pointInTime) return true;

      vars.collateralAvailable = _state.balance.collateralFree <= _collateralExposureLimit
        ? 0
        : _state.balance.collateralFree - _collateralExposureLimit;

      if (vars.collateralAvailable == 0) return false;
      vars.beingBurned = request.amount;
      vars.deltaReleasedLiquidity = (request.amount * _exitRatio) / NumLib.BONE;
      vars.fullyExecuted = vars.deltaReleasedLiquidity <= vars.collateralAvailable;
      if (!vars.fullyExecuted) {
        vars.deltaReleasedLiquidity = vars.collateralAvailable;
        vars.beingBurned = (vars.collateralAvailable * NumLib.BONE) / _exitRatio;
        request.amount -= vars.beingBurned;
      }

      _state.balance.collateralFree -= vars.deltaReleasedLiquidity;
      _state.increaseReleasedLiquidity(request.owner, vars.deltaReleasedLiquidity);
      _state.balance.releasedLiquidityTotal += vars.deltaReleasedLiquidity;

      _state.config.poolShare.burn(vars.beingBurned);

      vars.poolSharePriceAfter = (_state.calcPoolCollateralValue(_collateralPrice) + _poolDerivativesValue) * NumLib.BONE
        / PoolState.fromStandard(_state.config.poolShare.totalSupply());

      require(PoolState.subMod(vars.poolSharePriceAfter, _poolSharePrice) <= PoolState.POOL_SHARE_PRICE_APPROXIMATION, "QUEUELPP");

      require(_state.checkPoolCollateralBalance(), "COLERR");

      emitProcessedRedemptionQueueItem(
        request,
        _pointInTime,
        vars.beingBurned,
        vars.deltaReleasedLiquidity,
        vars.fullyExecuted,
        _collateralExposureLimit,
        _exitRatio,
        _poolSharePrice
      );

      if (vars.fullyExecuted) {
        _state.redemptionQueue.dequeue();
      }
    }

    return false;
  }

  function emitProcessedRedemptionQueueItem(
    RedemptionQueue.Request storage request,
    uint256 _pointInTime,
    uint256 beingBurned,
    uint256 deltaReleasedLiquidity,
    bool fullyExecuted,
    uint256 _collateralExposureLimit,
    uint256 _exitRatio,
    uint256 _poolSharePrice
  ) internal {
    emit ProcessedRedemptionQueueItem(
      request.owner,
      request.time,
      _pointInTime,
      beingBurned,
      deltaReleasedLiquidity,
      fullyExecuted,
      _collateralExposureLimit,
      _exitRatio,
      _poolSharePrice
    );
  }

  function rolloverOldestDerivativeBatch(
    PoolState.State storage _state,
    uint256 _pointInTime,
    IPoolTypes.RolloverHints[] memory _rolloverHintsList
  ) public returns (bool) {
    for (uint256 i = 0; i < _rolloverHintsList.length; i++) {
      if (!rolloverOldestDerivative(_state, _pointInTime, _rolloverHintsList[i])) {
        return false;
      }
    }
    return true;
  }

  function rolloverOldestDerivative(
    PoolState.State storage _state,
    uint256 _pointInTime,
    IPoolTypes.RolloverHints memory _rolloverHints
  ) public returns (bool) {
    require(block.timestamp >= _pointInTime, "TIME");
    address[] memory underlyingOracleIndex = _state.getUnderlyingOracleIndex();
    require(_rolloverHints.underlyingRoundHintsIndexed.length == underlyingOracleIndex.length, "PRICEHINTS");

    uint256 derivativeIndex = getOldestDerivativeForRollover(_state, _pointInTime);

    if (
      derivativeIndex == type(uint256).max || _rolloverHints.derivativeIndex != derivativeIndex
    ) {
      emit FailedRollover(derivativeIndex, _rolloverHints.derivativeIndex);
      return false;
    }

    uint256 collateralPrice = uint256(
      _state.getHintedAnswer(
        _state.config.collateralOracleIterator,
        _state.config.collateralOracle,
        _state.liveSet[derivativeIndex].params.settlement,
        _rolloverHints.collateralRoundHint
      )
    );
    if (collateralPrice == 0) return false;

    rolloverDerivative(
      _state,
      derivativeIndex,
      IPoolTypes.PoolSharePriceHints(
        false,
        collateralPrice,
        _rolloverHints.underlyingRoundHintsIndexed,
        _rolloverHints.volatilityRoundHint
      )
    );
    if (_state.pausing == true) return false;

    return true;
  }

  function getOldestDerivativeForRollover(PoolState.State storage _state, uint256 _pointInTime)
    public
    view
    returns (uint256 derivativeIndex)
  {
    derivativeIndex = type(uint256).max;
    uint256 oldest = _pointInTime;
    for (uint256 i = 0; i < _state.liveSet.length; i++) {
      uint256 settlement = _state.liveSet[i].params.settlement;
      if (
        settlement < oldest ||
        (settlement == oldest && derivativeIndex == type(uint256).max) ||
        (settlement == oldest &&
          _state.liveSet[i].sequence.mode == IPoolTypes.Mode.Temp &&
          _state.liveSet[derivativeIndex].sequence.mode != IPoolTypes.Mode.Temp)
      ) {
        derivativeIndex = i;
        oldest = settlement;
      }
    }
  }

  function refreshPoolTo(PoolState.State storage _state, uint256 _pointInTime)
    public
    returns (bool)
  {
    IPoolTypes.PoolSharePriceHints memory poolSharePriceHints = _state
      .createHintsWithCollateralPrice();
    if (poolSharePriceHints.collateralPrice == 0) return false;

    uint256 checks;
    uint256 derivativeIndex = getOldestDerivativeForRollover(_state, _pointInTime);
    while (derivativeIndex != type(uint256).max && checks < HINTS_FREE_ROLLOVER_MAX) {
      rolloverDerivative(_state, derivativeIndex, poolSharePriceHints);
      if (_state.pausing) return false;
      derivativeIndex = getOldestDerivativeForRollover(_state, _pointInTime);
      checks++;
    }

    require(checkWhetherPoolFresh(_state, block.timestamp), "NOTFRESH");
    require(_state.checkPoolCollateralBalance(), "COLERR");

    return true;
  }

  struct VarsB {
    IPoolTypes.SettlementValues settlementValues;
    uint256 settlement;
    uint256 priceReference;
    IPoolTypes.Pair poolPosition;
    IPoolTypes.Pair poolPositionBoned;
    IPoolTypes.Pair newPool;
    bool queueNotProcessed;
    bytes16 newPrimaryPriceRaw;
    IPoolTypes.RolloverTrade rolloverTrade;
    uint256 newPoolPositionValue;
    uint256 newTotalRolloverInAmount;
  }

  // B
  function rolloverDerivative(
    PoolState.State storage _state,
    uint256 _derivativeIndex,
    IPoolTypes.PoolSharePriceHints memory poolSharePriceHints
  ) internal {
    VarsB memory vars;

    IPoolTypes.Derivative storage derivative = _state.liveSet[_derivativeIndex];

    require(block.timestamp >= derivative.params.settlement, "Incorrect time");
    vars.settlement = derivative.params.settlement;
    vars.priceReference = derivative.params.priceReference;
    //I checks later
    //II collateralPrice calculates outside method (poolSharePriceHints.collateralPrice)

    //III
    vars.settlementValues = calcUsdValueAtSettlement(
      derivative,
      poolSharePriceHints.collateralPrice,
      poolSharePriceHints.hintLess
        ? createSingleItemArray(0)
        : createSingleItemArray(poolSharePriceHints.underlyingRoundHintsIndexed[
            _state.getUnderlyingOracleIndexNumber(derivative.config.underlyingOracles[0])
          ])
    );

    //IV
    vars.poolPosition = _state.positionBalances[PoolState.POOL_PORTFOLIO_ID][_derivativeIndex];
    vars.poolPositionBoned = IPoolTypes.Pair(
      PoolState.fromStandard(vars.poolPosition.primary),
      PoolState.fromStandard(vars.poolPosition.complement)
    );

    if (vars.poolPosition.primary != 0 || vars.poolPosition.complement != 0) {
      //I
      uint256 releasedCollateral = PoolState.toStandard(
        ((vars.poolPositionBoned.primary + vars.poolPositionBoned.complement) *
          derivative.params.denomination) / NumLib.BONE
      ) - 1; // decrement by minimal

      _state.balance.collateralLocked -= releasedCollateral;

      uint256 collateralFreeIncrement = PoolState.toStandard(
        (vars.poolPositionBoned.primary *
          vars.settlementValues.value.primary +
          vars.poolPositionBoned.complement *
          vars.settlementValues.value.complement) / poolSharePriceHints.collateralPrice
      );

      if(collateralFreeIncrement > releasedCollateral) {
        collateralFreeIncrement = releasedCollateral;
      }

      _state.balance.collateralFree += collateralFreeIncrement;
      _state.balance.releasedWinnings =
        _state.balance.releasedWinnings +
        releasedCollateral -
        collateralFreeIncrement;

      _state.positionBalances[PoolState.POOL_PORTFOLIO_ID][_derivativeIndex] = IPoolTypes.Pair(0, 0);

      //V
      vars.queueNotProcessed = !processRedemptionQueueAt(
        _state,
        derivative.params.settlement,
        poolSharePriceHints
      );
    }

    //VI
    uint256 newReferencePrice = derivative.config.specification.referencePrice(
      vars.settlementValues.underlyingPrice,
      derivative.sequence.strikePosition
    );
    uint256 newSettlement = derivative.params.settlement + derivative.sequence.settlementDelta;
    derivative.params = IPoolTypes.DerivativeParams(
      newReferencePrice,
      newSettlement,
      derivative.config.specification.denomination(newSettlement, newReferencePrice)
    );

    //VII
    if (
      derivative.sequence.mode == IPoolTypes.Mode.Temp ||
      vars.queueNotProcessed ||
      _state.balance.collateralFree == 0 ||
      derivative.sequence.side == IPoolTypes.Side.Empty ||
      PoolState.toStandard(
        (vars.poolPositionBoned.primary *
          vars.settlementValues.value.complement +
          vars.poolPositionBoned.complement *
          vars.settlementValues.value.primary) / NumLib.BONE
      ) ==
      0 //TODO: should we convert to bone and back here?
    ) {
      //VIII
      _state.setVintageFor(
        _derivativeIndex,
        0,
        0,
        NumLib.div(vars.settlementValues.value.primary, poolSharePriceHints.collateralPrice),
        NumLib.div(vars.settlementValues.value.complement, poolSharePriceHints.collateralPrice),
        vars.priceReference
      );
    } else {
      //VII continue
      vars.rolloverTrade = calculateRolloverTrade(
        _state,
        _derivativeIndex,
        IPoolTypes.DerivativeSettlement(
          vars.settlement,
          vars.settlementValues.value,
          vars.poolPositionBoned
        ),
        int256(poolSharePriceHints.collateralPrice),
        int256(vars.settlementValues.underlyingPrice),
        poolSharePriceHints.hintLess ? 0 : poolSharePriceHints.volatilityRoundHint
      );

      vars.newPool = IPoolTypes.Pair(
        vars.rolloverTrade.outward.complement,
        vars.rolloverTrade.outward.primary
      );

      //VIII
      _state.setVintageFor(
        _derivativeIndex,
        vars.poolPosition.complement == 0
          ? 0
          : NumLib.div(vars.newPool.complement, vars.poolPosition.complement),
        vars.poolPosition.primary == 0
          ? 0
          : NumLib.div(vars.newPool.primary, vars.poolPosition.primary),
        NumLib.div(vars.settlementValues.value.primary, poolSharePriceHints.collateralPrice) -
          (
            vars.poolPosition.complement == 0
              ? 0
              : NumLib.div(vars.rolloverTrade.inward.primary, vars.poolPosition.complement)
          ),
        NumLib.div(vars.settlementValues.value.complement, poolSharePriceHints.collateralPrice) -
          (
            vars.poolPosition.primary == 0
              ? 0
              : NumLib.div(vars.rolloverTrade.inward.complement, vars.poolPosition.primary)
          ),
        vars.priceReference
      );

      //IX
      _state.positionBalances[PoolState.POOL_PORTFOLIO_ID][_derivativeIndex] = vars.newPool;

      vars.newPoolPositionValue =
        (derivative.params.denomination * (vars.newPool.complement + vars.newPool.primary)) /
        NumLib.BONE;
      vars.newTotalRolloverInAmount =
        vars.rolloverTrade.inward.primary +
        vars.rolloverTrade.inward.complement;

      if (
        _state.balance.collateralFree + vars.newTotalRolloverInAmount <
        vars.newPoolPositionValue ||
        _state.balance.releasedWinnings < vars.newTotalRolloverInAmount ||
        !_state.checkPoolCollateralBalance()
      ) {
        _state.updateVintageFor(
          _derivativeIndex,
          _state.getCurrentVintageIndexFor(_derivativeIndex) - 1,
          0,
          0,
          NumLib.div(vars.settlementValues.value.primary, poolSharePriceHints.collateralPrice),
          NumLib.div(vars.settlementValues.value.complement, poolSharePriceHints.collateralPrice),
          vars.priceReference
        );

        _state.positionBalances[PoolState.POOL_PORTFOLIO_ID][_derivativeIndex] = IPoolTypes.Pair(0, 0);
      } else {
        _state.balance.collateralLocked += vars.newPoolPositionValue;
        _state.balance.collateralFree =
          _state.balance.collateralFree +
          vars.newTotalRolloverInAmount -
          vars.newPoolPositionValue;
        _state.balance.releasedWinnings -= vars.newTotalRolloverInAmount;
      }
    }

    emitRolledOverDerivative(_state, vars, _derivativeIndex, derivative.params);
  }

  function emitRolledOverDerivative(
    PoolState.State storage _state,
    VarsB memory vars,
    uint256 _derivativeIndex,
    IPoolTypes.DerivativeParams memory _newDerivativeParams
  ) internal {
    uint256 newVintageIndex = _state.getCurrentVintageIndexFor(_derivativeIndex) - 1;

    emit RolledOverDerivative(
      _derivativeIndex,
      block.timestamp,
      vars.settlement,
      vars.poolPosition,
      _state.positionBalances[PoolState.POOL_PORTFOLIO_ID][_derivativeIndex],
      newVintageIndex,
      _state.getVintageBy(_derivativeIndex, newVintageIndex),
      _newDerivativeParams,
      vars.settlementValues,
      vars.rolloverTrade
    );
  }

  function calcUsdValueAtSettlement(
    IPoolTypes.Derivative memory derivative,
    uint256 collateralPrice,
    uint256[] memory _underlyingRoundHints
  ) internal view returns (IPoolTypes.SettlementValues memory) {
    (uint256 primarySplit, int256[] memory underlyingEnds) = derivative
      .config
      .collateralSplit
      .split(
        derivative.config.underlyingOracles,
        derivative.config.underlyingOracleIterators,
        makeIntArrayFrom(int256(derivative.params.priceReference)),
        derivative.params.settlement,
        _underlyingRoundHints
      );
    primarySplit = range(primarySplit);
    uint256 complementSplit = NumLib.BONE - primarySplit;
    uint256 underlyingPrice = uint256(underlyingEnds[0]); //TODO: Process negative price

    return
      IPoolTypes.SettlementValues(
        IPoolTypes.Pair(
          (((primarySplit * collateralPrice) / NumLib.BONE) * derivative.params.denomination) /
            NumLib.BONE,
          (((complementSplit * collateralPrice) / NumLib.BONE) * derivative.params.denomination) /
            NumLib.BONE
        ),
        underlyingPrice
      );
  }

  function calculateRolloverTrade(
    PoolState.State storage _state,
    uint256 _derivativeIndex,
    IPoolTypes.DerivativeSettlement memory _derivativeSettlement,
    int256 _collateralPrice,
    int256 _underlyingPrice,
    uint256 _volatilityRoundHint
  ) internal returns (IPoolTypes.RolloverTrade memory) {
    return
      convertRolloverTradeFromBONE(
        ITerms(_state.liveSet[_derivativeIndex].terms).calculateRolloverTrade(
          _state.makePoolSnapshot(),
          _derivativeIndex,
          _derivativeSettlement,
          IPoolTypes.OtherPrices(_collateralPrice, _underlyingPrice, _volatilityRoundHint)
        )
      );
  }

  function checkWhetherPoolFresh(PoolState.State storage _state, uint256 _pointInTime)
    internal
    view
    returns (bool)
  {
    uint256 derivativeIndex = getOldestDerivativeForRollover(_state, _pointInTime);
    return derivativeIndex == type(uint256).max;
  }

  function makeIntArrayFrom(int256 _value) internal pure returns (int256[] memory array) {
    array = new int256[](1);
    array[0] = _value;
  }

  function range(uint256 _split) internal pure returns (uint256) {
    if (_split > NumLib.BONE) {
      return NumLib.BONE;
    }
    return _split;
  }

  function convertRolloverTradeFromBONE(IPoolTypes.RolloverTrade memory _rolloverTrade)
    internal
    pure
    returns (IPoolTypes.RolloverTrade memory)
  {
    return
      IPoolTypes.RolloverTrade(
        IPoolTypes.Pair(
          PoolState.toStandard(_rolloverTrade.inward.primary),
          PoolState.toStandard(_rolloverTrade.inward.complement)
        ),
        IPoolTypes.Pair(
          PoolState.toStandard(_rolloverTrade.outward.primary),
          PoolState.toStandard(_rolloverTrade.outward.complement)
        )
      );
  }

  function createSingleItemArray(uint256 item) internal pure returns (uint256[] memory array) {
    array = new uint256[](1);
    array[0] = item;
  }
}
