// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {SafeERC20, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IStableSwap} from "../interfaces/IStableSwap.sol";

import {IWeth} from "../interfaces/IWeth.sol";
import {ITokenRegistry} from "../interfaces/ITokenRegistry.sol";

import {LibConnextStorage, AppStorage, TokenId} from "./LibConnextStorage.sol";
import {SwapUtils} from "./SwapUtils.sol";

library AssetLogic {
  // ============ Libraries ============
  using SwapUtils for SwapUtils.Swap;

  // ============ Errors ============

  error AssetLogic__handleIncomingAsset_nativeAssetNotSupported();
  error AssetLogic__handleOutgoingAsset_notNative();
  error AssetLogic__transferAssetToContract_feeOnTransferNotSupported();
  error AssetLogic__swapToLocalAssetIfNeeded_swapPaused();
  error AssetLogic__swapFromLocalAssetIfNeeded_swapPaused();
  error AssetLogic__getTokenIndexFromStableSwapPool_notExist();

  // ============ Internal ============

  /**
   * @notice Check if the stabelswap pool exists or not
   * @param key the hash of the canonical id and domain
   */
  function stableSwapPoolExist(bytes32 key) internal view returns (bool) {
    AppStorage storage s = LibConnextStorage.connextStorage();
    return s.swapStorages[key].pooledTokens.length != 0;
  }

  /**
   * @notice Return the index of the given token address. Reverts if no matching
   * token is found.
   * @param key the hash of the canonical id and domain
   * @param tokenAddress address of the token
   * @return the index of the given token address
   */
  function getTokenIndexFromStableSwapPool(bytes32 key, address tokenAddress) internal view returns (uint8) {
    AppStorage storage s = LibConnextStorage.connextStorage();
    uint8 index = s.tokenIndexes[key][tokenAddress];
    if (address(s.swapStorages[key].pooledTokens[index]) != tokenAddress)
      revert AssetLogic__getTokenIndexFromStableSwapPool_notExist();
    return index;
  }

  /**
   * @notice Handles transferring funds from msg.sender to the Connext contract.
   * @dev Only allows native asset to be used for fee
   * @param _assetId - The address to transfer
   * @param _assetAmount - The specified amount to transfer. May not be the
   * actual amount transferred (i.e. fee on transfer tokens)
   */
  function handleIncomingAsset(address _assetId, uint256 _assetAmount) internal {
    if (_assetId == address(0)) {
      revert AssetLogic__handleIncomingAsset_nativeAssetNotSupported();
    }

    // Transfer asset to contract
    transferAssetToContract(_assetId, _assetAmount);
  }

  /**
   * @notice Handles transferring funds from msg.sender to the Connext contract.
   * @param _assetId - The address to transfer
   * @param _to - The account that will receive the withdrawn funds
   * @param _amount - The amount to withdraw from contract
   */
  function handleOutgoingAsset(
    address _assetId,
    address _to,
    uint256 _amount
  ) internal {
    // No native assets should ever be stored on this contract
    if (_assetId == address(0)) revert AssetLogic__handleOutgoingAsset_notNative();

    // If amount is 0 do nothing
    if (_amount == 0) {
      return;
    }

    // Transfer ERC20 asset
    SafeERC20.safeTransfer(IERC20(_assetId), _to, _amount);
  }

  /**
   * @notice Transfer asset funds from msg.sender to the Connext contract.
   * @param _assetId - The address to transfer
   * @param _amount - The specified amount to transfer
   */
  function transferAssetToContract(address _assetId, uint256 _amount) internal {
    // Validate correct amounts are transferred
    uint256 starting = IERC20(_assetId).balanceOf(address(this));

    SafeERC20.safeTransferFrom(IERC20(_assetId), msg.sender, address(this), _amount);
    // Ensure this was not a fee-on-transfer token
    if (IERC20(_assetId).balanceOf(address(this)) - starting != _amount) {
      revert AssetLogic__transferAssetToContract_feeOnTransferNotSupported();
    }
  }

  /**
   * @notice Swaps an adopted asset to the local (representation or canonical) nomad asset
   * @dev Will not swap if the asset passed in is the local asset
   * @param _canonical - The canonical token
   * @param _asset - The address of the adopted asset to swap into the local asset
   * @param _amount - The amount of the adopted asset to swap
   * @param _minOut - The minimum amount of `_assetOut` the user will accept
   * @return The amount of local asset received from swap
   * @return The address of asset received post-swap
   */
  function swapToLocalAssetIfNeeded(
    TokenId memory _canonical,
    address _asset,
    uint256 _amount,
    uint256 _minOut
  ) internal returns (uint256, address) {
    AppStorage storage s = LibConnextStorage.connextStorage();

    // Get the local token for this domain (may return canonical or representation).
    address local = s.tokenRegistry.getLocalAddress(_canonical.domain, _canonical.id);

    // If there's no amount, no need to swap.
    if (_amount == 0) {
      return (_amount, local);
    }

    // Check the case where the adopted asset *is* the local asset. If so, no need to swap.
    if (local == _asset) {
      return (_amount, _asset);
    }

    // Swap the asset to the proper local asset.
    bytes32 key = keccak256(abi.encode(_canonical.id, _canonical.domain));
    return _swapAsset(key, _asset, local, _amount, _minOut);
  }

  /**
   * @notice Swaps a local nomad asset for the adopted asset using the stored stable swap
   * @dev Will not swap if the asset passed in is the adopted asset
   * @param _key the hash of the canonical id and domain
   * @param _asset - The address of the local asset to swap into the adopted asset
   * @param _amount - The amount of the local asset to swap
   * @param _minOut - The minimum amount of `_assetOut` the user will accept
   * @return The amount of adopted asset received from swap
   * @return The address of asset received post-swap
   */
  function swapFromLocalAssetIfNeeded(
    bytes32 _key,
    address _asset,
    uint256 _amount,
    uint256 _minOut
  ) internal returns (uint256, address) {
    AppStorage storage s = LibConnextStorage.connextStorage();

    // If the adopted asset is the local asset, no need to swap
    address adopted = s.canonicalToAdopted[_key];
    if (adopted == _asset) {
      return (_amount, _asset);
    }

    // If 0 valued, do nothing
    if (_amount == 0) {
      return (_amount, adopted);
    }

    // Swap the asset to the proper local asset
    return _swapAsset(_key, _asset, adopted, _amount, _minOut);
  }

  /**
   * @notice Swaps a local nomad asset for the adopted asset using the stored stable swap
   * @dev Will not swap if the asset passed in is the adopted asset
   * @param _key the hash of the canonical id and domain
   * @param _asset - The address of the local asset to swap into the adopted asset
   * @param _amount - The exact amount to receive out of the swap
   * @param _maxIn - The most you will supply to the swap
   * @return The amount of local asset put into  swap
   * @return The address of asset received post-swap
   */
  function swapFromLocalAssetIfNeededForExactOut(
    bytes32 _key,
    address _asset,
    uint256 _amount,
    uint256 _maxIn
  )
    internal
    returns (
      bool,
      uint256,
      address
    )
  {
    AppStorage storage s = LibConnextStorage.connextStorage();

    // If the adopted asset is the local asset, no need to swap
    address adopted = s.canonicalToAdopted[_key];
    if (adopted == _asset) {
      return (true, _amount, _asset);
    }

    return _swapAssetOut(_key, _asset, adopted, _amount, _maxIn);
  }

  /**
   * @notice Swaps assetIn to assetOut using the stored stable swap or internal swap pool
   * @dev Will not swap if the asset passed in is the adopted asset
   * @param _key - The canonical token id
   * @param _assetIn - The address of the from asset
   * @param _assetOut - The address of the to asset
   * @param _amount - The amount of the local asset to swap
   * @param _minOut - The minimum amount of `_assetOut` the user will accept
   * @return The amount of assetOut
   * @return The address of assetOut
   */
  function _swapAsset(
    bytes32 _key,
    address _assetIn,
    address _assetOut,
    uint256 _amount,
    uint256 _minOut
  ) internal returns (uint256, address) {
    AppStorage storage s = LibConnextStorage.connextStorage();

    if (stableSwapPoolExist(_key)) {
      // if internal swap pool exists
      return (
        s.swapStorages[_key].swapInternal(
          getTokenIndexFromStableSwapPool(_key, _assetIn),
          getTokenIndexFromStableSwapPool(_key, _assetOut),
          _amount,
          _minOut
        ),
        _assetOut
      );
    } else {
      // Otherwise, swap via stable swap pool
      IStableSwap pool = s.adoptedToLocalPools[_key];

      SafeERC20.safeApprove(IERC20(_assetIn), address(pool), 0);
      SafeERC20.safeIncreaseAllowance(IERC20(_assetIn), address(pool), _amount);

      // NOTE: if pool is not registered here, then the following call will revert
      return (pool.swapExact(_amount, _assetIn, _assetOut, _minOut, block.timestamp + 3600), _assetOut);
    }
  }

  /**
   * @notice Swaps assetIn to assetOut using the stored stable swap or internal swap pool
   * @dev Will not swap if the asset passed in is the adopted asset
   * @param _key - The hash of the canonical id and domain
   * @param _assetIn - The address of the from asset
   * @param _assetOut - The address of the to asset
   * @param _amountOut - The amount of the _assetOut to swap
   * @param _maxIn - The most you will supply to the swap
   * @return Success value
   * @return The amount of assetIn
   * @return The address of assetOut
   */
  function _swapAssetOut(
    bytes32 _key,
    address _assetIn,
    address _assetOut,
    uint256 _amountOut,
    uint256 _maxIn
  )
    internal
    returns (
      bool,
      uint256,
      address
    )
  {
    AppStorage storage s = LibConnextStorage.connextStorage();

    bool success;
    uint256 amountIn;

    // Swap the asset to the proper local asset
    if (stableSwapPoolExist(_key)) {
      // get internal swap pool
      SwapUtils.Swap storage ipool = s.swapStorages[_key];
      // if internal swap pool exists
      uint8 tokenIndexIn = getTokenIndexFromStableSwapPool(_key, _assetIn);
      uint8 tokenIndexOut = getTokenIndexFromStableSwapPool(_key, _assetOut);
      // calculate slippage before performing swap
      // NOTE: this is less efficient then relying on the `swapInternalOut` revert, but makes it easier
      // to handle slippage failures (this can be called during reconcile, so must not fail)
      if (_maxIn >= ipool.calculateSwapInv(tokenIndexIn, tokenIndexOut, _amountOut)) {
        success = true;
        amountIn = ipool.swapInternalOut(tokenIndexIn, tokenIndexOut, _amountOut, _maxIn);
      }
      // slippage is too high to perform swap: success = false, amountIn = 0
    } else {
      // Otherwise, swap via stable swap pool
      IStableSwap pool = s.adoptedToLocalPools[_key];
      uint256 _amountIn = pool.calculateSwapOutFromAddress(_assetIn, _assetOut, _amountOut);
      if (_amountIn <= _maxIn) {
        // set the success
        success = true;

        // perform the swap
        // Edge case with some tokens: Example USDT in ETH Mainnet, after the backUnbacked call there could be a remaining allowance if not the whole amount is pulled by aave.
        // Later, if we try to increase the allowance it will fail. USDT demands if allowance is not 0, it has to be set to 0 first.
        // Example: https://github.com/aave/aave-v3-periphery/blob/ca184e5278bcbc10d28c3dbbc604041d7cfac50b/contracts/adapters/paraswap/ParaSwapRepayAdapter.sol#L138-L140
        SafeERC20.safeApprove(IERC20(_assetIn), address(pool), 0);
        SafeERC20.safeIncreaseAllowance(IERC20(_assetIn), address(pool), _amountIn);
        amountIn = pool.swapExactOut(_amountOut, _assetIn, _assetOut, _maxIn, block.timestamp + 3600);
      }
      // slippage is too high to perform swap: success = false, amountIn = 0
    }

    return (success, amountIn, _assetOut);
  }

  /**
   * @notice Calculate amount of tokens you receive on a local nomad asset for the adopted asset
   * using the stored stable swap
   * @dev Will not use the stored stable swap if the asset passed in is the local asset
   * @param _key - The hash of the canonical id and domain
   * @param _asset - The address of the local asset to swap into the local asset
   * @param _amount - The amount of the local asset to swap
   * @return The amount of local asset received from swap
   * @return The address of asset received post-swap
   */
  function calculateSwapFromLocalAssetIfNeeded(
    bytes32 _key,
    address _asset,
    uint256 _amount
  ) internal view returns (uint256, address) {
    AppStorage storage s = LibConnextStorage.connextStorage();

    // If the adopted asset is the local asset, no need to swap
    address adopted = s.canonicalToAdopted[_key];
    if (adopted == _asset) {
      return (_amount, _asset);
    }

    // Otherwise, calculate swap the asset to the proper local asset
    if (stableSwapPoolExist(_key)) {
      // if internal swap pool exists
      uint8 tokenIndexIn = getTokenIndexFromStableSwapPool(_key, _asset);
      uint8 tokenIndexOut = getTokenIndexFromStableSwapPool(_key, adopted);
      return (s.swapStorages[_key].calculateSwap(tokenIndexIn, tokenIndexOut, _amount), adopted);
    } else {
      IStableSwap pool = s.adoptedToLocalPools[_key];

      return (pool.calculateSwapFromAddress(_asset, adopted, _amount), adopted);
    }
  }

  /**
   * @notice Calculate amount of tokens you receive of a local nomad asset for the adopted asset
   * using the stored stable swap
   * @dev Will not use the stored stable swap if the asset passed in is the local asset
   * @param _asset - The address of the asset to swap into the local asset
   * @param _amount - The amount of the asset to swap
   * @return The amount of local asset received from swap
   * @return The address of asset received post-swap
   */
  function calculateSwapToLocalAssetIfNeeded(address _asset, uint256 _amount) internal view returns (uint256, address) {
    AppStorage storage s = LibConnextStorage.connextStorage();

    // Get the token id
    (uint32 domain, bytes32 id) = s.tokenRegistry.getTokenId(_asset);
    address local = s.tokenRegistry.getLocalAddress(domain, id);

    // If the asset is the local asset, no swap needed
    if (_asset == local) {
      return (_amount, _asset);
    }
    bytes32 key = keccak256(abi.encode(id, domain));

    // Otherwise, calculate swap the asset to the proper local asset
    if (stableSwapPoolExist(key)) {
      // if internal swap pool exists
      uint8 tokenIndexIn = getTokenIndexFromStableSwapPool(key, _asset);
      uint8 tokenIndexOut = getTokenIndexFromStableSwapPool(key, local);
      return (s.swapStorages[key].calculateSwap(tokenIndexIn, tokenIndexOut, _amount), local);
    } else {
      IStableSwap pool = s.adoptedToLocalPools[key];

      return (pool.calculateSwapFromAddress(_asset, local, _amount), local);
    }
  }
}
