import { AuctionStatus, NxtpError } from "@connext/nxtp-utils";

export class ParamsInvalid extends NxtpError {
  constructor(context: any = {}) {
    super(`Params invalid`, context, ParamsInvalid.name);
  }
}

export class RouterVersionInvalid extends NxtpError {
  constructor(context: any = {}) {
    super(`Router version is not supported by the sequencer`, context, RouterVersionInvalid.name);
  }
}

export class AuctionExpired extends NxtpError {
  constructor(status: AuctionStatus, context: any = {}) {
    super("This auction has already expired.", { status, ...context }, AuctionExpired.name);
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

export class RoundInvalid extends NxtpError {
  constructor(context: any = {}) {
    super(`Rounds invalid`, context, RoundInvalid.name);
  }
}
