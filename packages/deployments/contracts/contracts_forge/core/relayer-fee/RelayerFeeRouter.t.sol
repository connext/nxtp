// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Home} from "../../../contracts/nomad-core/contracts/Home.sol";
import {TypedMemView, RelayerFeeMessage, RelayerFeeRouter} from "../../../contracts/core/relayer-fee/RelayerFeeRouter.sol";
import {ProposedOwnable} from "../../../contracts/core/shared/ProposedOwnable.sol";

import {MockHome, MockConnext} from "../../utils/Mock.sol";
import "../../utils/ForgeHelper.sol";

contract RelayerFeeRouterTest is ForgeHelper {
  using TypedMemView for bytes;
  using TypedMemView for bytes29;
  using RelayerFeeMessage for bytes29;

  // ============ Libraries ============
  using stdStorage for StdStorage;

  event Send(uint32 domain, address recipient, bytes32[] transferIds, bytes32 remote, bytes message);

  event Receive(uint64 indexed originAndNonce, uint32 indexed origin, address indexed recipient, bytes32[] transferIds);

  event SetConnext(address indexed connext);

  // ============ Storage ============

  RelayerFeeRouter relayerFeeRouter;
  RelayerFeeRouter relayerFeeRouterImplementation;
  ERC1967Proxy proxy;

  uint256 domain = 1;
  address bridgeRouter = address(1);
  address tokenRegistry = address(2);

  address internal xAppConnectionManager = address(1);
  address internal home;
  MockConnext internal connext;
  address internal connext2 = address(3);
  address internal recipient = address(4);
  bytes32 internal remote = "remote";
  uint32 internal localDomain = uint32(123);
  uint32 internal remoteDomain = uint32(1);

  // ============ Test set up ============

  function setUp() public {
    connext = new MockConnext();
    home = address(new MockHome());
    vm.mockCall(xAppConnectionManager, abi.encodeWithSignature("home()"), abi.encode(home));
    vm.mockCall(xAppConnectionManager, abi.encodeWithSignature("isReplica(address)"), abi.encode(bool(true)));
    vm.mockCall(home, abi.encodeWithSignature("localDomain()"), abi.encode(localDomain));

    relayerFeeRouterImplementation = new RelayerFeeRouter();

    proxy = new ERC1967Proxy(
      address(relayerFeeRouterImplementation),
      abi.encodeWithSelector(RelayerFeeRouter.initialize.selector, xAppConnectionManager)
    );

    relayerFeeRouter = RelayerFeeRouter(payable(address(proxy)));
    relayerFeeRouter.setConnext(address(connext));

    // Shouldn't enrollRemoteRouter be protected by onlyOwner?
    relayerFeeRouter.enrollRemoteRouter(remoteDomain, bytes32(remote));
  }

  // ============ initialize ============
  function test_RelayerFeeRouter__initialize_setParameters() public {
    assertEq(address(relayerFeeRouter.xAppConnectionManager()), address(xAppConnectionManager));
    assertEq(address(relayerFeeRouter.connext()), address(connext));
  }

  // ============ setConnext ============

  // Should work
  function test_RelayerFeeRouter__setConnext_works() public {
    vm.expectEmit(true, true, true, true);
    emit SetConnext(connext2);

    relayerFeeRouter.setConnext(connext2);
    assertEq(address(relayerFeeRouter.connext()), connext2);
  }

  // Fail if not called by owner
  function test_RelayerFeeRouter__setConnext_failsIfNotOwner() public {
    vm.prank(address(0));
    vm.expectRevert(abi.encodeWithSelector(ProposedOwnable.ProposedOwnable__onlyOwner_notOwner.selector));
    relayerFeeRouter.setConnext(connext2);
  }

  // ============ send ============
  // Fail if not called by connext
  function test_RelayerFeeRouter__send_failsIfNotConnext() public {
    vm.prank(address(0));
    vm.expectRevert(abi.encodeWithSelector(RelayerFeeRouter.RelayerFeeRouter__onlyConnext_notConnext.selector));

    bytes32[] memory transferIds = new bytes32[](2);
    transferIds[0] = "AAA";
    transferIds[1] = "BBB";

    relayerFeeRouter.send(remoteDomain, recipient, transferIds);
  }

  // Fail if no transaction ids
  function test_RelayerFeeRouter__send_failsIfEmptyTransactionIds() public {
    vm.prank(address(connext));
    vm.expectRevert(abi.encodeWithSelector(RelayerFeeRouter.RelayerFeeRouter__send_claimEmpty.selector));

    bytes32[] memory transferIds = new bytes32[](0);

    relayerFeeRouter.send(remoteDomain, recipient, transferIds);
  }

  // Fail if empty recipient
  function test_RelayerFeeRouter__send_failsIfEmptyRecipient() public {
    vm.prank(address(connext));
    vm.expectRevert(abi.encodeWithSelector(RelayerFeeRouter.RelayerFeeRouter__send_recipientEmpty.selector));

    bytes32[] memory transferIds = new bytes32[](2);
    transferIds[0] = "AAA";
    transferIds[1] = "BBB";

    relayerFeeRouter.send(remoteDomain, address(0), transferIds);
  }

  // Should work
  function test_RelayerFeeRouter__send_works(bytes32[] calldata _transferIds) public {
    vm.prank(address(connext));
    vm.assume(_transferIds.length != 0);
    bytes memory message = RelayerFeeMessage.formatClaimFees(recipient, _transferIds);

    vm.expectCall(home, abi.encodeWithSelector(MockHome.dispatch.selector, remoteDomain, remote, message));
    vm.expectEmit(true, true, true, true);
    emit Send(remoteDomain, recipient, _transferIds, remote, message);

    relayerFeeRouter.send(remoteDomain, recipient, _transferIds);
  }

  // ============ handle ============
  // Should work
  function test_RelayerFeeRouter__handle_works(bytes32[] calldata _transferIds, uint32 _nonce) public {
    vm.assume(_transferIds.length != 0);
    uint64 originAndNonce = (uint64(remoteDomain) << 32) | _nonce;
    bytes memory message = RelayerFeeMessage.formatClaimFees(recipient, _transferIds);

    vm.expectCall(address(connext), abi.encodeWithSelector(MockConnext.claim.selector, recipient, _transferIds));

    vm.expectEmit(true, true, true, true);
    emit Receive(originAndNonce, remoteDomain, recipient, _transferIds);

    relayerFeeRouter.handle(remoteDomain, _nonce, remote, message);
  }
}
