// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "../poolBlocks/ITraderPortfolioMerger.sol";

//import "hardhat/console.sol";

contract TraderPortfolio is Ownable, ERC721 {
  using Counters for Counters.Counter;

  Counters.Counter private _tokenIdTracker;

  // user -> portfolioId
  mapping(address => uint256) internal _tokenByOwner;

  constructor(string memory _symbol, string memory _name, address _owner) ERC721(_symbol, _name) {
    _transferOwnership(_owner);

    _mint(_owner, 0); // add pool balance portfolio with 0 id
    _tokenIdTracker.increment();
  }

  function getPortfolioBy(address _user) public view returns (uint256) {
    return _tokenByOwner[_user];
  }

  function getOrCreatePortfolioBy(address _user) public onlyOwner returns (uint256) {
    if (_user == address(this)) return 0; // Pool portfolio
    if (_tokenByOwner[_user] > 0) {
      return _tokenByOwner[_user];
    }

    // We cannot just use balanceOf to create the new tokenId because tokens
    // can be burned (destroyed), so we need a separate counter.
    uint256 portfolioId = _tokenIdTracker.current();
    _mint(_user, portfolioId);
    _tokenIdTracker.increment();
    return portfolioId;
  }

  function _beforeTokenTransfer(
    address _from,
    address _to,
    uint256 _tokenId
  ) internal override {
    if (_to != address(0) && _tokenByOwner[_to] == 0) {
      _tokenByOwner[_to] = _tokenId;
    }
    if (_to == address(0) && _tokenByOwner[_from] == _tokenId) {
      delete _tokenByOwner[_from];
    }
  }

  function _transfer(
    address _from,
    address _to,
    uint256 _tokenId
  ) internal override {

    super._transfer(_from, _to, _tokenId);

    if(balanceOf(_to) > 1) {
      uint256 existedTokenId = _tokenByOwner[_to];
      ITraderPortfolioMerger(owner()).mergePortfolios(_from, _to, _tokenId, existedTokenId);
      _burn(_tokenId);
    }
  }
}
