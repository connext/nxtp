// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

interface IPriceOracle {
  /**
   * @notice Get the price of a token
   * @param token The token to get the price of
   * @return The asset price mantissa (scaled by 1e18).
   *  Zero means the price is unavailable.
   */
  function getTokenPrice(address token) external view returns (uint256);

  /**
   * @notice Get the price of a token from ChainLink
   * @param token The token to get the price of
   * @return The asset price mantissa (scaled by 1e18).
   *  Zero means the price is unavailable.
   */
  function getPriceFromChainlink(address token) external view returns (uint256);
}
