// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {XAppConnectionManager, TypeCasts} from "../../../../contracts/nomad-core/contracts/XAppConnectionManager.sol";
import {TypedMemView} from "../../../../contracts/nomad-core/libs/TypedMemView.sol";

import {IBridgeRouter} from "../../../../contracts/core/connext/interfaces/IBridgeRouter.sol";

import {LibDiamond} from "../../../../contracts/core/connext/libraries/LibDiamond.sol";

import {NomadFacet} from "../../../../contracts/core/connext/facets/NomadFacet.sol";
import {BaseConnextFacet} from "../../../../contracts/core/connext/facets/BaseConnextFacet.sol";
import {CallParams, ExecuteArgs, XCallArgs, TransferIdInformation} from "../../../../contracts/core/connext/libraries/LibConnextStorage.sol";

import "../../../utils/Mock.sol";
import "../../../utils/FacetHelper.sol";

contract NomadFacetTest is NomadFacet, FacetHelper {
  // ============ Libs ============
  using TypedMemView for bytes29;
  using TypedMemView for bytes;

  struct SwapInfo {
    uint256 input;
    uint256 output; // the equivalent amount of `out` token for given `in`
  }

  // ========== Storage ===========
  // diamond storage contract owner
  address _ds_owner = address(987654321);

  // aave pool details
  address _aavePool;

  // default origin sender
  address _originSender = address(4);

  // set connextion
  bytes32 _originConnext = TypeCasts.addressToBytes32(address(12365136));

  // relayer fee
  uint256 _relayerFee = 0.1 ether;

  // default amount
  uint256 _amount = 1.1 ether;

  // default nonce on xcall
  uint256 _nonce = 1;

  // bridge router
  address _bridge = address(565656565);

  // default recovery address
  address constant _recovery = address(121212);

  // default CallParams
  CallParams _params =
    CallParams(
      address(11), // to
      bytes(""), // callData
      _originDomain, // origin domain
      _destinationDomain, // destination domain
      address(112233332211), // agent
      _recovery, // recovery address
      false, // forceSlow
      false, // receiveLocal
      address(0), // callback
      0, // callbackFee
      _relayerFee, // relayer fee
      9900 // slippage tol
    );

  // ============ Test set up ============
  function setUp() public {
    // Deploy any needed contracts.
    utils_deployContracts();
    utils_deployAssetContracts();

    vm.prank(address(this));
    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    ds.contractOwner = _ds_owner;
    s.bridgeRouter = IBridgeRouter(_bridge);
    s.connextions[_originDomain] = _originConnext;
  }

  // ============ Utils ============
  // Used in set up for deploying any needed peripheral contracts.
  function utils_deployContracts() public {
    // setup aave pool
    _aavePool = address(new MockPool(false));
    s.aavePool = _aavePool;
  }

  // Meant to mimic the corresponding `_getTransferId` method in the BridgeFacet contract.
  function utils_getTransferIdFromXCallArgs(
    XCallArgs memory _args,
    address sender,
    bytes32 canonicalId,
    uint32 canonicalDomain
  ) public view returns (bytes32) {
    return keccak256(abi.encode(s.nonce, _args.params, sender, canonicalId, canonicalDomain, _args.transactingAmount));
  }

  // Makes some mock xcall arguments using params set in storage.
  function utils_makeXCallArgs() public returns (bytes32, XCallArgs memory) {
    // get args
    XCallArgs memory args = XCallArgs(_params, _adopted, _amount, (_amount * 9990) / 10000);
    // generate transfer id
    bytes32 transferId = utils_getTransferIdFromXCallArgs(args, _originSender, _canonicalId, _canonicalDomain);

    return (transferId, args);
  }

  function utils_makeXCallArgs(address transactingAssetId) public returns (bytes32, XCallArgs memory) {
    // get args
    XCallArgs memory args = XCallArgs(_params, transactingAssetId, _amount, (_amount * 9990) / 10000);
    // generate transfer id
    bytes32 transferId = utils_getTransferIdFromXCallArgs(args, _originSender, _canonicalId, _canonicalDomain);

    return (transferId, args);
  }

  // ============ Helpers ===============

  function helpers_reconcileCaller(
    address _local,
    uint256 _amount,
    bytes32 _bridgeCaller,
    CallParams memory params
  ) public {
    (uint32 canonicalDomain, bytes32 canonicalId) = s.tokenRegistry.getTokenId(_local);
    bytes memory data = abi.encode(TransferIdInformation(params, s.nonce, _originSender));
    vm.prank(_bridge);
    this.onReceive(_originDomain, _bridgeCaller, canonicalDomain, canonicalId, _local, _amount, data);
  }

  // Helper for calling `reconcile` and asserting expected behavior.
  function helpers_reconcileAndAssert(
    bytes32 transferId,
    XCallArgs memory args,
    bytes32 _bridgeCaller,
    bytes4 expectedError
  ) public {
    bool shouldSucceed = keccak256(abi.encode(expectedError)) == keccak256(abi.encode(bytes4("")));

    uint256[] memory routerBalances = new uint256[](s.routedTransfers[transferId].length);
    for (uint256 i = 0; i < s.routedTransfers[transferId].length; i++) {
      // Warming up the slot in order to make gas estimates more accurate to appropriate conditions.
      s.routerBalances[s.routedTransfers[transferId][i]][_local] = 1 ether;
      routerBalances[i] = 1 ether;
    }

    // Get pre-reconcile balances.
    uint256 prevBalance = IERC20(_local).balanceOf(address(this));

    if (shouldSucceed) {
      vm.expectEmit(true, true, true, true);
      emit Reconciled(transferId, s.routedTransfers[transferId], _local, args.transactingAmount, _bridge);
    } else {
      vm.expectRevert(expectedError);
    }

    helpers_reconcileCaller(_local, args.transactingAmount, _bridgeCaller, args.params);

    if (shouldSucceed) {
      assertEq(s.reconciledTransfers[transferId], true);
      address[] memory routers = s.routedTransfers[transferId];
      if (routers.length != 0) {
        uint256 routerAmt = args.transactingAmount / s.routedTransfers[transferId].length;

        // Fast liquidity route. Should have reimbursed routers.
        for (uint256 i = 0; i < routers.length; i++) {
          assertEq(s.routerBalances[routers[i]][_local], routerBalances[i] + routerAmt);
        }
      }
    }
  }

  function helpers_reconcileAndAssert(bytes4 expectedError) public {
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs();
    helpers_reconcileAndAssert(transferId, args, _originConnext, expectedError);
  }

  // Shortcut for above method.
  function helpers_reconcileAndAssert() public {
    helpers_reconcileAndAssert(bytes4(""));
  }

  // ============ bridgeRouter ============
  // NOTE: tested via assertions below

  // ============ setBridgeRouter ============

  function test_NomadFacet__setBridgeRouter_works() public {
    s.bridgeRouter = IBridgeRouter(address(0));
    assertEq(address(this.bridgeRouter()), address(0));
    address value = address(1234);

    vm.prank(LibDiamond.contractOwner());
    this.setBridgeRouter(value);
    assertEq(address(this.bridgeRouter()), value);
  }

  function test_NomadFacet__setBridgeRouter_failsIfNotOwner() public {
    s.bridgeRouter = IBridgeRouter(address(0));
    assertEq(address(this.bridgeRouter()), address(0));
    address value = address(1234);
    vm.prank(address(2345));
    vm.expectRevert(abi.encodeWithSelector(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector));
    this.setBridgeRouter(value);
  }

  // =========== reconcile ==========

  // ============ reconcile fail cases

  // fails if not sent by connext
  function test_NomadFacet__reconcile_failIfNotConnext() public {
    utils_setupAsset(true, false);
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs();
    (uint32 canonicalDomain, bytes32 canonicalId) = s.tokenRegistry.getTokenId(_local);

    vm.expectRevert(NomadFacet.NomadFacet__reconcile_notConnext.selector);

    vm.prank(_bridge);
    this.onReceive(
      _originDomain,
      TypeCasts.addressToBytes32(address(1232)),
      canonicalDomain,
      canonicalId,
      _local,
      args.transactingAmount,
      abi.encode(TransferIdInformation(args.params, s.nonce, _originSender))
    );
  }

  // fails if already reconciled (s.reconciledTransfers[transferId] = true)
  function test_NomadFacet__reconcile_failIfAlreadyReconciled() public {
    utils_setupAsset(true, false);
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs();
    (uint32 canonicalDomain, bytes32 canonicalId) = s.tokenRegistry.getTokenId(_local);
    s.reconciledTransfers[transferId] = true;

    vm.expectRevert(NomadFacet.NomadFacet__reconcile_alreadyReconciled.selector);

    vm.prank(_bridge);
    this.onReceive(
      _originDomain,
      _originConnext,
      canonicalDomain,
      canonicalId,
      _local,
      args.transactingAmount,
      abi.encode(TransferIdInformation(args.params, s.nonce, _originSender))
    );
  }

  // fails if portal record, but used in slow mode
  function test_NomadFacet__reconcile_failsIfPortalAndNoRouter() public {
    utils_setupAsset(true, false);
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs();
    (uint32 canonicalDomain, bytes32 canonicalId) = s.tokenRegistry.getTokenId(_local);
    delete s.routedTransfers[transferId];

    // set portal fee debt
    s.portalDebt[transferId] = 15;
    s.portalFeeDebt[transferId] = 10;

    vm.expectRevert(NomadFacet.NomadFacet__reconcile_noPortalRouter.selector);

    vm.prank(_bridge);
    this.onReceive(
      _originDomain,
      _originConnext,
      canonicalDomain,
      canonicalId,
      _local,
      args.transactingAmount,
      abi.encode(TransferIdInformation(args.params, s.nonce, _originSender))
    );
  }

  // ============ reconcile success cases
  // works with local representational tokens (remote origin, so they will be minted)
  function test_NomadFacet__reconcile_worksWithLocal() public {
    utils_setupAsset(true, false);
    helpers_reconcileAndAssert();
  }

  function test_NomadFacet__reconcile_worksWithCanonical() public {
    utils_setupAsset(true, true);
    helpers_reconcileAndAssert();
  }

  // funds contract when pre-execute (slow liquidity route)
  function test_NomadFacet__reconcile_worksPreExecute() public {
    utils_setupAsset(true, false);
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs();
    delete s.routedTransfers[transferId];

    helpers_reconcileAndAssert(transferId, args, _originConnext, bytes4(""));
  }

  // funds router when post-execute (fast liquidity route)
  function test_NomadFacet__reconcile_fastLiquiditySingleRouterWorks() public {
    utils_setupAsset(true, false);
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs();
    s.routedTransfers[transferId] = [address(42)];
    helpers_reconcileAndAssert(transferId, args, _originConnext, bytes4(""));
  }

  // funds routers when post-execute multipath (fast liquidity route)
  function test_NomadFacet__reconcile_fastLiquidityMultipathWorks() public {
    utils_setupAsset(true, false);
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs();
    s.routedTransfers[transferId] = [address(42), address(43), address(44), address(45)];
    helpers_reconcileAndAssert(transferId, args, _originConnext, bytes4(""));
  }
}
