// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {XAppConnectionManager, TypeCasts} from "../../../../contracts/nomad-core/contracts/XAppConnectionManager.sol";

import {IStableSwap} from "../../../../contracts/core/connext/interfaces/IStableSwap.sol";
import {ITokenRegistry} from "../../../../contracts/core/connext/interfaces/ITokenRegistry.sol";
import {IBridgeToken} from "../../../../contracts/core/connext/interfaces/IBridgeToken.sol";
import {IWrapped} from "../../../../contracts/core/connext/interfaces/IWrapped.sol";
import {IExecutor} from "../../../../contracts/core/connext/interfaces/IExecutor.sol";
import {Executor} from "../../../../contracts/core/connext/helpers/Executor.sol";
import {ConnextMessage} from "../../../../contracts/core/connext/libraries/ConnextMessage.sol";
import {LibCrossDomainProperty} from "../../../../contracts/core/connext/libraries/LibCrossDomainProperty.sol";
import {CallParams, ExecuteArgs, XCallArgs} from "../../../../contracts/core/connext/libraries/LibConnextStorage.sol";
import {LibDiamond} from "../../../../contracts/core/connext/libraries/LibDiamond.sol";
import {BridgeFacet} from "../../../../contracts/core/connext/facets/BridgeFacet.sol";
import {TestERC20} from "../../../../contracts/test/TestERC20.sol";
import {PromiseRouter} from "../../../../contracts/core/promise/PromiseRouter.sol";

import {MockXAppConnectionManager, MockHome, MockXApp, MockPromiseRouter, MockCallback, MockWrapper} from "../../../utils/Mock.sol";
import "../../../../lib/forge-std/src/console.sol";
import "./FacetHelper.sol";

contract BridgeFacetTest is BridgeFacet, FacetHelper {
  bytes32 constant TEST_MESSAGE = bytes32("test message");

  // ============ Storage ============
  // diamond storage contract owner
  address _ds_owner = address(987654321);

  // local asset for this domain
  address _local;
  // executor contract
  address _executor;
  // mock xapp contract
  address _xapp;
  // mock xapp connection manager
  address _xappConnectionManager;
  // mock home
  address _xappHome;
  // mock promise router
  address payable _promiseRouter;
  // mock callback contract
  address _callback;

  // native asset wrapper
  address _wrapper;

  // default origin sender
  address _originSender = address(4);

  // destination remote handler id
  bytes32 _remote = bytes32("remote");

  // domains
  uint32 _originDomain = 1000;
  uint32 _destinationDomain = 2000;

  // canonical token details
  address _canonical = address(5);
  bytes32 _canonicalId = bytes32(abi.encodePacked(_canonical));
  uint32 _canonicalDomain = _originDomain;

  // relayer fee
  uint256 _relayerFee = 0.1 ether;

  // default amount
  uint256 _amount = 1.1 ether;

  // default nonce on xcall
  uint256 _nonce = 1;

  // default recovery address
  address constant _recovery = address(121212);

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
    // Deploy any needed contracts.
    utils_deployContracts();

    setDefaults();

    // Set up asset context. By default, local is the adopted asset - the one the 'user'
    // is using - and is representational (meaning canonically it belongs to another chain).
    vm.mockCall(
      _tokenRegistry,
      abi.encodeWithSelector(ITokenRegistry.getTokenId.selector),
      abi.encode(_canonicalDomain, _canonicalId)
    );

    s.adoptedToCanonical[address(s.wrapper)] = ConnextMessage.TokenId(_canonicalDomain, _canonicalId);
    s.adoptedToCanonical[_local] = ConnextMessage.TokenId(_canonicalDomain, _canonicalId);
    s.adoptedToLocalPools[_canonicalId] = IStableSwap(address(0));
    s.canonicalToAdopted[_canonicalId] = _local;

    utils_makeLocalAssetRepresentational();

    // By default, the local asset will be used as the 'adopted' asset sent by the user in `xcall`, for instance.
    vm.mockCall(_tokenRegistry, abi.encodeWithSelector(ITokenRegistry.getLocalAddress.selector), abi.encode(_local));

    // Promise router mock calls.
    vm.mockCall(_promiseRouter, abi.encodeWithSelector(PromiseRouter.send.selector), abi.encode());
    vm.mockCall(_promiseRouter, abi.encodeWithSelector(PromiseRouter.initCallbackFee.selector), abi.encode());

    // Other context setup: configuration, storage, etc.
    s.approvedRelayers[address(this)] = true;
    s.maxRoutersPerTransfer = 5;
    s._routerOwnershipRenounced = true;

    vm.prank(address(this));
    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    ds.contractOwner = _ds_owner;

    // NOTE: Currently, the only time we check for the domain in params to match the contract's
    // domain is within the `xcall` method - so it's safe to set the contract domain to be origin.
    s.domain = _originDomain;
    s.remotes[_destinationDomain] = _remote;
  }

  // ============ Utils ============
  // Utils used in the following tests (as well as setup).

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
    _xappHome = address(new MockHome());
    // Deploy a mock xapp connection manager.
    _xappConnectionManager = address(new MockXAppConnectionManager(MockHome(_xappHome)));
    s.xAppConnectionManager = XAppConnectionManager(_xappConnectionManager);
    // Deploy the promise router.
    s.promiseRouter = new MockPromiseRouter();
    _promiseRouter = payable(s.promiseRouter);
    // vm.store(_promiseRouter, bytes32(uint256(0)), bytes32(bytes20(address(this))));

    // Deploy wrapper for native asset.
    s.wrapper = IWrapped(new MockWrapper());
    _wrapper = address(s.wrapper);
    vm.mockCall(_wrapper, abi.encodeWithSelector(IBridgeToken.name.selector), abi.encode("TestERC20"));
    vm.mockCall(_wrapper, abi.encodeWithSelector(IBridgeToken.symbol.selector), abi.encode("TEST"));
    vm.mockCall(_wrapper, abi.encodeWithSelector(IBridgeToken.decimals.selector), abi.encode(18));

    // Deploy a mock callback.
    _callback = address(new MockCallback());
  }

  function utils_useNative(bool isWrapperLocal) public {
    _local = address(0);
    // Make it so the local asset used for testing is canonical / considered to be locally originating.
    vm.mockCall(_tokenRegistry, abi.encodeWithSelector(ITokenRegistry.isLocalOrigin.selector), abi.encode(bool(true)));
    // getLocalAddress should return the wrapper address if we want to use the wrapper as the bridged asset.
    if (isWrapperLocal) {
      vm.mockCall(
        _tokenRegistry,
        abi.encodeWithSelector(ITokenRegistry.getLocalAddress.selector),
        abi.encode(address(s.wrapper))
      );
    } else {
      // TODO: Implement local token for wrapper, handle mockCalls for swapping wrapper => local.
      require(false, "Not implemented");
    }
  }

  // Make it so the local asset used for testing is representational / considered to be originating from another chain.
  // In order to send the asset via xcall, it will be burnt.
  function utils_makeLocalAssetRepresentational() public {
    vm.mockCall(_tokenRegistry, abi.encodeWithSelector(ITokenRegistry.isLocalOrigin.selector), abi.encode(bool(false)));
  }

  // Meant to mimic the corresponding `_getTransferId` method in the BridgeFacet contract.
  function utils_getTransferIdFromXCallArgs(
    XCallArgs memory _args,
    address sender,
    bytes32 canonicalId,
    uint32 canonicalDomain
  ) public returns (bytes32) {
    return keccak256(abi.encode(s.nonce, _args.params, sender, canonicalId, canonicalDomain, _args.amount));
  }

  // Meant to mimic the corresponding `_getTransferId` method in the BridgeFacet contract.
  function utils_getTransferIdFromExecuteArgs(ExecuteArgs memory _args) public returns (bytes32) {
    return
      keccak256(
        abi.encode(_args.nonce, _args.params, _args.originSender, _canonicalId, _canonicalDomain, _args.amount)
      );
  }

  // Makes some mock xcall arguments using params set in storage.
  function utils_makeXCallArgs() public returns (bytes32, XCallArgs memory) {
    // get args
    XCallArgs memory args = XCallArgs(
      _params,
      _local, // transactingAssetId : could be adopted, local, or wrapped.
      _amount,
      _relayerFee
    );
    // generate transfer id
    bytes32 transferId = utils_getTransferIdFromXCallArgs(args, _originSender, _canonicalId, _canonicalDomain);

    return (transferId, args);
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
    bytes32 transferId = utils_getTransferIdFromExecuteArgs(args);
    // generate router signatures if applicable
    if (routers.length > 0) {
      args.routerSignatures = utils_makeRouterSignatures(transferId, routers, keys);
    }
    return (transferId, args);
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

  // Mimics the xcall message formatting. Reduced functionality : won't burn any tokens, for example.
  function utils_formatMessage(
    XCallArgs memory _args,
    address _asset,
    bytes32 _transferId,
    uint256 _amount
  ) public returns (bytes memory) {
    IBridgeToken token = IBridgeToken(_asset);

    bytes32 detailsHash;
    if (s.tokenRegistry.isLocalOrigin(_asset)) {
      detailsHash = ConnextMessage.formatDetailsHash(token.name(), token.symbol(), token.decimals());
    } else {
      detailsHash = token.detailsHash();
    }

    bytes29 action = ConnextMessage.formatTransfer(
      TypeCasts.addressToBytes32(_args.params.to),
      _amount,
      detailsHash,
      _transferId
    );
    (uint32 canonicalDomain, bytes32 canonicalId) = s.tokenRegistry.getTokenId(_asset);
    bytes29 tokenId = ConnextMessage.formatTokenId(canonicalDomain, canonicalId);

    return ConnextMessage.formatMessage(tokenId, action);
  }

  // ============== Helpers ==================
  // Helpers used for executing target methods with given params that assert expected base behavior.

  // Calls `xcall` with given args and handles standard assertions.
  function helpers_xcallAndAssert(
    bytes32 transferId,
    XCallArgs memory args,
    uint256 dealTokens,
    bytes4 expectedError
  ) public {
    bool isNative = args.transactingAssetId == address(0);
    bool shouldSucceed = keccak256(abi.encode(expectedError)) == keccak256(abi.encode(bytes4("")));

    // Deal the user required eth for transfer.
    vm.deal(_originSender, 100 ether);

    uint256 initialUserBalance;
    uint256 initialContractBalance;
    if (isNative) {
      initialUserBalance = payable(_originSender).balance;
      initialContractBalance = payable(address(this)).balance;
    } else {
      TestERC20 localToken = TestERC20(_local);

      // Mint the specified amount of tokens for the user.
      localToken.mint(_originSender, dealTokens);

      initialUserBalance = localToken.balanceOf(_originSender);
      initialContractBalance = localToken.balanceOf(address(this));

      // Approve the target contract to spend the specified amount of tokens.
      vm.prank(_originSender);
      localToken.approve(address(this), dealTokens);
    }

    assertEq(s.relayerFees[transferId], 0);

    if (shouldSucceed) {
      // TODO: Handle bridgedAmt changing after swap?
      uint256 bridgedAmt = args.amount;
      address bridged = isNative ? address(s.wrapper) : _local;
      BridgeFacet.XCalledEventArgs memory eventArgs = BridgeFacet.XCalledEventArgs({
        transactingAssetId: isNative ? address(s.wrapper) : args.transactingAssetId,
        amount: args.amount,
        bridgedAmt: bridgedAmt,
        bridged: bridged
      });
      bytes memory message = this.utils_formatMessage(args, bridged, transferId, bridgedAmt);
      vm.expectEmit(true, true, true, true);
      emit XCalled(transferId, args, eventArgs, s.nonce, message, _originSender);

      if (args.params.callbackFee > 0) {
        // Assert that CallbackFee would be paid by the user.
        vm.expectCall(_promiseRouter, abi.encodeWithSelector(PromiseRouter.initCallbackFee.selector, transferId));
      }
    } else {
      vm.expectRevert(expectedError);
    }

    vm.prank(_originSender);
    uint256 fees = args.relayerFee + args.params.callbackFee;
    this.xcall{value: isNative ? fees + args.amount : fees}(args);

    if (shouldSucceed) {
      if (isNative) {
        // Should have custodied the relayer fee, sent any callback fee to the promise router, and deposited the
        // amount into the wrapper contract.
        assertEq(payable(address(this)).balance, initialContractBalance + args.relayerFee);
      } else {
        // User should have been debited fees... but also tx cost?
        // assertEq(payable(_originSender).balance, initialUserBalance - fees);

        // Check that the user has been debited the correct amount of tokens.
        assertEq(TestERC20(_local).balanceOf(_originSender), initialUserBalance - args.amount);
        // Check that the contract has been credited the correct amount of tokens.
        // NOTE: Because the tokens are a representational local asset, they are burnt. The contract
        // should NOT be holding any additional tokens after xcall completes.
        // TODO: Handle tokens being canonical asset - should be custodied instead.
        assertEq(TestERC20(_local).balanceOf(address(this)), initialContractBalance);
      }
      // Should have updated relayer fees mapping.
      assertEq(s.relayerFees[transferId], args.relayerFee);

      if (args.params.callbackFee > 0) {
        // TODO: For some reason, balance isn't changing. Perhaps the vm.mockCall prevents this?
        // CallbackFee should be delivered to the PromiseRouter.
        // assertEq(_promiseRouter.balance, _params.callbackFee);
      }
    } else {
      // Should have reverted.
      assertEq(s.relayerFees[transferId], 0);
    }
  }

  // Shortcut for the main fn. Generates args within this method.
  function helpers_xcallAndAssert(bytes4 expectedError) public {
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs();
    uint256 dealTokens = (args.transactingAssetId == address(0)) ? 0 : args.amount;
    helpers_xcallAndAssert(transferId, args, dealTokens, expectedError);
  }

  // Shortcut for the above fn, with no expected error.
  function helpers_xcallAndAssert() public {
    helpers_xcallAndAssert(bytes4(""));
  }

  // Shortcut for the main fn.
  // NOTE: Intended only for testing xcall with tokens, not native asset.
  function helpers_xcallAndAssert(uint256 dealTokens) public {
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs();
    helpers_xcallAndAssert(transferId, args, dealTokens, bytes4(""));
  }

  // Calls `execute` on the target method with the given args and asserts expected behavior.
  function helpers_executeAndAssert(
    bytes32 transferId,
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
    IERC20 token = IERC20(s.canonicalToAdopted[_canonicalId]);
    uint256 prevBalanceTo = token.balanceOf(_params.to);

    // execute
    uint256 transferred = pathLen == 0 ? _args.amount : utils_getFastTransferAmount(_args.amount);
    vm.expectEmit(true, true, false, true);
    emit Executed(transferId, _args.params.to, _args, _args.local, transferred, address(this));
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
    assertEq(s.transferRelayer[transferId], address(this));

    // should have assigned transfer as routed
    address[] memory savedRouters = s.routedTransfers[transferId];
    for (uint256 i; i < savedRouters.length; i++) {
      assertEq(savedRouters[i], _args.routers[i]);
    }
  }

  // Shortcut for above method
  function helpers_executeAndAssert(bytes32 transferId, ExecuteArgs memory _args) public {
    helpers_executeAndAssert(transferId, _args, true);
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
  function test_BridgeFacet__xcall_failIfDomainIncorrect() public {
    _params.originDomain = 999999;
    helpers_xcallAndAssert(BridgeFacet.BridgeFacet__xcall_wrongDomain.selector);
  }

  // fails if destination domain does not have an xapp router registered
  // function test_BridgeFacet__xcall_failIfDomainIncorrect() public {
  //   _originDomain = 999999;
  //   vm.expectRevert(BridgeFacet.BridgeFacet__xcall_wrongDomain.selector);
  //   helpers_xcallAndAssert(false);
  // }

  // fails if recipient `to` not a valid address (i.e. != address(0))
  function test_BridgeFacet__xcall_failIfMoRecipient() public {
    _params.to = address(0);
    helpers_xcallAndAssert(BridgeFacet.BridgeFacet__xcall_emptyTo.selector);
  }

  // fails if callback fee > 0 but callback address is not defined
  function test_BridgeFacet__xcall_failIfCallbackFeeButNoContract() public {
    _params.callback = address(0);
    _params.callbackFee = 0.001 ether;
    helpers_xcallAndAssert(BridgeFacet.BridgeFacet__xcall_nonZeroCallbackFeeForCallback.selector);
  }

  // TODO?: fails if callback is defined (and is a contract) but callback fee is 0 ??
  // function test_BridgeFacet__xcall_failIfCallbackContractSetButNoCallbackFee() public {
  //   _params.callback = _callback;
  //   _params.callbackFee = 0;
  //   helpers_xcallAndAssert(BridgeFacet.BridgeFacet__xcall_nonZeroCallbackFeeForCallback.selector);
  // }

  // fails if callback is defined but not a contract
  function test_BridgeFacet__xcall_failIfCallbackNotAContract() public {
    _params.callback = address(42);
    _params.callbackFee = 0.001 ether;
    helpers_xcallAndAssert(BridgeFacet.BridgeFacet__xcall_callbackNotAContract.selector);
  }

  // fails if asset is not supported (i.e. s.adoptedToCanonical[transactingAssetId].id == bytes32(0))

  // fails if callbackFee in param and value does not match in native transfer
  // fails if relayerFee in param and value does not match in native transfer

  // Fail if relayerFee in param and value does not match in token transfer

  // fails if native token transfer and amount of native tokens sent is < amount + relayerFee
  // AssetLogic__handleIncomingAsset_notAmount

  // fails if native token transfer and amount of native tokens sent is < amount + relayerFee + callbackFee
  // AssetLogic__handleIncomingAsset_notAmount

  // fails if erc20 transfer and eth sent < relayerFee + callbackFee
  // AssetLogic__handleIncomingAsset_ethWithErcTransfer
  // fails if erc20 transfer and eth sent > relayerFee + callbackFee
  // AssetLogic__handleIncomingAsset_ethWithErcTransfer

  // fails if user has insufficient tokens

  // ============ xcall success cases
  // local token transfer
  function test_BridgeFacet__xcall_tokenTransferWorks() public {
    helpers_xcallAndAssert();
  }

  // native asset transfer
  function test_BridgeFacet__xcall_nativeTransferWorks() public {
    utils_useNative(true);
    helpers_xcallAndAssert();
  }

  // should send promise router callback fee
  function test_BridgeFacet__xcall_shouldHandleCallbackFee() public {
    _params.callback = _callback;
    _params.callbackFee = 0.02 ether;
    helpers_xcallAndAssert();
  }

  // works if relayer fee is set to 0
  function test_BridgeFacet__xcall_zeroRelayerFeeWorks() public {
    _relayerFee = 0;
    helpers_xcallAndAssert();
  }

  // ======= handle (reconcile) =======
  // handle

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
    (bytes32 transferId, ExecuteArgs memory _args) = utils_makeExecuteArgs(0);

    // set reconciled context
    s.reconciledTransfers[transferId] = true;

    helpers_executeAndAssert(transferId, _args);
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

  // should work with failing calldata : recipient `to` is not a contract (should call _handleFailure)
  function test_BridgeFacet__execute_handleRecipientNotAContract() public {
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

  // TODO: test callback handling, should send the promise router the return data
  // TODO: test native asset handling
}
