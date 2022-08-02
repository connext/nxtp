// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {XAppConnectionManager, TypeCasts} from "../../../../contracts/nomad-core/contracts/XAppConnectionManager.sol";
import {Home} from "../../../../contracts/nomad-core/contracts/Home.sol";
import {TypedMemView} from "../../../../contracts/nomad-core/libs/TypedMemView.sol";

import {IAavePool} from "../../../../contracts/core/connext/interfaces/IAavePool.sol";
import {IStableSwap} from "../../../../contracts/core/connext/interfaces/IStableSwap.sol";
import {ISponsorVault} from "../../../../contracts/core/connext/interfaces/ISponsorVault.sol";
import {ITokenRegistry} from "../../../../contracts/core/connext/interfaces/ITokenRegistry.sol";
import {IBridgeRouter} from "../../../../contracts/core/connext/interfaces/IBridgeRouter.sol";
import {IWeth} from "../../../../contracts/core/connext/interfaces/IWeth.sol";
import {IExecutor} from "../../../../contracts/core/connext/interfaces/IExecutor.sol";
import {Executor} from "../../../../contracts/core/connext/helpers/Executor.sol";
import {RelayerFeeMessage} from "../../../../contracts/core/relayer-fee/libraries/RelayerFeeMessage.sol";
import {AssetLogic} from "../../../../contracts/core/connext/libraries/AssetLogic.sol";
import {LibCrossDomainProperty} from "../../../../contracts/core/connext/libraries/LibCrossDomainProperty.sol";
import {CallParams, ExecuteArgs, XCallArgs, TokenId, TransferIdInformation} from "../../../../contracts/core/connext/libraries/LibConnextStorage.sol";
import {LibDiamond} from "../../../../contracts/core/connext/libraries/LibDiamond.sol";
import {BridgeFacet} from "../../../../contracts/core/connext/facets/BridgeFacet.sol";
import {BaseConnextFacet} from "../../../../contracts/core/connext/facets/BaseConnextFacet.sol";
import {TestERC20} from "../../../../contracts/test/TestERC20.sol";
import {TokenRegistry} from "../../../../contracts/test/TokenRegistry.sol";
import {BridgeMessage} from "../../../../contracts/test/BridgeMessage.sol";
import {PromiseRouter} from "../../../../contracts/core/promise/PromiseRouter.sol";

import "../../../utils/Mock.sol";
import "../../../utils/FacetHelper.sol";

contract BridgeFacetTest is BridgeFacet, FacetHelper {
  // ============ Libs ============
  using TypedMemView for bytes29;
  using TypedMemView for bytes;
  // ============ Constants ============

  bytes32 constant TEST_MESSAGE = bytes32("test message");

  // ============ Storage ============
  // diamond storage contract owner
  address _ds_owner = address(987654321);

  // executor contract
  address _executor;
  // mock xapp contract
  address _xapp;
  // mock bridge router
  address _bridgeRouter;
  // mock promise router
  address payable _promiseRouter;
  // mock callback contract
  address _callback;

  // agents
  address _agent = address(123456654321);

  // sequencer
  uint256 _sequencerPKey = 0xA11CE;
  address _sequencer = vm.addr(_sequencerPKey);

  // default origin sender
  address _originSender = address(4);

  // aave pool details
  address _aavePool;

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
      _agent, // agent
      _recovery, // recovery address
      false, // forceSlow
      false, // receiveLocal
      address(0), // callback
      0, // callbackFee
      _relayerFee, // relayer fee
      1 ether // destinationMinOut
    );

  // ============ Test set up ============
  function setUp() public {
    // Deploy any needed contracts.
    utils_deployContracts();

    utils_setFees();

    // Set up asset context. By default, local is the adopted asset - the one the 'user'
    // is using - and is representational (meaning canonically it belongs to another chain).
    utils_setupAsset(true, false);

    // Promise router mock calls.
    vm.mockCall(_promiseRouter, abi.encodeWithSelector(PromiseRouter.send.selector), abi.encode());
    vm.mockCall(_promiseRouter, abi.encodeWithSelector(PromiseRouter.initCallbackFee.selector), abi.encode());

    // Other context setup: configuration, storage, etc.
    s.approvedRelayers[address(this)] = true;
    s.approvedSequencers[_sequencer] = true;
    s.maxRoutersPerTransfer = 5;
    s._routerWhitelistRemoved = true;
    s.bridgeRouter = IBridgeRouter(_bridgeRouter);

    s.connextions[_destinationDomain] = TypeCasts.addressToBytes32(address(this));
    s.connextions[_originDomain] = TypeCasts.addressToBytes32(address(this));
    s.connextions[_canonicalDomain] = TypeCasts.addressToBytes32(address(this));

    vm.prank(address(this));
    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    ds.contractOwner = _ds_owner;
  }

  // ============ Utils ============
  // Utils used in the following tests (as well as setup).

  // Used in set up for deploying any needed peripheral contracts.
  function utils_deployContracts() public {
    utils_deployAssetContracts();
    // Deploy an executor.
    _executor = address(new Executor(address(this)));
    s.executor = IExecutor(_executor);
    // Deploy a mock xapp consumer.
    _xapp = address(new MockXApp());

    // Deploy a mock bridge router.
    _bridgeRouter = address(new MockBridgeRouter());
    // Deploy the promise router.
    s.promiseRouter = new MockPromiseRouter();
    _promiseRouter = payable(address(s.promiseRouter));

    // Deploy a mock callback.
    _callback = address(new MockCallback());

    // setup aave pool
    _aavePool = address(new MockPool(false));
    s.aavePool = _aavePool;
  }

  // Meant to mimic the corresponding `_getTransferId` method in the BridgeFacet contract.
  function utils_getTransferIdFromXCallArgs(
    XCallArgs memory _args,
    address sender,
    bytes32 canonicalId,
    uint32 canonicalDomain,
    uint256 bridigedAmt
  ) public view returns (bytes32) {
    return keccak256(abi.encode(s.nonce, _args.params, sender, canonicalId, canonicalDomain, bridigedAmt));
  }

  // Meant to mimic the corresponding `_getTransferId` method in the BridgeFacet contract.
  function utils_getTransferIdFromExecuteArgs(ExecuteArgs memory _args) public returns (bytes32) {
    return
      keccak256(
        abi.encode(_args.nonce, _args.params, _args.originSender, _canonicalId, _canonicalDomain, _args.amount)
      );
  }

  // Makes some mock xcall arguments using params set in storage.
  function utils_makeXCallArgs(uint256 bridged) public returns (bytes32, XCallArgs memory) {
    s.domain = _originDomain;
    // get args
    XCallArgs memory args = XCallArgs(_params, _adopted, _amount, (_amount * 9990) / 10000);
    // generate transfer id
    bytes32 transferId = utils_getTransferIdFromXCallArgs(args, _originSender, _canonicalId, _canonicalDomain, bridged);

    return (transferId, args);
  }

  function utils_makeXCallArgs(address transactingAssetId, uint256 bridged) public returns (bytes32, XCallArgs memory) {
    s.domain = _originDomain;
    // get args
    XCallArgs memory args = XCallArgs(
      _params,
      transactingAssetId, // transactingAssetId : could be adopted, local, or wrapped.
      _amount,
      (_amount * 9990) / 10000
    );
    // generate transfer id
    bytes32 transferId = utils_getTransferIdFromXCallArgs(args, _originSender, _canonicalId, _canonicalDomain, bridged);

    return (transferId, args);
  }

  function utils_makeSequencerSignature(
    bytes32 transferId,
    address[] memory routers,
    address sequencer,
    uint256 key
  ) public returns (bytes memory) {
    bytes32 preImage = keccak256(abi.encode(transferId, routers));
    bytes32 toSign = ECDSA.toEthSignedMessageHash(preImage);
    (uint8 v, bytes32 r, bytes32 _s) = vm.sign(key, toSign);
    return abi.encodePacked(r, _s, v);
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
    s.domain = _destinationDomain;
    // get args
    bytes[] memory empty = new bytes[](0);
    ExecuteArgs memory args = ExecuteArgs(
      _params,
      _local,
      routers,
      empty,
      address(0),
      bytes(""),
      _amount,
      _nonce,
      _originSender
    );
    // generate transfer id
    bytes32 transferId = utils_getTransferIdFromExecuteArgs(args);
    // generate router signatures if applicable
    if (routers.length != 0) {
      args.routerSignatures = utils_makeRouterSignatures(transferId, routers, keys);
      args.sequencer = _sequencer;
      args.sequencerSignature = utils_makeSequencerSignature(transferId, routers, _sequencer, _sequencerPKey);
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
    return (_amount * s.LIQUIDITY_FEE_NUMERATOR) / BPS_FEE_DENOMINATOR;
  }

  // ============== Helpers ==================
  // Helpers used for executing target methods with given params that assert expected base behavior.
  function helpers_setupSuccessfulXcallCallAssertions(
    bytes32 transferId,
    XCallArgs memory args,
    uint256 bridgedAmt,
    bool shouldSwap
  ) public {
    // bridged is either local or canonical, depending on domain xcall originates on
    address bridged = _canonicalDomain == args.params.originDomain ? _canonical : _local;
    vm.expectEmit(true, true, true, true);
    emit XCalled(transferId, s.nonce, args, bridged, bridgedAmt, _originSender);

    // assert swap if expected
    if (shouldSwap && bridgedAmt != 0) {
      // Transacting asset shouldve been approved for amount in
      vm.expectCall(
        args.transactingAsset,
        abi.encodeWithSelector(IERC20.approve.selector, _stableSwap, args.transactingAmount)
      );

      // swapExact on pool should have been called
      vm.expectCall(
        _stableSwap,
        abi.encodeWithSelector(
          IStableSwap.swapExact.selector,
          args.transactingAmount,
          args.transactingAsset,
          _local,
          args.originMinOut
        )
      );
    }

    if (args.params.callbackFee != 0) {
      // Assert that CallbackFee would be paid by the user.
      vm.expectCall(
        _promiseRouter,
        args.params.callbackFee,
        abi.encodeWithSelector(PromiseRouter.initCallbackFee.selector, transferId)
      );
    }
    // Assert approval call
    vm.expectCall(bridged, abi.encodeWithSelector(IERC20.approve.selector, _bridgeRouter, bridgedAmt));

    // Assert bridge router call
    vm.expectCall(
      _bridgeRouter,
      abi.encodeWithSelector(
        IBridgeRouter.sendToHook.selector,
        bridged,
        bridgedAmt,
        args.params.destinationDomain,
        s.connextions[args.params.destinationDomain], // always use this as remote connext
        abi.encode(TransferIdInformation(args.params, s.nonce, _originSender))
      )
    );
  }

  // Calls `xcall` with given args and handles standard assertions.
  function helpers_xcallAndAssert(
    bytes32 transferId,
    XCallArgs memory args,
    uint256 dealTokens,
    uint256 bridgedAmt,
    bytes4 expectedError,
    bool shouldSwap
  ) public {
    bool shouldSucceed = keccak256(abi.encode(expectedError)) == keccak256(abi.encode(bytes4("")));
    bool isCanonical = _canonicalDomain == args.params.originDomain;

    // Deal the user required eth for transfer.
    vm.deal(_originSender, 100 ether);

    uint256 initialUserBalance;
    uint256 initialContractBalance;
    {
      TestERC20 tokenIn = TestERC20(args.transactingAsset);
      TestERC20 localToken = TestERC20(_local);

      // Mint the specified amount of tokens for the user.
      tokenIn.mint(_originSender, dealTokens);

      initialUserBalance = tokenIn.balanceOf(_originSender);
      initialContractBalance = localToken.balanceOf(address(this));

      // Approve the target contract to spend the specified amount of tokens.
      vm.prank(_originSender);
      tokenIn.approve(address(this), dealTokens);
    }

    if (shouldSwap) {
      // Setup the expected swap mock (adopted <> local)
      vm.mockCall(_stableSwap, abi.encodeWithSelector(IStableSwap.swapExact.selector), abi.encode(bridgedAmt, _local));
    }

    uint256 initialRelayerFees = s.relayerFees[transferId];

    if (shouldSucceed) {
      helpers_setupSuccessfulXcallCallAssertions(transferId, args, bridgedAmt, shouldSwap);
    } else {
      vm.expectRevert(expectedError);
    }

    uint256 fees = args.params.relayerFee + args.params.callbackFee;
    vm.prank(_originSender);
    this.xcall{value: fees}(args);

    if (shouldSucceed) {
      // User should have been debited fees... but also tx cost?
      // assertEq(payable(_originSender).balance, initialUserBalance - fees);

      // Check that the user has been debited the correct amount of tokens.
      assertEq(TestERC20(args.transactingAsset).balanceOf(_originSender), initialUserBalance - args.transactingAmount);

      // Check that the contract has been credited the correct amount of tokens.
      // NOTE: Because the tokens are a representational local asset, they are burnt. The contract
      // should NOT be holding any additional tokens after xcall completes.
      if (isCanonical) {
        // This should be a canonical asset transfer
        assertEq(TestERC20(_canonical).balanceOf(address(this)), initialContractBalance);
      } else {
        // NOTE: Normally the adopted asset would be swapped into the local asset and then
        // the local asset would be burned. Because the swap increases the contracts balance
        // the prod difference in balance is net 0. However, because the swap here is mocked,
        // when a swap occurrs no balance increase of local happens (i.e. if swap needed, the
        // balance will decrease by bridgedAmt / what is burned)
        uint256 expected = args.transactingAsset == _local
          ? initialContractBalance
          : initialContractBalance - bridgedAmt;
        assertEq(TestERC20(_local).balanceOf(address(this)), expected);
      }

      // Should have updated relayer fees mapping.
      assertEq(this.relayerFees(transferId), args.params.relayerFee + initialRelayerFees);

      if (args.params.callbackFee != 0) {
        // TODO: For some reason, balance isn't changing. Perhaps the vm.mockCall prevents this?
        // CallbackFee should be delivered to the PromiseRouter.
        // assertEq(_promiseRouter.balance, _params.callbackFee);
      }
    } else {
      // Should have reverted.
      assertEq(this.relayerFees(transferId), initialRelayerFees);
    }
  }

  // Shortcut for the main fn. Generates args within this method.
  function helpers_xcallAndAssert(
    bytes4 expectedError,
    uint256 bridged,
    bool swaps
  ) public {
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs(bridged);
    uint256 dealTokens = (args.transactingAsset == address(0)) ? 0 : args.transactingAmount;
    helpers_xcallAndAssert(transferId, args, dealTokens, bridged, expectedError, swaps);
  }

  function helpers_xcallAndAssert(bytes4 expectedError) public {
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs(_amount);
    uint256 dealTokens = (args.transactingAsset == address(0)) ? 0 : args.transactingAmount;
    helpers_xcallAndAssert(transferId, args, dealTokens, 0, expectedError, false);
  }

  // Shortcut for the above fn, with no expected error.
  function helpers_xcallAndAssert(uint256 bridged, bool swaps) public {
    helpers_xcallAndAssert(bytes4(""), bridged, swaps);
  }

  // Shortcut for the above fn, no expected error, specified transacting asset
  function helpers_xcallAndAssert(
    uint256 bridged,
    address transacting,
    bool swaps
  ) public {
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs(transacting, bridged);
    helpers_xcallAndAssert(transferId, args, args.transactingAmount, bridged, bytes4(""), swaps);
  }

  // Shortcut for the main fn.
  function helpers_xcallAndAssert(
    uint256 dealTokens,
    uint256 bridged,
    bool swaps
  ) public {
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs(bridged);
    helpers_xcallAndAssert(transferId, args, dealTokens, bridged, bytes4(""), swaps);
  }

  struct ExecuteBalances {
    uint256 bridge;
    uint256 to;
    uint256 executor;
    uint256 debt;
    uint256 feeDebt;
  }

  struct ExecuteTestInputs {
    uint256 expectedAmt;
    uint256 routerAmt;
    address token;
    bool callsExternal;
    bool externalCallSucceeds;
    bool shouldSwap; // Whether the `to` address should receive the tokens.
    bool isSlow;
    bool usesPortals;
    bool useAgent;
  }

  function utils_getExecuteBalances(
    bytes32 transferId,
    IERC20 asset,
    address _to
  ) public returns (ExecuteBalances memory) {
    uint256 debt = s.portalDebt[transferId];
    uint256 fee = s.portalFeeDebt[transferId];
    uint256 bridge = IERC20(_local).balanceOf(address(this));
    uint256 to = asset.balanceOf(_to);
    uint256 executor = asset.balanceOf(_executor);
    return ExecuteBalances(bridge, to, executor, debt, fee);
  }

  function helpers_setupExecuteAssertions(
    bytes32 transferId,
    ExecuteArgs memory _args,
    ExecuteTestInputs memory _inputs
  ) public {
    // ----- register expected calls

    // expects portal
    if (_inputs.usesPortals) {
      // mint position
      vm.expectCall(
        _aavePool,
        abi.encodeWithSelector(IAavePool.mintUnbacked.selector, _adopted, _inputs.routerAmt, address(this), 0)
      );

      // withdraw
      vm.expectCall(
        _aavePool,
        abi.encodeWithSelector(IAavePool.withdraw.selector, _adopted, _inputs.routerAmt, address(this))
      );
    }

    // expected swap
    if (_inputs.shouldSwap) {
      // register expected approval
      vm.expectCall(_local, abi.encodeWithSelector(IERC20.approve.selector, _stableSwap, _inputs.routerAmt));
      // register expected swap amount
      vm.expectCall(
        _stableSwap,
        abi.encodeWithSelector(
          IStableSwap.swapExact.selector,
          _inputs.routerAmt,
          _local,
          _adopted,
          _args.params.destinationMinOut
        )
      );
    }

    // expected sponsor vault
    if (address(s.sponsorVault) != address(0)) {
      // if it is a fast transfer, then it should reimburse liquidity fees
      if (!_inputs.isSlow) {
        vm.expectCall(
          address(s.sponsorVault),
          abi.encodeWithSelector(
            ISponsorVault.reimburseLiquidityFees.selector,
            _inputs.token,
            (_args.amount * (BPS_FEE_DENOMINATOR - s.LIQUIDITY_FEE_NUMERATOR)) / BPS_FEE_DENOMINATOR,
            _args.params.to
          )
        );
      }
      // always reimburses relayer fees
      vm.expectCall(
        address(s.sponsorVault),
        abi.encodeWithSelector(
          ISponsorVault.reimburseRelayerFees.selector,
          _originDomain,
          _args.params.to,
          _args.params.relayerFee
        )
      );
    }

    // expected transfer out of contract
    if (_args.amount != 0) {
      // token transfer
      vm.expectCall(
        _inputs.token,
        abi.encodeWithSelector(
          IERC20.transfer.selector,
          _inputs.callsExternal ? _executor : _args.params.to,
          _inputs.expectedAmt
        )
      );
    }

    // expected executor call
    if (_inputs.callsExternal) {
      {
        bytes memory properties = _inputs.isSlow
          ? LibCrossDomainProperty.formatDomainAndSenderBytes(_originDomain, _originSender)
          : LibCrossDomainProperty.EMPTY_BYTES;
        vm.expectCall(
          _executor,
          abi.encodeWithSelector(
            IExecutor.execute.selector,
            IExecutor.ExecutorArgs(
              transferId,
              _inputs.expectedAmt,
              _args.params.to,
              _args.params.recovery,
              _inputs.token,
              properties,
              _args.params.callData
            )
          )
        );
      }
    }

    // expected promise router call
    if (_args.params.callback != address(0)) {
      vm.expectCall(
        _promiseRouter,
        abi.encodeWithSelector(
          PromiseRouter.send.selector,
          _originDomain,
          transferId,
          _args.params.callback,
          _inputs.externalCallSucceeds,
          bytes("")
        )
      );
    }
  }

  // Calls `execute` on the target method with the given args and asserts expected behavior.
  function helpers_executeAndAssert(
    bytes32 transferId,
    ExecuteArgs memory _args,
    ExecuteTestInputs memory _inputs
  ) public {
    // get pre-execute liquidity in local
    uint256 pathLen = _args.routers.length;
    uint256[] memory prevLiquidity = new uint256[](pathLen);
    {
      for (uint256 i; i < pathLen; i++) {
        prevLiquidity[i] = s.routerBalances[_args.routers[i]][_local];
      }
    }

    // get pre-execute balance here in local
    IERC20 token = IERC20(_inputs.token);
    ExecuteBalances memory prevBalances = utils_getExecuteBalances(transferId, token, _args.params.to);

    // execute
    // expected amount is impacted by (1) fast liquidity fees (2) slippage
    // router debited amount in local is only impacted by fast liquidity
    uint256 routerAmt = _inputs.isSlow ? _args.amount : utils_getFastTransferAmount(_args.amount);

    // setup pool mock if needed
    if (_inputs.shouldSwap) {
      vm.mockCall(
        _stableSwap,
        abi.encodeWithSelector(IStableSwap.swapExact.selector),
        abi.encode(_inputs.expectedAmt, _adopted)
      );
    }

    // setup execute mock
    vm.mockCall(
      _executor,
      abi.encodeWithSelector(Executor.execute.selector),
      abi.encode(_inputs.externalCallSucceeds, bytes(""))
    );

    // register expected calls
    helpers_setupExecuteAssertions(transferId, _args, _inputs);

    if (_inputs.usesPortals) {
      vm.expectEmit(true, true, true, true);
      emit AavePortalMintUnbacked(transferId, _args.routers[0], _inputs.token, _inputs.expectedAmt);
    }

    // register expected emit event
    address sender = _inputs.useAgent ? _args.params.agent : address(this);
    vm.expectEmit(true, true, false, true);
    emit Executed(transferId, _args.params.to, _args, _inputs.token, _inputs.expectedAmt, sender);
    // make call
    vm.prank(sender);
    this.execute(_args);

    // check local balance
    {
      if (pathLen != 0) {
        // should decrement router balance unless using aave
        for (uint256 i; i < pathLen; i++) {
          assertEq(
            s.routerBalances[_args.routers[i]][_args.local],
            _inputs.usesPortals ? prevLiquidity[i] : prevLiquidity[i] - (_inputs.routerAmt / pathLen)
          );
        }
      }
    }

    {
      // assertions
      ExecuteBalances memory finalBalances = utils_getExecuteBalances(transferId, token, _args.params.to);

      // NOTE: the balance of the bridge *should* always decrement in local, however that depends on
      // the token executing the `swap` / `withdraw` call when a swap is needed (which we have as mocked).
      // Instead, assert the swap functions on the pool were called correctly
      if (!_inputs.shouldSwap) {
        // NOTE: when using aave would normally send you funds for the position minted,
        // but we are not adding any funds from the pool, so always decrement
        assertEq(
          finalBalances.bridge,
          _inputs.usesPortals ? prevBalances.bridge : prevBalances.bridge - _inputs.routerAmt
        );
      }

      if (_inputs.usesPortals) {
        uint256 fee = (_inputs.routerAmt * _portalFeeNumerator) / _liquidityFeeDenominator;
        assertEq(finalBalances.feeDebt, prevBalances.feeDebt + fee);
        assertEq(finalBalances.debt, prevBalances.debt + _inputs.routerAmt);
      } else {
        assertEq(finalBalances.feeDebt, prevBalances.feeDebt);
        assertEq(finalBalances.debt, prevBalances.debt);
      }

      if (_inputs.callsExternal) {
        // should increment balance of executor
        // should NOT increment balance of to
        // NOTE: recovery address testing should be done in Executor.t.sol
        // as such, executor balance should *always* increment
        assertEq(finalBalances.executor, prevBalances.executor + _inputs.expectedAmt);
        assertEq(token.balanceOf(_params.to), prevBalances.to);
      } else {
        // should have incremented balance of `to`
        // should NOT increment balance of executor
        assertEq(finalBalances.to, prevBalances.to + _inputs.expectedAmt);
        assertEq(finalBalances.executor, prevBalances.executor);
      }
    }

    // should mark the transfer as executed
    assertEq(s.transferRelayer[transferId], sender);

    // should have assigned transfer as routed
    address[] memory savedRouters = s.routedTransfers[transferId];
    for (uint256 i; i < savedRouters.length; i++) {
      assertEq(savedRouters[i], _args.routers[i]);
    }
  }

  function helpers_executeAndAssert(
    bytes32 transferId,
    ExecuteArgs memory _args,
    uint256 expectedAmt, // amount out of swap
    bool callsExternal,
    bool externalCallSucceeds,
    bool shouldSwap, // Whether the `to` address should receive the tokens.
    bool usesPortals,
    bool useAgent
  ) public {
    uint256 pathLen = _args.routers.length;
    bool isSlow = pathLen == 0;
    // get pre-execute balance here in local
    uint256 routerAmt = isSlow ? _args.amount : utils_getFastTransferAmount(_args.amount);
    helpers_executeAndAssert(
      transferId,
      _args,
      ExecuteTestInputs(
        expectedAmt,
        routerAmt,
        shouldSwap ? _adopted : _local, // token
        callsExternal,
        externalCallSucceeds,
        shouldSwap,
        isSlow,
        usesPortals,
        useAgent
      )
    );
  }

  function helpers_executeAndAssert(
    bytes32 transferId,
    ExecuteArgs memory _args,
    uint256 expectedAmt, // amount out of swap
    bool callsExternal,
    bool externalCallSucceeds,
    bool shouldSwap // Whether the `to` address should receive the tokens.
  ) public {
    helpers_executeAndAssert(
      transferId,
      _args,
      expectedAmt,
      callsExternal,
      externalCallSucceeds,
      shouldSwap,
      false,
      false
    );
  }

  // ============ execute ============
  // Shortcut for above method:
  // - local == adopted
  // - does not call external
  // - calling on non-canonical domain
  function helpers_executeAndAssert(bytes32 transferId, ExecuteArgs memory _args) public {
    uint256 expected = _args.amount;
    if (_args.routers.length != 0) {
      expected = utils_getFastTransferAmount(_args.amount);
    }
    helpers_executeAndAssert(transferId, _args, expected, false, false, false, false, false);
  }

  // Shortcut where:
  // - local != adopted
  // - does not call external
  // - calling on noncanonical domain
  function helpers_executeAndAssert(
    bytes32 transferId,
    ExecuteArgs memory _args,
    uint256 expected,
    bool shouldSwap
  ) public {
    helpers_executeAndAssert(transferId, _args, expected, false, false, shouldSwap, false, false);
  }

  function helpers_executeAndAssert(
    bytes32 transferId,
    ExecuteArgs memory _args,
    bool useAgent
  ) public {
    uint256 expected = _args.amount;
    if (_args.routers.length != 0) {
      expected = utils_getFastTransferAmount(_args.amount);
    }
    helpers_executeAndAssert(transferId, _args, expected, false, false, false, false, useAgent);
  }

  // ============ Getters ==============

  function test_BridgeFacet_domain_works() public {
    s.domain = 0;
    assertEq(this.domain(), 0);
    s.domain = _destinationDomain;
    assertEq(this.domain(), _destinationDomain);
  }

  function test_BridgeFacet_executor_works() public {
    s.executor = IExecutor(address(0));
    assertEq(address(this.executor()), address(0));
    s.executor = IExecutor(_local);
    assertEq(address(this.executor()), _local);
  }

  function test_BridgeFacet_nonce_works() public {
    s.nonce = 0;
    assertEq(this.nonce(), 0);
    s.nonce = _destinationDomain;
    assertEq(this.nonce(), _destinationDomain);
  }

  function test_BridgeFacet_sponsorVault_works() public {
    s.sponsorVault = ISponsorVault(address(0));
    assertEq(address(this.sponsorVault()), address(0));
    s.sponsorVault = ISponsorVault(_local);
    assertEq(address(this.sponsorVault()), _local);
  }

  function test_BridgeFacet_promiseRouter_works() public {
    s.promiseRouter = PromiseRouter(payable(address(0)));
    assertEq(address(this.promiseRouter()), address(0));
    s.promiseRouter = PromiseRouter(payable(_local));
    assertEq(address(this.promiseRouter()), _local);
  }

  // The rest (relayerFees, routedTransfers, reconciledTransfers) are checked on
  // assertions for xcall / reconcile / execute

  // ============ Admin methods ==============
  // setPromiseRouter
  // FIXME: move to BaseConnextFacet.t.sol
  function test_BridgeFacet__setPromiseRouter_failIfNotOwner() public {
    // constants
    address old = address(123);
    address updated = address(_local);

    // set storage
    s.promiseRouter = PromiseRouter(payable(old));

    // test revert
    vm.prank(_originSender);
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);
    this.setPromiseRouter(payable(updated));
  }

  function test_BridgeFacet__setPromiseRouter_failIfNoChange() public {
    // constants
    address old = address(123);
    address updated = old;

    // set storage
    s.promiseRouter = PromiseRouter(payable(old));

    // test revert
    vm.prank(LibDiamond.contractOwner());
    vm.expectRevert(BridgeFacet.BridgeFacet__setPromiseRouter_invalidPromiseRouter.selector);
    this.setPromiseRouter(payable(updated));
  }

  function test_BridgeFacet__setPromiseRouter_failIfNotContract() public {
    // constants
    address old = address(123);
    address updated = address(456);

    // set storage
    s.promiseRouter = PromiseRouter(payable(old));

    // test revert
    vm.prank(LibDiamond.contractOwner());
    vm.expectRevert(BridgeFacet.BridgeFacet__setPromiseRouter_invalidPromiseRouter.selector);
    this.setPromiseRouter(payable(updated));
  }

  function test_BridgeFacet__setPromiseRouter_works() public {
    // constants
    address old = address(123);
    address updated = address(_local);

    // set storage
    s.promiseRouter = PromiseRouter(payable(old));

    // test success
    vm.prank(LibDiamond.contractOwner());
    vm.expectEmit(true, true, true, true);
    emit PromiseRouterUpdated(old, updated, LibDiamond.contractOwner());
    this.setPromiseRouter(payable(updated));
    assertEq(address(this.promiseRouter()), updated);
  }

  // setExecutor
  function test_BridgeFacet__setExecutor_failIfNotOwner() public {
    // constants
    address old = address(123);
    address updated = address(_local);

    // set storage
    s.executor = IExecutor(payable(old));

    // test revert
    vm.prank(_originSender);
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);
    this.setExecutor(payable(updated));
  }

  function test_BridgeFacet__setExecutor_failIfNoChange() public {
    // constants
    address old = address(123);
    address updated = old;

    // set storage
    s.executor = IExecutor(payable(old));

    // test revert
    vm.prank(LibDiamond.contractOwner());
    vm.expectRevert(BridgeFacet.BridgeFacet__setExecutor_invalidExecutor.selector);
    this.setExecutor(payable(updated));
  }

  function test_BridgeFacet__setExecutor_failIfNotContract() public {
    // constants
    address old = address(123);
    address updated = address(456);

    // set storage
    s.executor = IExecutor(payable(old));

    // test revert
    vm.prank(LibDiamond.contractOwner());
    vm.expectRevert(BridgeFacet.BridgeFacet__setExecutor_invalidExecutor.selector);
    this.setExecutor(payable(updated));
  }

  function test_BridgeFacet__setExecutor_works() public {
    // constants
    address old = address(123);
    address updated = address(_local);

    // set storage
    s.executor = IExecutor(payable(old));

    // test revert
    vm.prank(LibDiamond.contractOwner());
    vm.expectEmit(true, true, true, true);
    emit ExecutorUpdated(old, updated, LibDiamond.contractOwner());
    this.setExecutor(payable(updated));
    assertEq(address(this.executor()), updated);
  }

  // setSponsorVault
  function test_BridgeFacet__setSponsorVault_failIfNotOwner() public {
    // constants
    address old = address(123);
    address updated = old;

    // set storage
    s.sponsorVault = ISponsorVault(payable(old));

    // test revert
    vm.prank(_originSender);
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);
    this.setSponsorVault(payable(updated));
  }

  function test_BridgeFacet__setSponsorVault_failIfNoChange() public {
    // constants
    address old = address(123);
    address updated = old;

    // set storage
    s.sponsorVault = ISponsorVault(payable(old));

    // test revert
    vm.prank(LibDiamond.contractOwner());
    vm.expectRevert(BridgeFacet.BridgeFacet__setSponsorVault_invalidSponsorVault.selector);
    this.setSponsorVault(payable(updated));
  }

  function test_BridgeFacet__setSponsorVault_works() public {
    // constants
    address old = address(123);
    address updated = address(_local);

    // set storage
    s.sponsorVault = ISponsorVault(payable(old));

    // test revert
    vm.prank(LibDiamond.contractOwner());
    vm.expectEmit(true, true, true, true);
    emit SponsorVaultUpdated(old, updated, LibDiamond.contractOwner());
    this.setSponsorVault(payable(updated));
    assertEq(address(this.sponsorVault()), updated);
  }

  // addSequencer
  function test_BridgeFacet__addSequencer_failIfNotOwner() public {
    // constants
    address sequencer = address(123);

    // test revert
    vm.prank(_originSender);
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);
    this.addSequencer(sequencer);
  }

  function test_BridgeFacet__addSequencer_failIfAlreadyApproved() public {
    // constants
    address sequencer = address(123);

    // set storage
    s.approvedSequencers[sequencer] = true;

    // test revert
    vm.prank(LibDiamond.contractOwner());
    vm.expectRevert(BridgeFacet.BridgeFacet__addSequencer_alreadyApproved.selector);
    this.addSequencer(sequencer);
  }

  function test_BridgeFacet__addSequencer_works() public {
    // constants
    address sequencer = address(123);

    // set storage
    s.approvedSequencers[sequencer] = false;

    // test revert
    vm.prank(LibDiamond.contractOwner());
    this.addSequencer(sequencer);

    assertEq(s.approvedSequencers[sequencer], true);
  }

  // removeSequencer
  function test_BridgeFacet__removeSequencer_failIfNotOwner() public {
    // constants
    address sequencer = address(123);

    // test revert
    vm.prank(_originSender);
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__onlyOwner_notOwner.selector);
    this.removeSequencer(sequencer);
  }

  function test_BridgeFacet__removeSequencer_failIfAlreadyApproved() public {
    // constants
    address sequencer = address(123);

    // set storage
    s.approvedSequencers[sequencer] = false;

    // test revert
    vm.prank(LibDiamond.contractOwner());
    vm.expectRevert(BridgeFacet.BridgeFacet__removeSequencer_notApproved.selector);
    this.removeSequencer(sequencer);
  }

  function test_BridgeFacet__removeSequencer_works() public {
    // constants
    address sequencer = address(123);

    // set storage
    s.approvedSequencers[sequencer] = true;

    // test revert
    vm.prank(LibDiamond.contractOwner());
    this.removeSequencer(sequencer);

    assertEq(s.approvedSequencers[sequencer], false);
  }

  // ============ Public methods ==============

  // ============ xcall ============

  // ============ xcall fail cases
  // fails if paused
  // FIXME: move to BaseConnextFacet.t.sol
  function test_BridgeFacet__xcall_failIfPaused() public {
    // require(false, "not tested");
  }

  // fails if origin domain is incorrect
  function test_BridgeFacet__xcall_failIfDomainIncorrect() public {
    _params.originDomain = 999999;
    helpers_xcallAndAssert(BridgeFacet.BridgeFacet__xcall_wrongDomain.selector);
  }

  function test_BridgeFacet__xcall_failIfDestinationNotSupported() public {
    _params.destinationDomain = 999999;
    helpers_xcallAndAssert(BridgeFacet.BridgeFacet__xcall_destinationNotSupported.selector);
  }

  // TODO: fails if destination domain does not have an xapp router registered
  // FIXME: this should be tested at the integration level (i.e. when we deploy
  // the contracts via Deployer.sol), or on a facet that asserts this

  // fails if recipient `to` not a valid address (i.e. != address(0))
  function test_BridgeFacet__xcall_failIfNoRecipient() public {
    _params.to = address(0);
    helpers_xcallAndAssert(BridgeFacet.BridgeFacet__xcall_emptyToOrRecovery.selector);
  }

  // fails if callback fee > 0 but callback address is not defined
  function test_BridgeFacet__xcall_failIfCallbackFeeButNoContract() public {
    _params.callback = address(0);
    _params.callbackFee = 0.001 ether;
    helpers_xcallAndAssert(BridgeFacet.BridgeFacet__xcall_nonZeroCallbackFeeForCallback.selector);
  }

  // fails if callback is defined but not a contract
  function test_BridgeFacet__xcall_failIfCallbackNotAContract() public {
    _params.callback = address(42);
    _params.callbackFee = 0.001 ether;
    helpers_xcallAndAssert(BridgeFacet.BridgeFacet__xcall_callbackNotAContract.selector);
  }

  // fails if asset is not supported (i.e. s.adoptedToCanonical[transactingAssetId].id == bytes32(0) and using non-local)
  function test_BridgeFacet__xcall_failIfAssetNotSupported() public {
    // setup asset with local != adopted, not on canonical domain
    utils_setupAsset(false, false);

    s.adoptedToCanonical[_adopted] = TokenId(0, bytes32(0));

    // ensure token registry returns true for local origin
    vm.mockCall(
      address(s.tokenRegistry),
      abi.encodeWithSelector(ITokenRegistry.isLocalOrigin.selector, _adopted),
      abi.encode(true)
    );
    helpers_xcallAndAssert(BridgeFacet.BridgeFacet__xcall_notSupportedAsset.selector);
  }

  // fails if native asset is used
  function test_BridgeFacet__xcall_failIfNativeAsset() public {
    _amount = 1 ether;
    TestERC20 localToken = TestERC20(_local);
    localToken.mint(_originSender, 1 ether);
    vm.prank(_originSender);
    localToken.approve(address(this), 1 ether);

    vm.deal(_originSender, 100 ether);

    (, XCallArgs memory args) = utils_makeXCallArgs(_amount);

    // Set transacting asset to address 0, indicating the user wants to send native token, which
    // isn't supported.
    args.transactingAsset = address(0);

    vm.expectRevert(BridgeFacet.BridgeFacet__xcall_nativeAssetNotSupported.selector);
    vm.prank(_originSender);
    this.xcall{value: args.params.relayerFee}(args);
  }

  // fails if erc20 transfer and eth sent < relayerFee + callbackFee
  function test_BridgeFacet__xcall_failEthWithErc20TransferInsufficient() public {
    utils_setupAsset(true, false);
    vm.deal(_originSender, 100 ether);
    _relayerFee = 0.1 ether;

    (, XCallArgs memory args) = utils_makeXCallArgs(_amount);

    vm.expectRevert(BridgeFacet.BridgeFacet__xcall_ethValueMismatchedFees.selector);
    vm.prank(_originSender);
    // Sending insufficent eth to cover relayer fee.
    this.xcall{value: 0.08 ether}(args);
  }

  // fails if erc20 transfer and eth sent > relayerFee + callbackFee
  function test_BridgeFacet__xcall_failEthWithErc20TransferUnnecessary() public {
    vm.deal(_originSender, 100 ether);
    _relayerFee = 0.1 ether;

    (, XCallArgs memory args) = utils_makeXCallArgs(_amount);

    vm.expectRevert(BridgeFacet.BridgeFacet__xcall_ethValueMismatchedFees.selector);
    vm.prank(_originSender);
    // Sending too much eth.
    this.xcall{value: 1 ether}(args);
  }

  // fails if user has insufficient tokens
  function test_BridgeFacet__xcall_failInsufficientErc20Tokens() public {
    _amount = 10.1 ether;
    TestERC20 localToken = TestERC20(_local);
    localToken.mint(_originSender, 10 ether);
    vm.prank(_originSender);
    localToken.approve(address(this), 10.1 ether);

    vm.deal(_originSender, 100 ether);

    (, XCallArgs memory args) = utils_makeXCallArgs(_amount);

    vm.expectRevert("ERC20: transfer amount exceeds balance");
    vm.prank(_originSender);
    this.xcall{value: args.params.relayerFee}(args);
  }

  // fails if user has not set enough allowance
  function test_BridgeFacet__xcall_failInsufficientErc20Approval() public {
    _amount = 10.1 ether;
    TestERC20 localToken = TestERC20(_local);
    localToken.mint(_originSender, 10.1 ether);
    vm.prank(_originSender);
    localToken.approve(address(this), 10 ether);

    vm.deal(_originSender, 100 ether);

    (, XCallArgs memory args) = utils_makeXCallArgs(_amount);

    vm.expectRevert("ERC20: transfer amount exceeds allowance");
    vm.prank(_originSender);
    this.xcall{value: args.params.relayerFee}(args);
  }

  // ============ xcall success cases
  // asset cases:
  // - works on remote domain
  //   - transferring native (local == adopted)
  //   - transferring native (local != adopted)
  //   - transferring asset (local == adopted)
  //   - transferring asset (local != adopted)

  // - works on cannonical domain
  //   - transferring native (local == adopted)
  //   - transferring asset (local == adopted)
  // canonincal token transfer on canonical domain
  function test_BridgeFacet__xcall_canonicalTokenTransferWorks() public {
    utils_setupAsset(true, true);
    helpers_xcallAndAssert(_amount, false);
  }

  // local token transfer on non-canonical domain (local != adopted)
  function test_BridgeFacet__xcall_localTokenTransferWorksWithAdopted() public {
    uint256 bridged = (_amount * 9995) / _liquidityFeeDenominator;
    utils_setupAsset(false, false);
    helpers_xcallAndAssert(bridged, true);
  }

  // local token transfer on non-canonical domain, local != adopted, send in local
  // (i.e. i should be able to xcall with madEth on optimism)
  function test_BridgeFacet__xcall_localTokenTransferWorksWhenNotAdopted() public {
    // local is not adopted, not on canonical domain, sending in local
    utils_setupAsset(false, false);
    s.adoptedToCanonical[_local] = TokenId(0, bytes32(0));
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs(_amount);
    vm.mockCall(
      _tokenRegistry,
      abi.encodeWithSelector(ITokenRegistry.isLocalOrigin.selector, _local),
      abi.encode(false)
    );
    args.transactingAsset = _local;
    helpers_xcallAndAssert(transferId, args, args.transactingAmount, args.transactingAmount, bytes4(""), false);
  }

  function test_BridgeFacet__xcall_worksIfPreexistingRelayerFee() public {
    // local is not adopted, not on canonical domain, sending in local
    utils_setupAsset(true, false);
    _params.relayerFee = 0.1 ether;
    (bytes32 transferId, XCallArgs memory args) = utils_makeXCallArgs(_amount);
    s.relayerFees[transferId] = 2 ether;
    helpers_xcallAndAssert(transferId, args, args.transactingAmount, args.transactingAmount, bytes4(""), false);
    assertEq(s.relayerFees[transferId], 2.1 ether);
  }

  // local token transfer on non-canonical domain (local == adopted)
  function test_BridgeFacet__xcall_localTokenTransferWorksWithoutAdopted() public {
    utils_setupAsset(true, false);
    helpers_xcallAndAssert(_amount, false);
  }

  // adopted asset transfer
  function test_BridgeFacet__xcall_adoptedTransferWorks() public {
    utils_setupAsset(false, false);
    uint256 bridged = (_amount * 9995) / _liquidityFeeDenominator;
    helpers_xcallAndAssert(bridged, true);
  }

  // FIXME: should work with fee on transfer tokens
  function test_BridgeFacet__xcall_feeOnTransferWorks() public {
    // require(false, "not tested");
  }

  // should work with positive slippage
  function test_BridgeFacet__xcall_worksWithPositiveSlippage() public {
    utils_setupAsset(false, false);
    uint256 bridged = (_amount * 10005) / _liquidityFeeDenominator;
    helpers_xcallAndAssert(bridged, true);
  }

  // should work with 0 value
  function test_BridgeFacet__xcall_worksWithoutValue() public {
    _amount = 0;
    helpers_xcallAndAssert(0, true);
  }

  // should send promise router callback fee
  function test_BridgeFacet__xcall_shouldHandleCallbackFee() public {
    _params.callback = _callback;
    _params.callbackFee = 0.02 ether;
    helpers_xcallAndAssert(_amount, false);
  }

  // works if relayer fee is set to 0
  function test_BridgeFacet__xcall_zeroRelayerFeeWorks() public {
    _relayerFee = 0;
    helpers_xcallAndAssert(_amount, false);
  }

  // works with callback fee set to 0
  function test_BridgeFacet__xcall_zeroCallbackFeesWorks() public {
    _params.callbackFee = 0;
    helpers_xcallAndAssert(_amount, false);
  }

  // FIXME: move to BaseConnextFacet.t.sol
  // works if swap isnt required and swaps are paused
  function test_BridgeFacet__xcall_worksIfNoSwapAndSwapPaused() public {
    // require(false, "not tested");
  }

  // ============ execute ============
  // ============ execute fail cases

  // FIXME: move to `BaseConnextFacet.t.sol`
  // should fail if paused
  function test_BridgeFacet__execute_failIfPaused() public {
    // set context
    s._paused = true;

    // get args
    (, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    // expect failure
    vm.expectRevert(BaseConnextFacet.BaseConnextFacet__whenNotPaused_paused.selector);
    this.execute(args);
  }

  // should fail if msg.sender is not an approved relayer && msg.sender != params.agent
  function test_BridgeFacet__execute_failIfSenderNotApproved() public {
    // set context
    s.approvedRelayers[address(this)] = false;

    // get args
    (, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    // expect failure
    vm.expectRevert(BridgeFacet.BridgeFacet__execute_unapprovedSender.selector);
    this.execute(args);
  }

  // multipath: should fail if pathLength > maxRouters
  function test_BridgeFacet__execute_failIfPathLengthGreaterThanMaxRouters() public {
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(s.maxRoutersPerTransfer + 1);

    for (uint256 i; i < args.routers.length; i++) {
      s.routerBalances[args.routers[i]][args.local] += 10 ether;
    }

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_maxRoutersExceeded.selector);
    this.execute(args);
  }

  // should fail if it is a slow transfer (forceSlow = true) and not reconciled
  function test_BridgeFacet__execute_failIfForceSlowAndNotReconciled() public {
    _params.forceSlow = true;

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(0);

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_notReconciled.selector);
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

  // should fail if no routers were passed in and not reconciled
  function test_BridgeFacet__execute_failIfNoRoutersAndNotReconciled() public {
    // Setting no routers in the execute call means that the transfer must already be reconciled.
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(0);

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_notReconciled.selector);
    this.execute(args);
  }

  // should fail if the router is not approved and ownership is not renounced
  function test_BridgeFacet__execute_failIfRouterNotApproved() public {
    s._routerWhitelistRemoved = false;

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

  // should fail if the sequencer is not approved
  function test_BridgeFacet__execute_failIfSequencerNotApproved() public {
    (, ExecuteArgs memory args) = utils_makeExecuteArgs(1);
    s.approvedSequencers[args.sequencer] = false;

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_notSupportedSequencer.selector);
    this.execute(args);
  }

  // should fail if the sequencer signature is invalid
  function test_BridgeFacet__execute_failIfSequencerSignatureInvalid() public {
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    // Make invalid args based on (slightly) altered params (this will make
    // the transfer ID different).
    _params.originDomain = 1001;
    (, ExecuteArgs memory invalidArgs) = utils_makeExecuteArgs(4);
    // The signature of the sequencer will be invalid, as it signed a different transfer ID.
    args.sequencerSignature = invalidArgs.sequencerSignature;

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_invalidSequencerSignature.selector);
    this.execute(args);
  }

  // should fail if the sequencer signature is invalid; for this test, we'll be attempting to replay
  // one of the routers in the array repeatedly.
  function test_BridgeFacet__execute_failIfSequencerSignatureAndRoutersMismatch() public {
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(4);

    s.routerBalances[args.routers[0]][args.local] += 100 ether;
    s.routerBalances[args.routers[1]][args.local] += 100 ether;
    s.routerBalances[args.routers[2]][args.local] += 100 ether;
    s.routerBalances[args.routers[3]][args.local] += 100 ether;

    // Imagine a malicious relayer calling `execute` colludes with the first router in the array
    // to replay their address and signature for the other slots in the path.
    args.routers[1] = args.routers[0];
    args.routers[2] = args.routers[0];
    args.routers[3] = args.routers[0];
    args.routerSignatures[1] = args.routerSignatures[0];
    args.routerSignatures[2] = args.routerSignatures[0];
    args.routerSignatures[3] = args.routerSignatures[0];

    // The signature of the sequencer will be invalid, as it signed a different router array.
    vm.expectRevert(BridgeFacet.BridgeFacet__execute_invalidSequencerSignature.selector);
    this.execute(args);
  }

  function test_BridgeFacet__execute_failIfSequencerSignatureAndSequencerAddressMismatch() public {
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    address otherSequencer = address(789456123);
    s.approvedSequencers[otherSequencer] = true;

    // The signature of the sequencer will be invalid, because the sig recovery will result in a
    // different address.
    args.sequencer = otherSequencer;

    vm.expectRevert(BridgeFacet.BridgeFacet__execute_invalidSequencerSignature.selector);
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

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(2);

    s.routerBalances[args.routers[0]][args.local] = 1.5 ether;

    vm.expectRevert(stdError.arithmeticError);
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

  // should fail if sponsored vault did not fund contract with returned amount
  function test_BridgeFacet__execute_failIfSponsorVaultLied() public {
    (, ExecuteArgs memory args) = utils_makeExecuteArgs(1);
    s.routerPermissionInfo.approvedRouters[args.routers[0]] = true;
    for (uint256 i = 0; i < args.routers.length; i++) {
      // The other routers have plenty of funds.
      s.routerBalances[args.routers[i]][args.local] = 50 ether;
    }

    // set mock sponsor vault
    address vault = address(123456654321);
    s.sponsorVault = ISponsorVault(vault);
    // set change
    vm.mockCall(vault, abi.encodeWithSelector(ISponsorVault.reimburseLiquidityFees.selector), abi.encode(10 ether));

    vm.expectRevert(BridgeFacet.BridgeFacet__handleExecuteTransaction_invalidSponsoredAmount.selector);
    this.execute(args);
  }

  function test_BridgeFacet__execute_failsIfRouterNotApprovedForPortal() public {
    _amount = 5 ether;

    (bytes32 _id, ExecuteArgs memory _args) = utils_makeExecuteArgs(1);

    s.routerBalances[_args.routers[0]][_args.local] = 4.5 ether;

    // set aave enabled
    s.aavePool = _aavePool;

    vm.expectRevert(abi.encodeWithSelector(BridgeFacet.BridgeFacet__execute_notApprovedForPortals.selector));
    this.execute(_args);
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

    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    helpers_executeAndAssert(transferId, _args);
  }

  // should use the local asset if specified (receiveLocal = true)
  function test_BridgeFacet__execute_receiveLocalWorks() public {
    _params.receiveLocal = true;

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    // set asset context (local != adopted)
    utils_setupAsset(false, false);

    helpers_executeAndAssert(transferId, args, utils_getFastTransferAmount(args.amount), false);
  }

  // should work with approved router if router ownership is not renounced
  function test_BridgeFacet__execute_worksWithLocalAsAdopted() public {
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;
    s.routerPermissionInfo.approvedRouters[args.routers[0]] = true;

    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    helpers_executeAndAssert(transferId, args);
  }

  // works when local != adopted
  function test_BridgeFacet__execute_worksWithAdopted() public {
    // set asset context (local != adopted)
    utils_setupAsset(false, false);

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;
    s.routerPermissionInfo.approvedRouters[args.routers[0]] = true;

    helpers_executeAndAssert(transferId, args, utils_getFastTransferAmount(args.amount), true);
  }

  // works when local != adopted, should work with +ve slippage
  function test_BridgeFacet__execute_worksWithPositiveSlippage() public {
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;
    s.routerPermissionInfo.approvedRouters[args.routers[0]] = true;

    // set asset context (local != adopted)
    utils_setupAsset(false, false);

    helpers_executeAndAssert(transferId, args, utils_getFastTransferAmount(args.amount) + 1 ether, true);
  }

  // works when local != adopted, should work with -ve slippage
  function test_BridgeFacet__execute_worksWithNegativeSlippage() public {
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;
    s.routerPermissionInfo.approvedRouters[args.routers[0]] = true;

    // set asset context (local != adopted)
    utils_setupAsset(false, false);

    helpers_executeAndAssert(transferId, args, utils_getFastTransferAmount(args.amount) - 0.01 ether, true);
  }

  // works when on canonical domain
  function test_BridgeFacet__execute_worksOnCanonical() public {
    // set asset context (local == adopted)
    utils_setupAsset(true, true);

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;
    s.routerPermissionInfo.approvedRouters[args.routers[0]] = true;

    helpers_executeAndAssert(transferId, args);
  }

  // should work with unapproved router if router ownership is renounced
  function test_BridgeFacet__execute_worksWithUnapprovedIfNoWhitelist() public {
    s._routerWhitelistRemoved = true;

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;
    s.routerPermissionInfo.approvedRouters[args.routers[0]] = false;

    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    helpers_executeAndAssert(transferId, args);
  }

  // should work with 0 value
  function test_BridgeFacet__execute_worksWith0Value() public {
    _amount = 0;

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    helpers_executeAndAssert(transferId, args);
  }

  // should work if no sponsor vault set
  function test_BridgeFacet__execute_worksWithoutVault() public {
    s.sponsorVault = ISponsorVault(address(0));

    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);
    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    helpers_executeAndAssert(transferId, args);
  }

  // should sponsor if fast liquidity is used and sponsor vault set
  function test_BridgeFacet__execute_worksWithSponsorLiquidity() public {
    // setup vault
    uint256 vaultAmount = 10000;
    MockSponsorVault vault = new MockSponsorVault(vaultAmount, 0);
    s.sponsorVault = vault;

    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);
    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    helpers_executeAndAssert(transferId, args, utils_getFastTransferAmount(args.amount) + vaultAmount, false);
  }

  // should sponsor relayer fee in slow liquidity
  function test_BridgeFacet__execute_sponsorsRelayersSlow() public {
    // set test vault
    uint256 vaultAmount = 10000;
    MockSponsorVault vault = new MockSponsorVault(vaultAmount, 0);
    s.sponsorVault = vault;

    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    // get args
    (bytes32 transferId, ExecuteArgs memory _args) = utils_makeExecuteArgs(0);

    // set reconciled context
    s.reconciledTransfers[transferId] = true;

    helpers_executeAndAssert(transferId, _args);
  }

  // should work without calldata
  function test_BridgeFacet__execute_noCalldataWorks() public {
    _params.callData = bytes("");
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    // With no calldata set, this method call should just send funds directly to the user.
    helpers_executeAndAssert(transferId, args);
  }

  // should work with successful calldata and using fast liquidity
  function test_BridgeFacet__execute_successfulCalldata() public {
    // Set the args.to to the mock xapp address, and args.callData to the `fulfill` fn.
    _params.callData = abi.encodeWithSelector(MockXApp.fulfill.selector, _local, TEST_MESSAGE);

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    helpers_executeAndAssert(
      transferId,
      args,
      utils_getFastTransferAmount(args.amount),
      true,
      true,
      false,
      false,
      false
    );
  }

  // should work with failing calldata : contract call failed
  function test_BridgeFacet__execute_failingCalldata() public {
    // Set the args.to to the mock xapp address, and args.callData to the `fail` fn.
    _params.callData = abi.encodeWithSelector(MockXApp.fail.selector);
    _params.to = _xapp;

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    helpers_executeAndAssert(
      transferId,
      args,
      utils_getFastTransferAmount(args.amount),
      true,
      false,
      false,
      false,
      false
    );
  }

  function test_BridgeFacet__execute_failsIfNoLiquidityAndAaveNotEnabled() public {
    // get args
    (bytes32 _id, ExecuteArgs memory _args) = utils_makeExecuteArgs(1);

    // set liquidity context
    for (uint256 i; i < _args.routers.length; i++) {
      s.routerBalances[_args.routers[i]][_args.local] = 0 ether;
    }

    // set aave not enabled
    s.aavePool = address(0);

    vm.expectRevert(stdError.arithmeticError);
    this.execute(_args);
  }

  // should work with a callback
  function test_BridgeFacet__execute_worksWithCallback() public {
    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    _params.callback = address(123456654321);
    // Set the args.to to the mock xapp address, and args.callData to the `fulfill` fn.
    _params.callData = abi.encodeWithSelector(MockXApp.fulfill.selector, _local, TEST_MESSAGE);

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    helpers_executeAndAssert(
      transferId,
      args,
      utils_getFastTransferAmount(args.amount),
      true,
      true,
      false,
      false,
      false
    );
  }

  // FIXME: move to Executor.t.sol
  // should work with failing calldata : recipient `to` is not a contract (should call _handleFailure)
  function test_BridgeFacet__execute_handleRecipientNotAContract() public {
    // Setting the calldata to be for fulfill... but obviously, that method should never be called.
    // Because `to` is not a valid contract address.
    _params.callData = abi.encodeWithSelector(MockXApp.fulfill.selector, _local, TEST_MESSAGE);
    _params.to = address(42);

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;

    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    helpers_executeAndAssert(
      transferId,
      args,
      utils_getFastTransferAmount(args.amount),
      true,
      true,
      false,
      false,
      false
    );
  }

  // should work if already reconciled (happening in slow liquidity mode, uses
  // authenticated data)
  function test_BridgeFacet__execute_handleAlreadyReconciled() public {
    // set asset context (local == adopted)
    utils_setupAsset(true, false);

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

    helpers_executeAndAssert(transferId, args, args.amount, true, true, false, false, false);
  }

  // multipath: should subtract equally from each router's liquidity
  function test_BridgeFacet__execute_multipath() public {
    _amount = 1 ether;

    // Should work if the pathLength == max routers.
    uint256 pathLength = s.maxRoutersPerTransfer;
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(pathLength);

    // Add initial liquiidty
    for (uint256 i = 1; i < args.routers.length; i++) {
      s.routerBalances[args.routers[i]][args.local] = 10 ether;
    }
    // Sanity check: assuming the multipath is > 1, no router should need to have more than half of the
    // transfer amount.
    s.routerBalances[args.routers[0]][args.local] = 0.5 ether;

    uint256 amount = utils_getFastTransferAmount(args.amount);
    uint256 routerAmountSent = amount / pathLength; // The amount each individual router will send.

    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    helpers_executeAndAssert(transferId, args);
  }

  // should work with approved router if router ownership is not renounced
  function test_BridgeFacet__execute_worksWithAgentAsSender() public {
    address agent = address(12345654321);
    _params.agent = agent;
    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    s.routerBalances[args.routers[0]][args.local] += 10 ether;
    s.routerPermissionInfo.approvedRouters[args.routers[0]] = true;

    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    s.approvedRelayers[address(this)] = false;
    helpers_executeAndAssert(transferId, args, true);
  }

  // can use liquidity from portals
  function test_BridgeFacet__execute_worksWithAave() public {
    // set asset context (local == adopted)
    utils_setupAsset(true, false);

    (bytes32 transferId, ExecuteArgs memory args) = utils_makeExecuteArgs(1);

    // set liquidity
    s.routerBalances[args.routers[0]][args.local] = 0;

    // set approval
    s.routerPermissionInfo.approvedForPortalRouters[args.routers[0]] = true;

    helpers_executeAndAssert(
      transferId,
      args,
      utils_getFastTransferAmount(args.amount),
      false,
      true,
      false,
      true,
      false
    );
  }

  // ============ bumpTransfer ============
  // ============ bumpTransfer fail cases

  // should work with unapproved router if router-whitelist ownership renouncedcanonicalId
}
