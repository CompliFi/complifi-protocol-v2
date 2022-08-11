// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./RedemptionQueue.sol";
import "./IPoolTypes.sol";
import "./IPoolConfigTypes.sol";
import "../poolBuilder/IPoolBuilderTypes.sol";
import "../math/NumLib.sol";
import "../terms/ITerms.sol";

//import "hardhat/console.sol";

library PoolState {
  using RedemptionQueue for RedemptionQueue.Queue;
  using SafeERC20 for IERC20;

  uint256 public constant POOL_SHARE_PRICE_APPROXIMATION = 10**21; // 1/10^(26-21)
  uint256 public constant P_MIN = 100000000000000000000; // 0.000001
  uint256 public constant EXCESS_ORACLES_PER_POOL = 100;
  event PausedByOracle(
    address oracle,
    uint256 roundHint,
    uint256 requestedTimestamp,
    uint80 roundId,
    int256 answer,
    uint256 timestamp
  );
  event AddedDerivative(
    uint256 indexed derivativeIndex,
    uint256 indexed timestamp,
    IPoolTypes.Derivative derivative
  );

  uint256 public constant POOL_PORTFOLIO_ID = 0;

  struct State {
    IPoolConfigTypes.PoolConfig config;
    IPoolTypes.PoolBalance balance;
    RedemptionQueue.Queue redemptionQueue;
    IPoolTypes.Derivative[] liveSet;
    mapping(uint256 => IPoolTypes.Vintage[]) _oldSet;
    // portfolio id => derivativeIndex => balance
    mapping(uint256 => mapping(uint256 => IPoolTypes.Pair)) positionBalances;
    // portfolio id => derivativeIndex => vintageIndex
    mapping(uint256 => mapping(uint256 => uint256)) _vintages;
    mapping(address => uint256) _releasedLiquidity;
    bool pausing;
  }

  function init(
    State storage _state,
    address _poolShare,
    address _traderPortfolio,
    address _volatilityEvolution,
    address _underlyingLiquidityValuer,
    address _exposure,
    IPoolBuilderTypes.FeeParams memory _feeParams,
    IPoolBuilderTypes.CollateralParams memory _collateralParams,
    uint256 _minExitAmount
  ) public {
    _state.config.poolShare = IERC20MintedBurnable(_poolShare);

    _state.config.traderPortfolio = ITraderPortfolio(_traderPortfolio);

    require(_volatilityEvolution != address(0), "VOLEVOADDR");
    _state.config.volatilityEvolution = IVolatilityEvolution(_volatilityEvolution);

    _state.config.underlyingLiquidityValuer = IUnderlyingLiquidityValuer(_underlyingLiquidityValuer);

    require(_exposure != address(0), "EXPADDR");
    _state.config.exposure = IExposure(_exposure);

    _state.config.protocolFee = _feeParams.protocolFee;
    require(_feeParams.feeWallet != address(0), "FEEWADDR");
    _state.config.feeWallet = _feeParams.feeWallet;

    require(_collateralParams.collateralToken != address(0), "COLTADDR");
    _state.config.collateralToken = IERC20(_collateralParams.collateralToken);
    _state.config.collateralDecimals = IERC20Metadata(_collateralParams.collateralToken)
      .decimals();

    require(_collateralParams.collateralOracle != address(0), "COLOADDR");
    _state.config.collateralOracle = _collateralParams.collateralOracle;

    require(_collateralParams.collateralOracleIterator != address(0), "COLOIADDR");
    _state.config.collateralOracleIterator = IOracleIterator(
      _collateralParams.collateralOracleIterator
    );

    _state.config.minExitAmount = _minExitAmount;

    _state.redemptionQueue.init();
  }

  function getUnderlyingOracleIndex(State storage _state) public view returns (address[] memory) {
    address[] memory underlyingOracleIndexExcess = new address[](EXCESS_ORACLES_PER_POOL);
    uint256 excessOracleCount = 0;
    for(uint256 i = 0; i < _state.liveSet.length; i++) {
      address[] memory underlyingOracles = _state.liveSet[i].config.underlyingOracles;
      for(uint256 j = 0; j < underlyingOracles.length; j++) {
        underlyingOracleIndexExcess[excessOracleCount] = underlyingOracles[j];
        excessOracleCount += 1;
      }
    }

    uint256 uniqueOracleCount = 0;
    for(uint256 i = 0; i < excessOracleCount; i++ ) {
      address oracle = underlyingOracleIndexExcess[i];
      if(oracle == address(0)) continue;
      uniqueOracleCount += 1;
      for(uint256 j = i + 1; j < excessOracleCount; j++ ) {
        if(oracle == underlyingOracleIndexExcess[j]) {
          delete underlyingOracleIndexExcess[j];
        }
      }
    }

    address[] memory underlyingOracleIndex = new address[](uniqueOracleCount);
    uint256 oracleCount = 0;
    for(uint256 i = 0; i < excessOracleCount; i++ ) {
      address oracle = underlyingOracleIndexExcess[i];
      if(oracle == address(0)) continue;
      underlyingOracleIndex[oracleCount] = oracle;
      oracleCount += 1;
    }
    require(uniqueOracleCount == oracleCount, "UNIQORACL");

    return underlyingOracleIndex;
  }

  function getUnderlyingOracleIndexNumber(State storage _state, address _underlyingOracle) public view returns (uint256) {
    address[] memory underlyingOracleIndex = getUnderlyingOracleIndex(_state);

    for(uint256 i = 0; i < underlyingOracleIndex.length; i++ ) {
      if(underlyingOracleIndex[i] == _underlyingOracle) return i;
    }

    revert("UNDORACLIND");
  }

  function getCollateralValue(State storage _state) public returns (uint256) {
    uint256 collateralPrice = getLatestAnswer(
      _state,
      _state.config.collateralOracleIterator,
      _state.config.collateralOracle
    );
    return
    (fromStandard(_state.balance.collateralFree + _state.balance.collateralLocked) *
    collateralPrice) / NumLib.BONE;
  }

  function getAllRedemptionRequests(State storage _state)
    external
    view
    returns (RedemptionQueue.Request[] memory)
  {
    return _state.redemptionQueue.getAll();
  }

  function addDerivative(
    State storage _state,
    IPoolTypes.DerivativeConfig memory _derivativeConfig,
    address _terms,
    IPoolTypes.Sequence memory sequence,
    uint256 pRef,
    uint256 settlement
  ) public returns (uint256 derivativeIndex) {
    require(
      _derivativeConfig.collateralToken == address(_state.config.collateralToken),
      "COLTADDR"
    );

    IPoolTypes.Derivative memory derivative = IPoolTypes.Derivative(
      _derivativeConfig,
      _terms,
      sequence,
      IPoolTypes.DerivativeParams(
        pRef,
        settlement,
        _derivativeConfig.specification.denomination(settlement, pRef)
      )
    );

    _state.liveSet.push(derivative);
    derivativeIndex = _state.liveSet.length - 1;
    emit AddedDerivative(derivativeIndex, block.timestamp, derivative);
  }

  function withdrawReleasedLiquidity(PoolState.State storage _state, uint256 _collateralAmount)
  public
  {
    if (_collateralAmount == 0) return;

    uint256 collateralAmountStandard = fromCollateralToStandard(_state, _collateralAmount);
    if(collateralAmountStandard > getReleasedLiquidity(_state, msg.sender)) {
      collateralAmountStandard = getReleasedLiquidity(_state, msg.sender);
    }
    if (collateralAmountStandard == 0) return;

    unchecked {
      decreaseReleasedLiquidity(_state, msg.sender, collateralAmountStandard);
    }
    _state.balance.releasedLiquidityTotal -= collateralAmountStandard;

    require(checkPoolCollateralBalance(_state), "COLERR");

    pushCollateral(
      address(_state.config.collateralToken),
      msg.sender,
      fromStandardToCollateral(_state, collateralAmountStandard)
    );
  }

  //D
  function calculatePoolSharePrice(
    PoolState.State storage _state,
    uint256 _pointInTime,
    IPoolTypes.PoolSharePriceHints memory _poolSharePriceHints
  ) internal returns (uint256 poolSharePrice, uint256 poolDerivativesValue) {
    if (_state.config.poolShare.totalSupply() == 0) return (_poolSharePriceHints.collateralPrice, 0);

    poolDerivativesValue = 0;
    for (uint256 i = 0; i < _state.liveSet.length; i++) {
      poolDerivativesValue += calcDerivativeValue(_state, _pointInTime, i, _poolSharePriceHints);
    }

    uint256 poolValue = calcPoolCollateralValue(_state, _poolSharePriceHints.collateralPrice) + poolDerivativesValue;

    poolSharePrice =
      max(
        PoolState.P_MIN,
        (poolValue * NumLib.BONE) / fromStandard(_state.config.poolShare.totalSupply())
      );
  }

  function getPoolSharePrice(PoolState.State storage _state)
  public
  returns (
    uint256 poolSharePrice,
    uint256 poolDerivativesValue,
    IPoolTypes.PoolSharePriceHints memory poolSharePriceHints
  )
  {
    poolSharePriceHints = createHintsWithCollateralPrice(_state);
    if (poolSharePriceHints.collateralPrice == 0) return (0, 0, poolSharePriceHints);

    if(_state.config.poolShare.totalSupply() == 0) return (poolSharePriceHints.collateralPrice, 0, poolSharePriceHints);

    (poolSharePrice, poolDerivativesValue) = calculatePoolSharePrice(_state, block.timestamp, poolSharePriceHints);
  }

  function getDerivativePrice(PoolState.State storage _state, uint256 _derivativeIndex)
  public
  returns (IPoolTypes.PricePair memory)
  {
    uint256 pintInTime = block.timestamp;

    IPoolTypes.PoolSharePriceHints memory poolSharePriceHints = createHintsWithCollateralPrice(_state);
    if (poolSharePriceHints.collateralPrice == 0) return IPoolTypes.PricePair(0, 0);

    IPoolTypes.Derivative memory derivative = _state.liveSet[_derivativeIndex];

    uint256 underlyingPrice = uint256(
      getHintedAnswer(
        _state,
        IOracleIterator(derivative.config.underlyingOracleIterators[0]),
        derivative.config.underlyingOracles[0],
        pintInTime,
        poolSharePriceHints.hintLess ? 0 : poolSharePriceHints.underlyingRoundHintsIndexed[
          getUnderlyingOracleIndexNumber(_state, derivative.config.underlyingOracles[0])
        ]
      )
    );
    if (underlyingPrice == 0) return IPoolTypes.PricePair(0, 0);

    return
    ITerms(derivative.terms).calculatePrice(
      pintInTime,
      derivative,
      IPoolTypes.Side.Empty,
      IPoolTypes.PriceType.mid,
      IPoolTypes.OtherPrices(
        int256(poolSharePriceHints.collateralPrice),
        int256(underlyingPrice),
        poolSharePriceHints.hintLess ? 0 : poolSharePriceHints.volatilityRoundHint
      ),
      _state.config.volatilityEvolution
    );
  }

  function calcPoolCollateralValue(PoolState.State storage _state, uint256 collateralPrice) public view returns(uint256) {
    return (collateralPrice * fromStandard(_state.balance.collateralFree)) / NumLib.BONE;
  }

  function calcDerivativeValue(
    PoolState.State storage _state,
    uint256 _pointInTime,
    uint256 _derivativeIndex,
    IPoolTypes.PoolSharePriceHints memory _poolSharePriceHints
  ) internal returns (uint256) {
    IPoolTypes.Pair memory poolPosition = _state.positionBalances[PoolState.POOL_PORTFOLIO_ID][
      _derivativeIndex
    ];
    if (poolPosition.primary == 0 && poolPosition.complement == 0) return 0;

    IPoolTypes.Derivative memory derivative = _state.liveSet[_derivativeIndex];

    uint256 underlyingPrice = uint256(
      getHintedAnswer(
        _state,
        IOracleIterator(derivative.config.underlyingOracleIterators[0]),
        derivative.config.underlyingOracles[0],
        _pointInTime,
        _poolSharePriceHints.hintLess ? 0 : _poolSharePriceHints.underlyingRoundHintsIndexed[
          getUnderlyingOracleIndexNumber(_state, derivative.config.underlyingOracles[0])
        ]
      )
    );

    if (underlyingPrice == 0) return 0;

    IPoolTypes.PricePair memory derivativePrices = ITerms(derivative.terms).calculatePrice(
      _pointInTime,
      derivative,
      IPoolTypes.Side.Empty,
      IPoolTypes.PriceType.mid,
      IPoolTypes.OtherPrices(
        int256(_poolSharePriceHints.collateralPrice),
        int256(underlyingPrice),
        _poolSharePriceHints.hintLess ? 0 : _poolSharePriceHints.volatilityRoundHint
      ),
      _state.config.volatilityEvolution
    );

    uint256 derivativeValue = 0;
    if (poolPosition.primary > 0) {
      derivativeValue +=
        (fromStandard(poolPosition.primary) * uint256(derivativePrices.primary)) /
        NumLib.BONE;
    }

    if (poolPosition.complement > 0) {
      derivativeValue +=
        (fromStandard(poolPosition.complement) * uint256(derivativePrices.complement)) /
        NumLib.BONE;
    }

    return derivativeValue;
  }

  function max(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a > b) {
      return a;
    } else {
      return b;
    }
  }

  function subMod(uint256 a, uint256 b) public pure returns (uint256) {
    unchecked{
      if (a > b) {
        return a - b;
      } else {
        return b - a;
      }
    }
  }

  function getCollateralExposureLimit(PoolState.State storage _state) public view returns (uint256) {
    return
    toStandard(
      _state.config.exposure.calcCollateralExposureLimit(
        _state.liveSet,
        getDerivativePoolPositionsBonified(_state)
      )
    );
  }

  function createHintsWithCollateralPrice(PoolState.State storage _state)
    public
    returns (IPoolTypes.PoolSharePriceHints memory)
  {
    uint256 collateralPrice = uint256(
      getLatestAnswer(
        _state,
        _state.config.collateralOracleIterator,
        _state.config.collateralOracle
      )
    );

    IPoolTypes.PoolSharePriceHints memory poolSharePriceHints;
    poolSharePriceHints.hintLess = true;
    poolSharePriceHints.collateralPrice = collateralPrice;
    return poolSharePriceHints;
  }

  function checkPoolCollateralBalance(PoolState.State storage _state) public view returns (bool) {
    return
      fromCollateralToStandard(_state, _state.config.collateralToken.balanceOf(address(this))) >=
      (_state.balance.collateralLocked +
        _state.balance.collateralFree +
        _state.balance.releasedLiquidityTotal +
        _state.balance.releasedWinnings);
  }

  function getDerivativePoolPositionsBonified(State storage _state)
    public
    view
    returns (IPoolTypes.Pair[] memory _balances)
  {
    _balances = new IPoolTypes.Pair[](_state.liveSet.length);
    for (uint256 i = 0; i < _state.liveSet.length; i++) {
      _balances[i] = IPoolTypes.Pair(
        fromStandard(_state.positionBalances[POOL_PORTFOLIO_ID][i].primary),
        fromStandard(_state.positionBalances[POOL_PORTFOLIO_ID][i].complement)
      );
    }
  }

  function getReleasedLiquidity(State storage _state, address user) public view returns (uint256) {
    return _state._releasedLiquidity[user];
  }

  function increaseReleasedLiquidity(
    State storage _state,
    address user,
    uint256 amount
  ) public {
    _state._releasedLiquidity[user] += amount;
  }

  function decreaseReleasedLiquidity(
    State storage _state,
    address user,
    uint256 amount
  ) public {
    _state._releasedLiquidity[user] -= amount;
  }

  function getCurrentVintageIndexFor(State storage _state, uint256 _derivativeIndex)
    public
    view
    returns (uint256)
  {
    return _state._oldSet[_derivativeIndex].length + 1;
  }

  function setVintageFor(
    State storage _state,
    uint256 _derivativeIndex,
    uint256 _rollRatePrimary,
    uint256 _rollRateComplement,
    uint256 _releaseRatePrimary,
    uint256 _releaseRateComplement,
    uint256 _priceReference
  ) public {
    _state._oldSet[_derivativeIndex].push(
      IPoolTypes.Vintage(
        IPoolTypes.Pair(_rollRatePrimary, _rollRateComplement),
        IPoolTypes.Pair(_releaseRatePrimary, _releaseRateComplement),
        _priceReference
      )
    );
  }

  function updateVintageFor(
    State storage _state,
    uint256 _derivativeIndex,
    uint256 _vintageIndex,
    uint256 _rollRatePrimary,
    uint256 _rollRateComplement,
    uint256 _releaseRatePrimary,
    uint256 _releaseRateComplement,
    uint256 _priceReference
  ) public {
    _state._oldSet[_derivativeIndex][_vintageIndex - 1] = IPoolTypes.Vintage(
      IPoolTypes.Pair(_rollRatePrimary, _rollRateComplement),
      IPoolTypes.Pair(_releaseRatePrimary, _releaseRateComplement),
      _priceReference
    );
  }

  function getVintageBy(
    State storage _state,
    uint256 _derivativeIndex,
    uint256 _vintageIndex
  ) public view returns (IPoolTypes.Vintage memory) {
    require(_vintageIndex >= 1, "UPDBADVIN");
    return _state._oldSet[_derivativeIndex][_vintageIndex - 1];
  }

  function getUserPositionVintageIndex(
    State storage _state,
    uint256 _userPortfolio,
    uint256 _derivativeIndex
  ) public view returns (uint256) {
    return _state._vintages[_userPortfolio][_derivativeIndex];
  }

  function setUserPositionVintageIndex(
    State storage _state,
    uint256 _userPortfolio,
    uint256 _derivativeIndex,
    uint256 _vintageIndex
  ) public {
    _state._vintages[_userPortfolio][_derivativeIndex] = _vintageIndex;
  }

  function makePoolSnapshot(State storage _state)
    public
    view
    returns (IPoolTypes.PoolSnapshot memory)
  {
    return
      IPoolTypes.PoolSnapshot(
        _state.liveSet,
        address(_state.config.exposure),
        fromStandard(_state.balance.collateralLocked),
        fromStandard(_state.balance.collateralFree),
        getDerivativePoolPositionsBonified(_state),
        _state.config.volatilityEvolution,
        _state.config.underlyingLiquidityValuer
      );
  }

  function checkIfRedemptionQueueEmpty(State storage _state) public view returns (bool) {
    return _state.redemptionQueue.empty();
  }

  function moveDerivative(
    State storage _state,
    uint256 senderPortfolio,
    uint256 recipientPortfolio,
    uint256 amount,
    uint256 derivativeIndex,
    IPoolTypes.Side side
  ) public {
    uint256 senderBalance;
    if (side == IPoolTypes.Side.Primary) {
      senderBalance = _state.positionBalances[senderPortfolio][derivativeIndex].primary;
      require(senderBalance >= amount, "DERPRINSUFBAL");
      unchecked {
        _state.positionBalances[senderPortfolio][derivativeIndex].primary = senderBalance - amount;
      }
      _state.positionBalances[recipientPortfolio][derivativeIndex].primary += amount;
    } else if (side == IPoolTypes.Side.Complement) {
      senderBalance = _state.positionBalances[senderPortfolio][derivativeIndex].complement;
      require(senderBalance >= amount, "DERCOINSUFBAL");
      unchecked {
        _state.positionBalances[senderPortfolio][derivativeIndex].complement = senderBalance - amount;
      }
      _state.positionBalances[recipientPortfolio][derivativeIndex].complement += amount;
    }
  }

  function getLatestAnswerByDerivative(
    State storage _state,
    IPoolTypes.Derivative memory derivative
  ) public returns (uint256) {
    return
      getLatestAnswer(
        _state,
        IOracleIterator(derivative.config.underlyingOracleIterators[0]),
        derivative.config.underlyingOracles[0]
      );
  }

  function getLatestAnswer(
    State storage _state,
    IOracleIterator _iterator,
    address _oracle
  ) public returns (uint256) {
    return getHintedAnswer(_state, _iterator, _oracle, block.timestamp, 0);
  }

  function getHintedAnswer(
    State storage _state,
    IOracleIterator _iterator,
    address _oracle,
    uint256 _timestamp,
    uint256 _roundHint
  ) public returns (uint256) {
    (uint80 roundId, int256 value, uint256 timestamp) = _iterator.getRound(
      _oracle,
      _timestamp,
      _roundHint
    );
    if (value == type(int256).min) {
      string memory reason = string(
        abi.encodePacked(
          "Iterator missed ",
          _oracle,
          " ",
          Strings.toString(_roundHint),
          " ",
          Strings.toString(_timestamp)
        )
      );
      assembly {
        revert(add(32, reason), mload(reason))
      }
    }
    if (value <= 0) {
      _state.pausing = true;
      emit PausedByOracle(_oracle, _roundHint, _timestamp, roundId, value, timestamp);
      return 0;
    }
    if (uint256(value) < P_MIN) {
      return P_MIN;
    }

    return uint256(value);
  }

  function pullCollateral(
    address erc20,
    address from,
    uint256 amount
  ) public returns (uint256) {
    uint256 balanceBefore = IERC20(erc20).balanceOf(address(this));
    IERC20(erc20).safeTransferFrom(from, address(this), amount);
    // Calculate the amount that was *actually* transferred
    uint256 balanceAfter = IERC20(erc20).balanceOf(address(this));
    require(balanceAfter >= balanceBefore, "COLINOVER");
    return balanceAfter - balanceBefore; // underflow already checked above, just subtract
  }

  function pushCollateral(
    address erc20,
    address to,
    uint256 amount
  ) public {
    IERC20(erc20).safeTransfer(to, amount);
  }

  function convertUpDecimals(
    uint256 _value,
    uint8 _decimalsFrom,
    uint8 _decimalsTo
  ) public pure returns (uint256) {
    require(_decimalsFrom <= _decimalsTo, "BADDECIM");
    return _value * (10**(_decimalsTo - _decimalsFrom));
  }

  function convertDownDecimals(
    uint256 _value,
    uint8 _decimalsFrom,
    uint8 _decimalsTo
  ) public pure returns (uint256) {
    require(_decimalsFrom <= _decimalsTo, "BADDECIM");
    return _value / (10**(_decimalsTo - _decimalsFrom));
  }

  function fromCollateralToStandard(State storage _state, uint256 _value)
    public
    view
    returns (uint256)
  {
    return convertUpDecimals(_value, _state.config.collateralDecimals, NumLib.STANDARD_DECIMALS);
  }

  function fromStandardToCollateral(State storage _state, uint256 _value)
    public
    view
    returns (uint256)
  {
    return convertDownDecimals(_value, _state.config.collateralDecimals, NumLib.STANDARD_DECIMALS);
  }

  function fromCollateral(State storage _state, uint256 _value) public view returns (uint256) {
    return convertUpDecimals(_value, _state.config.collateralDecimals, NumLib.BONE_DECIMALS);
  }

  function toCollateral(State storage _state, uint256 _value) public view returns (uint256) {
    return convertDownDecimals(_value, _state.config.collateralDecimals, NumLib.BONE_DECIMALS);
  }

  function fromStandard(uint256 _value) public pure returns (uint256) {
    return convertUpDecimals(_value, NumLib.STANDARD_DECIMALS, NumLib.BONE_DECIMALS);
  }

  function toStandard(uint256 _value) public pure returns (uint256) {
    return convertDownDecimals(_value, NumLib.STANDARD_DECIMALS, NumLib.BONE_DECIMALS);
  }
}
