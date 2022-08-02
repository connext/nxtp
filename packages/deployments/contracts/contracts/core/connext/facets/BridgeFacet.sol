// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {TypedMemView} from "../../../nomad-core/libs/TypedMemView.sol";
import {TypeCasts} from "../../../nomad-core/contracts/XAppConnectionManager.sol";

import {BaseConnextFacet} from "./BaseConnextFacet.sol";

import {AssetLogic} from "../libraries/AssetLogic.sol";
import {XCallArgs, ExecuteArgs, CallParams, TokenId, TransferIdInformation} from "../libraries/LibConnextStorage.sol";
import {LibCrossDomainProperty} from "../libraries/LibCrossDomainProperty.sol";

import {PromiseRouter} from "../../promise/PromiseRouter.sol";

import {IWeth} from "../interfaces/IWeth.sol";
import {ITokenRegistry} from "../interfaces/ITokenRegistry.sol";
import {IExecutor} from "../interfaces/IExecutor.sol";
import {IAavePool} from "../interfaces/IAavePool.sol";
import {ISponsorVault} from "../interfaces/ISponsorVault.sol";

contract BridgeFacet is BaseConnextFacet {
  // ============ Libraries ============
  using TypedMemView for bytes;
  using TypedMemView for bytes29;

  // ========== Structs ===========

  // ========== Custom Errors ===========

  error BridgeFacet__setPromiseRouter_invalidPromiseRouter();
  error BridgeFacet__setExecutor_invalidExecutor();
  error BridgeFacet__setSponsorVault_invalidSponsorVault();
  error BridgeFacet__addConnextion_invalidDomain();
  error BridgeFacet__addSequencer_alreadyApproved();
  error BridgeFacet__removeSequencer_notApproved();
  error BridgeFacet__xcall_nativeAssetNotSupported();
  error BridgeFacet__xcall_wrongDomain();
  error BridgeFacet__xcall_destinationNotSupported();
  error BridgeFacet__xcall_emptyToOrRecovery();
  error BridgeFacet__xcall_notSupportedAsset();
  error BridgeFacet__xcall_nonZeroCallbackFeeForCallback();
  error BridgeFacet__xcall_callbackNotAContract();
  error BridgeFacet__xcall_missingAgent();
  error BridgeFacet__xcall_invalidSlippageTol();
  error BridgeFacet__xcall_ethValueMismatchedFees();
  error BridgeFacet__execute_unapprovedSender();
  error BridgeFacet__execute_wrongDomain();
  error BridgeFacet__execute_notSupportedSequencer();
  error BridgeFacet__execute_invalidSequencerSignature();
  error BridgeFacet__execute_maxRoutersExceeded();
  error BridgeFacet__execute_notSupportedRouter();
  error BridgeFacet__execute_invalidRouterSignature();
  error BridgeFacet__execute_alreadyExecuted();
  error BridgeFacet__execute_notApprovedForPortals();
  error BridgeFacet__execute_alreadyReconciled();
  error BridgeFacet__execute_notReconciled();
  error BridgeFacet__handleExecuteTransaction_invalidSponsoredAmount();
  error BridgeFacet__executePortalTransfer_insufficientAmountWithdrawn();
  error BridgeFacet__bumpTransfer_valueIsZero();
  error BridgeFacet__forceReceiveLocal_invalidSender();

  // ============ Properties ============

  uint16 public constant AAVE_REFERRAL_CODE = 0;

  // ============ Events ============

  /**
   * @notice Emitted when `xcall` is called on the origin domain
   * @param transferId - The unique identifier of the crosschain transfer.
   * @param nonce - The bridge nonce of the transfer on the origin domain.
   * @param xcallArgs - The `XCallArgs` provided to the function.
   * @param bridgedAsset - The local (mad) asset being bridged. Could be the same as the transactingAsset (adopted
   * asset), or may be different (indicating the transactingAsset was swapped for this bridgedAsset).
   * @param bridgedAmount - The amount of the bridgedAsset being sent, after AMM swap from adopted asset if it was
   * necessary.
   * @param caller - The account that called the function.
   */
  event XCalled(
    bytes32 indexed transferId,
    uint256 indexed nonce,
    XCallArgs xcallArgs,
    address bridgedAsset,
    uint256 bridgedAmount,
    address caller
  );

  /**
   * @notice Emitted when `execute` is called on the destination chain
   * @dev `execute` may be called when providing fast liquidity *or* when processing a reconciled transfer
   * @param transferId - The unique identifier of the crosschain transfer.
   * @param to - The recipient `CallParams.to` provided, created as indexed parameter.
   * @param args - The `ExecuteArgs` provided to the function.
   * @param transactingAsset - The asset the to gets or the external call is executed with. Should be the
   * adopted asset on that chain.
   * @param transactingAmount - The amount of transferring asset the to address receives or the external call is
   * executed with.
   * @param caller - The account that called the function.
   */
  event Executed(
    bytes32 indexed transferId,
    address indexed to,
    ExecuteArgs args,
    address transactingAsset,
    uint256 transactingAmount,
    address caller
  );

  /**
   * @notice Emitted when `bumpTransfer` is called by an user on the origin domain
   * @param transferId - The unique identifier of the crosschain transaction
   * @param relayerFee - The updated amount of relayer fee in native asset
   * @param caller - The account that called the function
   */
  event TransferRelayerFeesUpdated(bytes32 indexed transferId, uint256 relayerFee, address caller);

  /**
   * @notice Emitted when a transfer will accept the local asset instead of the
   * previously specified adopted asset.
   * @param transferId - The unique identifier of the crosschain transaction
   * @param canonicalId - The canonical identifier for the local asset
   * @param canonicalDomain - The canonical domain for the local asset
   * @param amount - The amount for the transfer
   */
  event ForcedReceiveLocal(
    bytes32 indexed transferId,
    bytes32 indexed canonicalId,
    uint32 canonicalDomain,
    uint256 amount
  );

  /**
   * @notice Emitted when a router used Aave Portal liquidity for fast transfer
   * @param transferId - The unique identifier of the crosschain transaction
   * @param router - The authorized router that used Aave Portal liquidity
   * @param asset - The asset that was provided by Aave Portal
   * @param amount - The amount of asset that was provided by Aave Portal
   */
  event AavePortalMintUnbacked(bytes32 indexed transferId, address indexed router, address asset, uint256 amount);

  /**
   * @notice Emitted when the sponsorVault variable is updated
   * @param oldSponsorVault - The sponsorVault old value
   * @param newSponsorVault - The sponsorVault new value
   * @param caller - The account that called the function
   */
  event SponsorVaultUpdated(address oldSponsorVault, address newSponsorVault, address caller);

  /**
   * @notice Emitted when the promiseRouter variable is updated
   * @param oldRouter - The promiseRouter old value
   * @param newRouter - The promiseRouter new value
   * @param caller - The account that called the function
   */
  event PromiseRouterUpdated(address oldRouter, address newRouter, address caller);

  /**
   * @notice Emitted when the executor variable is updated
   * @param oldExecutor - The executor old value
   * @param newExecutor - The executor new value
   * @param caller - The account that called the function
   */
  event ExecutorUpdated(address oldExecutor, address newExecutor, address caller);

  /**
   * @notice Emitted when a new connext instance is added
   * @param domain - The domain the connext instance is on
   * @param connext - The address of the connext instance
   * @param caller - The account that called the function
   */
  event ConnextionAdded(uint32 domain, address connext, address caller);

  /**
   * @notice Emitted when a sequencer is added or removed from whitelists
   * @param sequencer - The sequencer address to be added or removed
   * @param caller - The account that called the function
   */
  event SequencerAdded(address sequencer, address caller);

  /**
   * @notice Emitted when a sequencer is added or removed from whitelists
   * @param sequencer - The sequencer address to be added or removed
   * @param caller - The account that called the function
   */
  event SequencerRemoved(address sequencer, address caller);

  // ============ Getters ============

  function relayerFees(bytes32 _transferId) public view returns (uint256) {
    return s.relayerFees[_transferId];
  }

  function routedTransfers(bytes32 _transferId) public view returns (address[] memory) {
    return s.routedTransfers[_transferId];
  }

  function reconciledTransfers(bytes32 _transferId) public view returns (bool) {
    return s.reconciledTransfers[_transferId];
  }

  function connextion(uint32 _domain) public view returns (address) {
    return TypeCasts.bytes32ToAddress(s.connextions[_domain]);
  }

  function domain() public view returns (uint32) {
    return s.domain;
  }

  function executor() public view returns (IExecutor) {
    return s.executor;
  }

  function nonce() public view returns (uint256) {
    return s.nonce;
  }

  function sponsorVault() public view returns (ISponsorVault) {
    return s.sponsorVault;
  }

  function promiseRouter() external view returns (PromiseRouter) {
    return s.promiseRouter;
  }

  // ============ Admin methods ==============

  function setPromiseRouter(address payable _promiseRouter) external onlyOwner {
    address old = address(s.promiseRouter);
    if (old == _promiseRouter || !Address.isContract(_promiseRouter))
      revert BridgeFacet__setPromiseRouter_invalidPromiseRouter();

    s.promiseRouter = PromiseRouter(_promiseRouter);
    emit PromiseRouterUpdated(old, _promiseRouter, msg.sender);
  }

  function setExecutor(address _executor) external onlyOwner {
    address old = address(s.executor);
    if (old == _executor || !Address.isContract(_executor)) revert BridgeFacet__setExecutor_invalidExecutor();

    s.executor = IExecutor(_executor);
    emit ExecutorUpdated(old, _executor, msg.sender);
  }

  function setSponsorVault(address _sponsorVault) external onlyOwner {
    address old = address(s.sponsorVault);
    if (old == _sponsorVault || !Address.isContract(_sponsorVault))
      revert BridgeFacet__setSponsorVault_invalidSponsorVault();

    s.sponsorVault = ISponsorVault(_sponsorVault);
    emit SponsorVaultUpdated(old, _sponsorVault, msg.sender);
  }

  function addConnextion(uint32 _domain, address _connext) external onlyOwner {
    // Make sure we aren't setting the current domain as the connextion.
    if (_domain == s.domain) {
      revert BridgeFacet__addConnextion_invalidDomain();
    }

    s.connextions[_domain] = TypeCasts.addressToBytes32(_connext);
    emit ConnextionAdded(_domain, _connext, msg.sender);
  }

  /**
   * @notice Used to add an approved sequencer to the whitelist.
   * @param _sequencer - The sequencer address to add.
   */
  function addSequencer(address _sequencer) external onlyOwner {
    if (s.approvedSequencers[_sequencer]) revert BridgeFacet__addSequencer_alreadyApproved();
    s.approvedSequencers[_sequencer] = true;

    emit SequencerAdded(_sequencer, msg.sender);
  }

  /**
   * @notice Used to remove an approved sequencer from the whitelist.
   * @param _sequencer - The sequencer address to remove.
   */
  function removeSequencer(address _sequencer) external onlyOwner {
    if (!s.approvedSequencers[_sequencer]) revert BridgeFacet__removeSequencer_notApproved();
    delete s.approvedSequencers[_sequencer];

    emit SequencerRemoved(_sequencer, msg.sender);
  }

  // ============ Public methods ==============

  /**
   * @notice Initiates a cross-chain transfer of funds, calldata, and/or various named properties using the nomad
   * network.
   *
   * @dev For ERC20 transfers, this contract must have approval to transfer the input (transacting) assets. The adopted
   * assets will be swapped for their local nomad asset counterparts (i.e. bridgeable tokens) via the configured AMM if
   * necessary. In the event that the adopted assets *are* local nomad assets, no swap is needed. The local tokens will
   * then be sent via the bridge router. If the local assets are representational for an asset on another chain, we will
   * burn the tokens here. If the local assets are canonical (meaning that the adopted<>local asset pairing is native
   * to this chain), we will custody the tokens here.
   *
   * @param _args - The XCallArgs arguments.
   * @return bytes32 - The transfer ID of the newly created crosschain transfer.
   */
  function xcall(XCallArgs calldata _args) external payable nonReentrant whenNotPaused returns (bytes32) {
    // Sanity checks.
    bytes32 remoteInstance;
    {
      // Not native asset
      if (_args.transactingAsset == address(0)) {
        revert BridgeFacet__xcall_nativeAssetNotSupported();
      }

      // Correct origin domain.
      if (_args.params.originDomain != s.domain) {
        revert BridgeFacet__xcall_wrongDomain();
      }

      // Destination domain is supported.
      // NOTE: This check implicitly also checks that `_args.params.destinationDomain != s.domain`, because the index
      // `s.domain` of `s.connextions` should always be `bytes32(0)`.
      remoteInstance = s.connextions[_args.params.destinationDomain];
      if (remoteInstance == bytes32(0)) {
        revert BridgeFacet__xcall_destinationNotSupported();
      }

      // Recipient and recovery defined.
      if (_args.params.to == address(0) || _args.params.recovery == address(0)) {
        revert BridgeFacet__xcall_emptyToOrRecovery();
      }

      // If the user might be receiving adopted assets on the destination chain, they ought to have a defined agent
      // so that they can call `forceReceiveLocal` if need be.
      if (_args.params.agent == address(0) && !_args.params.receiveLocal) {
        revert BridgeFacet__xcall_missingAgent();
      }

      if (_args.params.callback != address(0)) {
        // Callback address must be a contract if it is supplied.
        if (!Address.isContract(_args.params.callback)) {
          revert BridgeFacet__xcall_callbackNotAContract();
        }
      } else if (_args.params.callbackFee != 0) {
        // Othewrise, if callback address is not set, callback fee should be 0.
        revert BridgeFacet__xcall_nonZeroCallbackFeeForCallback();
      }

      // Check to make sure fee amount in argument is equal to msg.value.
      if (msg.value != _args.params.relayerFee + _args.params.callbackFee) {
        revert BridgeFacet__xcall_ethValueMismatchedFees();
      }
    }

    bytes32 transferId;
    uint256 _sNonce;
    address bridgedAsset;
    uint256 bridgedAmount;
    {
      // Check that the asset is supported -- can be either adopted or local.
      TokenId memory canonical = s.adoptedToCanonical[_args.transactingAsset];
      if (canonical.id == bytes32(0)) {
        // Here, the asset is *not* the adopted asset. The only other valid option
        // is for this asset to be the local asset (i.e. transferring madEth on optimism)
        // NOTE: it *cannot* be the canonical asset. the canonical asset is only used on
        // the canonical domain, where it is *also* the adopted asset.
        if (s.tokenRegistry.isLocalOrigin(_args.transactingAsset)) {
          // revert, using a token of local origin that is not registered as adopted
          revert BridgeFacet__xcall_notSupportedAsset();
        }

        (uint32 canonicalDomain, bytes32 canonicalId) = s.tokenRegistry.getTokenId(_args.transactingAsset);
        canonical = TokenId(canonicalDomain, canonicalId);
      }

      // Transfer funds of transacting asset to the contract from the user.
      AssetLogic.transferAssetToContract(_args.transactingAsset, _args.transactingAmount);

      // Swap to the local asset from adopted if applicable.
      (bridgedAmount, bridgedAsset) = AssetLogic.swapToLocalAssetIfNeeded(
        canonical,
        _args.transactingAsset,
        _args.transactingAmount,
        _args.originMinOut
      );

      // Calculate the transfer id
      transferId = _getTransferId(_args, canonical, bridgedAmount);
      _sNonce = s.nonce++;

      // Store the relayer fee
      // NOTE: this has to be done *after* transferring in + swapping assets because
      // the transfer id uses the amount that is bridged (i.e. amount in local asset)
      s.relayerFees[transferId] += _args.params.relayerFee;

      // Transfer callback fee to PromiseRouter if set
      if (_args.params.callbackFee != 0) {
        s.promiseRouter.initCallbackFee{value: _args.params.callbackFee}(transferId);
      }

      // Approve bridge router
      SafeERC20.safeApprove(IERC20(bridgedAsset), address(s.bridgeRouter), 0);
      SafeERC20.safeIncreaseAllowance(IERC20(bridgedAsset), address(s.bridgeRouter), bridgedAmount);

      // Send message
      s.bridgeRouter.sendToHook(
        bridgedAsset,
        bridgedAmount,
        _args.params.destinationDomain,
        remoteInstance,
        abi.encode(TransferIdInformation(_args.params, _sNonce, msg.sender))
      );
    }

    // emit event
    emit XCalled(transferId, _sNonce, _args, bridgedAsset, bridgedAmount, msg.sender);

    return transferId;
  }

  /**
   * @notice Called on a destination domain to disburse correct assets to end recipient and execute any included
   * calldata.
   *
   * @dev Can be called before or after `handle` [reconcile] is called (regarding the same transfer), depending on
   * whether the fast liquidity route (i.e. funds provided by routers) is being used for this transfer. As a result,
   * executed calldata (including properties like `originSender`) may or may not be verified depending on whether the
   * reconcile has been completed (i.e. the optimistic confirmation period has elapsed).
   *
   * @param _args - ExecuteArgs arguments.
   * @return bytes32 - The transfer ID of the crosschain transfer. Should match the xcall's transfer ID in order for
   * reconciliation to occur.
   */
  function execute(ExecuteArgs calldata _args) external nonReentrant whenNotPaused returns (bytes32) {
    // Retrieve canonical domain and ID for the transacting asset.
    (uint32 canonicalDomain, bytes32 canonicalId) = s.tokenRegistry.getTokenId(_args.local);

    (bytes32 transferId, bool reconciled) = _executeSanityChecks(_args, canonicalDomain, canonicalId);

    // Set the relayer for this transaction to allow for future claim
    s.transferRelayer[transferId] = msg.sender;

    // execute router liquidity when this is a fast transfer
    // asset will be adopted unless specified to be local in params
    (uint256 amountOut, address asset) = _handleExecuteLiquidity(
      transferId,
      _calculateCanonicalHash(canonicalId, canonicalDomain),
      !reconciled,
      _args
    );

    // execute the transaction
    uint256 amountWithSponsors = _handleExecuteTransaction(_args, amountOut, asset, transferId, reconciled);

    // emit event
    emit Executed(transferId, _args.params.to, _args, asset, amountWithSponsors, msg.sender);

    return transferId;
  }

  /**
   * @notice Anyone can call this function on the origin domain to increase the relayer fee for a transfer.
   * @param _transferId - The unique identifier of the crosschain transaction
   */
  function bumpTransfer(bytes32 _transferId) external payable nonReentrant whenNotPaused {
    if (msg.value == 0) revert BridgeFacet__bumpTransfer_valueIsZero();

    s.relayerFees[_transferId] += msg.value;

    emit TransferRelayerFeesUpdated(_transferId, s.relayerFees[_transferId], msg.sender);
  }

  /**
   * @notice A user-specified agent can call this to accept the local asset instead of the
   * previously specified adopted asset.
   * @dev Should be called in situations where transfers are facing unfavorable slippage
   * conditions for extended periods
   * @param _params - The call params for the transaction
   * @param _amount - The amount of transferring asset the tx called xcall with
   * @param _nonce - The nonce for the transfer
   * @param _canonicalId - The identifier of the canonical asset associated with the transfer
   * @param _canonicalDomain - The domain of the canonical asset associated with the transfer
   * @param _originSender - The msg.sender of the origin call
   */
  function forceReceiveLocal(
    CallParams calldata _params,
    uint256 _amount,
    uint256 _nonce,
    bytes32 _canonicalId,
    uint32 _canonicalDomain,
    address _originSender
  ) external nonReentrant {
    // Enforce caller
    if (msg.sender != _params.agent) revert BridgeFacet__forceReceiveLocal_invalidSender();

    // Calculate transfer id
    bytes32 transferId = _calculateTransferId(_params, _amount, _nonce, _canonicalId, _canonicalDomain, _originSender);

    // Store receive local
    s.receiveLocalOverrides[transferId] = true;

    // Emit event
    emit ForcedReceiveLocal(transferId, _canonicalId, _canonicalDomain, _amount);
  }

  // ============ Private Functions ============

  /**
   * @notice Holds the logic to recover the signer from an encoded payload.
   * @dev Will hash and convert to an eth signed message.
   * @param _signed The hash that was signed
   * @param _sig The signature you are recovering the signer from
   */
  function _recoverSignature(bytes32 _signed, bytes calldata _sig) internal pure returns (address) {
    // Recover
    return ECDSA.recover(ECDSA.toEthSignedMessageHash(_signed), _sig);
  }

  /**
   * @notice Performs some sanity checks for `execute`
   * @dev Need this to prevent stack too deep
   */
  function _executeSanityChecks(
    ExecuteArgs calldata _args,
    uint32 canonicalDomain,
    bytes32 canonicalId
  ) private view returns (bytes32, bool) {
    // If the sender is not approved relayer, revert
    if (!s.approvedRelayers[msg.sender] && msg.sender != _args.params.agent) {
      revert BridgeFacet__execute_unapprovedSender();
    }

    // If this is not the destination domain revert
    if (_args.params.destinationDomain != s.domain) {
      revert BridgeFacet__execute_wrongDomain();
    }

    // Path length refers to the number of facilitating routers. A transfer is considered 'multipath'
    // if multiple routers provide liquidity (in even 'shares') for it.
    uint256 pathLength = _args.routers.length;

    // Make sure number of routers is below the configured maximum.
    if (pathLength > s.maxRoutersPerTransfer) revert BridgeFacet__execute_maxRoutersExceeded();

    // Derive transfer ID based on given arguments.
    bytes32 transferId = _getTransferId(_args, canonicalDomain, canonicalId);

    // Retrieve the reconciled record. If the transfer is `forceSlow` then it must be reconciled first
    // before it's executed.
    bool reconciled = s.reconciledTransfers[transferId];
    if (_args.params.forceSlow && !reconciled) revert BridgeFacet__execute_notReconciled();

    // Hash the payload for which each router should have produced a signature.
    // Each router should have signed the `transferId` (which implicitly signs call params,
    // amount, and tokenId) as well as the `pathLength`, or the number of routers with which
    // they are splitting liquidity provision.
    bytes32 routerHash = keccak256(abi.encode(transferId, pathLength));

    if (pathLength != 0) {
      // Check to make sure the transfer has not been reconciled (no need for routers if the transfer is
      // already reconciled; i.e. if there are routers provided, the transfer must *not* be reconciled).
      if (reconciled) revert BridgeFacet__execute_alreadyReconciled();

      // NOTE: The sequencer address may be empty and no signature needs to be provided in the case of the
      // slow liquidity route (i.e. no routers involved). Additionally, the sequencer does not need to be the
      // msg.sender.
      // Check to make sure the sequencer address provided is approved
      if (!s.approvedSequencers[_args.sequencer]) {
        revert BridgeFacet__execute_notSupportedSequencer();
      }
      // Check to make sure the sequencer provided did sign the transfer ID and router path provided.
      if (
        _args.sequencer != _recoverSignature(keccak256(abi.encode(transferId, _args.routers)), _args.sequencerSignature)
      ) {
        revert BridgeFacet__execute_invalidSequencerSignature();
      }

      for (uint256 i; i < pathLength; ) {
        // Make sure the router is approved, if applicable.
        // If router ownership is renounced (_RouterOwnershipRenounced() is true), then the router whitelist
        // no longer applies and we can skip this approval step.
        if (!_isRouterWhitelistRemoved() && !s.routerPermissionInfo.approvedRouters[_args.routers[i]]) {
          revert BridgeFacet__execute_notSupportedRouter();
        }

        // Validate the signature. We'll recover the signer's address using the expected payload and basic ECDSA
        // signature scheme recovery. The address for each signature must match the router's address.
        if (_args.routers[i] != _recoverSignature(routerHash, _args.routerSignatures[i])) {
          revert BridgeFacet__execute_invalidRouterSignature();
        }

        unchecked {
          ++i;
        }
      }
    } else {
      // If there are no routers for this transfer, this `execute` must be a slow liquidity route; in which
      // case, we must make sure the transfer's been reconciled.
      if (!reconciled) revert BridgeFacet__execute_notReconciled();
    }

    // Require that this transfer has not already been executed. If it were executed, the `transferRelayer`
    // would have been set in the previous call (to enable the caller to claim relayer fees).
    if (s.transferRelayer[transferId] != address(0)) {
      revert BridgeFacet__execute_alreadyExecuted();
    }

    return (transferId, reconciled);
  }

  /**
   * @notice Calculates a transferId based on `xcall` arguments
   * @dev Need this to prevent stack too deep
   */
  function _getTransferId(
    XCallArgs calldata _args,
    TokenId memory _canonical,
    uint256 bridgedAmount
  ) private view returns (bytes32) {
    return _calculateTransferId(_args.params, bridgedAmount, s.nonce, _canonical.id, _canonical.domain, msg.sender);
  }

  /**
   * @notice Calculates a transferId based on `execute` arguments
   * @dev Need this to prevent stack too deep
   */
  function _getTransferId(
    ExecuteArgs calldata _args,
    uint32 canonicalDomain,
    bytes32 canonicalId
  ) private pure returns (bytes32) {
    return
      _calculateTransferId(_args.params, _args.amount, _args.nonce, canonicalId, canonicalDomain, _args.originSender);
  }

  /**
   * @notice Calculates fast transfer amount.
   * @param _amount Transfer amount
   * @param _numerator Numerator
   * @param _denominator Denominator
   */
  function _muldiv(
    uint256 _amount,
    uint256 _numerator,
    uint256 _denominator
  ) private pure returns (uint256) {
    return (_amount * _numerator) / _denominator;
  }

  /**
   * @notice Execute liquidity process used when calling `execute`
   * @dev Need this to prevent stack too deep
   */
  function _handleExecuteLiquidity(
    bytes32 _transferId,
    bytes32 _key,
    bool _isFast,
    ExecuteArgs calldata _args
  ) private returns (uint256, address) {
    if (_args.amount == 0) {
      return (0, _args.local);
    }

    bool localRequested = _args.params.receiveLocal || s.receiveLocalOverrides[_transferId];

    uint256 toSwap = _args.amount;
    // If this is a fast liquidity path, we should handle deducting from applicable routers' liquidity.
    // If this is a slow liquidity path, the transfer must have been reconciled (if we've reached this point),
    // and the funds would have been custodied in this contract. The exact custodied amount is untracked in state
    // (since the amount is hashed in the transfer ID itself) - thus, no updates are required.
    if (_isFast) {
      uint256 pathLen = _args.routers.length;

      // Calculate amount that routers will provide with the fast-liquidity fee deducted.
      toSwap = _muldiv(_args.amount, s.LIQUIDITY_FEE_NUMERATOR, BPS_FEE_DENOMINATOR);

      // Save the addresses of all routers providing liquidity for this transfer.
      s.routedTransfers[_transferId] = _args.routers;

      if (pathLen == 1) {
        // If router does not have enough liquidity, try to use Aave Portals.
        // only one router should be responsible for taking on this credit risk, and it should only
        // deal with transfers expecting adopted assets (to avoid introducing runtime slippage).
        if (!localRequested && s.routerBalances[_args.routers[0]][_args.local] < toSwap && s.aavePool != address(0)) {
          if (!s.routerPermissionInfo.approvedForPortalRouters[_args.routers[0]])
            revert BridgeFacet__execute_notApprovedForPortals();

          // Portal provides the adopted asset so we early return here
          return _executePortalTransfer(_transferId, _key, toSwap, _args.routers[0]);
        } else {
          // Decrement the router's liquidity.
          s.routerBalances[_args.routers[0]][_args.local] -= toSwap;
        }
      } else {
        // For each router, assert they are approved, and deduct liquidity.
        uint256 routerAmount = toSwap / pathLen;
        for (uint256 i; i < pathLen - 1; ) {
          // Decrement router's liquidity.
          s.routerBalances[_args.routers[i]][_args.local] -= routerAmount;

          unchecked {
            ++i;
          }
        }
        // The last router in the multipath will sweep the remaining balance to account for remainder dust.
        uint256 toSweep = routerAmount + (toSwap % pathLen);
        s.routerBalances[_args.routers[pathLen - 1]][_args.local] -= toSweep;
      }
    }

    // if the local asset is specified, or the adopted asset was overridden (i.e. when
    // user facing slippage conditions outside of their boundaries), exit
    if (localRequested) {
      return (toSwap, _args.local);
    }

    // swap out of mad* asset into adopted asset if needed
    return AssetLogic.swapFromLocalAssetIfNeeded(_key, _args.local, toSwap, _args.params.destinationMinOut);
  }

  /**
   * @notice Process the transfer, and calldata if needed, when calling `execute`
   * @dev Need this to prevent stack too deep
   */
  function _handleExecuteTransaction(
    ExecuteArgs calldata _args,
    uint256 _amountOut,
    address _asset, // adopted (or local if specified)
    bytes32 _transferId,
    bool _reconciled
  ) private returns (uint256) {
    // If the domain if sponsored
    if (address(s.sponsorVault) != address(0)) {
      // fast liquidity path
      if (!_reconciled) {
        // Vault will return the amount of the fee they sponsored in the native fee
        // NOTE: some considerations here around fee on transfer tokens and ensuring
        // there are no malicious `Vaults` that do not transfer the correct amount. Should likely do a
        // balance read about it

        uint256 starting = IERC20(_asset).balanceOf(address(this));
        uint256 denom = BPS_FEE_DENOMINATOR;
        // NOTE: using the amount that was transferred to calculate the liquidity fee, not the _amountOut
        // which already has fees debited and was swapped
        uint256 liquidityFee = _muldiv(_args.amount, (denom - s.LIQUIDITY_FEE_NUMERATOR), denom);

        (bool success, bytes memory data) = address(s.sponsorVault).call(
          abi.encodeWithSelector(s.sponsorVault.reimburseLiquidityFees.selector, _asset, liquidityFee, _args.params.to)
        );

        if (success) {
          uint256 sponsored = abi.decode(data, (uint256));

          // Validate correct amounts are transferred
          if (IERC20(_asset).balanceOf(address(this)) != starting + sponsored) {
            revert BridgeFacet__handleExecuteTransaction_invalidSponsoredAmount();
          }

          _amountOut += sponsored;
        }
      }

      // Should dust the recipient with the lesser of a vault-defined cap or the converted relayer fee
      // If there is no conversion available (i.e. no oracles for origin domain asset <> dest asset pair),
      // then the vault should just pay out the configured constant
      address(s.sponsorVault).call(
        abi.encodeWithSelector(
          s.sponsorVault.reimburseRelayerFees.selector,
          _args.params.originDomain,
          payable(_args.params.to),
          _args.params.relayerFee
        )
      );
    }

    // execute the the transaction
    if (keccak256(_args.params.callData) == EMPTY_HASH) {
      // no call data, send funds to the user
      AssetLogic.handleOutgoingAsset(_asset, _args.params.to, _amountOut);
    } else {
      // execute calldata w/funds
      AssetLogic.handleOutgoingAsset(_asset, address(s.executor), _amountOut);

      (bool success, bytes memory returnData) = s.executor.execute(
        IExecutor.ExecutorArgs(
          _transferId,
          _amountOut,
          _args.params.to,
          _args.params.recovery,
          _asset,
          _reconciled
            ? LibCrossDomainProperty.formatDomainAndSenderBytes(_args.params.originDomain, _args.originSender)
            : LibCrossDomainProperty.EMPTY_BYTES,
          _args.params.callData
        )
      );

      // If callback address is not zero, send on the PromiseRouter
      if (_args.params.callback != address(0)) {
        s.promiseRouter.send(_args.params.originDomain, _transferId, _args.params.callback, success, returnData);
      }
    }

    return _amountOut;
  }

  /**
   * @notice Uses Aave Portals to provide fast liquidity
   */
  function _executePortalTransfer(
    bytes32 _transferId,
    bytes32 _key,
    uint256 _fastTransferAmount,
    address _router
  ) internal returns (uint256, address) {
    // Calculate local to adopted swap output if needed
    address adopted = s.canonicalToAdopted[_key];

    IAavePool(s.aavePool).mintUnbacked(adopted, _fastTransferAmount, address(this), AAVE_REFERRAL_CODE);

    // Improvement: Instead of withdrawing to address(this), withdraw directly to the user or executor to save 1 transfer
    uint256 amountWithdrawn = IAavePool(s.aavePool).withdraw(adopted, _fastTransferAmount, address(this));

    if (amountWithdrawn < _fastTransferAmount) revert BridgeFacet__executePortalTransfer_insufficientAmountWithdrawn();

    // Store principle debt
    s.portalDebt[_transferId] = _fastTransferAmount;

    // Store fee debt
    s.portalFeeDebt[_transferId] = (s.aavePortalFeeNumerator * _fastTransferAmount) / BPS_FEE_DENOMINATOR;

    emit AavePortalMintUnbacked(_transferId, _router, adopted, _fastTransferAmount);

    return (_fastTransferAmount, adopted);
  }
}
