import { Signer, Wallet, BigNumber, providers } from "ethers";
import { arrayify, solidityKeccak256, splitSignature, verifyMessage } from "ethers/lib/utils";

import { encodeRouterPathPayload, encodeSequencerPermitPayload } from ".";

/**
 * Occasionally have seen metamask return signatures with v = 00 or v = 01.
 * Signatures having these values will revert when used onchain. Ethers handles
 * these cases in the `splitSignature` function, where it regenerates an
 * appropriate `v` value:
 * https://github.com/ethers-io/ethers.js/blob/c2c0ce75039e7256b287f9a764188d08ed0b7296/packages/bytes/src.ts/index.ts#L348-L355
 *
 * This function will rely on the edgecase handling there to ensure any
 * signatures are properly formatted. This has been tested manually against
 * offending signatures.
 *
 * @param sig Signature to sanitize
 */
const sanitizeSignature = (sig: string): string => {
  if (sig.endsWith("1c") || sig.endsWith("1b")) {
    return sig;
  }

  // Must be sanitized
  const { v } = splitSignature(sig);
  const hex = BigNumber.from(v).toHexString();
  return sig.slice(0, sig.length - 2) + hex.slice(2);
};

export const sign = async (hash: string, signer: Wallet | Signer): Promise<string> => {
  const msg = arrayify(hash);
  const addr = await signer.getAddress();
  if (typeof (signer.provider as providers.Web3Provider)?.send === "function") {
    try {
      return sanitizeSignature(
        (await (signer.provider as providers.Web3Provider).send("personal_sign", [hash, addr])) as string,
      );
    } catch (err: unknown) {
      // console.error("Error using personal_sign, falling back to signer.signMessage: ", err);
    }
  }

  return sanitizeSignature(await signer.signMessage(msg));
};

/**
 * Generates a signature on the transfer ID and routers array payload for the `execute` transaction.
 * Permit represents a (whitelisted) sequencer's indication that they were responsible for assigning
 * this path of routers to this particular transfer.
 *
 * @param transferId - The ID of the transfer.
 * @param routers - The addresses of the routers that are supplying fast liquidity for the transfer.
 * @param signer - The Wallet / Signer of the signing sequencer.
 * @returns Signature of the payload from the signer.
 */
export const signSequencerPermitPayload = async (
  transferId: string,
  routers: string[],
  signer: Wallet | Signer,
): Promise<string> => {
  const payload = encodeSequencerPermitPayload(transferId, routers);
  const hash = solidityKeccak256(["bytes"], [payload]);
  return await sign(hash, signer);
};

/**
 * Generates a signature on the router path length payload in `execute` transaction. Represents
 * consent of the signing router to use a portion of their liquidity (minus a fee) to `execute` the
 * transfer.
 *
 * @param transferId - The ID of the transfer.
 * @param pathLength - The number of routers that are supplying fast liquidity for the transfer.
 * @param signer - The Wallet / Signer of the signing router.
 * @returns Signature of the payload from the signer.
 */
export const signRouterPathPayload = async (
  transferId: string,
  pathLength: string,
  signer: Wallet | Signer,
): Promise<string> => {
  const hash = getRouterPathHashToSign(transferId, pathLength);

  return await sign(hash, signer);
};

/**
 * Generates a hash to sign of the router path length payload in `execute` transaction
 *
 * @param transferId - The nonce of the origin domain at the time the transaction was prepared. Used to generate
 * the transaction id for the crosschain transaction
 * @param pathLength - The number of routers in transfer
 * @returns Hash that should be signed
 */
export const getRouterPathHashToSign = (transferId: string, pathLength: string): string => {
  const payload = encodeRouterPathPayload(transferId, pathLength);
  const hash = solidityKeccak256(["bytes"], [payload]);
  return hash;
};

/**
 * Returns the recovered signer from the router path length payload
 *
 * @param transferId - The transferId generated on the origin domain
 * @param pathLength - The number of routers in transfer
 * @returns Recovered address of signer
 */
export const recoverRouterPathPayload = (transferId: string, pathLength: string, signature: string): string => {
  const hashed = getRouterPathHashToSign(transferId, pathLength);
  return verifyMessage(arrayify(hashed), signature);
};
