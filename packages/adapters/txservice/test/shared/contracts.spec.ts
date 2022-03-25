import { expect } from "chai";
import Sinon, { reset, restore, SinonStub } from "sinon";
import { ConnextPriceOracle as TConnextPriceOracle } from "@connext/nxtp-contracts/typechain-types";
import * as ContractFns from "../../src/shared/contracts";

describe("contracts", () => {
  let testChainId1 = 1336;
  let testChainId2 = 1337;
  let testAddress = "0xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
  let contractDeployment: any;
  let contractDeploymentStub: SinonStub;

  beforeEach(() => {
    contractDeployment = {
      [String(testChainId1)]: {
        test: {
          name: "test",
          chainId: testChainId1,
          contracts: {
            ConnextPriceOracle: {
              address: testAddress,
              abi: ["fakeAbi()"],
            },
          },
        },
      },
    };
    contractDeploymentStub = Sinon.stub(ContractFns, "_getContractDeployments");
  });

  describe("#getContractDeployments", () => {
    beforeEach(() => {
      contractDeploymentStub.returns(contractDeployment);
    });

    it("should be correct structure", () => {
      expect(Object.keys(ContractFns._getContractDeployments()[testChainId1])[0]).to.be.equal("test");
    });
  });

  describe("#getDeployedPriceOracleContract", () => {
    beforeEach(() => {
      contractDeploymentStub.returns(contractDeployment);
    });

    it("should be undefined for unknown chainId", async () => {
      expect(ContractFns.getDeployedPriceOracleContract(testChainId2)).to.be.equal(undefined);
    });

    it("should be same as test", async () => {
      let oracleContract = ContractFns.getDeployedPriceOracleContract(testChainId1);
      expect(oracleContract.address).to.be.equal(testAddress);
      expect(oracleContract.abi[0]).to.be.equal("fakeAbi()");
    });
  });

  describe("#CHAINS_WITH_PRICE_ORACLES", () => {
    beforeEach(() => {
      contractDeploymentStub.returns(contractDeployment);
    });

    it("should return just number[]", () => {
      expect(ContractFns.CHAINS_WITH_PRICE_ORACLES).to.be.an("array");
    });
  });

  describe("#getPriceOracleInterface", () => {
    let interfaceInstance: TConnextPriceOracle["interface"] = ContractFns.getPriceOracleInterface();

    beforeEach(() => {});

    it("happy", async () => {
      expect(interfaceInstance.encodeFunctionData("admin")).to.be.equal("0xf851a440");
    });
  });

  afterEach(() => {
    restore();
    reset();
  });
});
