// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LibDiamond} from "../../../../contracts/core/connext/libraries/LibDiamond.sol";
import {SwapUtils} from "../../../../contracts/core/connext/libraries/SwapUtils.sol";
import {AmplificationUtils} from "../../../../contracts/core/connext/libraries/AmplificationUtils.sol";
import {LPToken} from "../../../../contracts/core/connext/helpers/LPToken.sol";

import {BaseConnextFacet} from "../../../../contracts/core/connext/facets/BaseConnextFacet.sol";
import {StableSwapFacet} from "../../../../contracts/core/connext/facets/StableSwapFacet.sol";
import {SwapAdminFacet} from "../../../../contracts/core/connext/facets/SwapAdminFacet.sol";

import "../../../utils/FacetHelper.sol";

contract SwapAdminFacetTest is SwapAdminFacet, StableSwapFacet, FacetHelper {
  // ============ Libraries ============
  using SwapUtils for SwapUtils.Swap;
  using AmplificationUtils for SwapUtils.Swap;

  // ============ Storage ============

  // owner
  address _owner = address(1234);
  address _user1 = address(1);
  address _user2 = address(2);
  LPToken _lpTokenTarget;

  // TODO: Should initialize StableSwapFacet separately instead of inheriting here.
  // address _stableSwapFacet;

  // Test Values
  uint256 INITIAL_A_VALUE = 50;
  uint256 SWAP_FEE = 1e7;
  string LP_TOKEN_NAME = "Test LP Token Name";
  string LP_TOKEN_SYMBOL = "TESTLP";
  uint256 blockTimestamp = 2 days;

  // ============ Test set up ============
  function setUp() public {
    utils_deployAssetContracts();

    // we are on the origin domain where local == canonical
    utils_setupAsset(false, true);

    // set the owner to this contract
    setOwner(_owner);

    // _stableSwapFacet = address(new StableSwapFacet());

    utils_initializeSwap();
    utils_addLiquidity(1 ether, 1 ether);
  }

  // ============ Utils ==============
  function setOwner(address owner) internal {
    // set owner
    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    ds.contractOwner = owner;
  }

  function utils_initializeSwap() public {
    IERC20[] memory _pooledTokens = new IERC20[](2);
    _pooledTokens[0] = IERC20(_local);
    _pooledTokens[1] = IERC20(_adopted);

    // Mint Token0, Token1 to Owner, User1, User2
    TestERC20(_local).mint(_owner, 100 ether);
    TestERC20(_adopted).mint(_owner, 100 ether);

    TestERC20(_local).mint(_user1, 100 ether);
    TestERC20(_adopted).mint(_user1, 100 ether);

    TestERC20(_local).mint(_user2, 100 ether);
    TestERC20(_adopted).mint(_user2, 100 ether);

    // Approve Token0, Token1 from User1, User2
    vm.startPrank(_user1);
    TestERC20(_local).approve(address(this), 100 ether);
    TestERC20(_adopted).approve(address(this), 100 ether);
    vm.stopPrank();

    vm.startPrank(_user2);
    TestERC20(_local).approve(address(this), 100 ether);
    TestERC20(_adopted).approve(address(this), 100 ether);
    vm.stopPrank();

    uint8[] memory _decimals = new uint8[](2);
    _decimals[0] = 18;
    _decimals[1] = 18;

    uint256 _a = INITIAL_A_VALUE;
    uint256 _adminFee = 0;
    uint256 _fee = SWAP_FEE;

    _lpTokenTarget = new LPToken();
    _lpTokenTarget.initialize(LP_TOKEN_NAME, LP_TOKEN_SYMBOL);

    vm.prank(_owner);
    this.initializeSwap(
      _canonicalId,
      _pooledTokens,
      _decimals,
      LP_TOKEN_NAME,
      LP_TOKEN_SYMBOL,
      _a,
      _fee,
      _adminFee,
      address(_lpTokenTarget)
    );

    assertEq(this.getSwapVirtualPrice(_canonicalId), 0);
  }

  function utils_addLiquidity(uint256 amount1, uint256 amount2) public {
    vm.warp(blockTimestamp);

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = amount1;
    amounts[1] = amount2;

    vm.startPrank(_owner);
    IERC20(s.swapStorages[_canonicalId].pooledTokens[0]).approve(address(this), 100 ether);
    IERC20(s.swapStorages[_canonicalId].pooledTokens[1]).approve(address(this), 100 ether);

    this.addSwapLiquidity(_canonicalId, amounts, 0, blockTimestamp + 10);
    vm.stopPrank();
  }

  function utils_swapExact(
    uint256 amountIn,
    address assetIn,
    address assetOut,
    uint256 minAmountOut
  ) public returns (uint256) {
    vm.warp(blockTimestamp);
    return this.swapExact(_canonicalId, amountIn, assetIn, assetOut, minAmountOut, blockTimestamp + 10);
  }

  // =========== Admin Functions ============
  function test_SwapAdminFacet__initializeSwap_failIfNotOwner() public {
    IERC20[] memory _pooledTokens = new IERC20[](2);
    _pooledTokens[0] = IERC20(new TestERC20("Test Token", "TEST"));
    _pooledTokens[1] = IERC20(new TestERC20("Test Token", "TEST"));

    uint8[] memory _decimals = new uint8[](2);
    _decimals[0] = 18;
    _decimals[1] = 18;

    bytes32 canonicalId = bytes32(abi.encodePacked(address(_pooledTokens[0])));
    assertTrue(_owner != address(1));

    vm.prank(address(1));
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);

    this.initializeSwap(
      canonicalId,
      _pooledTokens,
      _decimals,
      LP_TOKEN_NAME,
      LP_TOKEN_SYMBOL,
      INITIAL_A_VALUE,
      SWAP_FEE,
      0,
      address(_lpTokenTarget)
    );
  }

  function test_SwapAdminFacet__initializeSwap_failIfDuplicatedTokens() public {
    IERC20[] memory _pooledTokens = new IERC20[](2);
    _pooledTokens[0] = IERC20(new TestERC20("Test Token", "TEST"));
    _pooledTokens[1] = _pooledTokens[0];

    uint8[] memory _decimals = new uint8[](2);
    _decimals[0] = 18;
    _decimals[1] = 18;

    bytes32 canonicalId = bytes32(abi.encodePacked(address(_pooledTokens[0])));

    vm.prank(_owner);
    vm.expectRevert(SwapAdminFacet.SwapAdminFacet__initializeSwap_duplicateTokens.selector);

    this.initializeSwap(
      canonicalId,
      _pooledTokens,
      _decimals,
      LP_TOKEN_NAME,
      LP_TOKEN_SYMBOL,
      INITIAL_A_VALUE,
      SWAP_FEE,
      0,
      address(_lpTokenTarget)
    );
  }

  function test_SwapAdminFacet__initializeSwap_failIfAlreadyInitialized() public {
    IERC20[] memory _pooledTokens = new IERC20[](2);
    _pooledTokens[0] = IERC20(new TestERC20("Test Token", "TEST"));
    _pooledTokens[1] = IERC20(new TestERC20("Test Token", "TEST"));

    uint8[] memory _decimals = new uint8[](2);
    _decimals[0] = 18;
    _decimals[1] = 18;

    vm.prank(_owner);
    vm.expectRevert(SwapAdminFacet.SwapAdminFacet__initializeSwap_alreadyInitialized.selector);

    this.initializeSwap(
      _canonicalId,
      _pooledTokens,
      _decimals,
      LP_TOKEN_NAME,
      LP_TOKEN_SYMBOL,
      INITIAL_A_VALUE,
      SWAP_FEE,
      0,
      address(_lpTokenTarget)
    );
  }

  function test_SwapAdminFacet__initializeSwap_failIfDecimalsMismatch() public {
    IERC20[] memory _pooledTokens = new IERC20[](2);
    _pooledTokens[0] = IERC20(new TestERC20("Test Token", "TEST"));
    _pooledTokens[1] = IERC20(new TestERC20("Test Token", "TEST"));

    uint8[] memory _decimals = new uint8[](1);
    _decimals[0] = 18;

    bytes32 canonicalId = bytes32(abi.encodePacked(address(_pooledTokens[0])));

    vm.prank(_owner);
    vm.expectRevert(SwapAdminFacet.SwapAdminFacet__initializeSwap_decimalsMismatch.selector);

    this.initializeSwap(
      canonicalId,
      _pooledTokens,
      _decimals,
      LP_TOKEN_NAME,
      LP_TOKEN_SYMBOL,
      INITIAL_A_VALUE,
      SWAP_FEE,
      0,
      address(_lpTokenTarget)
    );
  }

  function test_SwapAdminFacet__initializeSwap_failIfZeroTokenAddress() public {
    IERC20[] memory _pooledTokens = new IERC20[](2);
    _pooledTokens[0] = IERC20(new TestERC20("Test Token", "TEST"));
    _pooledTokens[1] = IERC20(address(0));

    uint8[] memory _decimals = new uint8[](2);
    _decimals[0] = 18;
    _decimals[1] = 18;

    bytes32 canonicalId = bytes32(abi.encodePacked(address(_pooledTokens[0])));

    vm.prank(_owner);
    vm.expectRevert(SwapAdminFacet.SwapAdminFacet__initializeSwap_zeroTokenAddress.selector);

    this.initializeSwap(
      canonicalId,
      _pooledTokens,
      _decimals,
      LP_TOKEN_NAME,
      LP_TOKEN_SYMBOL,
      INITIAL_A_VALUE,
      SWAP_FEE,
      0,
      address(_lpTokenTarget)
    );
  }

  function test_SwapAdminFacet__initializeSwap_failIfAExceedMax() public {
    IERC20[] memory _pooledTokens = new IERC20[](2);
    _pooledTokens[0] = IERC20(new TestERC20("Test Token", "TEST"));
    _pooledTokens[1] = IERC20(new TestERC20("Test Token", "TEST"));

    uint8[] memory _decimals = new uint8[](2);
    _decimals[0] = 18;
    _decimals[1] = 18;

    bytes32 canonicalId = bytes32(abi.encodePacked(address(_pooledTokens[0])));

    vm.prank(_owner);
    vm.expectRevert(SwapAdminFacet.SwapAdminFacet__initializeSwap_aExceedMax.selector);

    this.initializeSwap(
      canonicalId,
      _pooledTokens,
      _decimals,
      LP_TOKEN_NAME,
      LP_TOKEN_SYMBOL,
      AmplificationUtils.MAX_A,
      SWAP_FEE,
      0,
      address(_lpTokenTarget)
    );
  }

  function test_SwapAdminFacet__initializeSwap_failIfFeeExceedMax() public {
    IERC20[] memory _pooledTokens = new IERC20[](2);
    _pooledTokens[0] = IERC20(new TestERC20("Test Token", "TEST"));
    _pooledTokens[1] = IERC20(new TestERC20("Test Token", "TEST"));

    uint8[] memory _decimals = new uint8[](2);
    _decimals[0] = 18;
    _decimals[1] = 18;

    bytes32 canonicalId = bytes32(abi.encodePacked(address(_pooledTokens[0])));

    vm.prank(_owner);
    vm.expectRevert(SwapAdminFacet.SwapAdminFacet__initializeSwap_feeExceedMax.selector);

    this.initializeSwap(
      canonicalId,
      _pooledTokens,
      _decimals,
      LP_TOKEN_NAME,
      LP_TOKEN_SYMBOL,
      AmplificationUtils.MAX_A - 1,
      SwapUtils.MAX_SWAP_FEE,
      SwapUtils.MAX_ADMIN_FEE - 1,
      address(_lpTokenTarget)
    );
  }

  function test_SwapAdminFacet__initializeSwap_failIfAdminFeeExceedMax() public {
    IERC20[] memory _pooledTokens = new IERC20[](2);
    _pooledTokens[0] = IERC20(new TestERC20("Test Token", "TEST"));
    _pooledTokens[1] = IERC20(new TestERC20("Test Token", "TEST"));

    uint8[] memory _decimals = new uint8[](2);
    _decimals[0] = 18;
    _decimals[1] = 18;

    bytes32 canonicalId = bytes32(abi.encodePacked(address(_pooledTokens[0])));

    vm.prank(_owner);
    vm.expectRevert(SwapAdminFacet.SwapAdminFacet__initializeSwap_adminFeeExceedMax.selector);

    this.initializeSwap(
      canonicalId,
      _pooledTokens,
      _decimals,
      LP_TOKEN_NAME,
      LP_TOKEN_SYMBOL,
      AmplificationUtils.MAX_A - 1,
      SwapUtils.MAX_SWAP_FEE - 1,
      SwapUtils.MAX_ADMIN_FEE,
      address(_lpTokenTarget)
    );
  }

  function test_SwapAdminFacet__initializeSwap_shouldWork() public {
    IERC20[] memory _pooledTokens = new IERC20[](2);
    _pooledTokens[0] = IERC20(new TestERC20("Test Token", "TEST"));
    _pooledTokens[1] = IERC20(new TestERC20("Test Token", "TEST"));

    uint8[] memory _decimals = new uint8[](2);
    _decimals[0] = 18;
    _decimals[1] = 18;

    uint256 a = INITIAL_A_VALUE;
    uint256 adminFee = 0;
    uint256 fee = SWAP_FEE;

    address token;

    bytes32 canonicalId = bytes32(abi.encodePacked(address(_pooledTokens[0])));
    uint256[] memory precisionMultipliers = new uint256[](_pooledTokens.length);
    for (uint8 i = 0; i < _pooledTokens.length; i++) {
      precisionMultipliers[i] = 10**uint256(SwapUtils.POOL_PRECISION_DECIMALS - _decimals[i]);
      s.tokenIndexes[_canonicalId][address(_pooledTokens[i])] = i;
    }

    vm.expectEmit(true, true, true, true);
    emit SwapInitialized(
      canonicalId,
      SwapUtils.Swap({
        key: canonicalId,
        initialA: a * AmplificationUtils.A_PRECISION,
        futureA: a * AmplificationUtils.A_PRECISION,
        swapFee: fee,
        adminFee: adminFee,
        lpToken: LPToken(address(0x3A1148FE01e3c4721D93fe8A36c2b5C29109B6ae)),
        pooledTokens: _pooledTokens,
        tokenPrecisionMultipliers: precisionMultipliers,
        balances: new uint256[](_pooledTokens.length),
        adminFees: new uint256[](_pooledTokens.length),
        initialATime: 0,
        futureATime: 0
      }),
      _owner
    );

    vm.prank(_owner);
    this.initializeSwap(
      canonicalId,
      _pooledTokens,
      _decimals,
      LP_TOKEN_NAME,
      LP_TOKEN_SYMBOL,
      a,
      fee,
      adminFee,
      address(_lpTokenTarget)
    );

    assertEq(s.swapStorages[canonicalId].initialA, a * AmplificationUtils.A_PRECISION);
    assertEq(s.swapStorages[canonicalId].futureA, a * AmplificationUtils.A_PRECISION);
    assertEq(s.swapStorages[canonicalId].swapFee, fee);
    assertEq(s.swapStorages[canonicalId].adminFee, adminFee);
    assertEq(address(s.swapStorages[canonicalId].pooledTokens[0]), address(_pooledTokens[0]));
    assertEq(s.swapStorages[canonicalId].balances[0], 0);
  }

  // function test_SwapAdminFacet__withdrawSwapAdminFees
  function test_SwapAdminFacet__withdrawSwapAdminFess_failIfNotOwner() public {
    assertTrue(_owner != address(1));

    vm.prank(address(1));
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);

    this.withdrawSwapAdminFees(_canonicalId);
  }

  function test_SwapAdminFacet__withdrawSwapAdminFess_successIfNoFees() public {
    vm.startPrank(_owner);
    this.setSwapAdminFee(_canonicalId, 1e8);

    uint256 beforeBalance0 = IERC20(_local).balanceOf(_owner);
    uint256 beforeBalance1 = IERC20(_adopted).balanceOf(_owner);

    this.withdrawSwapAdminFees(_canonicalId);

    assertEq(IERC20(_local).balanceOf(_owner), beforeBalance0);
    assertEq(IERC20(_adopted).balanceOf(_owner), beforeBalance1);

    vm.stopPrank();
  }

  function test_SwapAdminFacet__withdrawSwapAdminFess_shouldWorkWithExpectedAmount() public {
    vm.startPrank(_owner);
    this.setSwapAdminFee(_canonicalId, 1e8);
    utils_swapExact(1e17, _local, _adopted, 0);
    utils_swapExact(1e17, _adopted, _local, 0);

    assertEq(this.getSwapAdminBalance(_canonicalId, 0), 1001973776101);
    assertEq(this.getSwapAdminBalance(_canonicalId, 1), 998024139765);

    uint256 beforeBalance0 = IERC20(_local).balanceOf(_owner);
    uint256 beforeBalance1 = IERC20(_adopted).balanceOf(_owner);

    vm.expectEmit(true, true, true, true);
    emit AdminFeesWithdrawn(_canonicalId, _owner);

    this.withdrawSwapAdminFees(_canonicalId);

    assertEq(IERC20(_local).balanceOf(_owner), beforeBalance0 + 1001973776101);
    assertEq(IERC20(_adopted).balanceOf(_owner), beforeBalance1 + 998024139765);
    vm.stopPrank();
  }

  // function test_SwapAdminFacet__setSwapAdminFee
  function test_SwapAdminFacet__setSwapAdminFee_failIfNotOwner() public {
    assertTrue(_owner != address(1));

    vm.prank(address(1));
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);

    this.setSwapAdminFee(_canonicalId, 1e8);
  }

  function test_SwapAdminFacet__setSwapAdminFee_failIfHigherThanLimit() public {
    vm.startPrank(_owner);
    this.setSwapAdminFee(_canonicalId, SwapUtils.MAX_ADMIN_FEE);
    assertEq(this.getSwapStorage(_canonicalId).adminFee, SwapUtils.MAX_ADMIN_FEE);

    vm.expectRevert("too high");
    this.setSwapAdminFee(_canonicalId, SwapUtils.MAX_ADMIN_FEE + 1);
    vm.stopPrank();
  }

  function test_SwapAdminFacet__setSwapAdminFee_shouldWork() public {
    vm.startPrank(_owner);
    uint256 adminFee = SwapUtils.MAX_ADMIN_FEE;
    vm.expectEmit(true, true, true, true);
    emit AdminFeesSet(_canonicalId, adminFee, _owner);
    this.setSwapAdminFee(_canonicalId, adminFee);
    assertEq(this.getSwapStorage(_canonicalId).adminFee, adminFee);
    vm.stopPrank();
  }

  // function test_SwapAdminFacet__setSwapFee
  function test_SwapAdminFacet__setSwapFee_failIfNotOwner() public {
    assertTrue(_owner != address(1));

    vm.prank(address(1));
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);

    this.setSwapFee(_canonicalId, 1e8);
  }

  function test_SwapAdminFacet__setSwapFee_failIfHigherThanLimit() public {
    vm.startPrank(_owner);
    this.setSwapFee(_canonicalId, SwapUtils.MAX_SWAP_FEE);
    assertEq(this.getSwapStorage(_canonicalId).swapFee, SwapUtils.MAX_SWAP_FEE);

    vm.expectRevert("too high");
    this.setSwapFee(_canonicalId, SwapUtils.MAX_SWAP_FEE + 1);
    vm.stopPrank();
  }

  function test_SwapAdminFacet__setSwapFee_shouldWork() public {
    vm.startPrank(_owner);
    uint256 swapFee = SwapUtils.MAX_SWAP_FEE;
    vm.expectEmit(true, true, true, true);
    emit SwapFeesSet(_canonicalId, swapFee, _owner);
    this.setSwapFee(_canonicalId, swapFee);
    assertEq(this.getSwapStorage(_canonicalId).swapFee, swapFee);
    vm.stopPrank();
  }

  // function test_SwapAdminFacet__rampA
  function test_SwapAdminFacet__rampA_failIfNotOwner() public {
    assertTrue(_owner != address(1));

    vm.prank(address(1));
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);

    this.rampA(_canonicalId, 100, blockTimestamp + 14 days + 1);
  }

  function test_SwapAdminFacet__rampA_shouldWorkWithUpwards() public {
    // Create imbalanced pool to measure virtual price change
    // We expect virtual price to increase as A decreases
    utils_addLiquidity(1 ether, 0);

    vm.startPrank(_owner);

    uint256 endTimestamp = blockTimestamp + 14 days + 1;

    vm.expectEmit(true, true, true, true);
    emit RampAStarted(_canonicalId, 100, endTimestamp, _owner);
    this.rampA(_canonicalId, 100, endTimestamp);

    // +0 seconds since ramp A
    assertEq(this.getSwapA(_canonicalId), INITIAL_A_VALUE);
    assertEq(this.getSwapAPrecise(_canonicalId), INITIAL_A_VALUE * AmplificationUtils.A_PRECISION);
    assertEq(this.getSwapVirtualPrice(_canonicalId), 1000167146429976812);

    // set timestamp to +100000 seconds
    vm.warp(blockTimestamp + 100000);
    assertEq(this.getSwapA(_canonicalId), 54);
    assertEq(this.getSwapAPrecise(_canonicalId), 5413);
    assertEq(this.getSwapVirtualPrice(_canonicalId), 1000258443200230795);

    // set timestamp to the end of ramp period
    vm.warp(endTimestamp);
    assertEq(this.getSwapA(_canonicalId), 100);
    assertEq(this.getSwapAPrecise(_canonicalId), 10000);
    assertEq(this.getSwapVirtualPrice(_canonicalId), 1000771363829404568);

    vm.stopPrank();
  }

  function test_SwapAdminFacet__rampA_shouldWorkWithDownwards() public {
    // Create imbalanced pool to measure virtual price change
    // We expect virtual price to increase as A decreases
    utils_addLiquidity(1 ether, 0);

    vm.startPrank(_owner);

    uint256 endTimestamp = blockTimestamp + 14 days + 1;
    vm.expectEmit(true, true, true, true);
    emit RampAStarted(_canonicalId, 25, endTimestamp, _owner);
    this.rampA(_canonicalId, 25, endTimestamp);

    // +0 seconds since ramp A
    assertEq(this.getSwapA(_canonicalId), INITIAL_A_VALUE);
    assertEq(this.getSwapAPrecise(_canonicalId), INITIAL_A_VALUE * AmplificationUtils.A_PRECISION);
    assertEq(this.getSwapVirtualPrice(_canonicalId), 1000167146429976812);

    // set timestamp to +100000 seconds
    vm.warp(blockTimestamp + 100000);
    assertEq(this.getSwapA(_canonicalId), 47);
    assertEq(this.getSwapAPrecise(_canonicalId), 4794);
    assertEq(this.getSwapVirtualPrice(_canonicalId), 1000115870150391394);

    // set timestamp to the end of ramp period
    vm.warp(endTimestamp);
    assertEq(this.getSwapA(_canonicalId), 25);
    assertEq(this.getSwapAPrecise(_canonicalId), 2500);
    assertEq(this.getSwapVirtualPrice(_canonicalId), 998999574522334973);

    vm.stopPrank();
  }

  // function test_SwapAdminFacet__stopRampA
  function test_SwapAdminFacet__stopRampA_failIfNotOwner() public {
    assertTrue(_owner != address(1));

    vm.prank(address(1));
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);

    this.stopRampA(_canonicalId);
  }

  function test_SwapAdminFacet__stopRampA_shouldWork() public {
    vm.startPrank(_owner);
    uint256 endTimestamp = blockTimestamp + 14 days + 1;
    this.rampA(_canonicalId, 100, endTimestamp);

    uint256 currentTimestmp = blockTimestamp + 100000;
    vm.warp(currentTimestmp);
    vm.expectEmit(true, true, true, true);
    emit RampAStopped(_canonicalId, _owner);
    this.stopRampA(_canonicalId);

    assertEq(this.getSwapStorage(_canonicalId).initialA, 5413);
    assertEq(this.getSwapStorage(_canonicalId).futureA, 5413);
    assertEq(this.getSwapStorage(_canonicalId).initialATime, currentTimestmp);
    assertEq(this.getSwapStorage(_canonicalId).futureATime, currentTimestmp);

    vm.stopPrank();
  }
}
