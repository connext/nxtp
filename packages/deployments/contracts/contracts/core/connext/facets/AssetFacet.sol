// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {BaseConnextFacet} from "./BaseConnextFacet.sol";
import {TokenId} from "../libraries/LibConnextStorage.sol";
import {IStableSwap} from "../interfaces/IStableSwap.sol";
import {IWeth} from "../interfaces/IWeth.sol";
import {ITokenRegistry} from "../interfaces/ITokenRegistry.sol";

contract AssetFacet is BaseConnextFacet {
  // ========== Custom Errors ===========
  error AssetFacet__setTokenRegistry_invalidTokenRegistry();
  error AssetFacet__addAssetId_nativeAsset();
  error AssetFacet__addAssetId_alreadyAdded();
  error AssetFacet__removeAssetId_notAdded();

  // ============ Events ============

  /**
   * @notice Emitted when the tokenRegistry variable is updated
   * @param oldTokenRegistry - The tokenRegistry old value
   * @param newTokenRegistry - The tokenRegistry new value
   * @param caller - The account that called the function
   */
  event TokenRegistryUpdated(address oldTokenRegistry, address newTokenRegistry, address caller);

  /**
   * @notice Emitted when a new stable-swap AMM is added for the local <> adopted token
   * @param key - The key in the mapping (hash of canonical id and domain)
   * @param canonicalId - The canonical identifier of the token the local <> adopted AMM is for
   * @param domain - The domain of the canonical token for the local <> adopted amm
   * @param swapPool - The address of the AMM
   * @param caller - The account that called the function
   */
  event StableSwapAdded(
    bytes32 indexed key,
    bytes32 indexed canonicalId,
    uint32 indexed domain,
    address swapPool,
    address caller
  );

  /**
   * @notice Emitted when a new asset is added
   * @param key - The key in the mapping (hash of canonical id and domain)
   * @param canonicalId - The canonical identifier of the token the local <> adopted AMM is for
   * @param domain - The domain of the canonical token for the local <> adopted amm
   * @param adoptedAsset - The address of the adopted (user-expected) asset
   * @param caller - The account that called the function
   */
  event AssetAdded(
    bytes32 indexed key,
    bytes32 indexed canonicalId,
    uint32 indexed domain,
    address adoptedAsset,
    address caller
  );

  /**
   * @notice Emitted when an asset is removed from whitelists
   * @param key - The hash of the canonical identifier and domain of the token removed
   * @param caller - The account that called the function
   */
  event AssetRemoved(bytes32 indexed key, address caller);

  // ============ Getters ============

  function canonicalToAdopted(bytes32 _key) public view returns (address) {
    return s.canonicalToAdopted[_key];
  }

  function canonicalToAdopted(TokenId calldata _canonical) public view returns (address) {
    return canonicalToAdopted(_calculateCanonicalHash(_canonical));
  }

  function adoptedToCanonical(address _adopted) public view returns (TokenId memory) {
    TokenId memory canonical = TokenId(s.adoptedToCanonical[_adopted].domain, s.adoptedToCanonical[_adopted].id);
    return canonical;
  }

  function approvedAssets(bytes32 _key) public view returns (bool) {
    return s.approvedAssets[_key];
  }

  function approvedAssets(TokenId calldata _canonical) public view returns (bool) {
    return approvedAssets(_calculateCanonicalHash(_canonical));
  }

  function adoptedToLocalPools(bytes32 _key) public view returns (IStableSwap) {
    return s.adoptedToLocalPools[_key];
  }

  function adoptedToLocalPools(TokenId calldata _canonical) public view returns (IStableSwap) {
    return adoptedToLocalPools(_calculateCanonicalHash(_canonical));
  }

  function tokenRegistry() public view returns (ITokenRegistry) {
    return s.tokenRegistry;
  }

  // ============ Admin functions ============

  /**
   * @notice Updates the token registry
   * @param _tokenRegistry The new token registry address
   */
  function setTokenRegistry(address _tokenRegistry) external onlyOwner {
    address old = address(s.tokenRegistry);
    if (old == _tokenRegistry || !Address.isContract(_tokenRegistry))
      revert AssetFacet__setTokenRegistry_invalidTokenRegistry();

    s.tokenRegistry = ITokenRegistry(_tokenRegistry);
    emit TokenRegistryUpdated(old, _tokenRegistry, msg.sender);
  }

  /**
   * @notice Used to add supported assets. This is an admin only function
   *
   * @dev When whitelisting the canonical asset, all representational assets would be
   * whitelisted as well. In the event you have a different adopted asset (i.e. PoS USDC
   * on polygon), you should *not* whitelist the adopted asset. The stable swap pool
   * address used should allow you to swap between the local <> adopted asset.
   *
   * @param _canonical - The canonical asset to add by id and domain. All representations
   * will be whitelisted as well
   * @param _adoptedAssetId - The used asset id for this domain (e.g. PoS USDC for
   * polygon)
   * @param _stableSwapPool - The address of the local stableswap pool, if it exists.
   */
  function setupAsset(
    TokenId calldata _canonical,
    address _adoptedAssetId,
    address _stableSwapPool
  ) external onlyOwner {
    // Native asset support does not exist in this contract
    if (_adoptedAssetId == address(0)) revert AssetFacet__addAssetId_nativeAsset();

    // Get the key
    bytes32 key = _calculateCanonicalHash(_canonical);

    // Sanity check: needs approval
    if (s.approvedAssets[key]) revert AssetFacet__addAssetId_alreadyAdded();

    // Update approved assets mapping
    s.approvedAssets[key] = true;

    // Update the adopted mapping
    s.adoptedToCanonical[_adoptedAssetId].domain = _canonical.domain;
    s.adoptedToCanonical[_adoptedAssetId].id = _canonical.id;

    // Update the canonical mapping
    s.canonicalToAdopted[key] = _adoptedAssetId;

    // Emit event
    emit AssetAdded(key, _canonical.id, _canonical.domain, _adoptedAssetId, msg.sender);

    // Add the swap pool
    _addStableSwapPool(_canonical, _stableSwapPool, key);
  }

  /**
   * @notice Adds a stable swap pool for the local <> adopted asset.
   * @dev Must pass in the _canonical information so it can be emitted in event
   */
  function addStableSwapPool(TokenId calldata _canonical, address _stableSwapPool) external onlyOwner {
    bytes32 key = _calculateCanonicalHash(_canonical);
    _addStableSwapPool(_canonical, _stableSwapPool, key);
  }

  /**
   * @notice Used to remove assets from the whitelist
   * @param _key - The hash of the canonical id and domain to remove (mapping key)
   * @param _adoptedAssetId - Corresponding adopted asset to remove
   */
  function removeAssetId(bytes32 _key, address _adoptedAssetId) external onlyOwner {
    _removeAssetId(_key, _adoptedAssetId);
  }

  /**
   * @notice Used to remove assets from the whitelist
   * @param _canonical - The canonical id and domain to remove
   * @param _adoptedAssetId - Corresponding adopted asset to remove
   */
  function removeAssetId(TokenId calldata _canonical, address _adoptedAssetId) external onlyOwner {
    bytes32 key = _calculateCanonicalHash(_canonical);
    _removeAssetId(key, _adoptedAssetId);
  }

  // ============ Private Functions ============

  /**
   * @notice Used to add an AMM for adopted <> local assets
   * @param _canonical - The canonical TokenId to add (domain and id)
   * @param _stableSwap - The address of the amm to add
   * @param _key - The hash of the canonical id and domain
   */
  function _addStableSwapPool(
    TokenId calldata _canonical,
    address _stableSwap,
    bytes32 _key
  ) internal {
    // Update the pool mapping
    s.adoptedToLocalPools[_key] = IStableSwap(_stableSwap);

    emit StableSwapAdded(_key, _canonical.id, _canonical.domain, _stableSwap, msg.sender);
  }

  /**
   * @notice Used to remove assets from the whitelist
   * @param _key - The hash of the canonical id and domain to remove (mapping key)
   * @param _adoptedAssetId - Corresponding adopted asset to remove
   */
  function _removeAssetId(bytes32 _key, address _adoptedAssetId) internal {
    // Sanity check: already approval
    if (!s.approvedAssets[_key]) revert AssetFacet__removeAssetId_notAdded();

    // Delete from approved assets mapping
    delete s.approvedAssets[_key];

    // Delete from pools
    delete s.adoptedToLocalPools[_key];

    // Delete from adopted mapping
    delete s.adoptedToCanonical[_adoptedAssetId];

    // Delete from canonical mapping
    delete s.canonicalToAdopted[_key];

    // Emit event
    emit AssetRemoved(_key, msg.sender);
  }
}
