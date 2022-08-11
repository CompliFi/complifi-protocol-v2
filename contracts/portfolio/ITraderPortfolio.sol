// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ITraderPortfolio is IERC721 {
  function getPortfolioBy(address _user) external view returns (uint256);
  function getOrCreatePortfolioBy(address _user) external returns (uint256);
}
