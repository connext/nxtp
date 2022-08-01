import { utils, Wallet } from "ethers";
import { getChainData, mkBytes32, ChainData, ChainConfig } from "@connext/nxtp-utils";
import { getDeployedConnextContract, _getContractDeployments } from "@connext/nxtp-txservice";
import { SequencerConfig } from "@connext/nxtp-sequencer/src/lib/entities/config";
import { NxtpRouterConfig as RouterConfig } from "@connext/nxtp-router/src/config";
import { version as routerPackageVersion } from "@connext/nxtp-router/package.json";
import { RelayerConfig } from "@connext/nxtp-relayer/src/lib/entities/config";
import { CartographerConfig } from "@connext/cartographer-poller/src/config";

export enum Environment {
  Staging = "staging",
  Production = "production",
}

// TODO: Should have an overrides in env:
export const LOCALHOST = "localhost"; // alt. 0.0.0.0
const ASSET_CONTRACT_NAME = "TestERC20";

/// MARK - Integration Settings
const DEFAULT_ROUTE = ["1111", "3331"]; // Rinkeby => Goerli

// Environment setting.
export const ENVIRONMENT: "staging" | "production" = (process.env.ENV ||
  process.env.ENVIRONMENT ||
  Environment.Staging) as "staging" | "production";

export const NOMAD_ENVIRONMENT: "staging" | "production" = (process.env.NXTP_NOMAD_ENVIRONMENT ||
  Environment.Staging) as "staging" | "production";
// Whether or not to run certain agents locally.
export const LOCAL_RELAYER_ENABLED = process.env.LOCAL_RELAYER_ENABLED === "true";
export const LOCAL_CARTOGRAPHER_ENABLED = process.env.LOCAL_CARTOGRAPHER_ENABLED === "true";

// TODO: May need to increase this at some point:
export const RELAYER_FEE_AMOUNT = utils.parseEther("0.0000000001"); // In ETH.
export const TRANSFER_TOKEN_AMOUNT = utils.parseEther("2.5"); // In TEST.
export const ROUTER_DESIRED_LIQUIDITY = utils.parseEther("1000"); // In TEST.

// Min amounts needed for testing.
export const MIN_USER_ETH = utils.parseEther("0.02").add(RELAYER_FEE_AMOUNT);
export const MIN_FUNDER_ETH = utils.parseEther("0").add(MIN_USER_ETH);

// Logging.
export const LOGFILE_PATH = "ops/data";

// Time period after which we consider the XCall appearance on the subgraph to have timed out.
// NOTE: This should basically reflect any lag that can occur in subgraph syncing... if it's not appearing
// after this period of time, something is wrong with the subgraph!
export const XCALL_TIMEOUT = 120_000;
// Time period in ms, after which we consider the fast liquidity layer's `execute` to have timed out.
// NOTE: This should reflect agent response time.
export const EXECUTE_TIMEOUT = 3_000_000;

export const SKIP_SEQUENCER_CHECKS = true;

// Used in polling loops.
export const SUBG_POLL_PARITY = 5_000;

export const DEBUG_XCALL_TXHASH = process.env.XCALL_TXHASH || process.env.XCALL_HASH;

/// MARK - Utility Constants
export const EMPTY_BYTES = mkBytes32("0x0");

// Message Queue settings
export const EXCHANGE_NAME = "sequencerX";
export const QUEUE_NAME = "1111";

/// MARK - General
export type DomainInfo = {
  name: string;
  network: string;
  domain: string;
  chain: number;
  config: ChainConfig;
};

export type Agent = {
  address: string;
  origin: Wallet;
  destination: Wallet;
};

export type TestAgents = {
  user: Agent;
  router?: Agent;
  relayer?: Agent;
  deployer?: Agent;
};

/// MARK - General domain info setup.
export const CHAIN_DATA: Promise<Map<string, ChainData>> = (async (): Promise<Map<string, ChainData>> => {
  return await getChainData();
})();

export const DOMAINS: Promise<{ ORIGIN: DomainInfo; DESTINATION: DomainInfo }> = (async (): Promise<{
  ORIGIN: DomainInfo;
  DESTINATION: DomainInfo;
}> => {
  /// MARK - Pick origin and destination domains.
  let origin = process.env.ORIGIN_DOMAIN || process.env.ORIGIN;
  let destination = process.env.DESTINATION_DOMAIN || process.env.DESTINATION;

  if (!origin || !destination) {
    console.log(
      "Origin and/or destination chains were not specified in env (ORIGIN, DESTINATION). Using default route.",
    );
    origin = DEFAULT_ROUTE[0];
    destination = DEFAULT_ROUTE[1];
  }

  /// MARK - Set up chain data for origin and destination.
  const chainData = await CHAIN_DATA;
  const originChainData = chainData.get(origin);
  const destinationChainData = chainData.get(destination);

  if (!originChainData || !destinationChainData) {
    throw new Error("Could not get chain data for origin or destination");
  }

  /// MARK - Get TEST ERC20 token addresses.
  const deployments = _getContractDeployments();
  const originChainAsset: string | undefined =
    (deployments[originChainData.chainId.toString()] ?? {})[0]?.contracts[ASSET_CONTRACT_NAME]?.address ?? undefined;
  const destinationChainAsset: string | undefined =
    (deployments[destinationChainData.chainId.toString()] ?? {})[0]?.contracts[ASSET_CONTRACT_NAME]?.address ??
    undefined;

  if (!originChainAsset || !destinationChainAsset) {
    throw new Error(
      "Could not locate addresses for origin and destination chain assets under contract name: " + ASSET_CONTRACT_NAME,
    );
  }

  /// MARK - Configure providers.
  const infuraKey =
    process.env.INFURA_KEY || process.env.INFURA_API_KEY || process.env.INFURA_PROJECT || process.env.INFURA_PROJECT_ID;
  const originProvider =
    process.env.ORIGIN_PROVIDER ?? infuraKey
      ? `https://${originChainData.network}.infura.io/v3/${infuraKey}`
      : undefined;
  const destinationProvider =
    process.env.DESTINATION_PROVIDER ?? infuraKey
      ? `https://${destinationChainData.network}.infura.io/v3/${infuraKey}`
      : undefined;

  if (!originProvider || !destinationProvider) {
    throw new Error(
      "RPC provider URLs for origin or destination were not set." +
        " Please set the env vars ORIGIN_PROVIDER and DESTINATION_PROVIDER." +
        " Alternatively, if you are using Infura, set the env var INFURA_KEY.",
    );
  }

  /// MARK - Assert ConnextHandler contract is deployed helper.
  const getConnextContract = (chainId: number): string => {
    const contract = getDeployedConnextContract(chainId, ENVIRONMENT === Environment.Staging ? "Staging" : "");
    if (!contract) {
      throw new Error(`No Connext contract deployed on chain ${chainId}`);
    }
    return contract.address.toLowerCase();
  };
  return {
    ORIGIN: {
      name: originChainData.name,
      network: originChainData.network,
      domain: originChainData.domainId,
      chain: originChainData.chainId,
      config: {
        providers: [originProvider],
        assets: [
          {
            name: "TEST",
            address: originChainAsset,
          },
        ],
        gasStations: [],
        confirmations: originChainData.confirmations ?? 1,
        deployments: {
          connext: getConnextContract(originChainData.chainId),
        },
      },
    },
    DESTINATION: {
      name: destinationChainData.name,
      network: destinationChainData.network,
      domain: destinationChainData.domainId,
      chain: destinationChainData.chainId,
      config: {
        providers: [destinationProvider],
        assets: [
          {
            name: "TEST",
            address: destinationChainAsset,
          },
        ],
        gasStations: [],
        confirmations: destinationChainData.confirmations ?? 1,
        deployments: {
          connext: getConnextContract(destinationChainData.chainId),
        },
      },
    },
  };
})();

/// MARK - Router
export const ROUTER_CONFIG: Promise<RouterConfig> = (async (): Promise<RouterConfig> => {
  const { ORIGIN, DESTINATION } = await DOMAINS;
  const environment = ENVIRONMENT.toString();
  if (environment !== "staging" && environment !== "production") {
    throw new Error(`Router environment only available for staging and production, not ${environment}`);
  }
  return {
    logLevel: "info",
    sequencerUrl: `http://${LOCALHOST}:8081`,
    redis: {},
    server: {
      adminToken: "a",
      pub: {
        port: 8081,
        host: LOCALHOST,
      },
      sub: {
        port: 8080,
        host: LOCALHOST,
      },
      requestLimit: 10,
    },
    chains: {
      [ORIGIN.domain]: ORIGIN.config,
      [DESTINATION.domain]: DESTINATION.config,
    },
    network: "testnet",
    maxSlippage: 1,
    mode: {
      cleanup: false,
      diagnostic: false,
      priceCaching: false,
    },
    polling: {
      subgraph: 5_000,
      cache: 5_000,
    },
    auctionRoundDepth: 3,
    environment,
    nomadEnvironment: NOMAD_ENVIRONMENT,
    messageQueue: {
      host: LOCALHOST,
    },
  };
})();

/// MARK - Sequencer
export const SEQUENCER_CONFIG: Promise<SequencerConfig> = (async (): Promise<SequencerConfig> => {
  const { ORIGIN, DESTINATION } = await DOMAINS;
  return {
    redis: {},
    server: {
      adminToken: "b",
      pub: {
        port: 8081,
        host: LOCALHOST,
      },
      sub: {
        port: 8080,
        host: LOCALHOST,
      },
    },
    chains: {
      [ORIGIN.domain]: {
        providers: ORIGIN.config.providers,
        confirmations: ORIGIN.config.confirmations,
        deployments: ORIGIN.config.deployments,
      },
      [DESTINATION.domain]: {
        providers: DESTINATION.config.providers,
        confirmations: DESTINATION.config.confirmations,
        deployments: DESTINATION.config.deployments,
      },
    },
    logLevel: "info",
    mode: {
      cleanup: false,
    },
    auctionWaitTime: 5_000,
    auctionRoundDepth: 3,
    network: "testnet",
    supportedBidVersion: routerPackageVersion,
    environment: ENVIRONMENT.toString() as "staging" | "production",
    relayerUrl: LOCAL_RELAYER_ENABLED ? `http://${LOCALHOST}:8082` : undefined,
    messageQueue: {
      connection: {
        uri: "amqp://guest:guest@localhost:5672",
      },
      exchanges: [{ name: EXCHANGE_NAME, type: "direct", publishTimeout: 1000, persistent: true, durable: true }],
      queues: [{ name: QUEUE_NAME, limit: 5, queueLimit: 10000, subscribe: true }],
      bindings: [{ exchange: EXCHANGE_NAME, target: QUEUE_NAME, keys: [QUEUE_NAME] }],
      executerTimeout: 300000,
      publisher: EXCHANGE_NAME,
      subscriber: QUEUE_NAME,
    },
  };
})();

/// MARK - RELAYER CONFIG
export const RELAYER_CONFIG: Promise<RelayerConfig> = (async (): Promise<RelayerConfig> => {
  const { DESTINATION } = await DOMAINS;
  return {
    redis: {},
    server: {
      adminToken: "c",
      port: 8082,
      host: LOCALHOST,
    },
    chains: {
      // [ORIGIN.domain]: {
      //   providers: ORIGIN.config.providers,
      //   confirmations: ORIGIN.config.confirmations,
      //   deployments: ORIGIN.config.deployments,
      // },
      [DESTINATION.domain]: {
        providers: DESTINATION.config.providers,
        confirmations: DESTINATION.config.confirmations,
        deployments: DESTINATION.config.deployments,
      },
    },
    logLevel: "debug",
    mode: {
      cleanup: false,
    },
    network: "testnet",
    environment: ENVIRONMENT.toString() as "staging" | "production",
  };
})();

/// MARK - CARTOGRAPHER CONFIG
export const CARTOGRAPHER_CONFIG: Promise<CartographerConfig> = (async (): Promise<CartographerConfig> => {
  const { ORIGIN, DESTINATION } = await DOMAINS;
  return {
    database: {
      url: "postgres://postgres:qwerty@localhost:5432/connext?sslmode=disable",
    },
    logLevel: "debug",
    pollInterval: 4_000,
    environment: "staging",
    chains: {
      [ORIGIN.domain]: {},
      [DESTINATION.domain]: {},
    },
  };
})();
