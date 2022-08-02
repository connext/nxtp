// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {XAppConnectionManager} from "../contracts/nomad-core/contracts/XAppConnectionManager.sol";
import {TypeCasts} from "../contracts/nomad-core/libs/TypeCasts.sol";

import {TokenId} from "../contracts/core/connext/libraries/LibConnextStorage.sol";

import {IConnextHandler} from "../contracts/core/connext/interfaces/IConnextHandler.sol";
import {ITokenRegistry} from "../contracts/core/connext/interfaces/ITokenRegistry.sol";
import {IBridgeRouter} from "../contracts/core/connext/interfaces/IBridgeRouter.sol";

import "../contracts/core/connext/facets/BridgeFacet.sol";

import {LPToken} from "../contracts/core/connext/helpers/LPToken.sol";

import {PromiseRouter} from "../contracts/core/promise/PromiseRouter.sol";

import {RelayerFeeRouter} from "../contracts/core/relayer-fee/RelayerFeeRouter.sol";
import {RelayerFeeMessage} from "../contracts/core/relayer-fee/libraries/RelayerFeeMessage.sol";

import {TestERC20} from "../contracts/test/TestERC20.sol";
import {TokenRegistry} from "../contracts/test/TokenRegistry.sol";
import {BridgeMessage} from "../contracts/test/BridgeMessage.sol";

import {WETH} from "./utils/TestWeth.sol";
import "./utils/ForgeHelper.sol";
import "./utils/Mock.sol";
import "./utils/Deployer.sol";

// Holds all balances that are impacted by an xcall
struct XCallBalances {
  uint256 bridgeTransacting;
  uint256 bridgeLocal;
  uint256 bridgeNative;
  uint256 callerTransacting;
  uint256 callerNative;
}

// Holds all balances that are impacted by an execute
struct ExecuteBalances {
  uint256 bridgeLocal;
  uint256 bridgeReceiving; // local -or- adopted
  uint256[] liquidity;
  uint256 toReceiving; // local -or- adopted
}

// Holds all balances that are impacted by a reconcile
struct ReconcileBalances {
  uint256[] liquidity;
  uint256 portalDebt;
  uint256 portalFeeDebt;
}

contract ConnextTest is ForgeHelper, Deployer {
  // ============ Events ============
  event XCalled(
    bytes32 indexed transferId,
    uint256 indexed nonce,
    XCallArgs xcallArgs,
    address bridgedAsset,
    uint256 bridgedAmount,
    address caller
  );

  event Executed(
    bytes32 indexed transferId,
    address indexed to,
    ExecuteArgs args,
    address transactingAsset,
    uint256 transactingAmount,
    address caller
  );

  event Reconciled(bytes32 indexed transferId, address[] routers, address asset, uint256 amount, address caller);

  event TransferRelayerFeesUpdated(bytes32 indexed transferId, uint256 relayerFee, address caller);

  event InitiatedClaim(uint32 indexed domain, address indexed recipient, address caller, bytes32[] transferIds);

  event Claimed(address indexed recipient, uint256 total, bytes32[] transferIds);

  event XSendCalled(address _token, uint256 _amount, uint32 _destination, bytes32 _externalId);

  // ============ Storage ============
  // ============ Config
  uint32 _origin = 1111;
  uint32 _destination = 2221;
  uint32 _other = 3331;

  address _destinationBridgeRouter;
  address _originBridgeRouter;

  // ============ Assets
  address _canonical;
  uint32 _canonicalDomain;
  bytes32 _canonicalKey;

  address _originLocal;
  address _originAdopted;
  address _originLp; // deployed IFF pool init-d

  address _destinationLocal;
  address _destinationAdopted;
  address _destinationLp; // deployed IFF pool init-d

  // ============ XAppConnectionManager
  XAppConnectionManager _originManager;
  XAppConnectionManager _destinationManager;

  // ============ TokenRegistry
  TokenRegistry _originRegistry;
  TokenRegistry _destinationRegistry;

  // ============ Promise router
  PromiseRouter _originPromise;
  PromiseRouter _destinationPromise;

  // ============ Relayer fee router
  RelayerFeeRouter _originRelayerFee;
  RelayerFeeRouter _destinationRelayerFee;

  // ============ Connext
  IConnextHandler _originConnext;
  IConnextHandler _destinationConnext;

  // ============ Payable ============
  receive() external payable {}

  // ============ Test set up ============
  function setUp() public {
    // Deploy all the contracts
    utils_deployAssets();
    utils_deployNomad();
    utils_deployConnext();
  }

  // ============ Utils ============

  function utils_deployAssets() public {
    // deploy tokens
    _canonical = address(new TestERC20("Test Token", "TEST"));
    _originLocal = address(new TestERC20("Test Token", "TEST"));
    _originAdopted = address(new TestERC20("Test Token", "TEST"));
    _destinationLocal = address(new TestERC20("Test Token", "TEST"));
    _destinationAdopted = address(new TestERC20("Test Token", "TEST"));
  }

  function utils_deployNomad() public {
    // Deploy mock home
    MockHome home = new MockHome();
    // Deploy origin XAppConnectionManager
    _originManager = new XAppConnectionManager();
    // Deploy destination XAppConnectionManager
    _destinationManager = new XAppConnectionManager();
    // set homes
    _originManager.setHome(address(home));
    _destinationManager.setHome(address(home));

    // Deploy token beacon
    address beacon = address(new TestERC20("Test Token", "TEST"));

    // Deploy TokenRegistry implementation
    TokenRegistry registryImp = new TokenRegistry();
    // Deploy origin TokenRegistry
    ERC1967Proxy originProxy = new ERC1967Proxy(
      address(registryImp),
      abi.encodeWithSelector(TokenRegistry.initialize.selector, beacon, address(_originManager))
    );
    _originRegistry = TokenRegistry(address(originProxy));
    // Deploy destination TokenRegistry
    ERC1967Proxy destinationProxy = new ERC1967Proxy(
      address(registryImp),
      abi.encodeWithSelector(TokenRegistry.initialize.selector, beacon, address(_destinationManager))
    );
    _destinationRegistry = TokenRegistry(address(destinationProxy));
    // set local domains
    _originRegistry.setLocalDomain(_origin);
    _destinationRegistry.setLocalDomain(_destination);

    // deploy bridge routers
    _destinationBridgeRouter = address(new MockBridgeRouter());
    _originBridgeRouter = address(new MockBridgeRouter());

    // set this to be a replica so we can call `handle` directly on routers
    _destinationManager.ownerEnrollReplica(address(this), _origin);
    _originManager.ownerEnrollReplica(address(this), _destination);
  }

  function utils_deployPromiseRouter() public {
    // Deploy promise router (origin + destination)
    PromiseRouter promiseRouterImpl = new PromiseRouter();

    ERC1967Proxy originProxy = new ERC1967Proxy(
      address(promiseRouterImpl),
      abi.encodeWithSelector(PromiseRouter.initialize.selector, address(_originManager))
    );
    _originPromise = PromiseRouter(payable(address(originProxy)));

    ERC1967Proxy destinationProxy = new ERC1967Proxy(
      address(promiseRouterImpl),
      abi.encodeWithSelector(PromiseRouter.initialize.selector, _destinationManager)
    );
    _destinationPromise = PromiseRouter(payable(address(destinationProxy)));

    // enroll remotes
    _originPromise.enrollRemoteRouter(_destination, TypeCasts.addressToBytes32(address(_destinationPromise)));
    _destinationPromise.enrollRemoteRouter(_origin, TypeCasts.addressToBytes32(address(_originPromise)));
  }

  function utils_deployRelayerFeeRouter() public {
    // Deploy promise router (origin + destination)
    RelayerFeeRouter impl = new RelayerFeeRouter();

    ERC1967Proxy originProxy = new ERC1967Proxy(
      address(impl),
      abi.encodeWithSelector(RelayerFeeRouter.initialize.selector, address(_originManager))
    );
    _originRelayerFee = RelayerFeeRouter(payable(address(originProxy)));

    ERC1967Proxy destinationProxy = new ERC1967Proxy(
      address(impl),
      abi.encodeWithSelector(PromiseRouter.initialize.selector, _destinationManager)
    );
    _destinationRelayerFee = RelayerFeeRouter(payable(address(destinationProxy)));

    // enroll remotes
    _originRelayerFee.enrollRemoteRouter(_destination, TypeCasts.addressToBytes32(address(_destinationRelayerFee)));
    _destinationRelayerFee.enrollRemoteRouter(_origin, TypeCasts.addressToBytes32(address(_originRelayerFee)));
  }

  function utils_deployConnext() public {
    // deploy promise router
    utils_deployPromiseRouter();
    // deploy relayer fee router
    utils_deployRelayerFeeRouter();

    // deploy connext
    address originConnext = deployConnext(
      _origin,
      address(_originManager),
      address(_originRegistry),
      address(_originRelayerFee),
      payable(address(_originPromise))
    );
    _originConnext = IConnextHandler(originConnext);

    address destinationConnext = deployConnext(
      _destination,
      address(_destinationManager),
      address(_destinationRegistry),
      address(_destinationRelayerFee),
      payable(address(_destinationPromise))
    );
    _destinationConnext = IConnextHandler(destinationConnext);

    // enroll bridge router (so we can call `reconcile` directly)
    _originConnext.setBridgeRouter(_originBridgeRouter);
    _destinationConnext.setBridgeRouter(_destinationBridgeRouter);

    // whitelist contract as router
    _originConnext.addRelayer(address(this));
    _destinationConnext.addRelayer(address(this));

    // set connext on relayer contracts
    _originRelayerFee.setConnext(address(_originConnext));
    _originPromise.setConnext(address(_originConnext));
    _destinationRelayerFee.setConnext(address(_destinationConnext));
    _destinationPromise.setConnext(address(_destinationConnext));

    // enroll instances
    _originConnext.addConnextion(_destination, address(_destinationConnext));
    _destinationConnext.addConnextion(_origin, address(_originConnext));
  }

  function utils_setupAssets(uint32 canonicalDomain, bool localIsAdopted) public {
    bytes32 canonicalId = TypeCasts.addressToBytes32(_canonical);
    _canonicalDomain = canonicalDomain;
    _canonicalKey = keccak256(abi.encode(canonicalId, _canonicalDomain));

    if (_origin == canonicalDomain) {
      // The canonical domain is the origin, meaning any local
      // assets on the origin should be the canonical
      _originLocal = _canonical;
      _originAdopted = _canonical;
    } else if (_destination == canonicalDomain) {
      _destinationLocal = _canonical;
      _destinationAdopted = _canonical;
    } // otherwise, could be anything

    // Handle origin
    if (_origin != canonicalDomain) {
      _originRegistry.enrollCustom(canonicalDomain, canonicalId, _originLocal);
    }
    // Setup asset whitelist
    if (localIsAdopted) {
      _originAdopted = _originLocal;
      _destinationAdopted = _destinationLocal;
    }
    _originConnext.setupAsset(TokenId(canonicalDomain, canonicalId), _originAdopted, address(0));

    // Handle destination
    if (_destination != canonicalDomain) {
      _destinationRegistry.enrollCustom(canonicalDomain, canonicalId, _destinationLocal);
    }
    // Setup asset whitelist
    _destinationConnext.setupAsset(TokenId(canonicalDomain, canonicalId), _destinationAdopted, address(0));

    // mint the asset
    uint256 toMint = 10_000 ether;
    TestERC20(_originLocal).mint(address(this), toMint);
    TestERC20(_destinationLocal).mint(address(this), toMint);
    TestERC20(_originAdopted).mint(address(this), toMint);
    TestERC20(_destinationAdopted).mint(address(this), toMint);
    TestERC20(_canonical).mint(address(this), toMint);

    // setup + fund the pools if needed
    if (_originLocal != _originAdopted) {
      utils_setupPool(_origin, _canonicalKey, 100 ether);
    }

    if (_destinationLocal != _destinationAdopted) {
      utils_setupPool(_destination, _canonicalKey, 100 ether);
    }
  }

  function utils_setupPool(
    uint32 domain,
    bytes32 canonicalKey,
    uint256 amount
  ) public {
    bool isOrigin = domain == _origin;
    // get tokens
    IERC20[] memory pooledTokens = new IERC20[](2);
    pooledTokens[0] = IERC20(isOrigin ? _originLocal : _destinationLocal);
    pooledTokens[1] = IERC20(isOrigin ? _originAdopted : _destinationAdopted);

    // get decimals
    uint8[] memory decimals = new uint8[](2);
    decimals[0] = 18;
    decimals[1] = 18;

    IConnextHandler connext = isOrigin ? _originConnext : _destinationConnext;

    string memory LP_TOKEN_NAME = "Test LP Token Name";
    string memory LP_TOKEN_SYMBOL = "TESTLP";
    {
      // deploy LP token
      LPToken token = new LPToken();
      // initialize
      token.initialize(LP_TOKEN_NAME, LP_TOKEN_SYMBOL);
      if (isOrigin) {
        _originLp = address(token);
      } else {
        _destinationLp = address(token);
      }
    }

    {
      // initialize pool
      connext.initializeSwap(
        canonicalKey, // canonicalkey
        pooledTokens, // pooled
        decimals, // decimals
        LP_TOKEN_NAME, // lp token name
        LP_TOKEN_SYMBOL, // lp token symbol
        50, // initialAValue
        0, // fee
        0, // admin fee
        isOrigin ? _originLp : _destinationLp // lp token address
      );

      if (amount == 0) {
        return;
      }

      // fund the pool
      uint256[] memory amounts = new uint256[](2);
      amounts[0] = amount;
      amounts[1] = amount;

      pooledTokens[0].approve(address(connext), amount);
      pooledTokens[1].approve(address(connext), amount);

      connext.addSwapLiquidity(canonicalKey, amounts, 0, block.timestamp + 60);
      assertTrue(connext.getSwapVirtualPrice(canonicalKey) != 0);
    }
  }

  function utils_createCallParams(uint32 destination) public returns (CallParams memory) {
    bool sendToDest = destination == _destination;
    return
      CallParams(
        address(1111), // to
        bytes(""), // callData
        sendToDest ? _origin : _destination, // origin domain
        destination, // dest domain
        address(2222), // agent
        address(3333), // recovery
        false, // forceSlow
        false, // receiveLocal
        address(0), // callback
        0, // callbackFee
        0, // relayerFee
        0.9 ether // slippage tol
      );
  }

  // ============ XCall helpers
  function utils_getXCallBalances(address transacting, address bridge) public returns (XCallBalances memory) {
    bool isDestination = bridge == address(_destinationConnext);
    address parkedAsset = transacting;
    return
      XCallBalances(
        IERC20(parkedAsset).balanceOf(bridge), // bridge transacting balance (what will sit there)
        IERC20(isDestination ? _destinationLocal : _originLocal).balanceOf(bridge), // bridge local balance
        bridge.balance, // bridge native balance
        IERC20(transacting).balanceOf(address(this)), // caller transacting balance
        address(this).balance
      );
  }

  function utils_xcallAndAssert(
    XCallArgs memory _args,
    address _bridged,
    uint256 _bridgedAmt
  ) public returns (bytes32) {
    // Approve the bridge
    if (_args.transactingAsset != address(0)) {
      IERC20(_args.transactingAsset).approve(address(_originConnext), _args.transactingAmount);
    }
    // Get initial balances
    XCallBalances memory initial = utils_getXCallBalances(_args.transactingAsset, address(_originConnext));

    // Register transfer id on bridge
    uint256 nonce = 0;
    bytes32 canonicalId = TypeCasts.addressToBytes32(_canonical);
    bytes32 transferId = keccak256(
      abi.encode(nonce, _args.params, address(this), canonicalId, _canonicalDomain, _bridgedAmt)
    );
    MockBridgeRouter(_originBridgeRouter).registerTransferId(transferId);

    // Expect an event
    vm.expectEmit(true, true, true, true);
    emit XCalled(transferId, nonce, _args, _bridged, _bridgedAmt, address(this));

    // Make call
    bytes32 ret = _originConnext.xcall{value: _args.params.relayerFee + _args.params.callbackFee}(_args);
    assertEq(ret, transferId);

    // Check balances
    XCallBalances memory end = utils_getXCallBalances(_args.transactingAsset, address(_originConnext));
    assertEq(
      end.bridgeTransacting,
      _args.transactingAsset == _originLocal
        ? initial.bridgeTransacting // will be transferred
        : initial.bridgeTransacting + _args.transactingAmount // will be swapped
    );
    assertEq(
      end.bridgeLocal,
      // on xcall, local will be (1) transferred (or swapped) in, (2) sent to the bridge router
      // meaning the balance should only change by the amount swapped
      _args.transactingAsset == _bridged ? initial.bridgeLocal : initial.bridgeLocal - _bridgedAmt
    );
    assertEq(end.bridgeNative, initial.bridgeNative + _args.params.relayerFee);
    assertEq(end.callerTransacting, initial.callerTransacting - _args.transactingAmount);
    assertEq(end.callerNative, initial.callerNative - _args.params.relayerFee - _args.params.callbackFee);

    // Check call to bridge router
    assertEq(MockBridgeRouter(_originBridgeRouter).getToken(transferId), _bridged);
    assertEq(MockBridgeRouter(_originBridgeRouter).getAmount(transferId), _bridgedAmt);
    assertEq(MockBridgeRouter(_originBridgeRouter).getDestination(transferId), _args.params.destinationDomain);
    return ret;
  }

  // ============ Execute helpers
  function utils_createRouters(
    uint256 num,
    bytes32 transferId,
    uint256 liquidity
  ) public returns (address[] memory, bytes[] memory) {
    if (num == 0) {
      address[] memory routers;
      bytes[] memory signatures;
      return (routers, signatures);
    }
    address[] memory routers = new address[](num);
    bytes[] memory signatures = new bytes[](num);

    bytes32 toSign = ECDSA.toEthSignedMessageHash(keccak256(abi.encode(transferId, num)));

    // setup liquidity
    if (liquidity != 0) {
      IERC20(_destinationLocal).approve(address(_destinationConnext), liquidity * num);
    }
    for (uint256 i; i < num; i++) {
      routers[i] = vm.addr(777 + i);
      (uint8 v, bytes32 r, bytes32 _s) = vm.sign(777 + i, toSign);
      signatures[i] = abi.encodePacked(r, _s, v);

      // whitelist all routers
      _destinationConnext.setupRouter(routers[i], address(0), address(0));

      // add liquidity for all routers
      if (liquidity != 0) {
        _destinationConnext.addRouterLiquidityFor(liquidity, _destinationLocal, routers[i]);
      }
    }

    return (routers, signatures);
  }

  function utils_createSequencer(bytes32 transferId, address[] memory routers) public returns (address, bytes memory) {
    uint256 key = 0xA11CE;
    address sequencer = vm.addr(key);
    _originConnext.addSequencer(sequencer);
    _destinationConnext.addSequencer(sequencer);

    bytes32 preImage = keccak256(abi.encode(transferId, routers));
    bytes32 toSign = ECDSA.toEthSignedMessageHash(preImage);
    (uint8 v, bytes32 r, bytes32 _s) = vm.sign(key, toSign);
    return (sequencer, abi.encodePacked(r, _s, v));
  }

  function utils_createExecuteArgs(
    CallParams memory params,
    uint256 pathLen,
    bytes32 transferId,
    uint256 bridgedAmt,
    uint256 liquidity
  ) public returns (ExecuteArgs memory) {
    (address[] memory routers, bytes[] memory routerSignatures) = utils_createRouters(pathLen, transferId, liquidity);
    (address sequencer, bytes memory sequencerSignature) = utils_createSequencer(transferId, routers);
    return
      ExecuteArgs(
        params, // CallParams
        _destinationLocal, // local asset
        routers, // routers
        routerSignatures, // router signatures
        sequencer, // sequencer
        sequencerSignature, // sequencer signatures
        bridgedAmt, // amount
        0, // nonce
        address(this) // originSender
      );
  }

  function utils_createExecuteArgs(
    CallParams memory params,
    uint256 pathLen,
    bytes32 transferId,
    uint256 bridgedAmt
  ) public returns (ExecuteArgs memory) {
    return utils_createExecuteArgs(params, pathLen, transferId, bridgedAmt, 20 ether);
  }

  function utils_getFastTransferAmount(uint256 amount) public returns (uint256) {
    return (amount * 9995) / 10000;
  }

  function utils_getExecuteBalances(
    address local,
    address receiving,
    address bridge,
    address recipient,
    address[] memory routers
  ) public returns (ExecuteBalances memory) {
    uint256[] memory routerBalances = new uint256[](routers.length);
    for (uint256 i; i < routers.length; i++) {
      routerBalances[i] = _destinationConnext.routerBalances(routers[i], local);
    }
    return
      ExecuteBalances(
        IERC20(local).balanceOf(bridge), // bridge local
        IERC20(receiving).balanceOf(bridge), // bridge receiving
        routerBalances, // router liquidity
        IERC20(receiving).balanceOf(recipient) // to receive
      );
  }

  function utils_executeAndAssert(
    ExecuteArgs memory args,
    bytes32 transferId,
    uint256 bridgeOut,
    uint256 vaultOut,
    bool usesPortals
  ) public {
    // Get initial balances
    address receiving = args.params.receiveLocal ? _destinationLocal : _destinationAdopted;
    ExecuteBalances memory initial = utils_getExecuteBalances(
      args.local,
      receiving,
      address(_destinationConnext),
      args.params.to,
      args.routers
    );

    // Expect an event
    vm.expectEmit(true, true, true, true);
    emit Executed(transferId, args.params.to, args, receiving, bridgeOut + vaultOut, address(this));

    // execute on bridge
    _destinationConnext.execute(args);

    // assert updated balances
    ExecuteBalances memory end = utils_getExecuteBalances(
      args.local,
      receiving,
      address(_destinationConnext),
      args.params.to,
      args.routers
    );

    uint256 pathLen = args.routers.length;
    bool isFast = pathLen != 0;
    // You are using internal swaps, so the amount of the local asset on the bridge
    // should *not* change iff you are using adopted assets. However, the router liquidity
    // and bridge adopted balance should drop
    if (!args.params.receiveLocal && _destinationLocal != _destinationAdopted) {
      assertEq(end.bridgeLocal, initial.bridgeLocal);
    } // else, local checked in receiving
    assertEq(end.bridgeReceiving, usesPortals ? initial.bridgeReceiving : initial.bridgeReceiving - bridgeOut);

    // router loses the liquidity it provides (local)
    uint256 debited = isFast ? (utils_getFastTransferAmount(args.amount)) / pathLen : 0;
    address[] memory stored = _destinationConnext.routedTransfers(transferId);
    if (isFast) {
      for (uint256 i; i < pathLen - 1; i++) {
        assertEq(stored[i], args.routers[i]);
        assertEq(end.liquidity[i], usesPortals ? initial.liquidity[i] : initial.liquidity[i] - debited);
      }

      uint256 sweep = isFast ? debited + (args.amount % pathLen) : 0;
      assertEq(stored[pathLen - 1], args.routers[pathLen - 1]);
      assertEq(
        end.liquidity[pathLen - 1],
        usesPortals ? initial.liquidity[pathLen - 1] : initial.liquidity[pathLen - 1] - sweep
      );
    } else {
      assertEq(stored.length, 0);
    }

    // recipient gains (adopted/specified)
    assertEq(end.toReceiving, initial.toReceiving + bridgeOut + vaultOut);

    // relayer stored
    assertEq(_destinationConnext.transferRelayer(transferId), address(this));

    if (!usesPortals) {
      return;
    }
    assertEq(_destinationConnext.getAavePortalDebt(transferId), bridgeOut);
    assertEq(
      _destinationConnext.getAavePortalFeeDebt(transferId),
      (bridgeOut * _destinationConnext.aavePortalFee()) / 10000
    );
  }

  function utils_executeAndAssert(
    ExecuteArgs memory args,
    bytes32 transferId,
    uint256 bridgeOut
  ) public {
    utils_executeAndAssert(args, transferId, bridgeOut, 0, false);
  }

  // ============ Reconcile helpers
  function utils_getReconcileBalances(bytes32 transferId, address[] memory routers)
    public
    returns (ReconcileBalances memory)
  {
    uint256[] memory initLiquidity = new uint256[](routers.length);
    for (uint256 i; i < routers.length; i++) {
      initLiquidity[i] = _destinationConnext.routerBalances(routers[i], _destinationLocal);
    }
    return
      ReconcileBalances(
        initLiquidity,
        _destinationConnext.getAavePortalDebt(transferId),
        _destinationConnext.getAavePortalFeeDebt(transferId)
      );
  }

  function utils_reconcileAndAssert(
    bytes32 transferId,
    uint256 bridgedAmt,
    address to,
    address[] memory routers,
    CallParams memory params,
    uint256 nonce,
    address originSender
  ) public {
    uint256 repayAmount = bridgedAmt;

    // NOTE: the bridge router handles the minting and custodying of assets. as far
    // as connext is concerned, the funds will *always* be transferred to the contract
    // when `reconcile` is called. Mint funds to the contract to mock
    TestERC20(_destinationLocal).mint(address(_destinationConnext), bridgedAmt);

    // Get initial bridge balance and router liquidity
    ReconcileBalances memory initial = utils_getReconcileBalances(transferId, routers);

    // expect emit
    vm.expectEmit(true, true, true, true);
    emit Reconciled(transferId, routers, _destinationLocal, bridgedAmt, _destinationBridgeRouter);

    vm.prank(_destinationBridgeRouter);
    _destinationConnext.onReceive(
      _origin, // origin, not used
      _canonicalDomain,
      TypeCasts.addressToBytes32(_canonical),
      _destinationLocal,
      bridgedAmt,
      abi.encode(TransferIdInformation(params, nonce, originSender))
    );

    ReconcileBalances memory end = utils_getReconcileBalances(transferId, routers);

    // assert router liquidity balance
    uint256 credited = routers.length != 0 ? bridgedAmt / routers.length : 0;
    for (uint256 i; i < routers.length; i++) {
      assertEq(end.liquidity[i], initial.liquidity[i] + credited);
    }

    // assert portal balance didnt change during reconcile call
    assertEq(end.portalDebt, initial.portalDebt);
    assertEq(end.portalFeeDebt, initial.portalFeeDebt);

    // assert transfer marked as reconciled
    assertTrue(_destinationConnext.reconciledTransfers(transferId));
  }

  // ============ Testing scenarios ============
  // you should be able to bridge tokens (local == adopted)
  function test_Connext__bridgingTokensShouldWorkFastNoSwap() public {
    /// 0. setup contracts
    utils_setupAssets(_origin, true);

    // 1. `xcall` on the origin
    XCallArgs memory xcall = XCallArgs(utils_createCallParams(_destination), _originLocal, 1 ether, 0.95 ether);
    bytes32 transferId = utils_xcallAndAssert(xcall, _originLocal, xcall.transactingAmount);

    // 2. call `execute` on the destination
    ExecuteArgs memory execute = utils_createExecuteArgs(xcall.params, 2, transferId, xcall.transactingAmount);
    utils_executeAndAssert(execute, transferId, utils_getFastTransferAmount(execute.amount));

    // 3. call `handle` on the destination
    utils_reconcileAndAssert(
      transferId,
      xcall.transactingAmount,
      xcall.params.to,
      execute.routers,
      xcall.params,
      0,
      address(this)
    );
  }

  // you should be able to bridge tokens (local != adopted)
  function test_Connext__bridgingTokensShouldWorkFastWithSwap() public {
    /// 0. setup contracts
    utils_setupAssets(_other, false);

    // 1. `xcall` on the origin
    XCallArgs memory args = XCallArgs(utils_createCallParams(_destination), _originAdopted, 1 ether, 0.95 ether);
    uint256 expected = _originConnext.calculateSwap(
      _canonicalKey,
      0, // local idx always 0
      1, // adopted idx always 1
      args.transactingAmount // no min
    );
    bytes32 transferId = utils_xcallAndAssert(args, _originLocal, expected);

    // 2. call `execute` on the destination
    ExecuteArgs memory execute = utils_createExecuteArgs(args.params, 1, transferId, expected);
    uint256 swapped = _destinationConnext.calculateSwap(
      _canonicalKey,
      1, // adopted idx always 1
      0, // local idx always 0
      utils_getFastTransferAmount(execute.amount)
    );
    utils_executeAndAssert(execute, transferId, swapped);

    // 3. call `handle` on the destination
    utils_reconcileAndAssert(transferId, expected, args.params.to, execute.routers, args.params, 0, address(this));
  }

  // you should be able to bridge local asset (local != adopted)
  function test_Connext__bridgingTokensShouldWorkFastWithLocalAndSwap() public {
    /// 0. setup contracts
    utils_setupAssets(_other, false);

    // 1. `xcall` on the origin
    XCallArgs memory args = XCallArgs(utils_createCallParams(_destination), _originLocal, 1 ether, 0.95 ether);
    bytes32 transferId = utils_xcallAndAssert(args, _originLocal, args.transactingAmount);

    // 2. call `execute` on the destination
    ExecuteArgs memory execute = utils_createExecuteArgs(args.params, 2, transferId, args.transactingAmount);
    uint256 swapped = _destinationConnext.calculateSwap(
      _canonicalKey,
      1, // adopted idx always 1
      0, // local idx always 0
      utils_getFastTransferAmount(execute.amount)
    );
    utils_executeAndAssert(execute, transferId, swapped);

    // 3. call `handle` on the destination
    utils_reconcileAndAssert(
      transferId,
      args.transactingAmount,
      args.params.to,
      execute.routers,
      args.params,
      0,
      address(this)
    );
  }

  // you should be able to use the slow path
  function test_Connext__bridgingTokensShouldWorkSlow() public {
    /// 0. setup contracts
    utils_setupAssets(_other, true); // local is adopted

    // 1. `xcall` on the origin
    XCallArgs memory args = XCallArgs(utils_createCallParams(_destination), _originLocal, 1 ether, 0.95 ether);
    bytes32 transferId = utils_xcallAndAssert(args, _originLocal, args.transactingAmount);

    // create execute args
    ExecuteArgs memory execute = utils_createExecuteArgs(args.params, 0, transferId, args.transactingAmount);

    // 2. call `handle` on the destination
    utils_reconcileAndAssert(
      transferId,
      args.transactingAmount,
      args.params.to,
      execute.routers,
      args.params,
      0,
      address(this)
    );

    // 3. call `execute` on the destination
    utils_executeAndAssert(execute, transferId, args.transactingAmount);
  }

  // you should be able to execute unpermissioned external call data
  function test_Connext__unpermissionedCallsWork() public {
    // 0. setup contracts
    utils_setupAssets(_origin, true);
    MockCalldata callTo = new MockCalldata(address(this), _origin);
    bytes memory callData = abi.encodeWithSelector(MockCalldata.unpermissionedCall.selector, _destinationAdopted);

    // 1. xcall
    XCallArgs memory xcall = XCallArgs(utils_createCallParams(_destination), _originLocal, 1 ether, 0.95 ether);
    xcall.params.to = address(callTo);
    xcall.params.callData = callData;
    bytes32 transferId = utils_xcallAndAssert(xcall, _originLocal, xcall.transactingAmount);

    // 2. call `execute` on the destination
    ExecuteArgs memory execute = utils_createExecuteArgs(xcall.params, 2, transferId, xcall.transactingAmount);
    utils_executeAndAssert(execute, transferId, utils_getFastTransferAmount(execute.amount));
    // NOTE: execute only passes if external call passes because of balance assertions on `to`
  }

  // you should be able to execute permissioned external call data
  function test_Connext__permissionedCallsWork() public {
    // 0. setup contracts
    utils_setupAssets(_origin, true);
    MockCalldata callTo = new MockCalldata(address(this), _origin);
    bytes memory callData = abi.encodeWithSelector(MockCalldata.permissionedCall.selector, _destinationAdopted);

    // 1. xcall
    XCallArgs memory xcall = XCallArgs(utils_createCallParams(_destination), _originLocal, 1 ether, 0.95 ether);
    xcall.params.to = address(callTo);
    xcall.params.callData = callData;
    bytes32 transferId = utils_xcallAndAssert(xcall, _originLocal, xcall.transactingAmount);

    // create execute args
    ExecuteArgs memory execute = utils_createExecuteArgs(xcall.params, 0, transferId, xcall.transactingAmount);

    // 2. call `handle` on the destination
    utils_reconcileAndAssert(
      transferId,
      xcall.transactingAmount,
      xcall.params.to,
      execute.routers,
      xcall.params,
      0,
      address(this)
    );

    // 3. call `execute` on the destination
    utils_executeAndAssert(execute, transferId, execute.amount);
    // NOTE: execute only passes if external call passes because of balance assertions on `to`
  }

  // you should be able to use a callback
  function test_Connext__callbacksWork() public {
    // 0. setup contracts
    utils_setupAssets(_origin, true);
    MockCalldata callTo = new MockCalldata(address(this), _origin);
    bytes memory callData = abi.encodeWithSelector(MockCalldata.unpermissionedCall.selector, _destinationAdopted);
    MockCallback callback = new MockCallback();

    (, bytes memory sample) = address(callTo).call(callData);

    // 1. xcall
    XCallArgs memory xcall = XCallArgs(utils_createCallParams(_destination), _originLocal, 1 ether, 0.95 ether);
    xcall.params.to = address(callTo);
    xcall.params.callData = callData;
    xcall.params.callback = address(callback);
    bytes32 transferId = utils_xcallAndAssert(xcall, _originLocal, xcall.transactingAmount);

    // 2. call `execute` on the destination
    ExecuteArgs memory execute = utils_createExecuteArgs(xcall.params, 2, transferId, xcall.transactingAmount);
    utils_executeAndAssert(execute, transferId, utils_getFastTransferAmount(execute.amount));
    // NOTE: execute only passes if external call passes because of balance assertions on `to`

    // 3. call `handle` on promise router
    bytes memory promiseMessage = abi.encodePacked(
      uint8(1),
      transferId,
      address(callback),
      uint8(1),
      sample.length,
      sample
    );
    _originPromise.handle(_destination, 0, TypeCasts.addressToBytes32(address(_destinationPromise)), promiseMessage);

    // 4. bump callback fee
    uint256 bump = 0.01 ether;
    uint256 initRouter = address(_originPromise).balance;
    _originPromise.bumpCallbackFee{value: bump}(transferId);
    assertEq(_originPromise.callbackFees(transferId), bump + xcall.params.callbackFee);
    assertEq(address(_originPromise).balance, initRouter + bump);

    // 5. call `process` on promise router
    uint256 initRelayer = address(this).balance;
    _originPromise.process(transferId, promiseMessage);
    assertTrue(callback.transferSuccess(transferId));
    assertEq(_originPromise.callbackFees(transferId), 0);
    assertEq(address(this).balance, initRelayer + bump + xcall.params.callbackFee);
  }

  // you should be able to use a sponsor vault
  function test_Connext__sponsorVaultsWork() public {
    // 0. deploy sponsor vault + setup contracts
    utils_setupAssets(_origin, true);
    uint256 liquidityReimbursement = 0.1 ether;
    uint256 dust = 0.01 ether;
    MockSponsorVault vault = new MockSponsorVault(liquidityReimbursement, dust);
    vm.deal(address(vault), 100 ether); // fund for dusting
    _destinationConnext.setSponsorVault(address(vault));

    // 1. xcall
    XCallArgs memory xcall = XCallArgs(utils_createCallParams(_destination), _originLocal, 1 ether, 0.95 ether);
    bytes32 transferId = utils_xcallAndAssert(xcall, _originLocal, xcall.transactingAmount);

    // 2. call `execute` on the destination
    uint256 initLiquidity = IERC20(_destinationLocal).balanceOf(xcall.params.to);
    uint256 initReceiver = xcall.params.to.balance;
    ExecuteArgs memory execute = utils_createExecuteArgs(xcall.params, 2, transferId, xcall.transactingAmount);
    utils_executeAndAssert(
      execute,
      transferId,
      utils_getFastTransferAmount(execute.amount),
      liquidityReimbursement,
      false
    );

    assertEq(xcall.params.to.balance, initReceiver + dust);
    assertEq(
      IERC20(_destinationLocal).balanceOf(xcall.params.to),
      initLiquidity + utils_getFastTransferAmount(execute.amount) + liquidityReimbursement
    );
  }

  // you should be able to use a portal
  function test_Connext__portalsShouldWork() public {
    // 0. deploy pool + setup contracts
    utils_setupAssets(_origin, false); // local != adopted
    MockPool aavePool = new MockPool(false);
    _destinationConnext.setAavePool(address(aavePool));
    _destinationConnext.setAavePortalFee(5);

    // 1. `xcall` on the origin
    XCallArgs memory args = XCallArgs(utils_createCallParams(_destination), _originAdopted, 1 ether, 0.95 ether);
    bytes32 transferId = utils_xcallAndAssert(args, _originLocal, args.transactingAmount);

    // 2. call `execute` on the destination
    ExecuteArgs memory execute = utils_createExecuteArgs(args.params, 1, transferId, args.transactingAmount, 0);
    // whitelist routers for portal
    _destinationConnext.approveRouterForPortal(execute.routers[0]);
    assertTrue(_destinationConnext.getRouterApprovalForPortal(execute.routers[0]));
    utils_executeAndAssert(execute, transferId, utils_getFastTransferAmount(args.transactingAmount), 0, true);

    // 3. call `handle` on the destination
    utils_reconcileAndAssert(
      transferId,
      args.transactingAmount,
      args.params.to,
      execute.routers,
      args.params,
      0,
      address(this)
    );

    // 4. repay portal out of band
    IERC20(_destinationAdopted).approve(address(_destinationConnext), 100 ether);
    _destinationConnext.repayAavePortalFor(
      args.params,
      _destinationAdopted,
      address(this),
      args.transactingAmount,
      0,
      _destinationConnext.getAavePortalDebt(transferId),
      _destinationConnext.getAavePortalFeeDebt(transferId)
    );
    assertEq(_destinationConnext.getAavePortalFeeDebt(transferId), 0);
    assertEq(_destinationConnext.getAavePortalDebt(transferId), 0);
  }

  // you should be able to bump + claim relayer fees
  function test_Connext__relayerFeeBumpingAndClaimingWorks() public {
    /// 0. setup contracts
    utils_setupAssets(_origin, true);

    // 1. `xcall` on the origin
    XCallArgs memory xcall = XCallArgs(utils_createCallParams(_destination), _originLocal, 1 ether, 0.95 ether);
    bytes32 transferId = utils_xcallAndAssert(xcall, _originLocal, xcall.transactingAmount);

    // 2. bump transfer id
    uint256 bump = 0.01 ether;
    uint256 init = address(_originConnext).balance;
    vm.expectEmit(true, true, true, true);
    emit TransferRelayerFeesUpdated(transferId, bump + xcall.params.relayerFee, address(this));
    _originConnext.bumpTransfer{value: bump}(transferId);
    assertEq(_originConnext.relayerFees(transferId), bump + xcall.params.relayerFee);
    assertEq(address(_originConnext).balance, bump + init);

    // 3. call `execute` on the destination
    ExecuteArgs memory execute = utils_createExecuteArgs(xcall.params, 2, transferId, xcall.transactingAmount);
    utils_executeAndAssert(execute, transferId, utils_getFastTransferAmount(execute.amount));

    // 4. initiate claim
    address recipient = address(123123123454545);
    bytes32[] memory ids = new bytes32[](1);
    ids[0] = transferId;
    vm.expectEmit(true, true, true, true);
    emit InitiatedClaim(_origin, recipient, address(this), ids);
    _destinationConnext.initiateClaim(_origin, recipient, ids);

    // 5. process claim
    vm.expectEmit(true, true, true, true);
    emit Claimed(recipient, bump + xcall.params.relayerFee, ids);

    uint256 recipientInit = recipient.balance;
    _originRelayerFee.handle(
      _destination,
      0,
      TypeCasts.addressToBytes32(address(_destinationRelayerFee)),
      abi.encodePacked(uint8(1), recipient, ids.length, ids)
    );

    assertEq(recipient.balance, recipientInit + bump + xcall.params.relayerFee);
    assertEq(_originConnext.relayerFees(transferId), 0);
  }
}
