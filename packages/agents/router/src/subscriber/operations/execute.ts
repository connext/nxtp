import {
  Bid,
  createLoggingContext,
  ajv,
  XTransferSchema,
  OriginTransfer,
  RequestContext,
  formatUrl,
  AuctionsApiPostBidReq,
  getMinimumBidsCountForRound as _getMinimumBidsCountForRound,
} from "@connext/nxtp-utils";
import { BigNumber } from "ethers";
import axios, { AxiosResponse } from "axios";

import {
  AuctionExpired,
  CallDataForNonContract,
  InvalidAuctionRound,
  MissingXCall,
  NonRetryableBidPostError,
  NotEnoughAmount,
  ParamsInvalid,
  RetryableBidPostError,
  SequencerResponseInvalid,
  UnableToGetAsset,
  NomadHomeBlacklisted,
  RouterVersionInvalid,
} from "../../errors";
// @ts-ignore
import { version } from "../../../package.json";
import { getContext } from "../subscriber";
import { signRouterPathPayload } from "../../mockable";

//helper function to match our config environments with nomads
export const getBlacklist = async (
  originDomain: string,
  destinationDomain: string,
): Promise<{ originBlacklisted: boolean; destinationBlacklisted: boolean }> => {
  const { bridgeContext: context } = getContext();
  if (!context) {
    return { originBlacklisted: false, destinationBlacklisted: false };
  }
  //todo: look for higher level import of this class
  //push them to blacklist if not there already
  await context.checkHomes([Number(originDomain), Number(destinationDomain)]);

  //get blacklist
  const blacklist = context.blacklist();

  //determine if origin or destintion aren't connected to nomad
  const originBlacklisted = blacklist.has(Number(originDomain));
  const destinationBlacklisted = blacklist.has(Number(destinationDomain));

  return { originBlacklisted, destinationBlacklisted };
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
): Promise<string | undefined> => {
  const {
    adapters: { subgraph },
  } = getContext();

  // get canonical asset from orgin domain.
  const sendingDomainAsset = await subgraph.getAssetByLocal(_originDomain, _originLocalAsset);

  const canonicalId = sendingDomainAsset?.canonicalId;

  if (!canonicalId) {
    return undefined;
  }

  const destinationDomainAsset = await subgraph.getAssetByCanonicalId(_destinationDomain, canonicalId);

  const localAddress = destinationDomainAsset?.local;

  return localAddress;
};

export const sendBid = async (bid: Bid, _requestContext: RequestContext): Promise<any> => {
  const { config, logger } = getContext();
  const { sequencerUrl } = config;
  const { requestContext, methodContext } = createLoggingContext(sendBid.name, _requestContext);

  const { transferId } = bid;

  logger.debug("Sending bid to sequencer", requestContext, methodContext, {
    transferId,
    // Remove actual signatures (sensitive data) from logs, but list participating rounds.
    bid: { ...bid, signatures: Object.keys(bid.signatures).join(",") },
  });

  const url = formatUrl(sequencerUrl, "auctions");
  try {
    const response = await axios.post<any, AxiosResponse<any, any>, AuctionsApiPostBidReq>(url, bid);
    // Make sure response.data is valid.
    if (!response || !response.data) {
      throw new SequencerResponseInvalid({ response });
    }
    logger.info("Sent bid to sequencer", requestContext, methodContext, { data: response.data });
    return response.data;
  } catch (error: any) {
    if (error.response?.data?.message === "AuctionExpired") {
      // TODO: Should we mark this transfer as expired? Technically speaking, it *could* become unexpired
      // if the sequencer decides relayer execution has timed out.
      throw new AuctionExpired({ transferId, requestContext, methodContext, data: error.response.data });
    } else if (error.response?.data?.message === "MissingXCall") {
      // TODO: Should we mark this transfer as expired? Technically speaking, it *could* become unexpired
      // if the sequencer decides relayer execution has timed out.
      throw new RetryableBidPostError({ transferId, requestContext, methodContext, data: error.response.data });
    } else if (error.response?.data?.message === "RouterVersionInvalid") {
      // TODO: Should we mark this transfer as expired? Technically speaking, it *could* become unexpired
      // if the sequencer decides relayer execution has timed out.
      throw new RouterVersionInvalid({ transferId, requestContext, methodContext, data: error.response.data });
    } else {
      const errorObj: any = {};
      if (error.response) {
        // The request was made and the server responded with a status code
        // that falls out of the range of 2xx
        errorObj.data = error.response.data;
        errorObj.status = error.response.status;
        errorObj.headers = error.response.headers;
      } else if (error.request) {
        errorObj.request = error.request;
      } else {
        // Something happened in setting up the request that triggered an Error
        errorObj.message = error.message;
      }
      errorObj.config = error.config;
      throw new NonRetryableBidPostError({
        transferId,
        requestContext,
        methodContext,
        error: errorObj,
      });
    }
  }
};

/**
 * Calculates the auction amount for `roundId`. Router needs to decide which rounds it needs to bid on.
 * @param roundId - The round number you're going to get the auction amount.
 * @param receivingAmount - The total amount
 */
export const getAuctionAmount = (roundId: number, receivingAmount: BigNumber): BigNumber => {
  return receivingAmount.div(getMinimumBidsCountForRound(roundId));
};

/**
 * Calculates the number of routers needed for a specific round
 * @param roundId - The round number
 */
export const getMinimumBidsCountForRound = (roundId: number): number => {
  const { config } = getContext();
  if (roundId > config.auctionRoundDepth || roundId < 1 || roundId != Math.trunc(roundId)) {
    throw new InvalidAuctionRound({
      roundId,
      startRound: 1,
      maxRoundDepth: config.auctionRoundDepth,
    });
  }
  return _getMinimumBidsCountForRound(roundId);
};

/**
 * Router creates a new bid and sends it to auctioneer.
 *
 * @param params - The crosschain xcall params.
 */
export const execute = async (params: OriginTransfer, _requestContext: RequestContext): Promise<void> => {
  const { requestContext, methodContext } = createLoggingContext(execute.name, _requestContext);

  const {
    config,
    logger,
    adapters: { wallet, subgraph, txservice },
    routerAddress,
  } = getContext();

  logger.debug("Method start", requestContext, methodContext, { params });

  // Validate Input schema
  const validateInput = ajv.compile(XTransferSchema);
  const validInput = validateInput(params);
  if (!validInput) {
    const msg = validateInput.errors?.map((err: any) => `${err.instancePath} - ${err.message}`).join(",");
    throw new ParamsInvalid({
      paramsError: msg,
      params,
    });
  }

  const {
    origin,
    transferId,
    xparams: { callData, to, forceSlow, originDomain, destinationDomain },
  } = params;

  if (forceSlow) {
    logger.debug("Opt for slow path", requestContext, methodContext, {});
    return;
  }

  const dest = await subgraph.getDestinationTransferById(destinationDomain, transferId);
  if (dest) {
    logger.info("Destination transfer already exists", requestContext, methodContext, {});
    return;
  }

  const _origin = await subgraph.getOriginTransferById(originDomain, transferId);
  if (!_origin) {
    throw new MissingXCall({ requestContext, methodContext });
  }

  logger.debug("Getting local asset", requestContext, methodContext, {
    originDomain,
    asset: origin.assets.bridged.asset,
    destinationDomain,
  });
  let executeLocalAsset;
  try {
    executeLocalAsset = await getDestinationLocalAsset(originDomain, origin.assets.bridged.asset, destinationDomain);
  } catch (err: unknown) {
    throw new UnableToGetAsset({
      requestContext,
      methodContext,
      originDomain,
      destinationDomain,
      asset: origin.assets.bridged.asset,
    });
  }

  if (!executeLocalAsset) {
    throw new UnableToGetAsset({
      requestContext,
      methodContext,
      originDomain,
      destinationDomain,
      asset: origin.assets.bridged.asset,
    });
  }

  logger.debug("Got local asset", requestContext, methodContext, { executeLocalAsset });

  const receivingAmount = origin.assets.bridged.amount;

  // TODO: We should make a list of signatures that reflect which auction rounds we want to bid on,
  // based on a calculation of which rounds we can afford to bid on. For now, this is hardcoded to bid
  // only on the first auction round.
  // Produce the router path signatures for each auction round we want to bid on.

  // Make a list of signatures that reflect which auction rounds we want to bid on.
  const balance = await subgraph.getAssetBalance(destinationDomain, routerAddress, executeLocalAsset);
  const signatures: Record<string, string> = {};
  for (let roundIdx = 1; roundIdx <= config.auctionRoundDepth; roundIdx++) {
    const amountForRound = getAuctionAmount(roundIdx, BigNumber.from(receivingAmount));
    if (amountForRound.lte(balance)) {
      const pathLen = Math.pow(2, roundIdx - 1);
      signatures[roundIdx.toString()] = await signRouterPathPayload(transferId, pathLen.toString(), wallet);
    } else {
      logger.debug(`Not enough balance for this round: ${roundIdx}. Skipping!`, requestContext, methodContext, {
        balance: balance.toString(),
        amountForRound: amountForRound.toString(),
      });
    }
  }

  if ([...Object.keys(signatures)].length == 0) {
    throw new NotEnoughAmount({
      balance: balance.toString(),
      receivingAmount: receivingAmount.toString(),
      executeLocalAsset,
      routerAddress,
      destinationDomain: destinationDomain,
      maxRoundDepth: config.auctionRoundDepth,
      requestContext,
      methodContext,
    });
  }

  logger.debug("Signed payloads", requestContext, methodContext, {
    rounds: Object.keys(signatures),
    // Sanitized with ellipsis.
    sigs: Object.values(signatures).map((s) => s.slice(0, 6) + ".."),
  });

  // Need to make sure if nomad-sdk handles an error in case of bad rpc before integrating.
  // Test code base: https://codesandbox.io/s/nomad-integration-testing-h8q00t?file=/index.js

  const { originBlacklisted, destinationBlacklisted } = await getBlacklist(originDomain, destinationDomain);
  if (originBlacklisted || destinationBlacklisted) {
    throw new NomadHomeBlacklisted({
      originDomainBlacklisted: originBlacklisted,
      destinationBlacklisted: destinationBlacklisted,
    });
  }

  if (callData !== "0x") {
    const code = await txservice.getCode(+destinationDomain, to);
    if (code === "0x") {
      throw new CallDataForNonContract({ transferId, destinationDomain, to, callData, requestContext, methodContext });
    }
  }

  logger.debug("Sanity checks passed", requestContext, methodContext, { liquidity: balance.toString() });

  const bid: Bid = {
    routerVersion: version,
    transferId,
    origin: originDomain,
    router: routerAddress.toLowerCase(),
    signatures,
  };

  await sendBid(bid, requestContext);
  logger.info("Executed transfer", requestContext, methodContext, { params });
};
