// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IPool.sol";
import "./poolBlocks/IPoolConfigTypes.sol";
import "./poolBlocks/IPoolTypes.sol";
import "./specification/IDerivativeSpecificationMetadata.sol";
import "./exposure/IExposure.sol";

contract PoolView {
  struct PoolInfo {
    IPoolConfigTypes.PoolConfig config;
    IPoolTypes.PoolBalance balance;
    IPoolTypes.Derivative[] liveSet;
    IPoolTypes.Vintage[][] oldSet;
    IPoolTypes.Pair[] derivativePoolBalances;
    RedemptionQueue.Request[] redemptionQueueRequests;
    bool paused;
    uint256 poolShareTotalSupply;
    uint256 collateralTokenPoolBalance;
    uint256[] exposureWeights;
  }

  struct UserPoolInfo {
    IPoolTypes.Pair[] derivativeBalances;
    uint256[] derivativeVintages;
    uint256 releasedLiquidity;
    uint256 poolShareBalance;
    uint256 poolShareAllowance;
    uint256 collateralTokenBalance;
    uint256 collateralTokenAllowance;
  }

  struct DerivativeSpecificationParams {
    bytes32[] underlyingOracleSymbols;
    bytes32[] underlyingOracleIteratorSymbols;
    bytes32 collateralTokenSymbol;
    bytes32 collateralSplitSymbol;
    uint256 denomination;
    uint256 referencePriceMultiplier;
    string symbol;
    string name;
    string baseURI;
  }

  /// @notice Getting the pool and the user related information
  /// @param _pool address for which information are being extracted
  /// @param _sender address of user for which pool information are being expanded
  /// @return poolInfo the pool information
  /// @return userPoolInfo the sender related pool information
  function getPoolInfo(address _pool, address _sender)
    public
    view
    returns (PoolInfo memory poolInfo, UserPoolInfo memory userPoolInfo)
  {
    IPool pool = IPool(_pool);
    IPoolConfigTypes.PoolConfig memory config = pool.getConfig();
    IPoolTypes.Derivative[] memory derivatives = pool.getDerivatives();

    uint256[] memory exposureWeights = new uint256[](derivatives.length);
    IPoolTypes.Pair[] memory derivativePoolBalances = new IPoolTypes.Pair[](derivatives.length);
    IPoolTypes.Vintage[][] memory derivativeVintages = new IPoolTypes.Vintage[][](
      derivatives.length
    );
    for (uint256 i = 0; i < derivatives.length; i++) {
      derivativePoolBalances[i] = pool.derivativeBalanceOf(0, i);
      derivativeVintages[i] = pool.getDerivativeVintages(i);
      exposureWeights[i] = config.exposure.getWeight(i);
    }

    poolInfo = PoolInfo(
      config,
      pool.getBalance(),
      derivatives,
      derivativeVintages,
      derivativePoolBalances,
      pool.getAllRedemptionRequests(),
      pool.paused(),
      config.poolShare.totalSupply(),
      config.collateralToken.balanceOf(_pool),
      exposureWeights
    );

    if (_sender != address(0)) {
      userPoolInfo = fetchUserPoolInfo(_sender, pool, derivatives, config);
    }
  }

  /// @notice Getting the pool related information to the user
  /// @param _pool address for which information are being extracted
  /// @param _sender address of user for which pool information are being expanded
  /// @return userPoolInfo the sender related pool information
  function getUserPoolInfo(address _pool, address _sender)
  public
  view
  returns (UserPoolInfo memory userPoolInfo)
  {
    require(_sender != address(0), "Zero sender");

    IPool pool = IPool(_pool);

    IPoolConfigTypes.PoolConfig memory config = pool.getConfig();
    IPoolTypes.Derivative[] memory derivatives = pool.getDerivatives();

    userPoolInfo = fetchUserPoolInfo(_sender, pool, derivatives, config);
  }

  function fetchUserPoolInfo(
    address _sender,
    IPool _pool,
    IPoolTypes.Derivative[] memory _derivatives,
    IPoolConfigTypes.PoolConfig memory _config
  )
  internal
  view
  returns (UserPoolInfo memory userPoolInfo)
  {
    IPoolTypes.Pair[] memory derivativeUserBalances = new IPoolTypes.Pair[](_derivatives.length);
    uint256[] memory derivativeUserVintages = new uint256[](_derivatives.length);

    if (_pool.checkPortfolioOf(_sender)) {
      uint256 userPortfolio = _pool.getPortfolioBy(_sender);
      for (uint256 i = 0; i < _derivatives.length; i++) {
        derivativeUserBalances[i] = _pool.derivativeBalanceOf(userPortfolio, i);
        derivativeUserVintages[i] = _pool.derivativeVintageIndexOf(userPortfolio, i);
      }
    }

    userPoolInfo = createUserPoolInfoStruct(
      _sender,
      _pool,
      _config,
      derivativeUserBalances,
      derivativeUserVintages
    );
  }

  function createUserPoolInfoStruct(
    address _sender,
    IPool _pool,
    IPoolConfigTypes.PoolConfig memory _config,
    IPoolTypes.Pair[] memory _derivativeUserBalances,
    uint256[] memory _derivativeUserVintages
  ) internal view returns (UserPoolInfo memory) {
    return
      UserPoolInfo(
        _derivativeUserBalances,
        _derivativeUserVintages,
        _pool.releasedLiquidityOf(_sender),
        _config.poolShare.balanceOf(_sender),
        _config.poolShare.allowance(_sender, address(_pool)),
        _config.collateralToken.balanceOf(_sender),
        _config.collateralToken.allowance(_sender, address(_pool))
      );
  }

  function getPoolsInfo(address[] calldata _pools, address _sender)
    public
    view
    returns (PoolInfo[] memory poolInfos, UserPoolInfo[] memory userPoolInfos)
  {
    poolInfos = new PoolInfo[](_pools.length);
    userPoolInfos = new UserPoolInfo[](_pools.length);
    for (uint256 i = 0; i < _pools.length; i++) {
      (PoolInfo memory poolInfo, UserPoolInfo memory userPoolInfo) = getPoolInfo(
        _pools[i],
        _sender
      );

      poolInfos[i] = poolInfo;
      userPoolInfos[i] = userPoolInfo;
    }
  }

  function getUserPoolsInfo(address[] calldata _pools, address _sender)
  public
  view
  returns (UserPoolInfo[] memory userPoolInfos)
  {
    userPoolInfos = new UserPoolInfo[](_pools.length);
    for (uint256 i = 0; i < _pools.length; i++) {
      UserPoolInfo memory userPoolInfo = getUserPoolInfo(
        _pools[i],
        _sender
      );

      userPoolInfos[i] = userPoolInfo;
    }
  }

  function getDerivativeSpecificationParams(address[] calldata _specifications)
    public
    view
    returns (DerivativeSpecificationParams[] memory params)
  {
    params = new DerivativeSpecificationParams[](_specifications.length);
    for (uint256 i = 0; i < _specifications.length; i++) {
      IDerivativeSpecificationMetadata spec = IDerivativeSpecificationMetadata(_specifications[i]);
      params[i] = DerivativeSpecificationParams(
        spec.underlyingOracleSymbols(),
        spec.underlyingOracleIteratorSymbols(),
        spec.collateralTokenSymbol(),
        spec.collateralSplitSymbol(),
        spec.denomination(0, 0),
        spec.referencePriceMultiplier(),
        spec.symbol(),
        spec.name(),
        spec.baseURI()
      );
    }
  }

  /// @notice Getting any ERC20 token balances
  /// @param _owner address for which balances are being extracted
  /// @param _tokens list of all tokens
  /// @return balances token balances
  function getERC20BalancesByOwner(address _owner, address[] calldata _tokens)
    external
    view
    returns (uint256[] memory balances)
  {
    balances = new uint256[](_tokens.length);

    for (uint256 i = 0; i < _tokens.length; i++) {
      balances[i] = IERC20(_tokens[i]).balanceOf(_owner);
    }
  }
}
