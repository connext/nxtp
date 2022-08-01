import { providers, constants, BigNumber, utils } from "ethers";

import {
  chainDataToMap,
  XTransfer,
  XTransferStatus,
  getRandomBytes32,
  Bid,
  CallParams,
  ExecuteArgs,
  createLoggingContext,
} from "..";
import { Auction, XCallArgs } from "../types";
import { getNtpTimeSeconds } from "../helpers";

import { mkAddress, mkBytes32, mkSig } from ".";

/**
 * General mock toolset used for testing globally.
 */
export const mock = {
  domain: {
    A: "13337",
    B: "13338",
  },
  chain: {
    A: "23337",
    B: "23338",
  },
  asset: {
    A: {
      name: "TEST-A",
      symbol: "TSTA",
      address: mkAddress("0xbeefbeefbeef"),
    },
    B: {
      name: "TEST-B",
      symbol: "TSTB",
      address: mkAddress("0x2faced"),
    },
  },
  chainData: () =>
    chainDataToMap([
      {
        name: "Unit Test Chain 1",
        chainId: parseInt(mock.chain.A),
        domainId: mock.domain.A,
        confirmations: 1,
        assetId: {},
        subgraphs: {
          runtime: [{ query: "http://example.com", health: "http://example.com" }],
          analytics: [{ query: "http://example.com", health: "http://example.com" }],
          maxLag: 10,
        },
      },
      {
        name: "Unit Test Chain 2",
        chainId: parseInt(mock.chain.B),
        domainId: mock.domain.B,
        confirmations: 1,
        assetId: {},
        subgraphs: {
          runtime: [{ query: "http://example.com", health: "http://example.com" }],
          analytics: [{ query: "http://example.com", health: "http://example.com" }],
          maxLag: 10,
        },
      },
    ]),
  signature: mkSig("0xabcdef1c"),
  encodedData: () => getRandomBytes32(),
  address: {
    router: mkAddress("0xc0ffeebabe"),
    relayer: mkAddress("0xdad"),
  },
  loggingContext: (name = "TEST") => createLoggingContext(name, undefined, mkBytes32()),
  entity: {
    callParams: (overrides: Partial<CallParams> = {}): CallParams => ({
      to: mkAddress("0xaaa"),
      callData: "0x",
      originDomain: mock.domain.A,
      destinationDomain: mock.domain.B,
      callback: mkAddress("0xbbbb"),
      callbackFee: "0",
      relayerFee: "123",
      forceSlow: false,
      receiveLocal: false,
      agent: mkAddress(),
      recovery: mkAddress("0xcccc"),
      destinationMinOut: "0",
      ...overrides,
    }),
    xcallArgs: (overrides: Partial<XCallArgs> = {}): XCallArgs => ({
      params: mock.entity.callParams(),
      transactingAsset: mock.asset.A.address,
      transactingAmount: utils.parseEther("1").toString(),
      originMinOut: "0",
      ...overrides,
    }),
    executeArgs: (overrides: Partial<ExecuteArgs> = {}): ExecuteArgs => ({
      params: mock.entity.callParams(),
      local: mock.asset.A.address,
      routers: [mkAddress("0x222")],
      routerSignatures: [mock.signature],
      sequencer: mkAddress("0x333"),
      sequencerSignature: mock.signature,
      amount: utils.parseEther("1").toString(),
      nonce: 0,
      originSender: mkAddress(),
      ...overrides,
    }),
    auction: (overrides: Partial<Auction>): Auction => ({
      timestamp: getNtpTimeSeconds().toString(),
      origin: mock.domain.A,
      destination: mock.domain.B,
      bids: {
        [mock.address.router]: mock.entity.bid(),
      },
      ...overrides,
    }),
    bid: (overrides: Partial<Bid> = {}): Bid => ({
      routerVersion: "0.0.1",
      transferId: getRandomBytes32(),
      origin: mock.domain.A,
      router: mock.address.router,
      signatures: {
        "1": getRandomBytes32(),
        "2": getRandomBytes32(),
        "3": getRandomBytes32(),
      },
      ...overrides,
    }),
    xtransfer: (
      overrides: {
        originDomain?: string;
        destinationDomain?: string;
        originChain?: string;
        destinationChain?: string;
        amount?: string;
        status?: XTransferStatus;
        asset?: string;
        transferId?: string;
        nonce?: number;
        user?: string;
        relayerFee?: string;
        routers?: string[];
      } = {},
    ): XTransfer => {
      const originDomain: string = overrides.originDomain ?? mock.domain.A;
      const destinationDomain: string = overrides.destinationDomain ?? mock.domain.B;
      const originChain: string = overrides.originChain ?? mock.chain.A;
      const destinationChain: string = overrides.destinationChain ?? mock.chain.B;
      const amount = overrides.amount ?? "1000";
      const status: XTransferStatus | undefined = overrides.status;
      const asset: string = overrides.asset ?? mock.asset.A.address;
      const transferId: string = overrides.transferId ?? getRandomBytes32();
      const nonce = overrides.nonce ?? 1234;
      const user: string = overrides.user ?? mkAddress("0xfaded");
      const relayerFee = overrides.relayerFee ?? "12345";
      const routers = overrides.routers ?? [mock.address.router];

      const shouldHaveOriginDefined = !!relayerFee;
      const shouldHaveDestinationDefined = !!status;
      const isReconciledOnly = !shouldHaveOriginDefined && status === XTransferStatus.Reconciled;

      return {
        // Meta
        transferId,
        nonce: !isReconciledOnly ? nonce : undefined,

        // Call Params
        xparams: {
          to: user,
          callData: "0x",
          callback: mkAddress("0x"),
          callbackFee: "0",
          relayerFee,
          recovery: mkAddress("0x"),
          agent: mkAddress("0x"),
          forceSlow: false,
          receiveLocal: false,
          destinationMinOut: "0",
          destinationDomain,
          originDomain,
        },

        origin: shouldHaveOriginDefined
          ? {
              chain: originChain,

              originMinOut: "0",

              // Assets
              assets: {
                transacting: {
                  asset,
                  amount,
                },
                bridged: {
                  asset,
                  amount,
                },
              },

              // XCalled
              xcall: {
                // Event Data
                caller: user,
                transactionHash: getRandomBytes32(),
                timestamp: Math.floor(Date.now() / 1000 - 60),
                gasPrice: utils.parseUnits("5", "gwei").toString(),
                gasLimit: "80000",
                blockNumber: 7654321,
              },
            }
          : undefined,

        destination: shouldHaveDestinationDefined
          ? {
              chain: destinationChain,

              // Event Data
              status,
              routers,

              // Assets
              assets: {
                // Transfer must have been Executed in order to have this defined.
                transacting:
                  status !== XTransferStatus.Reconciled
                    ? {
                        asset,
                        amount,
                      }
                    : undefined,
                local: {
                  asset,
                  amount,
                },
              },

              // If status is executed, we should have executed fields defined (but leave reconciled fields empty).
              execute:
                status === XTransferStatus.Executed || status === XTransferStatus.CompletedSlow
                  ? {
                      originSender: user,
                      caller: mock.address.relayer,
                      transactionHash: getRandomBytes32(),
                      timestamp: Math.floor(Date.now() / 1000 - 30),
                      gasPrice: utils.parseUnits("5", "gwei").toString(),
                      gasLimit: "80000",
                      blockNumber: 5651345,
                    }
                  : undefined,

              reconcile:
                status === XTransferStatus.Reconciled || status === XTransferStatus.CompletedFast
                  ? {
                      caller: mock.address.relayer,
                      transactionHash: getRandomBytes32(),
                      timestamp: Math.floor(Date.now() / 1000),
                      gasPrice: utils.parseUnits("5", "gwei").toString(),
                      gasLimit: "100000",
                      blockNumber: 5651390,
                    }
                  : undefined,
            }
          : undefined,
      };
    },
    dbTransfer: (overrides: any): any => ({
      origin_domain: mock.domain.A,
      destination_domain: mock.domain.B,
      nonce: 0,
      to: mkAddress("0x11111"),
      call_data: mkBytes32("0xaaa"),
      callback: mkAddress("0x111"),
      callback_fee: "0",
      recovery: mkAddress("0x112"),
      force_slow: false,
      receiveLocal: false,
      transfer_id: mkBytes32("0xbbb"),
      origin_chain: mock.chain.A,
      origin_transacting_amount: 100,
      origin_transacting_asset: mkAddress("0x11"),
      origin_bridged_amount: 100,
      origin_bridged_asset: mkAddress("0x12"),
      xcall_block_number: 100,
      xcall_caller: mkAddress("0x1"),
      xcall_gas_limit: 10000,
      xcall_gas_price: 5,
      xcall_timestamp: 1e8,
      xcall_transaction_hash: mkBytes32("0xccc"),
      relayer_fee: 0,
      destination_chain: mock.chain.B,
      destination_transacting_amount: 100,
      destination_transacting_asset: mkAddress("0x22"),
      destination_local_amount: 100,
      destination_local_asset: mkAddress("0x13"),
      routers: [],
      status: XTransferStatus.XCalled,
      execute_block_number: 100,
      execute_caller: mkAddress("0x2"),
      execute_gas_limit: 10000,
      execute_gas_price: 5,
      execute_timestamp: 1e8,
      execute_transaction_hash: mkBytes32("0xddd"),
      execute_relayer_fee: 0,
      execute_origin_sender: mkAddress("0x3"),
      reconcile_block_number: 100,
      reconcile_caller: mkAddress("0x4"),
      reconcile_gas_limit: 10000,
      reconcile_gas_price: 5,
      reconcile_timestamp: 1e8,
      reconcile_transaction_hash: mkBytes32("0xeee"),
      reconcile_relayer_fee: 0,
      reconcile_origin_sender: mkAddress("0x5"),
      ...overrides,
    }),
  },
  ethers: {
    receipt: (overrides: Partial<providers.TransactionReceipt> = {}): providers.TransactionReceipt =>
      ({
        blockHash: "foo",
        blockNumber: 1,
        byzantium: true,
        confirmations: 5,
        contractAddress: mkAddress(),
        cumulativeGasUsed: constants.One,
        from: mkAddress(),
        transactionHash: mkBytes32(),
        effectiveGasPrice: BigNumber.from(10),
        gasUsed: constants.One,
        to: mkAddress(),
        logs: [],
        logsBloom: "",
        transactionIndex: 1,
        ...overrides,
      } as unknown as providers.TransactionReceipt),
  },
  contracts: {
    deployments: {
      connext: function (_: number) {
        return {
          address: mkAddress("0x123123"),
          abi: "fakeAbi()",
        };
      },
      priceOracle: function (_: number) {
        return {
          address: mkAddress("0x321321"),
          abi: "fakeAbi()",
        };
      },
    },
  },
};
