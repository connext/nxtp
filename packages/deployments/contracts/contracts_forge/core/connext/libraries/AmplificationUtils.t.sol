// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "../../../../contracts/core/connext/libraries/SwapUtils.sol";
import "../../../utils/FacetHelper.sol";

contract AmplificationUtilsTest is FacetHelper {
  // ============ Storage ============
  SwapUtils.Swap swap;

  // ============ Events ============
  event RampA(uint256 oldA, uint256 newA, uint256 initialTime, uint256 futureTime);
  event StopRampA(uint256 currentA, uint256 time);

  // ============ Setup ============
  function setUp() public {
    IERC20[] memory _pooledTokens = new IERC20[](2);
    _pooledTokens[0] = IERC20(address(11));
    _pooledTokens[1] = IERC20(address(22));

    uint256[] memory _tokenPrecisionMultipliers = new uint256[](2);
    _tokenPrecisionMultipliers[0] = 1;
    _tokenPrecisionMultipliers[1] = 1;

    uint256[] memory _balances = new uint256[](2);
    _balances[0] = 100;
    _balances[1] = 100;

    swap = SwapUtils.Swap({
      key: _canonicalId,
      initialA: 1000,
      futureA: 10000,
      initialATime: 100,
      futureATime: 1000,
      swapFee: 0,
      adminFee: 0,
      lpToken: LPToken(address(100)),
      pooledTokens: _pooledTokens,
      tokenPrecisionMultipliers: _tokenPrecisionMultipliers,
      balances: _balances,
      adminFees: new uint256[](2)
    });
  }

  // ============ utils ============

  // ============ getA ============
  function test_AmplificationUtils__getA_works() public {
    vm.warp(500);
    // a0 + (a1 - a0) * (block.timestamp - t0) / (t1 - t0) ====>
    // a0: 1000, a1: 10000, block.timestamp: 500, t0: 100, t1: 1000;
    assertEq(AmplificationUtils.getA(swap), 50);
  }

  // ============ getAPrecise ============
  function test_AmplificationUtils__getAPrecise_works() public {
    vm.warp(500);
    // a0 + (a1 - a0) * (block.timestamp - t0) / (t1 - t0) ====>
    // a0: 1000, a1: 10000, block.timestamp: 500, t0: 100, t1: 1000;
    assertEq(AmplificationUtils.getAPrecise(swap), 5000);
  }

  // ============ _getAPrecise ============
  function test_AmplificationUtils___getAPrecise_works() public {
    vm.warp(500);
    swap.initialA = 10000;
    swap.futureA = 1000;
    // a0 - (a0 - a1) * (block.timestamp - t0) / (t1 - t0) ====>
    // a0: 1000, a1: 10000, block.timestamp: 500, t0: 100, t1: 1000;
    assertEq(AmplificationUtils._getAPrecise(swap), 6000);
    swap.initialA = 1000;
    swap.futureA = 10000;
    vm.warp(500);
    // a0 + (a1 - a0) * (block.timestamp - t0) / (t1 - t0) ====>
    // a0: 1000, a1: 10000, block.timestamp: 500, t0: 100, t1: 1000;
    assertEq(AmplificationUtils._getAPrecise(swap), 5000);
    vm.warp(1500);
    // should be equal to `a1` because block.timestamp > t1:[1000]
    assertEq(AmplificationUtils._getAPrecise(swap), 10000);
  }

  // ============ rampA ============
  function test_AmplificationUtils__rampA_revertIfWaitTimeNotEnough() public {
    vm.expectRevert(bytes("Wait 1 day before starting ramp"));
    vm.warp(500);
    AmplificationUtils.rampA(swap, 10000, 10000);
  }

  function test_AmplificationUtils__rampA_revertIfInsufficientRampTime() public {
    vm.expectRevert(bytes("Insufficient ramp time"));
    vm.warp(86600);
    AmplificationUtils.rampA(swap, 10000, 10000);
  }

  function test_AmplificationUtils__rampA_revertIfInvalidFutureTime() public {
    vm.expectRevert(bytes("futureA_ must be > 0 and < MAX_A"));
    vm.warp(86600);
    AmplificationUtils.rampA(swap, 10**7, 1382400);
  }

  function test_AmplificationUtils__rampA_revertIfFuturePriceTooSmall() public {
    vm.expectRevert(bytes("futureA_ is too small"));
    vm.warp(86600);
    AmplificationUtils.rampA(swap, 10, 1382400);
  }

  function test_AmplificationUtils__rampA_revertIfFuturePriceTooLarge() public {
    vm.expectRevert(bytes("futureA_ is too large"));
    vm.warp(86600);
    AmplificationUtils.rampA(swap, 10**5, 1382400);
  }

  function test_AmplificationUtils__rampA_works() public {
    vm.warp(86600);
    vm.expectEmit(true, true, true, true);
    emit RampA(10000, 10000, 86600, 1382400);
    AmplificationUtils.rampA(swap, 100, 1382400);
  }

  // ============ stopRampA ============
  function test_AmplificationUtils__stopRampA_revertIfRampStopped() public {
    swap.futureATime = 86400;
    vm.expectRevert(bytes("Ramp is already stopped"));
    vm.warp(86600);
    AmplificationUtils.stopRampA(swap);
  }

  function test_AmplificationUtils__stopRampA_works() public {
    swap.futureATime = 1000;
    vm.warp(500);
    vm.expectEmit(true, true, true, true);
    emit StopRampA(5000, 500);
    AmplificationUtils.stopRampA(swap);
  }
}
