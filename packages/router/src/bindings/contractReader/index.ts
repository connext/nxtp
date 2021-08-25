import { createRequestContext, delay, getUuid, jsonifyError, safeJsonStringify } from "@connext/nxtp-utils";

import { getContext } from "../../router";
import { ActiveTransaction, CrosschainTransactionStatus, FulfillPayload, PreparePayload } from "../../lib/entities";
import { getOperations } from "../../lib/operations";
import { ContractReaderNotAvailableForChain } from "../../lib/errors";

const LOOP_INTERVAL = 15_000;
export const getLoopInterval = () => LOOP_INTERVAL;

export const bindContractReader = async () => {
  const { contractReader, logger } = getContext();
  setInterval(async () => {
    try {
      const transactions = await contractReader.getActiveTransactions();
      if (transactions.length > 0) {
        logger.info({ transactions: transactions.length }, "Got active transactions");
        logger.debug({ transactions }, "Got active transactions");
      }
      await handleActiveTransactions(transactions);
    } catch (err) {
      logger.error({ err }, "Error getting active txs");
    }
  }, getLoopInterval());
};

export const handleActiveTransactions = async (transactions: ActiveTransaction<any>[]) => {
  const method = "handleActiveTransactions";
  const methodId = getUuid();
  const { logger, txService, config } = getContext();
  const { prepare, cancel, fulfill } = getOperations();

  const handleSingle = async (transaction: ActiveTransaction<any>) => {
    if (transaction.status === CrosschainTransactionStatus.SenderPrepared) {
      const requestContext = createRequestContext("ContractReader => SenderPrepared");
      const _transaction = transaction as ActiveTransaction<"SenderPrepared">;
      const chainConfig = config.chainConfig[_transaction.crosschainTx.invariant.sendingChainId];
      if (!chainConfig) {
        // this should not happen, this should get checked before this point
        throw new ContractReaderNotAvailableForChain(_transaction.crosschainTx.invariant.sendingChainId, {});
      }
      const senderReceipt = await txService.getTransactionReceipt(
        _transaction.crosschainTx.invariant.sendingChainId,
        _transaction.payload.senderPreparedHash,
      );
      if (senderReceipt.confirmations < chainConfig.confirmations) {
        logger.info(
          {
            requestContext,
            method,
            methodId,
            txConfirmations: senderReceipt.confirmations,
            configuredConfirmations: chainConfig.confirmations,
            chainId: _transaction.crosschainTx.invariant.sendingChainId,
            txHash: _transaction.payload.senderPreparedHash,
          },
          "Waiting for safe confirmations",
        );
        return;
      }
      const preparePayload: PreparePayload = _transaction.payload;
      try {
        logger.info({ requestContext }, "Preparing receiver");
        const receipt = await prepare(
          _transaction.crosschainTx.invariant,
          {
            senderExpiry: _transaction.crosschainTx.sending.expiry,
            senderAmount: _transaction.crosschainTx.sending.amount,
            bidSignature: preparePayload.bidSignature,
            encodedBid: preparePayload.encodedBid,
            encryptedCallData: preparePayload.encryptedCallData,
          },
          requestContext,
        );
        logger.info({ requestContext, txHash: receipt?.transactionHash }, "Prepared receiver");
      } catch (err) {
        if (safeJsonStringify(jsonifyError(err)).includes("#P:015")) {
          logger.warn({ requestContext, err: err.message }, "Receiver transaction already prepared");
        } else {
          logger.error({ err: jsonifyError(err), requestContext }, "Error preparing receiver");
        }
        if (err.cancellable === true) {
          logger.error({ requestContext }, "Cancellable validation error, cancelling");
          try {
            const cancelRes = await cancel(
              transaction.crosschainTx.invariant,
              {
                amount: transaction.crosschainTx.sending.amount,
                expiry: transaction.crosschainTx.sending.expiry,
                preparedBlockNumber: transaction.crosschainTx.sending.preparedBlockNumber,
                side: "sender",
              },
              requestContext,
            );
            logger.info({ requestContext, txHash: cancelRes?.transactionHash }, "Cancelled transaction");
          } catch (err) {
            logger.error({ err: jsonifyError(err), requestContext }, "Error cancelling sender");
          }
        }
      }
    } else if (transaction.status === CrosschainTransactionStatus.ReceiverFulfilled) {
      const requestContext = createRequestContext("ContractReader => ReceiverFulfilled");
      const _transaction = transaction as ActiveTransaction<"ReceiverFulfilled">;
      const chainConfig = config.chainConfig[_transaction.crosschainTx.invariant.receivingChainId];
      if (!chainConfig) {
        // this should not happen, this should get checked before this point
        throw new ContractReaderNotAvailableForChain(_transaction.crosschainTx.invariant.sendingChainId, {});
      }
      const receiverReceipt = await txService.getTransactionReceipt(
        _transaction.crosschainTx.invariant.receivingChainId,
        _transaction.payload.receiverFulfilledHash,
      );
      if (receiverReceipt.confirmations < chainConfig.confirmations) {
        logger.info(
          {
            requestContext,
            method,
            methodId,
            chainId: _transaction.crosschainTx.invariant.receivingChainId,
            txHash: _transaction.payload.receiverFulfilledHash,
            txConfirmations: receiverReceipt.confirmations,
            configuredConfirmations: chainConfig.confirmations,
          },
          "Waiting for safe confirmations",
        );
        return;
      }

      const fulfillPayload: FulfillPayload = _transaction.payload;
      try {
        logger.info({ requestContext }, "Fulfilling sender");
        const receipt = await fulfill(
          _transaction.crosschainTx.invariant,
          {
            amount: _transaction.crosschainTx.sending.amount,
            expiry: _transaction.crosschainTx.sending.expiry,
            preparedBlockNumber: _transaction.crosschainTx.sending.preparedBlockNumber,
            signature: fulfillPayload.signature,
            callData: fulfillPayload.callData,
            relayerFee: fulfillPayload.relayerFee,
            side: "sender",
          },
          requestContext,
        );
        logger.info({ requestContext, txHash: receipt?.transactionHash }, "Fulfilled sender");
      } catch (err) {
        if (safeJsonStringify(jsonifyError(err)).includes("#F:019")) {
          logger.warn({ requestContext, err: err.message }, "Sender alredy fulfilled");
        } else {
          logger.error({ err: jsonifyError(err), requestContext }, "Error fulfilling sender");
        }
      }
    } else if (transaction.status === CrosschainTransactionStatus.ReceiverExpired) {
      const requestContext = createRequestContext("ContractReader => ReceiverExpired");
      try {
        logger.info(
          { requestContext, transactionId: transaction.crosschainTx.invariant.transactionId },
          "Cancelling expired receiver",
        );
        const receipt = await cancel(
          transaction.crosschainTx.invariant,
          {
            amount: transaction.crosschainTx.receiving!.amount,
            expiry: transaction.crosschainTx.receiving!.expiry,
            preparedBlockNumber: transaction.crosschainTx.receiving!.preparedBlockNumber,
            side: "receiver",
          },
          requestContext,
        );
        logger.info({ requestContext, txHash: receipt?.transactionHash }, "Cancelled receiver");
      } catch (err) {
        const json = jsonifyError(err);
        if (json?.context?.message.includes("#C:019")) {
          logger.warn(
            {
              requestContext,
              transaction: transaction.crosschainTx.invariant.transactionId,
            },
            "Already cancelled",
          );
          return;
        }
        logger.error({ err: json, requestContext }, "Error cancelling receiver");
      }
    } else if (transaction.status === CrosschainTransactionStatus.SenderExpired) {
      // if sender is expired, both sender and receiver are expired so cancel both
      const requestContext = createRequestContext("ContractReader => SenderExpired");
      try {
        logger.info(
          { requestContext, transactionId: transaction.crosschainTx.invariant.transactionId },
          "Cancelling expired sender",
        );
        const receipt = await cancel(
          transaction.crosschainTx.invariant,
          {
            amount: transaction.crosschainTx.sending.amount,
            expiry: transaction.crosschainTx.sending.expiry,
            preparedBlockNumber: transaction.crosschainTx.sending.preparedBlockNumber,
            side: "sender",
          },
          requestContext,
        );
        logger.info({ requestContext, txHash: receipt?.transactionHash }, "Cancelled sender");
      } catch (err) {
        const json = jsonifyError(err);
        if (json?.context?.message.includes("#C:019")) {
          logger.warn(
            {
              requestContext,
              transaction: transaction.crosschainTx.invariant.transactionId,
            },
            "Already cancelled",
          );
          return;
        }
        logger.error({ err: json, requestContext }, "Error cancelling sender");
      }

      // If sender is cancelled, receiver should already be expired. If we do
      // not cancel here that is *ok* because it would have been caught earlier
      // when we cancel the receiving chain side (via enforcement)
    } else if (transaction.status === CrosschainTransactionStatus.ReceiverCancelled) {
      // if receiver is cancelled, cancel the sender as well
      const requestContext = createRequestContext("ContractReader => ReceiverCancelled");
      try {
        logger.info(
          { requestContext, transactionId: transaction.crosschainTx.invariant.transactionId },
          "Cancelling sender after receiver cancelled",
        );
        const receipt = await cancel(
          transaction.crosschainTx.invariant,
          {
            amount: transaction.crosschainTx.sending.amount,
            expiry: transaction.crosschainTx.sending.expiry,
            preparedBlockNumber: transaction.crosschainTx.sending.preparedBlockNumber,
            side: "sender",
          },
          requestContext,
        );
        logger.info({ requestContext, txHash: receipt?.transactionHash }, "Cancelled sender");
      } catch (err) {
        const json = jsonifyError(err);
        if (json?.context?.message.includes("#C:019")) {
          logger.warn(
            {
              requestContext,
              transaction: transaction.crosschainTx.invariant.transactionId,
            },
            "Already cancelled",
          );
          return;
        }
        logger.error({ err: json, requestContext }, "Error cancelling sender");
      }
    } else if (transaction.status === CrosschainTransactionStatus.ReceiverNotConfigured) {
      // if receiver is cancelled, cancel the sender as well
      const requestContext = createRequestContext("ContractReader => ReceiverNotConfigured");
      try {
        logger.info(
          { requestContext, transactionId: transaction.crosschainTx.invariant.transactionId },
          "Cancelling sender because receiver is not configured",
        );
        const receipt = await cancel(
          transaction.crosschainTx.invariant,
          {
            amount: transaction.crosschainTx.sending.amount,
            expiry: transaction.crosschainTx.sending.expiry,
            preparedBlockNumber: transaction.crosschainTx.sending.preparedBlockNumber,
            side: "sender",
          },
          requestContext,
        );
        logger.info({ requestContext, txHash: receipt?.transactionHash }, "Cancelled sender");
      } catch (err) {
        logger.error({ err: jsonifyError(err), requestContext }, "Error cancelling sender");
      }
    }
  };
  for (const transaction of transactions) {
    handleSingle(transaction);
    await delay(750);
  }
};
