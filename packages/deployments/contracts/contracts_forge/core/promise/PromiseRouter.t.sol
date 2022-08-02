// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {XAppConnectionManager} from "../../../contracts/nomad-core/contracts/XAppConnectionManager.sol";
import {Home} from "../../../contracts/nomad-core/contracts/Home.sol";

import "../../utils/ForgeHelper.sol";

import {TypedMemView, PromiseMessage, PromiseRouter, AddressUpgradeable} from "../../../contracts/core/promise/PromiseRouter.sol";
import {ProposedOwnable} from "../../../contracts/core/shared/ProposedOwnable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Deployer} from "../../utils/Deployer.sol";
import {IConnextHandler} from "../../../contracts/core/connext/interfaces/IConnextHandler.sol";
import {ICallback} from "../../../contracts/core/promise/interfaces/ICallback.sol";
import {BaseConnextFacet} from "../../../contracts/core/connext/facets/BaseConnextFacet.sol";

import {MockHome, MockCallback, MockPromiseRouter, TestSetterFacet, MockXAppConnectionManager} from "../../utils/Mock.sol";

contract PromiseRouterTest is ForgeHelper, PromiseRouter {
  // ============ Libraries ============

  using TypedMemView for bytes;
  using TypedMemView for bytes29;
  using PromiseMessage for bytes29;

  // ============ Storage ============

  address _xAppConnectionManager = address(1);
  address _connext = address(2);
  address _xAppHome = address(3);
  address _callback;

  uint32 _domain = 1000;
  bytes32 _remote = bytes32(abi.encode(address(4)));

  bytes32 _transferId = bytes32("id");

  PromiseRouter public promiseRouter;

  // ============ Test set up ============

  function setUp() public {
    PromiseRouter promiseRouterImpl = new PromiseRouter();

    // Deploy a mock home.
    _xAppHome = address(new MockHome());
    // Deploy a mock xapp connection manager.
    _xAppConnectionManager = address(new MockXAppConnectionManager(MockHome(_xAppHome)));

    ERC1967Proxy proxy = new ERC1967Proxy(
      address(promiseRouterImpl),
      abi.encodeWithSelector(PromiseRouter.initialize.selector, _xAppConnectionManager)
    );

    promiseRouter = PromiseRouter(payable(address(proxy)));
    promiseRouter.setConnext(_connext);

    // enroll router
    vm.prank(promiseRouter.owner());
    promiseRouter.enrollRemoteRouter(_domain, _remote);

    // deploy callback
    _callback = address(new MockCallback());
  }

  // ============ Utils ============
  function utils_formatPromiseCallback(bool _returnSuccess, bytes memory _returnData) internal returns (bytes memory) {
    return
      abi.encodePacked(
        uint8(PromiseMessage.Types.PromiseCallback),
        _transferId,
        _callback,
        uint8(_returnSuccess ? 1 : 0),
        _returnData.length,
        _returnData
      );
  }

  // ============ initialize ============
  function test_PromiseRouter__initializeParameters_shouldWork() public {
    assertEq(address(promiseRouter.xAppConnectionManager()), _xAppConnectionManager);
  }

  // ============ setConnext ============
  // fixme: move to ProposedOwnable.t.sol
  function test_PromiseRouter__setConnext_failsIfNotOwner() public {
    address updated = address(1234);

    vm.expectRevert(ProposedOwnable.ProposedOwnable__onlyOwner_notOwner.selector);
    vm.prank(updated);
    promiseRouter.setConnext(updated);
  }

  // Should work
  function test_PromiseRouter__setConnext_shouldWork() public {
    address updated = address(1234);
    vm.expectEmit(true, true, true, true);
    emit SetConnext(updated);

    vm.prank(promiseRouter.owner());
    promiseRouter.setConnext(updated);
    assertEq(address(promiseRouter.connext()), updated);
  }

  // ============ setReserveGas ============
  function test_PromiseRouter__setReserveGas_failsIfNotOwner() public {
    uint256 updated = 1234;

    vm.expectRevert(ProposedOwnable.ProposedOwnable__onlyOwner_notOwner.selector);
    vm.prank(address(1234));
    promiseRouter.setReserveGas(updated);
  }

  // Should work
  function test_PromiseRouter__setReserveGas_shouldWork() public {
    uint256 updated = 1234;
    vm.expectEmit(true, true, true, true);
    emit ReserveGasSet(promiseRouter.RESERVE_GAS(), updated);

    vm.prank(promiseRouter.owner());
    promiseRouter.setReserveGas(updated);
    assertEq(promiseRouter.RESERVE_GAS(), updated);
  }

  // ============ send ============
  // Fail if not called by connext
  function test_PromiseRouter__send_failsIfNotConnext(bool returnSuccess, bytes calldata returnData) public {
    vm.assume(returnData.length != 0);
    vm.prank(address(0));
    vm.expectRevert(abi.encodeWithSelector(PromiseRouter.PromiseRouter__onlyConnext_notConnext.selector));

    promiseRouter.send(_domain, _transferId, _callback, returnSuccess, returnData);
  }

  // Fail if callback address is not contract
  function test_PromiseRouter__send_failsIfEmptyCallback(bool returnSuccess, bytes calldata returnData) public {
    vm.assume(returnData.length != 0);
    vm.prank(_connext);
    vm.expectRevert(abi.encodeWithSelector(PromiseRouter.PromiseRouter__send_callbackEmpty.selector));

    promiseRouter.send(_domain, _transferId, address(0), returnSuccess, returnData);
  }

  // fails if no remote
  function test_PromiseRouter__send_failsIfNoRemote(bool returnSuccess, bytes calldata returnData) public {
    vm.assume(returnData.length != 0);

    // enroll router
    vm.prank(promiseRouter.owner());
    promiseRouter.enrollRemoteRouter(_domain, bytes32(0));

    vm.prank(_connext);
    vm.expectRevert(bytes("!remote"));

    promiseRouter.send(_domain, _transferId, _callback, returnSuccess, returnData);
  }

  // Should work
  function test_PromiseRouter__send_shouldWork(bool returnSuccess, bytes calldata returnData) public {
    vm.prank(_connext);
    vm.assume(returnData.length != 0);

    bytes memory message = PromiseMessage.formatPromiseCallback(_transferId, _callback, returnSuccess, returnData);

    vm.expectCall(_xAppHome, abi.encodeWithSelector(MockHome.dispatch.selector, _domain, _remote, message));
    vm.expectEmit(true, true, true, true);
    emit Send(_domain, _remote, _transferId, _callback, returnSuccess, returnData, message);

    promiseRouter.send(_domain, _transferId, _callback, returnSuccess, returnData);
  }

  // Should work if empty return data
  function test_PromiseRouter__send_shouldWorkIfEmptyReturnData(bool returnSuccess, bytes calldata returnData) public {
    vm.assume(returnData.length == 0);
    vm.prank(_connext);

    bytes memory message = PromiseMessage.formatPromiseCallback(_transferId, _callback, returnSuccess, returnData);
    vm.expectCall(_xAppHome, abi.encodeWithSelector(MockHome.dispatch.selector, _domain, _remote, message));
    vm.expectEmit(true, true, true, true);
    emit Send(_domain, _remote, _transferId, _callback, returnSuccess, returnData, message);

    promiseRouter.send(_domain, _transferId, _callback, returnSuccess, returnData);
  }

  // ============ handle ============
  // NOTE: modifiers are in the nomad contracts, tested separately

  // should fail if the message is not a promise callback
  function test_PromiseRouter__handle_failsIfMalformedMessage(bytes calldata returnData, uint32 nonce) public {
    vm.assume(returnData.length != 0);

    uint64 originAndNonce = _originAndNonce(_domain, nonce);

    // register as replica
    vm.mockCall(
      _xAppConnectionManager,
      abi.encodeWithSelector(XAppConnectionManager.isReplica.selector, address(this)),
      abi.encode(true)
    );

    bytes memory _message = bytes("msg");
    vm.expectRevert(bytes("Validity assertion failed"));
    promiseRouter.handle(_domain, nonce, _remote, _message);
  }

  // Should work
  // bytes calldata returnData, uint32 _nonce
  function test_PromiseRouter__handle_shouldWork(
    bytes calldata returnData,
    uint32 nonce,
    bool success
  ) public {
    vm.assume(returnData.length != 0);

    uint64 originAndNonce = _originAndNonce(_domain, nonce);

    bytes memory message = utils_formatPromiseCallback(success, returnData);
    bytes29 _msg = message.ref(0).mustBePromiseCallback();

    // register as replica
    vm.mockCall(
      _xAppConnectionManager,
      abi.encodeWithSelector(XAppConnectionManager.isReplica.selector, address(this)),
      abi.encode(true)
    );

    vm.expectEmit(true, true, true, true);
    emit Receive(originAndNonce, _domain, _transferId, _callback, success, returnData, message);

    promiseRouter.handle(_domain, nonce, _remote, message);
    assertEq(promiseRouter.messageHashes(_transferId), _msg.keccak());
  }

  // ============ process ============
  // fails if no message present for transfer
  function test_PromiseRouter__process_failsIfNoMessage(bytes calldata returnData, uint32 nonce) public {
    vm.assume(returnData.length != 0);
    bool success = true;
    bytes memory message = utils_formatPromiseCallback(success, returnData);
    // mock relayer approval
    vm.mockCall(_connext, abi.encodeWithSelector(IConnextHandler.approvedRelayers.selector), abi.encode(true));

    vm.expectRevert(PromiseRouter.PromiseRouter__process_invalidTransferId.selector);
    promiseRouter.process(_transferId, message);
  }

  // fails if invalid message provided
  function test_PromiseRouter__process_failsIfInvalidMessage(bytes calldata returnData, uint32 nonce) public {
    vm.assume(returnData.length != 0);
    bool success = true;
    bytes memory message = utils_formatPromiseCallback(success, returnData);
    bytes29 _msg = message.ref(0).mustBePromiseCallback();

    // mock is replica result for handle
    vm.mockCall(
      _xAppConnectionManager,
      abi.encodeWithSelector(XAppConnectionManager.isReplica.selector),
      abi.encode(true)
    );

    promiseRouter.handle(_domain, nonce, _remote, message);
    assertEq(promiseRouter.messageHashes(_transferId), _msg.keccak());

    // mock relayer approval
    vm.mockCall(_connext, abi.encodeWithSelector(IConnextHandler.approvedRelayers.selector), abi.encode(true));

    vm.expectRevert(bytes("Validity assertion failed"));
    promiseRouter.process(_transferId, bytes(""));
  }

  // Fail if relayer is not approved on connext contract
  function test_PromiseRouter__process_failsIfNotApprovedRelayer(bytes calldata returnData, uint32 nonce) public {
    vm.assume(returnData.length != 0);
    bool success = true;
    bytes memory message = utils_formatPromiseCallback(success, returnData);
    bytes29 _msg = message.ref(0).mustBePromiseCallback();

    // mock is replica result for handle
    vm.mockCall(
      _xAppConnectionManager,
      abi.encodeWithSelector(XAppConnectionManager.isReplica.selector),
      abi.encode(true)
    );

    promiseRouter.handle(_domain, nonce, _remote, message);
    assertEq(promiseRouter.messageHashes(_transferId), _msg.keccak());

    // mock relayer approval
    vm.mockCall(_connext, abi.encodeWithSelector(IConnextHandler.approvedRelayers.selector), abi.encode(false));

    vm.expectRevert(PromiseRouter.PromiseRouter__process_notApprovedRelayer.selector);
    vm.prank(address(123123123));
    promiseRouter.process(_transferId, message);
  }

  // fails if callback is not a contract
  function test_PromiseRouter__process_failsIfNotContract(bytes calldata returnData, uint32 nonce) public {
    vm.assume(returnData.length != 0);
    _callback = address(12344321);
    bool success = true;
    bytes memory message = utils_formatPromiseCallback(success, returnData);
    bytes29 _msg = message.ref(0).mustBePromiseCallback();

    // mock is replica result for handle
    vm.mockCall(
      _xAppConnectionManager,
      abi.encodeWithSelector(XAppConnectionManager.isReplica.selector),
      abi.encode(true)
    );

    promiseRouter.handle(_domain, nonce, _remote, message);
    assertEq(promiseRouter.messageHashes(_transferId), _msg.keccak());

    // mock relayer approval
    vm.mockCall(_connext, abi.encodeWithSelector(IConnextHandler.approvedRelayers.selector), abi.encode(true));

    vm.expectRevert(PromiseRouter.PromiseRouter__process_notContractCallback.selector);
    promiseRouter.process(_transferId, message);
  }

  // Should work if callback fee is zero
  function test_PromiseRouter__process_shouldWorkIfZeroCallbackFee(bytes calldata returnData, uint32 nonce) public {
    vm.assume(returnData.length != 0);
    bool success = true;
    bytes memory message = utils_formatPromiseCallback(success, returnData);
    bytes29 _msg = message.ref(0).mustBePromiseCallback();

    uint256 callbackFee = 0;

    uint256 relayerBeforeBalance = address(this).balance;
    uint256 beforeBalance = address(promiseRouter).balance;

    // mock is replica result for handle
    vm.mockCall(
      _xAppConnectionManager,
      abi.encodeWithSelector(XAppConnectionManager.isReplica.selector),
      abi.encode(true)
    );

    promiseRouter.handle(_domain, nonce, _remote, message);
    assertEq(promiseRouter.messageHashes(_transferId), _msg.keccak());

    // mock relayer approval
    vm.mockCall(_connext, abi.encodeWithSelector(IConnextHandler.approvedRelayers.selector), abi.encode(true));

    // check if callback executed
    vm.expectCall(_callback, abi.encodeWithSelector(ICallback.callback.selector, _transferId, success, returnData));

    vm.expectEmit(true, true, true, true);
    emit CallbackExecuted(_transferId, true, address(this));

    promiseRouter.process(_transferId, message);

    // check if promiseMessage cleared after callback
    assertEq(promiseRouter.messageHashes(_transferId), bytes32(0));

    // check if callbackFee cleared after callback
    assertTrue(promiseRouter.callbackFees(_transferId) == 0);

    // check if callback fee is transferred to relayer
    assertEq(address(this).balance, relayerBeforeBalance + callbackFee);
    assertEq(address(promiseRouter).balance, beforeBalance - callbackFee);
  }

  // Should work if callback fee is nonzero
  function test_PromiseRouter__process_shouldWork(bytes calldata returnData, uint32 nonce) public {
    vm.assume(returnData.length != 0);
    bool success = true;
    bytes memory message = utils_formatPromiseCallback(success, returnData);
    bytes29 _msg = message.ref(0).mustBePromiseCallback();

    uint256 callbackFee = 0.01 ether;
    vm.deal(address(promiseRouter), 10 ether);

    address relayer = address(123456654321);
    uint256 relayerBeforeBalance = relayer.balance;

    // mock is replica result for handle
    vm.mockCall(
      _xAppConnectionManager,
      abi.encodeWithSelector(XAppConnectionManager.isReplica.selector),
      abi.encode(true)
    );

    promiseRouter.handle(_domain, nonce, _remote, message);
    assertEq(promiseRouter.messageHashes(_transferId), _msg.keccak());

    // bump fee
    promiseRouter.bumpCallbackFee{value: callbackFee}(_transferId);
    uint256 beforeBalance = address(promiseRouter).balance;

    // force callback failure
    MockCallback(_callback).shouldFail(true);
    assertTrue(MockCallback(_callback).fails());

    // mock relayer approval
    vm.mockCall(_connext, abi.encodeWithSelector(IConnextHandler.approvedRelayers.selector), abi.encode(true));

    // check if callback executed
    vm.expectCall(_callback, abi.encodeWithSelector(ICallback.callback.selector, _transferId, success, returnData));

    vm.expectEmit(true, true, true, true);
    emit CallbackExecuted(_transferId, false, relayer);

    vm.prank(relayer);
    promiseRouter.process(_transferId, message);

    // check if promiseMessage cleared after callback
    assertEq(promiseRouter.messageHashes(_transferId), bytes32(0));

    // check if callbackFee cleared after callback
    assertTrue(promiseRouter.callbackFees(_transferId) == 0);

    // check if callback fee is transferred to relayer
    assertEq(relayer.balance, relayerBeforeBalance + callbackFee);
    assertEq(address(promiseRouter).balance, beforeBalance - callbackFee);
  }

  // Should work if callback fails
  function test_PromiseRouter__process_failingCallbackShouldWork(bytes calldata returnData, uint32 nonce) public {
    vm.assume(returnData.length != 0);
    bool success = true;
    bytes memory message = utils_formatPromiseCallback(success, returnData);
    bytes29 _msg = message.ref(0).mustBePromiseCallback();

    uint256 callbackFee = 0.01 ether;
    vm.deal(address(promiseRouter), 10 ether);

    address relayer = address(123456654321);
    uint256 relayerBeforeBalance = relayer.balance;

    // mock is replica result for handle
    vm.mockCall(
      _xAppConnectionManager,
      abi.encodeWithSelector(XAppConnectionManager.isReplica.selector),
      abi.encode(true)
    );

    promiseRouter.handle(_domain, nonce, _remote, message);
    assertEq(promiseRouter.messageHashes(_transferId), _msg.keccak());

    // bump fee
    promiseRouter.bumpCallbackFee{value: callbackFee}(_transferId);
    uint256 beforeBalance = address(promiseRouter).balance;

    // mock relayer approval
    vm.mockCall(_connext, abi.encodeWithSelector(IConnextHandler.approvedRelayers.selector), abi.encode(true));

    // check if callback executed
    vm.expectCall(_callback, abi.encodeWithSelector(ICallback.callback.selector, _transferId, success, returnData));

    vm.expectEmit(true, true, true, true);
    emit CallbackExecuted(_transferId, true, relayer);

    vm.prank(relayer);
    promiseRouter.process(_transferId, message);

    // check if promiseMessage cleared after callback
    assertEq(promiseRouter.messageHashes(_transferId), bytes32(0));

    // check if callbackFee cleared after callback
    assertTrue(promiseRouter.callbackFees(_transferId) == 0);

    // check if callback fee is transferred to relayer
    assertEq(relayer.balance, relayerBeforeBalance + callbackFee);
    assertEq(address(promiseRouter).balance, beforeBalance - callbackFee);
  }

  // ============ initCallbackFee ============
  // Fail if not called by connext
  function test_PromiseRouter__initCallbackFee_failsIfNotConnext() public {
    vm.expectRevert(PromiseRouter.PromiseRouter__onlyConnext_notConnext.selector);
    vm.prank(address(123321456654));
    promiseRouter.initCallbackFee(_transferId);
  }

  // Fail if value is zero
  function test_PromiseRouter__initCallbackFee_failsIfZeroValue() public {
    vm.expectRevert(PromiseRouter.PromiseRouter__initCallbackFee_valueIsZero.selector);
    vm.prank(_connext);
    promiseRouter.initCallbackFee(_transferId);
  }

  // Works
  function test_PromiseRouter__initCallbackFee_works() public {
    uint256 fee = 0.01 ether;
    uint256 init = address(promiseRouter).balance;
    vm.deal(address(promiseRouter.connext()), 10 ether);

    vm.expectEmit(true, true, true, true);
    emit CallbackFeeAdded(_transferId, fee, fee, _connext);

    vm.prank(address(promiseRouter.connext()));
    promiseRouter.initCallbackFee{value: fee}(_transferId);
    assertEq(promiseRouter.callbackFees(_transferId), fee);
    assertEq(address(promiseRouter).balance, init + fee);
  }

  // ============ bumpCallbackFee ============
  // Fail if value is zero
  function test_PromiseRouter__bumpCallbackFee_failsIfZeroValue(bytes calldata returnData, uint32 nonce) public {
    vm.expectRevert(PromiseRouter.PromiseRouter__bumpCallbackFee_valueIsZero.selector);
    promiseRouter.bumpCallbackFee(_transferId);
  }

  // Should fail if message isnt handled
  function test_PromiseRouter__bumpCallbackFee_shouldFailIfMessageNotHandled(bytes calldata returnData, uint32 nonce)
    public
  {
    vm.expectRevert(PromiseRouter.PromiseRouter__bumpCallbackFee_messageUnavailable.selector);
    promiseRouter.bumpCallbackFee{value: 0.01 ether}(_transferId);
  }

  // Should work
  function test_PromiseRouter__bumpCallbackFee_shouldWork(bytes calldata returnData, uint32 nonce) public {
    vm.assume(returnData.length != 0);
    bool success = true;
    bytes memory message = utils_formatPromiseCallback(success, returnData);
    bytes29 _msg = message.ref(0).mustBePromiseCallback();

    uint256 callbackFee = 0;

    uint256 relayerBeforeBalance = address(this).balance;
    uint256 beforeBalance = address(promiseRouter).balance;

    // mock is replica result for handle
    vm.mockCall(
      _xAppConnectionManager,
      abi.encodeWithSelector(XAppConnectionManager.isReplica.selector),
      abi.encode(true)
    );

    promiseRouter.handle(_domain, nonce, _remote, message);
    assertEq(promiseRouter.messageHashes(_transferId), _msg.keccak());

    uint256 initial = promiseRouter.callbackFees(_transferId);
    uint256 amount = 0.5 ether;

    vm.expectEmit(true, true, true, true);
    emit CallbackFeeAdded(_transferId, amount, amount + initial, address(this));
    promiseRouter.bumpCallbackFee{value: amount}(_transferId);

    assertEq(promiseRouter.callbackFees(_transferId), initial + amount);
  }
}
