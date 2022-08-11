// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Pool.sol";

import "hardhat/console.sol";

contract StubPool is Pool {

  function setBalance(PoolBalance memory newBalance) external {
    _state.balance = newBalance;
  }

  function setDerivativePosition(uint256 portfolioId, uint256 derivativeId, Pair memory position) external {
    console.log("setDerivativePosition portfolioId", portfolioId);
    console.log("setDerivativePosition derivativeId", derivativeId);
    console.log("setDerivativePosition position.primary", position.primary);
    console.log("setDerivativePosition position.complement", position.complement);

    _state.positionBalances[portfolioId][derivativeId] = position;
  }

  function setDerivativeVintage(uint256 portfolioId, uint256 derivativeId, uint256 vintageIndex) external {
    _state._vintages[portfolioId][derivativeId] = vintageIndex;
  }
}
