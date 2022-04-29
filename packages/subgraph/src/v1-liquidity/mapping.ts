/* eslint-disable prefer-const */
import { Address, BigInt, Bytes, dataSource } from "@graphprotocol/graph-ts";

import {
  TransactionManager,
  LiquidityAdded,
  LiquidityRemoved,
  TransactionCancelled,
  TransactionFulfilled,
  TransactionPrepared,
} from "../../generated/TransactionManager/TransactionManager";
import { Router, Liquidity } from "../../generated/schema";

export function handleLiquidityAdded(event: LiquidityAdded): void {
  let router = Router.load(event.params.router.toHex());
  if (router == null) {
    router = new Router(event.params.router.toHex());
    router.save();
  }
  const timestamp = event.block.timestamp;

  const liquidity = getOrCreateLiquidityMetric(timestamp, event.params.assetId, event.params.router);

  // add new amount
  liquidity.amount = liquidity.amount.plus(event.params.amount);

  // add supplied amount
  liquidity.supplied = liquidity.supplied.plus(event.params.amount);

  // save
  liquidity.save();
}

export function handleLiquidityRemoved(event: LiquidityRemoved): void {
  const router = Router.load(event.params.router.toHex());
  if (router == null) {
    throw new Error(`Router not found on liquidity removed event`);
  }
  const timestamp = event.block.timestamp;

  const liquidity = getOrCreateLiquidityMetric(timestamp, event.params.assetId, event.params.router);

  // add new amount
  liquidity.amount = liquidity.amount.minus(event.params.amount);

  // add removed amount
  liquidity.removed = liquidity.removed.plus(event.params.amount);

  // save
  liquidity.save();
}

export function handleTransactionPrepared(event: TransactionPrepared): void {
  const router = Router.load(event.params.router.toHex());
  if (router == null) {
    throw new Error(
      `Router (${event.params.router.toHex()}) not found on transaction prepared event on ${event.transaction.hash}`,
    );
  }
  const timestamp = event.block.timestamp;
  const chainId = getChainId(event.address);

  // Update the amount on receiving chain, and the prepared count on both
  // chains
  // NOTE: this means the `preparedTxCount` includes user prepares as well as
  // router prepares, so should reflect the onchain initiated transactions

  let liquidity: Liquidity;
  if (chainId === event.params.txData.receivingChainId) {
    // This is the router-side prepare, should update:
    // - amount -> router liquidity decrements
    liquidity = getOrCreateLiquidityMetric(timestamp, event.params.txData.receivingAssetId, event.params.router);

    liquidity.amount = liquidity.amount.minus(event.params.txData.amount);
  } else {
    liquidity = getOrCreateLiquidityMetric(timestamp, event.params.txData.sendingAssetId, event.params.router);
  }

  liquidity.preparedTxCount = liquidity.preparedTxCount.plus(BigInt.fromI32(1));

  liquidity.save();
}

export function handleTransactionFulfilled(event: TransactionFulfilled): void {
  const router = Router.load(event.params.router.toHex());
  if (router == null) {
    throw new Error(
      `Router (${event.params.router.toHex()}) not found on transaction fulfilled event ${event.transaction.hash}`,
    );
  }
  const timestamp = event.block.timestamp;
  const chainId = getChainId(event.address);

  let liquidity: Liquidity;
  if (chainId === event.params.args.txData.receivingChainId) {
    // This is the user fulfill, should update:
    // - volume -> router successfully provided this liq
    liquidity = getOrCreateLiquidityMetric(timestamp, event.params.args.txData.receivingAssetId, event.params.router);

    liquidity.volume = liquidity.volume.plus(event.params.args.txData.amount);
  } else {
    // This is the router fulfill, should update:
    // - amount -> router liquidity increments
    liquidity = getOrCreateLiquidityMetric(timestamp, event.params.args.txData.sendingAssetId, event.params.router);

    liquidity.amount = liquidity.amount.plus(event.params.args.txData.amount);
  }

  liquidity.fulfilledTxCount = liquidity.fulfilledTxCount.plus(BigInt.fromI32(1));

  liquidity.save();
}

export function handleTransactionCancelled(event: TransactionCancelled): void {
  const router = Router.load(event.params.router.toHex());
  if (router == null) {
    throw new Error(
      `Router (${event.params.router.toHex()}) not found on transaction cancelled event ${event.transaction.hash}`,
    );
  }
  const timestamp = event.block.timestamp;
  const chainId = getChainId(event.address);

  let liquidity: Liquidity;
  if (chainId === event.params.args.txData.receivingChainId) {
    // This is the user fulfill, should update:
    // - amount -> router liquidity restored
    liquidity = getOrCreateLiquidityMetric(timestamp, event.params.args.txData.receivingAssetId, event.params.router);

    liquidity.amount = liquidity.amount.plus(event.params.args.txData.amount);
  } else {
    // This is the user cancel, nothing to update
    liquidity = getOrCreateLiquidityMetric(timestamp, event.params.args.txData.sendingAssetId, event.params.router);
  }

  liquidity.cancelTxCount = liquidity.cancelTxCount.plus(BigInt.fromI32(1));

  liquidity.save();
}

function getChainId(transactionManagerAddress: Address): BigInt {
  // try to get chainId from the mapping
  let network = dataSource.network();
  let chainId: BigInt;
  if (network == "mainnet") {
    chainId = BigInt.fromI32(1);
  } else if (network == "ropsten") {
    chainId = BigInt.fromI32(3);
  } else if (network == "rinkeby") {
    chainId = BigInt.fromI32(4);
  } else if (network == "goerli") {
    chainId = BigInt.fromI32(5);
  } else if (network == "optimism") {
    chainId = BigInt.fromI32(10);
  } else if (network == "cronos") {
    chainId = BigInt.fromI32(25);
  } else if (network == "kovan") {
    chainId = BigInt.fromI32(42);
  } else if (network == "bsc") {
    chainId = BigInt.fromI32(56);
  } else if (network == "chapel") {
    chainId = BigInt.fromI32(97);
  } else if (network == "xdai") {
    chainId = BigInt.fromI32(100);
  } else if (network == "matic") {
    chainId = BigInt.fromI32(137);
  } else if (network == "fantom") {
    chainId = BigInt.fromI32(250);
  } else if (network == "moonbeam") {
    chainId = BigInt.fromI32(1284);
  } else if (network == "boba") {
    chainId = BigInt.fromI32(288);
  } else if (network == "moonriver") {
    chainId = BigInt.fromI32(1285);
  } else if (network == "mbase") {
    chainId = BigInt.fromI32(1287);
  } else if (network == "milkomeda-cardano") {
    chainId = BigInt.fromI32(2001);
  } else if (network == "kava-alphanet") {
    chainId = BigInt.fromI32(2221);
  } else if (network == "evmos") {
    chainId = BigInt.fromI32(9001);
  } else if (network == "arbitrum-one") {
    chainId = BigInt.fromI32(42161);
  } else if (network == "fuji") {
    chainId = BigInt.fromI32(43113);
  } else if (network == "avalanche") {
    chainId = BigInt.fromI32(43114);
  } else if (network == "mumbai") {
    chainId = BigInt.fromI32(80001);
  } else if (network == "arbitrum-rinkeby") {
    chainId = BigInt.fromI32(421611);
  } else if (network == "harmonyone") {
    chainId = BigInt.fromI32(1666600000);
  } else {
    // instantiate contract to get the chainId as a fallback
    chainId = TransactionManager.bind(transactionManagerAddress).getChainId();
  }

  return chainId;
}

function getOrCreateLiquidityMetric(timestamp: BigInt, assetId: Bytes, router: Address): Liquidity {
  let day = timestamp.toI32() / 86400; // rounded
  let dayStartTimestamp = day * 86400;

  let liqId = day.toString() + "-" + assetId.toHex() + "-" + router.toHex();

  let metric = Liquidity.load(liqId);
  if (metric === null) {
    metric = new Liquidity(liqId);
    metric.dayStartTimestamp = BigInt.fromI32(dayStartTimestamp);
    metric.router = router.toHex();
    metric.assetId = assetId.toHex();
    metric.supplied = BigInt.fromI32(0);
    metric.removed = BigInt.fromI32(0);
    metric.volume = BigInt.fromI32(0);
    metric.amount = BigInt.fromI32(0);
    metric.preparedTxCount = BigInt.fromI32(0);
    metric.fulfilledTxCount = BigInt.fromI32(0);
    metric.cancelTxCount = BigInt.fromI32(0);
  }
  return metric;
}
