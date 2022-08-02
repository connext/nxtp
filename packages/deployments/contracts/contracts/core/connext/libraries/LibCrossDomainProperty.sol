// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {TypedMemView} from "../../../nomad-core/libs/TypedMemView.sol";

/**
 * @notice This library includes functions to help parse the values appended
 * to the `msg.data` when a call is executed by the `Executor`.
 *
 * During a crosschain transfer, a user specifies `callData` to be executed on
 * the destination domain via `.call`. Prior to executing this `callData`, the
 * `Executor` will append the following properties to the calldata:
 * - origin - the origin domain
 * - originSender - `msg.sender` of `xcall`
 * - amount - the amount the `.call` is executed with
 *
 * This library provides helpers to parse these properties out from and append
 * them to the calldata.
 *
 * ***IMPORTANT NOTE ON USAGE***
 * It is important to keep in mind that ANYONE can append bogus properties to the
 * `msg.data` a function receives. To ensure checks such as:
 *      _admin == LibCrossDomainProperty.originSender(msg.data);
 * are valid, checking these properties should be paired with enforcing the msg.sender
 * of the call is the `Executor` contract on that domain.
 */
library LibCrossDomainProperty {
  // ============ Libraries ============

  using TypedMemView for bytes29;
  using TypedMemView for bytes;

  // ============ Constants ============

  // 32 bytes amount + 4 bytes domain + 20 bytes address = 56 bytes;
  uint256 private constant PROPERTIES_LENGTH = 56;

  // ============ Internal Functions ============

  /**
   * @notice Appends the supplied properties to the end of the callData
   * @dev See warning at the top of the file about usage
   * @param _amount The amount the call is executed with
   * @param _originDomain The originating domain of the call
   * @param _originSender The msg.sender of the xcall
   * @param _calldata The function data to be executed with the .call
   * @return bytes A byte array containing the calldata and all properties
   */
  function formatCalldataWithProperties(
    uint256 _amount,
    uint32 _originDomain,
    address _originSender,
    bytes memory _calldata
  ) internal returns (bytes memory) {
    // Convert data to bytes
    bytes memory properties = abi.encodePacked(_amount, _originDomain, _originSender);
    return bytes.concat(_calldata, properties);
  }

  /**
   * @notice Parses the amount from the msg.data
   * @dev See warning at the top of the file about usage
   * @param _data The msg.data sent by executor
   * @return uint256 Amount to execute call with
   */
  function amount(bytes memory _data) internal returns (uint256) {
    // create view
    bytes29 typed = _data.ref(0);
    // before the domain = calldata
    return typed.indexUint(callDataLength(typed), 32);
  }

  /**
   * @notice Parses the origin domain from the msg.data
   * @dev See warning at the top of the file about usage
   * @param _data The msg.data sent by executor
   * @return uint32 origin domain
   */
  function origin(bytes memory _data) internal returns (uint32) {
    // create view
    bytes29 typed = _data.ref(0);
    // before the domain = calldata + amount
    return uint32(typed.indexUint(callDataLength(typed) + 32, 4));
  }

  /**
   * @notice Parses the origin msg.sender from the msg.data
   * @dev See warning at the top of the file about usage
   * @param _data The msg.data sent by executor
   * @return address The msg.sender of the initial `xcall`
   */
  function originSender(bytes memory _data) internal returns (address) {
    // create view
    bytes29 typed = _data.ref(0);
    // before the domain = calldata + amount + domain
    return typed.indexAddress(callDataLength(typed) + 36);
  }

  /**
   * @notice Used internally to get the length of the calldata included
   * @dev See warning at the top of the file about usage
   * @param _view The msg.data sent by executor cast as a TypedMemView
   * @return uint256 Length of the calldata
   */
  function callDataLength(bytes29 _view) internal returns (uint256) {
    uint256 len = _view.len();
    require(len >= PROPERTIES_LENGTH, "!length");
    // The data will be packed with the properties appended to the data
    return len - PROPERTIES_LENGTH;
  }
}
