import {
  mkAddress,
  Bid,
  expect,
  AuctionStatus,
  getRandomBytes32,
  getNtpTimeSeconds,
  XTransfer,
} from "@connext/nxtp-utils";
import { stub, restore, reset, SinonStub } from "sinon";

import { ctxMock, getOperationsStub, getHelpersStub } from "../../globalTestHook";
import { mock } from "../../mock";
import { AuctionExpired, ParamsInvalid } from "../../../src/lib/errors";
import { executeAuctions, storeBid } from "../../../src/lib/operations/auctions";

const { requestContext } = mock.loggingContext("BID-TEST");

describe("Operations:Auctions", () => {
  // db
  let getQueuedTransfersStub: SinonStub;
  let getAuctionStub: SinonStub;
  let upsertTaskStub: SinonStub;
  let upsertAuctionStub: SinonStub;
  let getStatusStub: SinonStub;
  let setStatusStub: SinonStub;
  let getTransferStub: SinonStub;

  // operations
  let sendToRelayerStub: SinonStub;

  // helpers
  let encodeExecuteFromBidStub: SinonStub;
  beforeEach(() => {
    const { auctions, transfers } = ctxMock.adapters.cache;
    upsertAuctionStub = stub(auctions, "upsertAuction").resolves(0);
    getAuctionStub = stub(auctions, "getAuction");

    getStatusStub = stub(auctions, "getStatus").resolves(AuctionStatus.None);
    setStatusStub = stub(auctions, "setStatus").resolves(1);

    getQueuedTransfersStub = stub(auctions, "getQueuedTransfers");

    upsertTaskStub = stub(auctions, "upsertTask").resolves(0);

    getTransferStub = stub(transfers, "getTransfer");

    sendToRelayerStub = stub().resolves();
    getOperationsStub.returns({
      relayer: {
        sendToRelayer: sendToRelayerStub,
      },
    });

    encodeExecuteFromBidStub = stub().resolves(getRandomBytes32());
    getHelpersStub.returns({
      auctions: {
        encodeExecuteFromBid: encodeExecuteFromBidStub,
      },
    });
  });

  afterEach(() => {
    restore();
    reset();
  });

  describe("#storeBid", () => {
    it("happy: should store bid in auction cache", async () => {
      const transfer: XTransfer = mock.entity.xtransfer();
      const transferId = transfer.transferId;
      getTransferStub.resolves(transfer);

      const bid: Bid = mock.entity.bid({ transferId });

      getStatusStub.onCall(0).resolves(AuctionStatus.None);
      getStatusStub.onCall(1).resolves(AuctionStatus.Queued);

      await storeBid(bid, requestContext);

      expect(upsertAuctionStub).to.have.been.calledOnceWithExactly({
        transferId,
        origin: transfer.originDomain,
        destination: transfer.destinationDomain,
        bid,
      });
      expect(getTransferStub).to.have.been.calledOnceWithExactly(transferId);
      expect(getStatusStub.callCount).to.eq(2);
      expect(getStatusStub.getCall(0).args).to.be.deep.eq([transferId]);
      expect(getStatusStub.getCall(1).args).to.be.deep.eq([transferId]);
    });

    it("should error if input validation fails", async () => {
      const invalidBid1: any = {
        ...mock.entity.bid(),
        fee: 1,
      };
      await expect(storeBid(invalidBid1, requestContext)).to.be.rejectedWith(ParamsInvalid);

      const invalidBid2: any = {
        ...mock.entity.bid(),
        signatures: {
          99999: -1234,
        },
      };

      await expect(storeBid(invalidBid2, requestContext)).to.be.rejectedWith(ParamsInvalid);
    });

    it("should error if the auction has expired", async () => {
      const bid: Bid = mock.entity.bid();
      getStatusStub.resolves(AuctionStatus.Sent);
      await expect(storeBid(bid, requestContext)).to.be.rejectedWith(AuctionExpired);
    });
  });

  describe("#executeAuctions", () => {
    const mockAuctionDataBatch = (count: number) =>
      new Array(count).fill(0).map(() =>
        mock.entity.auction({
          timestamp: (getNtpTimeSeconds() - ctxMock.config.auctionWaitTime - 20).toString(),
        }),
      );
    const mockTransfersBatch = (count: number) => new Array(count).fill(0).map(() => mock.entity.xtransfer());

    it("happy case: should send best bid to the relayer for each transfer", async () => {
      const taskId = getRandomBytes32();
      sendToRelayerStub.resolves(taskId);

      const count = 3;

      const transfers = mockTransfersBatch(count);
      for (let i = 0; i < count; i++) {
        getTransferStub.onCall(i).resolves(transfers[i]);
      }

      const transferIds = transfers.map((t) => t.transferId);
      getQueuedTransfersStub.resolves(transferIds);

      const auctions = mockAuctionDataBatch(count);
      for (let i = 0; i < count; i++) {
        getAuctionStub.onCall(i).resolves(auctions[i]);
      }

      await executeAuctions(requestContext);

      expect(getQueuedTransfersStub.callCount).to.eq(1);

      expect(getAuctionStub.callCount).to.be.eq(count);
      expect(getTransferStub.callCount).to.be.eq(count);
      expect(sendToRelayerStub.callCount).to.be.eq(count);

      for (let i = 0; i < count; i++) {
        expect(getAuctionStub.getCall(i).args).to.be.deep.eq([transferIds[i]]);
        expect(getTransferStub.getCall(i).args).to.be.deep.eq([transferIds[i]]);
        expect(sendToRelayerStub.getCall(i).args[0].length).to.eq(1);

        const routers = sendToRelayerStub.getCall(i).args[0];
        const transfer = sendToRelayerStub.getCall(i).args[1];
        const relayerFee = sendToRelayerStub.getCall(i).args[2];
        expect(transfer).to.deep.eq(transfers[i]);
        for (const router of routers) {
          expect(Object.keys(auctions[i].bids)).to.include(router);
        }
        expect(relayerFee.amount).to.eq(transfers[i].relayerFee);
        expect(relayerFee.asset).to.eq(transfers[i].xcall.localAsset);

        expect(setStatusStub.getCall(i).args).to.be.deep.eq([transferIds[i], AuctionStatus.Sent]);
        expect(upsertTaskStub.getCall(i).args).to.be.deep.eq([{ transferId: transferIds[i], taskId }]);
      }
    });

    it("should ignore if time elapsed is insufficient", async () => {
      const taskId = getRandomBytes32();
      sendToRelayerStub.resolves(taskId);

      const router1 = mkAddress("0x1");
      const transferId = getRandomBytes32();
      getQueuedTransfersStub.resolves([transferId]);
      const auction = mock.entity.auction({
        timestamp: getNtpTimeSeconds().toString(),
        bids: [
          {
            ...mock.entity.bid(),
            router: router1,
          },
        ],
      });
      getAuctionStub.resolves(auction);

      await executeAuctions(requestContext);

      expect(getAuctionStub.callCount).to.be.eq(1);
      expect(getTransferStub.callCount).to.be.eq(0);
      expect(sendToRelayerStub.callCount).to.be.eq(0);
    });

    it("should select a bid from multiple bids", async () => {
      const taskId = getRandomBytes32();
      sendToRelayerStub.resolves(taskId);

      const router1 = mkAddress("0x1");
      const router2 = mkAddress("0x2");
      const router3 = mkAddress("0x3");

      const transfer = mock.entity.xtransfer();
      const transferId = transfer.transferId;

      getQueuedTransfersStub.resolves([transferId]);
      const auction = mock.entity.auction({
        timestamp: (getNtpTimeSeconds() - ctxMock.config.auctionWaitTime - 20).toString(),
        bids: [
          {
            ...mock.entity.bid(),
            router: router1,
          },
          {
            ...mock.entity.bid(),
            router: router2,
          },
          {
            ...mock.entity.bid(),
            router: router3,
          },
        ],
      });
      getAuctionStub.resolves(auction);
      getTransferStub.resolves(transfer);

      await executeAuctions(requestContext);

      expect(getAuctionStub.callCount).to.be.eq(1);
      expect(getTransferStub.callCount).to.be.eq(1);
      expect(sendToRelayerStub.callCount).to.be.eq(1);

      // Just selected 1 router.
      expect(sendToRelayerStub.getCall(0).args[0].length).to.eq(1);
    });

    it.skip("should handle multipath", async () => {
      const taskId = getRandomBytes32();
      sendToRelayerStub.resolves(taskId);

      const router1 = mkAddress("0x1");
      const router2 = mkAddress("0x2");
      const router3 = mkAddress("0x3");
      const router4 = mkAddress("0x4");

      const transfer = mock.entity.xtransfer();
      const transferId = transfer.transferId;

      getQueuedTransfersStub.resolves([transferId]);
      // Based on this bid arrangement, there's only 1 option: select the 3
      // routers that can afford a 3-path transfer.
      const auction = mock.entity.auction({
        timestamp: (getNtpTimeSeconds() - ctxMock.config.auctionWaitTime - 20).toString(),
        bids: [
          // Router 1 is wealthy and can afford a 2-path and 3-path transfer.
          // ... but there's not enough routers for 2-path!
          {
            ...mock.entity.bid(),
            router: router1,
            signatures: {
              "2": getRandomBytes32(),
              "3": getRandomBytes32(),
              "5": getRandomBytes32(),
            },
          },
          {
            ...mock.entity.bid(),
            router: router2,
            signatures: {
              "3": getRandomBytes32(),
              "4": getRandomBytes32(),
              "5": getRandomBytes32(),
            },
          },
          {
            ...mock.entity.bid(),
            router: router3,
            signatures: {
              "3": getRandomBytes32(),
              "4": getRandomBytes32(),
              "5": getRandomBytes32(),
            },
          },
          // Router 4 is poor: it can't afford a 4-path transfer!
          {
            ...mock.entity.bid(),
            router: router4,
            signatures: {
              "4": getRandomBytes32(),
              "5": getRandomBytes32(),
            },
          },
        ],
      });
      getAuctionStub.resolves(auction);
      getTransferStub.resolves(transfer);

      await executeAuctions(requestContext);

      expect(getAuctionStub.callCount).to.be.eq(1);
      expect(getTransferStub.callCount).to.be.eq(1);
      expect(sendToRelayerStub.callCount).to.be.eq(1);

      // Ensure we selected the correct 3 routers.
      const selectedRouters = sendToRelayerStub.getCall(0).args[0];
      expect(selectedRouters.length).to.eq(3);
      expect(selectedRouters).to.include(router1);
      expect(selectedRouters).to.include(router2);
      expect(selectedRouters).to.include(router3);
      expect(selectedRouters).to.not.include(router4);
    });

    it("does nothing if none queued", async () => {
      getQueuedTransfersStub.resolves([]);
      await executeAuctions(requestContext);
    });
  });
});
