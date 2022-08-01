import axios, { AxiosResponse } from "axios";
import { Wallet, utils, BigNumber, providers, constants } from "ethers";
import { makePublisher, makeSubscriber } from "@connext/nxtp-sequencer/src/sequencer";
import { makeRouter } from "@connext/nxtp-router/src/router";
import { makeRelayer } from "@connext/nxtp-relayer/src/relayer";
import { makeRoutersPoller } from "@connext/cartographer-poller/src/routersPoller";
import { makeTransfersPoller } from "@connext/cartographer-poller/src/transfersPoller";
import { SequencerConfig } from "@connext/nxtp-sequencer/src/lib/entities/config";
import { NxtpRouterConfig as RouterConfig } from "@connext/nxtp-router/src/config";
import { RelayerConfig } from "@connext/nxtp-relayer/src/lib/entities/config";
import { CartographerConfig } from "@connext/cartographer-poller/src/config";
import {
  AuctionsApiErrorResponse,
  AuctionsApiGetAuctionStatusResponse,
  delay,
  OriginTransfer,
  DestinationTransfer,
  ERC20Abi,
  getGelatoRelayerAddress,
  Logger,
  XCallArgs,
  ChainData,
} from "@connext/nxtp-utils";
import { ChainReader, getConnextInterface } from "@connext/nxtp-txservice";
import { SubgraphReader } from "@connext/nxtp-adapters-subgraph";

import {
  DomainInfo,
  TestAgents,
  DOMAINS,
  ROUTER_CONFIG,
  SEQUENCER_CONFIG,
  MIN_USER_ETH,
  TRANSFER_TOKEN_AMOUNT,
  MIN_FUNDER_ETH,
  EXECUTE_TIMEOUT,
  SUBG_POLL_PARITY,
  XCALL_TIMEOUT,
  ROUTER_DESIRED_LIQUIDITY,
  DEBUG_XCALL_TXHASH,
  SKIP_SEQUENCER_CHECKS,
  RELAYER_CONFIG,
  LOCAL_RELAYER_ENABLED,
  CHAIN_DATA,
  LOCAL_CARTOGRAPHER_ENABLED,
  CARTOGRAPHER_CONFIG,
  ENVIRONMENT,
} from "./constants/testnet";
import {
  checkOnchainLocalAsset,
  convertToCanonicalAsset,
  formatEtherscanLink,
  getAllowance,
  getAssetApproval,
  getRouterApproval,
  OperationContext,
  removeAsset,
  setupAsset,
  log,
} from "./helpers/testnet";
import { pollSomething } from "./helpers/shared";

const ROUTER_MNEMONIC = process.env.ROUTER_MNEMONIC;
const RELAYER_MNEMONIC = process.env.RELAYER_MNEMONIC;
const DEPLOYER_MNEMONIC = process.env.DEPLOYER_MNEMONIC;
const USER_MNEMONIC = process.env.USER_MNEMONIC || Wallet.createRandom()._mnemonic().phrase;

/**
 * NOTE: The router used in this integration test will not necessarily be the router that executes
 * the transfer. However, both router and sequencer are configured to 'outrace' the network under
 * typical operating conditions and configuration.
 *
 * The auction period, for instance, is set to be only 1 second.
 *
 * Because of this, we can't expect the transfer to be executed by the router, but we can get a
 * glimpse of how both are functioning/reacting to the xcall on-chain.
 */
describe("TESTNET:E2E", () => {
  // Configuration.
  let chainData: Map<string, ChainData>;
  let domainInfo: { ORIGIN: DomainInfo; DESTINATION: DomainInfo };
  let routerConfig: RouterConfig;
  let sequencerConfig: SequencerConfig;
  let relayerConfig: RelayerConfig;
  let cartographerConfig: CartographerConfig;

  // Services.
  let chainreader: ChainReader;
  let subgraph: SubgraphReader;

  // Agents.
  let agents: TestAgents;

  // Contexts.
  let context: OperationContext;

  before(async () => {
    chainData = await CHAIN_DATA;
    domainInfo = await DOMAINS;
    routerConfig = await ROUTER_CONFIG;
    sequencerConfig = await SEQUENCER_CONFIG;
    relayerConfig = await RELAYER_CONFIG;
    cartographerConfig = await CARTOGRAPHER_CONFIG;

    // Init agents.
    const router = ROUTER_MNEMONIC ? Wallet.fromMnemonic(ROUTER_MNEMONIC) : undefined;
    // As a backup, the relayer can use the router wallet as well.
    const relayer = RELAYER_MNEMONIC ? Wallet.fromMnemonic(RELAYER_MNEMONIC) : router;
    const deployer = ROUTER_MNEMONIC && DEPLOYER_MNEMONIC ? Wallet.fromMnemonic(DEPLOYER_MNEMONIC) : undefined;
    const user = Wallet.fromMnemonic(USER_MNEMONIC);
    const originProvider = new providers.JsonRpcProvider(domainInfo.ORIGIN.config.providers[0]);
    const destinationProvider = new providers.JsonRpcProvider(domainInfo.DESTINATION.config.providers[0]);
    agents = {
      router: router
        ? {
            address: router.address.toLowerCase(),
            origin: router.connect(originProvider),
            destination: router.connect(destinationProvider),
          }
        : undefined,
      relayer:
        relayer && LOCAL_RELAYER_ENABLED
          ? {
              address: relayer.address.toLowerCase(),
              origin: relayer.connect(originProvider),
              destination: relayer.connect(destinationProvider),
            }
          : undefined,
      deployer: deployer
        ? {
            address: deployer.address.toLowerCase(),
            origin: deployer.connect(originProvider),
            destination: deployer.connect(destinationProvider),
          }
        : undefined,
      user: {
        address: user.address.toLowerCase(),
        origin: user.connect(originProvider),
        destination: user.connect(destinationProvider),
      },
    };

    // Init services.
    chainreader = new ChainReader(
      new Logger({
        level: "silent",
        name: "IntegrationChainReader",
      }),
      {
        [domainInfo.ORIGIN.chain]: domainInfo.ORIGIN.config,
        [domainInfo.DESTINATION.chain]: domainInfo.DESTINATION.config,
      },
    );

    subgraph = await SubgraphReader.create(chainData, ENVIRONMENT, process.env.SUBGRAPH_PREFIX);

    // Setup contexts (used for injection into helpers).
    context = {
      chainreader,
      domainInfo,
      agents,
    };
  });

  const test = async () => {
    const connext = getConnextInterface();
    const testERC20 = new utils.Interface(ERC20Abi);
    const originConnextAddress = domainInfo.ORIGIN.config.deployments.connext;
    const destinationConnextAddress = domainInfo.DESTINATION.config.deployments.connext;
    const relayerAddress: string = agents.relayer
      ? agents.relayer.address
      : await getGelatoRelayerAddress(domainInfo.DESTINATION.chain);
    const originAsset = domainInfo.ORIGIN.config.assets[0];
    const destinationAsset = domainInfo.DESTINATION.config.assets[0];

    /// MARK - Log setup.
    log.params(
      "\n" +
        (agents.router ? "LOCAL TEST" : "LIVE TEST") +
        `\nENVIRONMENT: ${JSON.stringify(ENVIRONMENT)}` +
        `\nTRANSFER:\n\tRoute:    \t${domainInfo.ORIGIN.name} (${domainInfo.ORIGIN.domain}) => ` +
        `${domainInfo.DESTINATION.name} (${domainInfo.DESTINATION.domain})` +
        `\n\tAmount:    \t${utils.formatEther(TRANSFER_TOKEN_AMOUNT)} TEST` +
        `\nAGENTS\n\tDeployer:   \t${agents.deployer?.address ?? "N/A"}\n\tRouter:   \t${
          agents.router?.address ?? "N/A"
        }\n\tRelayer:   \t${relayerAddress}\n\tUser:    \t${agents.user.address}` +
        `\nCONNEXT\n\tOrigin:   \t${originConnextAddress}\n\tEtherscan:   \t${formatEtherscanLink({
          network: domainInfo.ORIGIN.network,
          address: originConnextAddress,
        })}\n\tDestination:\t${destinationConnextAddress}\n\tEtherscan:   \t${formatEtherscanLink({
          network: domainInfo.DESTINATION.network,
          address: destinationConnextAddress,
        })}` +
        `\nASSETS\n\tOrigin:   \t${originAsset.address}\n\tDestination:\t${destinationAsset.address}`,
    );

    /// MARK - Validate setup.
    {
      if (agents.router) {
        log.next("VERIFY ROUTER APPROVAL");
        // Make sure router's signer address is approved on origin and destination chain.
        for (const { domain, deployer } of [
          // { domain: domainInfo.ORIGIN, deployer: agents.deployer?.origin },
          { domain: domainInfo.DESTINATION, deployer: agents.deployer?.destination },
        ]) {
          let isApproved = await getRouterApproval(context, {
            domain,
          });
          if (!isApproved) {
            if (deployer) {
              log.info("Router is not approved. Using deployer to approve.");
              // Router is not approved. Use deployer to approve router.
              const encoded = connext.encodeFunctionData("setupRouter", [
                agents.router.address,
                agents.router.address,
                agents.router.address,
              ]);
              const tx = await deployer.sendTransaction({
                to: domain.config.deployments.connext,
                data: encoded,
              });
              await tx.wait(1);

              isApproved = await getRouterApproval(context, {
                domain,
              });

              if (!isApproved) {
                log.fail("Router approval attempt failed.", { domain, hash: tx.hash });
              }

              log.info("Successfully approved router.");
            } else {
              log.fail("Router needs approval. Specify the DEPLOYER_MNEMONIC in env to have this done automatically.", {
                domain: domainInfo.ORIGIN,
              });
            }
          }
          log.info("Router is approved!", { domain });
        }
      }

      log.next("VERIFY ASSET APPROVAL");
      // Make sure the assets on origin and destination are approved.
      {
        for (const { domain, deployer } of [
          { domain: domainInfo.ORIGIN, deployer: agents.deployer?.origin },
          { domain: domainInfo.DESTINATION, deployer: agents.deployer?.destination },
        ]) {
          const localAsset = domain.config.assets[0].address.toLowerCase();
          // Convert the local asset into the canonical asset using information from the chain.
          const { canonicalId, canonicalDomain } = await convertToCanonicalAsset(context, {
            adopted: localAsset,
            domain,
          });
          log.info("Retrieved canonical asset info from onchain.", {
            domain,
            etc: { canonicalId, canonicalDomain },
          });

          if (
            canonicalId === constants.AddressZero ||
            !(await getAssetApproval(context, {
              domain,
              canonicalId,
              canonicalDomain,
            }))
          ) {
            if (!deployer) {
              log.fail("Asset needs approval on this domain.", { domain });
            }
            const hash = await setupAsset(context, {
              deployer,
              domain,
              canonical: canonicalId,
              local: localAsset,
            });
            log.info("Added asset to chain.", { domain, hash });
          } else {
            // Check to make sure canonical -> local is correct onchain.
            const {
              adoptedToCanonical,
              canonicalToAdopted,
              canonicalId,
              canonicalDomain,
              canonicalKey,
              getTokenId,
              tokenRegistry,
            } = await checkOnchainLocalAsset(context, {
              domain,
              adopted: localAsset,
            });
            if (canonicalToAdopted !== localAsset || adoptedToCanonical !== canonicalId) {
              // TODO: Change this to log.info, actually carry out the on-chain replacement below.
              // (Need to confirm that this works.)
              log.fail("Asset needs to be overwritten! Wrong local asset set on this domain.", {
                domain,
                etc: {
                  local: localAsset,
                  adoptedToCanonical,
                  canonicalToAdopted,
                  canonicalId,
                  canonicalDomain,
                  canonicalKey,
                  getTokenId,
                },
              });
              if (!deployer) {
                log.info("No deployer available to overwrite incorrect asset.", { domain });
              }
              // Overwrite the local asset set on chain with the correct one.
              {
                const hash = await removeAsset(context, {
                  deployer,
                  domain,
                  canonicalId,
                  canonicalDomain,
                  local: localAsset,
                });
                log.info("Removed asset.", { domain, hash });
              }
              {
                const hash = await setupAsset(context, {
                  deployer,
                  domain,
                  canonical: canonicalId,
                  local: localAsset,
                });
                log.info("Replaced asset.", { domain, hash });
              }
            } else {
              log.info("Transfer asset is approved.", {
                domain,
                etc: {
                  local: localAsset,
                  adoptedToCanonical,
                  canonicalToAdopted,
                  canonicalId,
                  canonicalDomain,
                  canonicalKey,
                  getTokenId,
                  tokenRegistry,
                },
              });
            }
          }
        }
      }

      log.next("FUND USER AGENT");
      // Fund user with ETH and TEST on origin. Router signer will be funder for ETH.
      {
        // TODO: Make a separate "funder" agent role that gets delegated to deployer if not defined, and
        // then router if no deployer is defined.
        if (agents.deployer) {
          // Make sure funder is funded themselves.
          const funderEth = await chainreader.getBalance(domainInfo.ORIGIN.chain, agents.deployer.address);
          log.info(`Retrieved Deployer ETH.`, {
            domain: domainInfo.ORIGIN,
            etc: {
              balance: `${utils.formatEther(funderEth)} ETH.`,
            },
          });

          if (funderEth.lt(MIN_FUNDER_ETH)) {
            log.fail(`Deployer needs at least ${utils.formatEther(MIN_FUNDER_ETH)} ETH for funding user agent.`, {
              domain: domainInfo.ORIGIN,
            });
          }
        }

        // Retrieve user balances for ETH and TEST.
        const userEth = await chainreader.getBalance(domainInfo.ORIGIN.chain, agents.user.address);
        const userTokens = await chainreader.getBalance(
          domainInfo.ORIGIN.chain,
          agents.user.address,
          originAsset.address,
        );

        log.info("Retrieved User ETH.", {
          domain: domainInfo.ORIGIN,
          etc: {
            balance: `${utils.formatEther(userEth)} ETH.`,
          },
        });
        log.info("Retrieved User TEST.", {
          domain: domainInfo.ORIGIN,
          etc: {
            balance: `${utils.formatEther(userTokens)} TEST.`,
          },
        });

        if (userEth.lt(MIN_USER_ETH)) {
          log.info("Funding user with some ETH...", { domain: domainInfo.ORIGIN });

          if (!agents.deployer) {
            throw new Error(
              "Deployer signer not configured: cannot fund User agent! Please fund the User some ETH offline.",
            );
          }

          const tx = await agents.deployer.origin.sendTransaction({
            to: agents.user.address,
            value: MIN_USER_ETH,
          });
          const receipt = await tx.wait(1);

          const userEth = await chainreader.getBalance(domainInfo.ORIGIN.chain, agents.user.address);
          if (userEth.lt(MIN_USER_ETH)) {
            log.fail(`ETH funding operation failed! User still has only ${utils.formatEther(MIN_USER_ETH)} ETH.`, {
              domain: domainInfo.ORIGIN,
            });
          }
          log.info(`Sent ETH to User.`, {
            domain: domainInfo.ORIGIN,
            hash: receipt.transactionHash,
            etc: {
              balance: `${utils.formatEther(userEth)} ETH.`,
            },
          });
        }

        if (userTokens.lt(TRANSFER_TOKEN_AMOUNT)) {
          log.info("Minting TEST tokens for User...", { domain: domainInfo.ORIGIN });
          // Might as well mint enough for 100 test iterations...
          const amount = TRANSFER_TOKEN_AMOUNT.mul(100);
          const encoded = testERC20.encodeFunctionData("mint", [agents.user.address, amount]);
          const tx = await (agents.router ?? agents.user).origin.sendTransaction({
            to: originAsset.address,
            data: encoded,
            value: BigNumber.from("0"),
          });
          const receipt = await tx.wait(1);

          const userTokens = await chainreader.getBalance(
            domainInfo.ORIGIN.chain,
            agents.user.address,
            originAsset.address,
          );
          log.info("Minted TEST tokens for User.", {
            domain: domainInfo.ORIGIN,
            hash: receipt.transactionHash,
            etc: {
              balance: `${utils.formatEther(userTokens)} TEST.`,
            },
          });
        }
      }

      log.next("TOKEN ALLOWANCES");
      // Approve TEST token spending for agents.
      {
        const infiniteApproval = constants.MaxUint256;

        // User needs to approve TEST token spend for connext contract on origin chain.
        const userAllowance: BigNumber = await getAllowance(context, {
          domain: domainInfo.ORIGIN,
          owner: agents.user.address,
          spender: originConnextAddress,
          asset: originAsset.address,
        });
        if (userAllowance.lt(TRANSFER_TOKEN_AMOUNT)) {
          log.info("Approving TEST spending for User...", { domain: domainInfo.ORIGIN });
          const encoded = testERC20.encodeFunctionData("approve", [originConnextAddress, infiniteApproval]);
          const tx = await agents.user.origin.sendTransaction({
            to: originAsset.address,
            data: encoded,
            value: BigNumber.from("0"),
          });
          const receipt = await tx.wait(1);
          log.info(`Approved TEST spending for User.`, {
            domain: domainInfo.ORIGIN,
            hash: receipt.transactionHash,
            etc: {
              allowance: `${utils.formatEther(userAllowance)} TEST.`,
            },
          });
        }

        // If Deployer is configured, it will need to approve TEST token spend for connext on destination chain (to add liquidity).
        // Otherwise, fallback to using router directly.
        if (agents.router && agents.deployer) {
          const deployerAllowance: BigNumber = await getAllowance(context, {
            domain: domainInfo.DESTINATION,
            owner: agents.deployer.address,
            spender: destinationConnextAddress,
            asset: destinationAsset.address,
          });
          if (deployerAllowance.lt(TRANSFER_TOKEN_AMOUNT)) {
            log.info("Approving TEST spending for Deployer...", { domain: domainInfo.DESTINATION });
            const encoded = testERC20.encodeFunctionData("approve", [destinationConnextAddress, infiniteApproval]);
            const tx = await agents.deployer.destination.sendTransaction({
              to: destinationAsset.address,
              data: encoded,
              value: BigNumber.from("0"),
            });
            const receipt = await tx.wait(1);
            log.info(`Approved TEST spending for Deployer.`, {
              domain: domainInfo.ORIGIN,
              hash: receipt.transactionHash,
              etc: {
                // TODO: Should read and double-check new allowance.
                prevAllowance: `${utils.formatEther(deployerAllowance)} TEST.`,
              },
            });
          }
        } else if (agents.router) {
          const routerAllowance: BigNumber = await getAllowance(context, {
            domain: domainInfo.DESTINATION,
            owner: agents.router.address,
            spender: destinationConnextAddress,
            asset: destinationAsset.address,
          });
          if (routerAllowance.lt(TRANSFER_TOKEN_AMOUNT)) {
            log.info("Approving TEST spending for Router...", { domain: domainInfo.DESTINATION });
            const encoded = testERC20.encodeFunctionData("approve", [destinationConnextAddress, infiniteApproval]);
            const tx = await agents.router.destination.sendTransaction({
              to: destinationAsset.address,
              data: encoded,
              value: BigNumber.from("0"),
            });
            const receipt = await tx.wait(1);
            log.info(`Approved TEST spending for Router.`, {
              domain: domainInfo.ORIGIN,
              hash: receipt.transactionHash,
              etc: {
                // TODO: Should read and double-check new allowance.
                prevAllowance: `${utils.formatEther(routerAllowance)} TEST.`,
              },
            });
          }
        }
      }

      if (agents.router) {
        log.next("ADD LIQUIDITY");
        // Router should add liquidity to their pool on the destination chain.
        let routerBalance: BigNumber;
        {
          const encoded = connext.encodeFunctionData("routerBalances", [
            agents.router.address,
            destinationAsset.address,
          ]);
          const result = await chainreader.readTx({
            chainId: domainInfo.DESTINATION.chain,
            to: destinationConnextAddress,
            data: encoded,
          });
          routerBalance = connext.decodeFunctionResult("routerBalances", result)[0];
        }
        log.info(`Retrieved Router liquidity balance.`, {
          domain: domainInfo.DESTINATION,
          etc: {
            balance: `${utils.formatEther(routerBalance)} TEST.`,
          },
        });

        if (routerBalance.lt(TRANSFER_TOKEN_AMOUNT)) {
          // Router liquidity balance is insufficient.

          // Ensure router (or deployer, if configured) has enough TEST tokens to add liquidity.
          if (agents.deployer) {
            let deployerTokens = await chainreader.getBalance(
              domainInfo.DESTINATION.chain,
              agents.deployer.address,
              destinationAsset.address,
            );
            log.info("Retrieved Deployer TEST.", {
              domain: domainInfo.DESTINATION,
              etc: {
                balance: `${utils.formatEther(deployerTokens)} TEST.`,
              },
            });

            if (deployerTokens.lt(ROUTER_DESIRED_LIQUIDITY)) {
              // Mint TEST tokens.
              log.info("Minting TEST tokens for Deployer (for Router liquidity)...", {
                domain: domainInfo.DESTINATION,
              });
              const amount = ROUTER_DESIRED_LIQUIDITY.mul(10);
              const encoded = testERC20.encodeFunctionData("mint", [agents.deployer.address, amount]);
              const tx = await agents.deployer.destination.sendTransaction({
                to: destinationAsset.address,
                data: encoded,
                value: BigNumber.from("0"),
              });
              const receipt = await tx.wait(1);

              deployerTokens = await chainreader.getBalance(
                domainInfo.DESTINATION.chain,
                agents.router.address,
                destinationAsset.address,
              );
              log.info(`Minted TEST tokens for Deployer. Deployer now has ${utils.formatEther(deployerTokens)} TEST.`, {
                domain: domainInfo.DESTINATION,
                hash: receipt.transactionHash,
              });
            }
          } else {
            let routerTokens = await chainreader.getBalance(
              domainInfo.DESTINATION.chain,
              agents.router.address,
              destinationAsset.address,
            );
            log.info("Retrieved Router TEST.", {
              domain: domainInfo.DESTINATION,
              etc: {
                balance: `${utils.formatEther(routerTokens)} TEST.`,
              },
            });

            if (routerTokens.lt(ROUTER_DESIRED_LIQUIDITY)) {
              // Mint TEST tokens.
              log.info("Minting TEST tokens for Router...", { domain: domainInfo.DESTINATION });
              const amount = ROUTER_DESIRED_LIQUIDITY.mul(10);
              const encoded = testERC20.encodeFunctionData("mint", [agents.router.address, amount]);
              const tx = await agents.router.destination.sendTransaction({
                to: destinationAsset.address,
                data: encoded,
                value: BigNumber.from("0"),
              });
              const receipt = await tx.wait(1);

              routerTokens = await chainreader.getBalance(
                domainInfo.DESTINATION.chain,
                agents.router.address,
                destinationAsset.address,
              );
              log.info(`Minted TEST tokens for Router. Router now has ${utils.formatEther(routerTokens)} TEST.`, {
                domain: domainInfo.DESTINATION,
                hash: receipt.transactionHash,
              });
            }
          }

          // Add liquidity.
          const amount = ROUTER_DESIRED_LIQUIDITY.mul(2);
          log.info("Adding liquidity for Router...", {
            domain: domainInfo.DESTINATION,
            etc: { amount: amount.toString(), asset: destinationAsset.address },
          });
          {
            // Try adding liquidity using deployer. Fallback to attempting to add liquidity using the router.
            let receipt: providers.TransactionReceipt;
            if (agents.deployer) {
              const encoded = connext.encodeFunctionData("addRouterLiquidityFor", [
                amount,
                destinationAsset.address,
                agents.router.address,
              ]);
              const tx = await agents.deployer.destination.sendTransaction({
                to: destinationConnextAddress,
                data: encoded,
              });
              receipt = await tx.wait(1);
            } else {
              const encoded = connext.encodeFunctionData("addRouterLiquidity", [amount, destinationAsset.address]);
              const tx = await agents.router.destination.sendTransaction({
                to: destinationConnextAddress,
                data: encoded,
              });
              receipt = await tx.wait(1);
            }

            // Check router liquidity on-chain to confirm.
            {
              const encoded = connext.encodeFunctionData("routerBalances", [
                agents.router.address,
                destinationAsset.address,
              ]);
              const result = await chainreader.readTx({
                chainId: domainInfo.DESTINATION.chain,
                to: destinationConnextAddress,
                data: encoded,
              });
              routerBalance = connext.decodeFunctionResult("routerBalances", result)[0];
            }

            if (routerBalance.lt(amount)) {
              log.fail("Add liquidity operation failed!", {
                domain: domainInfo.DESTINATION,
                hash: receipt.transactionHash,
                etc: {
                  balance: `${utils.formatEther(routerBalance)} TEST.`,
                },
              });
            }

            log.info("Added liquidity for Router.", {
              domain: domainInfo.DESTINATION,
              etc: {
                balance: `${utils.formatEther(routerBalance)} TEST.`,
              },
            });
          }
        }
      }

      // TODO: Check if relayer has ETH if necessary.

      // Check if relayer needs approval.
      log.next("VERIFY RELAYER APPROVED");
      {
        const encoded = connext.encodeFunctionData("approvedRelayers", [relayerAddress]);
        const result = await chainreader.readTx({
          chainId: domainInfo.DESTINATION.chain,
          to: destinationConnextAddress,
          data: encoded,
        });
        const approved = connext.decodeFunctionResult("approvedRelayers", result)[0];
        if (!approved) {
          if (!agents.deployer) {
            log.fail("Relayer needs to be approved on chain.", { domain: domainInfo.DESTINATION });
          } else {
            log.info("Relayer is not approved. Approving Relayer...", {
              domain: domainInfo.DESTINATION,
              etc: { relayer: relayerAddress },
            });
            const encoded = connext.encodeFunctionData("addRelayer", [relayerAddress]);
            const tx = await agents.deployer.destination.sendTransaction({
              to: destinationConnextAddress,
              data: encoded,
            });
            const receipt = await tx.wait(1);
            log.info("Approved Relayer.", {
              domain: domainInfo.DESTINATION,
              hash: receipt.transactionHash,
            });
          }
        }
      }
    }

    /// MARK - Initialize local agents (if applicable).
    {
      if (LOCAL_CARTOGRAPHER_ENABLED) {
        log.next("CARTOGRAPHER START");
        await makeRoutersPoller(cartographerConfig);
        await makeTransfersPoller(cartographerConfig);
        await delay(1_000);
      }

      if (agents.router && agents.relayer) {
        log.next("RELAYER START");
        await makeRelayer({
          ...relayerConfig,
          mnemonic: RELAYER_MNEMONIC || ROUTER_MNEMONIC,
        });
        await delay(1_000);
      }

      if (agents.router) {
        log.next("SEQUENCER START");
        await makePublisher({
          ...sequencerConfig,
          relayerUrl: agents.relayer ? sequencerConfig.relayerUrl : undefined,
        });
        await delay(1_000);

        await makeSubscriber({
          ...sequencerConfig,
          relayerUrl: agents.relayer ? sequencerConfig.relayerUrl : undefined,
        });
        await delay(1_000);

        log.next("ROUTER START");
        await makeRouter({
          ...routerConfig,
          mnemonic: ROUTER_MNEMONIC,
        });
        await delay(1_000);
      }
    }

    /// MARK - E2E Test
    {
      log.next("XCALL");
      let originTransfer: OriginTransfer;
      {
        let transactionHash: string;
        if (DEBUG_XCALL_TXHASH) {
          transactionHash = DEBUG_XCALL_TXHASH;
          log.info("Using already existing XCall...", { domain: domainInfo.ORIGIN, hash: transactionHash });
        } else {
          log.info("Sending XCall...", { domain: domainInfo.ORIGIN });
          const args: XCallArgs = {
            params: {
              to: agents.user.address,
              callData: "0x",
              originDomain: domainInfo.ORIGIN.domain,
              destinationDomain: domainInfo.DESTINATION.domain,
              forceSlow: false,
              receiveLocal: false,
              callback: constants.AddressZero,
              callbackFee: "0",
              relayerFee: "0",
              recovery: agents.user.address,
              agent: agents.user.address,
              destinationMinOut: "0",
            },
            transactingAsset: originAsset.address,
            transactingAmount: TRANSFER_TOKEN_AMOUNT.toString(),
            originMinOut: "0",
          };
          const encoded = connext.encodeFunctionData("xcall", [args]);
          const tx = await agents.user.origin.sendTransaction({
            to: originConnextAddress,
            data: encoded,
            // value: RELAYER_FEE_AMOUNT,
            // 1m gas hardcoded, in case you need to just send it:
            // gasLimit: BigNumber.from("1000000"),
          });
          const receipt = await tx.wait(1);
          log.info("XCall sent.", {
            domain: domainInfo.ORIGIN,
            hash: receipt.transactionHash,
            etc: {
              ...args,
            },
          });
          transactionHash = receipt.transactionHash;
        }

        // Poll the origin subgraph until the new XCall transfer appears.
        log.info("Polling origin subgraph for added transfer...", { domain: domainInfo.ORIGIN });
        const startTime = Date.now();
        const _originTransfer: OriginTransfer | undefined = await pollSomething({
          // Attempts will be made for 1 minute.
          attempts: Math.floor(60_000 / SUBG_POLL_PARITY),
          parity: SUBG_POLL_PARITY,
          method: async () => {
            const originTransfer = await subgraph.getOriginTransferByHash(domainInfo.ORIGIN.domain, transactionHash);
            if (originTransfer?.origin.xcall?.transactionHash) {
              return originTransfer;
            }
            return undefined;
          },
        });
        const endTime = Date.now();

        if (!_originTransfer) {
          log.fail("Failed to retrieve xcalled transfer from the origin subgraph.", {
            domain: domainInfo.ORIGIN,
            etc: {
              polled: `${(endTime - startTime) / 1_000}s.`,
            },
          });
        }
        originTransfer = _originTransfer!;

        log.info("XCall retrieved.", {
          domain: domainInfo.ORIGIN,
          etc: {
            took: `${endTime - startTime}ms.`,
            transferID: originTransfer?.transferId,
            originTransfer,
          },
        });
      }

      log.next("WAIT FOR EXECUTE");
      {
        if (agents.router && !SKIP_SEQUENCER_CHECKS) {
          log.info("Polling sequencer for auction status...");
          // Poll the sequencer a few times to see if we can get the auction status.
          // NOTE: This may be unsuccessful, but is good information to have for debugging if available.
          let error: any | undefined;
          const status: AxiosResponse<AuctionsApiGetAuctionStatusResponse> | undefined = await pollSomething({
            attempts: Math.floor(60_000 / SUBG_POLL_PARITY),
            parity: SUBG_POLL_PARITY,
            method: async () => {
              return await axios
                .request<AuctionsApiGetAuctionStatusResponse>({
                  method: "get",
                  baseURL: `http://${sequencerConfig.server.host}:${sequencerConfig.server.port}`,
                  url: `/auctions/0xf8b72dd5eb4b330a736b8f336ae13f95a26f92774e2fe95e7b5236fda75f27ed`,
                })
                .catch((e: AxiosResponse<AuctionsApiErrorResponse>) => {
                  error = e.data ? (e.data.error ? e.data.error.message : e.data) : e;
                  return undefined;
                });
            },
          });
          if (!status) {
            log.info("Unable to retrieve auction status from Sequencer.", {
              etc: {
                error,
              },
            });
          } else {
            log.info(`Retrieved auction status from Sequencer.`, {
              domain: domainInfo.DESTINATION,
              etc: { status: status.data },
            });
          }
        }

        log.info("Polling destination subgraph for execute tx...", { domain: domainInfo.DESTINATION });
        const startTime = Date.now();
        const _destinationTransfer: DestinationTransfer | undefined = await pollSomething({
          // Attempts will be made for 3 minutes.
          attempts: Math.floor(180_000 / SUBG_POLL_PARITY),
          parity: SUBG_POLL_PARITY,
          method: async () => {
            const destinationTransfer = await subgraph.getDestinationTransferById(
              domainInfo.DESTINATION.domain,
              originTransfer!.transferId,
            );
            if (destinationTransfer?.destination.reconcile?.transactionHash) {
              log.info("Transfer was reconciled.", {
                domain: domainInfo.DESTINATION,
                hash: destinationTransfer.destination.reconcile.transactionHash,
              });
            }

            if (destinationTransfer?.destination.execute?.transactionHash) {
              return destinationTransfer;
            }
            return undefined;
          },
        });
        const endTime = Date.now();

        if (!_destinationTransfer) {
          log.fail("Failed to retrieve execute transfer from the destination subgraph.", {
            domain: domainInfo.DESTINATION,
            etc: {
              polled: `${(endTime - startTime) / 1_000}s`,
            },
          });
        }
        const destinationTransfer = _destinationTransfer!;

        log.info("Execute transaction found.", {
          domain: domainInfo.DESTINATION,
          hash: destinationTransfer.destination.execute?.transactionHash,
          etc: {
            took: `${(endTime - startTime) / 1_000}s`,
          },
        });

        log.info("Transfer completed successfully!", {
          domain: domainInfo.DESTINATION,
          etc: {
            locallyExecuted:
              agents.router &&
              destinationTransfer.destination.routers &&
              destinationTransfer.destination.routers.includes(agents.router.address),
            transfer: {
              ...originTransfer,
              destination: destinationTransfer.destination,
            },
          },
        });
      }
    }
  };

  it.only("should complete a fast liquidity transfer", async function () {
    this.timeout(300_000 + EXECUTE_TIMEOUT + XCALL_TIMEOUT);
    await test();
    log.done();
  });
});
