import { constants } from "ethers";
import { RequestContext, createLoggingContext, Bid, connextRelayerSend, OriginTransfer } from "@connext/nxtp-utils";

import { getContext } from "../../sequencer";
import { getHelpers } from "../helpers";

export const sendToRelayer = async (
  round: number,
  bids: Bid[],
  transfer: OriginTransfer,
  local: string,
  _requestContext: RequestContext,
): Promise<string> => {
  const {
    logger,
    chainData,
    config,
    adapters: { chainreader, relayer },
  } = getContext();
  const {
    auctions: { encodeExecuteFromBids },
  } = getHelpers();

  const { requestContext, methodContext } = createLoggingContext(sendToRelayer.name, _requestContext);
  logger.debug(`Method start: ${sendToRelayer.name}`, requestContext, methodContext, { transfer });

  const originChainId = chainData.get(transfer.xparams.originDomain)!.chainId;
  const destinationChainId = chainData.get(transfer.xparams.destinationDomain)!.chainId;

  const destinationConnextAddress = config.chains[transfer.xparams.destinationDomain].deployments.connext;

  const encodedData = await encodeExecuteFromBids(round, bids, transfer, local);

  const relayerFee = {
    // TODO: Is this correct?
    amount: "0",
    // amount: transfer.relayerFee!,
    // TODO: should handle relayer fee paid in alternative assets once that is implemented.
    asset: constants.AddressZero,
  };

  // TODO: Might want to move this logic inside the `relayer.send` method below.
  // Try sending the tx to the custom configured relayer, if applicable.
  // If this fails, we'll resort to using the default relayer network.
  if (config.relayerUrl) {
    try {
      const result = await connextRelayerSend(config.relayerUrl, destinationChainId, {
        fee: {
          chain: originChainId,
          amount: relayerFee.amount,
          token: relayerFee.asset,
        },
        to: destinationConnextAddress,
        data: encodedData,
      });
      const { taskId } = result;
      logger.info("Sent meta transaction to Connext relayer", requestContext, methodContext, {
        taskId,
        transferId: transfer.transferId,
      });
      return taskId;
    } catch (error: unknown) {
      logger.warn("Failed to send meta transaction to Connext relayer", requestContext, methodContext, {
        transferId: transfer.transferId,
        error,
      });
    }
  }

  // Validate the bid's fulfill call will succeed on chain.
  const relayerAddress = await relayer.getRelayerAddress(destinationChainId);

  logger.debug("Getting gas estimate", requestContext, methodContext, {
    chainId: destinationChainId,
    to: destinationConnextAddress,
    data: encodedData,
    from: relayerAddress,
    transferId: transfer.transferId,
  });
  const gas = await chainreader.getGasEstimateWithRevertCode(Number(transfer.xparams.destinationDomain), {
    chainId: destinationChainId,
    to: destinationConnextAddress,
    data: encodedData,
    from: relayerAddress,
  });

  logger.info("Sending meta tx to relayer", requestContext, methodContext, {
    relayer: relayerAddress,
    connext: destinationConnextAddress,
    domain: transfer.xparams.destinationDomain,
    gas: gas.toString(),
    relayerFee,
    transferId: transfer.transferId,
  });

  const taskId = await relayer.send(destinationChainId, destinationConnextAddress, encodedData, _requestContext);
  return taskId;
};
