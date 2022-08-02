// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LibDiamond} from "../../../../contracts/core/connext/libraries/LibDiamond.sol";
import {IStableSwap} from "../../../../contracts/core/connext/interfaces/IStableSwap.sol";
import {ITokenRegistry} from "../../../../contracts/core/connext/interfaces/ITokenRegistry.sol";
import {IWeth} from "../../../../contracts/core/connext/interfaces/IWeth.sol";
import {RoutersFacet, BaseConnextFacet} from "../../../../contracts/core/connext/facets/RoutersFacet.sol";
import {TestERC20} from "../../../../contracts/test/TestERC20.sol";

import {MockTokenRegistry} from "../../../utils/Mock.sol";
import "../../../utils/FacetHelper.sol";

contract RoutersFacetTest is RoutersFacet, FacetHelper {
  // ============ storage ============
  // owner
  address _owner = address(12345);

  // sample data
  uint32 _domain = _originDomain;

  address _routerAgent0 = address(222000111); // 0x000000000000000000000000000000000d3b73ef
  address _routerRecipient0 = address(222000222); // 0x000000000000000000000000000000000d3b745e
  address _routerOwner0 = address(222000333); // 0x000000000000000000000000000000000d3b74cd

  address _routerAgent1 = address(222001111);
  address _routerRecipient1 = address(222001222);
  address _routerOwner1 = address(222001333);

  address _routerAgent2 = address(222002111);
  address _routerRecipient2 = address(222002222);
  address _routerOwner2 = address(222002333);

  address _asset0 = address(333000111);
  address _asset1 = address(333001111);

  // ============ Test set up ============
  function setUp() public {
    setOwner(_owner);
    utils_deployAssetContracts();
    utils_setupAsset(true, false);
  }

  // ============ Utils ==============
  // Set diamond storage owner
  function setOwner(address owner) internal {
    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    ds.contractOwner = owner;
  }

  // ============ Test methods ============

  // TODO: test modifiers? onlyRouterOwner, onlyProposedRouterOwner, etc.

  // ============ Getters ==============

  function test_RoutersFacet__LIQUIDITY_FEE_NUMERATOR_success() public {
    assertEq(this.LIQUIDITY_FEE_NUMERATOR(), s.LIQUIDITY_FEE_NUMERATOR);
  }

  function test_RoutersFacet__LIQUIDITY_FEE_NUMERATOR_notFound() public {
    assertEq(this.LIQUIDITY_FEE_NUMERATOR(), 0);
  }

  function test_RoutersFacet__LIQUIDITY_FEE_DENOMINATOR_success() public {
    assertEq(this.LIQUIDITY_FEE_DENOMINATOR(), 10_000);
  }

  function test_RoutersFacet__getRouterApproval_success() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    assertEq(this.getRouterApproval(_routerAgent0), true);
  }

  function test_RoutersFacet__getRouterApproval_notFound() public {
    assertEq(this.getRouterApproval(_routerAgent0), false);
  }

  function test_RoutersFacet__getRouterRecipient_success() public {
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;
    assertEq(this.getRouterRecipient(_routerAgent0), _routerRecipient0);
  }

  function test_RoutersFacet__getRouterRecipient_notFound() public {
    assertEq(this.getRouterRecipient(_routerAgent0), address(0));
  }

  function test_RoutersFacet__getRouterOwner_success() public {
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    assertEq(this.getRouterOwner(_routerAgent0), _routerOwner0);
  }

  function test_RoutersFacet__getRouterOwner_notFound() public {
    assertEq(s.routerPermissionInfo.routerOwners[_routerAgent0], address(0));
    // NOTE: If router owner was not set, this method should return the router address itself.
    address routerOwner = this.getRouterOwner(_routerAgent0);
    assertEq(routerOwner, _routerAgent0);
  }

  function test_RoutersFacet__getProposedRouterOwner_success() public {
    s.routerPermissionInfo.proposedRouterOwners[_routerAgent0] = _routerOwner0;
    assertEq(this.getProposedRouterOwner(_routerAgent0), _routerOwner0);
  }

  function test_RoutersFacet__getProposedRouterOwner_notFound() public {
    assertEq(this.getProposedRouterOwner(_routerAgent0), address(0));
  }

  function test_RoutersFacet__getProposedRouterOwnerTimestamp() public {
    s.routerPermissionInfo.proposedRouterTimestamp[_routerAgent0] = 12345;
    assertEq(this.getProposedRouterOwnerTimestamp(_routerAgent0), 12345);
  }

  function test_RoutersFacet__maxRoutersPerTransfer_success() public {
    s.maxRoutersPerTransfer = 12345;
    assertEq(this.maxRoutersPerTransfer(), 12345);
  }

  function test_RoutersFacet__maxRoutersPerTransfer_notFound() public {
    assertEq(this.maxRoutersPerTransfer(), 0);
  }

  function test_RoutersFacet__routerBalances_success() public {
    s.routerBalances[_routerAgent0][_asset0] = 12345;
    s.routerBalances[_routerAgent0][_asset1] = 5678;
    assertEq(this.routerBalances(_routerAgent0, _asset0), 12345);
    assertEq(this.routerBalances(_routerAgent0, _asset1), 5678);
  }

  function test_RoutersFacet__routerBalances_notFound() public {
    assertEq(this.routerBalances(_routerAgent0, _asset0), 0);
  }

  // ============ Admin methods ==============

  function test_RoutersFacet__setupRouter_failsIfNotOwner() public {
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);
    vm.prank(address(123456123));
    this.setupRouter(address(0), _routerOwner0, _routerRecipient0);
  }

  function test_RoutersFacet__setupRouter_failsIfRouterAddressIsZero() public {
    vm.expectRevert(RoutersFacet.RoutersFacet__setupRouter_routerEmpty.selector);
    vm.prank(_owner);
    this.setupRouter(address(0), _routerOwner0, _routerRecipient0);
  }

  function test_RoutersFacet__setupRouter_failsIfRouterAlreadyApproved() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    vm.expectRevert(RoutersFacet.RoutersFacet__setupRouter_alreadyAdded.selector);
    vm.prank(_owner);
    this.setupRouter(_routerAgent0, _routerOwner0, _routerRecipient0);
  }

  // setupRouter -- set owner, router, recipient
  function test_RoutersFacet__setupRouter_success() public {
    assertEq(s.routerPermissionInfo.approvedRouters[_routerAgent0], false);

    vm.expectEmit(true, true, false, true);
    emit RouterAdded(_routerAgent0, _owner);

    vm.expectEmit(true, true, false, true);
    emit RouterOwnerAccepted(_routerAgent0, address(0), _routerOwner0);

    vm.expectEmit(true, true, false, true);
    emit RouterRecipientSet(_routerAgent0, address(0), _routerRecipient0);

    vm.prank(_owner);
    this.setupRouter(_routerAgent0, _routerOwner0, _routerRecipient0);

    assertEq(s.routerPermissionInfo.approvedRouters[_routerAgent0], true);
    assertEq(s.routerPermissionInfo.routerOwners[_routerAgent0], _routerOwner0);
    assertEq(s.routerPermissionInfo.routerRecipients[_routerAgent0], _routerRecipient0);

    // Should never touch these values:
    assertEq(s.routerPermissionInfo.proposedRouterOwners[_routerAgent0], address(0));
    assertEq(s.routerPermissionInfo.proposedRouterTimestamp[_routerAgent0], 0);
  }

  function test_RoutersFacet__setupRouter_shouldHandleNoOwner() public {
    vm.expectEmit(true, true, false, true);
    emit RouterAdded(_routerAgent0, _owner);

    vm.expectEmit(true, true, false, true);
    emit RouterRecipientSet(_routerAgent0, address(0), _routerRecipient0);

    vm.prank(_owner);
    this.setupRouter(_routerAgent0, address(0), _routerRecipient0);

    assertEq(s.routerPermissionInfo.approvedRouters[_routerAgent0], true);
    assertEq(s.routerPermissionInfo.routerOwners[_routerAgent0], address(0));
    assertEq(s.routerPermissionInfo.routerRecipients[_routerAgent0], _routerRecipient0);
  }

  function test_RoutersFacet__setupRouter_shouldHandleNoRecipient() public {
    vm.expectEmit(true, true, false, true);
    emit RouterAdded(_routerAgent0, _owner);

    vm.expectEmit(true, true, false, true);
    emit RouterOwnerAccepted(_routerAgent0, address(0), _routerOwner0);

    vm.prank(_owner);
    this.setupRouter(_routerAgent0, _routerOwner0, address(0));

    assertEq(s.routerPermissionInfo.approvedRouters[_routerAgent0], true);
    assertEq(s.routerPermissionInfo.routerOwners[_routerAgent0], _routerOwner0);
    assertEq(s.routerPermissionInfo.routerRecipients[_routerAgent0], address(0));
  }

  // removeRouter
  function test_RoutersFacet__removeRouter_success() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;
    // Should also remove these values, if they were previously set.
    s.routerPermissionInfo.proposedRouterOwners[_routerAgent0] = _routerOwner1;
    s.routerPermissionInfo.proposedRouterTimestamp[_routerAgent0] = 12345;

    vm.expectEmit(true, true, false, true);
    emit RouterRemoved(_routerAgent0, _owner);

    vm.expectEmit(true, true, false, true);
    emit RouterOwnerAccepted(_routerAgent0, _routerOwner0, address(0));

    vm.expectEmit(true, true, false, true);
    emit RouterRecipientSet(_routerAgent0, _routerRecipient0, address(0));

    vm.prank(_owner);
    this.removeRouter(_routerAgent0);

    assertEq(s.routerPermissionInfo.approvedRouters[_routerAgent0], false);
    assertEq(s.routerPermissionInfo.routerOwners[_routerAgent0], address(0));
    assertEq(s.routerPermissionInfo.routerRecipients[_routerAgent0], address(0));
    assertEq(s.routerPermissionInfo.proposedRouterOwners[_routerAgent0], address(0));
    assertEq(s.routerPermissionInfo.proposedRouterTimestamp[_routerAgent0], 0);
    assertEq(s.routerPermissionInfo.approvedForPortalRouters[_routerAgent0], false);
  }

  function test_RoutersFacet__removeRouter_failsIfNotOwner() public {
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);
    vm.prank(address(123456123));
    this.removeRouter(address(0));
  }

  function test_RoutersFacet__removeRouter_failsIfRouterAddressIsZero() public {
    vm.expectRevert(RoutersFacet.RoutersFacet__removeRouter_routerEmpty.selector);
    vm.prank(_owner);
    this.removeRouter(address(0));
  }

  function test_RoutersFacet__removeRouter_failsIfRouterNotApproved() public {
    vm.expectRevert(RoutersFacet.RoutersFacet__removeRouter_notAdded.selector);
    vm.prank(_owner);
    this.removeRouter(_routerAgent0);
  }

  function test_RoutersFacet__removeRouter_handlesNoOwner() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = address(0);
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;
    s.routerPermissionInfo.proposedRouterOwners[_routerAgent0] = _routerOwner1;
    s.routerPermissionInfo.proposedRouterTimestamp[_routerAgent0] = 12345;

    vm.expectEmit(true, true, false, true);
    emit RouterRemoved(_routerAgent0, _owner);

    vm.expectEmit(true, true, false, true);
    emit RouterRecipientSet(_routerAgent0, _routerRecipient0, address(0));

    vm.prank(_owner);
    this.removeRouter(_routerAgent0);

    assertEq(s.routerPermissionInfo.approvedRouters[_routerAgent0], false);
    assertEq(s.routerPermissionInfo.routerOwners[_routerAgent0], address(0));
    assertEq(s.routerPermissionInfo.routerRecipients[_routerAgent0], address(0));
    assertEq(s.routerPermissionInfo.proposedRouterOwners[_routerAgent0], address(0));
    assertEq(s.routerPermissionInfo.proposedRouterTimestamp[_routerAgent0], 0);
  }

  function test_RoutersFacet__removeRouter_handlesNoRecipient() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = address(0);
    s.routerPermissionInfo.proposedRouterOwners[_routerAgent0] = _routerOwner1;
    s.routerPermissionInfo.proposedRouterTimestamp[_routerAgent0] = 12345;

    vm.expectEmit(true, true, false, true);
    emit RouterRemoved(_routerAgent0, _owner);

    vm.expectEmit(true, true, false, true);
    emit RouterOwnerAccepted(_routerAgent0, _routerOwner0, address(0));

    vm.prank(_owner);
    this.removeRouter(_routerAgent0);

    assertEq(s.routerPermissionInfo.approvedRouters[_routerAgent0], false);
    assertEq(s.routerPermissionInfo.routerOwners[_routerAgent0], address(0));
    assertEq(s.routerPermissionInfo.routerRecipients[_routerAgent0], address(0));
    assertEq(s.routerPermissionInfo.proposedRouterOwners[_routerAgent0], address(0));
    assertEq(s.routerPermissionInfo.proposedRouterTimestamp[_routerAgent0], 0);
  }

  // setMaxRoutersPerTransfer
  function test_RoutersFacet__setMaxRoutersPerTransfer_success() public {
    // Change from zero.
    vm.expectEmit(true, true, false, true);
    emit MaxRoutersPerTransferUpdated(123, _owner);

    s.maxRoutersPerTransfer = 0;
    vm.prank(_owner);
    this.setMaxRoutersPerTransfer(123);
    assertEq(s.maxRoutersPerTransfer, 123);

    // Increasable.
    vm.expectEmit(true, true, false, true);
    emit MaxRoutersPerTransferUpdated(9999999, _owner);

    s.maxRoutersPerTransfer = 777;
    vm.prank(_owner);
    this.setMaxRoutersPerTransfer(9999999);
    assertEq(s.maxRoutersPerTransfer, 9999999);

    // Decreasable.
    vm.expectEmit(true, true, false, true);
    emit MaxRoutersPerTransferUpdated(1, _owner);

    s.maxRoutersPerTransfer = 777;
    vm.prank(_owner);
    this.setMaxRoutersPerTransfer(1);
    assertEq(s.maxRoutersPerTransfer, 1);
  }

  function test_RoutersFacet__setMaxRoutersPerTransfer_failsIfNotOwner() public {
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);
    vm.prank(address(123456654321));
    this.setMaxRoutersPerTransfer(10);
  }

  function test_RoutersFacet__setMaxRoutersPerTransfer_failsIfZero() public {
    s.maxRoutersPerTransfer = 10;
    vm.expectRevert(RoutersFacet.RoutersFacet__setMaxRoutersPerTransfer_invalidMaxRoutersPerTransfer.selector);
    vm.prank(_owner);
    this.setMaxRoutersPerTransfer(0);
    assertEq(s.maxRoutersPerTransfer, 10);
  }

  function test_RoutersFacet__setMaxRoutersPerTransfer_failsIfRedundant() public {
    s.maxRoutersPerTransfer = 10;
    vm.expectRevert(RoutersFacet.RoutersFacet__setMaxRoutersPerTransfer_invalidMaxRoutersPerTransfer.selector);
    vm.prank(_owner);
    this.setMaxRoutersPerTransfer(10);

    assertEq(s.maxRoutersPerTransfer, 10);
  }

  // setLiquidityFeeNumerator
  function test_RoutersFacet__setLiquidityFeeNumerator_success() public {
    s.LIQUIDITY_FEE_NUMERATOR = 9995; // Fee is currently 5 basis points.

    vm.expectEmit(true, true, false, true);
    emit LiquidityFeeNumeratorUpdated(9970, _owner);

    vm.prank(_owner);
    this.setLiquidityFeeNumerator(9970); // Set fee to 30 basis points.
    assertEq(s.LIQUIDITY_FEE_NUMERATOR, 9970);
  }

  function test_RoutersFacet__setLiquidityFeeNumerator_failsIfNotOwner() public {
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);
    vm.prank(address(123456654321));
    this.setLiquidityFeeNumerator(9995);
  }

  function test_RoutersFacet__setLiquidityFeeNumerator_failsIfTooSmall() public {
    s.LIQUIDITY_FEE_NUMERATOR = 9995; // Fee is currently 5 basis points.

    vm.expectRevert(RoutersFacet.RoutersFacet__setLiquidityFeeNumerator_tooSmall.selector);
    vm.prank(_owner);
    // Set fee to 600 basis points, which is over the 5% limit.
    this.setLiquidityFeeNumerator(9400);
    assertEq(s.LIQUIDITY_FEE_NUMERATOR, 9995);
  }

  function test_RoutersFacet__setLiquidityFeeNumerator_failsIfTooLarge() public {
    s.LIQUIDITY_FEE_NUMERATOR = 9995; // Fee is currently 5 basis points.

    vm.expectRevert(RoutersFacet.RoutersFacet__setLiquidityFeeNumerator_tooLarge.selector);
    vm.prank(_owner);
    // Set fee to -100 basis points, literally making the routers give users free money.
    this.setLiquidityFeeNumerator(10100);
    assertEq(s.LIQUIDITY_FEE_NUMERATOR, 9995);
  }

  // approveRouterForPortal
  // fails if not approved and ownership not renounced
  function test_RoutersFacet__approveRouterForPortal_failsIfNotApproved() public {
    vm.expectRevert(RoutersFacet.RoutersFacet__approveRouterForPortal_notAdded.selector);
    vm.prank(_owner);
    this.approveRouterForPortal(_routerAgent0);
  }

  // fails if already approved for portals
  function test_RoutersFacet__approveRouterForPortal_failsIfAlreadyApproved() public {
    s._routerWhitelistRemoved = true;
    s.routerPermissionInfo.approvedForPortalRouters[_routerAgent0] = true;
    vm.expectRevert(RoutersFacet.RoutersFacet__approveRouterForPortal_alreadyApproved.selector);
    vm.prank(_owner);
    this.approveRouterForPortal(_routerAgent0);
  }

  // works
  function test_RoutersFacet__approveRouterForPortal_success() public {
    s._routerWhitelistRemoved = true;
    vm.expectEmit(true, true, true, true);
    emit RouterApprovedForPortal(_routerAgent0, _owner);

    vm.prank(_owner);
    this.approveRouterForPortal(_routerAgent0);
    assertTrue(s.routerPermissionInfo.approvedForPortalRouters[_routerAgent0]);
  }

  // works if router is not whitelisted, but router ownership renounced
  function test_RoutersFacet__approveRouterForPortal_successWhenWhitelistRemoved() public {
    // ensure router ownership renounced and not whitelited
    s.routerPermissionInfo.approvedForPortalRouters[_routerAgent0] = false;
    s._routerWhitelistRemoved = true;

    vm.expectEmit(true, true, true, true);
    emit RouterApprovedForPortal(_routerAgent0, _owner);

    vm.prank(_owner);
    this.approveRouterForPortal(_routerAgent0);
    assertTrue(s.routerPermissionInfo.approvedForPortalRouters[_routerAgent0]);
  }

  // unapproveRouterForPortal
  // fails if already unapproved for portals
  function test_RoutersFacet__unapproveRouterForPortal_failsIfNotApproved() public {
    s.routerPermissionInfo.approvedForPortalRouters[_routerAgent0] = false;
    vm.expectRevert(RoutersFacet.RoutersFacet__unapproveRouterForPortal_notApproved.selector);
    vm.prank(_owner);
    this.unapproveRouterForPortal(_routerAgent0);
  }

  // works
  function test_RoutersFacet__unapproveRouterForPortal_success() public {
    s.routerPermissionInfo.approvedForPortalRouters[_routerAgent0] = true;
    vm.expectEmit(true, true, true, true);
    emit RouterUnapprovedForPortal(_routerAgent0, _owner);

    vm.prank(_owner);
    this.unapproveRouterForPortal(_routerAgent0);
    assertTrue(!s.routerPermissionInfo.approvedForPortalRouters[_routerAgent0]);
  }

  // ============ Public methods ==============
  // setRouterRecipient
  function test_RoutersFacet__setRouterRecipient_success() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;

    vm.expectEmit(true, true, false, true);
    emit RouterRecipientSet(_routerAgent0, _routerRecipient0, _routerRecipient1);

    // Call must come from router owner.
    vm.prank(_routerOwner0);
    this.setRouterRecipient(_routerAgent0, _routerRecipient1);

    assertEq(s.routerPermissionInfo.routerRecipients[_routerAgent0], _routerRecipient1);

    // Shouldn't change any of these values:
    assertEq(s.routerPermissionInfo.approvedRouters[_routerAgent0], true);
    assertEq(s.routerPermissionInfo.routerOwners[_routerAgent0], _routerOwner0);
    assertEq(s.routerPermissionInfo.proposedRouterOwners[_routerAgent0], address(0));
    assertEq(s.routerPermissionInfo.proposedRouterTimestamp[_routerAgent0], 0);
  }

  // Should work if owner == address(0) && msg.sender == router
  function test_RoutersFacet__setRouterRecipient_successIfOwnerEmpty() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = address(0);
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;

    vm.prank(_routerAgent0);
    this.setRouterRecipient(_routerAgent0, _routerRecipient1);
    assertEq(s.routerPermissionInfo.routerRecipients[_routerAgent0], _routerRecipient1);
  }

  // Should work if msg.sender == owner
  function test_RoutersFacet__setRouterRecipient_successIfOwnerSet() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;

    vm.prank(_routerOwner0);
    this.setRouterRecipient(_routerAgent0, _routerRecipient1);
    assertEq(s.routerPermissionInfo.routerRecipients[_routerAgent0], _routerRecipient1);
  }

  // Fail if setting a duplicate recipient
  function test_RoutersFacet__setRouterRecipient_failsIfRedundantRecipient() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;

    vm.expectRevert(RoutersFacet.RoutersFacet__setRouterRecipient_notNewRecipient.selector);
    vm.prank(_routerOwner0);
    this.setRouterRecipient(_routerAgent0, _routerRecipient0);

    assertEq(s.routerPermissionInfo.routerRecipients[_routerAgent0], _routerRecipient0);
  }

  // Fail if owner == address(0) && msg.sender != router
  function test_RoutersFacet__setRouterRecipient_failsIfEmptyOwnerSenderNotRouter() public {
    vm.prank(address(2));
    vm.expectRevert(abi.encodeWithSelector(RoutersFacet.RoutersFacet__onlyRouterOwner_notRouterOwner.selector));
    this.setRouterRecipient(_routerAgent0, address(0));
  }

  // Fail if owner != address(0) && msg.sender != owner
  function test_RoutersFacet__setRouterRecipient_failsIfNotOwner() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;

    vm.prank(_routerOwner1);
    vm.expectRevert(abi.encodeWithSelector(RoutersFacet.RoutersFacet__onlyRouterOwner_notRouterOwner.selector));
    this.setRouterRecipient(_routerAgent0, address(0));
  }

  // proposeRouterOwner

  // Fails if owner != address(0), msg.sender != owner
  function test_RoutersFacet__proposeRouterOwner_failIfNotOwnerWithOwnerSet() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;

    vm.expectRevert(RoutersFacet.RoutersFacet__onlyRouterOwner_notRouterOwner.selector);
    vm.prank(address(123456654321));
    this.proposeRouterOwner(_routerAgent0, _routerOwner1);
  }

  // Fails if owner == address(0), msg.sender != router
  function test_RoutersFacet__proposeRouterOwner_failIfNotOwnerWithoutSet() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = address(0);
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;

    vm.expectRevert(RoutersFacet.RoutersFacet__onlyRouterOwner_notRouterOwner.selector);
    vm.prank(address(123456654321));
    this.proposeRouterOwner(_routerAgent0, _routerOwner1);
  }

  // Fail if propose current owner
  function test_RoutersFacet__proposeRouterOwner_failsIfAlreadyOwner() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;

    vm.prank(_routerOwner0);
    vm.expectRevert(abi.encodeWithSelector(RoutersFacet.RoutersFacet__proposeRouterOwner_notNewOwner.selector));
    this.proposeRouterOwner(_routerAgent0, _routerOwner0);
  }

  // Fail if proposed owner is same as the previous proposed
  function test_RoutersFacet__proposeRouterOwner_failsIfAlreadyProposed() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;
    s.routerPermissionInfo.proposedRouterOwners[_routerAgent0] = _routerOwner1;

    vm.prank(_routerOwner0);
    vm.expectRevert(abi.encodeWithSelector(RoutersFacet.RoutersFacet__proposeRouterOwner_badRouter.selector));
    this.proposeRouterOwner(_routerAgent0, _routerOwner1);
  }

  // Should work
  function test_RoutersFacet__proposeRouterOwner_success() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;

    vm.prank(_routerOwner0);
    this.proposeRouterOwner(_routerAgent0, _routerOwner1);
    assertEq(this.getProposedRouterOwner(_routerAgent0), _routerOwner1);
  }

  // acceptProposedRouterOwner
  // Should work if proposed == address(0)  && (_owner == address(0) && msg.sender == router) || _owner != msg.sender
  function test_RoutersFacet__acceptProposedRouterOwner_successWhenProposedAndOwnerNotSet() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = address(0);
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;
    s.routerPermissionInfo.proposedRouterOwners[_routerAgent0] = address(0);

    vm.expectEmit(true, true, false, true);
    emit RouterOwnerAccepted(_routerAgent0, _routerAgent0, address(0));

    // If the proposed owner is not set and no current owner is set, the router itself must be the caller.
    vm.prank(_routerAgent0);
    this.acceptProposedRouterOwner(_routerAgent0);
    // No change...
    assertEq(s.routerPermissionInfo.routerOwners[_routerAgent0], address(0));
  }

  // Should work if proposed == address(0)  &&  msg.sender == owner
  function test_RoutersFacet__acceptProposedRouterOwner_successWhenProposedNotSet() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;
    s.routerPermissionInfo.proposedRouterOwners[_routerAgent0] = address(0);

    vm.prank(_routerOwner0);
    this.acceptProposedRouterOwner(_routerAgent0);
    // The owner should be address(0) now.
    assertEq(s.routerPermissionInfo.routerOwners[_routerAgent0], address(0));
  }

  // Should work if proposed != address(0)  &&  msg.sender == _proposed
  function test_RoutersFacet__acceptProposedRouterOwner_successWhenProposedIsSet() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;
    s.routerPermissionInfo.proposedRouterOwners[_routerAgent0] = _routerOwner1;
    s.routerPermissionInfo.proposedRouterTimestamp[_routerAgent0] = block.timestamp;

    vm.prank(_routerOwner1);
    vm.warp(block.timestamp + 8 days);

    this.acceptProposedRouterOwner(_routerAgent0);
    assertEq(s.routerPermissionInfo.routerOwners[_routerAgent0], _routerOwner1);
    // Should have cleared the proposed owner.
    assertEq(s.routerPermissionInfo.proposedRouterOwners[_routerAgent0], address(0));
    // Should have cleared the proposed owner timestamp.
    assertEq(s.routerPermissionInfo.proposedRouterTimestamp[_routerAgent0], 0);
  }

  // Fail if proposed == address(0) && (_owner != address(0) && msg.sender != router) || _owner != msg.sender
  function test_RoutersFacet__acceptProposedRouterOwner_failsIfNotOwnerWhenOwnerEmpty() public {
    address _router = address(1);

    vm.expectRevert(abi.encodeWithSelector(RoutersFacet.RoutersFacet__onlyProposedRouterOwner_notRouterOwner.selector));
    vm.prank(address(2));
    this.acceptProposedRouterOwner(_router);
  }

  // Fail if proposed == address(0) && (_owner != address(0) && msg.sender != router) || _owner != msg.sender
  function test_RoutersFacet__acceptProposedRouterOwner_failsIfNotOwnerWhenOwnerSet() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;

    vm.prank(address(2));
    vm.expectRevert(abi.encodeWithSelector(RoutersFacet.RoutersFacet__onlyProposedRouterOwner_notRouterOwner.selector));
    this.acceptProposedRouterOwner(_routerAgent0);
  }

  // Fail if proposed != address(0) && msg.sender != _proposed
  function test_RoutersFacet__acceptProposedRouterOwner_failsIfNotProposedWhenProposedSet() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = _routerOwner0;
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;
    s.routerPermissionInfo.proposedRouterOwners[_routerAgent0] = _routerOwner1;
    s.routerPermissionInfo.proposedRouterTimestamp[_routerAgent0] = block.timestamp;

    vm.prank(_routerOwner2);
    vm.expectRevert(
      abi.encodeWithSelector(RoutersFacet.RoutersFacet__onlyProposedRouterOwner_notProposedRouterOwner.selector)
    );
    this.acceptProposedRouterOwner(_routerAgent0);
  }

  // addLiquidityForRouter
  function test_RoutersFacet__addLiquidityForRouter_failsIfNoRouter() public {
    uint256 amount = 10;
    vm.expectRevert(RoutersFacet.RoutersFacet__addLiquidityForRouter_routerEmpty.selector);
    this.addRouterLiquidityFor(amount, _local, address(0));
  }

  function test_RoutersFacet__addLiquidityForRouter_failsIfNoAmount() public {
    uint256 amount = 0;
    vm.expectRevert(RoutersFacet.RoutersFacet__addLiquidityForRouter_amountIsZero.selector);
    this.addRouterLiquidityFor(amount, _local, _routerAgent0);
  }

  function test_RoutersFacet__addLiquidityForRouter_failsIfRouterUnapproved() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = false;
    uint256 amount = 10000;
    vm.expectRevert(RoutersFacet.RoutersFacet__addLiquidityForRouter_badRouter.selector);
    this.addRouterLiquidityFor(amount, _local, _routerAgent0);
  }

  function test_RoutersFacet__addLiquidityForRouter_failsIfAssetUnapproved() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.approvedAssets[_canonicalId] = false;
    uint256 amount = 10000;
    vm.expectRevert(RoutersFacet.RoutersFacet__addLiquidityForRouter_badAsset.selector);
    this.addRouterLiquidityFor(amount, _local, _routerAgent0);
  }

  function test_RoutersFacet__addLiquidityForRouter_worksForToken() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.approvedAssets[_canonicalKey] = true;
    address caller = address(1233422312);
    TestERC20(_local).mint(caller, 10 ether);

    uint256 amount = 10000;

    uint256 initCaller = IERC20(_local).balanceOf(caller);
    uint256 initLiquidity = this.routerBalances(_routerAgent0, _local);

    vm.prank(caller);
    IERC20(_local).approve(address(this), amount);

    vm.expectEmit(true, true, true, true);
    emit RouterLiquidityAdded(_routerAgent0, _local, _canonicalKey, amount, caller);
    vm.prank(caller);
    this.addRouterLiquidityFor(amount, _local, _routerAgent0);

    assertEq(IERC20(_local).balanceOf(caller), initCaller - amount);
    assertEq(this.routerBalances(_routerAgent0, _local), initLiquidity + amount);
  }

  // addLiquidity
  function test_RoutersFacet__addLiquidity_routerIsSender() public {
    s.routerPermissionInfo.approvedRouters[_routerAgent0] = true;
    s.approvedAssets[_canonicalKey] = true;
    TestERC20(_local).mint(_routerAgent0, 10 ether);

    uint256 amount = 10000;

    uint256 initCaller = IERC20(_local).balanceOf(_routerAgent0);
    uint256 initLiquidity = this.routerBalances(_routerAgent0, _local);

    vm.prank(_routerAgent0);
    IERC20(_local).approve(address(this), amount);

    vm.expectEmit(true, true, true, true);
    emit RouterLiquidityAdded(_routerAgent0, address(_local), _canonicalKey, amount, _routerAgent0);
    vm.prank(_routerAgent0);
    this.addRouterLiquidity(amount, _local);

    assertEq(IERC20(_local).balanceOf(_routerAgent0), initCaller - amount);
    assertEq(this.routerBalances(_routerAgent0, _local), initLiquidity + amount);
  }

  // removeRouterLiquidityFor
  function test_RoutersFacet__removeRouterLiquidityFor_failsIfNotRouterOwner() public {
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = address(0);
    s.routerPermissionInfo.routerOwners[_routerAgent0] = address(0);
    address to = address(0);
    uint256 amount = 100;
    vm.expectRevert(RoutersFacet.RoutersFacet__removeRouterLiquidityFor_notOwner.selector);
    vm.prank(address(123567));
    this.removeRouterLiquidityFor(amount, _local, payable(to), _routerAgent0);
  }

  function test_RoutersFacet__removeRouterLiquidityFor_works() public {
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = address(0);
    s.routerPermissionInfo.routerOwners[_routerAgent0] = address(0);
    s.routerBalances[_routerAgent0][_local] = 10 ether;

    address to = address(12);
    uint256 amount = 100;

    uint256 initLiquidity = this.routerBalances(_routerAgent0, _local);
    uint256 initBalance = IERC20(_local).balanceOf(to);

    vm.expectEmit(true, true, true, true);
    emit RouterLiquidityRemoved(_routerAgent0, to, _local, amount, _routerAgent0);
    vm.prank(_routerAgent0);
    this.removeRouterLiquidityFor(amount, _local, payable(to), _routerAgent0);

    assertEq(this.routerBalances(_routerAgent0, _local), initLiquidity - amount);
    assertEq(IERC20(_local).balanceOf(to), initBalance + amount);
  }

  // removeRouterLiquidity
  function test_RoutersFacet__removeRouterLiquidity_failsIfNoRecipient() public {
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = address(0);
    s.routerPermissionInfo.routerOwners[_routerAgent0] = address(0);
    address to = address(0);
    uint256 amount = 100;
    vm.expectRevert(RoutersFacet.RoutersFacet__removeRouterLiquidity_recipientEmpty.selector);
    vm.prank(_routerAgent0);
    this.removeRouterLiquidity(amount, _local, payable(to));
  }

  function test_RoutersFacet__removeRouterLiquidity_failsIfNoAmount() public {
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = address(0);
    s.routerPermissionInfo.routerOwners[_routerAgent0] = address(0);
    address to = address(12345);
    uint256 amount = 0;
    vm.expectRevert(RoutersFacet.RoutersFacet__removeRouterLiquidity_amountIsZero.selector);
    vm.prank(_routerAgent0);
    this.removeRouterLiquidity(amount, _local, payable(to));
  }

  function test_RoutersFacet__removeRouterLiquidity_failsIfNotEnoughFunds() public {
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = address(0);
    s.routerPermissionInfo.routerOwners[_routerAgent0] = address(0);
    s.routerBalances[_routerAgent0][_local] = 0;
    address to = address(12345);
    uint256 amount = 10000;
    vm.expectRevert(RoutersFacet.RoutersFacet__removeRouterLiquidity_insufficientFunds.selector);
    vm.prank(_routerAgent0);
    this.removeRouterLiquidity(amount, _local, payable(to));
  }

  // removeLiquidity
  function test_RoutersFacet__removeRouterLiquidity_worksWithRecipientSet() public {
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = _routerRecipient0;
    s.routerPermissionInfo.routerOwners[_routerAgent0] = address(0);
    s.routerBalances[_routerAgent0][_local] = 10 ether;

    address to = address(1234);
    uint256 amount = 100;

    uint256 initLiquidity = this.routerBalances(_routerAgent0, _local);
    uint256 initBalance = IERC20(_local).balanceOf(_routerRecipient0);

    vm.expectEmit(true, true, true, true);
    emit RouterLiquidityRemoved(_routerAgent0, _routerRecipient0, _local, amount, _routerAgent0);
    vm.prank(_routerAgent0);
    this.removeRouterLiquidity(amount, _local, payable(to));

    assertEq(this.routerBalances(_routerAgent0, _local), initLiquidity - amount);
    assertEq(IERC20(_local).balanceOf(_routerRecipient0), initBalance + amount);
  }

  function test_RoutersFacet__removeRouterLiquidity_worksWithToken() public {
    s.routerPermissionInfo.routerRecipients[_routerAgent0] = address(0);
    s.routerPermissionInfo.routerOwners[_routerAgent0] = address(0);
    s.routerBalances[_routerAgent0][_local] = 10 ether;

    address to = address(1234);
    uint256 amount = 100;

    uint256 initLiquidity = this.routerBalances(_routerAgent0, _local);
    uint256 initBalance = IERC20(_local).balanceOf(to);

    vm.expectEmit(true, true, true, true);
    emit RouterLiquidityRemoved(_routerAgent0, to, _local, amount, _routerAgent0);
    vm.prank(_routerAgent0);
    this.removeRouterLiquidity(amount, _local, payable(to));

    assertEq(this.routerBalances(_routerAgent0, _local), initLiquidity - amount);
    assertEq(IERC20(_local).balanceOf(to), initBalance + amount);
  }
}
