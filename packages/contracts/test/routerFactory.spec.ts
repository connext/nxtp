import { ethers, waffle } from "hardhat";
import { expect, use } from "chai";
import { solidity } from "ethereum-waffle";

use(solidity);

import { Wallet, providers, Contract } from "ethers";
import { TransactionManager } from "@connext/nxtp-contracts";
import TransactionManagerArtifact from "@connext/nxtp-contracts/artifacts/contracts/TransactionManager.sol/TransactionManager.json";
import RouterArtifact from "@connext/nxtp-contracts/artifacts/contracts/Router.sol/Router.json";

import { deployContract, assertReceiptEvent } from "./utils";

// import types
import { RouterFactory } from "../typechain";

const createFixtureLoader = waffle.createFixtureLoader;
describe("Router Contract", function () {
  const [wallet, routerSigner, recipient, other] = waffle.provider.getWallets() as Wallet[];
  let routerFactory: RouterFactory;
  let routerFactorySec: RouterFactory;

  let transactionManager: TransactionManager;
  let transactionManagerReceiverSide: TransactionManager;

  const sendingChainId = 1338;
  const receivingChainId = 1338;

  const fixture = async () => {
    transactionManager = await deployContract<TransactionManager>(TransactionManagerArtifact, receivingChainId);

    transactionManagerReceiverSide = await deployContract<TransactionManager>(
      TransactionManagerArtifact,
      receivingChainId,
    );

    routerFactory = await deployContract<RouterFactory>("RouterFactory");

    const initTx = await routerFactory.init(transactionManagerReceiverSide.address, receivingChainId);
    await initTx.wait();

    routerFactorySec = await deployContract<RouterFactory>("RouterFactory");

    const initSecTx = await routerFactorySec.init(transactionManager.address, sendingChainId);
    await initSecTx.wait();

    return {
      routerFactory,
      transactionManagerReceiverSide,
    };
  };

  let loadFixture: ReturnType<typeof createFixtureLoader>;
  before("create fixture loader", async () => {
    loadFixture = createFixtureLoader([wallet, routerSigner, recipient, other]);
  });

  beforeEach(async function () {
    ({ transactionManagerReceiverSide, routerFactory } = await loadFixture(fixture));
  });

  describe("constructor", async () => {
    it("should deploy", async () => {
      expect(routerFactory.address).to.be.a("string");
    });

    it("should get transactionManagerAddress", async () => {
      expect(await routerFactory.transactionManager()).to.eq(transactionManagerReceiverSide.address);
    });
  });

  describe("create router", () => {
    it("should create router", async () => {
      const tx: providers.TransactionResponse = await routerFactory
        .connect(routerSigner)
        .createRouter(routerSigner.address, recipient.address);

      const receipt = await tx.wait();
      expect(receipt.status).to.be.eq(1);

      const computedRouterAddress = await routerFactory.getRouterAddress(routerSigner.address);

      const computedRouterAddressSec = await routerFactorySec.getRouterAddress(routerSigner.address);

      console.log(computedRouterAddress, computedRouterAddressSec);
      expect(computedRouterAddress).to.be.a("string");

      await assertReceiptEvent(receipt, "RouterCreated", {
        router: computedRouterAddress,
        routerSigner: routerSigner.address,
        recipient: recipient.address,
        transactionManager: transactionManagerReceiverSide.address,
      });

      const routerInstance = new Contract(computedRouterAddress, RouterArtifact.abi, ethers.provider);

      expect(await routerInstance.transactionManager()).to.be.eq(transactionManagerReceiverSide.address);
      expect(await routerInstance.recipient()).to.be.eq(recipient.address);
      expect(await routerInstance.routerSigner()).to.be.eq(routerSigner.address);
    });
  });
});
