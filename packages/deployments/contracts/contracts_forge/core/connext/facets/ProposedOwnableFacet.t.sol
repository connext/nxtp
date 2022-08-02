// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {ProposedOwnableFacet} from "../../../../contracts/core/connext/facets/ProposedOwnableFacet.sol";
import {LibDiamond} from "../../../../contracts/core/connext/libraries/LibDiamond.sol";

import "../../../utils/Mock.sol";
import "../../../utils/FacetHelper.sol";

contract ProposedOwnableFacetTest is ProposedOwnableFacet, FacetHelper {
  // ============ Storage ============
  address _owner = address(123123);

  // ============ Test set up ============
  function setUp() public {
    LibDiamond.setContractOwner(_owner);
    assertEq(this.owner(), _owner);
  }

  // ============ Utils ============
  function utils_proposeRenounceRouterAndAssert() public {
    assertEq(this.routerWhitelistTimestamp(), 0);

    vm.expectEmit(true, true, true, true);
    emit RouterWhitelistRemovalProposed(block.timestamp);

    vm.prank(this.owner());
    this.proposeRouterWhitelistRemoval();

    assertEq(this.routerWhitelistTimestamp(), block.timestamp);
    assertTrue(!this.routerWhitelistRemoved());
    assertTrue(!this.renounced());
  }

  function utils_renounceRouterAndAssert() public {
    assertTrue(this.routerWhitelistTimestamp() != 0);

    vm.expectEmit(true, true, true, true);
    emit RouterWhitelistRemoved(true);

    vm.prank(this.owner());
    this.removeRouterWhitelist();

    assertEq(this.routerWhitelistTimestamp(), 0);
    assertTrue(this.routerWhitelistRemoved());
    assertTrue(!this.renounced());
  }

  function utils_proposeRenounceAssetAndAssert() public {
    assertEq(this.assetWhitelistTimestamp(), 0);

    vm.expectEmit(true, true, true, true);
    emit AssetWhitelistRemovalProposed(block.timestamp);

    vm.prank(this.owner());
    this.proposeAssetWhitelistRemoval();

    assertEq(this.assetWhitelistTimestamp(), block.timestamp);
    assertTrue(!this.assetWhitelistRemoved());
    assertTrue(!this.renounced());
  }

  function utils_renounceAssetAndAssert() public {
    assertTrue(this.assetWhitelistTimestamp() != 0);

    vm.expectEmit(true, true, true, true);
    emit AssetWhitelistRemoved(true);

    vm.prank(this.owner());
    this.removeAssetWhitelist();

    assertEq(this.assetWhitelistTimestamp(), 0);
    assertTrue(this.assetWhitelistRemoved());
    assertTrue(!this.renounced());
  }

  function utils_proposeNewOwnerAndAssert(address _proposed) public {
    // Assert change
    address current = this.owner();
    assertTrue(_proposed != current);

    // Assert event
    vm.expectEmit(true, true, true, true);
    emit OwnershipProposed(_proposed);

    // Call
    vm.prank(current);
    this.proposeNewOwner(_proposed);

    // Assert changes
    assertEq(this.owner(), current);
    assertEq(this.proposed(), _proposed);
    assertEq(this.proposedTimestamp(), block.timestamp);
  }

  function utils_acceptNewOwnerAndAssert(address _proposed) public {
    // Assert change
    address current = this.owner();
    assertTrue(_proposed != current);

    // Assert event
    vm.expectEmit(true, true, true, true);
    emit OwnershipTransferred(current, _proposed);

    // Call
    bool isRenounce = _proposed == address(0);
    if (isRenounce) {
      vm.prank(current);
      this.renounceOwnership();
    } else {
      vm.prank(_proposed);
      this.acceptProposedOwner();
    }

    // Assert changes
    assertEq(this.owner(), _proposed);
    assertEq(this.proposed(), address(0));
    assertEq(this.proposedTimestamp(), 0);
    assertEq(this.renounced(), isRenounce);
  }

  function utils_transferOwnership(address _proposed) public {
    // Propose new owner
    utils_proposeNewOwnerAndAssert(_proposed);

    // Fast-forward from delay
    vm.warp(block.timestamp + 7 days + 1);

    // Accept new owner
    utils_acceptNewOwnerAndAssert(_proposed);
  }

  // ============ owner ============
  // tested in assertion functions

  // ============ routerWhitelistRemoved ============
  // tested in assertion functions

  // ============ assetWhitelistRemoved ============
  // tested in assertion functions

  // ============ proposed ============
  // tested in assertion functions

  // ============ proposedTimestamp ============
  // tested in assertion functions

  // ============ routerWhitelistTimestamp ============
  // tested in assertion functions

  // ============ assetWhitelistTimestamp ============
  // tested in assertion functions

  // ============ delay ============
  function test_ProposedOwnableFacet__delay_works() public {
    assertEq(this.delay(), 7 days);
  }

  // ============ proposeRouterWhitelistRemoval ============
  function test_ProposedOwnableFacet__proposeRouterWhitelistRemoval_failsIfNotOwner() public {
    vm.expectRevert(BaseConnextFacet__onlyOwner_notOwner.selector);
    this.proposeRouterWhitelistRemoval();
  }

  function test_ProposedOwnableFacet__proposeRouterWhitelistRemoval_failsIfAlreadyRenounced() public {
    utils_proposeRenounceRouterAndAssert();
    vm.warp(block.timestamp + this.delay() + 1);
    utils_renounceRouterAndAssert();

    vm.expectRevert(ProposedOwnableFacet__proposeRouterWhitelistRemoval_noOwnershipChange.selector);
    vm.prank(_owner);
    this.proposeRouterWhitelistRemoval();
  }

  function test_ProposedOwnableFacet__proposeRouterWhitelistRemoval_works() public {
    utils_proposeRenounceRouterAndAssert();
  }

  // ============ removeRouterWhitelist ============
  function test_ProposedOwnableFacet__removeRouterWhitelist_failsIfNotOwner() public {
    utils_proposeRenounceRouterAndAssert();
    vm.expectRevert(BaseConnextFacet__onlyOwner_notOwner.selector);
    this.removeRouterWhitelist();
  }

  function test_ProposedOwnableFacet__removeRouterWhitelist_failsIfAlreadyRenounced() public {
    utils_proposeRenounceRouterAndAssert();
    vm.warp(block.timestamp + this.delay() + 1);
    utils_renounceRouterAndAssert();

    vm.prank(this.owner());
    vm.expectRevert(ProposedOwnableFacet__removeRouterWhitelist_noOwnershipChange.selector);
    this.removeRouterWhitelist();
  }

  function test_ProposedOwnableFacet__removeRouterWhitelist_failsIfNotProposed() public {
    vm.prank(this.owner());
    vm.expectRevert(ProposedOwnableFacet__removeRouterWhitelist_noProposal.selector);
    this.removeRouterWhitelist();
  }

  function test_ProposedOwnableFacet__removeRouterWhitelist_failsIfDelayNotElapsed() public {
    utils_proposeRenounceRouterAndAssert();
    vm.prank(this.owner());
    vm.expectRevert(ProposedOwnableFacet__removeRouterWhitelist_delayNotElapsed.selector);
    this.removeRouterWhitelist();
  }

  function test_ProposedOwnableFacet__removeRouterWhitelist_works() public {
    utils_proposeRenounceRouterAndAssert();
    vm.warp(block.timestamp + this.delay() + 1);
    utils_renounceRouterAndAssert();
  }

  // ============ proposeAssetWhitelistRemoval ============
  function test_ProposedOwnableFacet__proposeAssetWhitelistRemoval_failsIfNotOwner() public {
    vm.expectRevert(BaseConnextFacet__onlyOwner_notOwner.selector);
    this.proposeAssetWhitelistRemoval();
  }

  function test_ProposedOwnableFacet__proposeAssetWhitelistRemoval_failsIfAlreadyRenounced() public {
    utils_proposeRenounceAssetAndAssert();
    vm.warp(block.timestamp + this.delay() + 1);
    utils_renounceAssetAndAssert();

    vm.expectRevert(ProposedOwnableFacet__proposeAssetWhitelistRemoval_noOwnershipChange.selector);
    vm.prank(_owner);
    this.proposeAssetWhitelistRemoval();
  }

  function test_ProposedOwnableFacet__proposeAssetWhitelistRemoval_works() public {
    utils_proposeRenounceAssetAndAssert();
  }

  // ============ removeAssetWhitelist ============
  function test_ProposedOwnableFacet__removeAssetWhitelist_failsIfNotOwner() public {
    utils_proposeRenounceAssetAndAssert();
    vm.expectRevert(BaseConnextFacet__onlyOwner_notOwner.selector);
    this.removeAssetWhitelist();
  }

  function test_ProposedOwnableFacet__removeAssetWhitelist_failsIfAlreadyRenounced() public {
    utils_proposeRenounceAssetAndAssert();
    vm.warp(block.timestamp + this.delay() + 1);
    utils_renounceAssetAndAssert();

    vm.prank(this.owner());
    vm.expectRevert(ProposedOwnableFacet__removeAssetWhitelist_noOwnershipChange.selector);
    this.removeAssetWhitelist();
  }

  function test_ProposedOwnableFacet__removeAssetWhitelist_failsIfNotProposed() public {
    vm.prank(this.owner());
    vm.expectRevert(ProposedOwnableFacet__removeAssetWhitelist_noProposal.selector);
    this.removeAssetWhitelist();
  }

  function test_ProposedOwnableFacet__removeAssetWhitelist_failsIfDelayNotElapsed() public {
    utils_proposeRenounceAssetAndAssert();
    vm.prank(this.owner());
    vm.expectRevert(ProposedOwnableFacet__removeAssetWhitelist_delayNotElapsed.selector);
    this.removeAssetWhitelist();
  }

  function test_ProposedOwnableFacet__removeAssetWhitelist_works() public {
    utils_proposeRenounceAssetAndAssert();
    vm.warp(block.timestamp + this.delay() + 1);
    utils_renounceAssetAndAssert();
  }

  // ============ renounced ============
  // tested in assertions

  // ============ proposeNewOwner ============
  function test_ProposedOwnableFacet__proposeNewOwner_failsIfNotOwner() public {
    vm.expectRevert(BaseConnextFacet__onlyOwner_notOwner.selector);
    this.proposeNewOwner(address(12));
  }

  function test_ProposedOwnableFacet__proposeNewOwner_failsIfNoChange() public {
    utils_proposeNewOwnerAndAssert(address(12));

    vm.expectRevert(ProposedOwnableFacet__proposeNewOwner_invalidProposal.selector);
    vm.prank(_owner);
    this.proposeNewOwner(address(12));
  }

  function test_ProposedOwnableFacet__proposeNewOwner_failsIfProposingOwner() public {
    vm.expectRevert(ProposedOwnableFacet__proposeNewOwner_noOwnershipChange.selector);
    vm.prank(_owner);
    this.proposeNewOwner(_owner);
  }

  function test_ProposedOwnableFacet__proposeNewOwner_works() public {
    utils_proposeNewOwnerAndAssert(address(12));
  }

  // ============ renounceOwnership ============
  function test_ProposedOwnableFacet__renounceOwnership_failsIfNotOwner() public {
    utils_proposeNewOwnerAndAssert(address(0));

    vm.expectRevert(BaseConnextFacet__onlyOwner_notOwner.selector);
    this.renounceOwnership();
  }

  function test_ProposedOwnableFacet__renounceOwnership_failsIfNoProposal() public {
    vm.expectRevert(ProposedOwnableFacet__renounceOwnership_noProposal.selector);
    vm.prank(_owner);
    this.renounceOwnership();
  }

  function test_ProposedOwnableFacet__renounceOwnership_failsIfDelayNotElapsed() public {
    utils_proposeNewOwnerAndAssert(address(1));

    vm.prank(_owner);
    vm.expectRevert(ProposedOwnableFacet__renounceOwnership_delayNotElapsed.selector);
    this.renounceOwnership();
  }

  function test_ProposedOwnableFacet__renounceOwnership_failsIfProposedNonNull() public {
    utils_proposeNewOwnerAndAssert(address(1));
    vm.warp(block.timestamp + this.delay() + 1);

    vm.prank(_owner);
    vm.expectRevert(ProposedOwnableFacet__renounceOwnership_invalidProposal.selector);
    this.renounceOwnership();
  }

  function test_ProposedOwnableFacet__renounceOwnership_works() public {
    assertTrue(!this.renounced());

    utils_transferOwnership(address(0));
    assertTrue(this.renounced());
  }

  // ============ acceptProposedOwner ============
  function test_ProposedOwnableFacet__acceptProposedOwner_failsIfNotProposed() public {
    address proposed = address(12);
    utils_proposeNewOwnerAndAssert(proposed);

    vm.expectRevert(BaseConnextFacet__onlyProposed_notProposedOwner.selector);
    this.acceptProposedOwner();
  }

  function test_ProposedOwnableFacet__acceptProposedOwner_failsIfProposedIsOwner() public {
    address proposed = address(12);
    utils_proposeNewOwnerAndAssert(proposed);

    LibDiamond.setContractOwner(proposed);

    vm.prank(proposed);
    vm.expectRevert(ProposedOwnableFacet__acceptProposedOwner_noOwnershipChange.selector);
    this.acceptProposedOwner();
  }

  function test_ProposedOwnableFacet__acceptProposedOwner_failsIfDelayNotElapsed() public {
    address proposed = address(12);
    utils_proposeNewOwnerAndAssert(proposed);

    vm.prank(proposed);
    vm.expectRevert(ProposedOwnableFacet__acceptProposedOwner_delayNotElapsed.selector);
    this.acceptProposedOwner();
  }

  function test_ProposedOwnableFacet__acceptProposedOwner_works() public {
    utils_transferOwnership(address(12));
  }

  // ============ pause ============
  function test_ProposedOwnableFacet__pause_works() public {
    assertTrue(!s._paused);
    vm.prank(_owner);

    vm.expectEmit(true, true, true, true);
    emit Paused();

    this.pause();

    assertTrue(s._paused);
  }

  // ============ unpause ============
  function test_ProposedOwnableFacet__unpause_works() public {
    vm.prank(_owner);
    this.pause();

    assertTrue(s._paused);
    vm.prank(_owner);

    vm.expectEmit(true, true, true, true);
    emit Unpaused();

    this.unpause();

    assertTrue(!s._paused);
  }
}
