import { BigNumber, constants } from "ethers";
import {
  Bid,
  BidSchema,
  RequestContext,
  createLoggingContext,
  ajv,
  AuctionStatus,
  getNtpTimeSeconds,
  jsonifyError,
  OriginTransfer,
} from "@connext/nxtp-utils";
import { compare } from "compare-versions";

import { AuctionExpired, MissingXCall, ParamsInvalid, RouterVersionInvalid } from "../errors";
import { getContext } from "../../sequencer";
import { getHelpers } from "../helpers";
import { Message } from "../entities";

import { getOperations } from ".";

export const storeBid = async (bid: Bid, _requestContext: RequestContext): Promise<void> => {
  const {
    logger,
    config,
    adapters: { cache, subgraph, mqClient },
  } = getContext();
  const { requestContext, methodContext } = createLoggingContext(storeBid.name, _requestContext);
  logger.debug(`Method start: ${storeBid.name}`, requestContext, methodContext, { bid });

  const { transferId, origin } = bid;

  // Validate Input schema
  const validateInput = ajv.compile(BidSchema);
  const validInput = validateInput(bid);
  if (!validInput) {
    const msg = validateInput.errors?.map((err: any) => `${err.instancePath} - ${err.message}`).join(",");
    throw new ParamsInvalid({
      paramsError: msg,
      bid,
    });
  }

  // check if bid router version is compatible with hosted sequencer
  const checkVersion = compare(bid.routerVersion, config.supportedBidVersion!, "<");
  if (checkVersion) {
    throw new RouterVersionInvalid({
      supportedBidVersion: config.supportedBidVersion,
      bid,
    });
  }

  // Ensure that the auction for this transfer hasn't expired.
  const status = await cache.auctions.getStatus(transferId);
  if (status !== AuctionStatus.None && status !== AuctionStatus.Queued) {
    throw new AuctionExpired(status, {
      transferId,
      bid,
    });
  }

  // TODO: Check that a relayer is configured/approved for this chain (?).

  // Check to see if we have the XCall data saved locally for this.
  let transfer = await cache.transfers.getTransfer(transferId);
  if (!transfer || !transfer.origin) {
    // Get the XCall from the subgraph for this transfer.
    transfer = await subgraph.getOriginTransferById(origin, transferId);
    if (!transfer || !transfer.origin) {
      // Router shouldn't be bidding on a transfer that doesn't exist.
      throw new MissingXCall(origin, transferId, {
        bid,
      });
    }
    // Store the transfer locally. We will use this as a reference later when we execute this transfer
    // in the auction cycle, for both encoding data and passing relayer fee to the relayer.
    await cache.transfers.storeTransfers([transfer]);
  }

  if (transfer.destination?.execute || transfer.destination?.reconcile) {
    // This transfer has already been Executed or Reconciled, so fast liquidity is no longer valid.
    throw new AuctionExpired(status, {
      transferId,
      bid,
    });
  }

  // Update and/or create the auction instance in the cache if necessary.
  const res = await cache.auctions.upsertAuction({
    transferId,
    origin: transfer.xparams!.originDomain,
    destination: transfer.xparams!.destinationDomain!,
    bid,
  });
  logger.info("Updated auction", requestContext, methodContext, {
    new: res === 0,
    auction: await cache.auctions.getAuction(transferId),
    status: await cache.auctions.getStatus(transferId),
  });

  // Enqueue only once to dedup, when the first bid for the transfer is stored.
  if (status === AuctionStatus.None) {
    const message: Message = { transferId: transfer.transferId, originDomain: transfer.xparams!.originDomain };
    await mqClient.publish(config.messageQueue.publisher!, {
      type: transfer.xparams!.originDomain,
      body: message,
      routingKey: transfer.xparams!.originDomain,
      persistent: true,
    });
    logger.info("Enqueued transfer", requestContext, methodContext, {
      message: message,
    });
  } else {
    logger.debug("No need to enqueue transfer", requestContext, methodContext, {
      transferId: transferId,
      status: status,
    });
  }

  return;
};

export const executeAuction = async (transferId: string, _requestContext: RequestContext) => {
  const {
    config,
    logger,
    adapters: { cache, subgraph },
  } = getContext();
  // TODO: Bit of an antipattern here.
  const {
    relayer: { sendToRelayer },
  } = getOperations();
  const {
    auctions: { getDestinationLocalAsset, getBidsRoundMap, getAllSubsets, getMinimumBidsCountForRound },
  } = getHelpers();
  const { requestContext, methodContext } = createLoggingContext(executeAuction.name, _requestContext);
  logger.debug(`Method start: ${executeAuction.name}`, requestContext, methodContext);

  if (!transferId) {
    logger.debug("No auction to execute", requestContext, methodContext);
    return;
  }

  // Validate if transfer has exceeded the auction period and merits execution.
  const auction = await cache.auctions.getAuction(transferId);
  if (auction) {
    const startTime = Number(auction.timestamp);
    const elapsed = (getNtpTimeSeconds() - startTime) * 1000;
    if (elapsed > config.auctionWaitTime) {
      logger.info("Auction merits execution", requestContext, methodContext, { transferId: transferId });
    } else {
      logger.info("Waiting for auction timeout", requestContext, methodContext, {
        elapsed,
        waitTime: config.auctionWaitTime,
      });
      const remainingTime = config.auctionWaitTime - elapsed;
      // if (remainingTime > 0) setTimeout(() => {}, remainingTime);
      if (remainingTime > 0) await new Promise((f) => setTimeout(f, remainingTime));
    }
  } else {
    logger.error("Auction data not found for transfer!", requestContext, methodContext, undefined, {
      transferId: transferId,
    });
    return;
  }

  // Handling each domain in parallel, but each individual transfer synchronously. This is to account
  // for the fact that one transfer's auction might affect another. For instance, a router might have
  // 100 tokens to LP, but bid on 2 100-token transfers. We shouldn't send both of those bids.

  const { bids, origin, destination } = auction;
  logger.info("Started selecting bids", requestContext, methodContext, {
    bids,
    origin,
    destination,
    transferId,
  });

  // NOTE: Should be an OriginTransfer, but we will sanity check below.
  const transfer = (await cache.transfers.getTransfer(transferId)) as OriginTransfer | undefined;
  if (!transfer) {
    // This should never happen.
    // TODO: Should this be tossed out? We literally can't handle a transfer without the xcall data.
    logger.error("Transfer data not found for transfer!", requestContext, methodContext, undefined, {
      transferId,
      origin,
      destination,
      bids,
    });
    return;
  } else if (!transfer.origin) {
    // TODO: Same as above!
    // Again, shouldn't happen: sequencer should not have accepted an auction for a transfer with no xcall.
    logger.error("XCall or Relayer Fee not found for transfer!", requestContext, methodContext, undefined, {
      transferId,
      transfer,
      bids,
    });
    return;
  }

  const destTx = await subgraph.getDestinationTransferById(transfer.xparams!.destinationDomain!, transferId);
  if (destTx) {
    logger.error("Transfer already executed", requestContext, methodContext, undefined, {
      transferId,
      transfer,
      bids,
    });
    await cache.auctions.setStatus(transferId, AuctionStatus.Executed);
    return;
  }

  const bidsRoundMap = getBidsRoundMap(bids, config.auctionRoundDepth);
  const availableRoundIds = [...Object.keys(bidsRoundMap)].sort((a, b) => Number(a) - Number(b));
  if ([...Object.keys(bidsRoundMap)].length < 1) {
    logger.warn("No rounds available for this transferId", requestContext, methodContext, {
      bidsRoundMap,
      transferId,
    });

    return;
  }

  for (const roundIdx of availableRoundIds) {
    const roundIdInNum = Number(roundIdx);
    const totalBids = bidsRoundMap[roundIdInNum];
    const combinedBidsForRound = getAllSubsets(totalBids, getMinimumBidsCountForRound(roundIdInNum)) as Bid[][];
    logger.debug(`Selecting the round ${roundIdx}`, requestContext, methodContext, {
      availableRoundIds,
      totalBidsCount: totalBids.length,
      totalBids: totalBids,
      combinationCount: combinedBidsForRound.length,
      combinations: combinedBidsForRound,
    });
    let taskId: string | undefined;

    // Try every combinations until we find one that works.
    for (const randomCombination of combinedBidsForRound) {
      const asset = await getDestinationLocalAsset(
        transfer.xparams!.originDomain,
        transfer.origin.assets.bridged.asset,
        destination,
      );
      // TODO: Should use amount from router's bid.
      const amount = transfer.origin.assets.bridged.amount;
      const assignedAmount = BigNumber.from(amount).div(randomCombination.length);

      // Check the liquidity of each router whether it has enough funds
      let insufficientRouterExist = false;
      const routerLiquidityMap: Map<string, BigNumber> = new Map();
      for (const randomBid of randomCombination) {
        const { router } = randomBid;
        let routerLiquidity: BigNumber | undefined = await cache.routers.getLiquidity(router, destination, asset);
        if (!routerLiquidity) {
          // Either we haven't cached the liquidity yet, or the value cached has become expired.
          routerLiquidity = await subgraph.getAssetBalance(destination, router, asset);
          if (!routerLiquidity.eq(constants.Zero)) {
            await cache.routers.setLiquidity(router, destination, asset, routerLiquidity);
          } else {
            // NOTE: Using WARN level here as this is unexpected behavior... routers who are bidding on a transfer should
            // have added liquidity for the asset on the corresponding domain.
            logger.warn("Skipped bid from router; liquidity not found in subgraph", requestContext, methodContext, {
              transfer: {
                transferId,
                asset,
                destination,
                amount: amount.toString(),
              },
              assetBalanceId: `${asset.toLowerCase()}-${router.toLowerCase()}`,
              routerLiquidity,
              router,
            });
            insufficientRouterExist = true;
            break;
          }
        }

        routerLiquidityMap.set(router, routerLiquidity);

        if (routerLiquidity.lt(assignedAmount)) {
          logger.info("Skipped bid from router: insufficient liquidity", requestContext, methodContext, {
            transfer: {
              transferId,
              asset,
              destination,
              totalAmount: amount.toString(),
              assignedAmount,
            },
            router,
            liquidity: routerLiquidity.toString(),
          });
          insufficientRouterExist = true;
          break;
        }
      }

      // Skip this combination if there is a router which doesn't have enough liquidity
      if (insufficientRouterExist) continue;

      try {
        logger.debug("Sending bid to relayer", requestContext, methodContext, {
          transferId,
          bid: {
            // NOTE: Obfuscating signatures here for safety.
            routers: randomCombination.map((bid) => bid.router),
          },
        });
        // Send the relayer request based on chosen bids.
        taskId = await sendToRelayer(roundIdInNum, randomCombination, transfer, asset, requestContext);
        logger.info("Sent bid to relayer", requestContext, methodContext, {
          transferId,
          taskId,
          origin,
          destination,
        });

        // Update router liquidity record to reflect spending.
        for (const router of routerLiquidityMap.keys()) {
          const routerLiqudity = routerLiquidityMap.get(router)!.sub(assignedAmount);
          await cache.routers.setLiquidity(router, destination, asset, routerLiqudity);
        }

        // Break out from the bid selection loop.
        break;
      } catch (error: any) {
        logger.error(
          "Failed to send to relayer, trying next combination if possible",
          requestContext,
          methodContext,
          jsonifyError(error as Error),
          {
            transferId,
            round: roundIdInNum,
            combinations: combinedBidsForRound,
            bidsCount: randomCombination.length,
          },
        );
      }
    }

    if (!taskId) {
      logger.error(
        `No combinations sent to relayer for the round ${roundIdInNum}`,
        requestContext,
        methodContext,
        jsonifyError(new Error("No successfully sent bids")),
        {
          transferId,
          origin,
          destination,
          round: roundIdInNum,
          combinations: combinedBidsForRound,
        },
      );
      continue;
    }

    logger.debug(`Sent combinations successfully in round ${roundIdInNum}`, requestContext, methodContext, {
      transferId,
      origin,
      destination,
      round: roundIdInNum,
      combinations: combinedBidsForRound,
    });

    await cache.auctions.setStatus(transferId, AuctionStatus.Sent);
    await cache.auctions.upsertTask({ transferId, taskId });

    return;
  }
};
