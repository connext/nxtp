import {
  Logger,
  getChainData,
  RequestContext,
  createLoggingContext,
  createMethodContext,
  ChainData,
} from "@connext/nxtp-utils";
import { SubgraphReader } from "@connext/nxtp-adapters-subgraph";
import { StoreManager } from "@connext/nxtp-adapters-cache";
import { ChainReader, getContractInterfaces, contractDeployments } from "@connext/nxtp-txservice";

import { SequencerConfig } from "./lib/entities";
import { getConfig } from "./config";
import { AppContext } from "./lib/entities/context";
import { bindServer, bindAuctions } from "./bindings";
import { setupRelayer } from "./adapters";

const context: AppContext = {} as any;
export const getContext = () => context;

export const makeSequencer = async (_configOverride?: SequencerConfig) => {
  const { requestContext, methodContext } = createLoggingContext(makeSequencer.name);
  try {
    context.adapters = {} as any;

    // Get ChainData and parse out configuration.
    const chainData = await getChainData();
    if (!chainData) {
      throw new Error("Could not get chain data");
    }
    context.chainData = chainData;
    context.config = _configOverride ?? (await getConfig(chainData, contractDeployments));
    context.logger = new Logger({ level: context.config.logLevel });
    context.logger.info("Sequencer config generated.", requestContext, methodContext, { config: context.config });

    // Set up adapters.
    context.adapters.cache = await setupCache(context.config.redis, context.logger, requestContext);

    context.adapters.subgraph = await setupSubgraphReader(context.chainData, context.logger, requestContext);

    context.adapters.chainreader = new ChainReader(
      context.logger.child({ module: "ChainReader", level: context.config.logLevel }),
      context.config.chains,
    );

    context.adapters.contracts = getContractInterfaces();

    context.adapters.relayer = await setupRelayer();

    // Create server, set up routes, and start listening.
    await bindServer();

    await bindAuctions();

    context.logger.info("Sequencer is Ready!", requestContext, methodContext, {
      port: context.config.server.port,
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
  } catch (error: any) {
    console.error("Error starting sequencer :'(", error);
    process.exit();
  }
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

export const setupSubgraphReader = async (
  chainData: Map<string, ChainData>,
  logger: Logger,
  requestContext: RequestContext,
): Promise<SubgraphReader> => {
  const methodContext = createMethodContext(setupSubgraphReader.name);

  logger.info("Subgraph reader setup in progress...", requestContext, methodContext, {});

  const subgraphReader = await SubgraphReader.create(chainData);

  logger.info("Subgraph reader setup is done!", requestContext, methodContext, {});
  return subgraphReader;
};
