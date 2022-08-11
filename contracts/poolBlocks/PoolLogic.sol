// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PoolState.sol";
import "./PoolRolloverLogic.sol";
import "./IPoolTypes.sol";
import "../terms/ITermsTypes.sol";
import "../terms/ITerms.sol";
import "../math/NumLib.sol";

//import "hardhat/console.sol";

library PoolLogic {
  using PoolState for PoolState.State;
  using PoolRolloverLogic for PoolState.State;
  using RedemptionQueue for RedemptionQueue.Queue;

  event JoinedPool(
    address indexed user,
    uint256 indexed timestamp,
    uint256 collateralAmount,
    uint256 poolShareAmountOut,
    uint256 poolSharePrice
  );
  event CreatedRedemptionQueueItem(
    address indexed user,
    uint256 indexed timestamp,
    uint256 poolShareAmountIn
  );

  event MintedDerivative(
    uint256 indexed portfolioId,
    uint256 indexed derivativeIndex,
    IPoolTypes.Side indexed side,
    uint256 collateralAmount,
    uint256 derivativeAmount,
    uint256 collateralFeeAmount,
    uint256 currentVintageIndex
  );
  event ProcessedDerivative(
    uint256 indexed portfolioId,
    uint256 indexed derivativeIndex,
    uint256 indexed timestamp,
    IPoolTypes.Pair poolPosition,
    IPoolTypes.Pair newPoolPosition,
    uint256 newVintage
  );
  event MovedDerivative(
    uint256 fromPortfolioId,
    uint256 indexed toPortfolioId,
    uint256 indexed derivativeIndex,
    IPoolTypes.Side indexed side,
    uint256 amount
  );
  event BurnedDerivative(
    uint256 indexed portfolioId,
    uint256 indexed derivativeIndex,
    IPoolTypes.Side indexed side,
    uint256 derivativeAmount,
    uint256 collateralAmount,
    uint256 collateralFeeAmount
  );

  function moveDerivativeSafely(
    PoolState.State storage _state,
    address _from,
    uint256 _fromPortfolio,
    address _to,
    uint256 _toPortfolio,
    uint256 _amount,
    uint256 _derivativeIndex,
    IPoolTypes.Side _side
  ) public {
    if (!_state.refreshPoolTo(block.timestamp)) return;

    require(_to != address(0), "TOEMPTY");

    processUserPositionVintages(_state, _from, _fromPortfolio, _derivativeIndex);
    processUserPositionVintages(_state, _to, _toPortfolio, _derivativeIndex);

    _state.moveDerivative(_fromPortfolio, _toPortfolio, _amount, _derivativeIndex, _side);
    emit MovedDerivative(_fromPortfolio, _toPortfolio, _derivativeIndex, _side, _amount);
  }

  function processUserPositions(
    PoolState.State storage _state,
    address _user,
    uint256 _userPortfolio,
    uint256[] memory _derivativeIndexes
  ) public {
    for (uint256 i = 0; i < _derivativeIndexes.length; i++) {
      processUserPositionVintages(_state, _user, _userPortfolio, _derivativeIndexes[i]);
    }
  }

  function processUserPositionVintages(
    PoolState.State storage _state,
    address _user,
    uint256 _userPortfolio,
    uint256 _derivativeIndex
  ) public {
    if (!_state.refreshPoolTo(block.timestamp)) return;

    if (
      _state.positionBalances[_userPortfolio][_derivativeIndex].primary == 0 &&
      _state.positionBalances[_userPortfolio][_derivativeIndex].complement == 0
    ) return;

    uint256 currentVintageIndex = _state.getCurrentVintageIndexFor(_derivativeIndex);
    uint256 vintageIndex = _state.getUserPositionVintageIndex(_userPortfolio, _derivativeIndex);

    uint256 releasedCollateral = 0;
    while (vintageIndex < currentVintageIndex) {
      releasedCollateral += processPositionOnceFor(_state, _userPortfolio, _derivativeIndex);
      vintageIndex = _state.getUserPositionVintageIndex(_userPortfolio, _derivativeIndex);
    }

    uint256 releasedCollateralConverted = _state.fromStandardToCollateral(releasedCollateral);
    if (releasedCollateralConverted > 0) {
      _state.config.collateralToken.transfer(
        _user,
        releasedCollateralConverted
      );
    }
  }

  // C
  function processPositionOnceFor(
    PoolState.State storage _state,
    uint256 portfolioId,
    uint256 derivativeIndex
  ) internal returns (uint256 newVintageIndex) {
    uint256 userPositionVintageIndex = _state.getUserPositionVintageIndex(portfolioId, derivativeIndex);
    require(userPositionVintageIndex >= 1, "BADVINTIND");
    IPoolTypes.Vintage memory vintage = _state.getVintageBy(
      derivativeIndex,
      userPositionVintageIndex
    );

    IPoolTypes.Pair memory position = _state.positionBalances[portfolioId][derivativeIndex];

    uint256 collateralChange = (position.primary *
      vintage.releaseRate.primary +
      position.complement *
      vintage.releaseRate.complement) / NumLib.BONE;

    if (collateralChange > _state.balance.releasedWinnings) {
      collateralChange = _state.balance.releasedWinnings;
    }

    _state.balance.releasedWinnings -= collateralChange;

    _state.positionBalances[portfolioId][derivativeIndex] = IPoolTypes.Pair(
      (position.primary * vintage.rollRate.primary) / NumLib.BONE,
      (position.complement * vintage.rollRate.complement) / NumLib.BONE
    );

    _state.setUserPositionVintageIndex(portfolioId, derivativeIndex, userPositionVintageIndex + 1);

    require(_state.checkPoolCollateralBalance(), "COLERR");

    emit ProcessedDerivative(
      portfolioId,
      derivativeIndex,
      block.timestamp,
      position,
      _state.positionBalances[portfolioId][derivativeIndex],
      userPositionVintageIndex + 1
    );

    return collateralChange;
  }

  function calculateOutAmount(
    PoolState.State storage _state,
    uint256 derivativeIndex,
    IPoolTypes.Side side,
    uint256 inAmount,
    bool _poolReceivesCollateral,
    uint256 collateralPrice,
    uint256 underlyingPrice
  ) public returns (uint256) {
    uint256 outAmount = ITerms(_state.liveSet[derivativeIndex].terms).calculateOutAmount(
      _state.makePoolSnapshot(),
      _poolReceivesCollateral ? _state.fromCollateral(inAmount) : PoolState.fromStandard(inAmount),
      derivativeIndex,
      side,
      _poolReceivesCollateral,
      IPoolTypes.OtherPrices(
        int256(collateralPrice), //TODO: switch all math to uint256
        int256(underlyingPrice),
        0 // last volatility value
      )
    );

    return
      _poolReceivesCollateral ? PoolState.toStandard(outAmount) : _state.toCollateral(outAmount);
  }

  function mergePortfolios(
    PoolState.State storage _state,
    address _from,
    address _to,
    uint256 _tokenId,
    uint256 _existedTokenId
  ) public {
    for (uint256 derivativeIndex = 0; derivativeIndex < _state.liveSet.length; derivativeIndex++) {
      IPoolTypes.Pair memory balance = _state.positionBalances[_tokenId][derivativeIndex];
      bool hasAnyBalances = balance.primary > 0 || balance.complement > 0;
      if (hasAnyBalances) {
        processUserPositionVintages(_state, _from, _tokenId, derivativeIndex);
        processUserPositionVintages(_state, _to, _existedTokenId, derivativeIndex);
        //reread position balance
        balance = _state.positionBalances[_tokenId][derivativeIndex];
      }
      if (balance.primary > 0) {
        _state.moveDerivative(
          _tokenId,
          _existedTokenId,
          balance.primary,
          derivativeIndex,
          IPoolTypes.Side.Primary
        );
        emit MovedDerivative(
          _tokenId,
          _existedTokenId,
          derivativeIndex,
          IPoolTypes.Side.Primary,
          balance.primary
        );
      }
      if (balance.complement > 0) {
        _state.moveDerivative(
          _tokenId,
          _existedTokenId,
          balance.complement,
          derivativeIndex,
          IPoolTypes.Side.Complement
        );
        emit MovedDerivative(
          _tokenId,
          _existedTokenId,
          derivativeIndex,
          IPoolTypes.Side.Complement,
          balance.complement
        );
      }
      if (hasAnyBalances) {
        delete _state.positionBalances[_tokenId][derivativeIndex];
      }
    }
  }

  function processRedemptionQueueSimple(PoolState.State storage _state) public returns (bool) {
    IPoolTypes.PoolSharePriceHints memory poolSharePriceHints = _state
      .createHintsWithCollateralPrice();
    if (poolSharePriceHints.collateralPrice == 0) return false;

    return _state.processRedemptionQueueAt(block.timestamp, poolSharePriceHints);
  }

  function processRedemptionQueue(
    PoolState.State storage _state,
    IPoolTypes.RolloverHints[] memory _rolloverHintsList
  ) public {
    _state.rolloverOldestDerivativeBatch(block.timestamp, _rolloverHintsList);

    if (!_state.refreshPoolTo(block.timestamp)) return;

    processRedemptionQueueSimple(_state);
  }

  // 2
  function joinSimple(
    PoolState.State storage _state,
    uint256 _collateralAmount,
    uint256 _minPoolShareAmountOut
  ) public {
    if (!_state.refreshPoolTo(block.timestamp)) return;

    (
      uint256 poolSharePrice,
      uint256 poolDerivativesValue,
      IPoolTypes.PoolSharePriceHints memory poolSharePriceHints
    ) = _state.getPoolSharePrice();

    if (poolSharePrice == 0) return;

    require(poolSharePriceHints.collateralPrice >= PoolState.P_MIN, "COLPMIN");
    require(poolSharePrice >= PoolState.P_MIN, "PTPMIN");

    uint256 poolShareAmountOut = PoolState.toStandard((poolSharePriceHints.collateralPrice * _state.fromCollateral(_collateralAmount)) / poolSharePrice);

    require(poolShareAmountOut >= _minPoolShareAmountOut, "MINLPOUT");

    PoolState.pullCollateral(
      address(_state.config.collateralToken),
      msg.sender,
      _collateralAmount
    );
    _state.balance.collateralFree += _state.fromCollateralToStandard(_collateralAmount);

    _state.config.poolShare.mint(address(this), poolShareAmountOut);
    _state.config.poolShare.transfer(msg.sender, poolShareAmountOut);

    uint256 poolSharePriceAfter = (_state.calcPoolCollateralValue(poolSharePriceHints.collateralPrice) + poolDerivativesValue) * NumLib.BONE
      / PoolState.fromStandard(_state.config.poolShare.totalSupply());

    require(PoolState.subMod(poolSharePriceAfter, poolSharePrice) <= PoolState.POOL_SHARE_PRICE_APPROXIMATION, "JOINLPP");

    require(_state.checkPoolCollateralBalance(), "COLERR");

    emit JoinedPool(
      msg.sender,
      block.timestamp,
      _collateralAmount,
      poolShareAmountOut,
      poolSharePrice
    );

    processRedemptionQueueSimple(_state);
  }

  function join(
    PoolState.State storage _state,
    uint256 _collateralAmount,
    uint256 _minPoolShareAmountOut,
    IPoolTypes.RolloverHints[] memory _rolloverHintsList
  ) public {
    _state.rolloverOldestDerivativeBatch(block.timestamp, _rolloverHintsList);
    joinSimple(_state, _collateralAmount, _minPoolShareAmountOut);
  }

  // 3
  function exitSimple(PoolState.State storage _state, uint256 _poolShareAmountIn) public {
    require(_poolShareAmountIn <= _state.config.poolShare.balanceOf(msg.sender), "WRONGAMOUNT");
    require(
      _poolShareAmountIn >= _state.config.minExitAmount ||
        _poolShareAmountIn == _state.config.poolShare.balanceOf(msg.sender),
      "MINEXIT"
    );

    _state.redemptionQueue.enqueue(
      RedemptionQueue.Request({
        owner: msg.sender,
        amount: _poolShareAmountIn,
        time: block.timestamp
      })
    );

    _state.config.poolShare.transferFrom(msg.sender, address(this), _poolShareAmountIn);

    emit CreatedRedemptionQueueItem(msg.sender, block.timestamp, _poolShareAmountIn);
  }

  function exit(
    PoolState.State storage _state,
    uint256 _poolShareAmountIn,
    IPoolTypes.RolloverHints[] memory _rolloverHintsList
  ) public {
    exitSimple(_state, _poolShareAmountIn);

    _state.rolloverOldestDerivativeBatch(block.timestamp, _rolloverHintsList);

    processRedemptionQueueSimple(_state);

    uint256 userReleasedLiquidity = _state.getReleasedLiquidity(msg.sender);

    if (userReleasedLiquidity > 0) {
      _state.withdrawReleasedLiquidity(_state.fromStandardToCollateral(userReleasedLiquidity));
    }
  }

  struct VarsTrade {
    IPoolTypes.Derivative derivative;
    uint256 currentVintage;
    uint256 userPortfolio;
    uint256 vintageIndex;
    uint256 collateralPrice;
    uint256 underlyingPrice;
    uint256 outAmount;
  }

  // 4
  function buySimple(
    PoolState.State storage _state,
    uint256 _userPortfolio,
    uint256 _collateralAmount,
    uint256 _derivativeIndex,
    IPoolTypes.Side _side,
    uint256 _minDerivativeAmount
  ) public {
    require(_derivativeIndex < _state.liveSet.length, "DERIND");

    if (!_state.refreshPoolTo(block.timestamp)) return;

    if (!_state.checkIfRedemptionQueueEmpty()) {
      processRedemptionQueueSimple(_state);
      if (_state.pausing) return;
    }
    require(_state.checkIfRedemptionQueueEmpty(), "NOTEMPTYQUEUE");

    VarsTrade memory vars;

    PoolState.pullCollateral(
      address(_state.config.collateralToken),
      msg.sender,
      _collateralAmount
    );
    uint256 feeAmount = (_collateralAmount * _state.config.protocolFee) / NumLib.BONE;
    if (feeAmount > 0) {
      PoolState.pushCollateral(
        address(_state.config.collateralToken),
        _state.config.feeWallet,
        feeAmount
      );
      _collateralAmount -= feeAmount;
    }

    vars.derivative = _state.liveSet[_derivativeIndex];
    require(
      vars.derivative.sequence.side == _side ||
        vars.derivative.sequence.side == IPoolTypes.Side.Both,
      "SIDE"
    );

    processUserPositionVintages(_state, msg.sender, _userPortfolio, _derivativeIndex);

    vars.collateralPrice = _state.getLatestAnswer(
      _state.config.collateralOracleIterator,
      _state.config.collateralOracle
    );
    if (vars.collateralPrice == 0) return;

    vars.underlyingPrice = _state.getLatestAnswerByDerivative(vars.derivative);
    if (vars.underlyingPrice == 0) return;

    vars.outAmount = calculateOutAmount(
      _state,
      _derivativeIndex,
      _side,
      _collateralAmount,
      true,
      vars.collateralPrice,
      vars.underlyingPrice
    );

    require(vars.outAmount >= _minDerivativeAmount, "MINDER");

    if (_side == IPoolTypes.Side.Primary) {
      _state.positionBalances[_userPortfolio][_derivativeIndex].primary += vars.outAmount;
      _state.positionBalances[PoolState.POOL_PORTFOLIO_ID][_derivativeIndex].complement += vars.outAmount;
    } else if (_side == IPoolTypes.Side.Complement) {
      _state.positionBalances[_userPortfolio][_derivativeIndex].complement += vars.outAmount;
      _state.positionBalances[PoolState.POOL_PORTFOLIO_ID][_derivativeIndex].primary += vars.outAmount;
    }
    uint256 currentVintageIndex = _state.getCurrentVintageIndexFor(_derivativeIndex);
    // set current vintage as initial
    _state.setUserPositionVintageIndex(_userPortfolio, _derivativeIndex, currentVintageIndex);

    uint256 requiredCollateral = (vars.derivative.params.denomination * vars.outAmount) /
      NumLib.BONE + 1; //increment by minimal - round up
    _state.balance.collateralFree =
      _state.balance.collateralFree +
      _state.fromCollateralToStandard(_collateralAmount) -
      requiredCollateral;
    _state.balance.collateralLocked += requiredCollateral;

    require(_state.checkPoolCollateralBalance(), "COLERR");

    processRedemptionQueueSimple(_state);

    emit MintedDerivative(
      _userPortfolio,
      _derivativeIndex,
      _side,
      _collateralAmount,
      vars.outAmount,
      feeAmount,
      currentVintageIndex
    );
  }

  function buy(
    PoolState.State storage _state,
    address _user,
    uint256 _userPortfolio,
    uint256 _collateralAmount,
    uint256 _derivativeIndex,
    IPoolTypes.Side _side,
    uint256 _minDerivativeAmount,
    bool _redeemable,
    IPoolTypes.RolloverHints[] memory _rolloverHintsList
  ) public {
    _state.rolloverOldestDerivativeBatch(block.timestamp, _rolloverHintsList);
    if(_redeemable) {
      processUserPositionsAll(_state, _user, _userPortfolio);
    }
    buySimple(_state, _userPortfolio, _collateralAmount, _derivativeIndex, _side, _minDerivativeAmount);
  }

  // 5
  function sellSimple(
    PoolState.State storage _state,
    uint256 _userPortfolio,
    uint256 _derivativeAmount,
    uint256 _derivativeIndex,
    IPoolTypes.Side _side,
    uint256 _minCollateralAmount
  ) public {
    require(_derivativeIndex < _state.liveSet.length, "DERIND");

    if (!_state.refreshPoolTo(block.timestamp)) return;

    processUserPositionVintages(_state, msg.sender, _userPortfolio, _derivativeIndex);

    VarsTrade memory vars;

    vars.derivative = _state.liveSet[_derivativeIndex];

    uint256 userDerivativeBalance = _side == IPoolTypes.Side.Primary
      ? _state.positionBalances[_userPortfolio][_derivativeIndex].primary
      : _state.positionBalances[_userPortfolio][_derivativeIndex].complement;

    uint256 derivativeAmountBalanced = _derivativeAmount > userDerivativeBalance
      ? userDerivativeBalance
      : _derivativeAmount;

    vars.collateralPrice = _state.getLatestAnswer(
      _state.config.collateralOracleIterator,
      _state.config.collateralOracle
    );
    if (vars.collateralPrice == 0) return;

    vars.underlyingPrice = _state.getLatestAnswerByDerivative(vars.derivative);
    if (vars.underlyingPrice == 0) return;

    vars.outAmount = calculateOutAmount(
      _state,
      _derivativeIndex,
      _side,
      derivativeAmountBalanced,
      false,
      vars.collateralPrice,
      vars.underlyingPrice
    );

    require(vars.outAmount >= _minCollateralAmount, "MINCOL");

    if (_side == IPoolTypes.Side.Primary) {
      _state.positionBalances[_userPortfolio][_derivativeIndex].primary -= derivativeAmountBalanced;
      _state
      .positionBalances[PoolState.POOL_PORTFOLIO_ID][_derivativeIndex]
        .complement -= derivativeAmountBalanced;
    } else if (_side == IPoolTypes.Side.Complement) {
      _state.positionBalances[_userPortfolio][_derivativeIndex].complement -= derivativeAmountBalanced;
      _state
      .positionBalances[PoolState.POOL_PORTFOLIO_ID][_derivativeIndex].primary -= derivativeAmountBalanced;
    }

    uint256 requiredCollateral = (vars.derivative.params.denomination * derivativeAmountBalanced) /
      NumLib.BONE;
    _state.balance.collateralFree =
      _state.balance.collateralFree +
      requiredCollateral -
      _state.fromCollateralToStandard(vars.outAmount);
    _state.balance.collateralLocked -= requiredCollateral;

    require(_state.checkPoolCollateralBalance(), "COLERR");

    uint256 feeAmount = (vars.outAmount * _state.config.protocolFee) / NumLib.BONE;
    if (feeAmount > 0) {
      PoolState.pushCollateral(
        address(_state.config.collateralToken),
        _state.config.feeWallet,
        feeAmount
      );
    }

    PoolState.pushCollateral(
      address(_state.config.collateralToken),
      msg.sender,
      vars.outAmount - feeAmount
    );

    processRedemptionQueueSimple(_state);

    emit BurnedDerivative(
      _userPortfolio,
      _derivativeIndex,
      _side,
      derivativeAmountBalanced,
      vars.outAmount,
      feeAmount
    );
  }

  function sell(
    PoolState.State storage _state,
    address _user,
    uint256 _userPortfolio,
    uint256 _derivativeAmount,
    uint256 _derivativeIndex,
    IPoolTypes.Side _side,
    uint256 _minCollateralAmount,
    bool _redeemable,
    IPoolTypes.RolloverHints[] memory _rolloverHintsList
  ) public {
    _state.rolloverOldestDerivativeBatch(block.timestamp, _rolloverHintsList);
    if(_redeemable) {
      processUserPositionsAll(_state, _user, _userPortfolio);
    }
    sellSimple(_state, _userPortfolio, _derivativeAmount, _derivativeIndex, _side, _minCollateralAmount);
  }

  function processUserPositionsAll(
    PoolState.State storage _state,
    address _user,
    uint256 _userPortfolio
  ) public {
    for (uint256 i = 0; i < _state.liveSet.length; i++) {
      processUserPositionVintages(_state, _user, _userPortfolio, i);
    }
  }
}
