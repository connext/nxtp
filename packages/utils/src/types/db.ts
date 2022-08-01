import { BigNumber, constants } from "ethers";

import { AssetBalance, RouterBalance, XTransfer, XTransferStatus } from "./xtransfers";

/**
 * This is required to make sure numbers do not lose precision because of Javascript limitations.
 * All BigNumbers are selected as text into JS.
 */
export const transfersCastForUrl =
  "select=transfer_id,nonce,to,call_data,origin_domain,destination_domain,agent,recovery,force_slow,receive_local,callback,callback_fee,relayer_fee,slippage_tol,origin_chain,origin_transacting_asset,origin_transacting_amount::text,origin_bridged_asset,origin_bridged_amount::text,xcall_caller,xcall_transaction_hash,xcall_timestamp,xcall_gas_price::text,xcall_gas_limit::text,xcall_block_number,destination_chain,status,routers,destination_transacting_asset,destination_transacting_amount::text,destination_local_asset,destination_local_amount::text,execute_caller,execute_transaction_hash,execute_timestamp,execute_gas_price::text,execute_gas_limit::text,execute_block_number,execute_origin_sender,reconcile_caller,reconcile_transaction_hash,reconcile_timestamp,reconcile_gas_price::text,reconcile_gas_limit::text,reconcile_block_number";

/**
 * Converts a transfer from the cartographer db through either DB queries or Postgrest into the XTransfer type
 * @param transfer - the transfer from the cartographer db as a JSON object
 * @returns an XTransfer object
 */
export const convertFromDbTransfer = (transfer: any): XTransfer => {
  return {
    nonce: BigNumber.from(transfer.nonce).toNumber(),
    xparams: {
      to: transfer.to || constants.AddressZero,
      callData: transfer.call_data || "0x",
      originDomain: transfer.origin_domain,
      destinationDomain: transfer.destination_domain,
      recovery: transfer.recovery || constants.AddressZero,
      agent: transfer.agent || constants.AddressZero,
      callback: transfer.callback || constants.AddressZero,
      callbackFee: transfer.callback_fee || "0",
      relayerFee: BigNumber.from(BigInt((transfer.relayer_fee as string) ?? "0")).toString(),
      forceSlow: transfer.force_slow || false,
      receiveLocal: transfer.receive_local || false,
      destinationMinOut: BigNumber.from(BigInt((transfer.destination_min_out as string) ?? "0")).toString(),
    },
    transferId: transfer.transfer_id,

    origin: transfer.origin_chain
      ? {
          chain: transfer.origin_chain,
          originMinOut: BigNumber.from(BigInt((transfer.origin_min_out as string) ?? "0")).toString(),
          assets: {
            transacting: {
              amount: BigNumber.from(BigInt((transfer.origin_transacting_amount as string) ?? "0")).toString(),
              asset: transfer.origin_transacting_asset!,
            },
            bridged: {
              amount: BigNumber.from(BigInt((transfer.origin_bridged_amount as string) ?? "0")).toString(),
              asset: transfer.origin_bridged_asset!,
            },
          },
          xcall: {
            blockNumber: transfer.xcall_block_number!,
            caller: transfer.xcall_caller!,
            gasLimit: BigNumber.from(BigInt((transfer.xcall_gas_limit as string) ?? "0")).toString(),
            gasPrice: BigNumber.from(BigInt((transfer.xcall_gas_price as string) ?? "0")).toString(),
            timestamp: transfer.xcall_timestamp!,
            transactionHash: transfer.xcall_transaction_hash!,
          },
        }
      : undefined,

    destination: transfer.destination_chain
      ? {
          chain: transfer.destination_chain,
          assets: {
            transacting: {
              amount: BigNumber.from(BigInt((transfer.destination_transacting_amount as string) ?? "0")).toString(),
              asset: transfer.destination_transacting_asset!,
            },
            local: {
              amount: BigNumber.from(BigInt((transfer.destination_local_amount as string) ?? "0")).toString(),
              asset: transfer.destination_local_asset!,
            },
          },
          routers: transfer.routers || [],
          status: transfer.status === "XCalled" ? "Executed" : (transfer.status as XTransferStatus),
          execute: {
            blockNumber: transfer.execute_block_number!,
            caller: transfer.execute_caller!,
            gasLimit: BigNumber.from(BigInt((transfer.execute_gas_limit as string) ?? "0")).toString(),
            gasPrice: BigNumber.from(BigInt((transfer.execute_gas_price as string) ?? "0")).toString(),
            timestamp: transfer.execute_timestamp!,
            transactionHash: transfer.execute_transaction_hash!,
            originSender: transfer.execute_origin_sender!,
          },
          reconcile: {
            blockNumber: transfer.reconcile_block_number!,
            caller: transfer.reconcile_caller!,
            gasLimit: BigNumber.from(BigInt((transfer.reconcile_gas_limit as string) ?? "0")).toString(),
            gasPrice: BigNumber.from(BigInt((transfer.reconcile_gas_price as string) ?? "0")).toString(),
            timestamp: transfer.reconcile_timestamp!,
            transactionHash: transfer.reconcile_transaction_hash!,
          },
        }
      : undefined,
  };
};

/**
 * Converts router balance rows into a RouterBalance array
 * Example rows:
[
  {
    address: '0xa000000000000000000000000000000000000000',
    asset_canonical_id: '0xb000000000000000000000000000000000000000000000000000000000000000',
    asset_domain: '1234',
    router_address: '0xa000000000000000000000000000000000000000',
    balance: 100000000000000000000,
    local: '0xbb00000000000000000000000000000000000000',
    adopted: '0xaa00000000000000000000000000000000000000',
    canonical_id: '0xb000000000000000000000000000000000000000000000000000000000000000',
    canonical_domain: '1111',
    domain: '1234'
  },
  {
    address: '0xa000000000000000000000000000000000000000',
    asset_canonical_id: '0xbb00000000000000000000000000000000000000000000000000000000000000',
    asset_domain: '1234',
    router_address: '0xa000000000000000000000000000000000000000',
    balance: 99000000000000000000,
    local: '0xbb00000000000000000000000000000000000000',
    adopted: '0xaa00000000000000000000000000000000000000',
    canonical_id: '0xbb00000000000000000000000000000000000000000000000000000000000000',
    canonical_domain: '1111',
    domain: '1234'
  },
]
 * @param routerBalanceRows
 */
export const convertToRouterBalance = (routerBalanceRows: any[]): RouterBalance[] => {
  const routerBalances: RouterBalance[] = [];
  routerBalanceRows.forEach((routerBalanceRow) => {
    const assetBalance: AssetBalance = {
      adoptedAsset: routerBalanceRow.adopted,
      balance: BigNumber.from(BigInt(routerBalanceRow.balance as string)).toString(),
      blockNumber: "0",
      canonicalDomain: routerBalanceRow.canonical_domain,
      canonicalId: routerBalanceRow.canonical_id,
      domain: routerBalanceRow.asset_domain,
      local: routerBalanceRow.local,
    };
    const found = routerBalances.find((r) => r.router === routerBalanceRow.router_address);
    if (found) {
      const asset = found.assets.find(
        (a) => a.canonicalId === routerBalanceRow.asset_canonical_id && a.domain === routerBalanceRow.asset_domain,
      );
      if (asset) {
        asset.balance = BigNumber.from(BigInt(routerBalanceRow.balance as string)).toString();
      } else {
        found.assets.push(assetBalance);
      }
    } else {
      routerBalances.push({ router: routerBalanceRow.router_address, assets: [assetBalance] });
    }
  });

  return routerBalances;
};
