import { BigNumber, constants, Contract, providers, utils } from "ethers";
import { task } from "hardhat/config";
import { CallParams, XCallArgs } from "@connext/nxtp-utils";

import { Env, getDeploymentName, mustGetEnv } from "../src/utils";
import { canonizeId, getDomainInfoFromChainId } from "../src/nomad";

type TaskArgs = {
  transactingAssetId?: string;
  amount?: string;
  to?: string;
  destinationDomain?: string;
  callData?: string;
  connextAddress?: string;
  env?: Env;
  relayerFee?: string;
  callback?: string;
  callbackFee?: string;
  forceSlow?: string;
  receiveLocal?: string;
  recovery?: string;
  originMinOut?: string;
  destinationMinOut?: string;
  runs?: number;
  accounts?: number;
  showArgs?: string;
};

export default task("xcall", "Prepare a cross-chain tx")
  .addOptionalParam("transactingAssetId", "Transacting asset Id")
  .addOptionalParam("amount", "Amount to transfer")
  .addOptionalParam("to", "To address")
  .addOptionalParam("destinationDomain", "Destination domain")
  .addOptionalParam("callData", "Data for external call")
  .addOptionalParam("connextAddress", "Override connext address")
  .addOptionalParam("relayerFee", "Override relayer fee")
  .addOptionalParam("callback", "Override callback address")
  .addOptionalParam("callbackFee", "Override callback fee")
  .addOptionalParam("forceSlow", "Override for forcing slow path")
  .addOptionalParam("receiveLocal", "Override for receiving local")
  .addOptionalParam("recovery", "Override for recovery address")
  .addOptionalParam("originMinOut", "Override for origin domain tokens out (slippage tolerance)")
  .addOptionalParam("destinationMinOut", "Override for destination domain tokens out (slippage tolerance)")
  .addOptionalParam("env", "Environment of contracts")
  .addOptionalParam("runs", "Number of times to fire the xcall")
  .addOptionalParam("accounts", "Number of accounts to fire xcalls in parallel")
  .addOptionalParam("showArgs", "Verbose logs of xcall args")
  .setAction(
    async (
      {
        transactingAssetId: _transactingAssetId,
        amount: _amount,
        connextAddress: _connextAddress,
        to: _to,
        callData: _callData,
        destinationDomain: _destinationDomain,
        env: _env,
        relayerFee: _relayerFee,
        callback: _callback,
        callbackFee: _callbackFee,
        forceSlow: _forceSlow,
        receiveLocal: _receiveLocal,
        recovery: _recovery,
        originMinOut: _originMinOut,
        destinationMinOut: _destinationMinOut,
        runs: _runs,
        accounts: _accounts,
        showArgs: _showArgs,
      }: TaskArgs,
      hre,
    ) => {
      let tx: providers.TransactionResponse;

      const showArgs = _showArgs === "true" ? true : false;

      const env = mustGetEnv(_env);
      console.log("env:", env);

      const runs = _runs ?? 1;
      console.log("runs:", runs);

      const accounts = _accounts ?? 1;
      console.log("accounts:", accounts);

      const senders = await hre.ethers.getSigners();
      senders.splice(accounts);

      // Get the origin and destination domains.
      const network = await hre.ethers.provider.getNetwork();
      const originDomain = (await getDomainInfoFromChainId(network.chainId, hre)).domain;
      const destinationDomain = +(_destinationDomain ?? process.env.TRANSFER_DESTINATION_DOMAIN ?? "0");
      if (!destinationDomain) {
        throw new Error("Destination domain must be specified as params or from env (TRANSFER_DESTINATION_DOMAIN)");
      }

      // Get the "to" address (defaults to sender address)
      const to = _to ?? process.env.TRANSFER_TO ?? senders[0].address;

      // Get the call data, if applicable.
      const callData = _callData ?? process.env.TRANSFER_CALL_DATA ?? "0x";

      // Get the amount (defaults to 1 TEST)
      const amount = _amount ?? process.env.TRANSFER_AMOUNT ?? "1000000000000000000";

      // Get the relayer fee (defaults to 0)
      const relayerFee = _relayerFee ?? process.env.RELAYER_FEE ?? "0";

      // Get the transacting asset ID.
      let transactingAssetId = _transactingAssetId ?? process.env.TRANSFER_ASSET;
      if (!transactingAssetId) {
        // Alternatively, try defaulting to using the canonical token from the .env (if present) as the transacting asset ID,
        // deriving the local asset using the token registry if applicable.
        const canonicalDomain = process.env.CANONICAL_DOMAIN;
        const canonicalAsset = process.env.CANONICAL_TOKEN;
        if (!canonicalAsset || !canonicalDomain) {
          throw new Error("No canonical domain or token in env");
        }
        const canonicalTokenId = utils.hexlify(canonizeId(canonicalAsset));

        // Retrieve the local asset from the token registry, if applicable.
        if (+canonicalDomain === originDomain) {
          // Use the canonical asset as the local asset since we're on the canonical network.
          transactingAssetId = canonicalAsset;
        } else {
          // Current network's domain is not canonical domain, so we need to get the local asset representation.
          const tokenDeployment = await hre.deployments.get(getDeploymentName("TokenRegistryUpgradeBeaconProxy", env));
          const tokenRegistry = new Contract(
            tokenDeployment.address,
            (await hre.deployments.get(getDeploymentName("TokenRegistry"))).abi,
          );
          transactingAssetId = await tokenRegistry.getRepresentationAddress(canonicalDomain, canonicalTokenId);
          if (transactingAssetId === constants.AddressZero) {
            throw new Error("Empty transactingAssetId on registry");
          }
        }
      }
      if (!transactingAssetId) {
        // If the above attempt fails, then we default to telling the user to just specify the transacting asset ID.
        throw new Error("Transfer asset ID must be specified as param or from env (TRANSFER_ASSET)");
      }

      // Get the other params
      const callback = _callback ?? constants.AddressZero;
      const callbackFee = _callbackFee ?? "0";
      const forceSlow = _forceSlow === "true" ? true : false;
      const receiveLocal = _receiveLocal === "true" ? true : false;
      const recovery = _recovery ?? to;
      const destinationMinOut = _destinationMinOut ?? "0";
      const originMinOut = _originMinOut ?? "0";

      // Load contracts
      const connextName = getDeploymentName("ConnextHandler", env);
      const connextDeployment = await hre.deployments.get(connextName);
      const connextAddress = _connextAddress ?? connextDeployment.address;
      const connext = new Contract(connextAddress, connextDeployment.abi);
      console.log("connextAddress: ", connextAddress);

      const tokenRegistry = await connext.connect(senders[0]).tokenRegistry();
      if (tokenRegistry === constants.AddressZero) {
        throw new Error(`TokenRegistry not set on connext`);
      }
      console.log("tokenRegistry:", tokenRegistry);

      // Construct xcall args
      const params: CallParams = {
        to: to,
        callData,
        originDomain: `${originDomain}`,
        destinationDomain: `${destinationDomain}`,
        recovery,
        agent: constants.AddressZero,
        callback,
        callbackFee,
        relayerFee,
        forceSlow,
        receiveLocal,
        destinationMinOut,
      };

      const args: XCallArgs = {
        params,
        transactingAsset: transactingAssetId,
        transactingAmount: amount,
        originMinOut,
      };

      // Check balances and allowances
      for (let i = 0; i < senders.length; i++) {
        let balance: BigNumber;
        if (transactingAssetId === constants.AddressZero) {
          balance = await hre.ethers.provider.getBalance(senders[i].address);
        } else {
          const erc20 = await hre.ethers.getContractAt("IERC20", transactingAssetId, senders[i]);
          const allowance = await erc20.connect(senders[i]).allowance(senders[i].address, connextAddress);
          if (allowance.lt(BigNumber.from(amount).mul(runs))) {
            tx = await erc20.approve(connextAddress, constants.MaxUint256);
            await tx.wait();
          }
          balance = await erc20.balanceOf(senders[i].address);
        }
        const balanceNeeded = BigNumber.from(amount).mul(runs);
        if (balance.lt(balanceNeeded)) {
          throw new Error(
            `Account (${
              senders[i].address
            }) has balance (${balance.toString()}), which is less than total needed (${balanceNeeded})`,
          );
        }
      }

      // Run as many times as specified
      for (let i = 1; i <= runs; i++) {
        const receipts = Promise.all(
          senders.map(async (sender) => {
            args.params.to = sender.address;

            const tx = await connext
              .connect(sender)
              .functions.xcall(args, { from: sender.address, gasLimit: 2_000_000 });
            console.log(`Transaction from sender: ${sender.address}`);
            console.log("  Tx: ", tx.hash);

            if (showArgs) {
              console.log("  originDomain: ", originDomain);
              console.log("  destinationDomain: ", destinationDomain);
              console.log("  transactingAsset: ", transactingAssetId);
              console.log("  amount: ", amount);
              console.log("  callData: ", callData);
              console.log("  callback: ", callback);
              console.log("  callbackFee: ", callbackFee);
              console.log("  forceSlow: ", forceSlow);
              console.log("  receiveLocal: ", receiveLocal);
              console.log("  recovery: ", recovery);
              console.log("  originMinOut:", originMinOut);
              console.log("  destinationMinOut:", destinationMinOut);
              console.log("xcall args", JSON.stringify(args));
              const encoded = connext.interface.encodeFunctionData("xcall", [args]);
              console.log("encoded: ", encoded);
              console.log("to: ", connext.address);
            }

            return tx.wait();
          }),
        );
        await receipts;
        console.log(`--> Transactions mined for run #${i}`);
      }
    },
  );
