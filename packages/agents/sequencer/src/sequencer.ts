import { logger as ethersLogger, Wallet } from "ethers";
import {
  Logger,
  getChainData,
  RequestContext,
  createLoggingContext,
  createMethodContext,
  ChainData,
  jsonifyError,
} from "@connext/nxtp-utils";
import Broker from "foo-foo-mq";
import { SubgraphReader } from "@connext/nxtp-adapters-subgraph";
import { StoreManager } from "@connext/nxtp-adapters-cache";
import { ChainReader, getContractInterfaces, contractDeployments } from "@connext/nxtp-txservice";
import { Web3Signer } from "@connext/nxtp-adapters-web3signer";

import { SequencerConfig } from "./lib/entities";
import { getConfig } from "./config";
import { AppContext } from "./lib/entities/context";
import { bindHealthServer, bindSubscriber } from "./bindings/subscriber";
import { bindServer } from "./bindings/publisher";
import { setupRelayer } from "./adapters";
import { getHelpers } from "./lib/helpers";
import { getOperations } from "./lib/operations";

const context: AppContext = {} as any;
export const getContext = () => context;
export const msgContentType = "application/json";

export const makePublisher = async (_configOverride?: SequencerConfig) => {
  const { requestContext, methodContext } = createLoggingContext(makePublisher.name);
  try {
    context.adapters = {} as any;

    /// MARK - Config.
    // Get ChainData and parse out configuration.
    context.chainData = await getChainData();
    context.config = _configOverride ?? (await getConfig(context.chainData, contractDeployments));
    context.logger = new Logger({
      level: context.config.logLevel,
      formatters: {
        level: (label) => {
          return { level: label.toUpperCase() };
        },
      },
    });

    if (!context.config.messageQueue.publisher) throw new Error(`No publisher found in config`);

    context.logger.info("Sequencer config generated.", requestContext, methodContext, {
      config: { ...context.config, mnemonic: context.config.mnemonic ? "*****" : "N/A" },
    });

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

    /// MARK - Adapters
    context.adapters.cache = await setupCache(context.config.redis, context.logger, requestContext);
    context.adapters.subgraph = await setupSubgraphReader(requestContext);
    context.adapters.chainreader = new ChainReader(
      context.logger.child({ module: "ChainReader", level: context.config.logLevel }),
      context.config.chains,
    );
    context.adapters.contracts = getContractInterfaces();
    context.adapters.relayer = await setupRelayer();
    context.adapters.mqClient = await setupPublisher(requestContext);

    /// MARK - Bindings
    // Create server, set up routes, and start listening.
    await bindServer();

    context.logger.info("Sequencer boot complete!", requestContext, methodContext, {
      port: {
        pub: context.config.server.pub.port,
        sub: context.config.server.sub.port,
      },
      chains: [...Object.keys(context.config.chains)],
    });
    ethersLogger.info(
      `

          _|_|_|     _|_|     _|      _|   _|      _|   _|_|_|_|   _|      _|   _|_|_|_|_|
        _|         _|    _|   _|_|    _|   _|_|    _|   _|           _|  _|         _|
        _|         _|    _|   _|  _|  _|   _|  _|  _|   _|_|_|         _|           _|
        _|         _|    _|   _|    _|_|   _|    _|_|   _|           _|  _|         _|
          _|_|_|     _|_|     _|      _|   _|      _|   _|_|_|_|   _|      _|       _|

        `,
    );
  } catch (error: any) {
    console.error("Error starting publisher :'(", error);
    process.exit(1);
  }
};

export const execute = async (_configOverride?: SequencerConfig) => {
  const {
    auctions: { executeAuction },
  } = getOperations();
  try {
    // Transfer ID is a CLI argument. Always provided by the parent
    const transferId = process.argv[2];
    const { requestContext, methodContext } = createLoggingContext(execute.name, undefined, transferId);

    context.adapters = {} as any;

    /// MARK - Config.
    // Get ChainData and parse out configuration.
    context.chainData = await getChainData();
    context.config = _configOverride ?? (await getConfig(context.chainData, contractDeployments));
    context.logger = new Logger({
      level: context.config.logLevel,
      formatters: {
        level: (label) => {
          return { level: label.toUpperCase() };
        },
      },
    });
    context.logger.info("Sequencer config generated.", requestContext, methodContext, { config: context.config });

    // TODO: Which of these are not needed ?
    context.adapters.cache = await setupCache(context.config.redis, context.logger, requestContext);
    context.adapters.subgraph = await setupSubgraphReader(requestContext);
    context.adapters.chainreader = new ChainReader(
      context.logger.child({ module: "ChainReader", level: context.config.logLevel }),
      context.config.chains,
    );
    context.adapters.contracts = getContractInterfaces();
    context.adapters.relayer = await setupRelayer();

    await executeAuction(transferId, requestContext);
    context.logger.info("Executed", requestContext, methodContext, { transferId: transferId });
  } catch (error: any) {
    const { requestContext, methodContext } = createLoggingContext(execute.name);
    context.logger.error("Error executing:", requestContext, methodContext, jsonifyError(error as Error));
    process.exit(1);
  }
  process.exit();
};

export const setupCache = async (
  redis: { host?: string; port?: number },
  logger: Logger,
  requestContext: RequestContext,
): Promise<StoreManager> => {
  const methodContext = createMethodContext(setupCache.name);

  logger.info("Cache instance setup in progress...", requestContext, methodContext, {});
  const cacheInstance = StoreManager.getInstance({
    redis: { host: redis.host, port: redis.port, instance: undefined },
    mock: !redis.host || !redis.port,
    logger: logger.child({ module: "StoreManager" }),
  });

  logger.info("Cache instance setup is done!", requestContext, methodContext, {
    host: redis.host,
    port: redis.port,
  });
  return cacheInstance;
};

export const setupSubgraphReader = async (requestContext: RequestContext): Promise<SubgraphReader> => {
  const { chainData, logger, config } = getContext();
  const {
    auctions: { getMinimumBidsCountForRound },
  } = getHelpers();
  const methodContext = createMethodContext(setupSubgraphReader.name);

  const allowedDomains = [...Object.keys(config.chains)];
  const allowedChainData: Map<string, ChainData> = new Map();
  for (const allowedDomain of allowedDomains) {
    if (chainData.has(allowedDomain)) {
      allowedChainData.set(allowedDomain, chainData.get(allowedDomain)!);
    }
  }

  logger.info("Subgraph reader setup in progress...", requestContext, methodContext, {
    allowedDomains,
  });

  const subgraphReader = await SubgraphReader.create(
    allowedChainData,
    context.config.environment,
    context.config.subgraphPrefix,
  );

  // Pull support for domains that don't have a subgraph.
  const supported: Record<string, boolean> = subgraphReader.supported;
  for (const domain of Object.keys(supported)) {
    // If the domain is set to false, it indicates the SubgraphReader did not find active subgraphs for that domain.
    if (!supported[domain]) {
      delete context.config.chains[domain];
    }
  }

  logger.info("Subgraph reader setup is done!", requestContext, methodContext, {});

  logger.info("Validating the auction round depth for each domain...");
  const maxRoutersPerTransfer = await subgraphReader.getMaxRoutersPerTransfer(Object.keys(supported));
  for (const domain of maxRoutersPerTransfer.keys()) {
    const configuredMaxRouters = getMinimumBidsCountForRound(config.auctionRoundDepth);
    if (maxRoutersPerTransfer.has(domain) && configuredMaxRouters > maxRoutersPerTransfer.get(domain)!) {
      logger.info("Validation error, Invalid auctionRoundDepth configured!", requestContext, methodContext, {
        domain,
        auctionRoundDepth: config.auctionRoundDepth,
        configured: configuredMaxRouters,
        onchain: maxRoutersPerTransfer.get(domain),
      });
      process.exit(1);
    }
  }
  return subgraphReader;
};

export const setupPublisher = async (requestContext: RequestContext): Promise<typeof Broker> => {
  const { logger, config } = context;
  const methodContext = createMethodContext(setupPublisher.name);

  logger.info("MQ publisher setup in progress...", requestContext, methodContext, {});
  const client = await setupMQ(config);
  logger.info("MQ publisher setup is done!", requestContext, methodContext, {});

  return client;
};

export const setupSubscriber = async (requestContext: RequestContext): Promise<typeof Broker> => {
  const { logger, config } = context;
  const methodContext = createMethodContext(setupSubscriber.name);

  logger.info("MQ subscriber setup in progress...", requestContext, methodContext, {});
  const client = await setupMQ(config);
  logger.info("MQ subscriber setup is done!", requestContext, methodContext, {});

  return client;
};

export const setupMQ = async (_config: SequencerConfig): Promise<typeof Broker> => {
  const mqConfig: Broker.ConfigurationOptions = {
    connection: _config.messageQueue.connection,
    exchanges: _config.messageQueue.exchanges,
    queues: _config.messageQueue.queues,
    bindings: _config.messageQueue.bindings,
  };
  await Broker.configure(mqConfig);
  return Broker;
};

export const makeSubscriber = async (_configOverride?: SequencerConfig) => {
  const { requestContext, methodContext } = createLoggingContext(makePublisher.name);
  try {
    context.adapters = {} as any;

    context.chainData = await getChainData();
    context.config = _configOverride ?? (await getConfig(context.chainData, contractDeployments));
    context.logger = new Logger({
      level: context.config.logLevel,
      formatters: {
        level: (label) => {
          return { level: label.toUpperCase() };
        },
      },
    });

    if (context.config.messageQueue.queues.length === 0) throw new Error(`No queues found in config`);

    context.logger.info("Subscriber config generated.", requestContext, methodContext);
    context.adapters.cache = await setupCache(context.config.redis, context.logger, requestContext);

    context.adapters.mqClient = await setupSubscriber(requestContext);

    if (context.config.messageQueue.subscriber) {
      bindSubscriber(context.config.messageQueue.subscriber);
    } else {
      // By default subscribe to all configured queues concurrently
      await Promise.all(
        context.config.messageQueue.queues.map(async (queueConfig) => {
          if (queueConfig?.name) bindSubscriber(queueConfig.name);
        }),
      );
    }

    // Create health server, set up routes, and start listening.
    await bindHealthServer();
  } catch (error: any) {
    console.error("Error starting subscriber :'(", error);
    Broker.close();
    process.exit(1);
  }
};
