// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {LibDiamond} from "../../../../contracts/core/connext/libraries/LibDiamond.sol";
import {RelayerFeeRouter} from "../../../../contracts/core/relayer-fee/RelayerFeeRouter.sol";
import {RelayerFacet, BaseConnextFacet} from "../../../../contracts/core/connext/facets/RelayerFacet.sol";

import {MockTokenRegistry} from "../../../utils/Mock.sol";
import "../../../utils/FacetHelper.sol";

import "forge-std/console.sol";

contract RelayerFacetTest is RelayerFacet, FacetHelper {
  // ============ storage ============
  // owner
  address _owner = address(12345);

  // sample data
  uint32 _domain = 1000;

  address _relayer = address(222);
  address _relayerFeeRouter = address(555);

  // ============ Test set up ============
  function setUp() public {
    setOwner(_owner);

    bytes memory code = address(new RelayerFeeRouter()).code;
    vm.etch(_relayerFeeRouter, code);
    s.relayerFeeRouter = RelayerFeeRouter(_relayerFeeRouter);
  }

  // ============ Utils ==============
  // Set diamond storage owner
  function setOwner(address owner) internal {
    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    ds.contractOwner = owner;
  }

  // ============ Test methods ============
  // ============ Modifiers ============
  // TODO: onlyRelayerFeeRouter
  // whenNotPaused? onlyOwner?

  // ============ Getters ==============
  // transferRelayer
  // retrieves empty if not set
  function test_RelayerFacet__transferRelayer_empty() public {
    bytes32 transferId = bytes32("test");
    assertEq(this.transferRelayer(transferId), address(0));
  }

  // retrieves defined value
  function test_RelayerFacet__transferRelayer_defined() public {
    bytes32 transferId = bytes32("test");
    s.transferRelayer[transferId] = address(42);
    assertEq(this.transferRelayer(transferId), address(42));
  }

  // approvedRelayers
  // retrieves false if not set
  function test_RelayerFacet__approvedRelayers_empty() public {
    assertEq(this.approvedRelayers(address(42)), false);
  }

  // true works
  function test_RelayerFacet__approvedRelayers_definedTrue() public {
    s.approvedRelayers[_relayer] = true;
    assertEq(this.approvedRelayers(_relayer), true);
  }

  // false works
  function test_RelayerFacet__approvedRelayers_definedFalse() public {
    s.approvedRelayers[_relayer] = false;
    assertEq(this.approvedRelayers(_relayer), false);
  }

  // relayerFeeRouter
  // retrieves empty if not set
  function test_RelayerFacet__relayerFeeRouter_empty() public {
    s.relayerFeeRouter = RelayerFeeRouter(address(0));
    assertEq(address(this.relayerFeeRouter()), address(0));
  }

  // retrieves defined
  function test_RelayerFacet__relayerFeeRouter_defined() public {
    assertEq(address(this.relayerFeeRouter()), _relayerFeeRouter);
  }

  // ============ Admin functions ============
  // setRelayerFeeRouter
  // fail if not owner
  function test_RelayerFacet__setRelayerFeeRouter_failsIfNotOwner() public {
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);

    this.setRelayerFeeRouter(address(42));
  }

  // fail if same as previous relayer fee router
  function test_RelayerFacet__setRelayerFeeRouter_failsIfRedundant() public {
    vm.expectRevert(RelayerFacet.RelayerFacet__setRelayerFeeRouter_invalidRelayerFeeRouter.selector);

    vm.prank(_owner);
    this.setRelayerFeeRouter(_relayerFeeRouter);
  }

  // fail if address is not contract
  function test_RelayerFacet__setRelayerFeeRouter_failsIfAddressNotContract() public {
    vm.expectRevert(RelayerFacet.RelayerFacet__setRelayerFeeRouter_invalidRelayerFeeRouter.selector);

    vm.prank(_owner);
    this.setRelayerFeeRouter(address(42));
  }

  // works; updates relayerFeeRouter
  function test_RelayerFacet__setRelayerFeeRouter_works() public {
    address newRelayerFeeRouter = address(42);
    bytes memory code = address(new RelayerFeeRouter()).code;
    vm.etch(newRelayerFeeRouter, code);

    vm.expectEmit(true, true, true, true);
    emit RelayerFeeRouterUpdated(_relayerFeeRouter, newRelayerFeeRouter, _owner);

    vm.prank(_owner);
    this.setRelayerFeeRouter(newRelayerFeeRouter);

    assertEq(address(s.relayerFeeRouter), newRelayerFeeRouter);
  }

  // addRelayer
  // fails if not owner
  function test_RelayerFacet__addRelayer_failsIfNotOwner() public {
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);

    this.addRelayer(address(42));
  }

  // fails if already approved
  function test_RelayerFacet__addRelayer_failsIfAlreadyApproved() public {
    address relayer = address(42);
    s.approvedRelayers[relayer] = true;
    vm.expectRevert(RelayerFacet.RelayerFacet__addRelayer_alreadyApproved.selector);

    vm.prank(_owner);
    this.addRelayer(relayer);
  }

  // works; adds an approved relayer
  function test_RelayerFacet__addRelayer_works() public {
    address relayer = address(42);
    s.approvedRelayers[relayer] = false;

    vm.expectEmit(true, true, true, true);
    emit RelayerAdded(relayer, _owner);

    vm.prank(_owner);
    this.addRelayer(relayer);

    assertEq(s.approvedRelayers[relayer], true);
  }

  // removeRelayer
  // fails if not owner
  function test_RelayerFacet__removeRelayer_failsIfNotOwner() public {
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);

    this.removeRelayer(address(42));
  }

  // fails if not approved / already removed
  function test_RelayerFacet__removeRelayer_failsIfAlreadyUnapproved() public {
    address relayer = address(42);
    s.approvedRelayers[relayer] = false;
    vm.expectRevert(RelayerFacet.RelayerFacet__removeRelayer_notApproved.selector);

    vm.prank(_owner);
    this.removeRelayer(relayer);
  }

  // works; removes an approved relayer
  function test_RelayerFacet__removeRelayer_works() public {
    address relayer = address(42);
    s.approvedRelayers[relayer] = true;

    vm.expectEmit(true, true, true, true);
    emit RelayerRemoved(relayer, _owner);

    vm.prank(_owner);
    this.removeRelayer(relayer);

    assertEq(s.approvedRelayers[relayer], false);
  }

  // ============ External functions ============
  // initiateClaim
  // should fail if not relayer for the transfer (1/1)
  function test_RelayerFacet__initiateClaim_failsSingleClaimIfNotRelayer() public {
    bytes32[] memory transferIds = new bytes32[](1);
    transferIds[0] = bytes32("test");
    s.transferRelayer[transferIds[0]] = address(42);

    vm.expectRevert(
      abi.encodeWithSelector(RelayerFacet.RelayerFacet__initiateClaim_notRelayer.selector, transferIds[0])
    );
    vm.prank(_relayer);
    this.initiateClaim(_domain, _relayer, transferIds);
  }

  // should fail if not relayer for the transfer (1/200)
  function test_RelayerFacet__initiateClaim_failsMultipleClaimsIfNotRelayer() public {
    uint256 count = 200;
    bytes32[] memory transferIds = new bytes32[](count);
    for (uint32 i = 0; i < count; i++) {
      transferIds[i] = bytes32(abi.encode(i));
      s.transferRelayer[transferIds[i]] = _relayer;
    }
    s.transferRelayer[transferIds[123]] = address(42);

    vm.expectRevert(
      abi.encodeWithSelector(RelayerFacet.RelayerFacet__initiateClaim_notRelayer.selector, transferIds[123])
    );
    vm.prank(_relayer);
    this.initiateClaim(_domain, _relayer, transferIds);
  }

  // should fail if paused
  function test_RelayerFacet__initiateClaim_failsIfPaused() public {
    bytes32[] memory transferIds = new bytes32[](0);
    s._paused = true;

    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__whenNotPaused_paused.selector);
    vm.prank(_relayer);
    this.initiateClaim(_domain, _relayer, transferIds);
  }

  // should fail if transfer IDs is empty
  function test_RelayerFacet__initiateClaim_failsIfTransferIdsEmpty() public {
    bytes32[] memory transferIds = new bytes32[](0);

    vm.expectRevert(RelayerFacet.RelayerFacet__initiateClaim_emptyClaim.selector);
    vm.prank(_relayer);
    this.initiateClaim(_domain, _relayer, transferIds);
  }

  // sends transferIds via the relayer router
  function test_RelayerFacet__initiateClaim_sendsClaim() public {
    uint256 count = 1000;
    bytes32[] memory transferIds = new bytes32[](count);
    for (uint32 i = 0; i < count; i++) {
      transferIds[i] = bytes32(abi.encode(i));
      s.transferRelayer[transferIds[i]] = _relayer;
    }

    vm.mockCall(
      address(s.relayerFeeRouter),
      abi.encodeWithSelector(RelayerFeeRouter.send.selector, _domain, _relayer, transferIds),
      bytes("")
    );
    s.relayerFeeRouter.send(_domain, _relayer, transferIds);

    vm.expectCall(
      _relayerFeeRouter,
      abi.encodeWithSelector(RelayerFeeRouter.send.selector, _domain, _relayer, transferIds)
    );

    vm.expectEmit(true, true, true, true);
    emit InitiatedClaim(_domain, _relayer, _relayer, transferIds);

    vm.prank(_relayer);
    this.initiateClaim(_domain, _relayer, transferIds);
  }

  // claim
  // fails if not the relayer fee router
  function test_RelayerFacet__claim_failsIfNotRelayerFeeRouter(address other) public {
    if (other == _relayerFeeRouter) return;
    vm.expectRevert(RelayerFacet.RelayerFacet__onlyRelayerFeeRouter_notRelayerFeeRouter.selector);
    bytes32[] memory transferIds = new bytes32[](1);
    this.claim(_relayer, transferIds);
  }

  // sends total value from 1 transfer
  function test_RelayerFacet__claim_sendsFeesForSingleClaim() public {
    bytes32[] memory transferIds = new bytes32[](1);
    s.relayerFees[transferIds[0]] = 0.06 ether;

    vm.expectEmit(true, true, true, true);
    emit Claimed(_relayer, 0.06 ether, transferIds);

    vm.prank(_relayerFeeRouter);
    this.claim(_relayer, transferIds);

    assertEq(payable(_relayer).balance, 0.06 ether);
    assertEq(s.relayerFees[transferIds[0]], 0);
  }

  // sends total value from multiple transfers
  function test_RelayerFacet__claim_sendsFeesForMultipleClaims() public {
    uint256 count = 1;
    bytes32[] memory transferIds = new bytes32[](count);
    uint256 total;
    for (uint32 i = 0; i < count; i++) {
      transferIds[i] = bytes32(abi.encode(i));
      total += 0.0123 ether;
      s.relayerFees[transferIds[i]] = 0.0123 ether;
    }

    vm.expectEmit(true, true, true, true);
    emit Claimed(_relayer, total, transferIds);

    vm.prank(_relayerFeeRouter);
    this.claim(_relayer, transferIds);

    assertEq(payable(_relayer).balance, total);
    for (uint256 i = 0; i < count; i++) {
      assertEq(s.relayerFees[transferIds[i]], 0);
    }
  }
}
