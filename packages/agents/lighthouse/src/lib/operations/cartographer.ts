import {
  createLoggingContext,
  ExecuteArgs,
  jsonifyError,
  NxtpError,
  formatUrl,
  convertFromDbTransfer,
  transfersCastForUrl,
} from "@connext/nxtp-utils";
import axios from "axios";
import { constants } from "ethers";

import { getOperations } from "../../lib/operations";
import { getContext } from "../../lighthouse";
import { ApiRequestFailed } from "../errors/cartographer";

export const pollCartographer = async () => {
  const { requestContext, methodContext } = createLoggingContext(pollCartographer.name);
  const { logger } = getContext();
  const { execute } = getOperations();

  logger.debug("Polling cartographer", requestContext, methodContext, {});
  const reconciledTransactions = await getReconciledTransactions();
  logger.debug("Get reconciled transactions", requestContext, methodContext, { reconciledTransactions });

  await Promise.all(
    reconciledTransactions.map(async (transaction: any) => {
      try {
        const xTransfer = convertFromDbTransfer(transaction);

        const executeParams: ExecuteArgs = {
          params: {
            originDomain: xTransfer.xparams?.originDomain ?? "",
            destinationDomain: xTransfer.xparams?.destinationDomain ?? "",
            to: xTransfer.xparams!.to,
            callData: xTransfer.xparams!.callData,
            callback: xTransfer.xparams!.callback,
            callbackFee: xTransfer.xparams!.callbackFee,
            receiveLocal: xTransfer.xparams!.receiveLocal,
            forceSlow: xTransfer.xparams!.forceSlow,
            recovery: xTransfer.xparams!.recovery,
            destinationMinOut: xTransfer.xparams!.destinationMinOut,
            agent: xTransfer.xparams!.agent,
            relayerFee: xTransfer.xparams!.relayerFee,
          },
          local: xTransfer.destination!.assets.local.asset,
          routers: [],
          routerSignatures: [],
          sequencer: constants.AddressZero,
          sequencerSignature: "",
          amount: xTransfer.destination!.assets.local.amount.toString(),
          nonce: xTransfer.nonce!,
          originSender: xTransfer.origin!.xcall.caller,
        };

        const transferId = xTransfer.transferId;

        await execute(executeParams, transferId);
      } catch (error: any) {
        logger.error("Error Cartographer Binding", requestContext, methodContext, jsonifyError(error as NxtpError), {
          transaction,
        });
      }
    }),
  );
};

export const getReconciledTransactions = async (): Promise<any> => {
  const { requestContext, methodContext } = createLoggingContext(getReconciledTransactions.name);
  const { logger, config } = getContext();

  const statusIdentifier = `status=eq.Reconciled&${transfersCastForUrl}`;
  const uri = formatUrl(config.cartographerUrl, "transfers?", statusIdentifier);
  logger.debug("Getting transactions from URI", requestContext, methodContext, { uri });
  try {
    const response = await axios.get(uri);
    return response.data;
  } catch (error: any) {
    throw new ApiRequestFailed({ uri, error: jsonifyError(error as NxtpError) });
  }
};
