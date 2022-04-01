/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import type {
  BaseContract,
  BigNumber,
  BigNumberish,
  BytesLike,
  CallOverrides,
  ContractTransaction,
  Overrides,
  PayableOverrides,
  PopulatedTransaction,
  Signer,
  utils,
} from "ethers";
import type {
  FunctionFragment,
  Result,
  EventFragment,
} from "@ethersproject/abi";
import type { Listener, Provider } from "@ethersproject/providers";
import type {
  TypedEventFilter,
  TypedEvent,
  TypedListener,
  OnEvent,
} from "../../common";

export declare namespace IConnext {
  export type CallParamsStruct = {
    to: string;
    callData: BytesLike;
    originDomain: BigNumberish;
    destinationDomain: BigNumberish;
  };

  export type CallParamsStructOutput = [string, string, number, number] & {
    to: string;
    callData: string;
    originDomain: number;
    destinationDomain: number;
  };

  export type ExecutedTransferStruct = { router: string; amount: BigNumberish };

  export type ExecutedTransferStructOutput = [string, BigNumber] & {
    router: string;
    amount: BigNumber;
  };

  export type ExecuteArgsStruct = {
    params: IConnext.CallParamsStruct;
    local: string;
    router: string;
    feePercentage: BigNumberish;
    amount: BigNumberish;
    nonce: BigNumberish;
    relayerSignature: BytesLike;
    originSender: string;
  };

  export type ExecuteArgsStructOutput = [
    IConnext.CallParamsStructOutput,
    string,
    string,
    number,
    BigNumber,
    BigNumber,
    string,
    string
  ] & {
    params: IConnext.CallParamsStructOutput;
    local: string;
    router: string;
    feePercentage: number;
    amount: BigNumber;
    nonce: BigNumber;
    relayerSignature: string;
    originSender: string;
  };

  export type XCallArgsStruct = {
    params: IConnext.CallParamsStruct;
    transactingAssetId: string;
    amount: BigNumberish;
  };

  export type XCallArgsStructOutput = [
    IConnext.CallParamsStructOutput,
    string,
    BigNumber
  ] & {
    params: IConnext.CallParamsStructOutput;
    transactingAssetId: string;
    amount: BigNumber;
  };
}

export declare namespace BridgeMessage {
  export type TokenIdStruct = { domain: BigNumberish; id: BytesLike };

  export type TokenIdStructOutput = [number, string] & {
    domain: number;
    id: string;
  };
}

export interface IConnextInterface extends utils.Interface {
  functions: {
    "addLiquidity(uint256,address)": FunctionFragment;
    "addLiquidityFor(uint256,address,address)": FunctionFragment;
    "addRelayerFees(address)": FunctionFragment;
    "addStableSwapPool((uint32,bytes32),address)": FunctionFragment;
    "execute(((address,bytes,uint32,uint32),address,address,uint32,uint256,uint256,bytes,address))": FunctionFragment;
    "initialize(uint256,address,address,address)": FunctionFragment;
    "reconcile(bytes32,uint32,address,address,uint256)": FunctionFragment;
    "removeAssetId(bytes32,address)": FunctionFragment;
    "removeLiquidity(uint256,address,address)": FunctionFragment;
    "removeRelayerFees(uint256,address)": FunctionFragment;
    "removeRouter(address)": FunctionFragment;
    "setupAsset((uint32,bytes32),address,address)": FunctionFragment;
    "setupRouter(address,address,address)": FunctionFragment;
    "xcall(((address,bytes,uint32,uint32),address,uint256))": FunctionFragment;
  };

  getFunction(
    nameOrSignatureOrTopic:
      | "addLiquidity"
      | "addLiquidityFor"
      | "addRelayerFees"
      | "addStableSwapPool"
      | "execute"
      | "initialize"
      | "reconcile"
      | "removeAssetId"
      | "removeLiquidity"
      | "removeRelayerFees"
      | "removeRouter"
      | "setupAsset"
      | "setupRouter"
      | "xcall"
  ): FunctionFragment;

  encodeFunctionData(
    functionFragment: "addLiquidity",
    values: [BigNumberish, string]
  ): string;
  encodeFunctionData(
    functionFragment: "addLiquidityFor",
    values: [BigNumberish, string, string]
  ): string;
  encodeFunctionData(
    functionFragment: "addRelayerFees",
    values: [string]
  ): string;
  encodeFunctionData(
    functionFragment: "addStableSwapPool",
    values: [BridgeMessage.TokenIdStruct, string]
  ): string;
  encodeFunctionData(
    functionFragment: "execute",
    values: [IConnext.ExecuteArgsStruct]
  ): string;
  encodeFunctionData(
    functionFragment: "initialize",
    values: [BigNumberish, string, string, string]
  ): string;
  encodeFunctionData(
    functionFragment: "reconcile",
    values: [BytesLike, BigNumberish, string, string, BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "removeAssetId",
    values: [BytesLike, string]
  ): string;
  encodeFunctionData(
    functionFragment: "removeLiquidity",
    values: [BigNumberish, string, string]
  ): string;
  encodeFunctionData(
    functionFragment: "removeRelayerFees",
    values: [BigNumberish, string]
  ): string;
  encodeFunctionData(
    functionFragment: "removeRouter",
    values: [string]
  ): string;
  encodeFunctionData(
    functionFragment: "setupAsset",
    values: [BridgeMessage.TokenIdStruct, string, string]
  ): string;
  encodeFunctionData(
    functionFragment: "setupRouter",
    values: [string, string, string]
  ): string;
  encodeFunctionData(
    functionFragment: "xcall",
    values: [IConnext.XCallArgsStruct]
  ): string;

  decodeFunctionResult(
    functionFragment: "addLiquidity",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "addLiquidityFor",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "addRelayerFees",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "addStableSwapPool",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "execute", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "initialize", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "reconcile", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "removeAssetId",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "removeLiquidity",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "removeRelayerFees",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "removeRouter",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "setupAsset", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "setupRouter",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "xcall", data: BytesLike): Result;

  events: {
    "AssetAdded(bytes32,uint32,address,address,address)": EventFragment;
    "AssetRemoved(bytes32,address)": EventFragment;
    "Executed(bytes32,address,address,tuple,address,address,uint256,uint256,address)": EventFragment;
    "LiquidityAdded(address,address,bytes32,uint256,address)": EventFragment;
    "LiquidityRemoved(address,address,address,uint256,address)": EventFragment;
    "Reconciled(bytes32,uint32,address,address,address,uint256,tuple,address)": EventFragment;
    "StableSwapAdded(bytes32,uint32,address,address)": EventFragment;
    "XCalled(bytes32,address,tuple,address,address,uint256,uint256,uint256,address)": EventFragment;
  };

  getEvent(nameOrSignatureOrTopic: "AssetAdded"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "AssetRemoved"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "Executed"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "LiquidityAdded"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "LiquidityRemoved"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "Reconciled"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "StableSwapAdded"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "XCalled"): EventFragment;
}

export interface AssetAddedEventObject {
  canonicalId: string;
  domain: number;
  adoptedAsset: string;
  supportedAsset: string;
  caller: string;
}
export type AssetAddedEvent = TypedEvent<
  [string, number, string, string, string],
  AssetAddedEventObject
>;

export type AssetAddedEventFilter = TypedEventFilter<AssetAddedEvent>;

export interface AssetRemovedEventObject {
  canonicalId: string;
  caller: string;
}
export type AssetRemovedEvent = TypedEvent<
  [string, string],
  AssetRemovedEventObject
>;

export type AssetRemovedEventFilter = TypedEventFilter<AssetRemovedEvent>;

export interface ExecutedEventObject {
  transferId: string;
  to: string;
  router: string;
  params: IConnext.CallParamsStructOutput;
  localAsset: string;
  transactingAsset: string;
  localAmount: BigNumber;
  transactingAmount: BigNumber;
  caller: string;
}
export type ExecutedEvent = TypedEvent<
  [
    string,
    string,
    string,
    IConnext.CallParamsStructOutput,
    string,
    string,
    BigNumber,
    BigNumber,
    string
  ],
  ExecutedEventObject
>;

export type ExecutedEventFilter = TypedEventFilter<ExecutedEvent>;

export interface LiquidityAddedEventObject {
  router: string;
  local: string;
  canonicalId: string;
  amount: BigNumber;
  caller: string;
}
export type LiquidityAddedEvent = TypedEvent<
  [string, string, string, BigNumber, string],
  LiquidityAddedEventObject
>;

export type LiquidityAddedEventFilter = TypedEventFilter<LiquidityAddedEvent>;

export interface LiquidityRemovedEventObject {
  router: string;
  to: string;
  local: string;
  amount: BigNumber;
  caller: string;
}
export type LiquidityRemovedEvent = TypedEvent<
  [string, string, string, BigNumber, string],
  LiquidityRemovedEventObject
>;

export type LiquidityRemovedEventFilter =
  TypedEventFilter<LiquidityRemovedEvent>;

export interface ReconciledEventObject {
  transferId: string;
  origin: number;
  router: string;
  localAsset: string;
  to: string;
  localAmount: BigNumber;
  executed: IConnext.ExecutedTransferStructOutput;
  caller: string;
}
export type ReconciledEvent = TypedEvent<
  [
    string,
    number,
    string,
    string,
    string,
    BigNumber,
    IConnext.ExecutedTransferStructOutput,
    string
  ],
  ReconciledEventObject
>;

export type ReconciledEventFilter = TypedEventFilter<ReconciledEvent>;

export interface StableSwapAddedEventObject {
  canonicalId: string;
  domain: number;
  swapPool: string;
  caller: string;
}
export type StableSwapAddedEvent = TypedEvent<
  [string, number, string, string],
  StableSwapAddedEventObject
>;

export type StableSwapAddedEventFilter = TypedEventFilter<StableSwapAddedEvent>;

export interface XCalledEventObject {
  transferId: string;
  to: string;
  params: IConnext.CallParamsStructOutput;
  transactingAsset: string;
  localAsset: string;
  transactingAmount: BigNumber;
  localAmount: BigNumber;
  nonce: BigNumber;
  caller: string;
}
export type XCalledEvent = TypedEvent<
  [
    string,
    string,
    IConnext.CallParamsStructOutput,
    string,
    string,
    BigNumber,
    BigNumber,
    BigNumber,
    string
  ],
  XCalledEventObject
>;

export type XCalledEventFilter = TypedEventFilter<XCalledEvent>;

export interface IConnext extends BaseContract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  interface: IConnextInterface;

  queryFilter<TEvent extends TypedEvent>(
    event: TypedEventFilter<TEvent>,
    fromBlockOrBlockhash?: string | number | undefined,
    toBlock?: string | number | undefined
  ): Promise<Array<TEvent>>;

  listeners<TEvent extends TypedEvent>(
    eventFilter?: TypedEventFilter<TEvent>
  ): Array<TypedListener<TEvent>>;
  listeners(eventName?: string): Array<Listener>;
  removeAllListeners<TEvent extends TypedEvent>(
    eventFilter: TypedEventFilter<TEvent>
  ): this;
  removeAllListeners(eventName?: string): this;
  off: OnEvent<this>;
  on: OnEvent<this>;
  once: OnEvent<this>;
  removeListener: OnEvent<this>;

  functions: {
    addLiquidity(
      amount: BigNumberish,
      local: string,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    addLiquidityFor(
      amount: BigNumberish,
      local: string,
      router: string,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    addRelayerFees(
      router: string,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    addStableSwapPool(
      canonical: BridgeMessage.TokenIdStruct,
      stableSwapPool: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    execute(
      _args: IConnext.ExecuteArgsStruct,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    initialize(
      _domain: BigNumberish,
      _bridgeRouter: string,
      _tokenRegistry: string,
      _wrappedNative: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    reconcile(
      _transferId: BytesLike,
      _origin: BigNumberish,
      _local: string,
      _recipient: string,
      _amount: BigNumberish,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    removeAssetId(
      canonicalId: BytesLike,
      adoptedAssetId: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    removeLiquidity(
      amount: BigNumberish,
      local: string,
      to: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    removeRelayerFees(
      amount: BigNumberish,
      to: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    removeRouter(
      router: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    setupAsset(
      canonical: BridgeMessage.TokenIdStruct,
      adoptedAssetId: string,
      stableSwapPool: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    setupRouter(
      router: string,
      owner: string,
      recipient: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    xcall(
      _args: IConnext.XCallArgsStruct,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;
  };

  addLiquidity(
    amount: BigNumberish,
    local: string,
    overrides?: PayableOverrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  addLiquidityFor(
    amount: BigNumberish,
    local: string,
    router: string,
    overrides?: PayableOverrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  addRelayerFees(
    router: string,
    overrides?: PayableOverrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  addStableSwapPool(
    canonical: BridgeMessage.TokenIdStruct,
    stableSwapPool: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  execute(
    _args: IConnext.ExecuteArgsStruct,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  initialize(
    _domain: BigNumberish,
    _bridgeRouter: string,
    _tokenRegistry: string,
    _wrappedNative: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  reconcile(
    _transferId: BytesLike,
    _origin: BigNumberish,
    _local: string,
    _recipient: string,
    _amount: BigNumberish,
    overrides?: PayableOverrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  removeAssetId(
    canonicalId: BytesLike,
    adoptedAssetId: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  removeLiquidity(
    amount: BigNumberish,
    local: string,
    to: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  removeRelayerFees(
    amount: BigNumberish,
    to: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  removeRouter(
    router: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  setupAsset(
    canonical: BridgeMessage.TokenIdStruct,
    adoptedAssetId: string,
    stableSwapPool: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  setupRouter(
    router: string,
    owner: string,
    recipient: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  xcall(
    _args: IConnext.XCallArgsStruct,
    overrides?: PayableOverrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  callStatic: {
    addLiquidity(
      amount: BigNumberish,
      local: string,
      overrides?: CallOverrides
    ): Promise<void>;

    addLiquidityFor(
      amount: BigNumberish,
      local: string,
      router: string,
      overrides?: CallOverrides
    ): Promise<void>;

    addRelayerFees(router: string, overrides?: CallOverrides): Promise<void>;

    addStableSwapPool(
      canonical: BridgeMessage.TokenIdStruct,
      stableSwapPool: string,
      overrides?: CallOverrides
    ): Promise<void>;

    execute(
      _args: IConnext.ExecuteArgsStruct,
      overrides?: CallOverrides
    ): Promise<string>;

    initialize(
      _domain: BigNumberish,
      _bridgeRouter: string,
      _tokenRegistry: string,
      _wrappedNative: string,
      overrides?: CallOverrides
    ): Promise<void>;

    reconcile(
      _transferId: BytesLike,
      _origin: BigNumberish,
      _local: string,
      _recipient: string,
      _amount: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>;

    removeAssetId(
      canonicalId: BytesLike,
      adoptedAssetId: string,
      overrides?: CallOverrides
    ): Promise<void>;

    removeLiquidity(
      amount: BigNumberish,
      local: string,
      to: string,
      overrides?: CallOverrides
    ): Promise<void>;

    removeRelayerFees(
      amount: BigNumberish,
      to: string,
      overrides?: CallOverrides
    ): Promise<void>;

    removeRouter(router: string, overrides?: CallOverrides): Promise<void>;

    setupAsset(
      canonical: BridgeMessage.TokenIdStruct,
      adoptedAssetId: string,
      stableSwapPool: string,
      overrides?: CallOverrides
    ): Promise<void>;

    setupRouter(
      router: string,
      owner: string,
      recipient: string,
      overrides?: CallOverrides
    ): Promise<void>;

    xcall(
      _args: IConnext.XCallArgsStruct,
      overrides?: CallOverrides
    ): Promise<string>;
  };

  filters: {
    "AssetAdded(bytes32,uint32,address,address,address)"(
      canonicalId?: null,
      domain?: null,
      adoptedAsset?: null,
      supportedAsset?: null,
      caller?: null
    ): AssetAddedEventFilter;
    AssetAdded(
      canonicalId?: null,
      domain?: null,
      adoptedAsset?: null,
      supportedAsset?: null,
      caller?: null
    ): AssetAddedEventFilter;

    "AssetRemoved(bytes32,address)"(
      canonicalId?: null,
      caller?: null
    ): AssetRemovedEventFilter;
    AssetRemoved(canonicalId?: null, caller?: null): AssetRemovedEventFilter;

    "Executed(bytes32,address,address,tuple,address,address,uint256,uint256,address)"(
      transferId?: BytesLike | null,
      to?: string | null,
      router?: string | null,
      params?: null,
      localAsset?: null,
      transactingAsset?: null,
      localAmount?: null,
      transactingAmount?: null,
      caller?: null
    ): ExecutedEventFilter;
    Executed(
      transferId?: BytesLike | null,
      to?: string | null,
      router?: string | null,
      params?: null,
      localAsset?: null,
      transactingAsset?: null,
      localAmount?: null,
      transactingAmount?: null,
      caller?: null
    ): ExecutedEventFilter;

    "LiquidityAdded(address,address,bytes32,uint256,address)"(
      router?: string | null,
      local?: null,
      canonicalId?: null,
      amount?: null,
      caller?: null
    ): LiquidityAddedEventFilter;
    LiquidityAdded(
      router?: string | null,
      local?: null,
      canonicalId?: null,
      amount?: null,
      caller?: null
    ): LiquidityAddedEventFilter;

    "LiquidityRemoved(address,address,address,uint256,address)"(
      router?: string | null,
      to?: null,
      local?: null,
      amount?: null,
      caller?: null
    ): LiquidityRemovedEventFilter;
    LiquidityRemoved(
      router?: string | null,
      to?: null,
      local?: null,
      amount?: null,
      caller?: null
    ): LiquidityRemovedEventFilter;

    "Reconciled(bytes32,uint32,address,address,address,uint256,tuple,address)"(
      transferId?: BytesLike | null,
      origin?: BigNumberish | null,
      router?: string | null,
      localAsset?: null,
      to?: null,
      localAmount?: null,
      executed?: null,
      caller?: null
    ): ReconciledEventFilter;
    Reconciled(
      transferId?: BytesLike | null,
      origin?: BigNumberish | null,
      router?: string | null,
      localAsset?: null,
      to?: null,
      localAmount?: null,
      executed?: null,
      caller?: null
    ): ReconciledEventFilter;

    "StableSwapAdded(bytes32,uint32,address,address)"(
      canonicalId?: null,
      domain?: null,
      swapPool?: null,
      caller?: null
    ): StableSwapAddedEventFilter;
    StableSwapAdded(
      canonicalId?: null,
      domain?: null,
      swapPool?: null,
      caller?: null
    ): StableSwapAddedEventFilter;

    "XCalled(bytes32,address,tuple,address,address,uint256,uint256,uint256,address)"(
      transferId?: BytesLike | null,
      to?: string | null,
      params?: null,
      transactingAsset?: null,
      localAsset?: null,
      transactingAmount?: null,
      localAmount?: null,
      nonce?: null,
      caller?: null
    ): XCalledEventFilter;
    XCalled(
      transferId?: BytesLike | null,
      to?: string | null,
      params?: null,
      transactingAsset?: null,
      localAsset?: null,
      transactingAmount?: null,
      localAmount?: null,
      nonce?: null,
      caller?: null
    ): XCalledEventFilter;
  };

  estimateGas: {
    addLiquidity(
      amount: BigNumberish,
      local: string,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    addLiquidityFor(
      amount: BigNumberish,
      local: string,
      router: string,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    addRelayerFees(
      router: string,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    addStableSwapPool(
      canonical: BridgeMessage.TokenIdStruct,
      stableSwapPool: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    execute(
      _args: IConnext.ExecuteArgsStruct,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    initialize(
      _domain: BigNumberish,
      _bridgeRouter: string,
      _tokenRegistry: string,
      _wrappedNative: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    reconcile(
      _transferId: BytesLike,
      _origin: BigNumberish,
      _local: string,
      _recipient: string,
      _amount: BigNumberish,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    removeAssetId(
      canonicalId: BytesLike,
      adoptedAssetId: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    removeLiquidity(
      amount: BigNumberish,
      local: string,
      to: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    removeRelayerFees(
      amount: BigNumberish,
      to: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    removeRouter(
      router: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    setupAsset(
      canonical: BridgeMessage.TokenIdStruct,
      adoptedAssetId: string,
      stableSwapPool: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    setupRouter(
      router: string,
      owner: string,
      recipient: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    xcall(
      _args: IConnext.XCallArgsStruct,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;
  };

  populateTransaction: {
    addLiquidity(
      amount: BigNumberish,
      local: string,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    addLiquidityFor(
      amount: BigNumberish,
      local: string,
      router: string,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    addRelayerFees(
      router: string,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    addStableSwapPool(
      canonical: BridgeMessage.TokenIdStruct,
      stableSwapPool: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    execute(
      _args: IConnext.ExecuteArgsStruct,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    initialize(
      _domain: BigNumberish,
      _bridgeRouter: string,
      _tokenRegistry: string,
      _wrappedNative: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    reconcile(
      _transferId: BytesLike,
      _origin: BigNumberish,
      _local: string,
      _recipient: string,
      _amount: BigNumberish,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    removeAssetId(
      canonicalId: BytesLike,
      adoptedAssetId: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    removeLiquidity(
      amount: BigNumberish,
      local: string,
      to: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    removeRelayerFees(
      amount: BigNumberish,
      to: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    removeRouter(
      router: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    setupAsset(
      canonical: BridgeMessage.TokenIdStruct,
      adoptedAssetId: string,
      stableSwapPool: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    setupRouter(
      router: string,
      owner: string,
      recipient: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    xcall(
      _args: IConnext.XCallArgsStruct,
      overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;
  };
}
