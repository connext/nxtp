// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {BaseConnextFacet} from "./BaseConnextFacet.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IProposedOwnable} from "../../shared/interfaces/IProposedOwnable.sol";

/**
 * @title ProposedOwnable
 * @notice Contract module which provides a basic access control mechanism,
 * where there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed via a two step process:
 * 1. Call `proposeOwner`
 * 2. Wait out the delay period
 * 3. Call `acceptOwner`
 *
 * @dev This module is used through inheritance. It will make available the
 * modifier `onlyOwner`, which can be applied to your functions to restrict
 * their use to the owner.
 *
 * @dev The majority of this code was taken from the openzeppelin Ownable
 * contract
 *
 */
contract ProposedOwnableFacet is BaseConnextFacet, IProposedOwnable {
  // ========== Custom Errors ===========
  error ProposedOwnableFacet__proposeRouterWhitelistRemoval_noOwnershipChange();
  error ProposedOwnableFacet__removeRouterWhitelist_noOwnershipChange();
  error ProposedOwnableFacet__removeRouterWhitelist_noProposal();
  error ProposedOwnableFacet__removeRouterWhitelist_delayNotElapsed();
  error ProposedOwnableFacet__proposeAssetWhitelistRemoval_noOwnershipChange();
  error ProposedOwnableFacet__removeAssetWhitelist_noOwnershipChange();
  error ProposedOwnableFacet__removeAssetWhitelist_noProposal();
  error ProposedOwnableFacet__removeAssetWhitelist_delayNotElapsed();
  error ProposedOwnableFacet__proposeNewOwner_invalidProposal();
  error ProposedOwnableFacet__proposeNewOwner_noOwnershipChange();
  error ProposedOwnableFacet__renounceOwnership_noProposal();
  error ProposedOwnableFacet__renounceOwnership_delayNotElapsed();
  error ProposedOwnableFacet__renounceOwnership_invalidProposal();
  error ProposedOwnableFacet__acceptProposedOwner_noOwnershipChange();
  error ProposedOwnableFacet__acceptProposedOwner_delayNotElapsed();

  // ============ Properties ============

  uint256 private constant _delay = 7 days;

  // ============ Events ============

  event RouterWhitelistRemovalProposed(uint256 timestamp);

  event RouterWhitelistRemoved(bool renounced);

  event AssetWhitelistRemovalProposed(uint256 timestamp);

  event AssetWhitelistRemoved(bool renounced);

  event Paused();

  event Unpaused();

  // ============ External: Getters ============

  /**
   * @notice Returns the address of the current owner.
   */
  function owner() public view returns (address) {
    return LibDiamond.contractOwner();
  }

  /**
   * @notice Returns if the router whitelist is removed.
   */
  function routerWhitelistRemoved() public view returns (bool) {
    return s._routerWhitelistRemoved;
  }

  /**
   * @notice Returns if the asset whitelist is removed.
   */
  function assetWhitelistRemoved() public view returns (bool) {
    return s._assetWhitelistRemoved;
  }

  /**
   * @notice Returns the address of the proposed owner.
   */
  function proposed() public view returns (address) {
    return s._proposed;
  }

  /**
   * @notice Returns the address of the proposed owner.
   */
  function proposedTimestamp() public view returns (uint256) {
    return s._proposedOwnershipTimestamp;
  }

  /**
   * @notice Returns the timestamp when router whitelist was last proposed to be removed
   */
  function routerWhitelistTimestamp() public view returns (uint256) {
    return s._routerWhitelistTimestamp;
  }

  /**
   * @notice Returns the timestamp when asset whitelist was last proposed to be removed
   */
  function assetWhitelistTimestamp() public view returns (uint256) {
    return s._assetWhitelistTimestamp;
  }

  /**
   * @notice Returns the delay period before a new owner can be accepted.
   */
  function delay() public pure returns (uint256) {
    return _delay;
  }

  // ============ External ============

  /**
   * @notice Indicates if the ownership of the router whitelist has
   * been renounced
   */
  function proposeRouterWhitelistRemoval() public onlyOwner {
    // Use contract as source of truth
    // Will fail if all ownership is renounced by modifier
    if (s._routerWhitelistRemoved) revert ProposedOwnableFacet__proposeRouterWhitelistRemoval_noOwnershipChange();

    // Begin delay, emit event
    _setRouterWhitelistTimestamp();
  }

  /**
   * @notice Indicates if the ownership of the asset whitelist has
   * been renounced
   */
  function removeRouterWhitelist() public onlyOwner {
    // Contract as sounce of truth
    // Will fail if all ownership is renounced by modifier
    if (s._routerWhitelistRemoved) revert ProposedOwnableFacet__removeRouterWhitelist_noOwnershipChange();

    // Ensure there has been a proposal cycle started
    if (s._routerWhitelistTimestamp == 0) revert ProposedOwnableFacet__removeRouterWhitelist_noProposal();

    // Delay has elapsed
    if ((block.timestamp - s._routerWhitelistTimestamp) <= _delay)
      revert ProposedOwnableFacet__removeRouterWhitelist_delayNotElapsed();

    // Set renounced, emit event, reset timestamp to 0
    _setRouterWhitelistRemoved(true);
  }

  /**
   * @notice Indicates if the ownership of the asset whitelist has
   * been renounced
   */
  function proposeAssetWhitelistRemoval() public onlyOwner {
    // Contract as source of truth
    // Will fail if all ownership is renounced by modifier
    if (s._assetWhitelistRemoved) revert ProposedOwnableFacet__proposeAssetWhitelistRemoval_noOwnershipChange();

    // Start cycle, emit event
    _setAssetWhitelistTimestamp();
  }

  /**
   * @notice Indicates if the ownership of the asset whitelist has
   * been renounced
   */
  function removeAssetWhitelist() public onlyOwner {
    // Contract as source of truth
    // Will fail if all ownership is renounced by modifier
    if (s._assetWhitelistRemoved) revert ProposedOwnableFacet__removeAssetWhitelist_noOwnershipChange();

    // Ensure there has been a proposal cycle started
    if (s._assetWhitelistTimestamp == 0) revert ProposedOwnableFacet__removeAssetWhitelist_noProposal();

    // Ensure delay has elapsed
    if ((block.timestamp - s._assetWhitelistTimestamp) <= _delay)
      revert ProposedOwnableFacet__removeAssetWhitelist_delayNotElapsed();

    // Set ownership, reset timestamp, emit event
    _setAssetWhitelistRemoved(true);
  }

  /**
   * @notice Indicates if the ownership has been renounced() by
   * checking if current owner is address(0)
   */
  function renounced() public view returns (bool) {
    return owner() == address(0);
  }

  /**
   * @notice Sets the timestamp for an owner to be proposed, and sets the
   * newly proposed owner as step 1 in a 2-step process
   */
  function proposeNewOwner(address newlyProposed) public onlyOwner {
    // Contract as source of truth
    if (s._proposed == newlyProposed && newlyProposed != address(0))
      revert ProposedOwnableFacet__proposeNewOwner_invalidProposal();

    // Sanity check: reasonable proposal
    if (owner() == newlyProposed) revert ProposedOwnableFacet__proposeNewOwner_noOwnershipChange();

    _setProposed(newlyProposed);
  }

  /**
   * @notice Renounces ownership of the contract after a delay
   */
  function renounceOwnership() public onlyOwner {
    // Ensure there has been a proposal cycle started
    if (s._proposedOwnershipTimestamp == 0) revert ProposedOwnableFacet__renounceOwnership_noProposal();

    // Ensure delay has elapsed
    if ((block.timestamp - s._proposedOwnershipTimestamp) <= _delay)
      revert ProposedOwnableFacet__renounceOwnership_delayNotElapsed();

    // Require proposed is set to 0
    if (s._proposed != address(0)) revert ProposedOwnableFacet__renounceOwnership_invalidProposal();

    // Emit event, set new owner, reset timestamp
    _setOwner(s._proposed);
  }

  /**
   * @notice Transfers ownership of the contract to a new account (`newOwner`).
   * Can only be called by the proposed owner.
   */
  function acceptProposedOwner() public onlyProposed {
    // Contract as source of truth
    if (owner() == s._proposed) revert ProposedOwnableFacet__acceptProposedOwner_noOwnershipChange();

    // NOTE: no need to check if _proposedOwnershipTimestamp > 0 because
    // the only time this would happen is if the _proposed was never
    // set (will fail from modifier) or if the owner == _proposed (checked
    // above)

    // Ensure delay has elapsed
    if ((block.timestamp - s._proposedOwnershipTimestamp) <= _delay)
      revert ProposedOwnableFacet__acceptProposedOwner_delayNotElapsed();

    // Emit event, set new owner, reset timestamp
    _setOwner(s._proposed);
  }

  function pause() public onlyOwner {
    s._paused = true;
    emit Paused();
  }

  function unpause() public onlyOwner {
    s._paused = false;
    emit Unpaused();
  }

  ////// INTERNAL //////

  function _setRouterWhitelistTimestamp() private {
    s._routerWhitelistTimestamp = block.timestamp;
    emit RouterWhitelistRemovalProposed(block.timestamp);
  }

  function _setRouterWhitelistRemoved(bool value) private {
    s._routerWhitelistRemoved = value;
    delete s._routerWhitelistTimestamp;
    emit RouterWhitelistRemoved(value);
  }

  function _setAssetWhitelistTimestamp() private {
    s._assetWhitelistTimestamp = block.timestamp;
    emit AssetWhitelistRemovalProposed(block.timestamp);
  }

  function _setAssetWhitelistRemoved(bool value) private {
    s._assetWhitelistRemoved = value;
    delete s._assetWhitelistTimestamp;
    emit AssetWhitelistRemoved(value);
  }

  function _setOwner(address newOwner) private {
    delete s._proposedOwnershipTimestamp;
    delete s._proposed;
    LibDiamond.setContractOwner(newOwner);
  }

  function _setProposed(address newlyProposed) private {
    s._proposedOwnershipTimestamp = block.timestamp;
    s._proposed = newlyProposed;
    emit OwnershipProposed(newlyProposed);
  }
}
