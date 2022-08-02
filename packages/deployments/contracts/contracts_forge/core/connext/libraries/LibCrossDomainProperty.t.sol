// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "../../../utils/ForgeHelper.sol";

import "../../../../contracts/core/connext/libraries/LibCrossDomainProperty.sol";

contract Target {
  uint256 public value;
  uint256 public amount;
  uint32 public origin;
  address public originSender;

  function saveProperties(uint256 _value) public {
    value = _value;
    amount = LibCrossDomainProperty.amount(msg.data);
    origin = LibCrossDomainProperty.origin(msg.data);
    originSender = LibCrossDomainProperty.originSender(msg.data);
  }
}

contract LibCrossDomainPropertyTest is ForgeHelper {
  // ============ Libraries ============

  using stdStorage for StdStorage;
  using TypedMemView for bytes29;
  using TypedMemView for bytes;

  // ============ Storage ============

  uint32 domain = uint32(1000);
  address sender = address(1);
  uint256 amount = 12387129387;
  Target target;

  // ============ Setup ============

  function setUp() public {
    target = new Target();
    assertEq(target.value(), 0);
    assertEq(target.amount(), 0);
    assertEq(target.origin(), 0);
    assertEq(target.originSender(), address(0));
  }

  // ============ test ============

  function test_LibCrossDomainProperty__shouldWorkInMemory() public {
    uint256 value = 112112;
    bytes memory callData = abi.encodeWithSelector(Target.saveProperties.selector, value);
    bytes memory formatted = LibCrossDomainProperty.formatCalldataWithProperties(amount, domain, sender, callData);

    assertEq(LibCrossDomainProperty.amount(formatted), amount);
    assertEq(LibCrossDomainProperty.origin(formatted), domain);
    assertEq(LibCrossDomainProperty.originSender(formatted), sender);
  }

  function test_LibCrossDomainProperty__shouldWorkInFunctionCall() public {
    uint256 value = 112112;
    bytes memory callData = abi.encodeWithSelector(Target.saveProperties.selector, value);
    bytes memory formatted = LibCrossDomainProperty.formatCalldataWithProperties(amount, domain, sender, callData);

    address(target).call(formatted);
    assertEq(target.value(), value);
    assertEq(target.amount(), amount);
    assertEq(target.origin(), domain);
    assertEq(target.originSender(), sender);
  }

  function test_LibCrossDomainProperty__shouldWorkWithEmptyProperties() public {
    uint256 value = 112112;
    bytes memory callData = abi.encodeWithSelector(Target.saveProperties.selector, value);
    bytes memory formatted = LibCrossDomainProperty.formatCalldataWithProperties(0, 0, address(0), callData);

    address(target).call(formatted);
    assertEq(target.value(), value);
    assertEq(target.amount(), 0);
    assertEq(target.origin(), 0);
    assertEq(target.originSender(), address(0));
  }
}
