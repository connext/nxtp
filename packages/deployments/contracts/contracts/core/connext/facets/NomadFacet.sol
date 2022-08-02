// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.15;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TypedMemView} from "../../../nomad-core/libs/TypedMemView.sol";

import {XAppConnectionManager} from "../../../nomad-core/contracts/XAppConnectionManager.sol";

import {TransferIdInformation} from "../libraries/LibConnextStorage.sol";
import {AssetLogic} from "../libraries/AssetLogic.sol";

import {IAavePool} from "../interfaces/IAavePool.sol";
import {IBridgeRouter} from "../interfaces/IBridgeRouter.sol";
import {IBridgeHook} from "../interfaces/IBridgeHook.sol";

import {BaseConnextFacet} from "./BaseConnextFacet.sol";

/**
 * @title NomadFacet
 * @notice This is the facet that holds all the functionality needed for nomad to reconcile
 * the transfer
 *
 */
contract NomadFacet is BaseConnextFacet, IBridgeHook {
  // ============ Libraries ============
  using TypedMemView for bytes;
  using TypedMemView for bytes29;

  // ========== Custom Errors ===========
  error NomadFacet__setBridgeRouter_invalidBridge();
  error NomadFacet__reconcile_notConnext();
  error NomadFacet__reconcile_alreadyReconciled();
  error NomadFacet__reconcile_noPortalRouter();

  // ============ Events ============

  /**
   * @notice Emitted when `reconciled` is called by the bridge on the destination domain
   * @param transferId - The unique identifier of the crosschain transaction
   * @param routers - The CallParams.recipient provided, created as indexed parameter
   * @param asset - The asset that was provided by the bridge
   * @param amount - The amount that was provided by the bridge
   * @param caller - The account that called the function
   */
  event Reconciled(bytes32 indexed transferId, address[] routers, address asset, uint256 amount, address caller);

  /**
   * @notice Emitted when the bridgeRouter variable is updated
   * @param oldBridgeRouter - The bridgeRouter old value
   * @param newBridgeRouter - The bridgeRouter new value
   * @param caller - The account that called the function
   */
  event BridgeRouterUpdated(address oldBridgeRouter, address newBridgeRouter, address caller);

  // ============ Getters ============

  /**
   * @notice Returns the stored bridge router reference
   */
  function bridgeRouter() external view returns (IBridgeRouter) {
    return s.bridgeRouter;
  }

  // ============ Admin functions ============

  /**
   * @notice Updates the bridge router
   * @param _bridgeRouter The new bridge router address
   */
  function setBridgeRouter(address _bridgeRouter) external onlyOwner {
    address old = address(s.bridgeRouter);
    if (old == _bridgeRouter) {
      revert NomadFacet__setBridgeRouter_invalidBridge();
    }
    s.bridgeRouter = IBridgeRouter(_bridgeRouter);
    emit BridgeRouterUpdated(old, _bridgeRouter, msg.sender);
  }

  // ============ External functions ============

  /**
   * @notice Called via `handle` on Nomad BridgeRouter. Will either (a) credit the router(s) if fast liquidity was provided (i.e. `execute`
   * has already occurred) or (b) make funds available for execution, updating state to mark the transfer as having
   * been reconciled (i.e. verified).
   *
   * @dev The output asset will be the one registered under the canonical token ID in the TokenRegistry. If the output
   * asset is an adopted token, the bridged nomad counterpart (i.e. the local asset) will be minted then swapped via
   * the configured AMM to the adopted token. If the target output is the canonical token (i.e. this domain is the
   * canonical domain for the token), then we will release custody of the appropriate amount of that canonical token
   * (tokens which were previously deposited into this bridge via outgoing `xcall`s). If the target adopted token
   * is also the local nomad asset (which would be minted here), then no swap is necessary.
   *
   * @dev Should be interface compatible with interface defined here:
   * https://github.com/nomad-xyz/monorepo/blob/main/packages/contracts-bridge/contracts/interfaces/IBridgeHook.sol
   *
   * @param _origin - The origin domain
   * @param _sender - The msg.sender of the original bridge call on origin domain
   * @param _tokenDomain - The canonical domain of the token
   * @param _tokenAddress - The canonical identifier of the token
   * @param _localToken - The address of the token representation on this domain, or the canonical
   * address if you are on the canonical domain
   * @param _amount - The amount bridged
   * @param _extraData - The extra data passed with the transfer on `sendToHook` (in this case transferId)
   */
  function onReceive(
    uint32 _origin,
    bytes32 _sender,
    uint32 _tokenDomain, // of canonical token not used
    bytes32 _tokenAddress, // of canonical token
    address _localToken,
    uint256 _amount,
    bytes memory _extraData
  ) external onlyBridgeRouter {
    // Assert sender was the connext contract on the origin domain
    if (s.connextions[_origin] != _sender) {
      revert NomadFacet__reconcile_notConnext();
    }

    // Calculate the transfer id
    // NOTE: Rather than sending the transferId through directly, recalculate the information here, to ensure
    // it was transported correctly to ensure all xcall, execute, and reconcile data must match. The sender
    // is asserted to be the connext contract on that domain, so this check could be unneccessary, but since
    // the implications of incorrectly transferred data are severe
    TransferIdInformation memory info = abi.decode(_extraData, (TransferIdInformation));
    bytes32 transferId = _calculateTransferId(
      info.params,
      _amount,
      info.nonce,
      _tokenAddress,
      _tokenDomain,
      info.originSender
    );

    // Ensure the transaction has not already been handled (i.e. previously reconciled).
    if (s.reconciledTransfers[transferId]) {
      revert NomadFacet__reconcile_alreadyReconciled();
    }

    // Mark the transfer as reconciled.
    s.reconciledTransfers[transferId] = true;

    // If the transfer was executed using fast-liquidity provided by routers, then this value would be set
    // to the participating routers.
    // NOTE: If the transfer was not executed using fast-liquidity, then the funds will be reserved for
    // execution (i.e. funds will be delivered to the transfer's recipient in a subsequent `execute` call).
    address[] memory routers = s.routedTransfers[transferId];

    // If fast transfer was made using portal liquidity, we need to repay
    // NOTE: routers can repay any-amount out-of-band using the `repayAavePortal` method
    // or by interacting with the aave contracts directly
    uint256 portalTransferAmount = s.portalDebt[transferId] + s.portalFeeDebt[transferId];

    uint256 pathLen = routers.length;
    if (portalTransferAmount != 0 && pathLen != 1) {
      // ensure a router took on credit risk
      revert NomadFacet__reconcile_noPortalRouter();
    }

    if (pathLen != 0) {
      // fast liquidity path
      // Credit each router that provided liquidity their due 'share' of the asset.
      uint256 routerAmt = _amount / pathLen;
      for (uint256 i; i < pathLen - 1; ) {
        s.routerBalances[routers[i]][_localToken] += routerAmt;
        unchecked {
          ++i;
        }
      }
      // The last router in the multipath will sweep the remaining balance to account for remainder dust.
      uint256 toSweep = routerAmt + (_amount % pathLen);
      s.routerBalances[routers[pathLen - 1]][_localToken] += toSweep;
    }

    emit Reconciled(transferId, routers, _localToken, _amount, msg.sender);
  }
}
