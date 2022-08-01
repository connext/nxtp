import { NxtpError, DestinationTransfer, OriginTransfer } from "@connext/nxtp-utils";
import { BigNumber } from "ethers";

import { XQueryResultParseError } from "../errors";

import { getHelpers } from ".";

// Used for sanity checking: both OriginTransfer and DestinationTransfer will have these fields defined.
export const SHARED_TRANSFER_ENTITY_REQUIREMENTS = ["transferId"];

export const originTransfer = (entity: any): OriginTransfer => {
  // Sanity checks.
  if (!entity) {
    throw new NxtpError("Subgraph `OriginTransfer` entity parser: Transfer entity is `undefined`.");
  }
  if (entity.executedTransactionHash || entity.reconciledTransactionHash) {
    // Wrong transfer type. This is a destination transfer entity!
    throw new NxtpError("Subgraph `OriginTransfer` entity parser: Transfer entity is a destination transfer entity.");
  }
  for (const field of [
    ...SHARED_TRANSFER_ENTITY_REQUIREMENTS,
    "originDomain",
    "destinationDomain",
    "nonce",
    "to",
    "callData",
  ]) {
    if (!entity[field]) {
      throw new NxtpError("Subgraph `OriginTransfer` entity parser: Transfer entity missing required field", {
        missingField: field,
        entity,
      });
    }
  }

  return {
    // Meta Data

    transferId: entity.transferId,
    nonce: BigNumber.from(entity.nonce).toNumber(),

    // Call Params
    xparams: {
      to: entity.to,
      callData: entity.callData,
      callback: entity.callback,
      callbackFee: entity.callbackFee,
      relayerFee: entity.relayerFee,
      forceSlow: entity.forceSlow,
      receiveLocal: entity.receiveLocal,
      originDomain: entity.originDomain,
      destinationDomain: entity.destinationDomain,
      recovery: entity.recovery,
      agent: entity.agent,
      destinationMinOut: entity.destinationMinOut,
    },

    // Origin Info
    origin: {
      chain: entity.chainId,

      // Event Data
      originMinOut: entity.originMinOut,

      // Assets
      assets: {
        transacting: {
          asset: entity.transactingAsset,
          amount: entity.transactingAmount,
        },
        bridged: {
          asset: entity.bridgedAsset,
          amount: entity.bridgedAmount,
        },
      },

      // XCall
      xcall: {
        // Transaction Data
        caller: entity.caller,
        transactionHash: entity.transactionHash,
        timestamp: BigNumber.from(entity.timestamp ?? "0").toNumber(),
        gasPrice: entity.gasPrice,
        gasLimit: entity.gasLimit,
        blockNumber: BigNumber.from(entity.blockNumber ?? "0").toNumber(),
      },
    },

    // Destination Info
    destination: undefined,
  };
};

export const destinationTransfer = (entity: any): DestinationTransfer => {
  // Sanity checks.
  if (!entity) {
    throw new NxtpError("Subgraph `DestinationTransfer` entity parser: Transfer entity is `undefined`.");
  }
  if (entity.transactionHash) {
    // Wrong transfer type. This is an origin transfer entity!
    throw new NxtpError("Subgraph `DestinationTransfer` entity parser: Transfer entity is an origin transfer entity.");
  }
  for (const field of [
    ...SHARED_TRANSFER_ENTITY_REQUIREMENTS,
    // NOTE: destinationDomain is not emitted by Reconciled event, it could be undefined.
    "originDomain",
    "localAmount",
    "localAsset",
    "status",
    "routers",
  ]) {
    if (!entity[field]) {
      throw new NxtpError("Subgraph `DestinationTransfer` entity parser: Transfer entity missing required field", {
        missingField: field,
        entity,
      });
    }
  }

  return {
    // Meta Data

    transferId: entity.transferId,
    nonce: entity.nonce ? BigNumber.from(entity.nonce).toNumber() : undefined,

    // Call Params
    xparams: {
      to: entity.to,
      callData: entity.callData,
      callback: entity.callback,
      callbackFee: entity.callbackFee,
      relayerFee: entity.relayerFee,
      forceSlow: entity.forceSlow,
      receiveLocal: entity.receiveLocal,
      destinationDomain: entity.destinationDomain,
      originDomain: entity.originDomain,
      recovery: entity.recovery,
      agent: entity.agent,
      destinationMinOut: entity.destinationMinOut,
    },

    // Origin Info
    origin: undefined,

    // Destination Info
    destination: {
      chain: entity.chainId,

      // Status (Executed | Reconciled | Completed)
      status: entity.status,
      routers: entity.routers.map((router: any) => router.id),

      // Assets
      assets: {
        transacting:
          entity.transactingAmount && entity.transactingAsset
            ? {
                asset: entity.transactingAsset,
                amount: entity.transactingAmount,
              }
            : undefined,
        local: {
          asset: entity.localAsset,
          amount: entity.localAmount,
        },
      },

      // Execute
      execute: entity.executedTransactionHash
        ? {
            // Event Data
            originSender: entity.originSender,
            // Transaction Data
            caller: entity.executedCaller,
            transactionHash: entity.executedTransactionHash,
            timestamp: BigNumber.from(entity.executedTimestamp ?? "0").toNumber(),
            gasPrice: entity.executedGasPrice,
            gasLimit: entity.executedGasLimit,
            blockNumber: BigNumber.from(entity.executedBlockNumber ?? "0").toNumber(),
          }
        : undefined,

      // Reconcile
      reconcile: entity.reconciledTransactionHash
        ? {
            // Transaction Data
            caller: entity.reconciledCaller,
            transactionHash: entity.reconciledTransactionHash,
            timestamp: BigNumber.from(entity.reconciledTimestamp ?? "0").toNumber(),
            gasPrice: entity.reconciledGasPrice,
            gasLimit: entity.reconciledGasLimit,
            blockNumber: BigNumber.from(entity.reconciledBlockNumber ?? "0").toNumber(),
          }
        : undefined,
    },
  };
};

/**
 * Parses raw response of crosschain query request and group by domain
 * @param response The raw response from endpoints
 */
export const xquery = (response: any): Map<string, any[]> => {
  const { getDomainFromPrefix } = getHelpers();
  const result: Map<string, any[]> = new Map();
  if (response.data) {
    const entityRes = response.data as Record<string, any[]>;
    for (const key of Object.keys(entityRes)) {
      const prefix = key.split("_")[0].toLowerCase();
      const domain = getDomainFromPrefix(prefix);
      if (domain) {
        const value = entityRes[key];
        if (result.has(domain)) {
          result.get(domain)!.push(value);
        } else {
          result.set(domain, [value]);
        }
      }
    }

    return result;
  } else {
    throw new XQueryResultParseError({ response });
  }
};
