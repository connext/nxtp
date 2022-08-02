// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.15;

interface IWeth {
  function deposit() external payable;

  function withdraw(uint256 amount) external;
}
