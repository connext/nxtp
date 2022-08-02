// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {BaseConnextFacet} from "./BaseConnextFacet.sol";
import {AmplificationUtils, SwapUtils} from "../libraries/AmplificationUtils.sol";
import {LPToken} from "../helpers/LPToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title SwapAdminFacet
 * @notice Contract module which exposes only-admin controls for the StableSwapFacet
 * contract.
 *
 * @dev This module is used through inheritance. It will make available the
 * modifier `onlyOwner`, which can be applied to your functions to restrict
 * their use to the owner.
 */
contract SwapAdminFacet is BaseConnextFacet {
  using SwapUtils for SwapUtils.Swap;
  using AmplificationUtils for SwapUtils.Swap;

  // ========== Custom Errors ===========
  error SwapAdminFacet__initializeSwap_alreadyInitialized();
  error SwapAdminFacet__initializeSwap_invalidPooledTokens();
  error SwapAdminFacet__initializeSwap_decimalsMismatch();
  error SwapAdminFacet__initializeSwap_duplicateTokens();
  error SwapAdminFacet__initializeSwap_zeroTokenAddress();
  error SwapAdminFacet__initializeSwap_tokenDecimalsExceedMax();
  error SwapAdminFacet__initializeSwap_aExceedMax();
  error SwapAdminFacet__initializeSwap_feeExceedMax();
  error SwapAdminFacet__initializeSwap_adminFeeExceedMax();
  error SwapAdminFacet__initializeSwap_failedInitLpTokenClone();

  // ============ Properties ============

  // ============ Events ============

  /**
   * @notice Emitted when the owner calls `initializeSwap`
   * @param key - Identifier for asset
   * @param swap - The swap that was initialized
   * @param caller - The caller of the function
   */
  event SwapInitialized(bytes32 indexed key, SwapUtils.Swap swap, address caller);

  /**
   * @notice Emitted when the owner withdraws admin fees
   * @param key - Identifier for asset
   * @param caller - The caller of the function
   */
  event AdminFeesWithdrawn(bytes32 indexed key, address caller);

  /**
   * @notice Emitted when the owner sets admin fees
   * @param key - Identifier for asset
   * @param newAdminFee - The updated fee
   * @param caller - The caller of the function
   */
  event AdminFeesSet(bytes32 indexed key, uint256 newAdminFee, address caller);

  /**
   * @notice Emitted when the owner sets swap fees
   * @param key - Identifier for asset
   * @param newSwapFee - The updated fee
   * @param caller - The caller of the function
   */
  event SwapFeesSet(bytes32 indexed key, uint256 newSwapFee, address caller);

  /**
   * @notice Emitted when the owner starts ramping up or down the A parameter
   * @param key - Identifier for asset
   * @param futureA - The final A value after ramp
   * @param futureTime - The time A should reach the final value
   * @param caller - The caller of the function
   */
  event RampAStarted(bytes32 indexed key, uint256 futureA, uint256 futureTime, address caller);

  /**
   * @notice Emitted when the owner stops ramping up or down the A parameter
   * @param key - Identifier for asset
   * @param caller - The caller of the function
   */
  event RampAStopped(bytes32 indexed key, address caller);

  // ============ External: Getters ============

  /*** StableSwap ADMIN FUNCTIONS ***/
  /**
   * @notice Initializes this Swap contract with the given parameters.
   * This will also clone a LPToken contract that represents users'
   * LP positions. The owner of LPToken will be this contract - which means
   * only this contract is allowed to mint/burn tokens.
   *
   * @param _key the hash of the canonical id and domain for token
   * @param _pooledTokens an array of ERC20s this pool will accept
   * @param decimals the decimals to use for each pooled token,
   * eg 8 for WBTC. Cannot be larger than POOL_PRECISION_DECIMALS
   * @param lpTokenName the long-form name of the token to be deployed
   * @param lpTokenSymbol the short symbol for the token to be deployed
   * @param _a the amplification coefficient * n * (n - 1). See the
   * StableSwap paper for details
   * @param _fee default swap fee to be initialized with
   * @param _adminFee default adminFee to be initialized with
   * @param lpTokenTargetAddress the address of an existing LPToken contract to use as a target
   */
  function initializeSwap(
    bytes32 _key,
    IERC20[] memory _pooledTokens,
    uint8[] memory decimals,
    string memory lpTokenName,
    string memory lpTokenSymbol,
    uint256 _a,
    uint256 _fee,
    uint256 _adminFee,
    address lpTokenTargetAddress
  ) external onlyOwner {
    if (s.swapStorages[_key].pooledTokens.length != 0) revert SwapAdminFacet__initializeSwap_alreadyInitialized();

    // Check _pooledTokens and precisions parameter
    if (_pooledTokens.length <= 1 || _pooledTokens.length > 32)
      revert SwapAdminFacet__initializeSwap_invalidPooledTokens();

    uint8 numPooledTokens = uint8(_pooledTokens.length);

    if (numPooledTokens != decimals.length) revert SwapAdminFacet__initializeSwap_decimalsMismatch();

    uint256[] memory precisionMultipliers = new uint256[](decimals.length);

    for (uint8 i; i < numPooledTokens; ) {
      if (i != 0) {
        // Check if index is already used. Check if 0th element is a duplicate.
        if (s.tokenIndexes[_key][address(_pooledTokens[i])] != 0 || _pooledTokens[0] == _pooledTokens[i])
          revert SwapAdminFacet__initializeSwap_duplicateTokens();
      }
      if (address(_pooledTokens[i]) == address(0)) revert SwapAdminFacet__initializeSwap_zeroTokenAddress();

      if (decimals[i] > SwapUtils.POOL_PRECISION_DECIMALS)
        revert SwapAdminFacet__initializeSwap_tokenDecimalsExceedMax();

      precisionMultipliers[i] = 10**uint256(SwapUtils.POOL_PRECISION_DECIMALS - decimals[i]);
      s.tokenIndexes[_key][address(_pooledTokens[i])] = i;

      unchecked {
        ++i;
      }
    }

    // Check _a, _fee, _adminFee, _withdrawFee parameters
    if (_a >= AmplificationUtils.MAX_A) revert SwapAdminFacet__initializeSwap_aExceedMax();
    if (_fee >= SwapUtils.MAX_SWAP_FEE) revert SwapAdminFacet__initializeSwap_feeExceedMax();
    if (_adminFee >= SwapUtils.MAX_ADMIN_FEE) revert SwapAdminFacet__initializeSwap_adminFeeExceedMax();

    // Initialize a LPToken contract
    LPToken lpToken = LPToken(Clones.clone(lpTokenTargetAddress));
    if (!lpToken.initialize(lpTokenName, lpTokenSymbol)) revert SwapAdminFacet__initializeSwap_failedInitLpTokenClone();

    // Initialize swapStorage struct
    SwapUtils.Swap memory entry = SwapUtils.Swap({
      key: _key,
      initialA: _a * AmplificationUtils.A_PRECISION,
      futureA: _a * AmplificationUtils.A_PRECISION,
      swapFee: _fee,
      adminFee: _adminFee,
      lpToken: lpToken,
      pooledTokens: _pooledTokens,
      tokenPrecisionMultipliers: precisionMultipliers,
      balances: new uint256[](_pooledTokens.length),
      adminFees: new uint256[](_pooledTokens.length),
      initialATime: 0,
      futureATime: 0
    });
    s.swapStorages[_key] = entry;
    emit SwapInitialized(_key, entry, msg.sender);
  }

  /**
   * @notice Withdraw all admin fees to the contract owner
   * @param key Hash of the canonical domain and id
   */
  function withdrawSwapAdminFees(bytes32 key) external onlyOwner nonReentrant {
    s.swapStorages[key].withdrawAdminFees(msg.sender);
    emit AdminFeesWithdrawn(key, msg.sender);
  }

  /**
   * @notice Update the admin fee. Admin fee takes portion of the swap fee.
   * @param key Hash of the canonical domain and id
   * @param newAdminFee new admin fee to be applied on future transactions
   */
  function setSwapAdminFee(bytes32 key, uint256 newAdminFee) external onlyOwner {
    s.swapStorages[key].setAdminFee(newAdminFee);
    emit AdminFeesSet(key, newAdminFee, msg.sender);
  }

  /**
   * @notice Update the swap fee to be applied on swaps
   * @param key Hash of the canonical domain and id
   * @param newSwapFee new swap fee to be applied on future transactions
   */
  function setSwapFee(bytes32 key, uint256 newSwapFee) external onlyOwner {
    s.swapStorages[key].setSwapFee(newSwapFee);
    emit SwapFeesSet(key, newSwapFee, msg.sender);
  }

  /**
   * @notice Start ramping up or down A parameter towards given futureA and futureTime
   * Checks if the change is too rapid, and commits the new A value only when it falls under
   * the limit range.
   * @param key Hash of the canonical domain and id
   * @param futureA the new A to ramp towards
   * @param futureTime timestamp when the new A should be reached
   */
  function rampA(
    bytes32 key,
    uint256 futureA,
    uint256 futureTime
  ) external onlyOwner {
    s.swapStorages[key].rampA(futureA, futureTime);
    emit RampAStarted(key, futureA, futureTime, msg.sender);
  }

  /**
   * @notice Stop ramping A immediately. Reverts if ramp A is already stopped.
   * @param key Hash of the canonical domain and id
   */
  function stopRampA(bytes32 key) external onlyOwner {
    s.swapStorages[key].stopRampA();
    emit RampAStopped(key, msg.sender);
  }
}
