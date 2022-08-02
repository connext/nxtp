// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {Deployer} from "../../../utils/Deployer.sol";
import {IConnextHandler} from "../../../../contracts/core/connext/interfaces/IConnextHandler.sol";
import {IStableSwap} from "../../../../contracts/core/connext/interfaces/IStableSwap.sol";
import {IAavePool} from "../../../../contracts/core/connext/interfaces/IAavePool.sol";
import {IDiamondCut} from "../../../../contracts/core/connext/interfaces/IDiamondCut.sol";

import {BaseConnextFacet} from "../../../../contracts/core/connext/facets/BaseConnextFacet.sol";
import {LibDiamond} from "../../../../contracts/core/connext/libraries/LibDiamond.sol";
import {CallParams} from "../../../../contracts/core/connext/libraries/LibConnextStorage.sol";
import {PortalFacet} from "../../../../contracts/core/connext/facets/PortalFacet.sol";
import {TestAavePool} from "../../../../contracts/test/TestAavePool.sol";
import {TestERC20} from "../../../../contracts/test/TestERC20.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../../utils/Mock.sol";
import "../../../utils/FacetHelper.sol";

import "forge-std/console.sol";

contract PortalFacetTest is PortalFacet, FacetHelper {
  // ============ Storage ============
  uint32 domain = _originDomain;
  address bridgeRouter = address(1);
  address relayerFeeRouter = address(4);
  address xAppConnectionManager = address(5);
  address router = address(1111);
  address aavePool;

  bytes32 transferId;
  CallParams params;
  address originSender = address(1232123);
  uint256 bridgedAmt = 1 ether;
  uint256 nonce = 89;

  // ============ Test set up ============

  function setUp() public {
    utils_deployAssetContracts();
    utils_setFees();

    // we are on the origin domain where local == canonical
    utils_setupAsset(true, true);

    // set the owner to this contract
    LibDiamond.setContractOwner(address(this));

    // setup aave pool
    aavePool = address(new MockPool(false));
    // set pool
    s.aavePool = aavePool;

    params = CallParams(
      address(11), // to
      bytes(""), // callData
      _originDomain, // origin domain
      _destinationDomain, // destination domain
      address(222222222), // agent
      address(6666666), // recovery address
      false, // forceSlow
      false, // receiveLocal
      address(0), // callback
      0, // callbackFee
      0, // relayer fee
      1 ether // destinationMinOut
    );

    // set default transfer id
    transferId = utils_calculateTransferId();
  }

  // ============ Test utils ============

  function utils_calculateTransferId() public returns (bytes32) {
    console.log("canonical id");
    console.logBytes32(_canonicalId);
    return keccak256(abi.encode(nonce, params, originSender, _canonicalId, _canonicalDomain, bridgedAmt));
  }

  function utils_repayPortal(
    CallParams memory p,
    uint256 _backingAmount,
    uint256 _feeAmount,
    uint256 _maxIn
  ) public {
    this.repayAavePortal(p, _local, originSender, bridgedAmt, nonce, _backingAmount, _feeAmount, _maxIn);
  }

  function utils_repayPortalFor(
    CallParams memory p,
    address _adopted,
    uint256 _backingAmount,
    uint256 _feeAmount
  ) public {
    this.repayAavePortalFor(p, _adopted, originSender, bridgedAmt, nonce, _backingAmount, _feeAmount);
  }

  // ============ setAavePool ============

  // should work
  function test_PortalFacet__setAavePool_works() public {
    s.aavePool = address(0);
    assertEq(this.aavePool(), address(0));

    this.setAavePool(aavePool);

    assertEq(this.aavePool(), aavePool);
  }

  // should fail if not owner
  function test_PortalFacet__setAavePool_failsIfNotOwner() public {
    vm.prank(address(10));
    vm.expectRevert(abi.encodeWithSelector(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector));
    this.setAavePool(aavePool);
  }

  // ============ setAavePortalFee ============

  // should work
  function test_PortalFacet__setAavePortalFee_works() public {
    uint256 fee = 125;
    assertEq(this.aavePortalFee(), _portalFeeNumerator);

    this.setAavePortalFee(fee);

    assertEq(this.aavePortalFee(), fee);
  }

  // should fail if not owner
  function test_PortalFacet__setAavePortalFee_failsIfNotOwner() public {
    uint256 fee = 5;

    vm.prank(address(10));
    vm.expectRevert(abi.encodeWithSelector(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector));

    this.setAavePortalFee(fee);
  }

  // fail if the fee is invalid (greater than denominator)
  function test_PortalFacet__setAavePortalFee_failsIfInvalidFee() public {
    uint256 fee = _liquidityFeeDenominator + 1;

    vm.expectRevert(abi.encodeWithSelector(PortalFacet.PortalFacet__setAavePortalFee_invalidFee.selector));
    this.setAavePortalFee(fee);
  }

  // ============ repayAavePortal ============

  // should work when local asset is the adopted asset
  function test_PortalFacet__repayAavePortal_works() public {
    // set approval context
    s.routerPermissionInfo.approvedForPortalRouters[router] = true;

    // set debt amount
    uint256 backing = 1111;
    uint256 fee = 111;

    // set liquidity
    uint256 init = 10 ether;
    s.routerBalances[router][_local] = init;
    s.portalDebt[transferId] = backing;
    s.portalFeeDebt[transferId] = fee;
    assertTrue(IERC20(_local).balanceOf(address(this)) > init);

    // set mock for backing
    vm.mockCall(s.aavePool, abi.encodeWithSelector(IAavePool.backUnbacked.selector), abi.encode(true));

    // make call
    vm.expectCall(_local, abi.encodeWithSelector(IERC20.approve.selector, aavePool, backing + fee));
    vm.expectCall(aavePool, abi.encodeWithSelector(IAavePool.backUnbacked.selector, _local, backing, fee));
    vm.expectEmit(true, true, true, true);
    emit AavePortalRepayment(transferId, _local, backing, fee, router);
    vm.prank(router);
    utils_repayPortal(params, backing, fee, backing);

    // assert balance decrement
    assertEq(s.routerBalances[router][_local], init - backing - fee);
  }

  // fails if not enough balance
  function test_PortalFacet__repayAavePortal_failsIfInsufficientAmount() public {
    // set approval context
    s.routerPermissionInfo.approvedForPortalRouters[router] = true;

    // set liquidity
    assertEq(s.routerBalances[router][_local], 0);

    // set debt amount
    uint256 backing = 1111;
    uint256 fee = 111;

    // call coming from router
    vm.prank(router);
    vm.expectRevert(abi.encodeWithSelector(PortalFacet.PortalFacet__repayAavePortal_insufficientFunds.selector));
    utils_repayPortal(params, backing, fee, backing);
  }

  // fails if swap failed
  function test_PortalFacet__repayAavePortal_failsIfSwapFailed() public {
    // we are on the destination domain where local != canonical
    utils_setupAsset(false, false);

    // set approval context
    s.routerPermissionInfo.approvedForPortalRouters[router] = true;

    // set debt amount
    uint256 backing = 1111;
    uint256 fee = 111;
    uint256 maxIn = 1200;

    // set liquidity
    s.routerBalances[router][_local] = maxIn + 1;

    // set mock + storage (using external pool)
    // calculateSwapOutFromAddress returns maxIn + 1 and it causes swap Failed!
    vm.mockCall(
      _stableSwap,
      abi.encodeWithSelector(IStableSwap.calculateSwapOutFromAddress.selector),
      abi.encode(maxIn + 1)
    );

    // call coming from router
    vm.prank(router);
    vm.expectRevert(abi.encodeWithSelector(PortalFacet.PortalFacet__repayAavePortal_swapFailed.selector));
    utils_repayPortal(params, backing, fee, maxIn);
  }

  function test_PortalFacet__repayAavePortal_failsIfRepalyTooMuch() public {
    // we are on the destination domain where local != canonical
    utils_setupAsset(false, false);

    // set approval context
    s.routerPermissionInfo.approvedForPortalRouters[router] = true;

    // set debt amount
    uint256 backing = 1111;
    uint256 fee = 111;
    uint256 maxIn = 1200;
    uint256 totalAmount = backing + fee;
    uint256 amountIn = maxIn - 1;
    uint256 init = maxIn + 1;

    s.routerBalances[router][_local] = init;
    s.portalDebt[transferId] = backing - 1;
    s.portalFeeDebt[transferId] = fee - 1;

    // set liquidity
    s.routerBalances[router][_local] = maxIn + 1;

    // set mock + storage (using external pool)
    vm.mockCall(
      _stableSwap,
      abi.encodeWithSelector(IStableSwap.calculateSwapOutFromAddress.selector),
      abi.encode(amountIn)
    );
    vm.mockCall(_stableSwap, abi.encodeWithSelector(IStableSwap.swapExactOut.selector), abi.encode(amountIn));

    // set mock for backing
    vm.mockCall(s.aavePool, abi.encodeWithSelector(IAavePool.backUnbacked.selector), abi.encode(true));

    vm.expectRevert(stdError.arithmeticError);
    vm.prank(router);
    utils_repayPortal(params, backing, fee, maxIn);

    // assert balance decrement
    assertEq(s.routerBalances[router][_local], init);
  }

  function test_PortalFacet__repayAavePortal_shouldWorkUsingSwap() public {
    // we are on the destination domain where local != canonical
    utils_setupAsset(false, false);
    transferId = utils_calculateTransferId();

    // set approval context
    s.routerPermissionInfo.approvedForPortalRouters[router] = true;

    // set debt amount
    uint256 backing = 1111;
    uint256 fee = 111;
    uint256 maxIn = 1200;
    uint256 totalAmount = backing + fee;
    uint256 amountIn = maxIn - 1;
    uint256 init = maxIn + 1;

    s.routerBalances[router][_local] = init;
    s.portalDebt[transferId] = backing;
    s.portalFeeDebt[transferId] = fee;

    // set liquidity
    s.routerBalances[router][_local] = maxIn + 1;

    // set mock + storage (using external pool)
    vm.mockCall(
      _stableSwap,
      abi.encodeWithSelector(IStableSwap.calculateSwapOutFromAddress.selector),
      abi.encode(amountIn)
    );
    vm.mockCall(_stableSwap, abi.encodeWithSelector(IStableSwap.swapExactOut.selector), abi.encode(amountIn));

    // set mock for backing
    vm.mockCall(s.aavePool, abi.encodeWithSelector(IAavePool.backUnbacked.selector), abi.encode(true));

    // make call
    vm.expectCall(_adopted, abi.encodeWithSelector(IERC20.approve.selector, aavePool, backing + fee));
    vm.expectCall(aavePool, abi.encodeWithSelector(IAavePool.backUnbacked.selector, _adopted, backing, fee));
    vm.expectEmit(true, true, true, true);
    emit AavePortalRepayment(transferId, _adopted, backing, fee, router);
    vm.prank(router);
    utils_repayPortal(params, backing, fee, maxIn);

    // assert balance decrement
    assertEq(s.routerBalances[router][_local], init - amountIn);
  }

  // ============ repayAavePortalFor ============

  // fails if not supported asset
  function test_PortalFacet__repayAavePortalFor_failsIfNotSupportedAsset() public {
    // set debt amount
    uint256 backing = 1111;
    uint256 fee = 111;

    // we are on the destination domain where local != canonical
    utils_setupAsset(false, false);

    address adopted = address(1);
    assertTrue(adopted != _adopted);

    vm.expectRevert(abi.encodeWithSelector(PortalFacet.PortalFacet__repayAavePortalFor_notSupportedAsset.selector));
    utils_repayPortalFor(params, adopted, backing, fee);
  }

  // fails if zero amount
  function test_PortalFacet__repayAavePortalFor_failsIfZeroTotalAmount() public {
    // set debt amount
    uint256 backing = 0;
    uint256 fee = 0;

    // we are on the destination domain where local != canonical
    utils_setupAsset(false, false);

    vm.expectRevert(abi.encodeWithSelector(PortalFacet.PortalFacet__repayAavePortalFor_zeroAmount.selector));
    utils_repayPortalFor(params, _adopted, backing, fee);
  }

  // should work
  function test_PortalFacet__repayAavePortalFor_shouldWork() public {
    // we are on the destination domain where local != canonical
    utils_setupAsset(false, false);
    transferId = utils_calculateTransferId();

    // set debt amount
    uint256 backing = 1111;
    uint256 fee = 111;
    uint256 total = backing + fee;

    s.portalDebt[transferId] = backing;
    s.portalFeeDebt[transferId] = fee;

    // mint initial balance to sender and approve
    address sender = address(111);
    TestERC20(_adopted).mint(sender, total);
    vm.prank(sender);
    TestERC20(_adopted).approve(address(this), total);

    // make call
    vm.expectCall(_adopted, abi.encodeWithSelector(IERC20.approve.selector, aavePool, total));
    vm.expectCall(aavePool, abi.encodeWithSelector(IAavePool.backUnbacked.selector, _adopted, backing, fee));
    vm.expectEmit(true, true, true, true);
    emit AavePortalRepayment(transferId, _adopted, backing, fee, sender);
    vm.prank(sender);
    utils_repayPortalFor(params, _adopted, backing, fee);
    console.log("repaid");

    // assert balance decrement
    assertEq(IERC20(_adopted).balanceOf(sender), 0);
    assertEq(s.portalDebt[transferId], 0);
    assertEq(s.portalFeeDebt[transferId], 0);
  }
}
