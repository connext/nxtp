// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "../../../utils/ForgeHelper.sol";
import {TestAggregator} from "../../../../contracts/test/TestAggregator.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../../../contracts/core/connext/helpers/ConnextPriceOracle.sol";

contract MockERC20 is ERC20 {
  uint8 public _decimals;

  constructor(uint8 decimals) ERC20("MockERC20", "MockERC20") {
    _decimals = decimals;
    _mint(msg.sender, 1000000 ether);
  }

  function decimals() public view override(ERC20) returns (uint8) {
    return _decimals;
  }

  function mint(address account, uint256 amount) external {
    _mint(account, amount);
  }
}

contract ConnextPriceOracleTest is ForgeHelper {
  // ============ Storage ============
  ConnextPriceOracle priceOracle;
  ConnextPriceOracle v1PriceOracle;
  address _aggregator;
  address _tokenA;
  address _tokenB;
  address _tokenV1 = address(1);
  address _wrapped = address(55555);

  // ============ Errors ============
  error ProposedOwnable__onlyOwner_notOwner();

  // ============ Events ============
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event PriceRecordUpdated(address token, address baseToken, address lpToken, bool _active);
  event DirectPriceUpdated(address token, uint256 oldPrice, uint256 newPrice);
  event AggregatorUpdated(address tokenAddress, address source);
  event V1PriceOracleUpdated(address oldAddress, address newAddress);

  // ============ Setup ============
  function setUp() public {
    utils_deployAndSetup();
  }

  // ============ utils ============
  function utils_deployAndSetup() public {
    vm.expectEmit(true, true, true, true);
    emit OwnershipTransferred(address(0), address(this));
    priceOracle = new ConnextPriceOracle(_wrapped);

    vm.expectEmit(true, true, true, true);
    emit OwnershipTransferred(address(0), address(this));
    v1PriceOracle = new ConnextPriceOracle(_tokenV1);
    _aggregator = address(new TestAggregator(18));
    _tokenA = address(new MockERC20(18));
    _tokenB = address(new MockERC20(36));

    address[] memory tokenAddresses = new address[](1);
    address[] memory sources = new address[](1);
    tokenAddresses[0] = _wrapped;
    sources[0] = _aggregator;
    v1PriceOracle.setDirectPrice(_tokenV1, 1e18, block.timestamp);
    priceOracle.setAggregators(tokenAddresses, sources);
    priceOracle.setV1PriceOracle(address(v1PriceOracle));
    assertEq(priceOracle.owner(), address(this));
    assertEq(priceOracle.proposed(), address(0));
    assertEq(v1PriceOracle.owner(), address(this));
    assertEq(v1PriceOracle.proposed(), address(0));
  }

  // ============ getTokenPrice ============
  function test_ConnextPriceOracle__getTokenPrice_worksIfExistsInAssetPrices() public {
    priceOracle.setDirectPrice(_tokenA, 1e18, block.timestamp);
    (uint256 price, uint256 source) = priceOracle.getTokenPrice(_tokenA);
    assertEq(price, 1e18);
    assertEq(source, 1);
  }

  function test_ConnextPriceOracle__getTokenPrice_worksIfAggregatorExists() public {
    (uint256 price, ) = priceOracle.getTokenPrice(_wrapped);
    assertEq(price, 1e18);
  }

  // should work for the native asset
  function test_ConnextPriceOracle__getTokenPrice_worksForNative() public {
    (uint256 price, ) = priceOracle.getTokenPrice(address(0));
    assertEq(price, 1e18);
  }

  function test_ConnextPriceOracle__getTokenPrice_worksIfv1Exists() public {
    (uint256 price, uint256 source) = priceOracle.getTokenPrice(_tokenV1);
    assertEq(price, 1e18);
    assertEq(source, 4);
  }

  function test_ConnextPriceOracle__getTokenPrice_fails() public {
    (uint256 price, uint256 source) = priceOracle.getTokenPrice(address(12345));
    assertEq(price, 0);
    assertEq(source, 4);
  }

  // ============ getPriceFromOracle ============
  function test_ConnextPriceOracle__getPriceFromOracle_works() public {
    assertEq(priceOracle.getPriceFromOracle(_wrapped), 1e18);
  }

  // should work if the token is not configured
  function test_ConnextPriceOracle__getPriceFromOracle_returnZeroIfNotConfigured() public {
    assertEq(priceOracle.getPriceFromOracle(address(123123123123)), 0);
  }

  // ============ getPriceFromChainlink ============
  function test_ConnextPriceOracle__getPriceFromChainlink_works() public {
    assertEq(priceOracle.getPriceFromChainlink(_wrapped), 1e18);
  }

  function test_ConnextPriceOracle__getPriceFromChainlink_fails() public {
    assertEq(priceOracle.getPriceFromChainlink(address(12345)), 0);
  }

  function test_ConnextPriceOracle__getPriceFromChainlink_worksIfGreaterThan18() public {
    address[] memory _tokenAddresses = new address[](2);
    address _tokenAddr1 = address(11);
    address _tokenAddr2 = address(22);
    _tokenAddresses[0] = _tokenAddr1;
    _tokenAddresses[1] = _tokenAddr2;

    address[] memory _sources = new address[](2);
    address _aggregator1 = address(new TestAggregator(24));
    address _aggregator2 = address(new TestAggregator(36));
    _sources[0] = _aggregator1;
    _sources[1] = _aggregator2;
    vm.expectEmit(true, true, true, true);
    for (uint256 i = 0; i < 2; i++) {
      emit AggregatorUpdated(_tokenAddresses[i], _sources[i]);
    }
    priceOracle.setAggregators(_tokenAddresses, _sources);

    assertEq(priceOracle.getPriceFromChainlink(_tokenAddr1), 1e18);
    assertEq(priceOracle.getPriceFromChainlink(_tokenAddr2), 1e18);
  }

  function test_ConnextPriceOracle__getPriceFromChainlink_returnsZeroIfAggregatorReverts() public {
    address[] memory _tokenAddresses = new address[](2);
    address _tokenAddr1 = address(11);
    address _tokenAddr2 = address(22);
    _tokenAddresses[0] = _tokenAddr1;
    _tokenAddresses[1] = _tokenAddr2;

    address[] memory _sources = new address[](2);
    address _aggregator1 = address(new TestAggregator(24));
    address _aggregator2 = address(new TestAggregator(36));
    _sources[0] = _aggregator1;
    _sources[1] = _aggregator2;
    vm.expectEmit(true, true, true, true);
    for (uint256 i = 0; i < 2; i++) {
      emit AggregatorUpdated(_tokenAddresses[i], _sources[i]);
    }
    priceOracle.setAggregators(_tokenAddresses, _sources);

    assertEq(priceOracle.getPriceFromChainlink(_tokenAddr1), 1e18);

    TestAggregator(_aggregator2).stop();
    assertEq(priceOracle.getPriceFromChainlink(_tokenAddr2), 0);
  }

  function test_ConnextPriceOracle__getPriceFromChainlink_returnsZeroIfReturnsStalePrice() public {
    address[] memory _tokenAddresses = new address[](1);
    address _tokenAddr = address(11);
    _tokenAddresses[0] = _tokenAddr;

    address[] memory _sources = new address[](1);
    address _aggregator = address(new TestAggregator(24));
    _sources[0] = _aggregator;
    vm.expectEmit(true, true, true, true);
    for (uint256 i = 0; i < 1; i++) {
      emit AggregatorUpdated(_tokenAddresses[i], _sources[i]);
    }
    priceOracle.setAggregators(_tokenAddresses, _sources);

    assertEq(priceOracle.getPriceFromChainlink(_tokenAddr), 1e18);
    TestAggregator(_aggregator).updateMockData(2, 1, 1e8, 1);
    assertEq(priceOracle.getPriceFromChainlink(_tokenAddr), 0);
  }

  function test_ConnextPriceOracle__getPriceFromChainlink_returnsZeroIfRoundsNotCompleted() public {
    address[] memory _tokenAddresses = new address[](1);
    address _tokenAddr = address(11);
    _tokenAddresses[0] = _tokenAddr;

    address[] memory _sources = new address[](1);
    address _aggregator = address(new TestAggregator(24));
    _sources[0] = _aggregator;
    vm.expectEmit(true, true, true, true);
    for (uint256 i = 0; i < 1; i++) {
      emit AggregatorUpdated(_tokenAddresses[i], _sources[i]);
    }
    priceOracle.setAggregators(_tokenAddresses, _sources);

    assertEq(priceOracle.getPriceFromChainlink(_tokenAddr), 1e18);
    TestAggregator(_aggregator).updateMockData(2, 1, 0, 2);
    assertEq(priceOracle.getPriceFromChainlink(_tokenAddr), 0);
  }

  // ============ setDirectPrice ============
  function test_ConnextPriceOracle__setDirectPrice_worksIfOnlyAdmin() public {
    vm.expectEmit(true, true, true, true);
    emit DirectPriceUpdated(_tokenA, 0, 2e18);
    priceOracle.setDirectPrice(_tokenA, 2e18, block.timestamp);
    (uint256 timestamp, uint256 price) = priceOracle.assetPrices(_tokenA);
    assertEq(timestamp, block.timestamp);
    assertEq(price, 2e18);
  }

  function test_ConnextPriceOracle__setDirectPrice_failsIfNotOwner() public {
    vm.expectRevert(ProposedOwnable__onlyOwner_notOwner.selector);
    vm.prank(address(12345));
    priceOracle.setDirectPrice(_tokenA, 2e18, block.timestamp);
    (uint256 price, ) = priceOracle.assetPrices(_tokenA);
    assertEq(price, 0);
  }

  // ============ setV1PriceOracle ============
  function test_ConnextPriceOracle__setV1PriceOracle_worksIfOnlyAdmin() public {
    ConnextPriceOracle newV1PriceOracle = new ConnextPriceOracle(_wrapped);
    vm.expectEmit(true, true, true, true);
    emit V1PriceOracleUpdated(address(v1PriceOracle), address(newV1PriceOracle));
    priceOracle.setV1PriceOracle(address(newV1PriceOracle));
  }

  function test_ConnextPriceOracle__setV1PriceOracle_failsIfNotOwner() public {
    ConnextPriceOracle newV1PriceOracle = new ConnextPriceOracle(_wrapped);
    vm.expectRevert(ProposedOwnable__onlyOwner_notOwner.selector);
    vm.prank(address(12345));
    priceOracle.setV1PriceOracle(address(newV1PriceOracle));
  }

  // ============ setAggregators ============
  function test_ConnextPriceOracle__setAggregators_worksIfOnlyAdmin() public {
    address[] memory _tokenAddresses = new address[](2);
    address _tokenAddr1 = address(11);
    address _tokenAddr2 = address(22);
    _tokenAddresses[0] = _tokenAddr1;
    _tokenAddresses[1] = _tokenAddr2;

    address[] memory _sources = new address[](2);
    address _aggregator1 = address(new TestAggregator(18));
    address _aggregator2 = address(new TestAggregator(36));
    _sources[0] = _aggregator1;
    _sources[1] = _aggregator2;
    vm.expectEmit(true, true, true, true);
    for (uint256 i = 0; i < 2; i++) {
      emit AggregatorUpdated(_tokenAddresses[i], _sources[i]);
    }
    priceOracle.setAggregators(_tokenAddresses, _sources);
  }

  function test_ConnextPriceOracle__setAggregators_failsIfNotOwner() public {
    address[] memory _tokenAddresses = new address[](2);
    address _tokenAddr1 = address(11);
    address _tokenAddr2 = address(22);
    _tokenAddresses[0] = _tokenAddr1;
    _tokenAddresses[1] = _tokenAddr2;

    address[] memory _sources = new address[](2);
    address _aggregator1 = address(new TestAggregator(18));
    address _aggregator2 = address(new TestAggregator(36));
    _sources[0] = _aggregator1;
    _sources[1] = _aggregator2;
    vm.expectRevert(ProposedOwnable__onlyOwner_notOwner.selector);
    vm.prank(address(12345));
    priceOracle.setAggregators(_tokenAddresses, _sources);
  }
}
