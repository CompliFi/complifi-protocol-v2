// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract MintableToken is AccessControl, ERC20Burnable {
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  uint8 private immutable decimal_;

  constructor(
    string memory _name,
    string memory _symbol,
    uint8 _decimal
  ) ERC20(_name, _symbol) {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(MINTER_ROLE, msg.sender);

    decimal_ = (_decimal > 0) ? _decimal : 18;
  }

  function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
    _mint(to, amount);
  }

  function decimals() public view override returns (uint8) {
    return decimal_;
  }
}
