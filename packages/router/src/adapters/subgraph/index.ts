import { FallbackSubgraph, RequestContext, SubgraphDomain, SubgraphSyncRecord } from "@connext/nxtp-utils";
import { BigNumber } from "ethers";
import { GraphQLClient } from "graphql-request";

import { ActiveTransaction, ExpressiveAssetBalance, SingleChainTransaction } from "../../lib/entities";
import { ContractReaderNotAvailableForChain } from "../../lib/errors/contractReader";
import { getContext } from "../../router";

import { getSdk, Sdk } from "./runtime/graphqlsdk";
import { getSdk as getAnalyticsSdk, Sdk as AnalyticsSdk } from "./analytics/graphqlsdk";
import {
  getActiveTransactions,
  getAssetBalance,
  getTransactionForChain,
  getSyncRecords,
  getAssetBalances,
  getExpressiveAssetBalances,
} from "./subgraph";

export type ContractReader = {
  getActiveTransactions: () => Promise<ActiveTransaction<any>[]>;
  getTransactionForChain: (
    transactionId: string,
    user: string,
    chainId: number,
  ) => Promise<SingleChainTransaction | undefined>;

  /**
   *
   * Returns available liquidity for the given asset on the TransactionManager on the provided chain.
   *
   * @param assetId - The asset you want to determine router liquidity of
   * @param chainId - The chain you want to determine liquidity on
   * @returns The available balance
   */
  getAssetBalance: (assetId: string, chainId: number) => Promise<BigNumber>;

  /**
   * Returns available liquidity for any of the assets
   *
   * @param chainId - The chain you want to determine liquidity on
   * @returns An array of asset ids and amounts of liquidity
   */
  getAssetBalances: (chainId: number) => Promise<{ assetId: string; amount: BigNumber }[]>;

  /**
   * Returns the detailed analytics view of router liquidity
   *
   * @param chainId - The chain you want to determine liquidity on
   * @returns An array of asset ids and amounts of liquidity
   */
  getExpressiveAssetBalances: (chainId: number) => Promise<ExpressiveAssetBalance[]>;

  getSyncRecords: (chainId: number, requestContext?: RequestContext) => Promise<SubgraphSyncRecord[]>;
};

const sdks: Record<number, FallbackSubgraph<Sdk>> = {};

export const getSdks = (): Record<number, FallbackSubgraph<Sdk>> => {
  if (Object.keys(sdks).length === 0) {
    throw new ContractReaderNotAvailableForChain(0);
  }
  return sdks;
};

const analyticsSdks: Record<number, FallbackSubgraph<AnalyticsSdk>> = {};

export const getAnalyticsSdks = (): Record<number, FallbackSubgraph<AnalyticsSdk>> => {
  if (Object.keys(analyticsSdks).length === 0) {
    throw new ContractReaderNotAvailableForChain(0);
  }
  return analyticsSdks;
};

export const subgraphContractReader = (): ContractReader => {
  const { config } = getContext();
  Object.entries(config.chainConfig).forEach(([chainId, { subgraph, analyticsSubgraph, subgraphSyncBuffer }]) => {
    const chainIdNumber = parseInt(chainId);

    const abortController = new AbortController();
    sdks[chainIdNumber] = new FallbackSubgraph<Sdk>(
      chainIdNumber,
      (url: string) => getSdk(new GraphQLClient(url, { signal: abortController.signal })),
      subgraphSyncBuffer,
      SubgraphDomain.COMMON,
      subgraph,
      abortController,
    );

    analyticsSdks[chainIdNumber] = new FallbackSubgraph<AnalyticsSdk>(
      chainIdNumber,
      (url: string) => getAnalyticsSdk(new GraphQLClient(url)),
      subgraphSyncBuffer,
      SubgraphDomain.ANALYTICS,
      analyticsSubgraph,
    );
  });

  return {
    getActiveTransactions,
    getTransactionForChain,
    getAssetBalance,
    getSyncRecords,
    getAssetBalances,
    getExpressiveAssetBalances,
  };
};
