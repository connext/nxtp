// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

interface ISponsorVault {
  // Should be callable by the Connext contract only. Should:
  // - call `addLiquidityFor` to send the calculated fee to the router
  // - return the amount of liquidity router was reimbursed
  function reimburseLiquidityFees(
    address token,
    uint256 amount, // Fee amount, not transfer amount
    address receiver
  ) external returns (uint256);

  // Should be callable by the Connext contract only. Should:
  // - take in an amount of relayer fee specified on origin chain
  // - convert that amount to destination domain gas
  // - send the user the destination domain gas
  function reimburseRelayerFees(
    uint32 originDomain,
    address payable receiver,
    uint256 amount
  ) external;

  // Should allow anyone to send funds to the vault for sponsoring fees
  function deposit(address _token, uint256 _amount) external payable;

  // Should allow the owner of the vault to withdraw funds put in to a given
  // address
  function withdraw(
    address token,
    address receiver,
    uint256 amount
  ) external;
}
