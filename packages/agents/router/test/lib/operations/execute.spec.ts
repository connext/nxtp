import { constants, utils } from "ethers";
import { Bid, BidData, DEFAULT_ROUTER_FEE, expect, mkAddress } from "@connext/nxtp-utils";

import * as ExecuteFns from "../../../src/lib/operations/execute";
import { SlippageInvalid, ParamsInvalid, RouterNotApproved, NotEnoughAmount } from "../../../src/lib/errors";
import { mock, stubContext, stubHelpers } from "../../mock";

const { execute } = ExecuteFns;

const mockTransactingAmount = utils.parseEther("1");
const mockXTransfer = mock.entity.xtransfer(mock.chain.A, mock.chain.B, mockTransactingAmount.toString());
const mockRouter = mock.address.router;

describe("Operations:Execute", () => {
  let mockContext: any;

  before(() => {
    stubHelpers();
    mockContext = stubContext();
  });

  describe("#execute", () => {
    const mockFulfillLocalAsset = mock.asset.A.address;
    beforeEach(() => {
      mock.helpers.execute.sanityCheck.resolves();
      mock.helpers.shared.getDestinationLocalAsset.resolves(mockFulfillLocalAsset);
      mock.helpers.shared.signHandleRelayerFeePayload.resolves(mock.signature);
      mockContext.adapters.subgraph.isRouterApproved.resolves(true);
      mockContext.adapters.subgraph.getAssetBalance.resolves(constants.MaxUint256);
    });

    it("happy", async () => {
      const expectedBid: Bid = {
        fee: DEFAULT_ROUTER_FEE,
        router: mockRouter,
        signatures: {
          "1": mock.signature,
        },
      };
      const expectedBidData: BidData = {
        params: {
          to: mockXTransfer.to,
          callData: mockXTransfer.callData,
          originDomain: mockXTransfer.originDomain,
          destinationDomain: mockXTransfer.destinationDomain,
        },
        local: mockFulfillLocalAsset,
        feePercentage: ExecuteFns.RELAYER_FEE_PERCENTAGE,
        amount: mockXTransfer.xcall.localAmount,
        nonce: mockXTransfer.nonce,
        originSender: mkAddress("0xfaded"),
        relayerSignature: mock.signature,
      };

      await expect(execute(mockXTransfer)).to.be.fulfilled;

      expect(mockContext.adapters.subgraph.getAssetBalance).to.be.calledOnceWithExactly(
        mock.chain.B,
        mockContext.routerAddress,
        mockFulfillLocalAsset,
      );
      expect(mock.helpers.shared.getDestinationLocalAsset).to.be.calledOnceWithExactly(
        mockXTransfer.originDomain,
        mockXTransfer.xcall.localAsset,
        mockXTransfer.destinationDomain,
      );
      expect(mock.helpers.shared.signHandleRelayerFeePayload).to.be.calledOnce;
      expect(mock.helpers.auctions.sendBid.getCall(0).args.slice(0, 3)).to.deep.equal([
        mockXTransfer.transferId,
        expectedBid,
        expectedBidData,
      ]);
    });

    it("throws ParamsInvalid if the call params are invalid according to schema", async () => {
      const invalidParams = {
        ...mockXTransfer,
        to: "0x0",
        callData: "0x0",
        originDomain: "-1",
        destinationDomain: "-2",
      };
      expect(execute(invalidParams)).to.eventually.be.throw(new ParamsInvalid());
    });

    it.skip("should throw NotEnoughAmount if final receiving amount < 0", async () => {});

    it.skip("should error if slippage invalid", async () => {
      mockContext.config.maxSlippage = "0";
      await expect(execute(mockXTransfer)).to.be.rejectedWith(SlippageInvalid);
    });

    it("should not sendBid if no liquidity", async () => {
      mockContext.adapters.subgraph.getAssetBalance.resolves(constants.Zero);

      await expect(execute(mockXTransfer)).to.be.rejectedWith(NotEnoughAmount);
    });
  });
});
