// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ExcessivelySafeCall} from "../../../nomad-core/libs/ExcessivelySafeCall.sol";

import {IExecutor} from "../interfaces/IExecutor.sol";

import {LibCrossDomainProperty, TypedMemView} from "../libraries/LibCrossDomainProperty.sol";

/**
 * @title Executor
 * @author Connext <support@connext.network>
 * @notice This library contains an `execute` function that is callable by
 * an associated Connext contract. This is used to execute
 * arbitrary calldata on a receiving chain.
 * @dev In the event this external call fails, funds will be sent to a provided
 * recovery address. Consequently, funds held in this contract should be transitory
 */
contract Executor is IExecutor {
  // ============ Libraries =============

  using TypedMemView for bytes29;
  using TypedMemView for bytes;

  // ============ Properties =============

  /**
   * @notice Address of associated connext
   */
  address private immutable connext;

  /**
   * @notice Transaction properties that are accessible by external contracts.
   * These properties are the `origin` and `originSender` of the transfer, and are
   * only set once the data has been authenticated (i.e. nomad fraud window
   * elapsed)
   * @dev Contracts that interact with this (i.e. ones that are processing the calldata
   * for a transfer) can use these cross domain properties to permission crosschain calls
   * via:
   *
   * `require(PERMISSIONED == IExecutor(msg.sender).originSender(), "!authed");`
   *
   * If the data has not been authenticated, these properties are set to empty, and the
   * above code will revert
   */
  bytes private properties = LibCrossDomainProperty.EMPTY_BYTES;

  /**
   * @notice Amount transferred via the crosschain transaction. This is always
   * accessible (i.e. set even if the data is not authenticated) by contracts
   * processing calldata.
   * @dev This amount could be different than the amount transferred by the user from the
   * origin domain due to the AMM slippage.
   *
   * Callers can access the amount via:
   * `IExecutor(msg.sender).amount();`
   */
  uint256 private amnt;

  /**
   * @notice The amount of gas needed to execute _sendToRecovery
   * @dev Used to calculate the amount of gas to reserve from transaction
   * to properly handle failure cases
   */
  uint256 public FAILURE_GAS = 100_000; // Allowance decrease + transfer

  /**
   * @notice The maximum number of bytes to store in the return data
   */
  uint16 public MAX_COPY = 256;

  // ============ Constructor =============

  constructor(address _connext) {
    connext = _connext;
  }

  // ============ Modifiers =============

  /**
   * @notice Errors if the sender is not Connext
   */
  modifier onlyConnext() {
    require(msg.sender == connext, "!connext");
    _;
  }

  // ============ Public Functions =============

  /**
   * @notice Returns the connext contract address (only address that can
   * call the `execute` function)
   * @return The address of the associated connext contract
   */
  function getConnext() external view override returns (address) {
    return connext;
  }

  /**
   * @notice Allows a `_to` contract to access origin domain sender (i.e. msg.sender of `xcall`)
   * @dev These properties are set via reentrancy a la L2CrossDomainMessenger from
   * optimism
   */
  function originSender() external view override returns (address) {
    // The following will revert if it is empty
    bytes29 _parsed = LibCrossDomainProperty.parseDomainAndSenderBytes(properties);
    return LibCrossDomainProperty.sender(_parsed);
  }

  /**
   * @notice Allows a `_to` contract to access origin domain (i.e. domain of `xcall`)
   * @dev These properties are set via reentrancy a la L2CrossDomainMessenger from
   * optimism
   */
  function origin() external view override returns (uint32) {
    // The following will revert if it is empty
    bytes29 _parsed = LibCrossDomainProperty.parseDomainAndSenderBytes(properties);
    return LibCrossDomainProperty.domain(_parsed);
  }

  /**
   * @notice Allows a `_to` contract to access the amount that was delivered from the
   * bridge. This is also set during reentrancy, but is set during fast *and* slow
   * liquidity paths
   * @dev These properties are set via reentrancy a la L2CrossDomainMessenger from
   * optimism
   */
  function amount() external view override returns (uint256) {
    return amnt;
  }

  /**
   * @notice Executes some arbitrary call data on a given address. The call data executes can be payable, and
   * will have `amount` sent along with the function (or approved to the contract). If the call fails, rather
   * than reverting, funds are sent directly to the provided fallback address (`recovery`).
   *
   * @param _args ExecutorArgs to function.
   */
  function execute(ExecutorArgs memory _args) external override onlyConnext returns (bool, bytes memory) {
    // Check if the `to` target is a contract.
    bool success;
    bytes memory returnData;

    if (!Address.isContract(_args.to)) {
      _sendToRecovery(false, _args.assetId, _args.to, _args.recovery, _args.amount);
      // Emit event
      emit Executed(
        _args.transferId,
        _args.to,
        _args.recovery,
        _args.assetId,
        _args.amount,
        _args.properties,
        _args.callData,
        returnData,
        success
      );
      return (success, returnData);
    }

    // Approve the `to` address for spending tokens.
    // We approve here rather than transfer since many external contracts simply require an approval, and
    // it is unclear if they can handle funds transferred directly to them (i.e. Uniswap).

    bool hasValue = _args.amount != 0;

    if (hasValue) {
      SafeERC20.safeApprove(IERC20(_args.assetId), _args.to, 0);
      SafeERC20.safeIncreaseAllowance(IERC20(_args.assetId), _args.to, _args.amount);
    }

    // If it should set the properties, set them.
    // NOTE: safe to set the properties always because modifier will revert if
    // it is the wrong type on conversion, and revert occurs with empty type as
    // well
    properties = _args.properties;

    // Set the amount as well
    amnt = _args.amount;

    // Ensure there is enough gas to handle failures
    uint256 gas = gasleft() - FAILURE_GAS;

    // Try to execute the callData
    // the low level call will return `false` if its execution reverts
    (success, returnData) = ExcessivelySafeCall.excessivelySafeCall(_args.to, gas, 0, MAX_COPY, _args.callData);

    // Unset properties
    properties = LibCrossDomainProperty.EMPTY_BYTES;

    // Unset amount
    amnt = 0;

    // Handle failure cases
    if (!success) {
      _sendToRecovery(hasValue, _args.assetId, _args.to, _args.recovery, _args.amount);
    }

    // Emit event
    emit Executed(
      _args.transferId,
      _args.to,
      _args.recovery,
      _args.assetId,
      _args.amount,
      _args.properties,
      _args.callData,
      returnData,
      success
    );
    return (success, returnData);
  }

  /**
   * @notice Sends funds to the specified recovery address
   * @dev Called if the external call data fails or if the recipient was not a contract.
   * @param _hasIncreased - Whether the allowance was increased
   * @param _assetId - Asset associated with call
   * @param _to - Where call was attempted
   * @param _recovery - Where to send funds
   * @param _amount - Amount to send
   */
  function _sendToRecovery(
    bool _hasIncreased,
    address _assetId,
    address _to,
    address _recovery,
    uint256 _amount
  ) private {
    if (_amount == 0) {
      // Nothing to do, exit early
      return;
    }

    // Decrease allowance
    if (_hasIncreased) {
      SafeERC20.safeDecreaseAllowance(IERC20(_assetId), _to, _amount);
    }
    // Transfer funds
    SafeERC20.safeTransfer(IERC20(_assetId), _recovery, _amount);
  }
}
