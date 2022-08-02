// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

/**
 * @title IBridgeRouter
 * @notice Contains the interface used by Connext contracts into Nomad's
 * BridgeRouter. The BridgeRouter is responsible for:
 * - formatting and dispatching outbound nomad messages
 * - custodying canonical and minting/burning local tokens
 * - formatting and handling inbound nomad messages
 */
interface IBridgeRouter {
  /**
   * @notice Send tokens to a recipient on a remote chain
   * @param _token The token address
   * @param _amount The token amount
   * @param _destination The destination domain
   * @param _recipient The recipient address
   */
  function send(
    address _token,
    uint256 _amount,
    uint32 _destination,
    bytes32 _recipient,
    bool /* _enableFast deprecated field, left argument for backwards compatibility */
  ) external;

  /**
   * @notice Send tokens to a hook on the remote chain
   * @param _token The token address
   * @param _amount The token amount
   * @param _destination The destination domain
   * @param _remoteHook The hook contract on the remote chain
   * @param _extraData Extra data that will be passed to the hook for
   *        execution
   */
  function sendToHook(
    address _token,
    uint256 _amount,
    uint32 _destination,
    bytes32 _remoteHook,
    bytes calldata _extraData
  ) external;
}
