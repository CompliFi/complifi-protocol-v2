// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITraderPortfolioMerger {
  function mergePortfolios(
    address _from,
    address _to,
    uint256 _tokenId,
    uint256 _existedTokenId
  ) external;
}
