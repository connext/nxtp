import { Wallet } from "ethers";
import {
  createMethodContext,
  createRequestContext,
  getChainData,
  jsonifyError,
  Logger,
  RequestContext,
} from "@connext/nxtp-utils";
import { Web3Signer } from "@connext/nxtp-adapters-web3signer";
import { getContractInterfaces, TransactionService, contractDeployments } from "@connext/nxtp-txservice";
import axios from "axios";
import { BridgeContext } from "@nomad-xyz/sdk-bridge";
import fetch, { Headers, Request, Response } from "node-fetch";

if (!(globalThis as any).fetch) {
  (globalThis as any).fetch = fetch;
  (globalThis as any).Headers = Headers;
  (globalThis as any).Request = Request;
  (globalThis as any).Response = Response;
}

import { getConfig, NxtpRouterConfig } from "../config";
import { bindMetrics } from "../bindings";
import { setupMq, setupSubgraphReader } from "../setup";

import { AppContext } from "./context";
import { bindMessageQueue, bindServer } from "./bindings";

// AppContext instance used for interacting with adapters, config, etc.
const context: AppContext = {} as any;
export const getContext = () => context;

export const makeSubscriber = async (_configOverride?: NxtpRouterConfig) => {
  const requestContext = createRequestContext("Router subscriber Init");
  const methodContext = createMethodContext(makeSubscriber.name);

  try {
    context.adapters = {} as any;

    /// MARK - Config.
    // Get ChainData and parse out configuration.
    context.chainData = await getChainData();
    context.config = _configOverride ?? (await getConfig(context.chainData, contractDeployments));

    /// MARK - Signer
    if (!context.config.mnemonic && !context.config.web3SignerUrl) {
      throw new Error(
        "No mnemonic or web3signer was configured. Please ensure either a mnemonic or a web3signer" +
          " URL is provided in the config. Exiting!",
      );
    }
    context.adapters.wallet = context.config.mnemonic
      ? Wallet.fromMnemonic(context.config.mnemonic)
      : new Web3Signer(context.config.web3SignerUrl!);

    context.routerAddress = await context.adapters.wallet.getAddress();

    /// MARK - Logger
    context.logger = new Logger({
      level: context.config.logLevel,
      name: context.routerAddress,
      formatters: {
        level: (label) => {
          return { level: label.toUpperCase() };
        },
      },
    });
    context.logger.info("Generated config.", requestContext, methodContext, {
      config: { ...context.config, mnemonic: context.config.mnemonic ? "*****" : "N/A" },
    });

    /// MARK - BridgeContext
    context.bridgeContext =
      context.config.nomadEnvironment !== "none" ? await setupBridgeContext(requestContext) : undefined;

    /// MARK - Adapters
    context.adapters.subgraph = await setupSubgraphReader(
      context.logger,
      context.chainData,
      Object.keys(context.config.chains),
      context.config.environment,
      context.config.subgraphPrefix,
      requestContext,
    );
    context.adapters.txservice = new TransactionService(
      context.logger.child({ module: "TransactionService", level: context.config.logLevel }),
      context.config.chains,
      context.adapters.wallet as Wallet,
    );
    context.adapters.contracts = getContractInterfaces();
    context.adapters.mqClient = await setupMq(
      context.config.messageQueue.uri as string,
      context.logger,
      requestContext,
    );

    /// MARK - Validation for auctionRoundDepth

    /// MARK - Cold Start Housekeeping
    try {
      const res = await axios.get(`${context.config.sequencerUrl}/ping`);
      context.logger.info("Ping response received from sequencer", requestContext, methodContext, {
        response: res.data,
      });
    } catch (e: unknown) {
      context.logger.error(
        "Ping error, could not reach sequencer. Exiting!",
        requestContext,
        methodContext,
        jsonifyError(e as Error),
      );
      process.exit(1);
    }
    // TODO: Cold start housekeeping cont'd.
    // - read subgraph to make sure router is approved
    // - read contract or subgraph for current liquidity in each asset, cache it
    // - read subgraph to make sure each asset is (still) approved
    // - bring cache up to speed
    // - make sure a relayer is configured for supported chains.

    /// MARK - Bindings
    // TODO: New diagnostic mode / cleanup mode?
    await bindServer();
    await bindMetrics("subscriber");
    await bindMessageQueue();

    context.logger.info("Bindings initialized.", requestContext, methodContext);
    context.logger.info("Router subscriber boot complete!", requestContext, methodContext, {
      port: context.config.server.sub.port,
      chains: [...Object.keys(context.config.chains)],
    });
    context.logger.info(
      `

        _|_|_|     _|_|     _|      _|   _|      _|   _|_|_|_|   _|      _|   _|_|_|_|_|
      _|         _|    _|   _|_|    _|   _|_|    _|   _|           _|  _|         _|
      _|         _|    _|   _|  _|  _|   _|  _|  _|   _|_|_|         _|           _|
      _|         _|    _|   _|    _|_|   _|    _|_|   _|           _|  _|         _|
        _|_|_|     _|_|     _|      _|   _|      _|   _|_|_|_|   _|      _|       _|

      `,
    );
  } catch (e: unknown) {
    console.error("Error starting router subscriber. Sad! :(", e);
    process.exit();
  }
};

export const setupBridgeContext = async (requestContext: RequestContext): Promise<BridgeContext> => {
  const { config, logger } = context;
  const methodContext = createMethodContext(setupBridgeContext.name);
  logger.info("BridgeContext setup in progress...", requestContext, methodContext, {});

  const bridgeContext = await BridgeContext.fetch(config.nomadEnvironment);

  const allowedDomains = [...Object.keys(config.chains)];
  for (const allowedDomain of allowedDomains) {
    const chainData = config.chains[allowedDomain];
    chainData.providers.map((provider) => {
      bridgeContext.registerRpcProvider(Number(allowedDomain), provider);
    });
  }
  logger.info("BridgeContext setup done!", requestContext, methodContext, {});
  return bridgeContext;
};
