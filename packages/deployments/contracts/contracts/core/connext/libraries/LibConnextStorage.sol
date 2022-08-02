// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {RelayerFeeRouter} from "../../relayer-fee/RelayerFeeRouter.sol";
import {PromiseRouter} from "../../promise/PromiseRouter.sol";

import {IWeth} from "../interfaces/IWeth.sol";
import {ITokenRegistry} from "../interfaces/ITokenRegistry.sol";

import {IBridgeRouter} from "../interfaces/IBridgeRouter.sol";
import {IExecutor} from "../interfaces/IExecutor.sol";
import {IStableSwap} from "../interfaces/IStableSwap.sol";
import {ISponsorVault} from "../interfaces/ISponsorVault.sol";

import {SwapUtils} from "./SwapUtils.sol";

// ============= Structs =============

struct TokenId {
  uint32 domain;
  bytes32 id;
}

/**
 * @notice Contains all information needed to calculate transfer id within the
 * `onReceive` hook from nomad.
 * @dev This excludes information that is included within that interface
 */
struct TransferIdInformation {
  CallParams params;
  uint256 nonce;
  address originSender;
}

/**
 * @notice These are the call parameters that will remain constant between the
 * two chains. They are supplied on `xcall` and should be asserted on `execute`
 * @property to - The account that receives funds, in the event of a crosschain call,
 * will receive funds if the call fails.
 *
 * @param to - The address you are sending funds (and potentially data) to
 * @param callData - The data to execute on the receiving chain. If no crosschain call is needed, then leave empty.
 * @param originDomain - The originating domain (i.e. where `xcall` is called). Must match nomad domain schema
 * @param destinationDomain - The final domain (i.e. where `execute` / `reconcile` are called). Must match nomad domain schema
 * @param agent - An address who can execute txs on behalf of `to`, in addition to allowing relayers
 * @param recovery - The address to send funds to if your `Executor.execute call` fails
 * @param callback - The address on the origin domain of the callback contract
 * @param callbackFee - The relayer fee to execute the callback
 * @param forceSlow - If true, will take slow liquidity path even if it is not a permissioned call
 * @param receiveLocal - If true, will use the local nomad asset on the destination instead of adopted.
 * @param relayerFee - The amount of relayer fee the tx called xcall with
 * @param destinationMinOut - Minimum amount received on swaps for local <> adopted on destination chain.
 */
struct CallParams {
  address to;
  bytes callData;
  uint32 originDomain;
  uint32 destinationDomain;
  address agent;
  address recovery;
  bool forceSlow;
  bool receiveLocal;
  address callback;
  uint256 callbackFee;
  uint256 relayerFee;
  uint256 destinationMinOut;
}

/**
 * @notice The arguments you supply to the `xcall` function called by user on origin domain
 * @param params - The CallParams. These are consistent across sending and receiving chains
 * @param transactingAsset - The asset the caller sent with the transfer. Can be the adopted, canonical,
 * or the representational asset.
 * @param transactingAmount - The amount of transferring asset supplied by the user in the `xcall`.
 * @param originMinOut - Minimum amount received on swaps for adopted <> local on origin chain
 */
struct XCallArgs {
  CallParams params;
  address transactingAsset; // Could be adopted, local, or canonical.
  uint256 transactingAmount;
  uint256 originMinOut;
}

/**
 * @notice
 * @param params - The CallParams. These are consistent across sending and receiving chains.
 * @param local - The local asset for the transfer, will be swapped to the adopted asset if
 * appropriate.
 * @param routers - The routers who you are sending the funds on behalf of.
 * @param routerSignatures - Signatures belonging to the routers indicating permission to use funds
 * for the signed transfer ID.
 * @param sequencer - The sequencer who assigned the router path to this transfer.
 * @param sequencerSignature - Signature produced by the sequencer for path assignment accountability
 * for the path that was signed.
 * @param amount - The amount of liquidity the router provided or the bridge forwarded, depending on
 * whether fast liquidity was used.
 * @param nonce - The nonce used to generate transfer ID.
 * @param originSender - The msg.sender of the xcall on origin domain.
 */
struct ExecuteArgs {
  CallParams params;
  address local; // local representation of canonical token
  address[] routers;
  bytes[] routerSignatures;
  address sequencer;
  bytes sequencerSignature;
  uint256 amount;
  uint256 nonce;
  address originSender;
}

/**
 * @notice Contains RouterFacet related state
 * @param approvedRouters - Mapping of whitelisted router addresses
 * @param routerRecipients - Mapping of router withdraw recipient addresses.
 * If set, all liquidity is withdrawn only to this address. Must be set by routerOwner
 * (if configured) or the router itself
 * @param routerOwners - Mapping of router owners
 * If set, can update the routerRecipient
 * @param proposedRouterOwners - Mapping of proposed router owners
 * Must wait timeout to set the
 * @param proposedRouterTimestamp - Mapping of proposed router owners timestamps
 * When accepting a proposed owner, must wait for delay to elapse
 */
struct RouterPermissionsManagerInfo {
  mapping(address => bool) approvedRouters;
  mapping(address => bool) approvedForPortalRouters;
  mapping(address => address) routerRecipients;
  mapping(address => address) routerOwners;
  mapping(address => address) proposedRouterOwners;
  mapping(address => uint256) proposedRouterTimestamp;
}

struct AppStorage {
  //
  // 0
  bool initialized;
  //
  // ConnextHandler
  //
  // 1
  uint256 LIQUIDITY_FEE_NUMERATOR;
  // The local nomad relayer fee router
  // 2
  RelayerFeeRouter relayerFeeRouter;
  // The local nomad promise callback router
  // 3
  PromiseRouter promiseRouter;
  /**
   * @notice Nonce for the contract, used to keep unique transfer ids.
   * @dev Assigned at first interaction (xcall on origin domain);
   */
  // 4
  uint256 nonce;
  /**
   * @notice The external contract that will execute crosschain calldata
   */
  // 5
  IExecutor executor;
  /**
   * @notice The domain this contract exists on
   * @dev Must match the nomad domain, which is distinct from the "chainId"
   */
  // 6
  uint32 domain;
  /**
   * @notice The local nomad token registry
   */
  // 7
  ITokenRegistry tokenRegistry;
  /**
   * @notice Mapping holding the AMMs for swapping in and out of local assets
   * @dev Swaps for an adopted asset <> nomad local asset (i.e. POS USDC <> madUSDC on polygon).
   * This mapping is keyed on the hash of the canonical id + domain for local asset
   */
  // 8
  mapping(bytes32 => IStableSwap) adoptedToLocalPools;
  /**
   * @notice Mapping of whitelisted assets on same domain as contract
   * @dev Mapping is keyed on the hash of the canonical id and domain taken from the
   * token registry
   */
  // 9
  mapping(bytes32 => bool) approvedAssets;
  /**
   * @notice Mapping of adopted to canonical asset information
   * @dev If the adopted asset is the native asset, the keyed address will
   * be the wrapped asset address
   */
  // 10
  mapping(address => TokenId) adoptedToCanonical;
  /**
   * @notice Mapping of hash(canonicalId, canonicalDomain) to adopted asset on this domain
   * @dev If the adopted asset is the native asset, the stored address will be the
   * wrapped asset address
   */
  // 11
  mapping(bytes32 => address) canonicalToAdopted;
  /**
   * @notice Mapping to determine if transfer is reconciled
   */
  // 12
  mapping(bytes32 => bool) reconciledTransfers;
  /**
   * @notice Mapping holding router address that provided fast liquidity
   */
  // 13
  mapping(bytes32 => address[]) routedTransfers;
  /**
   * @notice Mapping of router to available balance of an asset
   * @dev Routers should always store liquidity that they can expect to receive via the bridge on
   * this domain (the nomad local asset)
   */
  // 14
  mapping(address => mapping(address => uint256)) routerBalances;
  /**
   * @notice Mapping of approved relayers
   * @dev Send relayer fee if msg.sender is approvedRelayer. otherwise revert()
   */
  // 15
  mapping(address => bool) approvedRelayers;
  /**
   * @notice Stores the relayer fee for a transfer. Updated on origin domain when a user calls xcall or bump
   * @dev This will track all of the relayer fees assigned to a transfer by id, including any bumps made by the relayer
   */
  // 16
  mapping(bytes32 => uint256) relayerFees;
  /**
   * @notice Stores the relayer of a transfer. Updated on the destination domain when a relayer calls execute
   * for transfer
   * @dev When relayer claims, must check that the msg.sender has forwarded transfer
   */
  // 17
  mapping(bytes32 => address) transferRelayer;
  /**
   * @notice The max amount of routers a payment can be routed through
   */
  // 18
  uint256 maxRoutersPerTransfer;
  /**
   * @notice The Vault used for sponsoring fees
   */
  // 19
  ISponsorVault sponsorVault;
  /**
   * @notice The address of the nomad bridge router for this chain
   */
  // 20
  IBridgeRouter bridgeRouter;
  /**
   * @notice Stores whether a transfer has had `receiveLocal` overrides forced
   */
  // 21
  mapping(bytes32 => bool) receiveLocalOverrides;
  /**
   * @notice Stores a mapping of connext addresses keyed on domains
   * @dev Addresses are cast to bytes32
   */
  // 22
  mapping(uint32 => bytes32) connextions;
  //
  // ProposedOwnable
  //
  // 23
  address _proposed;
  // 24
  uint256 _proposedOwnershipTimestamp;
  // 25
  bool _routerWhitelistRemoved;
  // 26
  uint256 _routerWhitelistTimestamp;
  // 27
  bool _assetWhitelistRemoved;
  // 28
  uint256 _assetWhitelistTimestamp;
  //
  // RouterFacet
  //
  // 29
  RouterPermissionsManagerInfo routerPermissionInfo;
  //
  // ReentrancyGuard
  //
  // 30
  uint256 _status;
  //
  // StableSwap
  //
  /**
   * @notice Mapping holding the AMM storages for swapping in and out of local assets
   * @dev Swaps for an adopted asset <> nomad local asset (i.e. POS USDC <> madUSDC on polygon)
   * Struct storing data responsible for automatic market maker functionalities. In order to
   * access this data, this contract uses SwapUtils library. For more details, see SwapUtils.sol
   */
  // 31
  mapping(bytes32 => SwapUtils.Swap) swapStorages;
  /**
   * @notice Maps token address to an index in the pool. Used to prevent duplicate tokens in the pool.
   * @dev getTokenIndex function also relies on this mapping to retrieve token index.
   */
  // 32
  mapping(bytes32 => mapping(address => uint8)) tokenIndexes;
  /**
   * @notice Stores whether or not bribing, AMMs, have been paused
   */
  // 33
  bool _paused;
  //
  // AavePortals
  //
  /**
   * @notice Address of Aave Pool contract
   */
  // 34
  address aavePool;
  /**
   * @notice Fee percentage numerator for using Portal liquidity
   * @dev Assumes the same basis points as the liquidity fee
   */
  // 35
  uint256 aavePortalFeeNumerator;
  /**
   * @notice Mapping to store the transfer liquidity amount provided by Aave Portals
   */
  // 36
  mapping(bytes32 => uint256) portalDebt;
  /**
   * @notice Mapping to store the transfer liquidity amount provided by Aave Portals
   */
  // 37
  mapping(bytes32 => uint256) portalFeeDebt;
  /**
   * @notice Mapping of approved sequencers
   * @dev Sequencer address provided must belong to an approved sequencer in order to call `execute`
   * for the fast liquidity route.
   */
  // 38
  mapping(address => bool) approvedSequencers;
}

library LibConnextStorage {
  function connextStorage() internal pure returns (AppStorage storage ds) {
    assembly {
      ds.slot := 0
    }
  }
}
