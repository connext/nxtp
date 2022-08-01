import { defaultAbiCoder, keccak256 } from "ethers/lib/utils";

import { ExternalCall, ReconciledTransaction } from "..";

/**
 * Cleans any strings so they replace the newlines and properly format whitespace. Used to translate human readable encoding to contract-compatible encoding.
 *
 * @param str String to clean
 * @returns Cleaned version of the input
 */
export const tidy = (str: string): string => `${str.replace(/\n/g, "").replace(/ +/g, " ")}`;

export const SignedSequencerPermitEncoding = tidy(`tuple(
  bytes32 transferId,
  address[] routers
)`);

export const SignedRouterPathEncoding = tidy(`tuple(
  bytes32 transferId,
  uint256 pathLength
)`);

export const ExternalCallDataEncoding = tidy(`tuple(
  address to,
  bytes callData
)`);

export const ReconciledTransactionDataEncoding = tidy(`tuple(
  bytes32 externalHash,
  address local,
  uint256 amount,
  address recipient
)`);

/**
 * Encodes a sequencer payload object, as defined in the BridgeFacet contract.
 *
 * @param transferId - The ID of the transfer.
 * @param routers - The addresses of the routers in the path.
 * @returns Encoded sequencer permit payload.
 */
export const encodeSequencerPermitPayload = (transferId: string, routers: string[]): string => {
  return defaultAbiCoder.encode([SignedSequencerPermitEncoding], [{ transferId, routers }]);
};

/**
 * Encodes a router path payload object, as defined in the BridgeFacet contract.
 *
 * @param transferId - The ID of the transfer.
 * @param pathLength - The number of routers in the path.
 * @returns Encoded router path payload.
 */
export const encodeRouterPathPayload = (transferId: string, pathLength: string): string => {
  return defaultAbiCoder.encode([SignedRouterPathEncoding], [{ transferId, pathLength }]);
};

/**
 * Encodes a reconcile transaction payload object, as defined in the Connext contract
 *
 * @param externalHash - Hash of the `ExternalCall`
 * @param local - The address of the bridged asset
 * @param amount - The amount forwarded through the bridge
 * @param recipient - The address that gets the funds on the destination chain
 * @returns Encoded reconcile transaction payload
 */
export const encodeReconcileData = (reconcileData: ReconciledTransaction): string => {
  return defaultAbiCoder.encode([ReconciledTransactionDataEncoding], [reconcileData]);
};

/**
 * Hashes ReconciledData payload object
 *
 * @param reconciledData Object to encode and hash
 * @returns Hash of encode object
 */
export const getReconciledHash = (reconciledData: ReconciledTransaction): string => {
  const digest = keccak256(defaultAbiCoder.encode([ReconciledTransactionDataEncoding], [reconciledData]));
  return digest;
};

/**
 * Encodes an external call transaction payload object, as defined in the Connext contract
 *
 * @param recipient - The address that should receive the funds on the destination domain if no call is
 * specified, or the fallback if an external call fails
 * @param callTo - The address of the receiving chain to execute the `callData` on
 * @param callData - The data to execute on the receiving chain
 * @returns Encoded exteranl call payload
 */
export const encodeExternalCallData = (exteranalCallData: ExternalCall): string => {
  return defaultAbiCoder.encode([ExternalCallDataEncoding], [exteranalCallData]);
};

/**
 * Hashes ExternalCall payload object
 *
 * @param externalCallData Object to encode and hash
 * @returns Hash of encoded object
 */
export const getExternalCallHash = (externalCallData: ExternalCall): string => {
  const digest = keccak256(defaultAbiCoder.encode([ExternalCallDataEncoding], [externalCallData]));
  return digest;
};
