// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAddressRegistry {
  function get(bytes32 _key) external view returns (address);

  function set(address _value) external;
}
