// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "../../../../contracts/core/connext/libraries/AssetLogic.sol";
import "../../../../contracts/core/connext/libraries/SwapUtils.sol";
import {IWeth} from "../../../../contracts/core/connext/interfaces/IWeth.sol";
import {BaseConnextFacet} from "../../../../contracts/core/connext/facets/BaseConnextFacet.sol";
import {LibConnextStorage, AppStorage, TokenId} from "../../../../contracts/core/connext/libraries/LibConnextStorage.sol";
import {ITokenRegistry} from "../../../../contracts/core/connext/interfaces/ITokenRegistry.sol";

import "../../../utils/FacetHelper.sol";
import "../../../utils/Mock.sol";


// Helper to call library with native value functions
contract LibCaller {
  constructor() {
    AppStorage storage s = LibConnextStorage.connextStorage();
  }

  function handleIncomingAsset(
    address _assetId,
    uint256 _assetAmount
  ) public payable {
    AssetLogic.handleIncomingAsset(_assetId, _assetAmount);
  }

  function deposit(IWeth wrapper) public payable {
    wrapper.deposit{ value: msg.value }();
  }

  function transferAssetToContract(address _assetId, uint256 _amount) public {
    AssetLogic.transferAssetToContract(_assetId, _amount);
  }
}

contract AssetLogicTest is BaseConnextFacet, FacetHelper {
  // ============ Storage ============
  LibCaller caller;

  // ============ Setup ============
  function setUp() public {
    // set defaults
    utils_setFees();
    utils_deployAssetContracts();
    // set up assets (including remote swap)
    utils_setupAsset(false, false);
    // // set stable swap
    // utils_setMockStableSwap();
    caller = new LibCaller();
  }

  // ============ utils ============

  function utils_setMockStableSwap() internal {
    IERC20[] memory _pooledTokens = new IERC20[](2);
    _pooledTokens[0] = IERC20(_adopted);
    _pooledTokens[1] = IERC20(address(22));
    uint256[] memory _tokenPrecisionMultipliers = new uint256[](2);
    _tokenPrecisionMultipliers[0] = 1;
    _tokenPrecisionMultipliers[1] = 1;
    uint256[] memory  _balances = new uint256[](2);
    _balances[0] = 100;
    _balances[1] = 100;
    SwapUtils.Swap memory swap = SwapUtils.Swap({
        initialA : 0,
        futureA : 0,
        initialATime: 0,
        futureATime: 0,
        // fee calculations
        swapFee : 0,
        adminFee : 0,
        lpToken: LPToken(address(100)),
        // contract references for all tokens being pooled
        pooledTokens: _pooledTokens,
        // multipliers for each pooled token's precision to get to POOL_PRECISION_DECIMALS
        // for example, TBTC has 18 decimals, so the multiplier should be 1. WBTC
        // has 8, so the multiplier should be 10 ** 18 / 10 ** 8 => 10 ** 10
        tokenPrecisionMultipliers: _tokenPrecisionMultipliers,
        // the pool balance of each token, in the token's precision
        // the contract's actual token balance might differ
        balances: _balances,
        adminFees:  new uint256[](2)
    });

    s.swapStorages[_canonicalKey] = swap;
    s.tokenIndexes[_canonicalKey][_adopted] = 0;
    
  }

  // transfers specified asset to contract
  function utils_handleIncomingAssetAndAssert(address assetId, uint256 amount, uint256 fee) public {
    // get initial balances
    uint256 initDestAssetBalance = IERC20(assetId).balanceOf(address(caller));
    uint256 initDestFeeBalance = address(caller).balance;

    uint256 initSrcAssetBalance = IERC20(assetId).balanceOf(address(this));
    uint256 initSrcFeeBalance = address(this).balance;

    // approve
    IERC20(assetId).approve(address(caller), amount);

    caller.handleIncomingAsset{ value: fee }(assetId, amount);

    // caller balance always goes up in token
    assertEq(IERC20(assetId).balanceOf(address(caller)), initDestAssetBalance + amount);
    // fees on caller
    assertEq(address(caller).balance, initDestFeeBalance + fee);
    assertEq(IERC20(assetId).balanceOf(address(this)), initSrcAssetBalance - amount);
    assertEq(address(this).balance, initSrcFeeBalance - fee);
  }

  // transfers specified asset from contract
  function utils_handleOutgoingAssetAndAssert(address assetId, address to, uint256 amount) public {
    TestERC20(assetId).mint(address(this), 10 ether);

    // set expects
    if (amount != 0) {
      // Should transfer funds to user
      vm.expectCall(assetId, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
    } // otherwise, no calls should be made

    // get initial balances
    uint256 initContract = IERC20(assetId).balanceOf(address(this));
    uint256 initTarget = IERC20(assetId).balanceOf(to);

    // call
    AssetLogic.handleOutgoingAsset(assetId, to, amount);

    // assert balance changes on contract + target
    uint256 finalTarget = IERC20(assetId).balanceOf(to);
    assertEq(IERC20(assetId).balanceOf(address(this)), initContract - amount);
    assertEq(finalTarget, initTarget + amount);
  }

  // Sets up env to swap from local -> adopted using external pools only
  function utils_swapFromLocalAndAssertViaExternal(address asset, uint256 amount, uint256 swapOut) internal {
    // set mock
    vm.mockCall(_stableSwap, abi.encodeWithSelector(IStableSwap.swapExact.selector), abi.encode(swapOut));

    bool willSwap = asset == _local && amount != 0;
    if (willSwap) {
      // expect pool approval
      vm.expectCall(_local, abi.encodeWithSelector(IERC20.approve.selector, _stableSwap, amount));
      // expect swap
      vm.expectCall(_stableSwap, abi.encodeWithSelector(IStableSwap.swapExact.selector, amount, _local, _adopted));
    }

    (uint32 domain, bytes32 canonicalId) = s.tokenRegistry.getTokenId(asset);
    bytes32 key = keccak256(abi.encode(canonicalId, domain));
    (uint256 received, address out) = AssetLogic.swapFromLocalAssetIfNeeded(key, asset, amount, _liquidityFeeDenominator);
    // assert return amount
    assertEq(received, willSwap ? swapOut : amount);
    // assert return asset
    assertEq(out, _adopted);
  }

  // Sets up env to swap from local -> adopted using external pools only
  function utils_swapToLocalAndAssertViaExternal(address asset, uint256 amount, uint256 swapOut) internal {
    // set mock
    vm.mockCall(_stableSwap, abi.encodeWithSelector(IStableSwap.swapExact.selector), abi.encode(swapOut));

    bool willSwap = asset == _adopted && amount != 0;
    if (willSwap) {
      // expect pool approval
      vm.expectCall(_adopted, abi.encodeWithSelector(IERC20.approve.selector, _stableSwap, amount));
      // expect swap
      vm.expectCall(_stableSwap, abi.encodeWithSelector(IStableSwap.swapExact.selector, amount, _adopted, _local));
    }

    (uint256 received, address out) = AssetLogic.swapToLocalAssetIfNeeded(TokenId(_canonicalDomain, _canonicalId), asset, amount, _liquidityFeeDenominator);
    // assert return amount
    assertEq(received, willSwap ? swapOut : amount);
    // assert return asset
    assertEq(out, _local);
  }

  // ============ stableSwapPoolExist ============
  function test_AssetLogic__stableSwapPoolExist_works() public {
    utils_setMockStableSwap();
    assertEq(AssetLogic.stableSwapPoolExist(_canonicalKey), true);
    assertEq(AssetLogic.stableSwapPoolExist(bytes32(abi.encodePacked(address(5)))), false);
  }

  // ============ getTokenIndexFromStableSwapPool ============
  function test_AssetLogic__getTokenIndexFromStableSwapPool_failsIfNotFound() public {
    utils_setMockStableSwap();
    address arbitrary = address(555555555555);
    vm.expectRevert(AssetLogic.AssetLogic__getTokenIndexFromStableSwapPool_notExist.selector);
    AssetLogic.getTokenIndexFromStableSwapPool(_canonicalKey, arbitrary);
  }

  function test_AssetLogic__getTokenIndexFromStableSwapPool_works() public {
    utils_setMockStableSwap();
    assertEq(AssetLogic.getTokenIndexFromStableSwapPool(_canonicalKey, _adopted), 0);
  }

  // ============ handleIncomingAsset ============
  function test_AssetLogic__handleIncomingAsset_worksWithToken() public {
    address assetId = _local;
    uint256 amount = 10;
    uint256 fee = 1;
    utils_handleIncomingAssetAndAssert(assetId, amount, fee);
  }

  // ============ transferAssetToContract ============
  function test_AssetLogic__transferAssetToContract_works() public {
    uint256 initSrc = IERC20(_local).balanceOf(address(this));
    uint256 initDest = IERC20(_local).balanceOf(address(caller));
    IERC20(_local).approve(address(caller), 100);
    caller.transferAssetToContract(_local, 100);
    assertEq(IERC20(_local).balanceOf(address(this)), initSrc - 100);
    assertEq(IERC20(_local).balanceOf(address(caller)), initDest + 100);
  }

  function test_AssetLogic__transferAssetToContract_failsWithFeeOnTransfer() public {
    FeeERC20 fee = new FeeERC20();
    vm.expectRevert(AssetLogic.AssetLogic__transferAssetToContract_feeOnTransferNotSupported.selector);
    caller.transferAssetToContract(address(fee), 100);
  }

  // ============ handleOutgoingAsset ============
  function test_AssetLogic__handleOutgoingAsset_failsIfNoAsset() public {
    // set constants
    address assetId = address(0);
    address to = address(12345);
    uint256 amount = 12345678;
    vm.expectRevert(AssetLogic.AssetLogic__handleOutgoingAsset_notNative.selector);
    AssetLogic.handleOutgoingAsset(assetId, to, amount);
  }

  function test_AssetLogic__handleOutgoingAsset_works() public {
    // set constants
    address assetId = _local;
    address to = address(12345);
    uint256 amount = 12345678;
    utils_handleOutgoingAssetAndAssert(assetId, to, amount);
  }

  function test_AssetLogic__handleOutgoingAsset_worksIfZero() public {
    // set constants
    address assetId = _local;
    address to = address(12345);
    uint256 amount = 0;
    utils_handleOutgoingAssetAndAssert(assetId, to, amount);
  }

  // ============ swapToLocalAssetIfNeeded ============

  // doesnt swap
  function test_AssetLogic__swapToLocalAssetIfNeeded_worksIfZero() public {
    utils_swapToLocalAndAssertViaExternal(_adopted, 0, 10000);
  }

  // does not swap if already local
  function test_AssetLogic__swapToLocalAssetIfNeeded_worksWithLocal() public {
    utils_swapToLocalAndAssertViaExternal(_local, 1 ether, 0.9 ether);
  }

  // works
  function test_AssetLogic__swapToLocalAssetIfNeeded_worksWithAdopted() public {
    utils_swapToLocalAndAssertViaExternal(_adopted, 1 ether, 0.9 ether);
  }

  // ============ swapFromLocalAssetIfNeeded ============

  // doesnt swap
  function test_AssetLogic__swapFromLocalAssetIfNeeded_worksIfZero() public {
    utils_swapFromLocalAndAssertViaExternal(_local, 0, 0.1 ether);
  }

  // does not swap if already adopted
  function test_AssetLogic__swapFromLocalAssetIfNeeded_worksWithAdopted() public {
    utils_swapFromLocalAndAssertViaExternal(_adopted, 1 ether, 0.9 ether);
  }

  // should work (swap local for adopted)
  function test_AssetLogic__swapFromLocalAssetIfNeeded_worksWithLocal() public {
    utils_swapFromLocalAndAssertViaExternal(_local, 1 ether, 0.9 ether);
  }
}
