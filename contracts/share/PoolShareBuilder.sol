// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "./IPoolShareBuilder.sol";
import "./ERC20PresetMinterPermitted.sol";

contract PoolShareBuilder is IPoolShareBuilder {
  event PoolShareCreated(address poolShareAddress);

  function isTokenBuilder() external pure override returns (bool) {
    return true;
  }

  function build(
    string memory _symbol,
    string memory _name,
    uint8 _decimals
  ) external override returns (address) {
    address poolShare = address(
      new ERC20PresetMinterPermitted(
        concat(_name, " LP"),
        concat(_symbol, "-LP"),
        msg.sender,
        _decimals
      )
    );

    emit PoolShareCreated(poolShare);

    return poolShare;
  }

  function concat(string memory _a, string memory _b) internal pure returns (string memory) {
    return string(abi.encodePacked(bytes(_a), bytes(_b)));
  }
}
