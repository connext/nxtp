// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {XAppConnectionManager} from "../../../../contracts/nomad-core/contracts/XAppConnectionManager.sol";
import {IStableSwap} from "../../../../contracts/core/connext/interfaces/IStableSwap.sol";
import {ITokenRegistry} from "../../../../contracts/core/connext/interfaces/ITokenRegistry.sol";
import {IExecutor} from "../../../../contracts/core/connext/interfaces/IExecutor.sol";
import {Executor} from "../../../../contracts/core/connext/helpers/Executor.sol";
import {ConnextMessage} from "../../../../contracts/core/connext/libraries/ConnextMessage.sol";
import {LibCrossDomainProperty} from "../../../../contracts/core/connext/libraries/LibCrossDomainProperty.sol";
import {CallParams, ExecuteArgs, XCallArgs} from "../../../../contracts/core/connext/libraries/LibConnextStorage.sol";
import {LibDiamond} from "../../../../contracts/core/connext/libraries/LibDiamond.sol";
import {BridgeFacet} from "../../../../contracts/core/connext/facets/BridgeFacet.sol";
import {TestERC20} from "../../../../contracts/test/TestERC20.sol";

import {MockXAppConnectionManager, MockHome} from "../../../utils/Mock.sol";
import "../../../../lib/forge-std/src/console.sol";
import "./FacetHelper.sol";

contract MockXApp {
  bytes32 constant TEST_MESSAGE = bytes32("test message");

  event MockXAppEvent(address caller, address asset, bytes32 message, uint256 amount);

  modifier checkMockMessage(bytes32 message) {
    require(keccak256(abi.encode(message)) == keccak256(abi.encode(TEST_MESSAGE)), "Mock message invalid!");
    _;
  }

  // This method call will transfer asset to this contract and succeed.
  function fulfill(address asset, bytes32 message) external checkMockMessage(message) returns (bytes32) {
    IExecutor executor = IExecutor(address(msg.sender));

    emit MockXAppEvent(msg.sender, asset, message, executor.amount());

    IERC20(asset).transferFrom(address(executor), address(this), executor.amount());

    return (bytes32("good"));
  }

  // Read from originDomain/originSender properties and validate them based on arguments.
  function fulfillWithProperties(
    address asset,
    bytes32 message,
    uint256 expectedOriginDomain,
    address expectedOriginSender
  ) external checkMockMessage(message) returns (bytes32) {
    IExecutor executor = IExecutor(address(msg.sender));

    emit MockXAppEvent(msg.sender, asset, message, executor.amount());

    IERC20(asset).transferFrom(address(executor), address(this), executor.amount());

    require(expectedOriginDomain == executor.origin(), "Origin domain incorrect");
    require(expectedOriginSender == executor.originSender(), "Origin sender incorrect");

    return (bytes32("good"));
  }

  // This method call will always fail.
  function fail() external {
    require(false, "bad");
  }
}

contract BridgeFacetTest is BridgeFacet, FacetHelper {
  bytes32 constant TEST_MESSAGE = bytes32("test message");

  // ============ storage ============
  // diamond storage contract owner
  address _ds_owner = address(987654321);

  // local asset for this domain
  address _local;
  // executor contract
  address _executor;
  // mock xapp contract
  address _xapp;
  // mock xapp connection manager
  address _xapp_connection_manager;
  // mock home
  address _xapp_home;

  // default origin sender
  address _originSender = address(4);

  // destination remote handler id
  bytes32 _remote = bytes32("remote");

  // domains
  uint32 _originDomain = 1000;
  uint32 _destinationDomain = 2000;

  // canonical token details
  address _canonical = address(5);
  bytes32 _canonicalTokenId = bytes32(abi.encodePacked(_canonical));
  uint32 _canonicalDomain = _originDomain;

  // relayer fee
  uint256 _relayerFee = 0.1 ether;

  // default amount
  uint256 _amount = 1.1 ether;

  // default nonce on xcall
  uint256 _nonce = 1;

  // default recovery address
  address constant _recovery = address(12121212);

  // default CallParams
  CallParams _params =
    CallParams(
      address(11), // to
      bytes(""), // callData
      _originDomain, // origin domain
      _destinationDomain, // destination domain
      _recovery, // recovery address
      address(0), // callback
      0, // callbackFee
      false, // forceSlow
      false // receiveLocal
    );

  // ============ Test set up ============
  function setUp() public {
    // deploy any needed contracts
    utils_deployContracts();

    // set defaults
    setDefaults();

    vm.mockCall(
      _tokenRegistry,
      abi.encodeWithSelector(ITokenRegistry.getTokenId.selector),
      abi.encode(_canonicalDomain, _canonicalTokenId)
    );

    // setup asset context (use local == adopted)
    s.adoptedToCanonical[_local] = ConnextMessage.TokenId(_canonicalDomain, _canonicalTokenId);
    s.adoptedToLocalPools[_canonicalTokenId] = IStableSwap(address(0));
    s.canonicalToAdopted[_canonicalTokenId] = _local;

    // setup other context
    s.approvedRelayers[address(this)] = true;
    s.maxRoutersPerTransfer = 5;
    s._routerOwnershipRenounced = true;

    vm.prank(address(this));
    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    ds.contractOwner = _ds_owner;

    // NOTE: Currently, only domain check is with xcall.
    s.domain = _originDomain;
    s.remotes[_destinationDomain] = _remote;
  }

  // ============ Utils ============
  // Utils used in the following tests.

  // Used in set up for deploying any needed peripheral contracts.
  function utils_deployContracts() public {
    // Deploy the local token.
    _local = address(new TestERC20());
    // Deploy an executor.
    _executor = address(new Executor(address(this)));
    s.executor = IExecutor(_executor);
    // Deploy a mock xapp consumer.
    _xapp = address(new MockXApp());

    // Deploy a mock home.
    _xapp_home = address(new MockHome());
    // Deploy a mock xapp connection manager.
    _xapp_connection_manager = address(new MockXAppConnectionManager(MockHome(_xapp_home)));
    s.xAppConnectionManager = XAppConnectionManager(_xapp_connection_manager);
  }

  // Meant to mimic the corresponding `_getTransferId` method in the BridgeFacet contract.
  function utils_getTransferIdFromExecuteArgs(ExecuteArgs memory _args) public returns (bytes32) {
    return
      keccak256(
        abi.encode(_args.nonce, _args.params, _args.originSender, _canonicalTokenId, _canonicalDomain, _args.amount)
      );
  }

  // Meant to mimic the corresponding `_getTransferId` method in the BridgeFacet contract.
  function utils_getTransferIdFromXCallArgs(XCallArgs memory _args, ConnextMessage.TokenId memory _canonical)
    public
    returns (bytes32)
  {
    return keccak256(abi.encode(s.nonce, _args.params, msg.sender, _canonical.id, _canonical.domain, _args.amount));
  }

  // Makes some mock router signatures.
  function utils_makeRouterSignatures(
    bytes32 _transferId,
    address[] memory _routers,
    uint256[] memory _keys
  ) public returns (bytes[] memory) {
    uint256 pathLen = _routers.length;
    bytes[] memory signatures = new bytes[](pathLen);
    if (pathLen == 0) {
      return signatures;
    }
    bytes32 preImage = keccak256(abi.encode(_transferId, pathLen));
    bytes32 toSign = ECDSA.toEthSignedMessageHash(preImage);
    for (uint256 i; i < pathLen; i++) {
      (uint8 v, bytes32 r, bytes32 _s) = vm.sign(_keys[i], toSign);
      signatures[i] = abi.encodePacked(r, _s, v);
    }
    return signatures;
  }

  // Makes some mock execute arguments with given router/key pairs.
  function utils_makeExecuteArgs(address[] memory routers, uint256[] memory keys)
    public
    returns (bytes32, ExecuteArgs memory)
  {
    // get args
    bytes[] memory empty = new bytes[](0);
    ExecuteArgs memory args = ExecuteArgs(_params, _local, routers, empty, _relayerFee, _amount, _nonce, _originSender);
    // generate transfer id
    bytes32 _id = utils_getTransferIdFromExecuteArgs(args);
    // generate router signatures if applicable
    if (routers.length > 0) {
      args.routerSignatures = utils_makeRouterSignatures(_id, routers, keys);
    }
    return (_id, args);
  }

  // Make execute args, fill in a number of router/key pairs.
  // Specifically input 0 to make execute arguments with no routers/keys for slow liq simulation.
  function utils_makeExecuteArgs(uint256 num) public returns (bytes32, ExecuteArgs memory) {
    if (num == 0) {
      address[] memory routers;
      uint256[] memory keys;
      return utils_makeExecuteArgs(routers, keys);
    }
    address[] memory routers = new address[](num);
    uint256[] memory keys = new uint256[](num);
    for (uint256 i; i < num; i++) {
      routers[i] = vm.addr(777 + i);
      keys[i] = 777 + i;
    }
    return utils_makeExecuteArgs(routers, keys);
  }

  // Intended to mock the fast transfer amount calculation in the target contract.
  function utils_getFastTransferAmount(uint256 _amount) public returns (uint256) {
    // This is the method used internally to get the amount of tokens to transfer after liquidity
    // fees are taken.
    return (_amount * s.LIQUIDITY_FEE_NUMERATOR) / s.LIQUIDITY_FEE_DENOMINATOR;
  }

  function utils_makeXCallArgs() public returns (bytes32, XCallArgs memory) {
    // get args
    XCallArgs memory args = XCallArgs(
      _params,
      _local, // transactingAssetId : could be adopted, local, or wrapped.
      _amount,
      _relayerFee
    );
    // generate transfer id
    bytes32 _id = utils_getTransferIdFromXCallArgs(args, s.adoptedToCanonical[_local]);

    return (_id, args);
  }

  // ============== Helpers ==================
  // Helpers used for executing target methods with given params that assert expected base behavior.

  // Calls `xcall` with given args and handles standard assertions.
  function helpers_xcallAndAssert(
    bytes32 _id,
    XCallArgs memory _args,
    uint256 dealTokens,
    uint256 dealEth
  ) public {
    uint256 fees = _args.relayerFee + _args.params.callbackFee;

    TestERC20 localToken = TestERC20(_local);
    uint256 initialUserBalance = localToken.balanceOf(_originSender);

    uint256 initialContractBalance = localToken.balanceOf(address(this));

    // Mint the specified amount of tokens for the user.
    localToken.mint(_originSender, dealTokens);
    // Deal the user required eth.
    deal(_originSender, dealEth);

    // Approve the target contract to spend the specified amount of tokens.
    vm.prank(_originSender);
    localToken.approve(address(this), dealTokens);

    // IERC20 adoptedToken = IERC20(s.canonicalToAdopted[_canonicalTokenId]);
    // uint256 prevBalanceTo = adoptedToken.balanceOf(_originSender);

    vm.prank(_originSender);
    this.xcall{value: fees}(_args);
    // assertEq(localToken.balanceOf(_originSender), initialUserBalance - _args.amount);
    // assertEq(localToken.balanceOf(address(this)), initialContractBalance + _args.amount);
  }

  // Shortcut for the above fn.
  function helpers_xcallAndAssert(
    bytes32 _id,
    XCallArgs memory _args,
    uint256 dealTokens
  ) public {
    helpers_xcallAndAssert(_id, _args, dealTokens, 100 ether);
  }

  // Shortcut for the above fn. Uses the amount for the transfer.
  function helpers_xcallAndAssert(bytes32 _id, XCallArgs memory _args) public {
    helpers_xcallAndAssert(_id, _args, _args.amount, 100 ether);
  }

  // Calls `execute` on the target method with the given args and asserts expected behavior.
  function helpers_executeAndAssert(
    bytes32 _id,
    ExecuteArgs memory _args,
    bool toShouldReceive // Whether the `to` address should receive the tokens.
  ) public {
    // get pre-execute liquidity in local
    uint256 pathLen = _args.routers.length;
    uint256[] memory prevLiquidity = new uint256[](pathLen);
    for (uint256 i; i < pathLen; i++) {
      prevLiquidity[i] = s.routerBalances[_args.routers[i]][_local];
    }

    // get pre-execute balance here in local
    uint256 prevBalance = IERC20(_local).balanceOf(address(this));

    // get pre-execute to balance in adopted
    IERC20 token = IERC20(s.canonicalToAdopted[_canonicalTokenId]);
    uint256 prevBalanceTo = token.balanceOf(_params.to);

    // execute
    uint256 transferred = pathLen == 0 ? _args.amount : utils_getFastTransferAmount(_args.amount);
    vm.expectEmit(true, true, false, true);
    emit Executed(_id, _args.params.to, _args, _args.local, transferred, address(this));
    this.execute(_args);

    // check local balance
    if (pathLen > 0) {
      // should decrement router balance
      uint256 decrement = transferred / pathLen;
      for (uint256 i; i < pathLen; i++) {
        assertEq(s.routerBalances[_args.routers[i]][_args.local], prevLiquidity[i] - decrement);
      }
    } else {
      // should decrement balance of bridge
      assertEq(IERC20(_local).balanceOf(address(this)), prevBalance - _amount);
    }

    if (toShouldReceive) {
      // should increment balance of `to` in `adopted`
      assertEq(token.balanceOf(_params.to), prevBalanceTo + transferred);
    } else {
      // should NOT have incremented balance of `to` in `adopted`
      assertEq(token.balanceOf(_params.to), prevBalanceTo);
    }

    // should mark the transfer as executed
    assertEq(s.transferRelayer[_id], address(this));

    // should have assigned transfer as routed
    address[] memory savedRouters = s.routedTransfers[_id];
    for (uint256 i; i < savedRouters.length; i++) {
      assertEq(savedRouters[i], _args.routers[i]);
    }
  }

  // Shortcut for above method
  function helpers_executeAndAssert(bytes32 _id, ExecuteArgs memory _args) public {
    helpers_executeAndAssert(_id, _args, true);
  }

  // ============ Tests ==============

  // TODO: Getters/view methods

  // ============ Admin methods ==============
  // setPromiseRouter
  // setExecutor
  // setSponsorVault

  // ============ Public methods ==============

  // ============ xcall ============

  // ============ xcall fail cases
  // fails if origin domain is incorrect
  // fails if destination domain does not have an xapp router registered
  // fails if recipient `to` not a valid address (i.e. != address(0))
  // fails if callback address is empty and callback fee is > 0
  // fails if callback is defined but not a contract
  // fails if callback is defined (and is a contract) but callback fee is 0
  // fails if asset is not supported (i.e. s.adoptedToCanonical[transactingAssetId].id == bytes32(0))

  // fails if native token transfer and amount of native tokens sent is < amount + relayerFee
  // AssetLogic__handleIncomingAsset_notAmount

  // fails if native token transfer and amount of native tokens sent is < amount + relayerFee + callbackFee
  // AssetLogic__handleIncomingAsset_notAmount

  // fails if native tokens sent < relayerFee + callbackFee
  // AssetLogic__handleIncomingAsset_ethWithErcTransfer

  // fails if user has insufficient tokens

  // ============ xcall success cases
  // base case
  function test_BridgeFacet__xcall_shouldWork() public {
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs();
    helpers_xcallAndAssert(transferId, args);
  }

  // handle (reconcile)

  // bumpTransfer

  // ============ execute ============

  // ============ execute fail cases
  // should fail if msg.sender is not an approved relayer
  function test_BridgeFacet__execute_failIfRelayerNotApproved() public {
    // set context
    s.approvedRelayers[address(this)] = false;

    // get args
    (, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    // expect failure
    vm.expectRevert(BridgeFacet.BridgeFacet__execute_unapprovedRelayer.selector);
    this.execute(args);
  }

  // should fail if it is a slow transfer (forceSlow = true) and we try to execute with routers
  function test_BridgeFacet__execute_failIfForceSlowAndRoutersSet() public {
    _params.forceSlow = true;

    // Routers providing liquidity implies this is a fast-liquidity transfer. If we're forcing slow,
    // this should fail.
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(2);

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_notReconciled.selector);
    this.execute(args);
  }

  // should fail if it is a slow transfer (forceSlow = true) and not reconciled
  function test_BridgeFacet__execute_failIfForceSlowAndNotReconciled() public {
    _params.forceSlow = true;

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(0);

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_notReconciled.selector);
    this.execute(args);
  }

  // should fail if no routers were passed in and not reconciled
  function test_BridgeFacet__execute_failIfNoRoutersAndNotReconciled() public {
    // Setting no routers in the execute call means that the transfer must already be reconciled.
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(0);

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_notReconciled.selector);
    this.execute(args);
  }

  // should fail if the router is not approved and ownership is not renounced
  function test_BridgeFacet__execute_failIfRouterNotApproved() public {
    s._routerOwnershipRenounced = false;

    (, ExecuteArgs memory args) = utils_makeExecuteArgs(1);
    s.routerPermissionInfo.approvedRouters[args.routers[0]] = false;

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_notSupportedRouter.selector);
    this.execute(args);
  }

  // should fail if the router signature is invalid
  function test_BridgeFacet__execute_failIfSignatureInvalid() public {
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    // Make invalid args based on (slightly) altered params.
    _params.originDomain = 1001;
    (, ExecuteArgs memory invalidArgs) = utils_makeExecuteArgs(4);
    // The signature of the last router in the group will be invalid.
    args.routerSignatures[0] = invalidArgs.routerSignatures[0];

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_invalidRouterSignature.selector);
    this.execute(args);
  }

  // multipath: should fail if any 1 router's signature is invalid
  function test_BridgeFacet__execute_failIfAnySignatureInvalid() public {
    // Using multipath; this should fail if any 1 router signature is invalid.
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(4);

    for (uint256 i; i < args.routers.length; i++) {
      s.routerBalances[args.routers[i]][args.local] += 10 ether;
    }

    // Make invalid args based on (slightly) altered params.
    _params.originDomain = 1001;
    (, ExecuteArgs memory invalidArgs) = utils_makeExecuteArgs(4);
    // The signature of the last router in the group will be invalid.
    args.routerSignatures[3] = invalidArgs.routerSignatures[3];

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_invalidRouterSignature.selector);
    this.execute(args);
  }

  // should fail if it was already executed (s.transferRelayer[transferId] != address(0))
  function test_BridgeFacet__execute_failIfAlreadyExecuted() public {
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);
    s.transferRelayer[transferId] = address(this);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_alreadyExecuted.selector);
    this.execute(args);
  }

  // should fail if the router does not have sufficient tokens
  function test_BridgeFacet__execute_failIfRouterHasInsufficientFunds() public {
    _amount = 5 ether;

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 4.5 ether;

    vm.expectRevert(stdError.arithmeticError);
    this.execute(args);
  }

  // should fail if sponsored vault did not fund contract

  // multipath: should fail if pathLength > maxRouters
  function test_BridgeFacet__execute_failIfPathLengthGreaterThanMaxRouters() public {
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(s.maxRoutersPerTransfer + 1);

    for (uint256 i; i < args.routers.length; i++) {
      s.routerBalances[args.routers[i]][args.local] += 10 ether;
    }

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_maxRoutersExceeded.selector);
    this.execute(args);
  }

  // multipath: should fail if any 1 router has insufficient tokens
  function test_BridgeFacet__execute_failIfAnyRouterHasInsufficientFunds() public {
    _amount = 5 ether;

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(s.maxRoutersPerTransfer);

    uint256 routerAmountSent = _amount / args.routers.length; // The amount each individual router will send.

    // Set the first router's balance to be (slightly) less than the amount that they'd need to send.
    s.routerBalances[args.routers[0]][args.local] = routerAmountSent - 0.1 ether;
    for (uint256 i = 1; i < args.routers.length; i++) {
      // The other routers have plenty of funds.
      s.routerBalances[args.routers[i]][args.local] = 50 ether;
    }

    vm.expectRevert(stdError.arithmeticError);
    this.execute(args);
  }

  // ============ execute success cases
  // should use slow liquidity if specified (forceSlow = true)
  function test_BridgeFacet__execute_forceSlowWorks() public {
    // set test params
    _params.forceSlow = true;

    // get args
    (bytes32 _id, ExecuteArgs memory _args) = utils_makeExecuteArgs(0);

    // set reconciled context
    s.reconciledTransfers[_id] = true;

    helpers_executeAndAssert(_id, _args);
  }

  // should use the local asset if specified (receiveLocal = true)
  function test_BridgeFacet__execute_receiveLocalWorks() public {
    _params.receiveLocal = true;

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    helpers_executeAndAssert(transferId, args);
  }

  // should work with approved router if router ownership is not renounced
  function test_BridgeFacet__execute_approvedRouterWorks() public {
    s._routerOwnershipRenounced = false;

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;
    s.routerPermissionInfo.approvedRouters[args.routers[0]] = true;

    helpers_executeAndAssert(transferId, args);
  }

  // should work without calldata
  function test_BridgeFacet__execute_noCalldataWorks() public {
    _params.callData = bytes("");
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    uint256 amount = utils_getFastTransferAmount(args.amount);

    // Sanity check: caller should previously have 0 tokens.
    assertEq(IERC20(args.local).balanceOf(args.params.to), 0);
    // With no calldata set, this method call should just send funds directly to the user.
    helpers_executeAndAssert(transferId, args);
    assertEq(IERC20(args.local).balanceOf(args.params.to), amount);
  }

  // should work with successful calldata
  function test_BridgeFacet__execute_successfulCalldata() public {
    // Set the args.to to the mock xapp address, and args.callData to the `fulfill` fn.
    _params.callData = abi.encodeWithSelector(MockXApp.fulfill.selector, _local, TEST_MESSAGE);
    _params.to = _xapp;

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    // TODO: Would be great to check for this emit, but currently it's not visible to compiler for some reason.
    // uint256 amount = utils_getFastTransferAmount(args.amount);
    // bytes memory returnData;
    // vm.expectEmit(true, true, false, true);
    // emit IExecutor.Executed(
    //   transferId,
    //   args.params.to,
    //   args.params.recovery,
    //   adopted,
    //   amount,
    //   // Should be EMPTY_BYTES because the originDomain/originSender properties have not been
    //   // optimistically verified if the call has not been reconciled.
    //   LibCrossDomainProperty.EMPTY_BYTES,
    //   args.params.callData,
    //   returnData,
    //   true
    // );

    // TODO: Can't emit this event either!
    // vm.expectEmit(true, true, false, true);
    // emit MockXApp.MockXAppEvent(address(this), _local, bytes32("test message"), amount);

    helpers_executeAndAssert(transferId, args);
    // Recovery address should not receive any funds if the call was successful.
    assertEq(IERC20(args.local).balanceOf(_recovery), 0);
  }

  // should work with failing calldata : contract call failed
  function test_BridgeFacet__execute_failingCalldata() public {
    // Set the args.to to the mock xapp address, and args.callData to the `fail` fn.
    _params.callData = abi.encodeWithSelector(MockXApp.fail.selector);
    _params.to = _xapp;

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    uint256 amount = utils_getFastTransferAmount(args.amount);

    helpers_executeAndAssert(transferId, args, false);
    // Recovery address should receive the funds if the call failed.
    assertEq(IERC20(args.local).balanceOf(_recovery), amount);
    // TODO: Check allowance is the same as before.
  }

  // should work with failing calldata : `to` is not a contract (should call _handleFailure)
  function test_BridgeFacet__execute_handleToIsNotAContract() public {
    // Setting the calldata to be for fulfill... but obviously, that method should never be called.
    // Because `to` is not a valid contract address.
    _params.callData = abi.encodeWithSelector(MockXApp.fulfill.selector, _local, TEST_MESSAGE);
    _params.to = address(42);

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    uint256 amount = utils_getFastTransferAmount(args.amount);

    helpers_executeAndAssert(transferId, args, false);
    // Recovery address should receive the funds if the call failed.
    assertEq(IERC20(args.local).balanceOf(_recovery), amount);
  }

  // should work if already reconciled (happening in slow liquidity mode)
  function test_BridgeFacet__execute_handleAlreadyReconciled() public {
    // Set the args.to to the mock xapp address, and args.callData to the
    // `fulfillWithProperties` fn. This will check to make sure `originDomain` and
    // `originSender` properties are correctly set.
    _params.callData = abi.encodeWithSelector(
      MockXApp.fulfillWithProperties.selector,
      _local,
      TEST_MESSAGE,
      _originDomain,
      _originSender
    );
    _params.to = _xapp;

    // We specify that 0 routers are in the path for this execution.
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(0);

    // Transfer has already been reconciled.
    s.reconciledTransfers[transferId] = true;

    helpers_executeAndAssert(transferId, args, true);
    // Recovery address should not receive the funds if the call succeeded.
    assertEq(IERC20(args.local).balanceOf(_recovery), 0);
  }

  // multipath: should subtract equally from each router's liquidity
  function test_BridgeFacet__execute_multipath() public {
    _amount = 1 ether;

    // Call the mock xapp just to ensure that the full execute e2e remains uniform.
    _params.callData = abi.encodeWithSelector(MockXApp.fulfill.selector, _local, TEST_MESSAGE);
    _params.to = _xapp;

    // Should work if the pathLength == max routers.
    uint256 pathLength = s.maxRoutersPerTransfer;
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(pathLength);

    // Sanity check: assuming the multipath is > 1, no router should need to have more than half of the
    // transfer amount.
    s.routerBalances[args.routers[0]][args.local] = 0.5 ether;
    for (uint256 i = 1; i < args.routers.length; i++) {
      s.routerBalances[args.routers[i]][args.local] = 10 ether;
    }

    uint256 amount = utils_getFastTransferAmount(args.amount);
    uint256 routerAmountSent = amount / pathLength; // The amount each individual router will send.

    helpers_executeAndAssert(transferId, args);
    // Recovery address should not receive any funds if the call was successful.
    assertEq(IERC20(args.local).balanceOf(_recovery), 0);
    // Make sure routers had their funds deducted correctly.
    assertEq(s.routerBalances[args.routers[0]][args.local], 0.5 ether - routerAmountSent);
    for (uint256 i = 1; i < args.routers.length; i++) {
      assertEq(s.routerBalances[args.routers[i]][args.local], 10 ether - routerAmountSent);
    }
  }

  // should work with sponsorship from sponsor vault
  // TODO: see _handleExecuteTransaction

  // TODO: test callback handling
}
