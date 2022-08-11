// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITraderPortfolioBuilder {
  function isPortfolioBuilder() external pure returns (bool);

  function build(
    string memory _symbol,
    string memory _name
  ) external returns (address);
}
