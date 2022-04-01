import * as fs from "fs";

import { ajv, ChainData } from "@connext/nxtp-utils";
import { ConnextContractDeployments } from "@connext/nxtp-txservice";

import { SequencerConfig, SequencerConfigSchema } from "./lib/entities";

const MIN_SUBGRAPH_SYNC_BUFFER = 25;
const DEFAULT_AUCTION_WAIT_TIME = 30_000;

export const getEnvConfig = (
  chainData: Map<string, ChainData>,
  deployments: ConnextContractDeployments,
): SequencerConfig => {
  let configJson: Record<string, any> = {};
  let configFile: any = {};

  try {
    configJson = JSON.parse(process.env.SEQ_CONFIG || "");
  } catch (e) {
    console.info("No SEQ_CONFIG exists; using config file and individual env vars.");
  }
  try {
    let json: string;

    const path = process.env.SEQ_CONFIG_FILE ?? "config.json";
    if (fs.existsSync(path)) {
      json = fs.readFileSync(path, { encoding: "utf-8" });
      configFile = JSON.parse(json);
    }
  } catch (e) {
    console.error("Error reading config file!");
    process.exit(1);
  }

  const _sequencerConfig: SequencerConfig = {
    redisUrl: process.env.SEQ_REDIS_URL || configJson.redisUrl || configFile.redisUrl || process.env.NXTP_REDIS_URL,
    chains: process.env.SEQ_CHAIN_CONFIG
      ? JSON.parse(process.env.SEQ_CHAIN_CONFIG)
      : configJson.chains
      ? configJson.chains
      : configFile.chains,
    logLevel:
      process.env.SEQ_LOG_LEVEL || configJson.logLevel || configFile.logLevel || process.env.NXTP_LOG_LEVEL || "info",
    network:
      process.env.SEQ_NETWORK || configJson.network || configFile.network || process.env.NXTP_NETWORK || "mainnet",
    server: {
      port: process.env.SEQ_SERVER_PORT || configJson.server?.port || configFile.server?.port || 8081,
      host: process.env.SEQ_SERVER_HOST || configJson.server?.host || configFile.server?.host || "0.0.0.0",
    },
    auctionWaitTime:
      process.env.SEQ_AUCTION_WAIT_TIME ||
      configJson.auctionWaitTime ||
      configFile.auctionWaitTime ||
      DEFAULT_AUCTION_WAIT_TIME,
    mode: {
      cleanup: process.env.SEQ_CLEANUP_MODE || configJson.mode?.cleanup || configFile.mode?.cleanup || false,
    },
  };

  const defaultConfirmations = chainData && (chainData.get("1")?.confirmations ?? 1 + 3);

  // add contract deployments if they exist
  Object.entries(_sequencerConfig.chains).forEach(([domainId, chainConfig]) => {
    const chainDataForChain = chainData.get(domainId);
    const chainRecommendedConfirmations = chainDataForChain?.confirmations ?? defaultConfirmations;
    // allow passed in address to override
    // format: { [domainId]: { { "deployments": { "connext": <address>, ... } }
    if (!chainConfig.deployments?.connext) {
      const res = chainDataForChain ? deployments.connext(chainDataForChain.chainId) : undefined;
      if (!res) {
        throw new Error(`No Connext contract address for domain ${domainId}`);
      }

      _sequencerConfig.chains[domainId].deployments.connext = res.address;
    }

    if (!chainConfig.subgraph.runtime) {
      _sequencerConfig.chains[domainId].subgraph.runtime = chainDataForChain?.subgraph ?? [];
    }

    if (!chainConfig.subgraph.analytics) {
      _sequencerConfig.chains[domainId].subgraph.analytics = chainDataForChain?.analyticsSubgraph ?? [];
    }

    if (!chainConfig.confirmations) {
      _sequencerConfig.chains[domainId].confirmations = chainRecommendedConfirmations;
    }

    const maxLag = chainConfig.subgraph.maxLag ?? MIN_SUBGRAPH_SYNC_BUFFER;
    // 25 blocks minimum.
    _sequencerConfig.chains[domainId].subgraph.maxLag =
      maxLag < MIN_SUBGRAPH_SYNC_BUFFER ? MIN_SUBGRAPH_SYNC_BUFFER : maxLag;
  });

  const validate = ajv.compile(SequencerConfigSchema);
  const valid = validate(_sequencerConfig);
  if (!valid) {
    throw new Error(validate.errors?.map((err: any) => JSON.stringify(err, null, 2)).join(","));
  }

  return _sequencerConfig;
};

export let sequencerConfig: SequencerConfig | undefined;

/**
 * Gets and validates the router config from the environment.
 * @param useDefaultLocal - (optional) If true, use the default local config.
 * @returns The router config with sensible defaults
 */
export const getConfig = async (
  chainData: Map<string, ChainData>,
  deployments: ConnextContractDeployments,
): Promise<SequencerConfig> => {
  if (!sequencerConfig) {
    sequencerConfig = getEnvConfig(chainData, deployments);
  }
  return sequencerConfig;
};