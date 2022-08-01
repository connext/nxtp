import { providers, BigNumber, utils } from "ethers";
import { getChainData, Logger, createLoggingContext, ChainData } from "@connext/nxtp-utils";
import { getContractInterfaces, contractDeployments, ChainReader } from "@connext/nxtp-txservice";
import {
  ConnextHandler as TConnext,
  TokenRegistry as TTokenRegistry,
  IERC20Extended,
  canonizeId,
} from "@connext/nxtp-contracts";

import { NxtpSdkConfig, getConfig } from "./config";
import { SignerAddressMissing, ContractAddressMissing, ChainDataUndefined } from "./lib/errors";
import { IPoolStats, IPoolData } from "./interfaces";

export class Pool implements IPoolData {
  domainId: string;
  name: string;
  symbol: string; // in the form of <TKN>-mad<TKN>
  tokens: string[]; // [0] is adopted, [1] is representation
  decimals: number[];
  balances: BigNumber[];
  lpTokenAddress: string;
  address?: string; // no address if internal pool

  constructor(
    domainId: string,
    name: string,
    symbol: string,
    tokens: string[],
    decimals: number[],
    balances: BigNumber[],
    lpTokenAddress: string,
    address?: string,
  ) {
    this.domainId = domainId;
    this.name = name;
    this.symbol = symbol;
    this.tokens = tokens;
    this.decimals = decimals;
    this.balances = balances;
    this.lpTokenAddress = lpTokenAddress;
    this.address = address;
  }

  async getLiquidity(): Promise<string> {
    // TODO: get this from cartographer
    return "100";
  }

  async getVolume(): Promise<string> {
    // TODO: get this from cartographer
    return "100";
  }

  async getFees(): Promise<string> {
    // TODO: get this from cartographer
    return "100";
  }

  async getApy(): Promise<{ week: string; month: string; year: string; total: string }> {
    // TODO: get this from cartographer
    return {
      week: "100",
      month: "100",
      year: "100",
      total: "100",
    };
  }
}

/**
 * @classdesc Lightweight class to facilitate interaction with StableSwap Pools.
 * @dev This class will either interact with internal StableSwapFacet pools or external StableSwap pools
 *      depending on which type of pool is being used for each asset.
 *      Note: SDK currently only supports internal StableSwapFacet pools.
 *
 */
export class NxtpSdkPool {
  public readonly config: NxtpSdkConfig;
  public readonly chainData: Map<string, ChainData>;
  public readonly connext: TConnext["interface"];
  public readonly tokenRegistry: TTokenRegistry["interface"];
  public readonly erc20: IERC20Extended["interface"];

  private readonly logger: Logger;
  private readonly chainReader: ChainReader;

  // pools[domainId][canonicalId] -> Pool
  private pools = new Map<string, Map<string, Pool>>();

  constructor(config: NxtpSdkConfig, logger: Logger, chainData: Map<string, ChainData>, chainReader: ChainReader) {
    this.config = config;
    this.logger = logger;
    this.chainData = chainData;
    this.chainReader = chainReader;
    this.connext = getContractInterfaces().connext;
    this.tokenRegistry = getContractInterfaces().tokenRegistry;
    this.erc20 = getContractInterfaces().erc20Extended;
  }

  static async create(
    _config: NxtpSdkConfig,
    _logger?: Logger,
    _chainData?: Map<string, ChainData>,
    _chainReader?: ChainReader,
  ): Promise<NxtpSdkPool> {
    const chainData = _chainData ?? (await getChainData());
    if (!chainData) {
      throw new ChainDataUndefined();
    }

    const nxtpConfig = await getConfig(_config, contractDeployments, chainData);

    const logger = _logger
      ? _logger.child({ name: "NxtpSdkPool" })
      : new Logger({ name: "NxtpSdkPool", level: nxtpConfig.logLevel });

    const chainReader =
      _chainReader ?? new ChainReader(logger.child({ module: "ChainReader" }, nxtpConfig.logLevel), nxtpConfig.chains);

    return new NxtpSdkPool(nxtpConfig, logger, chainData, chainReader);
  }

  // ------------------- Read Operations ------------------- //

  async getCanonicalFromLocal(domainId: string, tokenAddress: string): Promise<[number, string]> {
    const tokenRegistryContractAddress = this.config.chains[domainId].deployments!.tokenRegistry;
    if (!tokenRegistryContractAddress) {
      throw new ContractAddressMissing();
    }

    const data = this.tokenRegistry.encodeFunctionData("getTokenId", [tokenAddress]);
    const encoded = await this.chainReader.readTx({
      chainId: Number(domainId),
      to: tokenRegistryContractAddress,
      data: data,
    });
    const [canonicalDomain, canonicalId] = this.tokenRegistry.decodeFunctionResult("getTokenId", encoded);

    return [canonicalDomain, canonicalId];
  }

  async getLPTokenAddress(domainId: string, canonicalId: string): Promise<string> {
    const connextContract = this.config.chains[domainId].deployments?.connext;
    if (!connextContract) {
      throw new ContractAddressMissing();
    }

    const data = this.connext.encodeFunctionData("getSwapLPToken", [canonicalId]);
    const encoded = await this.chainReader.readTx({
      chainId: Number(domainId),
      to: connextContract,
      data: data,
    });
    const [tokenAddress] = this.connext.decodeFunctionResult("getSwapLPToken", encoded);

    return tokenAddress;
  }

  async getLPTokenUserBalance(domainId: string, lpTokenAddress: string, userAddress: string): Promise<BigNumber> {
    const data = this.erc20.encodeFunctionData("balanceOf", [userAddress]);
    const encoded = await this.chainReader.readTx({
      chainId: Number(domainId),
      to: lpTokenAddress,
      data: data,
    });
    const [balance] = this.erc20.decodeFunctionResult("balanceOf", encoded);

    return balance;
  }

  async getPoolTokenIndex(domainId: string, canonicalId: string, tokenAddress: string): Promise<number> {
    const connextContract = this.config.chains[domainId].deployments!.connext;
    if (!connextContract) {
      throw new ContractAddressMissing();
    }

    const data = this.connext.encodeFunctionData("getSwapTokenIndex", [canonicalId, tokenAddress]);
    const encoded = await this.chainReader.readTx({
      chainId: Number(domainId),
      to: connextContract,
      data: data,
    });
    const [index] = this.connext.decodeFunctionResult("getSwapTokenIndex", encoded);

    return index;
  }

  async getPoolTokenBalance(domainId: string, canonicalId: string, tokenAddress: string): Promise<BigNumber> {
    const connextContract = this.config.chains[domainId].deployments?.connext;
    if (!connextContract) {
      throw new ContractAddressMissing();
    }

    const index = await this.getPoolTokenIndex(domainId, canonicalId, tokenAddress);

    const data = this.connext.encodeFunctionData("getSwapTokenBalance", [canonicalId, index]);
    const encoded = await this.chainReader.readTx({
      chainId: Number(domainId),
      to: connextContract,
      data: data,
    });
    const [balance] = this.connext.decodeFunctionResult("getSwapTokenBalance", encoded);

    return balance;
  }

  async getPoolTokenUserBalance(domainId: string, tokenAddress: string, userAddress: string): Promise<BigNumber> {
    const data = this.erc20.encodeFunctionData("balanceOf", [userAddress]);
    const encoded = await this.chainReader.readTx({
      chainId: Number(domainId),
      to: tokenAddress,
      data: data,
    });
    const [balance] = this.erc20.decodeFunctionResult("balanceOf", encoded);

    return balance;
  }

  async getPoolTokenAddress(domainId: string, canonicalId: string, index: number) {
    const connextContract = this.config.chains[domainId].deployments?.connext;
    if (!connextContract) {
      throw new ContractAddressMissing();
    }

    const data = this.connext.encodeFunctionData("getSwapToken", [canonicalId, index]);
    const encoded = await this.chainReader.readTx({
      chainId: Number(domainId),
      to: connextContract,
      data: data,
    });
    const [tokenAddress] = this.connext.decodeFunctionResult("getSwapToken", encoded);

    return tokenAddress;
  }

  async getVirtualPrice(domainId: string, canonicalId: string): Promise<BigNumber> {
    const connextContract = this.config.chains[domainId].deployments!.connext;
    if (!connextContract) {
      throw new ContractAddressMissing();
    }

    const data = this.connext.encodeFunctionData("getSwapVirtualPrice", [canonicalId]);
    const encoded = await this.chainReader.readTx({
      chainId: Number(domainId),
      to: connextContract,
      data: data,
    });
    const [price] = this.connext.decodeFunctionResult("getSwapVirtualPrice", encoded);

    return price;
  }

  async calculateSwap(
    domainId: string,
    canonicalId: string,
    tokenIndexFrom: number,
    tokenIndexTo: number,
    amount: string,
  ): Promise<number> {
    const connextContract = this.config.chains[domainId].deployments!.connext;
    if (!connextContract) {
      throw new ContractAddressMissing();
    }

    const encoded = this.connext.encodeFunctionData("calculateSwap", [
      canonicalId,
      tokenIndexFrom,
      tokenIndexTo,
      amount,
    ]);
    const result = await this.chainReader.readTx({
      chainId: Number(domainId),
      to: connextContract,
      data: encoded,
    });
    const [minAmount] = this.connext.decodeFunctionResult("calculateSwap", result);

    return minAmount;
  }

  async calculateTokenAmount(
    domainId: string,
    canonicalId: string,
    amounts: string[],
    isDeposit = true,
  ): Promise<BigNumber> {
    const connextContract = this.config.chains[domainId]?.deployments?.connext;
    if (!connextContract) {
      throw new ContractAddressMissing();
    }

    const data = this.connext.encodeFunctionData("calculateSwapTokenAmount", [canonicalId, amounts, isDeposit]);
    const encoded = await this.chainReader.readTx({
      to: connextContract,
      data: data,
      chainId: Number(domainId),
    });
    const [amount] = this.connext.decodeFunctionResult("calculateSwapTokenAmount", encoded);

    return amount;
  }

  async calculateRemoveSwapLiquidity(domainId: string, canonicalId: string, amount: string): Promise<BigNumber[]> {
    const connextContract = this.config.chains[domainId]?.deployments?.connext;
    if (!connextContract) {
      throw new ContractAddressMissing();
    }

    const data = this.connext.encodeFunctionData("calculateRemoveSwapLiquidity", [canonicalId, amount]);
    const encoded = await this.chainReader.readTx({
      to: connextContract,
      data: data,
      chainId: Number(domainId),
    });
    const [amounts] = this.connext.decodeFunctionResult("calculateRemoveSwapLiquidity", encoded);

    return amounts;
  }

  // ------------------- Pool Operations ------------------- //

  /**
   * Returns the transaction request for adding liquidity to a pool.
   * @param domainId The domain id of the pool.
   * @param canonicalId The canonical ID of the asset to swap.
   * @param amounts The amounts of the tokens to swap.
   * @param minToMint The minimum acceptable amount of LP tokens to mint.
   * @param deadline The deadline for the swap.
   * @param estimateGas Whether to estimate the gas needed for the transaction.
   */
  async addLiquidity(
    domainId: string,
    canonicalId: string,
    amounts: string[], // [0] for adopted asset, [1] for local asset
    minToMint = "0",
    deadline?: number,
    estimateGas = false,
  ): Promise<providers.TransactionRequest> {
    // TODO: handle estimateGas=true

    // TODO: find the right value for this
    if (!deadline) {
      const now = new Date();
      deadline = now.setHours(now.getHours() + 1);
    }

    const { requestContext, methodContext } = createLoggingContext(this.addLiquidity.name);
    this.logger.info("Method start", requestContext, methodContext, { domainId, amounts, deadline, estimateGas });

    const signerAddress = this.config.signerAddress;
    if (!signerAddress) {
      throw new SignerAddressMissing();
    }

    const connextContract = this.config.chains[domainId]?.deployments?.connext;
    if (!connextContract) {
      throw new ContractAddressMissing();
    }

    const data = this.connext.encodeFunctionData("addSwapLiquidity", [canonicalId, amounts, minToMint, deadline]);
    const txRequest = {
      to: connextContract,
      value: 0,
      data,
      from: signerAddress,
    };
    this.logger.info(`${this.addLiquidity.name} transaction created `, requestContext, methodContext);

    return txRequest;
  }

  /**
   * Returns the transaction request for removing liquidity from a pool.
   * @param domainId The domain id of the pool.
   * @param canonicalId The canonical ID of the asset to swap.
   * @param amount The amount of the token to swap.
   * @param minAmounts The minimum acceptable amounts of each token to burn.
   * @param deadline The deadline for the swap.
   * @param estimateGas Whether to estimate the gas needed for the transaction.
   */
  async removeLiquidity(
    domainId: string,
    canonicalId: string,
    amount: string,
    minAmounts = ["0", "0"],
    deadline?: number,
    estimateGas = false,
  ): Promise<providers.TransactionRequest> {
    // TODO: handle estimateGas=true

    // TODO: find the right value for this
    if (!deadline) {
      const now = new Date();
      deadline = now.setHours(now.getHours() + 1);
    }

    const { requestContext, methodContext } = createLoggingContext(this.removeLiquidity.name);
    this.logger.info("Method start", requestContext, methodContext, { domainId, amount, deadline, estimateGas });

    const signerAddress = this.config.signerAddress;
    if (!signerAddress) {
      throw new SignerAddressMissing();
    }

    const connextContract = this.config.chains[domainId]?.deployments?.connext;
    if (!connextContract) {
      throw new ContractAddressMissing();
    }

    const data = this.connext.encodeFunctionData("removeSwapLiquidity", [canonicalId, amount, minAmounts, deadline]);
    const txRequest = {
      to: connextContract,
      value: 0,
      data,
      from: signerAddress,
    };
    this.logger.info(`${this.addLiquidity.name} transaction created `, requestContext, methodContext);

    return txRequest;
  }

  /**
   * Returns the transaction request for performing a swap in a pool.
   * @param domainId The domain id of the pool.
   * @param canonicalId The canonical ID of the asset to swap.
   * @param from The address of the token to sell.
   * @param to The address of the token to buy.
   * @param amount The amount of the selling token to swap.
   * @param minDy The minimum amount of the buying token to receive.
   * @param deadline The deadline for the swap.
   * @param estimateGas Whether to estimate the gas needed for the transaction.
   */
  async swap(
    domainId: string,
    canonicalId: string,
    from: string,
    to: string,
    amount: string,
    minDy = 0,
    deadline?: number,
    estimateGas = false,
  ): Promise<providers.TransactionRequest> {
    // TODO: handle estimateGas=true

    // TODO: find the right value for this
    if (!deadline) {
      const now = new Date();
      deadline = now.setHours(now.getHours() + 1);
    }

    const signerAddress = this.config.signerAddress;
    if (!signerAddress) {
      throw new SignerAddressMissing();
    }

    const connextContract = this.config.chains[domainId].deployments?.connext;
    if (!connextContract) {
      throw new ContractAddressMissing();
    }

    const { requestContext, methodContext } = createLoggingContext(this.swap.name);
    this.logger.info("Method start", requestContext, methodContext, {
      domainId,
      canonicalId,
      from,
      to,
      amount,
      deadline,
      estimateGas,
    });

    const tokenIndexFrom = await this.getPoolTokenIndex(domainId, canonicalId, from);
    const tokenIndexTo = await this.getPoolTokenIndex(domainId, canonicalId, to);

    const data = this.connext.encodeFunctionData("swap", [
      canonicalId,
      tokenIndexFrom,
      tokenIndexTo,
      amount,
      minDy,
      deadline,
    ]);
    const txRequest = {
      to: connextContract,
      value: 0,
      data,
      from: signerAddress,
    };
    this.logger.info(`${this.swap.name} transaction created `, requestContext, methodContext);

    return txRequest;
  }

  // ------------------- Pool Data ------------------- //

  /**
   * Returns the Pools for a given local asset.
   * @param domainId The domain id of the pool.
   * @param tokenAddress The address of the local token to get the pool for.
   */
  async getPool(domainId: string, tokenAddress: string): Promise<Pool | undefined> {
    const [canonicalDomain, canonicalId] = await this.getCanonicalFromLocal(domainId, tokenAddress);
    const pool = this.pools.get(domainId)?.get(canonicalId);
    if (pool) {
      return pool;
    }

    const connextContract = this.config.chains[domainId]?.deployments?.connext;
    if (!connextContract) {
      throw new ContractAddressMissing();
    }
    const tokenRegistryContract = this.config.chains[domainId].deployments?.tokenRegistry;
    if (!tokenRegistryContract) {
      throw new ContractAddressMissing();
    }

    // If the canonical domain is the same as the local domain, then there is no pool
    if (canonicalDomain !== Number(domainId)) {
      const key = this.calculateCanonicalHash(canonicalDomain, canonicalId);
      let encoded = this.connext.encodeFunctionData("canonicalToAdopted(bytes32)", [key]);
      let result = await this.chainReader.readTx({
        chainId: Number(domainId),
        to: connextContract,
        data: encoded,
      });
      const adopted = this.connext.decodeFunctionResult("canonicalToAdopted(bytes32)", result)[0] as string;

      // If the adopted token is the same as the local token, then there is no pool
      if (adopted != tokenAddress) {
        encoded = this.connext.encodeFunctionData("getSwapLPToken", [canonicalId]);
        result = await this.chainReader.readTx({
          chainId: Number(domainId),
          to: connextContract,
          data: encoded,
        });
        const lpTokenAddress = this.connext.decodeFunctionResult("getSwapLPToken", result)[0] as string;

        encoded = this.erc20.encodeFunctionData("decimals");
        result = await this.chainReader.readTx({
          chainId: Number(domainId),
          to: tokenAddress,
          data: encoded,
        });
        const localDecimals = this.erc20.decodeFunctionResult("decimals", result)[0] as number;

        result = await this.chainReader.readTx({
          chainId: Number(domainId),
          to: adopted,
          data: encoded,
        });
        const adoptedDecimals = this.erc20.decodeFunctionResult("decimals", result)[0] as number;

        encoded = this.erc20.encodeFunctionData("symbol");
        result = await this.chainReader.readTx({
          chainId: Number(domainId),
          to: adopted,
          data: encoded,
        });
        const tokenSymbol = this.erc20.decodeFunctionResult("symbol", result)[0] as string;

        const adoptedBalance = await this.getPoolTokenBalance(domainId, canonicalId, adopted);
        const localBalance = await this.getPoolTokenBalance(domainId, canonicalId, tokenAddress);

        const pool = new Pool(
          domainId,
          `${tokenSymbol}-Pool`,
          `${tokenSymbol}-mad${tokenSymbol}`,
          [adopted, tokenAddress],
          [adoptedDecimals, localDecimals],
          [adoptedBalance, localBalance],
          lpTokenAddress,
        );

        return pool;
      }
    }

    return;
  }

  /**
   * Returns the Pools that a user has LP tokens for.
   * @param domainId The domain id of the pool.
   * @param userAddress The address of the user to get the pools for.
   */
  async getUserPools(
    domainId: string,
    userAddress: string,
  ): Promise<{ info: Pool; lpTokenBalance: BigNumber; poolTokenBalances: BigNumber[] }[]> {
    const result: { info: Pool; lpTokenBalance: BigNumber; poolTokenBalances: BigNumber[] }[] = [];

    await Promise.all(
      Object.values(this.config.chains[domainId].assets).map(async (asset) => {
        const pool = await this.getPool(domainId, asset.address);

        if (pool) {
          const lpTokenUserBalance = await this.getLPTokenUserBalance(domainId, pool.lpTokenAddress, userAddress);
          const adoptedTokenUserBalance = await this.getPoolTokenUserBalance(domainId, pool.tokens[0], userAddress);
          const localTokenUserBalance = await this.getPoolTokenUserBalance(domainId, pool.tokens[1], userAddress);
          result.push({
            info: pool,
            lpTokenBalance: lpTokenUserBalance,
            poolTokenBalances: [adoptedTokenUserBalance, localTokenUserBalance],
          });
        }
      }),
    );

    return result;
  }

  async getPoolStats(domainId: string, tokenAddress: string): Promise<IPoolStats> {
    const pool = await this.getPool(domainId, tokenAddress);

    const stats: IPoolStats = {
      liquidity: await pool!.getLiquidity(),
      volume: await pool!.getVolume(),
      fees: await pool!.getFees(),
      apy: await pool!.getApy(),
    };

    return stats;
  }

  private calculateCanonicalHash(canonicalDomain: number, _canonicalId: string): string {
    const canonicalId = utils.hexlify(canonizeId(_canonicalId));
    const payload = utils.defaultAbiCoder.encode(
      ["tuple(bytes32 canonicalId,uint32 canonicalDomain)"],
      [{ canonicalId, canonicalDomain }],
    );
    return utils.solidityKeccak256(["bytes32"], [payload]);
  }
}
