import { constants, providers, BigNumber } from "ethers";
import { Logger, createLoggingContext, ChainData, XCallArgs, CallParams } from "@connext/nxtp-utils";
import {
  getContractInterfaces,
  ConnextContractInterfaces,
  contractDeployments,
  ChainReader,
} from "@connext/nxtp-txservice";

import {
  getChainData,
  getChainIdFromDomain,
  getConversionRate,
  relayerBufferPercentage,
  getGelatoEstimatedFee,
  getHardcodedGasLimits,
  getDecimalsForAsset,
} from "./lib/helpers";
import { SignerAddressMissing, ChainDataUndefined } from "./lib/errors";
import { NxtpSdkConfig, getConfig } from "./config";

/**
 * @classdesc Lightweight class to facilitate interaction with the Connext contract on configured chains.
 */
export class NxtpSdkBase {
  public readonly config: NxtpSdkConfig;
  private readonly logger: Logger;
  private contracts: ConnextContractInterfaces; // Used to read and write to smart contracts.
  private chainReader: ChainReader;
  public readonly chainData: Map<string, ChainData>;

  constructor(config: NxtpSdkConfig, logger: Logger, chainData: Map<string, ChainData>) {
    this.config = config;
    this.logger = logger;
    this.chainData = chainData;
    this.contracts = getContractInterfaces();
    this.chainReader = new ChainReader(
      this.logger.child({ module: "ChainReader" }, this.config.logLevel),
      this.config.chains,
    );
  }

  static async create(
    _config: NxtpSdkConfig,
    _logger?: Logger,
    _chainData?: Map<string, ChainData>,
  ): Promise<NxtpSdkBase> {
    const chainData = _chainData ?? (await getChainData());
    if (!chainData) {
      throw new ChainDataUndefined();
    }

    const nxtpConfig = await getConfig(_config, contractDeployments, chainData);
    const logger = _logger
      ? _logger.child({ name: "NxtpSdkBase" })
      : new Logger({ name: "NxtpSdkBase", level: nxtpConfig.logLevel });

    return new NxtpSdkBase(nxtpConfig, logger, chainData);
  }

  async approveIfNeeded(
    domain: string,
    assetId: string,
    amount: string,
    infiniteApprove = true,
  ): Promise<providers.TransactionRequest | undefined> {
    const { requestContext, methodContext } = createLoggingContext(this.approveIfNeeded.name);

    const signerAddress = this.config.signerAddress;
    this.logger.info("Method start", requestContext, methodContext, {
      domain,
      assetId,
      amount,
      signerAddress,
    });

    if (!signerAddress) {
      throw new SignerAddressMissing();
    }

    let chainId = this.config.chains[domain].chainId;
    if (!chainId) {
      chainId = await getChainIdFromDomain(domain, this.chainData);
    }

    if (assetId !== constants.AddressZero) {
      const ConnextContractAddress = this.config.chains[domain].deployments!.connext;

      const approvedData = this.contracts.erc20.encodeFunctionData("allowance", [
        signerAddress,
        ConnextContractAddress,
      ]);
      this.logger.debug("Got approved data", requestContext, methodContext, { approvedData });
      const approvedEncoded = await this.chainReader.readTx({
        to: assetId,
        data: approvedData,
        chainId: Number(domain),
      });
      this.logger.debug("Got approved data", requestContext, methodContext, { approvedEncoded });
      const [approved] = this.contracts.erc20.decodeFunctionResult("allowance", approvedEncoded);
      this.logger.debug("Got approved data", requestContext, methodContext, { approved });

      this.logger.info("Got approved tokens", requestContext, methodContext, { approved: approved.toString() });
      if (BigNumber.from(approved).lt(amount)) {
        const data = this.contracts.erc20.encodeFunctionData("approve", [
          ConnextContractAddress,
          infiniteApprove ? constants.MaxUint256 : amount,
        ]);
        const txRequest = {
          to: assetId,
          data,
          from: signerAddress,
          value: 0,
          chainId,
        };
        this.logger.info("Approve transaction created", requestContext, methodContext, txRequest);
        return txRequest;
      } else {
        this.logger.info("Allowance sufficient", requestContext, methodContext, {
          approved: approved.toString(),
          amount,
        });
        return undefined;
      }
    }
    return undefined;
  }

  /**
   * Check, sanitize, and format the XCall and encode calldata. Returns an ethers TransactionRequest object, ready
   * to be sent to an RPC provider.
   *
   * @param args - XCall arguments. Some fields in args.params are optional and have default values provided.
   * @returns providers.TransactionRequest object.
   */
  public async xcall(
    // All XCallArgs must be defined except for params.
    args: Omit<XCallArgs, "params"> & {
      // In params, all fields are optional (because of Partial) except for the ones listed by string literals here:
      params: Omit<Partial<CallParams>, "to" | "originDomain" | "destinationDomain" | "agent" | "destinationMinOut"> &
        // This Pick is used to make these fields required to be defined. The rest are optional with default values.
        Pick<CallParams, "to" | "originDomain" | "destinationDomain" | "agent" | "destinationMinOut">;
    },
  ): Promise<providers.TransactionRequest> {
    const { requestContext, methodContext } = createLoggingContext(this.xcall.name);
    this.logger.info("Method start", requestContext, methodContext, { args });

    const signerAddress = this.config.signerAddress;
    if (!signerAddress) {
      throw new SignerAddressMissing();
    }

    const { params, transactingAmount, transactingAsset, originMinOut } = args;
    const { originDomain, destinationDomain, relayerFee: _relayerFee } = params;

    // Calculate estimate for relayer fee and include it in the call params.
    let relayerFee = _relayerFee;
    if (!_relayerFee || _relayerFee == "0") {
      relayerFee = (
        await this.estimateRelayerFee({
          originDomain: originDomain,
          destinationDomain: destinationDomain,
        })
      ).toString();
    }

    // Substitute default values as needed.
    const formattedXParams: CallParams = {
      ...params,
      callData: params.callData || "0x",
      callback: params.callback || constants.AddressZero,
      callbackFee: params.callbackFee || "0",
      recovery: params.recovery || params.to,
      forceSlow: params.forceSlow || false,
      receiveLocal: params.receiveLocal || false,
      relayerFee: relayerFee!,
      // agent: params.agent || constants.AddressZero,
    };

    // Validate XCall arguments.
    if (transactingAsset === constants.AddressZero) {
      // TODO: Custom error.
      throw new Error("Transacting asset specified was address zero; native assets are not supported!");
    }
    // TODO: Use ajv validator:
    // const validateInput = ajv.compile(XTransferSchema);
    // const validInput = validateInput(params);
    // if (!validInput) {
    //   const msg = validateInput.errors?.map((err: any) => `${err.instancePath} - ${err.message}`).join(",");
    //   throw new ParamsInvalid({
    //     paramsError: msg,
    //     params,
    //   });
    // }

    const ConnextContractAddress = this.config.chains[originDomain].deployments!.connext;

    // Get the current chain ID.
    let chainId = this.config.chains[originDomain].chainId;
    if (!chainId) {
      chainId = await getChainIdFromDomain(originDomain, this.chainData);
    }

    // Add callback and relayer fee together to get the total ETH value that should be sent.
    const value = BigNumber.from(formattedXParams.relayerFee).add(BigNumber.from(formattedXParams.callbackFee));

    // Take the finalized xcall arguments and encode calldata.
    const formattedXCallArgs: XCallArgs = {
      params: formattedXParams,
      transactingAsset,
      transactingAmount,
      originMinOut,
    };
    const data = this.contracts.connext.encodeFunctionData("xcall", [formattedXCallArgs]);

    // Make an ethers TransactionRequest object.
    const txRequest: providers.TransactionRequest = {
      to: ConnextContractAddress,
      value,
      data,
      from: signerAddress,
      chainId,
    };
    this.logger.info("XCall transaction formatted.", requestContext, methodContext, txRequest);

    return txRequest;
  }

  async bumpTransfer(params: {
    domain: string;
    transferId: string;
    relayerFee: string;
  }): Promise<providers.TransactionRequest> {
    const { requestContext, methodContext } = createLoggingContext(this.bumpTransfer.name);
    this.logger.info("Method start", requestContext, methodContext, { params });

    const signerAddress = this.config.signerAddress;
    if (!signerAddress) {
      throw new SignerAddressMissing();
    }

    const { domain, transferId, relayerFee } = params;

    let chainId = this.config.chains[domain].chainId;
    if (!chainId) {
      chainId = await getChainIdFromDomain(domain, this.chainData);
    }
    const ConnextContractAddress = this.config.chains[domain].deployments!.connext;

    // if transactingAsset is AddressZero then we are adding relayerFee to amount for value
    const value = BigNumber.from(relayerFee);

    const data = this.contracts.connext.encodeFunctionData("bumpTransfer", [transferId]);

    const txRequest = {
      to: ConnextContractAddress,
      value,
      data,
      from: signerAddress,
      chainId,
    };

    this.logger.info(`${this.bumpTransfer.name} transaction created`, requestContext, methodContext, txRequest);

    return txRequest;
  }

  async estimateRelayerFee(params: {
    originDomain: string;
    destinationDomain: string;
    originNativeToken?: string;
    destinationNativeToken?: string;
    callDataGasAmount?: number;
    isHighPriority?: boolean;
  }): Promise<BigNumber> {
    const { requestContext, methodContext } = createLoggingContext(this.estimateRelayerFee.name);
    this.logger.info("Method start", requestContext, methodContext, { params });

    const {
      originDomain,
      destinationDomain,
      callDataGasAmount,
      originNativeToken: _originNativeToken,
      destinationNativeToken: _destinationNativeToken,
      isHighPriority: _isHighPriority,
    } = params;

    const originNativeToken = _originNativeToken ?? constants.AddressZero;
    const destinationNativeToken = _destinationNativeToken ?? constants.AddressZero;
    const isHighPriority = _isHighPriority ?? false;

    const originChainId = await getChainIdFromDomain(originDomain, this.chainData);
    const destinationChainId = await getChainIdFromDomain(destinationDomain, this.chainData);

    // fetch executeGasAmount from chainData
    const {
      execute: executeGasAmount,
      executeL1: executeL1GasAmount,
      gasPriceFactor,
    } = await getHardcodedGasLimits(originChainId, this.chainData);
    this.logger.debug("Hardcoded gasLimits", requestContext, methodContext, {
      execute: executeGasAmount,
      executeL1: executeL1GasAmount,
      gasPriceFactor,
    });

    const totalGasAmount = callDataGasAmount
      ? Number(executeGasAmount) + Number(callDataGasAmount)
      : Number(executeGasAmount);
    const estimatedRelayerFee = await getGelatoEstimatedFee(
      destinationChainId,
      destinationNativeToken,
      Number(totalGasAmount),
      isHighPriority,
    );

    this.logger.info("Gas Price estimates", requestContext, methodContext, {
      originNativeToken,
      originChainId,
      destinationNativeToken,
      destinationChainId,
      executeGasAmount,
      callDataGasAmount,
    });

    // add relayerFee bump to estimatedRelayerFee
    const bumpedFee = estimatedRelayerFee.add(
      estimatedRelayerFee.mul(BigNumber.from(relayerBufferPercentage)).div(100),
    );

    // TODO: Convert the estimatedRelayerFee to the originNativeToken
    const [originTokenPrice, destinationTokenPrice, originTokenDecimals, destinationTokenDecimals] = await Promise.all([
      getConversionRate(originChainId, undefined, this.logger),
      getConversionRate(destinationChainId, undefined, this.logger),
      getDecimalsForAsset(originNativeToken, originChainId, undefined, this.chainData),
      getDecimalsForAsset(destinationNativeToken, destinationChainId, undefined, this.chainData),
    ]);

    if (originTokenPrice == 0 || destinationTokenPrice == 0) {
      return BigNumber.from(0);
    }

    // converstion rate is float-point number. we multiply by 1000 to be more precise
    const impactedOriginTokenPrice = Math.floor(originTokenPrice * 1000);
    const impactedDestinationTokenPrice = Math.floor(destinationTokenPrice * 1000);

    const relayerFeeInOrginNativeAsset =
      originTokenDecimals >= destinationTokenDecimals
        ? bumpedFee
            .mul(impactedDestinationTokenPrice)
            .div(impactedOriginTokenPrice)
            .mul(BigNumber.from(10).pow(originTokenDecimals - destinationTokenDecimals))
        : bumpedFee
            .mul(impactedDestinationTokenPrice)
            .div(impactedOriginTokenPrice)
            .div(BigNumber.from(10).pow(destinationTokenDecimals - originTokenDecimals));

    this.logger.info("Method end", requestContext, methodContext, {
      bumpedFee,
      originTokenPrice,
      destinationTokenPrice,
      relayerFeeInOrginNativeAsset,
    });

    return relayerFeeInOrginNativeAsset;
  }

  async changeSignerAddress(signerAddress: string) {
    this.config.signerAddress = signerAddress;
  }
}
