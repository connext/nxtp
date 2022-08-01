import {
  Bid,
  ExecuteArgs,
  OriginTransfer,
  getMinimumBidsCountForRound as _getMinimumBidsCountForRound,
  signSequencerPermitPayload,
} from "@connext/nxtp-utils";
import { constants } from "ethers";

import { getContext } from "../../sequencer";
import { RoundInvalid } from "../errors";

export const encodeExecuteFromBids = async (
  round: number,
  bids: Bid[],
  transfer: OriginTransfer,
  local: string,
): Promise<string> => {
  const {
    adapters: { contracts, wallet },
  } = getContext();
  // Sanity check.
  if (!transfer.origin) {
    throw new Error("XTransfer provided did not have XCall present!");
  }

  // Format arguments from XTransfer.
  const routers = bids.map((b) => b.router);
  const args: ExecuteArgs = {
    params: {
      originDomain: transfer.xparams.originDomain,
      destinationDomain: transfer.xparams.destinationDomain,
      to: transfer.xparams.to,
      callData: transfer.xparams.callData,
      callback: transfer.xparams.callback ?? constants.AddressZero,
      callbackFee: transfer.xparams.callbackFee ?? "0",
      relayerFee: transfer.xparams.relayerFee ?? "0",
      forceSlow: transfer.xparams.forceSlow,
      receiveLocal: transfer.xparams.receiveLocal,
      recovery: transfer.xparams.recovery,
      agent: transfer.xparams.agent,
      destinationMinOut: transfer.xparams.destinationMinOut,
    },
    local,
    routers,
    routerSignatures: bids.map((b) => b.signatures[round.toString()]),
    sequencer: await wallet.getAddress(),
    sequencerSignature: await signSequencerPermitPayload(transfer.transferId, routers, wallet),
    amount: transfer.origin.assets.bridged.amount,
    nonce: transfer.nonce,
    originSender: transfer.origin.xcall.caller,
  };
  return contracts.connext.encodeFunctionData("execute", [args]);
};

/**
 * Returns local asset address on destination domain corresponding to local asset on origin domain
 *
 * @param _originDomain
 * @param _originLocalAsset The asset sent over the bridge
 * @param _destinationDomain
 * @returns
 */
export const getDestinationLocalAsset = async (
  _originDomain: string,
  _originLocalAsset: string,
  _destinationDomain: string,
): Promise<string> => {
  const {
    adapters: { subgraph },
  } = getContext();

  // get canonical asset from orgin domain.
  const sendingDomainAsset = await subgraph.getAssetByLocal(_originDomain, _originLocalAsset);

  const canonicalId = sendingDomainAsset!.canonicalId;

  const destinationDomainAsset = await subgraph.getAssetByCanonicalId(_destinationDomain, canonicalId);

  const localAddress = destinationDomainAsset!.local;
  return localAddress;
};

/**
 * Picks up the valid bids and groups the bids by round
 * @param bids - The array of raw bids, mapping between `router` and `bid` for the specific transferId
 * @param roundDepth - The maximum round which is allowed in the sequencer
 * @returns roundId -> array of bids
 */
export const getBidsRoundMap = (bids: Record<string, Bid>, roundDepth: number): Record<number, Bid[]> => {
  const availableBids: Record<number, Bid[]> = {};
  // Sanity checks and pick up valid bid combinations
  for (let roundIdx = 1; roundIdx <= roundDepth; roundIdx++) {
    const filteredBids = Object.values(bids)
      .filter((bid) => {
        return Array.from(Object.keys(bid.signatures)).includes(roundIdx.toString());
      })
      .map((bid) => {
        const signatures: Record<string, string> = {};
        signatures[roundIdx.toString()] = bid.signatures[roundIdx].toString();
        return { ...bid, signatures };
      });

    // We need 2 ^ (roundIdx - 1) of different bids at least for roundIdx
    if (filteredBids.length >= getMinimumBidsCountForRound(roundIdx)) {
      availableBids[roundIdx] = filteredBids;
    }
  }

  return availableBids;
};

/**
 * Calculates the minimum number of bids for the round
 * round 1 -> amount / 1, round 2 -> amount / 2, round 3 -> amount / 4, round4 -> amount / 8
 * @param round The round id to calculate the minimum number of bids for
 * @returns - The number of bids
 */
export const getMinimumBidsCountForRound = (round: number): number => {
  const { config } = getContext();
  if (round < 1 || round > config.auctionRoundDepth || Math.trunc(round) != round) {
    throw new RoundInvalid({ round, auctionRoundDepth: config.auctionRoundDepth });
  }
  return _getMinimumBidsCountForRound(round);
};

/**
 * Generate all combinations of an array.
 * @param sources - Array of input elements.
 * @param length - Desired length of combinations.
 * @return - Array of combination arrays.
 */
export const getAllSubsets = (sources: any[], length: number): any[] => {
  const sourceLength = sources.length;
  if (length > sourceLength) return [];

  const combos: any[] = []; // Stores valid combinations as they are generated.

  // Accepts a partial combination, an index into sources,
  // and the number of elements required to be added to create a full-length combination.
  // Called recursively to build combinations, adding subsequent elements at each call depth.
  const makeNextCombos = (workingCombo: any[], currentIndex: number, remainingCount: number) => {
    const oneAwayFromComboLength = remainingCount == 1;

    // For each element that remaines to be added to the working combination.
    for (let sourceIndex = currentIndex; sourceIndex < sourceLength; sourceIndex++) {
      // Get next (possibly partial) combination.
      const next = [...workingCombo, sources[sourceIndex]];

      if (oneAwayFromComboLength) {
        // Combo of right length found, save it.
        combos.push(next);
      } else {
        // Otherwise go deeper to add more elements to the current partial combination.
        makeNextCombos(next, sourceIndex + 1, remainingCount - 1);
      }
    }
  };

  makeNextCombos([], 0, length);
  return combos;
};
