// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./poolBlocks/IPoolConfigTypes.sol";
import "./poolBuilder/IPoolBuilderTypes.sol";

import "./poolBlocks/PoolState.sol";
import "./poolBlocks/PoolLogic.sol";
import "./poolBlocks/PoolRolloverLogic.sol";

import "./share/IPoolShareBuilder.sol";
import "./portfolio/ITraderPortfolioBuilder.sol";

//import "hardhat/console.sol";

contract Pool is
  IPoolTypes,
  ReentrancyGuardUpgradeable,
  OwnableUpgradeable,
  PausableUpgradeable,
  UUPSUpgradeable
{
  using PoolState for PoolState.State;
  using PoolLogic for PoolState.State;
  using PoolRolloverLogic for PoolState.State;

  PoolState.State internal _state;

  event PausedByOracle(
    address oracle,
    uint256 roundHint,
    uint256 requestedTimestamp,
    uint80 roundId,
    int256 answer,
    uint256 timestamp
  );

  event InitiatedPool(uint256 indexed timestamp, IPoolConfigTypes.PoolConfig config);

  event AddedDerivative(
    uint256 indexed derivativeIndex,
    uint256 indexed timestamp,
    Derivative derivative
  );
  event ChangedDerivativeMode(
    uint256 indexed derivativeIndex,
    Mode mode
  );
  event ChangedDerivativeSide(
    uint256 indexed derivativeIndex,
    Side side
  );
  event ChangedDerivativeTerms(
    uint256 indexed derivativeIndex,
    address terms
  );

  event ChangedDerivativeSettlementDelta(
    uint256 indexed derivativeIndex,
    uint256 settlementDelta
  );

  event ChangedConfigParam(string paramName, uint256 paramValue);
  event ChangedConfigComponent(string componentName, address componentValue);

  event FailedRollover(uint256 chainDerivativeIndex, uint256 inDerivativeIndex);

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

  event UpdatedVolatility(
    uint256 updatedAt,
    uint256 omegaNew,
    uint256 omegaAdjusted,
    uint256 sigmaEst,
    uint256 sigmaPrice,
    uint256 ttm,
    int256 mu,
    uint256 underlyingPrice,
    uint256 strike,
    uint256 priceNorm,
    bool buyPrimary
  );

  event LogOutAmount(
    uint256 inAmount,
    uint256 outAmountFeeFree,
    uint256 inPrice,
    uint256 outAmount,
    uint256 outPrice,
    uint256 tradingFee,
    uint256 alphaTrade,
    uint256 ttm,
    int256 mu
  );

  event LogRolloverTrade(Pair valueAllowed, uint256 percentLiq, uint256 percentExp);

  event LogTradingFee(uint256 tradingFee, uint256 expStart, uint256 expEnd, uint256 feeAmp);

  function initialize(
    string memory _name,
    string memory _symbol,
    IPoolBuilderTypes.Components memory _components,
    address _exposure,
    IPoolBuilderTypes.FeeParams memory _feeParams,
    IPoolBuilderTypes.CollateralParams memory _collateralParams,
    uint256 _minExitAmount
  ) public initializer {
    __ReentrancyGuard_init();
    __Ownable_init();
    __Pausable_init();
    __UUPSUpgradeable_init();

    require(_components.poolShareBuilder != address(0), "PTBLDR");
    require(_components.traderPortfolioBuilder != address(0), "PTFBLDR");

    _state.init(
      IPoolShareBuilder(_components.poolShareBuilder).build(_symbol, _name, 18), // STANDARD_DECIMALS,
      ITraderPortfolioBuilder(_components.traderPortfolioBuilder).build(_symbol, _name),
      _components.volatilityEvolution,
      _components.underlyingLiquidityValuer,
      _exposure,
      _feeParams,
      _collateralParams,
      _minExitAmount
    );

    emit InitiatedPool(block.timestamp, _state.config);
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  function version() public pure returns (uint256) {
    return 1;
  }

  function addDerivative(
    DerivativeConfig memory _derivativeConfig,
    address _terms,
    Sequence memory _sequence,
    uint256 _pRef,
    uint256 _settlement
  ) external nonReentrant onlyOwner returns (uint256 derivativeIndex) {
    return _state.addDerivative(_derivativeConfig, _terms, _sequence, _pRef, _settlement);
  }

  function mergePortfolios(
    address _from,
    address _to,
    uint256 _portfolioId,
    uint256 _existedPortfolioId
  ) external nonReentrant {
    require(address(_state.config.traderPortfolio) == _msgSender(), "PORTOK");

    _state.mergePortfolios(_from, _to, _portfolioId, _existedPortfolioId);
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  function changeProtocolFee(uint256 _protocolFee) external onlyOwner {
    _state.config.protocolFee = _protocolFee;
    emit ChangedConfigParam("protocolFee", _protocolFee);
  }

  function changeMinExitAmount(uint256 _minExitAmount) external onlyOwner {
    _state.config.minExitAmount = _minExitAmount;
    emit ChangedConfigParam("minExitAmount", _minExitAmount);
  }

  function changeFeeWallet(address _feeWallet) external onlyOwner {
    require(_feeWallet != address(0), "WRNGWLLT");
    _state.config.feeWallet = _feeWallet;
    emit ChangedConfigComponent("feeWallet", _feeWallet);
  }

  function changeVolatilityEvolution(address _volatilityEvolution) external onlyOwner {
    require(_volatilityEvolution != address(0), "WRNGVOLEV");
    _state.config.volatilityEvolution = IVolatilityEvolution(_volatilityEvolution);
    emit ChangedConfigComponent("volatilityEvolution", _volatilityEvolution);
  }

  function changeExposure(address _exposure) external onlyOwner {
    require(_exposure != address(0), "WRNGEXP");
    _state.config.exposure = IExposure(_exposure);
    emit ChangedConfigComponent("exposure", _exposure);
  }

  function changeCollateralOracleIterator(address _collateralOracleIterator) external onlyOwner {
    require(_collateralOracleIterator != address(0), "WRNGCOLITER");
    _state.config.collateralOracleIterator = IOracleIterator(_collateralOracleIterator);
    emit ChangedConfigComponent("collateralOracleIterator", _collateralOracleIterator);
  }

  function changeUnderlyingLiquidityValuer(address _underlyingLiquidityValuer) external onlyOwner {
    require(_underlyingLiquidityValuer != address(0), "WRNGVALUER");
    _state.config.underlyingLiquidityValuer = IUnderlyingLiquidityValuer(_underlyingLiquidityValuer);
    emit ChangedConfigComponent("underlyingLiquidityValuer", _underlyingLiquidityValuer);
  }

  function changeDerivativeMode(uint256 _derivativeIndex, Mode _mode) external onlyOwner {
    _state.liveSet[_derivativeIndex].sequence.mode = _mode;
    emit ChangedDerivativeMode(_derivativeIndex, _mode);
  }

  function changeDerivativeSide(uint256 _derivativeIndex, Side _side) external onlyOwner {
    _state.liveSet[_derivativeIndex].sequence.side = _side;
    emit ChangedDerivativeSide(_derivativeIndex, _side);
  }

  function changeDerivativeTerms(uint256 _derivativeIndex, address _terms) external onlyOwner {
    require(_terms != address(0), "WRNGTOT");
    _state.liveSet[_derivativeIndex].terms = _terms;
    emit ChangedDerivativeTerms(_derivativeIndex, _terms);
  }

  function changeDerivativeSettlementDelta(uint256 _derivativeIndex, uint256 _settlementDelta) external onlyOwner {
    require(_settlementDelta != 0, "WRNGSETLDELT");
    _state.liveSet[_derivativeIndex].sequence.settlementDelta = _settlementDelta;
    emit ChangedDerivativeSettlementDelta(_derivativeIndex, _settlementDelta);
  }

  function getPoolSharePrice() external returns (uint256) {
    (uint256 poolSharePrice,,) = _state.getPoolSharePrice();
    return poolSharePrice;
  }

  function getDerivativePrice(uint256 _derivativeIndex) external returns (PricePair memory) {
    return _state.getDerivativePrice(_derivativeIndex);
  }

  function getCollateralExposureLimit() external view returns (uint256) {
    return _state.getCollateralExposureLimit();
  }

  function getCollateralValue() external returns (uint256) {
    return _state.getCollateralValue();
  }

  function getPortfolioBy(address user) public view returns (uint256) {
    if (user == address(this)) return 0;
    uint256 userPortfolio = _state.config.traderPortfolio.getPortfolioBy(user);
    require(userPortfolio > 0, "PRTFL");
    return userPortfolio;
  }

  function checkPortfolioOf(address user) external view returns (bool) {
    if (user == address(this)) return true;
    uint256 userPortfolio = _state.config.traderPortfolio.getPortfolioBy(user);
    return userPortfolio > 0;
  }

  function derivativeBalanceOf(uint256 _portfolioId, uint256 _derivativeIndex)
    public
    view
    returns (Pair memory)
  {
    return _state.positionBalances[_portfolioId][_derivativeIndex];
  }

  function derivativeVintageIndexOf(uint256 _portfolioId, uint256 _derivativeIndex)
    public
    view
    returns (uint256)
  {
    return _state.getUserPositionVintageIndex(_portfolioId, _derivativeIndex);
  }

  function releasedLiquidityOf(address _owner) public view returns (uint256) {
    return _state.getReleasedLiquidity(_owner);
  }

  function getDerivative(uint256 _derivativeIndex) external view returns (Derivative memory) {
    return _state.liveSet[_derivativeIndex];
  }

  function getDerivatives() external view returns (Derivative[] memory) {
    return _state.liveSet;
  }

  function getDerivativeIndex() external view returns (uint256) {
    return _state.liveSet.length - 1;
  }

  function getDerivativeVintages(uint256 _derivativeIndex)
    external
    view
    returns (Vintage[] memory)
  {
    return _state._oldSet[_derivativeIndex];
  }

  function getBalance() external view returns (PoolBalance memory) {
    return _state.balance;
  }

  function getConfig() external view returns (IPoolConfigTypes.PoolConfig memory) {
    return _state.config;
  }

  function getDerivativeVintageIndex(uint256 _derivativeIndex) external view returns (uint256) {
    return _state.getCurrentVintageIndexFor(_derivativeIndex);
  }

  function getDerivativeVintage(uint256 _derivativeIndex, uint256 _vintageIndex)
    external
    view
    returns (Vintage memory)
  {
    return _state.getVintageBy(_derivativeIndex, _vintageIndex);
  }

  function getAllRedemptionRequests() external view returns (RedemptionQueue.Request[] memory) {
    return _state.getAllRedemptionRequests();
  }

  function getUnderlyingOracleIndex() external view returns (address[] memory) {
    return _state.getUnderlyingOracleIndex();
  }

  modifier executePause() {
    _;
    if (_state.pausing) {
      _pause();
      _state.pausing = false;
    }
  }

  // 1 PoolLogic.refreshPoolTo

  // 2
  function join(
    uint256 _collateralAmount,
    uint256 _minPoolShareAmountOut,
    RolloverHints[] memory _rolloverHintsList
  ) external nonReentrant whenNotPaused executePause {
    _state.join(_collateralAmount, _minPoolShareAmountOut, _rolloverHintsList);
  }

  function joinSimple(
    uint256 _collateralAmount,
    uint256 _minPoolShareAmountOut
  ) external nonReentrant whenNotPaused executePause {
    _state.joinSimple(_collateralAmount, _minPoolShareAmountOut);
  }

  // 3
  function exit(uint256 _poolShareAmountIn, RolloverHints[] memory _rolloverHintsList)
    external
    nonReentrant
    whenNotPaused
    executePause
  {
    _state.exit(_poolShareAmountIn, _rolloverHintsList);
  }

  function exitSimple(uint256 _poolShareAmountIn)
    external
    nonReentrant
    whenNotPaused
    executePause
  {
    _state.exitSimple(_poolShareAmountIn);
  }

  // 4
  function buy(
    uint256 _collateralAmount,
    uint256 _derivativeIndex,
    Side _side,
    uint256 _minDerivativeAmount,
    bool redeemable,
    RolloverHints[] memory _rolloverHintsList
  ) external nonReentrant whenNotPaused executePause {

    _state.buy(
      msg.sender,
      _state.config.traderPortfolio.getOrCreatePortfolioBy(msg.sender),
      _collateralAmount,
      _derivativeIndex,
      _side,
      _minDerivativeAmount,
      redeemable,
      _rolloverHintsList
    );
  }

  // 5
  function sell(
    uint256 _derivativeAmount,
    uint256 _derivativeIndex,
    Side _side,
    uint256 _minCollateralAmount,
    bool redeemable,
    RolloverHints[] memory _rolloverHintsList
  ) external nonReentrant whenNotPaused executePause {

    _state.sell(
      msg.sender,
      _state.config.traderPortfolio.getOrCreatePortfolioBy(msg.sender),
      _derivativeAmount,
      _derivativeIndex,
      _side,
      _minCollateralAmount,
      redeemable,
      _rolloverHintsList
    );
  }

// 6
  function getOldestDerivativeForRollover(uint256 _pointInTime) external view returns (uint256) {
    return _state.getOldestDerivativeForRollover(_pointInTime);
  }

  function rolloverOldestDerivativeBatch(
    uint256 _pointInTime,
    RolloverHints[] memory _rolloverHintsList
  ) external nonReentrant whenNotPaused executePause {
    _state.rolloverOldestDerivativeBatch(_pointInTime, _rolloverHintsList);
  }

  // 7
  function processRedemptionQueue(RolloverHints[] memory _rolloverHintsList)
    external
    nonReentrant
    whenNotPaused
    executePause
  {
    _state.processRedemptionQueue(_rolloverHintsList);
  }

  // 8 redeem trade
  function processUserPositions(
    uint256[] memory _derivativeIndexes,
    RolloverHints[] memory _rolloverHintsList
  ) external nonReentrant whenNotPaused executePause {
    _state.rolloverOldestDerivativeBatch(block.timestamp, _rolloverHintsList);
    _state.processUserPositions(
      msg.sender,
      _state.config.traderPortfolio.getOrCreatePortfolioBy(msg.sender),
      _derivativeIndexes
    );
  }

// 9
  function withdrawReleasedLiquidity(uint256 _collateralAmount) external nonReentrant {
    _state.withdrawReleasedLiquidity(_collateralAmount);
  }

  // 10
  function moveDerivative(
    address _recipient,
    uint256 _amount,
    uint256 _derivativeIndex,
    Side _side,
    RolloverHints[] memory _rolloverHintsList
  ) external nonReentrant whenNotPaused executePause {
    _state.rolloverOldestDerivativeBatch(block.timestamp, _rolloverHintsList);

    _state.moveDerivativeSafely(
      msg.sender,
      _state.config.traderPortfolio.getOrCreatePortfolioBy(msg.sender),
      _recipient,
      _state.config.traderPortfolio.getOrCreatePortfolioBy(_recipient),
      _amount,
      _derivativeIndex,
      _side
    );
  }

  function redeemInvestments(uint256 _collateralAmount, RolloverHints[] memory _rolloverHintsList) external nonReentrant whenNotPaused executePause {
    _state.processRedemptionQueue(_rolloverHintsList);
    _state.withdrawReleasedLiquidity(_collateralAmount);
  }

  uint256[50] private __gap;
}
