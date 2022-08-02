// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseConnextFacet} from "./BaseConnextFacet.sol";
import {AmplificationUtils, SwapUtils} from "../libraries/AmplificationUtils.sol";

/**
 * @title Swap - A StableSwap implementation in solidity.
 * @notice This contract is responsible for custody of closely pegged assets (eg. group of stablecoins)
 * and automatic market making system. Users become an LP (Liquidity Provider) by depositing their tokens
 * in desired ratios for an exchange of the pool token that represents their share of the pool.
 * Users can burn pool tokens and withdraw their share of token(s).
 *
 * Each time a swap between the pooled tokens happens, a set fee incurs which effectively gets
 * distributed to the LPs.
 *
 * In case of emergencies, admin can pause additional deposits, swaps, or single-asset withdraws - which
 * stops the ratio of the tokens in the pool from changing.
 *
 * Users can always withdraw their tokens via multi-asset withdraws.
 *
 * @dev Most of the logic is stored as a library `SwapUtils` for the sake of contract readability.
 */
contract StableSwapFacet is BaseConnextFacet {
  using SwapUtils for SwapUtils.Swap;
  using AmplificationUtils for SwapUtils.Swap;

  // ========== Custom Errors ===========
  error StableSwapFacet__deadlineCheck_deadlineNotMet();
  error StableSwapFacet__getSwapToken_outOfRange();
  error StableSwapFacet__getSwapTokenIndex_notExist();
  error StableSwapFacet__getSwapTokenBalance_indexOutOfRange();

  // ============ Properties ============

  // ============ Modifiers ============

  /**
   * @notice Modifier to check deadline against current timestamp
   * @param deadline latest timestamp to accept this transaction
   */
  modifier deadlineCheck(uint256 deadline) {
    if (block.timestamp > deadline) revert StableSwapFacet__deadlineCheck_deadlineNotMet();
    _;
  }

  // ============ View Functions ============
  /**
   * @notice Return Stable swap storage
   * @param key Hash of the canonical id + domain
   * @return SwapUtils.Swap
   */
  function getSwapStorage(bytes32 key) external view returns (SwapUtils.Swap memory) {
    return s.swapStorages[key];
  }

  /**
   * @notice Return LP token for canonical Id
   * @param key Hash of the canonical id + domain
   * @return LPToken
   */
  function getSwapLPToken(bytes32 key) external view returns (address) {
    return address(s.swapStorages[key].lpToken);
  }

  /**
   * @notice Return A, the amplification coefficient * n * (n - 1)
   * @dev See the StableSwap paper for details
   * @param key Hash of the canonical id + domain
   * @return A parameter
   */
  function getSwapA(bytes32 key) external view returns (uint256) {
    return s.swapStorages[key].getA();
  }

  /**
   * @notice Return A in its raw precision form
   * @dev See the StableSwap paper for details
   * @param key Hash of the canonical id + domain
   * @return A parameter in its raw precision form
   */
  function getSwapAPrecise(bytes32 key) external view returns (uint256) {
    return s.swapStorages[key].getAPrecise();
  }

  /**
   * @notice Return address of the pooled token at given index. Reverts if tokenIndex is out of range.
   * @param key Hash of the canonical id + domain
   * @param index the index of the token
   * @return address of the token at given index
   */
  function getSwapToken(bytes32 key, uint8 index) public view returns (IERC20) {
    if (index >= s.swapStorages[key].pooledTokens.length) revert StableSwapFacet__getSwapToken_outOfRange();
    return s.swapStorages[key].pooledTokens[index];
  }

  /**
   * @notice Return the index of the given token address. Reverts if no matching
   * token is found.
   * @param key Hash of the canonical id + domain
   * @param tokenAddress address of the token
   * @return the index of the given token address
   */
  function getSwapTokenIndex(bytes32 key, address tokenAddress) public view returns (uint8) {
    uint8 index = s.tokenIndexes[key][tokenAddress];
    if (address(getSwapToken(key, index)) != tokenAddress) revert StableSwapFacet__getSwapTokenIndex_notExist();
    return index;
  }

  /**
   * @notice Return current balance of the pooled token at given index
   * @param key Hash of the canonical id + domain
   * @param index the index of the token
   * @return current balance of the pooled token at given index with token's native precision
   */
  function getSwapTokenBalance(bytes32 key, uint8 index) external view returns (uint256) {
    if (index >= s.swapStorages[key].balances.length) revert StableSwapFacet__getSwapTokenBalance_indexOutOfRange();
    return s.swapStorages[key].balances[index];
  }

  /**
   * @notice Get the virtual price, to help calculate profit
   * @param key Hash of the canonical id + domain
   * @return the virtual price, scaled to the POOL_PRECISION_DECIMALS
   */
  function getSwapVirtualPrice(bytes32 key) external view returns (uint256) {
    return s.swapStorages[key].getVirtualPrice();
  }

  /**
   * @notice Calculate amount of tokens you receive on swap
   * @param key Hash of the canonical id + domain
   * @param tokenIndexFrom the token the user wants to sell
   * @param tokenIndexTo the token the user wants to buy
   * @param dx the amount of tokens the user wants to sell. If the token charges
   * a fee on transfers, use the amount that gets transferred after the fee.
   * @return amount of tokens the user will receive
   */
  function calculateSwap(
    bytes32 key,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 dx
  ) external view returns (uint256) {
    return s.swapStorages[key].calculateSwap(tokenIndexFrom, tokenIndexTo, dx);
  }

  /**
   * @notice A simple method to calculate prices from deposits or
   * withdrawals, excluding fees but including slippage. This is
   * helpful as an input into the various "min" parameters on calls
   * to fight front-running
   *
   * @dev This shouldn't be used outside frontends for user estimates.
   *
   * @param key Hash of the canonical id + domain
   * @param amounts an array of token amounts to deposit or withdrawal,
   * corresponding to pooledTokens. The amount should be in each
   * pooled token's native precision. If a token charges a fee on transfers,
   * use the amount that gets transferred after the fee.
   * @param deposit whether this is a deposit or a withdrawal
   * @return token amount the user will receive
   */
  function calculateSwapTokenAmount(
    bytes32 key,
    uint256[] calldata amounts,
    bool deposit
  ) external view returns (uint256) {
    return s.swapStorages[key].calculateTokenAmount(amounts, deposit);
  }

  /**
   * @notice A simple method to calculate amount of each underlying
   * tokens that is returned upon burning given amount of LP tokens
   * @param key Hash of the canonical id + domain
   * @param amount the amount of LP tokens that would be burned on withdrawal
   * @return array of token balances that the user will receive
   */
  function calculateRemoveSwapLiquidity(bytes32 key, uint256 amount) external view returns (uint256[] memory) {
    return s.swapStorages[key].calculateRemoveLiquidity(amount);
  }

  /**
   * @notice Calculate the amount of underlying token available to withdraw
   * when withdrawing via only single token
   * @param key Hash of the canonical id + domain
   * @param tokenAmount the amount of LP token to burn
   * @param tokenIndex index of which token will be withdrawn
   * @return availableTokenAmount calculated amount of underlying token
   * available to withdraw
   */
  function calculateRemoveSwapLiquidityOneToken(
    bytes32 key,
    uint256 tokenAmount,
    uint8 tokenIndex
  ) external view returns (uint256 availableTokenAmount) {
    return s.swapStorages[key].calculateWithdrawOneToken(tokenAmount, tokenIndex);
  }

  /**
   * @notice This function reads the accumulated amount of admin fees of the token with given index
   * @param key Hash of the canonical id + domain
   * @param index Index of the pooled token
   * @return admin's token balance in the token's precision
   */
  function getSwapAdminBalance(bytes32 key, uint256 index) external view returns (uint256) {
    return s.swapStorages[key].getAdminBalance(index);
  }

  /*** STATE MODIFYING FUNCTIONS ***/

  /**
   * @notice Swap two tokens using this pool
   * @param key Hash of the canonical id + domain
   * @param tokenIndexFrom the token the user wants to swap from
   * @param tokenIndexTo the token the user wants to swap to
   * @param dx the amount of tokens the user wants to swap from
   * @param minDy the min amount the user would like to receive, or revert.
   * @param deadline latest timestamp to accept this transaction
   */
  function swap(
    bytes32 key,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 dx,
    uint256 minDy,
    uint256 deadline
  ) external nonReentrant deadlineCheck(deadline) whenNotPaused returns (uint256) {
    return s.swapStorages[key].swap(tokenIndexFrom, tokenIndexTo, dx, minDy);
  }

  /**
   * @notice Swap two tokens using this pool
   * @param key Hash of the canonical id + domain
   * @param assetIn the token the user wants to swap from
   * @param assetOut the token the user wants to swap to
   * @param amountIn the amount of tokens the user wants to swap from
   */
  function swapExact(
    bytes32 key,
    uint256 amountIn,
    address assetIn,
    address assetOut,
    uint256 minAmountOut,
    uint256 deadline
  ) external nonReentrant deadlineCheck(deadline) whenNotPaused returns (uint256) {
    return
      s.swapStorages[key].swap(
        getSwapTokenIndex(key, assetIn),
        getSwapTokenIndex(key, assetOut),
        amountIn,
        minAmountOut
      );
  }

  /**
   * @notice Swap two tokens using this pool
   * @param key Hash of the canonical id + domain
   * @param assetIn the token the user wants to swap from
   * @param assetOut the token the user wants to swap to
   * @param amountOut the amount of tokens the user wants to swap to
   */
  function swapExactOut(
    bytes32 key,
    uint256 amountOut,
    address assetIn,
    address assetOut,
    uint256 maxAmountIn,
    uint256 deadline
  ) external nonReentrant deadlineCheck(deadline) whenNotPaused returns (uint256) {
    return
      s.swapStorages[key].swapOut(
        getSwapTokenIndex(key, assetIn),
        getSwapTokenIndex(key, assetOut),
        amountOut,
        maxAmountIn
      );
  }

  /**
   * @notice Add liquidity to the pool with the given amounts of tokens
   * @param key Hash of the canonical id + domain
   * @param amounts the amounts of each token to add, in their native precision
   * @param minToMint the minimum LP tokens adding this amount of liquidity
   * should mint, otherwise revert. Handy for front-running mitigation
   * @param deadline latest timestamp to accept this transaction
   * @return amount of LP token user minted and received
   */
  function addSwapLiquidity(
    bytes32 key,
    uint256[] calldata amounts,
    uint256 minToMint,
    uint256 deadline
  ) external nonReentrant deadlineCheck(deadline) whenNotPaused returns (uint256) {
    return s.swapStorages[key].addLiquidity(amounts, minToMint);
  }

  /**
   * @notice Burn LP tokens to remove liquidity from the pool. Withdraw fee that decays linearly
   * over period of 4 weeks since last deposit will apply.
   * @dev Liquidity can always be removed, even when the pool is paused.
   * @param key Hash of the canonical id + domain
   * @param amount the amount of LP tokens to burn
   * @param minAmounts the minimum amounts of each token in the pool
   *        acceptable for this burn. Useful as a front-running mitigation
   * @param deadline latest timestamp to accept this transaction
   * @return amounts of tokens user received
   */
  function removeSwapLiquidity(
    bytes32 key,
    uint256 amount,
    uint256[] calldata minAmounts,
    uint256 deadline
  ) external nonReentrant deadlineCheck(deadline) whenNotPaused returns (uint256[] memory) {
    return s.swapStorages[key].removeLiquidity(amount, minAmounts);
  }

  /**
   * @notice Remove liquidity from the pool all in one token. Withdraw fee that decays linearly
   * over period of 4 weeks since last deposit will apply.
   * @param key Hash of the canonical id + domain
   * @param tokenAmount the amount of the token you want to receive
   * @param tokenIndex the index of the token you want to receive
   * @param minAmount the minimum amount to withdraw, otherwise revert
   * @param deadline latest timestamp to accept this transaction
   * @return amount of chosen token user received
   */
  function removeSwapLiquidityOneToken(
    bytes32 key,
    uint256 tokenAmount,
    uint8 tokenIndex,
    uint256 minAmount,
    uint256 deadline
  ) external nonReentrant deadlineCheck(deadline) whenNotPaused returns (uint256) {
    return s.swapStorages[key].removeLiquidityOneToken(tokenAmount, tokenIndex, minAmount);
  }

  /**
   * @notice Remove liquidity from the pool, weighted differently than the
   * pool's current balances. Withdraw fee that decays linearly
   * over period of 4 weeks since last deposit will apply.
   * @param key Hash of the canonical id + domain
   * @param amounts how much of each token to withdraw
   * @param maxBurnAmount the max LP token provider is willing to pay to
   * remove liquidity. Useful as a front-running mitigation.
   * @param deadline latest timestamp to accept this transaction
   * @return amount of LP tokens burned
   */
  function removeSwapLiquidityImbalance(
    bytes32 key,
    uint256[] calldata amounts,
    uint256 maxBurnAmount,
    uint256 deadline
  ) external nonReentrant deadlineCheck(deadline) whenNotPaused returns (uint256) {
    return s.swapStorages[key].removeLiquidityImbalance(amounts, maxBurnAmount);
  }
}
