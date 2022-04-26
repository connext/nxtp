import { BigNumber } from "ethers";
import {
  Bid,
  BidSchema,
  RequestContext,
  createLoggingContext,
  ajv,
  AuctionStatus,
  getNtpTimeSeconds,
  Auction,
  jsonifyError,
} from "@connext/nxtp-utils";

import { AuctionExpired, MissingXCall, ParamsInvalid } from "../errors";
import { getContext } from "../../sequencer";

import { getOperations } from ".";

export const storeBid = async (bid: Bid, _requestContext: RequestContext): Promise<void> => {
  const {
    logger,
    adapters: { cache, subgraph },
  } = getContext();
  const { requestContext, methodContext } = createLoggingContext(storeBid.name, _requestContext);
  logger.info(`Method start: ${storeBid.name}`, requestContext, methodContext, { bid });

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
  if (!transfer) {
    // Get the XCall from the subgraph for this transfer.
    transfer = await subgraph.getTransfer(origin, transferId);
    if (!transfer) {
      // Router shouldn't be bidding on a transfer that doesn't exist.
      throw new MissingXCall(origin, transferId, {
        bid,
      });
    }
    // Store the transfer locally. We will use this as a reference later when we execute this transfer
    // in the auction cycle, for both encoding data and passing relayer fee to the relayer.
    await cache.transfers.storeTransfers([transfer]);
  }

  if (transfer.execute || transfer.reconcile) {
    // This transfer has already been Executed or Reconciled, so fast liquidity is no longer valid.
    throw new AuctionExpired(status, {
      transferId,
      bid,
    });
  }

  // Update and/or create the auction instance in the cache if necessary.
  const res = await cache.auctions.upsertAuction({
    transferId,
    origin: transfer.originDomain,
    destination: transfer.destinationDomain,
    bid,
  });
  logger.info("Updated auction", requestContext, methodContext, {
    new: res === 0,
    auction: await cache.auctions.getAuction(transferId),
    status: await cache.auctions.getStatus(transferId),
  });

  return;
};

export const executeAuctions = async (_requestContext: RequestContext) => {
  const {
    config,
    logger,
    adapters: { cache, subgraph },
  } = getContext();
  // TODO: Bit of an antipattern here.
  const {
    relayer: { sendToRelayer },
  } = getOperations();
  const { requestContext, methodContext } = createLoggingContext(executeAuctions.name, _requestContext);

  logger.debug(`Method start: ${executeAuctions.name}`, requestContext, methodContext);

  // Fetch all the queued transfer IDs from the cache.
  const transferIds: string[] = await cache.auctions.getQueuedTransfers();

  if (transferIds.length === 0) {
    logger.debug("No auctions to execute", requestContext, methodContext);
    return;
  }

  logger.info("Queued transfers", requestContext, methodContext, {
    transferIds,
    count: transferIds.length,
  });

  // Filter transfers by whether they have exceeded the auction period and merit execution.
  const auctions: { [domain: string]: { [transferIds: string]: Auction } } = {};
  await Promise.all(
    transferIds.map(async (transferId) => {
      const auction = await cache.auctions.getAuction(transferId);
      if (auction) {
        const startTime = Number(auction.timestamp);
        const elapsed = (getNtpTimeSeconds() - startTime) * 1000;
        if (elapsed > config.auctionWaitTime) {
          const domain = auction.destination;
          auctions[domain] = {
            ...(auctions[domain] || {}),
            [transferId]: auction,
          };
        }
      }
    }),
  );

  // Handling each domain in parallel, but each individual transfer synchronously. This is to account
  // for the fact that one transfer's auction might affect another. For instance, a router might have
  // 100 tokens to LP, but bid on 2 100-token transfers. We shouldn't send both of those bids.
  await Promise.all(
    Object.keys(auctions).map(async (domain) => {
      for (const transferId of Object.keys(auctions[domain])) {
        const { bids, origin, destination } = auctions[domain][transferId];
        logger.info("Started selecting bids", requestContext, methodContext, {
          bids,
          origin,
          destination,
          transferId,
        });

        const transfer = await cache.transfers.getTransfer(transferId);
        if (!transfer) {
          // This should never happen.
          // TODO: Should this be tossed out? We literally can't handle a transfer without the xcall data.
          logger.error("Transfer data not found for transfer!", requestContext, methodContext, undefined, {
            transferId,
            origin,
            destination,
            bids,
          });
          continue;
        } else if (!transfer.xcall || !transfer.relayerFee) {
          // TODO: Same as above!
          // Again, shouldn't happen: sequencer should not have accepted an auction for a transfer with no xcall.
          logger.error("XCall or Relayer Fee not found for transfer!", requestContext, methodContext, undefined, {
            transferId,
            transfer,
            bids,
          });
          continue;
        }

        // TODO: Reimplement auction rounds!
        // hardcoded round 1
        const availableBids = Object.values(bids).filter((bid) => {
          // TODO: Check to make sure this specific router has enough funds to execute this bid! Right now,
          // all we are doing is an estimateGas call in sendToRelayer below.
          return Array.from(Object.keys(bid.signatures)).includes("1");
        });
        if (availableBids.length < 1) {
          logger.warn("No bids available for this round", requestContext, methodContext, {
            availableBids,
            transferId,
          });
          // Not enough router bids to form a transfer for this round.
          // (e.g. for round 3, we need 3 router bids to form a multipath transfer)
          continue;
        }

        // TODO: Sort by fee amount, selecting the best bid available.
        // Randomly sort the bids.
        const randomized = availableBids
          .map((value) => ({ value, sort: Math.random() }))
          .sort((a, b) => a.sort - b.sort)
          .map(({ value }) => value);

        let taskId: string | undefined;
        // Try every bid until we find one that works.
        for (const randomBid of randomized) {
          // Sanity: Check if this router has enough funds.
          const { router } = randomBid;
          const { amount: _amount, local: asset } = bidData;
          const amount = BigNumber.from(_amount);
          let routerLiquidity: BigNumber | undefined = await cache.routers.getLiquidity(router, destination, asset);

          if (!routerLiquidity) {
            // Either we haven't cached the liquidity yet, or the value cached has become expired.
            routerLiquidity = await subgraph.getAssetBalance(destination, router, asset);
            if (routerLiquidity) {
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
                router,
              });
              continue;
            }
          }

          if (routerLiquidity.lt(amount)) {
            logger.info("Skipped bid from router: insufficient liquidity", requestContext, methodContext, {
              transfer: {
                transferId,
                asset,
                destination,
                amount: amount.toString(),
              },
              router,
              liquidity: routerLiquidity.toString(),
            });
            continue;
          }

          try {
            logger.info("Sending bid to relayer", requestContext, methodContext, {
              transferId,
              bid: {
                // NOTE: Obfuscating signatures here for safety.
                router: randomBid.router,
                fee: randomBid.fee,
              },
            });
            // Send the relayer request based on chosen bids.
            taskId = await sendToRelayer(
              [randomBid.router],
              transfer,
              {
                amount: transfer.relayerFee!,
                asset: transfer.xcall!.localAsset,
              },
              requestContext,
            );
            logger.info("Sent bid to relayer", requestContext, methodContext, {
              transferId,
              taskId,
              origin,
              destination,
            });

            // Update router liquidity record to reflect spending.
            routerLiquidity = routerLiquidity.sub(amount);
            await cache.routers.setLiquidity(router, destination, asset, routerLiquidity);

            // Break out from the bid selection loop.
            break;
          } catch (error: any) {
            logger.error(
              "Failed to send to relayer, trying next bid if possible",
              requestContext,
              methodContext,
              jsonifyError(error as Error),
              {
                transferId,
                availableBidsCount: availableBids.length,
              },
            );
          }
        }
        if (!taskId) {
          logger.error(
            "No bids sent to relayer",
            requestContext,
            methodContext,
            jsonifyError(new Error("No successfully sent bids")),
            {
              transferId,
              origin,
              destination,
              bids,
            },
          );
          continue;
        }
        await cache.auctions.setStatus(transferId, AuctionStatus.Sent);
        await cache.auctions.upsertTask({ transferId, taskId });
      }
    }),
  );
};
