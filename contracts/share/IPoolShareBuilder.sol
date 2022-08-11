// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPoolShareBuilder {
  function isTokenBuilder() external pure returns (bool);

  function build(
    string memory _symbol,
    string memory _name,
    uint8 _decimals
  ) external returns (address);
}
