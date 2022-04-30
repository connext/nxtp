import { AuctionStatus, NxtpError } from "@connext/nxtp-utils";

export class ParamsInvalid extends NxtpError {
  constructor(context: any = {}) {
    super("Params invalid.", context, ParamsInvalid.name);
  }
}

export class AuctionExpired extends NxtpError {
  constructor(status: AuctionStatus, context: any = {}) {
    super("This auction has already expired.", { status, ...context }, AuctionExpired.name);
  }
}

export class AssetNotFound extends NxtpError {
  constructor(domain: string, local: string, context: any = {}) {
    super(
      "Unable to find the origin domain's local asset in the subgraph.",
      { domain, local, ...context },
      AssetNotFound.name,
    );
  }
}

export class MissingXCall extends NxtpError {
  constructor(domain: string, transferId: string, context: any = {}) {
    super(
      "No XCall was found in the subgraph for this auction.",
      { domain, transferId, ...context },
      MissingXCall.name,
    );
  }
}
