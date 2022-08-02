// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {BaseConnextFacet} from "./BaseConnextFacet.sol";
import {RelayerFeeRouter} from "../../relayer-fee/RelayerFeeRouter.sol";

contract RelayerFacet is BaseConnextFacet {
  // ========== Custom Errors ===========
  error RelayerFacet__onlyRelayerFeeRouter_notRelayerFeeRouter();
  error RelayerFacet__setRelayerFeeRouter_invalidRelayerFeeRouter();
  error RelayerFacet__addRelayer_alreadyApproved();
  error RelayerFacet__removeRelayer_notApproved();
  error RelayerFacet__initiateClaim_emptyClaim();
  error RelayerFacet__initiateClaim_notRelayer(bytes32 transferId);

  // ========== Events ===========
  /**
   * @notice Emitted when the relayerFeeRouter variable is updated
   * @param oldRouter - The relayerFeeRouter old value
   * @param newRouter - The relayerFeeRouter new value
   * @param caller - The account that called the function
   */
  event RelayerFeeRouterUpdated(address oldRouter, address newRouter, address caller);

  /**
   * @notice Emitted when a relayer is added or removed from whitelists
   * @param relayer - The relayer address to be added or removed
   * @param caller - The account that called the function
   */
  event RelayerAdded(address relayer, address caller);

  /**
   * @notice Emitted when a relayer is added or removed from whitelists
   * @param relayer - The relayer address to be added or removed
   * @param caller - The account that called the function
   */
  event RelayerRemoved(address relayer, address caller);

  /**
   * @notice Emitted when `initiateClaim` is called on the destination chain
   * @param domain - Domain to claim funds on
   * @param recipient - Address on origin chain to send claimed funds to
   * @param caller - The account that called the function
   * @param transferIds - TransferIds to claim
   */
  event InitiatedClaim(uint32 indexed domain, address indexed recipient, address caller, bytes32[] transferIds);

  /**
   * @notice Emitted when `claim` is called on the origin domain
   * @param recipient - Address on origin chain to send claimed funds to
   * @param total - Total amount claimed
   * @param transferIds - TransferIds to claim
   */
  event Claimed(address indexed recipient, uint256 total, bytes32[] transferIds);

  // ============ Modifiers ============

  /**
   * @notice Restricts the caller to the local relayer fee router
   */
  modifier onlyRelayerFeeRouter() {
    if (msg.sender != address(s.relayerFeeRouter)) revert RelayerFacet__onlyRelayerFeeRouter_notRelayerFeeRouter();
    _;
  }

  // ============ Getters ============

  function transferRelayer(bytes32 _transferId) public view returns (address) {
    return s.transferRelayer[_transferId];
  }

  function approvedRelayers(address _relayer) public view returns (bool) {
    return s.approvedRelayers[_relayer];
  }

  function relayerFeeRouter() external view returns (RelayerFeeRouter) {
    return s.relayerFeeRouter;
  }

  // ============ Admin functions ============

  /**
   * @notice Updates the relayer fee router
   * @param _relayerFeeRouter The address of the new router
   */
  function setRelayerFeeRouter(address _relayerFeeRouter) external onlyOwner {
    address old = address(s.relayerFeeRouter);
    if (old == _relayerFeeRouter || !Address.isContract(_relayerFeeRouter))
      revert RelayerFacet__setRelayerFeeRouter_invalidRelayerFeeRouter();

    s.relayerFeeRouter = RelayerFeeRouter(_relayerFeeRouter);
    emit RelayerFeeRouterUpdated(old, _relayerFeeRouter, msg.sender);
  }

  /**
   * @notice Used to add approved relayer
   * @param _relayer - The relayer address to add
   */
  function addRelayer(address _relayer) external onlyOwner {
    if (s.approvedRelayers[_relayer]) revert RelayerFacet__addRelayer_alreadyApproved();
    s.approvedRelayers[_relayer] = true;

    emit RelayerAdded(_relayer, msg.sender);
  }

  /**
   * @notice Used to remove approved relayer
   * @param _relayer - The relayer address to remove
   */
  function removeRelayer(address _relayer) external onlyOwner {
    if (!s.approvedRelayers[_relayer]) revert RelayerFacet__removeRelayer_notApproved();
    delete s.approvedRelayers[_relayer];

    emit RelayerRemoved(_relayer, msg.sender);
  }

  // ============ External functions ============

  /**
   * @notice Called by relayer when they want to claim owed funds on a given domain.
   *
   * @dev Domain should be the origin domain of all the transfer IDs.
   *
   * @param _recipient - address on origin chain to send claimed funds to
   * @param _domain - domain to claim funds on
   * @param _transferIds - transferIds to claim
   */
  function initiateClaim(
    uint32 _domain,
    address _recipient,
    bytes32[] calldata _transferIds
  ) external whenNotPaused nonReentrant {
    // Make sure the transferIds length is greater than 0.
    // This is to make sure a valid relayer is calling this function.
    uint256 numTransfers = _transferIds.length;
    if (numTransfers == 0) revert RelayerFacet__initiateClaim_emptyClaim();

    // Ensure the relayer can claim all transfers specified.
    for (uint256 i; i < numTransfers; ) {
      if (s.transferRelayer[_transferIds[i]] != msg.sender)
        revert RelayerFacet__initiateClaim_notRelayer(_transferIds[i]);
      unchecked {
        ++i;
      }
    }

    // Send transferIds via nomad.
    s.relayerFeeRouter.send(_domain, _recipient, _transferIds);

    emit InitiatedClaim(_domain, _recipient, msg.sender, _transferIds);
  }

  /**
   * @notice Pays out a relayer for the given fees
   * @dev Called by the RelayerFeeRouter.handle message. The validity of the transferIds is
   * asserted before dispatching the message.
   * @param _recipient - address on origin chain to send claimed funds to
   * @param _transferIds - transferIds to claim
   */
  function claim(address _recipient, bytes32[] calldata _transferIds) external onlyRelayerFeeRouter nonReentrant {
    uint256 numTransfers = _transferIds.length;
    // Tally amounts owed
    uint256 total;
    for (uint256 i; i < numTransfers; ) {
      total += s.relayerFees[_transferIds[i]];
      delete s.relayerFees[_transferIds[i]];
      unchecked {
        ++i;
      }
    }

    Address.sendValue(payable(_recipient), total);

    emit Claimed(_recipient, total, _transferIds);
  }
}
