// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

contract ERC20PresetMinterPermitted is Ownable, ERC20Permit {
  uint8 private _decimals;

  constructor(
    string memory name,
    string memory symbol,
    address owner,
    uint8 decimals
  ) ERC20Permit(name) ERC20(name, symbol) {
    _transferOwnership(owner);
    _decimals = decimals;
  }

  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }

  function burn(uint256 amount) public onlyOwner {
    _burn(_msgSender(), amount);
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }
}
