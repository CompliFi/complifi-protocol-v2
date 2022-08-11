// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract PossessingFaucet {
  uint256 public constant DEFAULT_AMOUNT_WHOLE = 100;

  function request(address to, address[] memory tokens) public {
    require(to != address(0), "ZERO TO");

    for (uint256 i = 0; i < tokens.length; i++) {
      IERC20Metadata token = IERC20Metadata(tokens[i]);
      uint8 decimals = token.decimals();
      uint256 defaultAmount = DEFAULT_AMOUNT_WHOLE * (10**decimals);
      if (token.balanceOf(to) < defaultAmount) {
        token.transfer(to, defaultAmount);
      }
    }
  }
}
