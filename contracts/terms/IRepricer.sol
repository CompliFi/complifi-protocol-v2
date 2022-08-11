// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IRepricerTypes.sol";

interface IRepricer is IRepricerTypes {
  function isRepricer() external pure returns (bool);

  function symbol() external pure returns (string memory);

  function reprice(
    bytes16 _underlyingPrice,
    bytes16 _collateralPrice, // doesn't used
    bytes16 _ttm,
    bytes16 _repricerParam1,
    bytes16 _repricerParam2,
    bytes16 _strike, // doesn't used
    bytes16 _denomination
  ) external view returns (PairBytes16 memory);
}
