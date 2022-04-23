import { utils, Wallet } from "ethers";
import { SequencerConfig } from "@connext/nxtp-sequencer/src/lib/entities/config";
import { NxtpRouterConfig as RouterConfig, ChainConfig as RouterChainConfig } from "@connext/nxtp-router/src/config";
import { getChainData, mkBytes32 } from "@connext/nxtp-utils";

// TODO: Should have an overrides in env:
export const LOCALHOST = "localhost"; // alt. 0.0.0.0
export const ORIGIN_ASSET = {
  name: "TEST",
  address: "0xB5AabB55385bfBe31D627E2A717a7B189ddA4F8F",
};
export const DESTINATION_ASSET = {
  name: "TEST",
  address: "0xcF4d2994088a8CDE52FB584fE29608b63Ec063B2",
};

/// MARK - Integration Settings

// TODO: Why is the deployments lookup not working here? Having to hardcode this for now.
const ORIGIN_CONNEXT_ADDRESS = "0x983d9d70c1003baAE321fAA9C36BEb0eA37BD6E3";
const DESTINATION_CONNEXT_ADDRESS = "0x3e99898Da8A01Ed909976AF13e4Fa6094326cB10";
const ORIGIN_DOMAIN = "2221"; // Kovan
const DESTINATION_DOMAIN = "1111"; // Rinkeby
export const CANONICAL_DOMAIN = "ORIGIN";
export const MIN_USER_ETH = utils.parseEther("0.02");
export const MIN_FUNDER_ETH = utils.parseEther("0").add(MIN_USER_ETH);
export const TRANSFER_TOKEN_AMOUNT = utils.parseEther("25");

/// MARK - Utility Constants
export const EMPTY_BYTES = mkBytes32("0x0");

/// MARK - General
export type DomainInfo = {
  name: string;
  domain: string;
  chain: number;
  config: RouterChainConfig;
};

export type Agent = {
  address: string;
  origin: Wallet;
  destination: Wallet;
};

// Asynchronous domain info setup.
export const DOMAINS: Promise<{ ORIGIN: DomainInfo; DESTINATION: DomainInfo }> = (async (): Promise<{
  ORIGIN: DomainInfo;
  DESTINATION: DomainInfo;
}> => {
  const chainData = await getChainData();
  if (!chainData) {
    throw new Error("Could not get chain data");
  }

  const originChainData = chainData.get(ORIGIN_DOMAIN);
  const destinationChainData = chainData.get(DESTINATION_DOMAIN);

  if (!originChainData || !destinationChainData) {
    throw new Error("Could not get chain data for origin or destination");
  }

  const infuraKey = process.env.INFURA_KEY;
  const originProvider =
    process.env.ORIGIN_PROVIDER ?? infuraKey ? `https://kovan.infura.io/v3/${infuraKey}` : undefined;
  const destinationProvider =
    process.env.DESTINATION_PROVIDER ?? infuraKey ? `https://rinkeby.infura.io/v3/${infuraKey}` : undefined;

  if (!originProvider || !destinationProvider) {
    throw new Error(
      "RPC provider URLs for origin or destination were not set." +
        " Please set the env vars ORIGIN_PROVIDER and DESTINATION_PROVIDER." +
        " Alternatively, if you are using Infura, set the env var INFURA_KEY.",
    );
  }

  // See above TODO regarding hardcoded contract addresses.
  // const getConnextContract = (chainId: number): string => {
  //   const contract = contractDeployments.connext(chainId);
  //   if (!contract) {
  //     throw new Error(`No Connext contract deployed on chain ${chainId}`);
  //   }
  //   return contract.address;
  // };
  return {
    ORIGIN: {
      name: originChainData.name,
      domain: originChainData.domainId,
      chain: originChainData.chainId,
      config: {
        providers: [originProvider],
        assets: [ORIGIN_ASSET],
        subgraph: {
          analytics: originChainData.analyticsSubgraph
            ? [
                {
                  query: originChainData.analyticsSubgraph[0],
                  health: "",
                },
              ]
            : [],
          runtime: [
            {
              query: originChainData.subgraph[0],
              health: "",
            },
          ],
          maxLag: 25,
        },
        gasStations: [],
        confirmations: originChainData.confirmations ?? 1,
        deployments: {
          // connext: getConnextContract(originChainData.chainId),
          connext: ORIGIN_CONNEXT_ADDRESS,
        },
      },
    },
    DESTINATION: {
      name: destinationChainData.name,
      domain: destinationChainData.domainId,
      chain: destinationChainData.chainId,
      config: {
        providers: [destinationProvider],
        assets: [DESTINATION_ASSET],
        subgraph: {
          analytics: [
            {
              query: "",
              health: "",
            },
          ],
          runtime: [
            {
              query: "",
              health: "",
            },
          ],
          maxLag: 25,
        },
        gasStations: [],
        confirmations: destinationChainData.confirmations ?? 1,
        deployments: {
          // connext: getConnextContract(destinationChainData.chainId),
          connext: DESTINATION_CONNEXT_ADDRESS,
        },
      },
    },
  };
})();

/// MARK - Router
export const ROUTER_CONFIG: Promise<RouterConfig> = (async (): Promise<RouterConfig> => {
  const { DESTINATION } = await DOMAINS;
  return {
    logLevel: "debug",
    sequencerUrl: `http://${LOCALHOST}:8081`,
    redis: {},
    server: {
      adminToken: "a",
      port: 8080,
      host: LOCALHOST,
      requestLimit: 10,
    },
    chains: {
      // [ORIGIN.domain]: ORIGIN.config,
      [DESTINATION.domain]: DESTINATION.config,
    },
    network: "testnet",
    maxSlippage: 1,
    mode: {
      cleanup: false,
      diagnostic: false,
      priceCaching: false,
    },
    subgraphPollInterval: 5_000,
  };
})();

/// MARK - Sequencer
export const SEQUENCER_CONFIG: Promise<SequencerConfig> = (async (): Promise<SequencerConfig> => {
  const { ORIGIN, DESTINATION } = await DOMAINS;
  return {
    redis: {},
    server: {
      adminToken: "b",
      port: 8081,
      host: LOCALHOST,
    },
    chains: {
      [ORIGIN.domain]: {
        providers: ["https://rpc.ankr.com/eth_rinkeby"],
        subgraph: ORIGIN.config.subgraph,
        confirmations: ORIGIN.config.confirmations,
        deployments: ORIGIN.config.deployments,
      },
      [DESTINATION.domain]: {
        providers: ["https://kovan.infura.io/v3/19b854cad0bc4089bffd0c93f23ece9f"],
        subgraph: DESTINATION.config.subgraph,
        confirmations: DESTINATION.config.confirmations,
        deployments: DESTINATION.config.deployments,
      },
    },
    logLevel: "debug",
    mode: {
      cleanup: false,
    },
    auctionWaitTime: 10,
    network: "testnet",
  };
})();