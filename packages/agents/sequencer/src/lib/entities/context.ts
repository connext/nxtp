import { Wallet } from "ethers";
import { ChainData, Logger } from "@connext/nxtp-utils";
import { StoreManager } from "@connext/nxtp-adapters-cache";
import { SubgraphReader } from "@connext/nxtp-adapters-subgraph";
import { Web3Signer } from "@connext/nxtp-adapters-web3signer";
import { ChainReader, ConnextContractInterfaces } from "@connext/nxtp-txservice";
import Broker from "foo-foo-mq";

import { Relayer } from "../../adapters";

import { SequencerConfig } from ".";

export type AppContext = {
  logger: Logger;
  adapters: {
    // Stateful interfaces for peripherals.
    subgraph: SubgraphReader; // Aggregates subgraphs in a FallbackSubgraph for each chain.
    cache: StoreManager; // Used to cache important data locally.
    chainreader: ChainReader; // For reading blockchain using RPC providers.
    contracts: ConnextContractInterfaces; // Used to encode/decode fn data for smart contracts.
    relayer: Relayer; // Relayer for sending transactions to the blockchain.
    // Should be signer for sequencer's whitelisted EOA. Used for signing permits.
    wallet: Wallet | Web3Signer;
    mqClient: typeof Broker; // Broker for interacting with the message queue
  };
  config: SequencerConfig;
  chainData: Map<string, ChainData>;
};
