// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LPToken} from "../helpers/LPToken.sol";
import {AmplificationUtils} from "./AmplificationUtils.sol";
import {MathUtils} from "./MathUtils.sol";

/**
 * @title SwapUtils library
 * @notice A library to be used within Swap.sol. Contains functions responsible for custody and AMM functionalities.
 * @dev Contracts relying on this library must initialize SwapUtils.Swap struct then use this library
 * for SwapUtils.Swap struct. Note that this library contains both functions called by users and admins.
 * Admin functions should be protected within contracts using this library.
 */
library SwapUtils {
  using SafeERC20 for IERC20;
  using MathUtils for uint256;

  /*** EVENTS ***/

  event TokenSwap(
    bytes32 indexed key,
    address indexed buyer,
    uint256 tokensSold,
    uint256 tokensBought,
    uint128 soldId,
    uint128 boughtId
  );
  event AddLiquidity(
    bytes32 indexed key,
    address indexed provider,
    uint256[] tokenAmounts,
    uint256[] fees,
    uint256 invariant,
    uint256 lpTokenSupply
  );
  event RemoveLiquidity(bytes32 indexed key, address indexed provider, uint256[] tokenAmounts, uint256 lpTokenSupply);
  event RemoveLiquidityOne(
    bytes32 indexed key,
    address indexed provider,
    uint256 lpTokenAmount,
    uint256 lpTokenSupply,
    uint256 boughtId,
    uint256 tokensBought
  );
  event RemoveLiquidityImbalance(
    bytes32 indexed key,
    address indexed provider,
    uint256[] tokenAmounts,
    uint256[] fees,
    uint256 invariant,
    uint256 lpTokenSupply
  );
  event NewAdminFee(bytes32 indexed key, uint256 newAdminFee);
  event NewSwapFee(bytes32 indexed key, uint256 newSwapFee);

  struct Swap {
    // variables around the ramp management of A,
    // the amplification coefficient * n * (n - 1)
    // see https://www.curve.fi/stableswap-paper.pdf for details
    bytes32 key;
    uint256 initialA;
    uint256 futureA;
    uint256 initialATime;
    uint256 futureATime;
    // fee calculation
    uint256 swapFee;
    uint256 adminFee;
    LPToken lpToken;
    // contract references for all tokens being pooled
    IERC20[] pooledTokens;
    // multipliers for each pooled token's precision to get to POOL_PRECISION_DECIMALS
    // for example, TBTC has 18 decimals, so the multiplier should be 1. WBTC
    // has 8, so the multiplier should be 10 ** 18 / 10 ** 8 => 10 ** 10
    uint256[] tokenPrecisionMultipliers;
    // the pool balance of each token, in the token's precision
    // the contract's actual token balance might differ
    uint256[] balances;
    // the admin fee balance of each token, in the token's precision
    uint256[] adminFees;
  }

  // Struct storing variables used in calculations in the
  // calculateWithdrawOneTokenDY function to avoid stack too deep errors
  struct CalculateWithdrawOneTokenDYInfo {
    uint256 d0;
    uint256 d1;
    uint256 newY;
    uint256 feePerToken;
    uint256 preciseA;
  }

  // Struct storing variables used in calculations in the
  // {add,remove}Liquidity functions to avoid stack too deep errors
  struct ManageLiquidityInfo {
    uint256 d0;
    uint256 d1;
    uint256 d2;
    uint256 preciseA;
    LPToken lpToken;
    uint256 totalSupply;
    uint256[] balances;
    uint256[] multipliers;
  }

  // the precision all pools tokens will be converted to
  uint8 internal constant POOL_PRECISION_DECIMALS = 18;

  // the denominator used to calculate admin and LP fees. For example, an
  // LP fee might be something like tradeAmount.mul(fee).div(FEE_DENOMINATOR)
  uint256 internal constant FEE_DENOMINATOR = 1e10;

  // Max swap fee is 1% or 100bps of each swap
  uint256 internal constant MAX_SWAP_FEE = 1e8;

  // Max adminFee is 100% of the swapFee
  // adminFee does not add additional fee on top of swapFee
  // Instead it takes a certain % of the swapFee. Therefore it has no impact on the
  // users but only on the earnings of LPs
  uint256 internal constant MAX_ADMIN_FEE = 1e10;

  // Constant value used as max loop limit
  uint256 internal constant MAX_LOOP_LIMIT = 256;

  /*** VIEW & PURE FUNCTIONS ***/

  function _getAPrecise(Swap storage self) private view returns (uint256) {
    return AmplificationUtils._getAPrecise(self);
  }

  /**
   * @notice Calculate the dy, the amount of selected token that user receives and
   * the fee of withdrawing in one token
   * @param tokenAmount the amount to withdraw in the pool's precision
   * @param tokenIndex which token will be withdrawn
   * @param self Swap struct to read from
   * @return the amount of token user will receive
   */
  function calculateWithdrawOneToken(
    Swap storage self,
    uint256 tokenAmount,
    uint8 tokenIndex
  ) internal view returns (uint256) {
    (uint256 availableTokenAmount, ) = _calculateWithdrawOneToken(
      self,
      tokenAmount,
      tokenIndex,
      self.lpToken.totalSupply()
    );
    return availableTokenAmount;
  }

  function _calculateWithdrawOneToken(
    Swap storage self,
    uint256 tokenAmount,
    uint8 tokenIndex,
    uint256 totalSupply
  ) private view returns (uint256, uint256) {
    uint256 dy;
    uint256 newY;
    uint256 currentY;

    (dy, newY, currentY) = calculateWithdrawOneTokenDY(self, tokenIndex, tokenAmount, totalSupply);

    // dy_0 (without fees)
    // dy, dy_0 - dy

    uint256 dySwapFee = (currentY - newY) / self.tokenPrecisionMultipliers[tokenIndex] - dy;

    return (dy, dySwapFee);
  }

  /**
   * @notice Calculate the dy of withdrawing in one token
   * @param self Swap struct to read from
   * @param tokenIndex which token will be withdrawn
   * @param tokenAmount the amount to withdraw in the pools precision
   * @return the d and the new y after withdrawing one token
   */
  function calculateWithdrawOneTokenDY(
    Swap storage self,
    uint8 tokenIndex,
    uint256 tokenAmount,
    uint256 totalSupply
  )
    internal
    view
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    // Get the current D, then solve the stableswap invariant
    // y_i for D - tokenAmount
    uint256[] memory xp = _xp(self);

    require(tokenIndex < xp.length, "index out of range");

    CalculateWithdrawOneTokenDYInfo memory v = CalculateWithdrawOneTokenDYInfo(0, 0, 0, 0, 0);
    v.preciseA = _getAPrecise(self);
    v.d0 = getD(xp, v.preciseA);
    v.d1 = v.d0 - ((tokenAmount * v.d0) / totalSupply);

    require(tokenAmount <= xp[tokenIndex], "exceeds available");

    v.newY = getYD(v.preciseA, tokenIndex, xp, v.d1);

    uint256[] memory xpReduced = new uint256[](xp.length);

    v.feePerToken = _feePerToken(self.swapFee, xp.length);
    // TODO: Set a length variable (at top) instead of reading xp.length on each loop.
    for (uint256 i; i < xp.length; ) {
      uint256 xpi = xp[i];
      // if i == tokenIndex, dxExpected = xp[i] * d1 / d0 - newY
      // else dxExpected = xp[i] - (xp[i] * d1 / d0)
      // xpReduced[i] -= dxExpected * fee / FEE_DENOMINATOR
      xpReduced[i] =
        xpi -
        ((((i == tokenIndex) ? ((xpi * v.d1) / v.d0 - v.newY) : (xpi - (xpi * v.d1) / v.d0)) * v.feePerToken) /
          FEE_DENOMINATOR);

      unchecked {
        ++i;
      }
    }

    uint256 dy = xpReduced[tokenIndex] - getYD(v.preciseA, tokenIndex, xpReduced, v.d1);
    dy = (dy - 1) / (self.tokenPrecisionMultipliers[tokenIndex]);

    return (dy, v.newY, xp[tokenIndex]);
  }

  /**
   * @notice Calculate the price of a token in the pool with given
   * precision-adjusted balances and a particular D.
   *
   * @dev This is accomplished via solving the invariant iteratively.
   * See the StableSwap paper and Curve.fi implementation for further details.
   *
   * x_1**2 + x1 * (sum' - (A*n**n - 1) * D / (A * n**n)) = D ** (n + 1) / (n ** (2 * n) * prod' * A)
   * x_1**2 + b*x_1 = c
   * x_1 = (x_1**2 + c) / (2*x_1 + b)
   *
   * @param a the amplification coefficient * n * (n - 1). See the StableSwap paper for details.
   * @param tokenIndex Index of token we are calculating for.
   * @param xp a precision-adjusted set of pool balances. Array should be
   * the same cardinality as the pool.
   * @param d the stableswap invariant
   * @return the price of the token, in the same precision as in xp
   */
  function getYD(
    uint256 a,
    uint8 tokenIndex,
    uint256[] memory xp,
    uint256 d
  ) internal pure returns (uint256) {
    uint256 numTokens = xp.length;
    require(tokenIndex < numTokens, "Token not found");

    uint256 c = d;
    uint256 s;
    uint256 nA = a * numTokens;

    for (uint256 i; i < numTokens; ) {
      if (i != tokenIndex) {
        s += xp[i];
        c = (c * d) / (xp[i] * numTokens);
        // If we were to protect the division loss we would have to keep the denominator separate
        // and divide at the end. However this leads to overflow with large numTokens or/and D.
        // c = c * D * D * D * ... overflow!
      }

      unchecked {
        ++i;
      }
    }
    c = (c * d * AmplificationUtils.A_PRECISION) / (nA * numTokens);

    uint256 b = s + ((d * AmplificationUtils.A_PRECISION) / nA);
    uint256 yPrev;
    uint256 y = d;
    for (uint256 i; i < MAX_LOOP_LIMIT; ) {
      yPrev = y;
      y = ((y * y) + c) / ((y * 2) + b - d);
      if (y.within1(yPrev)) {
        return y;
      }

      unchecked {
        ++i;
      }
    }
    revert("Approximation did not converge");
  }

  /**
   * @notice Get D, the StableSwap invariant, based on a set of balances and a particular A.
   * @param xp a precision-adjusted set of pool balances. Array should be the same cardinality
   * as the pool.
   * @param a the amplification coefficient * n * (n - 1) in A_PRECISION.
   * See the StableSwap paper for details
   * @return the invariant, at the precision of the pool
   */
  function getD(uint256[] memory xp, uint256 a) internal pure returns (uint256) {
    uint256 numTokens = xp.length;
    uint256 s;
    for (uint256 i; i < numTokens; ) {
      s += xp[i];

      unchecked {
        ++i;
      }
    }
    if (s == 0) {
      return 0;
    }

    uint256 prevD;
    uint256 d = s;
    uint256 nA = a * numTokens;

    for (uint256 i; i < MAX_LOOP_LIMIT; ) {
      uint256 dP = d;
      for (uint256 j; j < numTokens; ) {
        dP = (dP * d) / (xp[j] * numTokens);
        // If we were to protect the division loss we would have to keep the denominator separate
        // and divide at the end. However this leads to overflow with large numTokens or/and D.
        // dP = dP * D * D * D * ... overflow!

        unchecked {
          ++j;
        }
      }
      prevD = d;
      d =
        (((nA * s) / AmplificationUtils.A_PRECISION + dP * numTokens) * d) /
        ((((nA - AmplificationUtils.A_PRECISION) * d) / AmplificationUtils.A_PRECISION + (numTokens + 1) * dP));
      if (d.within1(prevD)) {
        return d;
      }

      unchecked {
        ++i;
      }
    }

    // Convergence should occur in 4 loops or less. If this is reached, there may be something wrong
    // with the pool. If this were to occur repeatedly, LPs should withdraw via `removeLiquidity()`
    // function which does not rely on D.
    revert("D does not converge");
  }

  /**
   * @notice Given a set of balances and precision multipliers, return the
   * precision-adjusted balances.
   *
   * @param balances an array of token balances, in their native precisions.
   * These should generally correspond with pooled tokens.
   *
   * @param precisionMultipliers an array of multipliers, corresponding to
   * the amounts in the balances array. When multiplied together they
   * should yield amounts at the pool's precision.
   *
   * @return an array of amounts "scaled" to the pool's precision
   */
  function _xp(uint256[] memory balances, uint256[] memory precisionMultipliers)
    internal
    pure
    returns (uint256[] memory)
  {
    uint256 numTokens = balances.length;
    require(numTokens == precisionMultipliers.length, "mismatch multipliers");
    uint256[] memory xp = new uint256[](numTokens);
    for (uint256 i; i < numTokens; ) {
      xp[i] = balances[i] * precisionMultipliers[i];

      unchecked {
        ++i;
      }
    }
    return xp;
  }

  /**
   * @notice Return the precision-adjusted balances of all tokens in the pool
   * @param self Swap struct to read from
   * @return the pool balances "scaled" to the pool's precision, allowing
   * them to be more easily compared.
   */
  function _xp(Swap storage self) internal view returns (uint256[] memory) {
    return _xp(self.balances, self.tokenPrecisionMultipliers);
  }

  /**
   * @notice Get the virtual price, to help calculate profit
   * @param self Swap struct to read from
   * @return the virtual price, scaled to precision of POOL_PRECISION_DECIMALS
   */
  function getVirtualPrice(Swap storage self) internal view returns (uint256) {
    uint256 d = getD(_xp(self), _getAPrecise(self));
    LPToken lpToken = self.lpToken;
    uint256 supply = lpToken.totalSupply();
    if (supply != 0) {
      return (d * (10**uint256(POOL_PRECISION_DECIMALS))) / supply;
    }
    return 0;
  }

  /**
   * @notice Calculate the new balances of the tokens given the indexes of the token
   * that is swapped from (FROM) and the token that is swapped to (TO).
   * This function is used as a helper function to calculate how much TO token
   * the user should receive on swap.
   *
   * @param preciseA precise form of amplification coefficient
   * @param tokenIndexFrom index of FROM token
   * @param tokenIndexTo index of TO token
   * @param x the new total amount of FROM token
   * @param xp balances of the tokens in the pool
   * @return the amount of TO token that should remain in the pool
   */
  function getY(
    uint256 preciseA,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 x,
    uint256[] memory xp
  ) internal pure returns (uint256) {
    uint256 numTokens = xp.length;
    require(tokenIndexFrom != tokenIndexTo, "compare token to itself");
    require(tokenIndexFrom < numTokens && tokenIndexTo < numTokens, "token not found");

    uint256 d = getD(xp, preciseA);
    uint256 c = d;
    uint256 s;
    uint256 nA = numTokens * preciseA;

    uint256 _x;
    for (uint256 i; i < numTokens; ) {
      if (i == tokenIndexFrom) {
        _x = x;
      } else if (i != tokenIndexTo) {
        _x = xp[i];
      } else {
        unchecked {
          ++i;
        }
        continue;
      }
      s += _x;
      c = (c * d) / (_x * numTokens);
      // If we were to protect the division loss we would have to keep the denominator separate
      // and divide at the end. However this leads to overflow with large numTokens or/and D.
      // c = c * D * D * D * ... overflow!

      unchecked {
        ++i;
      }
    }
    c = (c * d * AmplificationUtils.A_PRECISION) / (nA * numTokens);
    uint256 b = s + ((d * AmplificationUtils.A_PRECISION) / nA);
    uint256 yPrev;
    uint256 y = d;

    // iterative approximation
    for (uint256 i; i < MAX_LOOP_LIMIT; ) {
      yPrev = y;
      y = ((y * y) + c) / ((y * 2) + b - d);
      if (y.within1(yPrev)) {
        return y;
      }

      unchecked {
        ++i;
      }
    }
    revert("Approximation did not converge");
  }

  /**
   * @notice Externally calculates a swap between two tokens.
   * @param self Swap struct to read from
   * @param tokenIndexFrom the token to sell
   * @param tokenIndexTo the token to buy
   * @param dx the number of tokens to sell. If the token charges a fee on transfers,
   * use the amount that gets transferred after the fee.
   * @return dy the number of tokens the user will get
   */
  function calculateSwap(
    Swap storage self,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 dx
  ) internal view returns (uint256 dy) {
    (dy, ) = _calculateSwap(self, tokenIndexFrom, tokenIndexTo, dx, self.balances);
  }

  /**
   * @notice Externally calculates a swap between two tokens.
   * @param self Swap struct to read from
   * @param tokenIndexFrom the token to sell
   * @param tokenIndexTo the token to buy
   * @param dy the number of tokens to buy.
   * @return dx the number of tokens the user have to transfer + fee
   */
  function calculateSwapInv(
    Swap storage self,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 dy
  ) internal view returns (uint256 dx) {
    (dx, ) = _calculateSwapInv(self, tokenIndexFrom, tokenIndexTo, dy, self.balances);
  }

  /**
   * @notice Internally calculates a swap between two tokens.
   *
   * @dev The caller is expected to transfer the actual amounts (dx and dy)
   * using the token contracts.
   *
   * @param self Swap struct to read from
   * @param tokenIndexFrom the token to sell
   * @param tokenIndexTo the token to buy
   * @param dx the number of tokens to sell. If the token charges a fee on transfers,
   * use the amount that gets transferred after the fee.
   * @return dy the number of tokens the user will get in the token's precision. ex WBTC -> 8
   * @return dyFee the associated fee in multiplied precision (POOL_PRECISION_DECIMALS)
   */
  function _calculateSwap(
    Swap storage self,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 dx,
    uint256[] memory balances
  ) internal view returns (uint256 dy, uint256 dyFee) {
    uint256[] memory multipliers = self.tokenPrecisionMultipliers;
    uint256[] memory xp = _xp(balances, multipliers);
    require(tokenIndexFrom < xp.length && tokenIndexTo < xp.length, "index out of range");
    uint256 x = dx * multipliers[tokenIndexFrom] + xp[tokenIndexFrom];
    uint256 y = getY(_getAPrecise(self), tokenIndexFrom, tokenIndexTo, x, xp);
    dy = xp[tokenIndexTo] - y - 1;
    dyFee = (dy * self.swapFee) / FEE_DENOMINATOR;
    dy = (dy - dyFee) / multipliers[tokenIndexTo];
  }

  /**
   * @notice Internally calculates a swap between two tokens.
   *
   * @dev The caller is expected to transfer the actual amounts (dx and dy)
   * using the token contracts.
   *
   * @param self Swap struct to read from
   * @param tokenIndexFrom the token to sell
   * @param tokenIndexTo the token to buy
   * @param dy the number of tokens to buy. If the token charges a fee on transfers,
   * use the amount that gets transferred after the fee.
   * @return dx the number of tokens the user have to deposit in the token's precision. ex WBTC -> 8
   * @return dxFee the associated fee in multiplied precision (POOL_PRECISION_DECIMALS)
   */
  function _calculateSwapInv(
    Swap storage self,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 dy,
    uint256[] memory balances
  ) internal view returns (uint256 dx, uint256 dxFee) {
    require(tokenIndexFrom != tokenIndexTo, "compare token to itself");
    uint256[] memory multipliers = self.tokenPrecisionMultipliers;
    uint256[] memory xp = _xp(balances, multipliers);
    require(tokenIndexFrom < xp.length && tokenIndexTo < xp.length, "index out of range");

    uint256 a = _getAPrecise(self);
    uint256 d0 = getD(xp, a);

    xp[tokenIndexTo] = xp[tokenIndexTo] - (dy * multipliers[tokenIndexTo]);
    uint256 x = getYD(a, tokenIndexFrom, xp, d0);
    dx = x - xp[tokenIndexFrom] + 1;
    dxFee = (dx * self.swapFee) / FEE_DENOMINATOR;
    dx = (dx + dxFee) / multipliers[tokenIndexFrom];
  }

  /**
   * @notice A simple method to calculate amount of each underlying
   * tokens that is returned upon burning given amount of
   * LP tokens
   *
   * @param amount the amount of LP tokens that would to be burned on
   * withdrawal
   * @return array of amounts of tokens user will receive
   */
  function calculateRemoveLiquidity(Swap storage self, uint256 amount) internal view returns (uint256[] memory) {
    return _calculateRemoveLiquidity(self.balances, amount, self.lpToken.totalSupply());
  }

  function _calculateRemoveLiquidity(
    uint256[] memory balances,
    uint256 amount,
    uint256 totalSupply
  ) internal pure returns (uint256[] memory) {
    require(amount <= totalSupply, "exceed total supply");

    uint256 numBalances = balances.length;
    uint256[] memory amounts = new uint256[](numBalances);

    for (uint256 i; i < numBalances; ) {
      amounts[i] = (balances[i] * amount) / totalSupply;

      unchecked {
        ++i;
      }
    }
    return amounts;
  }

  /**
   * @notice A simple method to calculate prices from deposits or
   * withdrawals, excluding fees but including slippage. This is
   * helpful as an input into the various "min" parameters on calls
   * to fight front-running
   *
   * @dev This shouldn't be used outside frontends for user estimates.
   *
   * @param self Swap struct to read from
   * @param amounts an array of token amounts to deposit or withdrawal,
   * corresponding to pooledTokens. The amount should be in each
   * pooled token's native precision. If a token charges a fee on transfers,
   * use the amount that gets transferred after the fee.
   * @param deposit whether this is a deposit or a withdrawal
   * @return if deposit was true, total amount of lp token that will be minted and if
   * deposit was false, total amount of lp token that will be burned
   */
  function calculateTokenAmount(
    Swap storage self,
    uint256[] calldata amounts,
    bool deposit
  ) internal view returns (uint256) {
    uint256 a = _getAPrecise(self);
    uint256[] memory balances = self.balances;
    uint256[] memory multipliers = self.tokenPrecisionMultipliers;

    uint256 numBalances = balances.length;
    uint256 d0 = getD(_xp(balances, multipliers), a);
    for (uint256 i; i < numBalances; ) {
      if (deposit) {
        balances[i] = balances[i] + amounts[i];
      } else {
        balances[i] = balances[i] - amounts[i];
      }

      unchecked {
        ++i;
      }
    }
    uint256 d1 = getD(_xp(balances, multipliers), a);
    uint256 totalSupply = self.lpToken.totalSupply();

    if (deposit) {
      return ((d1 - d0) * totalSupply) / d0;
    } else {
      return ((d0 - d1) * totalSupply) / d0;
    }
  }

  /**
   * @notice return accumulated amount of admin fees of the token with given index
   * @param self Swap struct to read from
   * @param index Index of the pooled token
   * @return admin balance in the token's precision
   */
  function getAdminBalance(Swap storage self, uint256 index) internal view returns (uint256) {
    require(index < self.pooledTokens.length, "index out of range");
    return self.adminFees[index];
  }

  /**
   * @notice internal helper function to calculate fee per token multiplier used in
   * swap fee calculations
   * @param swapFee swap fee for the tokens
   * @param numTokens number of tokens pooled
   */
  function _feePerToken(uint256 swapFee, uint256 numTokens) internal pure returns (uint256) {
    return (swapFee * numTokens) / ((numTokens - 1) * 4);
  }

  /*** STATE MODIFYING FUNCTIONS ***/

  /**
   * @notice swap two tokens in the pool
   * @param self Swap struct to read from and write to
   * @param tokenIndexFrom the token the user wants to sell
   * @param tokenIndexTo the token the user wants to buy
   * @param dx the amount of tokens the user wants to sell
   * @param minDy the min amount the user would like to receive, or revert.
   * @return amount of token user received on swap
   */
  function swap(
    Swap storage self,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 dx,
    uint256 minDy
  ) internal returns (uint256) {
    {
      IERC20 tokenFrom = self.pooledTokens[tokenIndexFrom];
      require(dx <= tokenFrom.balanceOf(msg.sender), "swap more than you own");
      // Transfer tokens first to see if a fee was charged on transfer
      uint256 beforeBalance = tokenFrom.balanceOf(address(this));
      tokenFrom.safeTransferFrom(msg.sender, address(this), dx);

      // Use the actual transferred amount for AMM math
      require(dx == tokenFrom.balanceOf(address(this)) - beforeBalance, "no fee token support");
    }

    uint256 dy;
    uint256 dyFee;
    uint256[] memory balances = self.balances;
    (dy, dyFee) = _calculateSwap(self, tokenIndexFrom, tokenIndexTo, dx, balances);
    require(dy >= minDy, "dy < minDy");

    uint256 dyAdminFee = (dyFee * self.adminFee) / FEE_DENOMINATOR / self.tokenPrecisionMultipliers[tokenIndexTo];

    self.balances[tokenIndexFrom] = balances[tokenIndexFrom] + dx;
    self.balances[tokenIndexTo] = balances[tokenIndexTo] - dy - dyAdminFee;
    if (dyAdminFee != 0) {
      self.adminFees[tokenIndexTo] = self.adminFees[tokenIndexTo] + dyAdminFee;
    }

    self.pooledTokens[tokenIndexTo].safeTransfer(msg.sender, dy);

    emit TokenSwap(self.key, msg.sender, dx, dy, tokenIndexFrom, tokenIndexTo);

    return dy;
  }

  /**
   * @notice swap two tokens in the pool
   * @param self Swap struct to read from and write to
   * @param tokenIndexFrom the token the user wants to sell
   * @param tokenIndexTo the token the user wants to buy
   * @param dy the amount of tokens the user wants to buy
   * @param maxDx the max amount the user would like to send.
   * @return amount of token user have to transfer on swap
   */
  function swapOut(
    Swap storage self,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 dy,
    uint256 maxDx
  ) internal returns (uint256) {
    require(dy <= self.balances[tokenIndexTo], ">pool balance");

    uint256 dx;
    uint256 dxFee;
    uint256[] memory balances = self.balances;
    (dx, dxFee) = _calculateSwapInv(self, tokenIndexFrom, tokenIndexTo, dy, balances);
    require(dx <= maxDx, "dx > maxDx");

    uint256 dxAdminFee = (dxFee * self.adminFee) / FEE_DENOMINATOR / self.tokenPrecisionMultipliers[tokenIndexFrom];

    self.balances[tokenIndexFrom] = balances[tokenIndexFrom] + dx - dxAdminFee;
    self.balances[tokenIndexTo] = balances[tokenIndexTo] - dy;
    if (dxAdminFee != 0) {
      self.adminFees[tokenIndexFrom] = self.adminFees[tokenIndexFrom] + dxAdminFee;
    }

    {
      IERC20 tokenFrom = self.pooledTokens[tokenIndexFrom];
      require(dx <= tokenFrom.balanceOf(msg.sender), "more than you own");
      // Transfer tokens first to see if a fee was charged on transfer
      uint256 beforeBalance = tokenFrom.balanceOf(address(this));
      tokenFrom.safeTransferFrom(msg.sender, address(this), dx);

      // Use the actual transferred amount for AMM math
      require(dx == tokenFrom.balanceOf(address(this)) - beforeBalance, "not support fee token");
    }

    self.pooledTokens[tokenIndexTo].safeTransfer(msg.sender, dy);

    emit TokenSwap(self.key, msg.sender, dx, dy, tokenIndexFrom, tokenIndexTo);

    return dx;
  }

  /**
   * @notice swap two tokens in the pool internally
   * @param self Swap struct to read from and write to
   * @param tokenIndexFrom the token the user wants to sell
   * @param tokenIndexTo the token the user wants to buy
   * @param dx the amount of tokens the user wants to sell
   * @param minDy the min amount the user would like to receive, or revert.
   * @return amount of token user received on swap
   */
  function swapInternal(
    Swap storage self,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 dx,
    uint256 minDy
  ) internal returns (uint256) {
    IERC20 tokenFrom = self.pooledTokens[tokenIndexFrom];
    require(dx <= tokenFrom.balanceOf(msg.sender), "more than you own");

    uint256 dy;
    uint256 dyFee;
    uint256[] memory balances = self.balances;
    (dy, dyFee) = _calculateSwap(self, tokenIndexFrom, tokenIndexTo, dx, balances);
    require(dy >= minDy, "dy < minDy");

    uint256 dyAdminFee = (dyFee * self.adminFee) / FEE_DENOMINATOR / self.tokenPrecisionMultipliers[tokenIndexTo];

    self.balances[tokenIndexFrom] = balances[tokenIndexFrom] + dx;
    self.balances[tokenIndexTo] = balances[tokenIndexTo] - dy - dyAdminFee;

    if (dyAdminFee != 0) {
      self.adminFees[tokenIndexTo] = self.adminFees[tokenIndexTo] + dyAdminFee;
    }

    emit TokenSwap(self.key, msg.sender, dx, dy, tokenIndexFrom, tokenIndexTo);

    return dy;
  }

  /**
   * @notice Should get exact amount out of AMM for asset put in
   */
  function swapInternalOut(
    Swap storage self,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 dy,
    uint256 maxDx
  ) internal returns (uint256) {
    require(dy <= self.balances[tokenIndexTo], "more than pool balance");

    uint256 dx;
    uint256 dxFee;
    uint256[] memory balances = self.balances;
    (dx, dxFee) = _calculateSwapInv(self, tokenIndexFrom, tokenIndexTo, dy, balances);
    require(dx <= maxDx, "dx > maxDx");

    uint256 dxAdminFee = (dxFee * self.adminFee) / FEE_DENOMINATOR / self.tokenPrecisionMultipliers[tokenIndexFrom];

    self.balances[tokenIndexFrom] = balances[tokenIndexFrom] + dx - dxAdminFee;
    self.balances[tokenIndexTo] = balances[tokenIndexTo] - dy;

    if (dxAdminFee != 0) {
      self.adminFees[tokenIndexFrom] = self.adminFees[tokenIndexFrom] + dxAdminFee;
    }

    emit TokenSwap(self.key, msg.sender, dx, dy, tokenIndexFrom, tokenIndexTo);

    return dx;
  }

  /**
   * @notice Add liquidity to the pool
   * @param self Swap struct to read from and write to
   * @param amounts the amounts of each token to add, in their native precision
   * @param minToMint the minimum LP tokens adding this amount of liquidity
   * should mint, otherwise revert. Handy for front-running mitigation
   * allowed addresses. If the pool is not in the guarded launch phase, this parameter will be ignored.
   * @return amount of LP token user received
   */
  function addLiquidity(
    Swap storage self,
    uint256[] memory amounts,
    uint256 minToMint
  ) internal returns (uint256) {
    uint256 numTokens = self.pooledTokens.length;
    require(amounts.length == numTokens, "mismatch pooled tokens");

    // current state
    ManageLiquidityInfo memory v = ManageLiquidityInfo(
      0,
      0,
      0,
      _getAPrecise(self),
      self.lpToken,
      0,
      self.balances,
      self.tokenPrecisionMultipliers
    );
    v.totalSupply = v.lpToken.totalSupply();
    if (v.totalSupply != 0) {
      v.d0 = getD(_xp(v.balances, v.multipliers), v.preciseA);
    }

    uint256[] memory newBalances = new uint256[](numTokens);

    for (uint256 i; i < numTokens; ) {
      require(v.totalSupply != 0 || amounts[i] != 0, "!supply all tokens");

      // Transfer tokens first to see if a fee was charged on transfer
      if (amounts[i] != 0) {
        IERC20 token = self.pooledTokens[i];
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amounts[i]);

        // Update the amounts[] with actual transfer amount
        amounts[i] = token.balanceOf(address(this)) - beforeBalance;
      }

      newBalances[i] = v.balances[i] + amounts[i];

      unchecked {
        ++i;
      }
    }

    // invariant after change
    v.d1 = getD(_xp(newBalances, v.multipliers), v.preciseA);
    require(v.d1 > v.d0, "D should increase");

    // updated to reflect fees and calculate the user's LP tokens
    v.d2 = v.d1;
    uint256[] memory fees = new uint256[](numTokens);

    if (v.totalSupply != 0) {
      uint256 feePerToken = _feePerToken(self.swapFee, numTokens);
      for (uint256 i; i < numTokens; ) {
        uint256 idealBalance = (v.d1 * v.balances[i]) / v.d0;
        fees[i] = (feePerToken * (idealBalance.difference(newBalances[i]))) / FEE_DENOMINATOR;
        uint256 adminFee = (fees[i] * self.adminFee) / FEE_DENOMINATOR;
        self.balances[i] = newBalances[i] - adminFee;
        self.adminFees[i] = self.adminFees[i] + adminFee;
        newBalances[i] = newBalances[i] - fees[i];

        unchecked {
          ++i;
        }
      }
      v.d2 = getD(_xp(newBalances, v.multipliers), v.preciseA);
    } else {
      // the initial depositor doesn't pay fees
      self.balances = newBalances;
    }

    uint256 toMint;
    if (v.totalSupply == 0) {
      toMint = v.d1;
    } else {
      toMint = ((v.d2 - v.d0) * v.totalSupply) / v.d0;
    }

    require(toMint >= minToMint, "mint < min");

    // mint the user's LP tokens
    v.lpToken.mint(msg.sender, toMint);

    emit AddLiquidity(self.key, msg.sender, amounts, fees, v.d1, v.totalSupply + toMint);

    return toMint;
  }

  /**
   * @notice Burn LP tokens to remove liquidity from the pool.
   * @dev Liquidity can always be removed, even when the pool is paused.
   * @param self Swap struct to read from and write to
   * @param amount the amount of LP tokens to burn
   * @param minAmounts the minimum amounts of each token in the pool
   * acceptable for this burn. Useful as a front-running mitigation
   * @return amounts of tokens the user received
   */
  function removeLiquidity(
    Swap storage self,
    uint256 amount,
    uint256[] calldata minAmounts
  ) internal returns (uint256[] memory) {
    LPToken lpToken = self.lpToken;
    require(amount <= lpToken.balanceOf(msg.sender), ">LP.balanceOf");
    uint256 numTokens = self.pooledTokens.length;
    require(minAmounts.length == numTokens, "mismatch poolTokens");

    uint256[] memory balances = self.balances;
    uint256 totalSupply = lpToken.totalSupply();

    uint256[] memory amounts = _calculateRemoveLiquidity(balances, amount, totalSupply);

    uint256 numAmounts = amounts.length;
    for (uint256 i; i < numAmounts; ) {
      require(amounts[i] >= minAmounts[i], "amounts[i] < minAmounts[i]");
      self.balances[i] = balances[i] - amounts[i];
      self.pooledTokens[i].safeTransfer(msg.sender, amounts[i]);

      unchecked {
        ++i;
      }
    }

    lpToken.burnFrom(msg.sender, amount);

    emit RemoveLiquidity(self.key, msg.sender, amounts, totalSupply - amount);

    return amounts;
  }

  /**
   * @notice Remove liquidity from the pool all in one token.
   * @param self Swap struct to read from and write to
   * @param tokenAmount the amount of the lp tokens to burn
   * @param tokenIndex the index of the token you want to receive
   * @param minAmount the minimum amount to withdraw, otherwise revert
   * @return amount chosen token that user received
   */
  function removeLiquidityOneToken(
    Swap storage self,
    uint256 tokenAmount,
    uint8 tokenIndex,
    uint256 minAmount
  ) internal returns (uint256) {
    LPToken lpToken = self.lpToken;

    require(tokenAmount <= lpToken.balanceOf(msg.sender), ">LP.balanceOf");
    uint256 numTokens = self.pooledTokens.length;
    require(tokenIndex < numTokens, "not found");

    uint256 totalSupply = lpToken.totalSupply();

    (uint256 dy, uint256 dyFee) = _calculateWithdrawOneToken(self, tokenAmount, tokenIndex, totalSupply);

    require(dy >= minAmount, "dy < minAmount");

    uint256 adminFee = (dyFee * self.adminFee) / FEE_DENOMINATOR;
    self.balances[tokenIndex] = self.balances[tokenIndex] - (dy + adminFee);
    if (adminFee != 0) {
      self.adminFees[tokenIndex] = self.adminFees[tokenIndex] + adminFee;
    }
    lpToken.burnFrom(msg.sender, tokenAmount);
    self.pooledTokens[tokenIndex].safeTransfer(msg.sender, dy);

    emit RemoveLiquidityOne(self.key, msg.sender, tokenAmount, totalSupply, tokenIndex, dy);

    return dy;
  }

  /**
   * @notice Remove liquidity from the pool, weighted differently than the
   * pool's current balances.
   *
   * @param self Swap struct to read from and write to
   * @param amounts how much of each token to withdraw
   * @param maxBurnAmount the max LP token provider is willing to pay to
   * remove liquidity. Useful as a front-running mitigation.
   * @return actual amount of LP tokens burned in the withdrawal
   */
  function removeLiquidityImbalance(
    Swap storage self,
    uint256[] memory amounts,
    uint256 maxBurnAmount
  ) internal returns (uint256) {
    ManageLiquidityInfo memory v = ManageLiquidityInfo(
      0,
      0,
      0,
      _getAPrecise(self),
      self.lpToken,
      0,
      self.balances,
      self.tokenPrecisionMultipliers
    );
    v.totalSupply = v.lpToken.totalSupply();

    uint256 numTokens = self.pooledTokens.length;
    uint256 numAmounts = amounts.length;
    require(numAmounts == numTokens, "mismatch pool tokens");

    require(maxBurnAmount <= v.lpToken.balanceOf(msg.sender) && maxBurnAmount != 0, ">LP.balanceOf");

    uint256 feePerToken = _feePerToken(self.swapFee, numTokens);
    uint256[] memory fees = new uint256[](numTokens);
    {
      uint256[] memory balances1 = new uint256[](numTokens);
      v.d0 = getD(_xp(v.balances, v.multipliers), v.preciseA);
      for (uint256 i; i < numTokens; ) {
        require(v.balances[i] >= amounts[i], "withdraw more than available");

        unchecked {
          balances1[i] = v.balances[i] - amounts[i];
          ++i;
        }
      }
      v.d1 = getD(_xp(balances1, v.multipliers), v.preciseA);

      for (uint256 i; i < numTokens; ) {
        {
          uint256 idealBalance = (v.d1 * v.balances[i]) / v.d0;
          uint256 difference = idealBalance.difference(balances1[i]);
          fees[i] = (feePerToken * difference) / FEE_DENOMINATOR;
        }
        uint256 adminFee = (fees[i] * self.adminFee) / FEE_DENOMINATOR;
        self.balances[i] = balances1[i] - adminFee;
        self.adminFees[i] = self.adminFees[i] + adminFee;
        balances1[i] = balances1[i] - fees[i];

        unchecked {
          ++i;
        }
      }

      v.d2 = getD(_xp(balances1, v.multipliers), v.preciseA);
    }
    uint256 tokenAmount = ((v.d0 - v.d2) * v.totalSupply) / v.d0;
    require(tokenAmount != 0, "!zero amount");
    tokenAmount = tokenAmount + 1;

    require(tokenAmount <= maxBurnAmount, "tokenAmount > maxBurnAmount");

    v.lpToken.burnFrom(msg.sender, tokenAmount);

    for (uint256 i; i < numTokens; ) {
      self.pooledTokens[i].safeTransfer(msg.sender, amounts[i]);

      unchecked {
        ++i;
      }
    }

    emit RemoveLiquidityImbalance(self.key, msg.sender, amounts, fees, v.d1, v.totalSupply - tokenAmount);

    return tokenAmount;
  }

  /**
   * @notice withdraw all admin fees to a given address
   * @param self Swap struct to withdraw fees from
   * @param to Address to send the fees to
   */
  function withdrawAdminFees(Swap storage self, address to) internal {
    uint256 numTokens = self.pooledTokens.length;
    for (uint256 i; i < numTokens; ) {
      IERC20 token = self.pooledTokens[i];
      uint256 balance = self.adminFees[i];
      if (balance != 0) {
        self.adminFees[i] = 0;
        token.safeTransfer(to, balance);
      }

      unchecked {
        ++i;
      }
    }
  }

  /**
   * @notice Sets the admin fee
   * @dev adminFee cannot be higher than 100% of the swap fee
   * @param self Swap struct to update
   * @param newAdminFee new admin fee to be applied on future transactions
   */
  function setAdminFee(Swap storage self, uint256 newAdminFee) internal {
    require(newAdminFee <= MAX_ADMIN_FEE, "too high");
    self.adminFee = newAdminFee;

    emit NewAdminFee(self.key, newAdminFee);
  }

  /**
   * @notice update the swap fee
   * @dev fee cannot be higher than 1% of each swap
   * @param self Swap struct to update
   * @param newSwapFee new swap fee to be applied on future transactions
   */
  function setSwapFee(Swap storage self, uint256 newSwapFee) internal {
    require(newSwapFee <= MAX_SWAP_FEE, "too high");
    self.swapFee = newSwapFee;

    emit NewSwapFee(self.key, newSwapFee);
  }
}
