import { NxtpError, Values } from "@connext/nxtp-utils";

export class ExecuteError extends NxtpError {
  constructor(
    public readonly msg: Values<typeof NxtpError.reasons>,
    public readonly context: any = {},
    public readonly type = ExecuteError.name,
    public readonly level: "debug" | "info" | "warn" | "error" = "error",
    public readonly retryable = true,
  ) {
    super(msg, context, type, level);
  }
}

export class ParamsInvalid extends ExecuteError {
  constructor(context: any = {}) {
    super("Params invalid", context, ParamsInvalid.name);
  }
}

export class MissingXCall extends ExecuteError {
  constructor(context: any = {}) {
    super("Transfer is missing XCall information", context, MissingXCall.name);
  }
}
export class RouterVersionInvalid extends NxtpError {
  constructor(context: any = {}) {
    super(`Router version is not supported by the sequencer`, context, RouterVersionInvalid.name);
  }
}

export class SenderChainDataInvalid extends ExecuteError {
  constructor(context: any = {}) {
    super("Invalid data on sending chain", context, SenderChainDataInvalid.name);
  }
}

export class SlippageInvalid extends ExecuteError {
  constructor(context: any = {}) {
    super("Slippage invalid", context, SlippageInvalid.name);
  }
}

export class ExpiryInvalid extends ExecuteError {
  constructor(expiry: number, context: any = {}) {
    super(`Expiry ${expiry} invalid`, context, ExpiryInvalid.name);
  }
}

export class BidExpiryInvalid extends ExecuteError {
  constructor(expiry: number, current: number, context: any = {}) {
    super(`Bid expiry ${expiry} invalid, current: ${current}`, context, BidExpiryInvalid.name);
  }
}

export class AmountInvalid extends ExecuteError {
  constructor(amount: string, context: any = {}) {
    super(`Amount (${amount}) is invalid`, context, AmountInvalid.name);
  }
}

export class NotEnoughLiquidity extends ExecuteError {
  constructor(chainId: number, assetId: string, balance: string, amountRequested: string, context: any = {}) {
    super(
      "Not enough liquidity for bid.",
      { ...context, chainId, assetId, balance, amountRequested },
      NotEnoughLiquidity.name,
    );
  }
}

export class NotEnoughAmount extends ExecuteError {
  constructor(context: any = {}) {
    super("Not enough tokens for swap", context, NotEnoughAmount.name);
  }
}

export class CallDataForNonContract extends ExecuteError {
  constructor(context: any = {}) {
    super("Calldata specified for an address that is not a contract", context, CallDataForNonContract.name);
  }
}

export class RouterNotApproved extends ExecuteError {
  constructor(context: any = {}) {
    super("Router not approved", context, RouterNotApproved.name);
  }
}

export class SequencerResponseInvalid extends ExecuteError {
  constructor(context: any = {}) {
    super("sendBid: POST request returned invalid response", context, SequencerResponseInvalid.name);
  }
}

export class AuctionExpired extends ExecuteError {
  constructor(context: any = {}) {
    super("Auction has already expired for this transfer.", context, AuctionExpired.name);
  }
}

export class SanityCheckFailed extends ExecuteError {
  constructor(context: any = {}) {
    super("Sanity check failed", context, SanityCheckFailed.name);
  }
}

export class NomadHomeBlacklisted extends ExecuteError {
  constructor(context: any = {}) {
    super("Home network is on blacklist (nomad down)", context, NomadHomeBlacklisted.name);
  }
}

export class InvalidAuctionRound extends ExecuteError {
  constructor(context: any = {}) {
    super("Invalid auction round", context, InvalidAuctionRound.name);
  }
}

export class UnableToGetAsset extends ExecuteError {
  constructor(context: any = {}) {
    super("Unable to get asset", context, UnableToGetAsset.name, undefined, false);
  }
}

export class RetryableBidPostError extends ExecuteError {
  constructor(context: any = {}) {
    super("Could not send bid, retryable", context, RetryableBidPostError.name, undefined, true);
  }
}

export class NonRetryableBidPostError extends ExecuteError {
  constructor(context: any = {}) {
    super("Could not send bid, nonretryable", context, NonRetryableBidPostError.name, undefined, false);
  }
}
