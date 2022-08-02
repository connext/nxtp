// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {IAavePool} from "../core/connext/interfaces/IAavePool.sol";

contract TestAavePool is IAavePool {
  bool revertCall;

  function setRevertCall(bool _revert) external {
    revertCall = _revert;
  }

  function mintUnbacked(
    address, //asset,
    uint256, //amount,
    address, //onBehalfOf,
    uint16 //referralCode
  ) external view {
    require(!revertCall, "mintUnbacked reverted");
  }

  function backUnbacked(
    address, //asset,
    uint256, // amount,
    uint256 // fee
  ) external view {
    require(!revertCall, "backUnbacked reverted");
  }

  function withdraw(
    address, // asset,
    uint256 amount,
    address //to
  ) external view returns (uint256) {
    require(!revertCall, "withdraw reverted");
    return amount;
  }
}
