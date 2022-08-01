import { constants, BigNumber } from "ethers";
import {
  RequestContext,
  createLoggingContext,
  RelayerApiPostTaskRequestParams,
  ExecuteArgs,
  ajv,
  ExecuteArgsSchema,
} from "@connext/nxtp-utils";
import { getDeployedConnextContract } from "@connext/nxtp-txservice";

import { getContext } from "../../relayer";
import { ChainNotSupported, ContractDeploymentMissing, DecodeExecuteError, ParamsInvalid } from "../errors/tasks";

/**
 * Creates a task based on passed-in params (assuming task doesn't already exist), and returns the taskId.
 * @param chain
 * @param params
 * @param _requestContext
 * @returns
 */
export const createTask = async (
  chain: number,
  params: RelayerApiPostTaskRequestParams,
  _requestContext: RequestContext,
): Promise<string> => {
  const {
    logger,
    config,
    adapters: {
      cache,
      contracts: { connext },
    },
    chainToDomainMap,
  } = getContext();
  const { requestContext, methodContext } = createLoggingContext(createTask.name, _requestContext);

  const { to, data, fee } = params;

  // TODO: Allow alternative shitcoins.
  if (fee.token !== constants.AddressZero) {
    throw new Error("Only ETH is supported for now.");
  }

  let args: ExecuteArgs;
  let decoded: any;
  try {
    decoded = connext.decodeFunctionData("execute", data)[0];
    if (!decoded) {
      throw new Error("Decoded data is null");
    }
    args = {
      params: {
        originDomain: decoded.params.originDomain.toString(),
        destinationDomain: decoded.params.destinationDomain.toString(),
        to: decoded.params.to,
        callData: decoded.params.callData,
        callback: decoded.params.callback,
        callbackFee: decoded.params.callbackFee.toString(),
        forceSlow: decoded.params.forceSlow,
        receiveLocal: decoded.params.receiveLocal,
        recovery: decoded.params.recovery,
        agent: decoded.params.agent,
        relayerFee: decoded.params.relayerFee.toString(),
        destinationMinOut: decoded.params.destinationMinOut.toString(),
      },
      local: decoded.local,
      routers: decoded.routers,
      routerSignatures: decoded.routerSignatures,
      sequencer: decoded.sequencer,
      sequencerSignature: decoded.sequencerSignature,
      amount: decoded.amount.toString(),
      nonce: (decoded.nonce as BigNumber).toNumber(),
      originSender: decoded.originSender,
    };
    logger.debug("Parsed execute arguments", requestContext, methodContext, { args });
  } catch (error: unknown) {
    throw new DecodeExecuteError({
      decoded,
      error,
    });
  }

  // Validate execute arguments.
  const validateInput = ajv.compile(ExecuteArgsSchema);
  const validInput = validateInput(args);
  if (!validInput) {
    const msg = validateInput.errors?.map((err: any) => `${err.instancePath} - ${err.message}`).join(",");
    throw new ParamsInvalid({
      paramsError: msg,
      args,
    });
  }

  const connextAddress =
    config.chains[chain].deployments.connext ??
    getDeployedConnextContract(chain, config.environment === "staging" ? "Staging" : "")?.address;
  if (!connextAddress) {
    throw new ContractDeploymentMissing(ContractDeploymentMissing.contracts.connext, chain);
  } else if (to.toLowerCase() !== connextAddress.toLowerCase()) {
    throw new ParamsInvalid({
      paramsError: "to must be designated connext contract address",
      to,
      connextAddress,
    });
  }

  if (!chainToDomainMap.has(chain)) {
    throw new ChainNotSupported(chain);
  }

  // TODO: Sanity check: should have enough balance to pay for gas on the specified chain.

  const taskId: string = await cache.tasks.createTask({
    chain,
    to,
    data,
    fee,
  });
  logger.info("Created a new task.", requestContext, methodContext, { taskId });
  return taskId;
};
