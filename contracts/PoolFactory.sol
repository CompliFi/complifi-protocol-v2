// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./specification/IDerivativeSpecification.sol";
import "./registries/IAddressRegistry.sol";
import "./poolBuilder/IPoolBuilder.sol";
import "./IUnderlyingLiquidityValuer.sol";
import "./IPool.sol";
import "./poolBlocks/IPausablePool.sol";

/// @title Pool Factory implementation contract
/// @notice Creates new pools and registers them in internal storage
contract PoolFactory is OwnableUpgradeable, UUPSUpgradeable, IUnderlyingLiquidityValuer, IPoolTypes {
  address[] internal _pools;

  IAddressRegistry public derivativeSpecificationRegistry;
  IAddressRegistry public oracleRegistry;
  IAddressRegistry public collateralTokenRegistry;
  IAddressRegistry public collateralSplitRegistry;
  IAddressRegistry public oracleIteratorRegistry;
  address public volatilityEvolution;

  /// @notice protocol fee
  uint256 public protocolFee;
  /// @notice protocol fee receiving wallet
  address public feeWallet;

  IPoolBuilder public poolBuilder;
  address public poolProxyBuilder;
  address public poolShareBuilder;
  address public traderPortfolioBuilder;

  mapping(address => address[]) private _poolsByUnderlying;

  event CreatedPool(
    address pool,
    string _name,
    string _symbol,
    address _underlyingLiquidityValuer,
    address _volatilityEvolution,
    address _exposure,
    IPoolBuilderTypes.FeeParams _feeParams,
    IPoolBuilderTypes.CollateralParams _collateralParams,
    uint256 _minExitAmount,
    address _poolProxyBuilder,
    address _poolShareBuilder,
    address _traderPortfolioBuilder
  );

  event RegisteredPool(address indexed underlying, address pool);

  event SetComponent(string indexed componentName, address componentAddress);
  event SetProtocolFee(uint256 protocolFee);

  /// @notice Initializes pool factory contract storage
  /// @dev Used only once when pool factory is created for the first time
  function initialize(
    address _derivativeSpecificationRegistry,
    address _oracleRegistry,
    address _oracleIteratorRegistry,
    address _collateralTokenRegistry,
    address _collateralSplitRegistry,
    address _volatilityEvolution,
    uint256 _protocolFee,
    address _feeWallet,
    address _poolBuilder,
    address _poolProxyBuilder,
    address _poolShareBuilder,
    address _traderPortfolioBuilder
  ) public initializer {
    __Ownable_init();
    __UUPSUpgradeable_init();

    setDerivativeSpecificationRegistry(_derivativeSpecificationRegistry);
    setOracleRegistry(_oracleRegistry);
    setOracleIteratorRegistry(_oracleIteratorRegistry);
    setCollateralTokenRegistry(_collateralTokenRegistry);
    setCollateralSplitRegistry(_collateralSplitRegistry);
    setVolatilityEvolution(_volatilityEvolution);

    setPoolBuilder(_poolBuilder);
    setPoolProxyBuilder(_poolProxyBuilder);
    setPoolShareBuilder(_poolShareBuilder);
    setTraderPortfolioBuilder(_traderPortfolioBuilder);

    setFeeWallet(_feeWallet);
    setProtocolFee(_protocolFee);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function _authorizeUpgrade(address) internal override onlyOwner {}

  function version() public pure returns (uint256) {
    return 1;
  }

  function registerPool(address _underlying, address _pool) internal {
    address[] storage pools = _poolsByUnderlying[_underlying];
    pools.push(_pool);
    emit RegisteredPool(_underlying, _pool);
  }

  function getUnderlyingLiquidityValue(address _underlying)
    external
    override
    returns (uint256 liquidityValue)
  {
    address[] memory relatedPools = _poolsByUnderlying[_underlying];
    liquidityValue = 0;
    for (uint256 i = 0; i < relatedPools.length; i++) {
      liquidityValue += IPool(relatedPools[i]).getCollateralValue();
    }
  }

  function createPool(
    string memory _symbol,
    string memory _name,
    address _exposure, //TODO: create internally by Exposure builder
    bytes32 _collateralTokenSymbol,
    bytes32 _collateralOracleSymbol,
    bytes32 _collateralOracleIteratorSymbol,
    uint256 _minExitAmount
  ) external onlyOwner returns (uint256) {
    IPoolBuilderTypes.CollateralParams memory collateralParams = createCollateralParams(
      _collateralTokenSymbol,
      _collateralOracleSymbol,
      _collateralOracleIteratorSymbol
    );

    IPoolBuilderTypes.FeeParams memory feeParams = IPoolBuilderTypes.FeeParams(
      feeWallet,
      protocolFee
    );

    address pool = buildPool(
      _symbol,
      _name,
      _exposure,
      feeParams,
      collateralParams,
      _minExitAmount
    );

    _pools.push(pool);

    return _pools.length - 1;
  }

  function buildPool(
    string memory _name,
    string memory _symbol,
    address _exposure,
    IPoolBuilderTypes.FeeParams memory _feeParams,
    IPoolBuilderTypes.CollateralParams memory _collateralParams,
    uint256 _minExitAmount
  ) internal returns (address pool) {

    pool = poolBuilder.buildPool(
      _symbol,
      _name,
      IPoolBuilderTypes.Components(
        {
          poolShareBuilder: poolShareBuilder,
          traderPortfolioBuilder: traderPortfolioBuilder,
          underlyingLiquidityValuer: address(this),
          volatilityEvolution: volatilityEvolution
        }
      ),
      _exposure,
      _feeParams,
      _collateralParams,
      _minExitAmount,
      poolProxyBuilder
    );

    emit CreatedPool(
      pool,
      _symbol,
      _name,
      address(this),
      volatilityEvolution,
      _exposure,
      _feeParams,
      _collateralParams,
      _minExitAmount,
      poolProxyBuilder,
      poolShareBuilder,
      traderPortfolioBuilder
    );
  }

  function createCollateralParams(
    bytes32 _collateralTokenSymbol,
    bytes32 _collateralOracleSymbol,
    bytes32 _collateralOracleIteratorSymbol
  ) internal view returns (IPoolBuilderTypes.CollateralParams memory) {
    address collateralToken = collateralTokenRegistry.get(_collateralTokenSymbol);
    require(address(collateralToken) != address(0), "Collateral token");

    address collateralOracle = oracleRegistry.get(_collateralOracleSymbol);
    require(address(collateralOracle) != address(0), "Collateral Oracle");

    address collateralOracleIterator = oracleIteratorRegistry.get(_collateralOracleIteratorSymbol);
    require(address(collateralOracleIterator) != address(0), "Collateral OracleIterator");

    return
      IPoolBuilderTypes.CollateralParams(
        collateralToken,
        collateralOracle,
        collateralOracleIterator
      );
  }

  function addDerivative(
    uint256 _poolIndex,
    bytes32 _derivativeSpecificationSymbol,
    address _termsOfTrade,
    Mode _mode,
    Side _side,
    uint256 _settlementDelta,
    uint256 _strikePosition,
    uint256 _pRef,
    uint256 _settlement
  ) external onlyOwner returns (uint256 derivativeIndex) {
    IPool pool = IPool(_pools[_poolIndex]);
    derivativeIndex = pool.addDerivative(
      resolveDerivative(_derivativeSpecificationSymbol),
      _termsOfTrade,
      Sequence(_mode, _side, _settlementDelta, _strikePosition),
      _pRef,
      _settlement
    );

    Derivative memory derivative = pool.getDerivative(derivativeIndex);
    registerPool(derivative.config.underlyingOracles[0], address(pool));
  }

  function resolveDerivative(bytes32 _derivativeSpecificationSymbol)
    internal
    view
    returns (DerivativeConfig memory)
  {
    IDerivativeSpecification derivativeSpecification = IDerivativeSpecification(
      derivativeSpecificationRegistry.get(_derivativeSpecificationSymbol)
    );
    require(address(derivativeSpecification) != address(0), "Specification is absent");

    address collateralToken = collateralTokenRegistry.get(
      derivativeSpecification.collateralTokenSymbol()
    );
    require(collateralToken != address(0), "Collateral Token is absent");

    address collateralSplit = collateralSplitRegistry.get(
      derivativeSpecification.collateralSplitSymbol()
    );
    require(collateralSplit != address(0), "Collateral Split is absent");

    (
      address[] memory underlyingOracles,
      address[] memory underlyingOracleIterators
    ) = getOraclesAndIterators(derivativeSpecification);

    return
      DerivativeConfig(
        derivativeSpecification,
        underlyingOracles,
        underlyingOracleIterators,
        collateralToken,
        ICollateralSplit(collateralSplit)
      );
  }

  function getOraclesAndIterators(IDerivativeSpecification _derivativeSpecification)
    internal
    view
    returns (address[] memory _oracles, address[] memory _oracleIterators)
  {
    bytes32[] memory oracleSymbols = _derivativeSpecification.underlyingOracleSymbols();
    bytes32[] memory oracleIteratorSymbols = _derivativeSpecification
      .underlyingOracleIteratorSymbols();
    require(oracleSymbols.length == oracleIteratorSymbols.length, "Oracles and iterators length");

    _oracles = new address[](oracleSymbols.length);
    _oracleIterators = new address[](oracleIteratorSymbols.length);
    for (uint256 i = 0; i < oracleSymbols.length; i++) {
      address oracle = oracleRegistry.get(oracleSymbols[i]);
      require(address(oracle) != address(0), "Oracle is absent");
      _oracles[i] = oracle;

      address oracleIterator = oracleIteratorRegistry.get(oracleIteratorSymbols[i]);
      require(address(oracleIterator) != address(0), "OracleIterator is absent");
      _oracleIterators[i] = oracleIterator;
    }
  }

  function setProtocolFee(uint256 _protocolFee) public onlyOwner {
    protocolFee = _protocolFee;
    emit SetProtocolFee(_protocolFee);
  }

  function setPoolBuilder(address _poolBuilder) public onlyOwner {
    require(_poolBuilder != address(0), "Pool builder");
    poolBuilder = IPoolBuilder(_poolBuilder);
    emit SetComponent("PoolBuilder", _poolBuilder);
  }

  function setPoolProxyBuilder(address _poolProxyBuilder) public onlyOwner {
    require(_poolProxyBuilder != address(0), "Pool proxy builder");
    poolProxyBuilder = _poolProxyBuilder;
    emit SetComponent("PoolProxyBuilder", _poolProxyBuilder);
  }

  function setPoolShareBuilder(address _poolShareBuilder) public onlyOwner {
    require(_poolShareBuilder != address(0), "Pool token builder");
    poolShareBuilder = _poolShareBuilder;
    emit SetComponent("PoolShareBuilder", _poolShareBuilder);
  }

  function setTraderPortfolioBuilder(address _traderPortfolioBuilder) public onlyOwner {
    require(_traderPortfolioBuilder != address(0), "Pool Portfolio builder");
    traderPortfolioBuilder = _traderPortfolioBuilder;
    emit SetComponent("TraderPortfolioBuilder", _traderPortfolioBuilder);
  }

  function setFeeWallet(address _feeWallet) public onlyOwner {
    require(_feeWallet != address(0), "Fee wallet");
    feeWallet = _feeWallet;
    emit SetComponent("FeeWallet", _feeWallet);
  }

  function setDerivativeSpecificationRegistry(address _derivativeSpecificationRegistry)
    public
    onlyOwner
  {
    require(_derivativeSpecificationRegistry != address(0), "Derivative specification registry");
    derivativeSpecificationRegistry = IAddressRegistry(_derivativeSpecificationRegistry);
    emit SetComponent("DerivativeSpecificationRegistry", _derivativeSpecificationRegistry);
  }

  function setOracleRegistry(address _oracleRegistry) public onlyOwner {
    require(_oracleRegistry != address(0), "Oracle registry");
    oracleRegistry = IAddressRegistry(_oracleRegistry);
    emit SetComponent("OracleRegistry", _oracleRegistry);
  }

  function setOracleIteratorRegistry(address _oracleIteratorRegistry) public onlyOwner {
    require(_oracleIteratorRegistry != address(0), "Oracle iterator registry");
    oracleIteratorRegistry = IAddressRegistry(_oracleIteratorRegistry);
    emit SetComponent("OracleIteratorRegistry", _oracleIteratorRegistry);
  }

  function setCollateralTokenRegistry(address _collateralTokenRegistry) public onlyOwner {
    require(_collateralTokenRegistry != address(0), "Collateral token registry");
    collateralTokenRegistry = IAddressRegistry(_collateralTokenRegistry);
    emit SetComponent("CollateralTokenRegistry", _collateralTokenRegistry);
  }

  function setCollateralSplitRegistry(address _collateralSplitRegistry) public onlyOwner {
    require(_collateralSplitRegistry != address(0), "Collateral split registry");
    collateralSplitRegistry = IAddressRegistry(_collateralSplitRegistry);
    emit SetComponent("CollateralSplitRegistry", _collateralSplitRegistry);
  }

  function setVolatilityEvolution(address _volatilityEvolution) public onlyOwner {
    require(_volatilityEvolution != address(0), "Volatility Evolution");
    volatilityEvolution = _volatilityEvolution;
    emit SetComponent("VolatilityEvolution", _volatilityEvolution);
  }

  function setDerivativeSpecification(address _value) external {
    derivativeSpecificationRegistry.set(_value);
  }

  function setOracle(address _value) external {
    oracleRegistry.set(_value);
  }

  function setOracleIterator(address _value) external {
    oracleIteratorRegistry.set(_value);
  }

  function setCollateralToken(address _value) external {
    collateralTokenRegistry.set(_value);
  }

  function setCollateralSplit(address _value) external {
    collateralSplitRegistry.set(_value);
  }

  function upgradePool(address _pool) public onlyOwner {
    address newPoolController = poolBuilder.createPoolController();
    UUPSUpgradeable(_pool).upgradeTo(newPoolController);
  }

  function pausePool(address _pool) public onlyOwner {
    IPausablePool(_pool).pause();
  }

  function unpausePool(address _pool) public onlyOwner {
    IPausablePool(_pool).unpause();
  }

  function changeProtocolFee(address _pool, uint256 _protocolFee) external onlyOwner {
    IPool(_pool).changeProtocolFee(_protocolFee);
  }

  function changeMinExitAmount(address _pool, uint256 _minExitAmount) external onlyOwner {
    IPool(_pool).changeMinExitAmount(_minExitAmount);
  }

  function changeFeeWallet(address _pool, address _feeWallet) external onlyOwner {
    IPool(_pool).changeFeeWallet(_feeWallet);
  }

  function changeVolatilityEvolution(address _pool, address _volatilityEvolution) external onlyOwner {
    IPool(_pool).changeVolatilityEvolution(_volatilityEvolution);
  }

  function changeExposure(address _pool, address _exposure) external onlyOwner {
    IPool(_pool).changeExposure(_exposure);
  }

  function changeCollateralOracleIterator(address _pool, address _collateralOracleIterator) external onlyOwner {
    IPool(_pool).changeCollateralOracleIterator(_collateralOracleIterator);
  }

  function changeUnderlyingLiquidityValuer(address _pool, address _underlyingLiquidityValuer) external onlyOwner {
    IPool(_pool).changeUnderlyingLiquidityValuer(_underlyingLiquidityValuer);
  }

  function changeDerivativeMode(
    address _pool,
    uint256 _derivativeIndex,
    Mode _mode
  ) external onlyOwner {
    IPool(_pool).changeDerivativeMode(_derivativeIndex, _mode);
  }

  function changeDerivativeSide(
    address _pool,
    uint256 _derivativeIndex,
    Side _side
  ) external onlyOwner {
    IPool(_pool).changeDerivativeSide(_derivativeIndex, _side);
  }

  function changeDerivativeTerms(
    address _pool,
    uint256 _derivativeIndex,
    address _terms
  ) external onlyOwner {
    IPool(_pool).changeDerivativeTerms(_derivativeIndex, _terms);
  }

  function changeDerivativeSettlementDelta(
    address _pool,
    uint256 _derivativeIndex,
    uint256 _settlementDelta
  ) external onlyOwner {
    IPool(_pool).changeDerivativeSettlementDelta(_derivativeIndex, _settlementDelta);
  }

  /// @notice Returns pool based on internal index
  /// @param _index internal pool index
  /// @return pool address
  function getPool(uint256 _index) external view returns (address) {
    return _pools[_index];
  }

  /// @notice Get last created pool index
  /// @return last created pool index
  function getLastPoolIndex() external view returns (uint256) {
    return _pools.length - 1;
  }

  /// @notice Get all previously created pools
  /// @return all previously created pools
  function getAllPools() external view returns (address[] memory) {
    return _pools;
  }

  uint256[50] private __gap;
}
