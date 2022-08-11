// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ITraderPortfolioBuilder.sol";
import "./TraderPortfolio.sol";

contract TraderPortfolioBuilder is ITraderPortfolioBuilder {
  event TraderPortfolioCreated(address traderPortfolioAddress);

  function isPortfolioBuilder() external pure override returns (bool) {
    return true;
  }

  function build(
    string memory _symbol,
    string memory _name
  ) external override returns (address) {
    address portfolioToken = address(
      new TraderPortfolio(_symbol, _name, msg.sender)
    );

    emit TraderPortfolioCreated(portfolioToken);

    return portfolioToken;
  }
}
