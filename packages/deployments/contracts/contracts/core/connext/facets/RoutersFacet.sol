// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {BaseConnextFacet} from "./BaseConnextFacet.sol";
import {AssetLogic} from "../libraries/AssetLogic.sol";
import {AppStorage} from "../libraries/LibConnextStorage.sol";

/**
 * @notice
 * This contract is designed to manage router access, meaning it maintains the
 * router recipients, owners, and the router whitelist itself.
 *
 * As a router, there are three important permissions:
 * `router` - this is the address that will sign bids sent to the sequencer
 * `routerRecipient` - this is the address that receives funds when liquidity is withdrawn
 * `routerOwner` - this is the address permitted to update recipients and propose new owners
 *
 * In cases where the owner is not set, the caller should be the `router` itself. In cases where the
 * `routerRecipient` is not set, the funds can be removed to anywhere.
 *
 * When setting a new `routerOwner`, the current owner (or router) must create a proposal, which
 * can be accepted by the proposed owner after the delay period. If the proposed owner is the empty
 * address, then it must be accepted by the current owner.
 */
contract RoutersFacet is BaseConnextFacet {
  // ========== Custom Errors ===========
  error RoutersFacet__acceptProposedRouterOwner_notElapsed();
  error RoutersFacet__setRouterRecipient_notNewRecipient();
  error RoutersFacet__onlyRouterOwner_notRouterOwner();
  error RoutersFacet__onlyProposedRouterOwner_notRouterOwner();
  error RoutersFacet__onlyProposedRouterOwner_notProposedRouterOwner();
  error RoutersFacet__removeRouter_routerEmpty();
  error RoutersFacet__removeRouter_notAdded();
  error RoutersFacet__setupRouter_routerEmpty();
  error RoutersFacet__setupRouter_alreadyAdded();
  error RoutersFacet__proposeRouterOwner_notNewOwner();
  error RoutersFacet__proposeRouterOwner_badRouter();
  error RoutersFacet__setMaxRoutersPerTransfer_invalidMaxRoutersPerTransfer();
  error RoutersFacet__addLiquidityForRouter_routerEmpty();
  error RoutersFacet__addLiquidityForRouter_amountIsZero();
  error RoutersFacet__addLiquidityForRouter_badRouter();
  error RoutersFacet__addLiquidityForRouter_badAsset();
  error RoutersFacet__removeRouterLiquidity_recipientEmpty();
  error RoutersFacet__removeRouterLiquidity_amountIsZero();
  error RoutersFacet__removeRouterLiquidity_insufficientFunds();
  error RoutersFacet__removeRouterLiquidityFor_notOwner();
  error RoutersFacet__setLiquidityFeeNumerator_tooSmall();
  error RoutersFacet__setLiquidityFeeNumerator_tooLarge();
  error RoutersFacet__approveRouterForPortal_notAdded();
  error RoutersFacet__approveRouterForPortal_alreadyApproved();
  error RoutersFacet__unapproveRouterForPortal_notApproved();

  // ============ Properties ============

  // ============ Constants ============
  uint256 private constant _delay = 7 days;

  // ============ Events ============

  /**
   * @notice Emitted when a new router is added
   * @param router - The address of the added router
   * @param caller - The account that called the function
   */
  event RouterAdded(address indexed router, address caller);

  /**
   * @notice Emitted when an existing router is removed
   * @param router - The address of the removed router
   * @param caller - The account that called the function
   */
  event RouterRemoved(address indexed router, address caller);

  /**
   * @notice Emitted when the recipient of router is updated
   * @param router - The address of the added router
   * @param prevRecipient  - The address of the previous recipient of the router
   * @param newRecipient  - The address of the new recipient of the router
   */
  event RouterRecipientSet(address indexed router, address indexed prevRecipient, address indexed newRecipient);

  /**
   * @notice Emitted when the owner of router is proposed
   * @param router - The address of the added router
   * @param prevProposed  - The address of the previous proposed
   * @param newProposed  - The address of the new proposed
   */
  event RouterOwnerProposed(address indexed router, address indexed prevProposed, address indexed newProposed);

  /**
   * @notice Emitted when the owner of router is accepted
   * @param router - The address of the added router
   * @param prevOwner  - The address of the previous owner of the router
   * @param newOwner  - The address of the new owner of the router
   */
  event RouterOwnerAccepted(address indexed router, address indexed prevOwner, address indexed newOwner);

  /**
   * @notice Emitted when the maxRoutersPerTransfer variable is updated
   * @param maxRoutersPerTransfer - The maxRoutersPerTransfer new value
   * @param caller - The account that called the function
   */
  event MaxRoutersPerTransferUpdated(uint256 maxRoutersPerTransfer, address caller);

  /**
   * @notice Emitted when the LIQUIDITY_FEE_NUMERATOR variable is updated
   * @param liquidityFeeNumerator - The LIQUIDITY_FEE_NUMERATOR new value
   * @param caller - The account that called the function
   */
  event LiquidityFeeNumeratorUpdated(uint256 liquidityFeeNumerator, address caller);

  /**
   * @notice Emitted when a router is approved for Portal
   * @param router - The address of the approved router
   * @param caller - The account that called the function
   */
  event RouterApprovedForPortal(address router, address caller);

  /**
   * @notice Emitted when a router is disapproved for Portal
   * @param router - The address of the disapproved router
   * @param caller - The account that called the function
   */
  event RouterUnapprovedForPortal(address router, address caller);

  /**
   * @notice Emitted when a router adds liquidity to the contract
   * @param router - The address of the router the funds were credited to
   * @param local - The address of the token added (all liquidity held in local asset)
   * @param key - The hash of the canonical id and domain
   * @param amount - The amount of liquidity added
   * @param caller - The account that called the function
   */
  event RouterLiquidityAdded(address indexed router, address local, bytes32 key, uint256 amount, address caller);

  /**
   * @notice Emitted when a router withdraws liquidity from the contract
   * @param router - The router you are removing liquidity from
   * @param to - The address the funds were withdrawn to
   * @param local - The address of the token withdrawn
   * @param amount - The amount of liquidity withdrawn
   * @param caller - The account that called the function
   */
  event RouterLiquidityRemoved(address indexed router, address to, address local, uint256 amount, address caller);

  // ============ Modifiers ============

  /**
   * @notice Asserts caller is the router owner (if set) or the router itself
   */
  modifier onlyRouterOwner(address _router) {
    address owner = s.routerPermissionInfo.routerOwners[_router];
    if (!((owner == address(0) && msg.sender == _router) || owner == msg.sender))
      revert RoutersFacet__onlyRouterOwner_notRouterOwner();
    _;
  }

  /**
   * @notice Asserts caller is the proposed router. If proposed router is address(0), then asserts
   * the owner is calling the function (if set), or the router itself is calling the function
   */
  modifier onlyProposedRouterOwner(address _router) {
    address proposed = s.routerPermissionInfo.proposedRouterOwners[_router];
    if (proposed == address(0)) {
      address owner = s.routerPermissionInfo.routerOwners[_router];
      if (!((owner == address(0) && msg.sender == _router) || owner == msg.sender))
        revert RoutersFacet__onlyProposedRouterOwner_notRouterOwner();
    } else {
      if (msg.sender != proposed) revert RoutersFacet__onlyProposedRouterOwner_notProposedRouterOwner();
    }
    _;
  }

  // ============ Getters ==============

  function LIQUIDITY_FEE_NUMERATOR() public view returns (uint256) {
    return s.LIQUIDITY_FEE_NUMERATOR;
  }

  function LIQUIDITY_FEE_DENOMINATOR() public pure returns (uint256) {
    return BPS_FEE_DENOMINATOR;
  }

  /**
   * @notice Returns the approved router for the given router address
   * @param _router The relevant router address
   */
  function getRouterApproval(address _router) public view returns (bool) {
    return s.routerPermissionInfo.approvedRouters[_router];
  }

  /**
   * @notice Returns the recipient for the specified router
   * @dev The recipient (if set) receives all funds when router liquidity is removed
   * @param _router The relevant router address
   */
  function getRouterRecipient(address _router) public view returns (address) {
    return s.routerPermissionInfo.routerRecipients[_router];
  }

  /**
   * @notice Returns the router owner if it is set, or the router itself if not
   * @dev Uses logic function here to handle the case where router owner is not set.
   * Other getters within this interface use explicitly the stored value
   * @param _router The relevant router address
   */
  function getRouterOwner(address _router) public view returns (address) {
    address _owner = s.routerPermissionInfo.routerOwners[_router];
    return _owner == address(0) ? _router : _owner;
  }

  /**
   * @notice Returns the currently proposed router owner
   * @dev All routers must wait for the delay timeout before accepting a new owner
   * @param _router The relevant router address
   */
  function getProposedRouterOwner(address _router) public view returns (address) {
    return s.routerPermissionInfo.proposedRouterOwners[_router];
  }

  /**
   * @notice Returns the currently proposed router owner timestamp
   * @dev All routers must wait for the delay timeout before accepting a new owner
   * @param _router The relevant router address
   */
  function getProposedRouterOwnerTimestamp(address _router) public view returns (uint256) {
    return s.routerPermissionInfo.proposedRouterTimestamp[_router];
  }

  function maxRoutersPerTransfer() public view returns (uint256) {
    return s.maxRoutersPerTransfer;
  }

  function routerBalances(address _router, address _asset) public view returns (uint256) {
    return s.routerBalances[_router][_asset];
  }

  /**
   * @notice Returns whether the router is approved for portals or not
   * @param _router The relevant router address
   */
  function getRouterApprovalForPortal(address _router) public view returns (bool) {
    return s.routerPermissionInfo.approvedForPortalRouters[_router];
  }

  // ============ Admin methods ==============

  /**
   * @notice Used to set router initial properties
   * @param router Router address to setup
   * @param owner Initial Owner of router
   * @param recipient Initial Recipient of router
   */
  function setupRouter(
    address router,
    address owner,
    address recipient
  ) external onlyOwner {
    // Sanity check: not empty
    if (router == address(0)) revert RoutersFacet__setupRouter_routerEmpty();

    // Sanity check: needs approval
    if (s.routerPermissionInfo.approvedRouters[router]) revert RoutersFacet__setupRouter_alreadyAdded();

    // Approve router
    s.routerPermissionInfo.approvedRouters[router] = true;

    // Emit event
    emit RouterAdded(router, msg.sender);

    // Update routerOwner (zero address possible)
    if (owner != address(0)) {
      s.routerPermissionInfo.routerOwners[router] = owner;
      emit RouterOwnerAccepted(router, address(0), owner);
    }

    // Update router recipient
    if (recipient != address(0)) {
      s.routerPermissionInfo.routerRecipients[router] = recipient;
      emit RouterRecipientSet(router, address(0), recipient);
    }
  }

  /**
   * @notice Used to remove routers that can transact crosschain
   * @param router Router address to remove
   */
  function removeRouter(address router) external onlyOwner {
    // Sanity check: not empty
    if (router == address(0)) revert RoutersFacet__removeRouter_routerEmpty();

    // Sanity check: needs removal
    if (!s.routerPermissionInfo.approvedRouters[router]) revert RoutersFacet__removeRouter_notAdded();

    // Update mapping
    s.routerPermissionInfo.approvedRouters[router] = false;

    // Emit event
    emit RouterRemoved(router, msg.sender);

    // Remove router owner
    address _owner = s.routerPermissionInfo.routerOwners[router];
    if (_owner != address(0)) {
      emit RouterOwnerAccepted(router, _owner, address(0));
      // delete routerOwners[router];
      s.routerPermissionInfo.routerOwners[router] = address(0);
    }

    // Remove router recipient
    address _recipient = s.routerPermissionInfo.routerRecipients[router];
    if (_recipient != address(0)) {
      emit RouterRecipientSet(router, _recipient, address(0));
      // delete routerRecipients[router];
      s.routerPermissionInfo.routerRecipients[router] = address(0);
    }

    // Clear any proposed ownership changes
    delete s.routerPermissionInfo.proposedRouterOwners[router];
    delete s.routerPermissionInfo.proposedRouterTimestamp[router];

    // Clear approvedForPortal status.
    delete s.routerPermissionInfo.approvedForPortalRouters[router];
  }

  /**
   * @notice Used to set the max amount of routers a payment can be routed through
   * @param _newMaxRouters The new max amount of routers
   */
  function setMaxRoutersPerTransfer(uint256 _newMaxRouters) external onlyOwner {
    if (_newMaxRouters == 0 || _newMaxRouters == s.maxRoutersPerTransfer)
      revert RoutersFacet__setMaxRoutersPerTransfer_invalidMaxRoutersPerTransfer();

    emit MaxRoutersPerTransferUpdated(_newMaxRouters, msg.sender);

    s.maxRoutersPerTransfer = _newMaxRouters;
  }

  /**
   * @notice Sets the LIQUIDITY_FEE_NUMERATOR
   * @dev Admin can set LIQUIDITY_FEE_NUMERATOR variable, Liquidity fee should be less than 5%
   * @param _numerator new LIQUIDITY_FEE_NUMERATOR
   */
  function setLiquidityFeeNumerator(uint256 _numerator) external onlyOwner {
    // Slightly misleading: the liquidity fee numerator is not the amount charged,
    // but the amount received after fees are deducted (e.g. 9995/10000 would be .005%).
    uint256 denominator = BPS_FEE_DENOMINATOR;
    if (_numerator < (denominator * 95) / 100) revert RoutersFacet__setLiquidityFeeNumerator_tooSmall();

    if (_numerator > denominator) revert RoutersFacet__setLiquidityFeeNumerator_tooLarge();
    s.LIQUIDITY_FEE_NUMERATOR = _numerator;

    emit LiquidityFeeNumeratorUpdated(_numerator, msg.sender);
  }

  /**
   * @notice Allow router to use Portals
   * @param _router - The router address to approve
   */
  function approveRouterForPortal(address _router) external onlyOwner {
    if (!s.routerPermissionInfo.approvedRouters[_router] && !_isRouterWhitelistRemoved())
      revert RoutersFacet__approveRouterForPortal_notAdded();
    if (s.routerPermissionInfo.approvedForPortalRouters[_router])
      revert RoutersFacet__approveRouterForPortal_alreadyApproved();

    s.routerPermissionInfo.approvedForPortalRouters[_router] = true;

    emit RouterApprovedForPortal(_router, msg.sender);
  }

  /**
   * @notice Remove router access to use Portals
   * @param _router - The router address to remove approval
   */
  function unapproveRouterForPortal(address _router) external onlyOwner {
    if (!s.routerPermissionInfo.approvedForPortalRouters[_router])
      revert RoutersFacet__unapproveRouterForPortal_notApproved();

    delete s.routerPermissionInfo.approvedForPortalRouters[_router];

    emit RouterUnapprovedForPortal(_router, msg.sender);
  }

  // ============ Public methods ==============

  /**
   * @notice Sets the designated recipient for a router
   * @dev Router should only be able to set this once otherwise if router key compromised,
   * no problem is solved since attacker could just update recipient
   * @param router Router address to set recipient
   * @param recipient Recipient Address to set to router
   */
  function setRouterRecipient(address router, address recipient) external onlyRouterOwner(router) {
    // Check recipient is changing
    address _prevRecipient = s.routerPermissionInfo.routerRecipients[router];
    if (_prevRecipient == recipient) revert RoutersFacet__setRouterRecipient_notNewRecipient();

    // Set new recipient
    s.routerPermissionInfo.routerRecipients[router] = recipient;

    // Emit event
    emit RouterRecipientSet(router, _prevRecipient, recipient);
  }

  /**
   * @notice Current owner or router may propose a new router owner
   * @param router Router address to set recipient
   * @param proposed Proposed owner Address to set to router
   */
  function proposeRouterOwner(address router, address proposed) external onlyRouterOwner(router) {
    // Check that proposed is different than current owner
    if (getRouterOwner(router) == proposed) revert RoutersFacet__proposeRouterOwner_notNewOwner();

    // Check that proposed is different than current proposed
    address _currentProposed = s.routerPermissionInfo.proposedRouterOwners[router];
    if (_currentProposed == proposed) revert RoutersFacet__proposeRouterOwner_badRouter();

    // Set proposed owner + timestamp
    s.routerPermissionInfo.proposedRouterOwners[router] = proposed;
    s.routerPermissionInfo.proposedRouterTimestamp[router] = block.timestamp;

    // Emit event
    emit RouterOwnerProposed(router, _currentProposed, proposed);
  }

  /**
   * @notice New router owner must accept role, or previous if proposed is 0x0
   * @param router Router address to set recipient
   */
  function acceptProposedRouterOwner(address router) external onlyProposedRouterOwner(router) {
    address owner = getRouterOwner(router);

    // Check timestamp has passed
    if (block.timestamp - s.routerPermissionInfo.proposedRouterTimestamp[router] <= _delay)
      revert RoutersFacet__acceptProposedRouterOwner_notElapsed();

    // Get current owner + proposed
    address _proposed = s.routerPermissionInfo.proposedRouterOwners[router];

    // Update the current owner
    s.routerPermissionInfo.routerOwners[router] = _proposed;

    // Reset proposal + timestamp
    if (_proposed != address(0)) {
      delete s.routerPermissionInfo.proposedRouterOwners[router];
    }
    delete s.routerPermissionInfo.proposedRouterTimestamp[router];

    // Emit event
    emit RouterOwnerAccepted(router, owner, _proposed);
  }

  /**
   * @notice This is used by anyone to increase a router's available liquidity for a given asset.
   * @dev The liquidity will be held in the local asset, which is the representation if you
   * are *not* on the canonical domain, and the canonical asset otherwise.
   * @param _amount - The amount of liquidity to add for the router
   * @param _local - The address of the asset you're adding liquidity for. If adding liquidity of the
   * native asset, routers may use `address(0)` or the wrapped asset
   * @param _router The router you are adding liquidity on behalf of
   */
  function addRouterLiquidityFor(
    uint256 _amount,
    address _local,
    address _router
  ) external payable nonReentrant whenNotPaused {
    _addLiquidityForRouter(_amount, _local, _router);
  }

  /**
   * @notice This is used by any router to increase their available liquidity for a given asset.
   * @dev The liquidity will be held in the local asset, which is the representation if you
   * are *not* on the canonical domain, and the canonical asset otherwise.
   * @param _amount - The amount of liquidity to add for the router
   * @param _local - The address of the asset you're adding liquidity for. If adding liquidity of the
   * native asset, routers may use `address(0)` or the wrapped asset
   */
  function addRouterLiquidity(uint256 _amount, address _local) external payable nonReentrant whenNotPaused {
    _addLiquidityForRouter(_amount, _local, msg.sender);
  }

  /**
   * @notice This is used by any router owner to decrease their available liquidity for a given asset.
   * @param _amount - The amount of liquidity to remove for the router
   * @param _local - The address of the asset you're removing liquidity from. If removing liquidity of the
   * native asset, routers may use `address(0)` or the wrapped asset
   * @param _to The address that will receive the liquidity being removed
   * @param _router The address of the router
   */
  function removeRouterLiquidityFor(
    uint256 _amount,
    address _local,
    address payable _to,
    address _router
  ) external nonReentrant whenNotPaused {
    // Caller must be the router owner
    if (msg.sender != getRouterOwner(_router)) revert RoutersFacet__removeRouterLiquidityFor_notOwner();

    // Remove liquidity
    _removeLiquidityForRouter(_amount, _local, _to, _router);
  }

  /**
   * @notice This is used by any router to decrease their available liquidity for a given asset.
   * @param _amount - The amount of liquidity to remove for the router
   * @param _local - The address of the asset you're removing liquidity from. If removing liquidity of the
   * native asset, routers may use `address(0)` or the wrapped asset
   * @param _to The address that will receive the liquidity being removed if no router recipient exists.
   */
  function removeRouterLiquidity(
    uint256 _amount,
    address _local,
    address payable _to
  ) external nonReentrant whenNotPaused {
    _removeLiquidityForRouter(_amount, _local, _to, msg.sender);
  }

  // ============ Internal functions ============

  /**
   * @notice Contains the logic to verify + increment a given routers liquidity
   * @dev The liquidity will be held in the local asset, which is the representation if you
   * are *not* on the canonical domain, and the canonical asset otherwise.
   * @param _amount - The amount of liquidity to add for the router
   * @param _local - The address of the nomad representation of the asset
   * @param _router - The router you are adding liquidity on behalf of
   */
  function _addLiquidityForRouter(
    uint256 _amount,
    address _local,
    address _router
  ) internal {
    // Sanity check: router is sensible.
    if (_router == address(0)) revert RoutersFacet__addLiquidityForRouter_routerEmpty();

    // Sanity check: nonzero amounts.
    if (_amount == 0) revert RoutersFacet__addLiquidityForRouter_amountIsZero();

    // Get the canonical asset ID from the representation.
    (uint32 domain, bytes32 canonicalId) = s.tokenRegistry.getTokenId(_local);
    bytes32 key = _calculateCanonicalHash(canonicalId, domain);

    // Sanity check: router is approved.
    if (!_isRouterWhitelistRemoved() && !getRouterApproval(_router))
      revert RoutersFacet__addLiquidityForRouter_badRouter();

    // Sanity check: asset is approved.
    if (!_isAssetWhitelistRemoved() && !s.approvedAssets[key]) revert RoutersFacet__addLiquidityForRouter_badAsset();

    // Transfer funds to contract.
    AssetLogic.handleIncomingAsset(_local, _amount);

    // Update the router balances. Happens after pulling funds to account for
    // the fee on transfer tokens.
    s.routerBalances[_router][_local] += _amount;

    emit RouterLiquidityAdded(_router, _local, key, _amount, msg.sender);
  }

  /**
   * @notice This is used by any router owner to decrease their available liquidity for a given asset.
   * @param _amount - The amount of liquidity to remove for the router
   * @param _local - The address of the asset you're removing liquidity from. If removing liquidity of the
   * native asset, routers may use `address(0)` or the wrapped asset
   * @param _to The address that will receive the liquidity being removed
   * @param _router The address of the router
   */
  function _removeLiquidityForRouter(
    uint256 _amount,
    address _local,
    address payable _to,
    address _router
  ) internal {
    // Transfer to specified recipient IF recipient not set.
    address recipient = getRouterRecipient(_router);
    recipient = recipient == address(0) ? _to : recipient;

    // Sanity check: to is sensible.
    if (recipient == address(0)) revert RoutersFacet__removeRouterLiquidity_recipientEmpty();

    // Sanity check: nonzero amounts.
    if (_amount == 0) revert RoutersFacet__removeRouterLiquidity_amountIsZero();

    // Get existing router balance.
    uint256 routerBalance = s.routerBalances[_router][_local];

    // Sanity check: amount can be deducted for the router.
    if (routerBalance < _amount) revert RoutersFacet__removeRouterLiquidity_insufficientFunds();

    // Update router balances.
    unchecked {
      s.routerBalances[_router][_local] = routerBalance - _amount;
    }

    // Transfer from contract to specified `to` address.
    AssetLogic.handleOutgoingAsset(_local, recipient, _amount);

    emit RouterLiquidityRemoved(_router, recipient, _local, _amount, msg.sender);
  }
}
