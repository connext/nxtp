// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {DiamondCutFacet} from "../../contracts/core/connext/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../contracts/core/connext/facets/DiamondLoupeFacet.sol";
import {DiamondInit} from "../../contracts/core/connext/facets/upgrade-initializers/DiamondInit.sol";
import {AssetFacet} from "../../contracts/core/connext/facets/AssetFacet.sol";
import {BridgeFacet} from "../../contracts/core/connext/facets/BridgeFacet.sol";
import {NomadFacet} from "../../contracts/core/connext/facets/NomadFacet.sol";
import {ProposedOwnableFacet} from "../../contracts/core/connext/facets/ProposedOwnableFacet.sol";
import {RelayerFacet} from "../../contracts/core/connext/facets/RelayerFacet.sol";
import {RoutersFacet} from "../../contracts/core/connext/facets/RoutersFacet.sol";
import {StableSwapFacet} from "../../contracts/core/connext/facets/StableSwapFacet.sol";
import {SwapAdminFacet} from "../../contracts/core/connext/facets/SwapAdminFacet.sol";
import {PortalFacet} from "../../contracts/core/connext/facets/PortalFacet.sol";
import {VersionFacet} from "../../contracts/core/connext/facets/VersionFacet.sol";
import {XCallArgs, CallParams} from "../../contracts/core/connext/libraries/LibConnextStorage.sol";
import {IDiamondCut} from "../../contracts/core/connext/interfaces/IDiamondCut.sol";

import {Connext} from "./Connext.sol";
import {TestSetterFacet} from "./Mock.sol";

contract Deployer {
  Connext connextDiamondProxy;
  DiamondCutFacet diamondCutFacet;
  DiamondLoupeFacet diamondLoupeFacet;
  DiamondInit diamondInit;
  AssetFacet assetFacet;
  BridgeFacet bridgeFacet;
  NomadFacet nomadFacet;
  ProposedOwnableFacet proposedOwnableFacet;
  RelayerFacet relayerFacet;
  RoutersFacet routersFacet;
  StableSwapFacet stableSwapFacet;
  SwapAdminFacet swapAdminFacet;
  PortalFacet portalFacet;
  VersionFacet versionFacet;
  TestSetterFacet testSetterFacet;

  function getDiamondCutFacetCut(address _diamondCutFacet) internal pure returns (IDiamondCut.FacetCut memory) {
    bytes4[] memory diamondCutFacetSelectors = new bytes4[](3);
    diamondCutFacetSelectors[0] = DiamondCutFacet.diamondCut.selector;
    diamondCutFacetSelectors[1] = DiamondCutFacet.proposeDiamondCut.selector;
    diamondCutFacetSelectors[2] = DiamondCutFacet.rescindDiamondCut.selector;
    return
      IDiamondCut.FacetCut({
        facetAddress: _diamondCutFacet,
        action: IDiamondCut.FacetCutAction.Add,
        functionSelectors: diamondCutFacetSelectors
      });
  }

  function getDiamondLoupeFacetCut(address _diamondLoupeFacet) internal pure returns (IDiamondCut.FacetCut memory) {
    bytes4[] memory diamondLoupeFacetSelectors = new bytes4[](5);
    diamondLoupeFacetSelectors[0] = DiamondLoupeFacet.facets.selector;
    diamondLoupeFacetSelectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
    diamondLoupeFacetSelectors[2] = DiamondLoupeFacet.facetAddresses.selector;
    diamondLoupeFacetSelectors[3] = DiamondLoupeFacet.facetAddress.selector;
    diamondLoupeFacetSelectors[4] = DiamondLoupeFacet.supportsInterface.selector;
    return
      IDiamondCut.FacetCut({
        facetAddress: _diamondLoupeFacet,
        action: IDiamondCut.FacetCutAction.Add,
        functionSelectors: diamondLoupeFacetSelectors
      });
  }

  function getAssetFacetCut(address _assetFacet) internal view returns (IDiamondCut.FacetCut memory) {
    bytes4[] memory assetFacetSelectors = new bytes4[](13);
    // NOTE: because you cannot differentiate between overloaded function selectors, you must calculate
    // them manually here.
    assetFacetSelectors[0] = getSelector("canonicalToAdopted(bytes32)");
    assetFacetSelectors[1] = getSelector("canonicalToAdopted(tuple(uint32,bytes32))");
    assetFacetSelectors[2] = AssetFacet.adoptedToCanonical.selector;
    assetFacetSelectors[3] = getSelector("approvedAssets(bytes32)");
    assetFacetSelectors[4] = getSelector("approvedAssets(tuple(uint32,bytes32))");
    assetFacetSelectors[5] = getSelector("adoptedToLocalPools(bytes32)");
    assetFacetSelectors[6] = getSelector("adoptedToLocalPools(tuple(uint32,bytes32))");
    assetFacetSelectors[7] = AssetFacet.tokenRegistry.selector;
    assetFacetSelectors[8] = AssetFacet.setTokenRegistry.selector;
    assetFacetSelectors[9] = AssetFacet.setupAsset.selector;
    assetFacetSelectors[10] = AssetFacet.addStableSwapPool.selector;
    assetFacetSelectors[11] = getSelector("removeAssetId(bytes32,address)");
    assetFacetSelectors[12] = getSelector("removeAssetId(tuple(uint32,bytes32),address)");
    return
      IDiamondCut.FacetCut({
        facetAddress: _assetFacet,
        action: IDiamondCut.FacetCutAction.Add,
        functionSelectors: assetFacetSelectors
      });
  }

  function getBridgeFacetCut(address _bridgeFacet) internal pure returns (IDiamondCut.FacetCut memory) {
    bytes4[] memory bridgeFacetSelectors = new bytes4[](19);
    // getters
    bridgeFacetSelectors[0] = BridgeFacet.relayerFees.selector;
    bridgeFacetSelectors[1] = BridgeFacet.routedTransfers.selector;
    bridgeFacetSelectors[2] = BridgeFacet.reconciledTransfers.selector;
    bridgeFacetSelectors[3] = BridgeFacet.connextion.selector;
    bridgeFacetSelectors[4] = BridgeFacet.domain.selector;
    bridgeFacetSelectors[5] = BridgeFacet.executor.selector;
    bridgeFacetSelectors[6] = BridgeFacet.nonce.selector;
    bridgeFacetSelectors[7] = BridgeFacet.sponsorVault.selector;
    bridgeFacetSelectors[8] = BridgeFacet.promiseRouter.selector;
    // admin
    bridgeFacetSelectors[9] = BridgeFacet.setPromiseRouter.selector;
    bridgeFacetSelectors[10] = BridgeFacet.setExecutor.selector;
    bridgeFacetSelectors[11] = BridgeFacet.setSponsorVault.selector;
    bridgeFacetSelectors[12] = BridgeFacet.addConnextion.selector;
    bridgeFacetSelectors[13] = BridgeFacet.addSequencer.selector;
    bridgeFacetSelectors[14] = BridgeFacet.removeSequencer.selector;
    // public
    bridgeFacetSelectors[15] = BridgeFacet.xcall.selector;
    bridgeFacetSelectors[16] = BridgeFacet.execute.selector;
    bridgeFacetSelectors[17] = BridgeFacet.bumpTransfer.selector;
    bridgeFacetSelectors[18] = BridgeFacet.forceReceiveLocal.selector;
    return
      IDiamondCut.FacetCut({
        facetAddress: _bridgeFacet,
        action: IDiamondCut.FacetCutAction.Add,
        functionSelectors: bridgeFacetSelectors
      });
  }

  function getNomadFacetCut(address _nomadFacet) internal pure returns (IDiamondCut.FacetCut memory) {
    bytes4[] memory nomadFacetSelectors = new bytes4[](3);
    nomadFacetSelectors[0] = NomadFacet.bridgeRouter.selector;
    nomadFacetSelectors[1] = NomadFacet.setBridgeRouter.selector;
    nomadFacetSelectors[2] = NomadFacet.onReceive.selector;
    return
      IDiamondCut.FacetCut({
        facetAddress: _nomadFacet,
        action: IDiamondCut.FacetCutAction.Add,
        functionSelectors: nomadFacetSelectors
      });
  }

  function getProposedOwnableFacetCut(address _proposedOwnableFacet)
    internal
    pure
    returns (IDiamondCut.FacetCut memory)
  {
    bytes4[] memory proposedOwnableFacetSelectors = new bytes4[](18);
    proposedOwnableFacetSelectors[0] = ProposedOwnableFacet.owner.selector;
    proposedOwnableFacetSelectors[1] = ProposedOwnableFacet.routerWhitelistRemoved.selector;
    proposedOwnableFacetSelectors[2] = ProposedOwnableFacet.assetWhitelistRemoved.selector;
    proposedOwnableFacetSelectors[3] = ProposedOwnableFacet.proposed.selector;
    proposedOwnableFacetSelectors[4] = ProposedOwnableFacet.proposedTimestamp.selector;
    proposedOwnableFacetSelectors[5] = ProposedOwnableFacet.routerWhitelistTimestamp.selector;
    proposedOwnableFacetSelectors[6] = ProposedOwnableFacet.assetWhitelistTimestamp.selector;
    proposedOwnableFacetSelectors[7] = ProposedOwnableFacet.delay.selector;
    proposedOwnableFacetSelectors[8] = ProposedOwnableFacet.proposeRouterWhitelistRemoval.selector;
    proposedOwnableFacetSelectors[9] = ProposedOwnableFacet.removeRouterWhitelist.selector;
    proposedOwnableFacetSelectors[10] = ProposedOwnableFacet.proposeAssetWhitelistRemoval.selector;
    proposedOwnableFacetSelectors[11] = ProposedOwnableFacet.removeAssetWhitelist.selector;
    proposedOwnableFacetSelectors[12] = ProposedOwnableFacet.renounced.selector;
    proposedOwnableFacetSelectors[13] = ProposedOwnableFacet.proposeNewOwner.selector;
    proposedOwnableFacetSelectors[14] = ProposedOwnableFacet.renounceOwnership.selector;
    proposedOwnableFacetSelectors[15] = ProposedOwnableFacet.acceptProposedOwner.selector;
    proposedOwnableFacetSelectors[16] = ProposedOwnableFacet.pause.selector;
    proposedOwnableFacetSelectors[17] = ProposedOwnableFacet.unpause.selector;
    return
      IDiamondCut.FacetCut({
        facetAddress: _proposedOwnableFacet,
        action: IDiamondCut.FacetCutAction.Add,
        functionSelectors: proposedOwnableFacetSelectors
      });
  }

  function getRelayerFacetCut(address _relayerFacet) internal pure returns (IDiamondCut.FacetCut memory) {
    bytes4[] memory relayerFacetSelectors = new bytes4[](8);
    relayerFacetSelectors[0] = RelayerFacet.transferRelayer.selector;
    relayerFacetSelectors[1] = RelayerFacet.approvedRelayers.selector;
    relayerFacetSelectors[2] = RelayerFacet.relayerFeeRouter.selector;
    relayerFacetSelectors[3] = RelayerFacet.setRelayerFeeRouter.selector;
    relayerFacetSelectors[4] = RelayerFacet.addRelayer.selector;
    relayerFacetSelectors[5] = RelayerFacet.removeRelayer.selector;
    relayerFacetSelectors[6] = RelayerFacet.initiateClaim.selector;
    relayerFacetSelectors[7] = RelayerFacet.claim.selector;
    return
      IDiamondCut.FacetCut({
        facetAddress: _relayerFacet,
        action: IDiamondCut.FacetCutAction.Add,
        functionSelectors: relayerFacetSelectors
      });
  }

  function getRoutersFacetCut(address _routersFacet) internal pure returns (IDiamondCut.FacetCut memory) {
    bytes4[] memory routersFacetSelectors = new bytes4[](23);
    routersFacetSelectors[0] = RoutersFacet.LIQUIDITY_FEE_NUMERATOR.selector;
    routersFacetSelectors[1] = RoutersFacet.LIQUIDITY_FEE_DENOMINATOR.selector;
    routersFacetSelectors[2] = RoutersFacet.getRouterApproval.selector;
    routersFacetSelectors[3] = RoutersFacet.getRouterRecipient.selector;
    routersFacetSelectors[4] = RoutersFacet.getRouterOwner.selector;
    routersFacetSelectors[5] = RoutersFacet.getProposedRouterOwner.selector;
    routersFacetSelectors[6] = RoutersFacet.getProposedRouterOwnerTimestamp.selector;
    routersFacetSelectors[7] = RoutersFacet.maxRoutersPerTransfer.selector;
    routersFacetSelectors[8] = RoutersFacet.routerBalances.selector;
    routersFacetSelectors[9] = RoutersFacet.getRouterApprovalForPortal.selector;
    routersFacetSelectors[10] = RoutersFacet.setupRouter.selector;
    routersFacetSelectors[11] = RoutersFacet.removeRouter.selector;
    routersFacetSelectors[12] = RoutersFacet.setMaxRoutersPerTransfer.selector;
    routersFacetSelectors[13] = RoutersFacet.setLiquidityFeeNumerator.selector;
    routersFacetSelectors[14] = RoutersFacet.approveRouterForPortal.selector;
    routersFacetSelectors[15] = RoutersFacet.unapproveRouterForPortal.selector;
    routersFacetSelectors[16] = RoutersFacet.setRouterRecipient.selector;
    routersFacetSelectors[17] = RoutersFacet.proposeRouterOwner.selector;
    routersFacetSelectors[18] = RoutersFacet.acceptProposedRouterOwner.selector;
    routersFacetSelectors[19] = RoutersFacet.addRouterLiquidityFor.selector;
    routersFacetSelectors[20] = RoutersFacet.addRouterLiquidity.selector;
    routersFacetSelectors[21] = RoutersFacet.removeRouterLiquidityFor.selector;
    routersFacetSelectors[22] = RoutersFacet.removeRouterLiquidity.selector;
    return
      IDiamondCut.FacetCut({
        facetAddress: _routersFacet,
        action: IDiamondCut.FacetCutAction.Add,
        functionSelectors: routersFacetSelectors
      });
  }

  function getStableSwapFacetCut(address _stableSwapFacet) internal pure returns (IDiamondCut.FacetCut memory) {
    bytes4[] memory stableSwapFacetSelectors = new bytes4[](20);
    stableSwapFacetSelectors[0] = StableSwapFacet.getSwapStorage.selector;
    stableSwapFacetSelectors[1] = StableSwapFacet.getSwapLPToken.selector;
    stableSwapFacetSelectors[2] = StableSwapFacet.getSwapA.selector;
    stableSwapFacetSelectors[3] = StableSwapFacet.getSwapAPrecise.selector;
    stableSwapFacetSelectors[4] = StableSwapFacet.getSwapToken.selector;
    stableSwapFacetSelectors[5] = StableSwapFacet.getSwapTokenIndex.selector;
    stableSwapFacetSelectors[6] = StableSwapFacet.getSwapTokenBalance.selector;
    stableSwapFacetSelectors[7] = StableSwapFacet.getSwapVirtualPrice.selector;
    stableSwapFacetSelectors[8] = StableSwapFacet.calculateSwap.selector;
    stableSwapFacetSelectors[9] = StableSwapFacet.calculateSwapTokenAmount.selector;
    stableSwapFacetSelectors[10] = StableSwapFacet.calculateRemoveSwapLiquidity.selector;
    stableSwapFacetSelectors[11] = StableSwapFacet.calculateRemoveSwapLiquidityOneToken.selector;
    stableSwapFacetSelectors[12] = StableSwapFacet.getSwapAdminBalance.selector;
    stableSwapFacetSelectors[13] = StableSwapFacet.swap.selector;
    stableSwapFacetSelectors[14] = StableSwapFacet.swapExact.selector;
    stableSwapFacetSelectors[15] = StableSwapFacet.swapExactOut.selector;
    stableSwapFacetSelectors[16] = StableSwapFacet.addSwapLiquidity.selector;
    stableSwapFacetSelectors[17] = StableSwapFacet.removeSwapLiquidity.selector;
    stableSwapFacetSelectors[18] = StableSwapFacet.removeSwapLiquidityOneToken.selector;
    stableSwapFacetSelectors[19] = StableSwapFacet.removeSwapLiquidityImbalance.selector;
    return
      IDiamondCut.FacetCut({
        facetAddress: _stableSwapFacet,
        action: IDiamondCut.FacetCutAction.Add,
        functionSelectors: stableSwapFacetSelectors
      });
  }

  function getSwapAdminFacetCut(address _swapAdminFacet) internal pure returns (IDiamondCut.FacetCut memory) {
    bytes4[] memory adminFacetSelectors = new bytes4[](6);
    adminFacetSelectors[0] = SwapAdminFacet.initializeSwap.selector;
    adminFacetSelectors[1] = SwapAdminFacet.withdrawSwapAdminFees.selector;
    adminFacetSelectors[2] = SwapAdminFacet.setSwapAdminFee.selector;
    adminFacetSelectors[3] = SwapAdminFacet.setSwapFee.selector;
    adminFacetSelectors[4] = SwapAdminFacet.rampA.selector;
    adminFacetSelectors[5] = SwapAdminFacet.stopRampA.selector;
    return
      IDiamondCut.FacetCut({
        facetAddress: _swapAdminFacet,
        action: IDiamondCut.FacetCutAction.Add,
        functionSelectors: adminFacetSelectors
      });
  }

  function getPortalFacetCut(address _portalFacet) internal pure returns (IDiamondCut.FacetCut memory) {
    bytes4[] memory portalFacetSelectors = new bytes4[](8);
    portalFacetSelectors[0] = PortalFacet.getAavePortalDebt.selector;
    portalFacetSelectors[1] = PortalFacet.getAavePortalFeeDebt.selector;
    portalFacetSelectors[2] = PortalFacet.aavePool.selector;
    portalFacetSelectors[3] = PortalFacet.aavePortalFee.selector;
    portalFacetSelectors[4] = PortalFacet.setAavePool.selector;
    portalFacetSelectors[5] = PortalFacet.setAavePortalFee.selector;
    portalFacetSelectors[6] = PortalFacet.repayAavePortal.selector;
    portalFacetSelectors[7] = PortalFacet.repayAavePortalFor.selector;

    return
      IDiamondCut.FacetCut({
        facetAddress: _portalFacet,
        action: IDiamondCut.FacetCutAction.Add,
        functionSelectors: portalFacetSelectors
      });
  }

  function getVersionFacetCut(address _versionFacet) internal pure returns (IDiamondCut.FacetCut memory) {
    bytes4[] memory versionFacetSelectors = new bytes4[](1);
    versionFacetSelectors[0] = VersionFacet.VERSION.selector;
    return
      IDiamondCut.FacetCut({
        facetAddress: _versionFacet,
        action: IDiamondCut.FacetCutAction.Add,
        functionSelectors: versionFacetSelectors
      });
  }

  function getTestSetterFacetCut(address _testSetterFacetFacet) internal pure returns (IDiamondCut.FacetCut memory) {
    bytes4[] memory testSetterFacetSelectors = new bytes4[](11);
    testSetterFacetSelectors[0] = TestSetterFacet.setTestRelayerFees.selector;
    testSetterFacetSelectors[1] = TestSetterFacet.setTestTransferRelayer.selector;
    testSetterFacetSelectors[2] = TestSetterFacet.setTestApproveRouterForPortal.selector;
    testSetterFacetSelectors[3] = TestSetterFacet.setTestSponsorVault.selector;
    testSetterFacetSelectors[4] = TestSetterFacet.setTestApprovedRelayer.selector;
    testSetterFacetSelectors[5] = TestSetterFacet.setTestRouterBalances.selector;
    testSetterFacetSelectors[6] = TestSetterFacet.setTestApprovedRouter.selector;
    testSetterFacetSelectors[7] = TestSetterFacet.setTestCanonicalToAdopted.selector;
    testSetterFacetSelectors[8] = TestSetterFacet.setTestAavePortalDebt.selector;
    testSetterFacetSelectors[9] = TestSetterFacet.setTestAavePortalFeeDebt.selector;
    testSetterFacetSelectors[10] = TestSetterFacet.setTestRoutedTransfers.selector;
    return
      IDiamondCut.FacetCut({
        facetAddress: _testSetterFacetFacet,
        action: IDiamondCut.FacetCutAction.Add,
        functionSelectors: testSetterFacetSelectors
      });
  }

  function deployFacets() internal {
    diamondCutFacet = new DiamondCutFacet();
    diamondLoupeFacet = new DiamondLoupeFacet();
    diamondInit = new DiamondInit();
    assetFacet = new AssetFacet();
    bridgeFacet = new BridgeFacet();
    nomadFacet = new NomadFacet();
    proposedOwnableFacet = new ProposedOwnableFacet();
    relayerFacet = new RelayerFacet();
    routersFacet = new RoutersFacet();
    stableSwapFacet = new StableSwapFacet();
    swapAdminFacet = new SwapAdminFacet();
    portalFacet = new PortalFacet();
    versionFacet = new VersionFacet();
    testSetterFacet = new TestSetterFacet();
  }

  function getFacetCuts() internal view returns (IDiamondCut.FacetCut[] memory) {
    IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](13);
    facetCuts[0] = getTestSetterFacetCut(address(testSetterFacet));
    facetCuts[1] = getDiamondCutFacetCut(address(diamondCutFacet));
    facetCuts[2] = getDiamondLoupeFacetCut(address(diamondLoupeFacet));
    facetCuts[3] = getAssetFacetCut(address(assetFacet));
    facetCuts[4] = getBridgeFacetCut(address(bridgeFacet));
    facetCuts[5] = getNomadFacetCut(address(nomadFacet));
    facetCuts[6] = getProposedOwnableFacetCut(address(proposedOwnableFacet));
    facetCuts[7] = getRelayerFacetCut(address(relayerFacet));
    facetCuts[8] = getRoutersFacetCut(address(routersFacet));
    facetCuts[9] = getStableSwapFacetCut(address(stableSwapFacet));
    facetCuts[10] = getSwapAdminFacetCut(address(swapAdminFacet));
    facetCuts[11] = getPortalFacetCut(address(portalFacet));
    facetCuts[12] = getVersionFacetCut(address(versionFacet));

    return facetCuts;
  }

  function deployConnext(
    uint256 domain,
    address xAppConnectionManager,
    address tokenRegistry,
    address relayerFeeRouter,
    address payable promiseRouter
  ) internal returns (address) {
    bytes memory initCallData = abi.encodeWithSelector(
      DiamondInit.init.selector,
      domain,
      tokenRegistry,
      relayerFeeRouter,
      promiseRouter
    );

    deployFacets();

    connextDiamondProxy = new Connext(address(this), address(diamondInit), initCallData, getFacetCuts());
    return address(connextDiamondProxy);
  }

  function getSelector(bytes memory fnSig) internal pure returns (bytes4) {
    return bytes4(keccak256(fnSig));
  }
}
