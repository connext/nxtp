// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "../../../utils/ForgeHelper.sol";
import {Deployer, DiamondInit, VersionFacet} from "../../../utils/Deployer.sol";

import "../../../../contracts/core/connext/libraries/LibDiamond.sol";
import {IConnextHandler} from "../../../../contracts/core/connext/interfaces/IConnextHandler.sol";
import {IDiamondCut} from "../../../../contracts/core/connext/interfaces/IDiamondCut.sol";

import "forge-std/console.sol";

contract LibDiamondTest is ForgeHelper, Deployer {
  // ============ Libraries ============

  using stdStorage for StdStorage;

  // ============ Storage ============
  IConnextHandler connextHandler;
  uint32 domain = 1;
  address internal xAppConnectionManager = address(1);
  address relayerFeeRouter = address(3);
  address promiseRouter = address(4);
  address tokenRegistry = address(5);
  address executor = address(0);

  // ============ Setup ============

  function setUp() public {
    deployConnext(
      uint256(domain),
      xAppConnectionManager,
      tokenRegistry,
      address(relayerFeeRouter),
      payable(promiseRouter)
    );

    connextHandler = IConnextHandler(address(connextDiamondProxy));
    executor = address(connextHandler.executor());
  }

  // ============ Utils ============

  // Should work: first initialization
  function test_LibDiamond__initializeDiamondCut_works() public {
    assertTrue(connextDiamondProxy.isInitialized());
    assertTrue(executor != address(0));
  }

  // Second initialization should not alter state.
  function test_LibDiamond__initializeDiamondCut_ignoreDuplicateInit() public {
    uint32 newDomain = 2;
    address newXAppConnectionManager = address(11);
    address newRelayerFeeRouter = address(13);
    address newPromiseRouter = address(14);
    address newTokenRegistry = address(15);

    bytes memory initCallData = abi.encodeWithSelector(
      DiamondInit.init.selector,
      newDomain,
      newXAppConnectionManager,
      newTokenRegistry,
      newRelayerFeeRouter,
      newPromiseRouter
    );

    IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](1);
    bytes4[] memory versionFacetSelectors = new bytes4[](1);
    versionFacetSelectors[0] = VersionFacet.VERSION.selector;
    facetCuts[0] = IDiamondCut.FacetCut({
      facetAddress: address(0),
      action: IDiamondCut.FacetCutAction.Remove,
      functionSelectors: versionFacetSelectors
    });

    IDiamondCut(address(connextDiamondProxy)).proposeDiamondCut(facetCuts, address(diamondInit), initCallData);

    vm.warp(block.timestamp + 7 days + 1);

    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    bytes32 key = keccak256(abi.encode(facetCuts, address(diamondInit), initCallData));
    ds.acceptanceTimes[key] = 1;

    IDiamondCut(address(connextDiamondProxy)).diamondCut(facetCuts, address(diamondInit), initCallData);

    // still initialized
    assertTrue(connextDiamondProxy.isInitialized());

    // executor not updated
    assertTrue(address(connextHandler.executor()) == executor);

    // promise router not updated
    assertTrue(address(connextHandler.promiseRouter()) != newPromiseRouter);
    assertTrue(address(connextHandler.promiseRouter()) == promiseRouter);
  }
}
