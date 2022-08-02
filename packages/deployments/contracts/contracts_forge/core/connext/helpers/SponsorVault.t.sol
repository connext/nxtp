// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "../../../utils/ForgeHelper.sol";

import {SponsorVault, ITokenExchange, IGasTokenOracle, IPriceOracle} from "../../../../contracts/core/connext/helpers/SponsorVault.sol";
import {ConnextPriceOracle} from "../../../../contracts/core/connext/helpers/ConnextPriceOracle.sol";

import {TestERC20} from "../../../../contracts/test/TestERC20.sol";

contract MockTokenExchange is ITokenExchange {
  uint256 private sawpResult;

  function setSwapResult(uint256 _sawpResult) external {
    sawpResult = _sawpResult;
  }

  function getInGivenExpectedOut(address token, uint256 expectedOut) external returns (uint256) {
    return expectedOut / 10;
  }

  function swapExactIn(address token, address recipient) external payable returns (uint256) {
    return sawpResult;
  }
}

// running tests (with logging on failure):
// yarn workspace @connext/nxtp-contracts test:forge -vvv
// run a single test:
// yarn workspace @connext/nxtp-contracts test:forge -m testAddRouterAlreadyApproved -vvv

// other forge commands: yarn workspace @connext/nxtp-contracts forge <CMD>
// see docs here: https://onbjerg.github.io/foundry-book/index.html

contract SponsorVaultTest is ForgeHelper {
  // ============ Libraries ============
  using stdStorage for StdStorage;

  // ============ Events ============

  event ConnextUpdated(address oldConnext, address newConnext, address caller);
  event RateUpdated(uint32 originDomain, SponsorVault.Rate oldRate, SponsorVault.Rate newRate, address caller);
  event RelayerFeeCapUpdated(uint256 oldRelayerFeeCap, uint256 newRelayerFeeCap, address caller);
  event GasTokenOracleUpdated(address oldOracle, address newOracle, address caller);
  event TokenExchangeUpdated(address token, address oldTokenExchange, address newTokenExchange, address caller);
  event PriceOracleUpdated(address oldOracle, address newOracle, address caller);
  event MaxPriceDiffPercentUpdated(uint256 oldRelayerFeeCap, uint256 newRelayerFeeCap, address caller);
  event Deposit(address token, uint256 amount, address caller);
  event Withdraw(address token, address receiver, uint256 amount, address caller);
  event ReimburseLiquidityFees(address token, uint256 amount, address receiver);
  event ReimburseRelayerFees(uint256 amount, address receiver);

  // ============ Storage ============

  SponsorVault vault;

  address connext = address(this);
  address gasTokenOracle = address(1);
  MockTokenExchange tokenExchange;
  IPriceOracle priceOracle;
  address gasPriceOracle = address(2);
  uint32 originDomain = 1;
  TestERC20 localToken;
  TestERC20 localToken2;

  SponsorVault.Rate rate = SponsorVault.Rate(1, 1);

  receive() external payable {}

  function setUp() public {
    localToken = new TestERC20("Test Token", "TEST");
    localToken2 = new TestERC20("Test Token", "TEST");

    tokenExchange = new MockTokenExchange();

    vault = new SponsorVault(connext);

    priceOracle = IPriceOracle(address(new ConnextPriceOracle(address(1))));
    vault.setPriceOracle(address(priceOracle));

    localToken.approve(address(vault), type(uint256).max);
    localToken2.approve(address(vault), type(uint256).max);

    // fund the vault
    vault.deposit{value: 100 ether}(address(0), 0);
    vault.deposit(address(localToken), 10 ether);
  }

  // ============ Utils ============
  // https://github.com/brockelmore/forge-std
  // specifically here with overriding mappings: https://github.com/brockelmore/forge-std/blob/99107e3e39f27339d224575756d4548c08639bc0/src/test/StdStorage.t.sol#L189-L192

  // ============ constructor ============
  function test_SponsorVault__constructor_failsWithConnextZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(SponsorVault.SponsorVault__setConnext_invalidConnext.selector));

    new SponsorVault(address(0));
  }

  function test_SponsorVault__constructor_works(address _connext) public {
    vm.assume(_connext != address(0));

    vm.expectEmit(true, true, true, true);
    emit ConnextUpdated(address(0), _connext, address(this));

    SponsorVault testVault = new SponsorVault(_connext);

    assertEq(testVault.connext(), _connext);
  }

  // ============ setConnext ============

  function test_SponsorVault__setConnext_failsIfNotOwner() public {
    vm.prank(address(0));
    vm.expectRevert("Ownable: caller is not the owner");

    vault.setConnext(address(2));
  }

  function test_SponsorVault__setConnext_failsWithConnextZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(SponsorVault.SponsorVault__setConnext_invalidConnext.selector));

    vault.setConnext(address(0));
  }

  function test_SponsorVault__setConnext_works(address _connext) public {
    vm.assume(_connext != address(0));

    vm.expectEmit(true, true, true, true);
    emit ConnextUpdated(connext, _connext, address(this));

    vault.setConnext(_connext);

    assertEq(vault.connext(), _connext);
  }

  // ============ setRate ============

  function test_SponsorVault__setRate_failsIfNotOwner() public {
    vm.prank(address(0));
    vm.expectRevert("Ownable: caller is not the owner");

    vault.setRate(1, rate);
  }

  function test_SponsorVault__setRate_failsWithOriginDomainZero() public {
    vm.expectRevert(abi.encodeWithSelector(SponsorVault.SponsorVault__setRate_invalidOriginDomain.selector));

    vault.setRate(0, rate);
  }

  function test_SponsorVault__setRate_works(uint32 _originDomain, SponsorVault.Rate calldata _rate) public {
    vm.assume(_originDomain != 0);

    (uint256 currNum, uint256 currDen) = vault.rates(_originDomain);
    SponsorVault.Rate memory currentRate = SponsorVault.Rate(currNum, currDen);

    vm.expectEmit(true, true, true, true);
    emit RateUpdated(_originDomain, currentRate, _rate, address(this));

    vault.setRate(_originDomain, _rate);

    (uint256 num, uint256 den) = vault.rates(_originDomain);

    assertEq(num, _rate.num);
    assertEq(den, _rate.den);
  }

  // ============ setRelayerFeeCap ============

  function test_SponsorVault__setRelayerFeeCap_failsIfNotOwner() public {
    vm.prank(address(0));
    vm.expectRevert("Ownable: caller is not the owner");

    vault.setRelayerFeeCap(1);
  }

  function test_SponsorVault__setRelayerFeeCap_works(uint256 _relayerFeeCap) public {
    uint256 currRelayerFeeCap = vault.relayerFeeCap();

    vm.expectEmit(true, true, true, true);
    emit RelayerFeeCapUpdated(currRelayerFeeCap, _relayerFeeCap, address(this));

    vault.setRelayerFeeCap(_relayerFeeCap);

    assertEq(vault.relayerFeeCap(), _relayerFeeCap);
  }

  // ============ setGasTokenOracle ============

  function test_SponsorVault__setGasTokenOracle_failsIfNotOwner() public {
    vm.prank(address(0));
    vm.expectRevert("Ownable: caller is not the owner");

    vault.setGasTokenOracle(address(1));
  }

  function test_SponsorVault__setGasTokenOracle_works(address _gasTokenOracle) public {
    address currOracle = address(vault.gasTokenOracle());

    vm.expectEmit(true, true, true, true);
    emit GasTokenOracleUpdated(currOracle, _gasTokenOracle, address(this));

    vault.setGasTokenOracle(_gasTokenOracle);

    assertEq(address(vault.gasTokenOracle()), _gasTokenOracle);
  }

  // ============ setTokenExchange ============

  function test_SponsorVault__setTokenExchange_failsIfNotOwner() public {
    vm.prank(address(0));
    vm.expectRevert("Ownable: caller is not the owner");

    vault.setTokenExchange(address(2), payable(address(tokenExchange)));
  }

  function test_SponsorVault__setTokenExchange_failsWithConnextZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(SponsorVault.SponsorVault__setTokenExchange_invalidAdopted.selector));

    vault.setTokenExchange(address(0), payable(address(tokenExchange)));
  }

  function test_SponsorVault__setTokenExchange_works(address _token, address payable _tokenExchange) public {
    vm.assume(_token != address(0));

    address currTokenExchange = address(vault.tokenExchanges(_token));

    vm.expectEmit(true, true, true, true);
    emit TokenExchangeUpdated(_token, currTokenExchange, _tokenExchange, address(this));

    vault.setTokenExchange(_token, _tokenExchange);

    assertEq(address(vault.tokenExchanges(_token)), _tokenExchange);
  }

  // ============ setPriceOracle ============

  function test_SponsorVault__setPriceOracle_failsIfNotOwner() public {
    vm.prank(address(0));
    vm.expectRevert("Ownable: caller is not the owner");

    vault.setPriceOracle(address(3));
  }

  function test_SponsorVault__setPriceOracle_works(address _priceOracle) public {
    address currOracle = address(vault.priceOracle());

    vm.expectEmit(true, true, true, true);
    emit PriceOracleUpdated(currOracle, _priceOracle, address(this));

    vault.setPriceOracle(_priceOracle);

    assertEq(address(vault.priceOracle()), _priceOracle);
  }

  // ============ setMaxPriceDiffPercent ============

  function test_SponsorVault__setMaxPriceDiffPercent_failsIfNotOwner() public {
    vm.prank(address(0));
    vm.expectRevert("Ownable: caller is not the owner");

    vault.setMaxPriceDiffPercent(1);
  }

  function test_SponsorVault__setMaxPriceDiffPercent_failsIfTooLarge() public {
    vm.expectRevert(abi.encodeWithSelector(SponsorVault.SponsorVault__setMaxPriceDiffPercent_tooLarge.selector));

    vault.setMaxPriceDiffPercent(50);
  }

  function test_SponsorVault__setMaxPriceDiffPercent_works(uint256 _maxPriceDiffPercent) public {
    vm.assume(_maxPriceDiffPercent < 30);
    uint256 currMaxPriceDiffPercent = vault.maxPriceDiffPercent();

    vm.expectEmit(true, true, true, true);
    emit MaxPriceDiffPercentUpdated(currMaxPriceDiffPercent, _maxPriceDiffPercent, address(this));

    vault.setMaxPriceDiffPercent(_maxPriceDiffPercent);

    assertEq(vault.maxPriceDiffPercent(), _maxPriceDiffPercent);
  }

  // ============ deposit ============
  function test_SponsorVault__deposit_works_adding_native_token(uint256 _amount) public {
    vm.assume(address(this).balance >= _amount);
    vm.assume(_amount > 0);

    uint256 balanceBefore = address(vault).balance;

    vm.expectEmit(true, true, true, true);
    emit Deposit(address(0), _amount, address(this));

    vault.deposit{value: _amount}(address(0), 0);

    assertEq(address(vault).balance, balanceBefore + _amount);
  }

  function test_SponsorVault__deposit_works_adding_ERC20_token(uint256 _amount) public {
    TestERC20 someToken = new TestERC20("Test Token", "TEST");
    vm.assume(someToken.balanceOf(address(this)) >= _amount);

    uint256 balanceBefore = someToken.balanceOf(address(vault));

    someToken.approve(address(vault), 1);

    vm.expectEmit(true, true, true, true);
    emit Deposit(address(someToken), 1, address(this));

    vault.deposit(address(someToken), 1);

    assertEq(someToken.balanceOf(address(vault)), balanceBefore + 1);
  }

  // ============ withdraw ============

  function test_SponsorVault__withdraw_failsIfNotOwner() public {
    vm.prank(address(0));
    vm.expectRevert("Ownable: caller is not the owner");

    vault.withdraw(address(0), address(this), 1);
  }

  function test_SponsorVault__withdraw_fails_removing_more_than_owned() public {
    uint256 balance = address(vault).balance;

    vm.expectRevert(abi.encodeWithSelector(SponsorVault.SponsorVault__withdraw_invalidAmount.selector));

    vault.withdraw(address(0), address(this), balance + 1);
  }

  function test_SponsorVault__withdraw_works_removing_native_token(uint256 _amount) public {
    vm.assume(address(vault).balance >= _amount);

    uint256 balanceThisBefore = address(this).balance;
    uint256 balanceVaultBefore = address(vault).balance;

    vm.expectEmit(true, true, true, true);
    emit Withdraw(address(0), address(this), _amount, address(this));

    vault.withdraw(address(0), address(this), _amount);

    assertEq(address(this).balance, balanceThisBefore + _amount);
    assertEq(address(vault).balance, balanceVaultBefore - _amount);
  }

  function test_SponsorVault__withdraw_works_removing_ERC20_token(uint256 _amount) public {
    TestERC20 someToken = new TestERC20("Test Token", "TEST");
    someToken.approve(address(vault), someToken.balanceOf(address(this)));
    vault.deposit(address(someToken), someToken.balanceOf(address(this)));

    uint256 balanceThisBefore = someToken.balanceOf(address(this));
    uint256 balanceVaultBefore = someToken.balanceOf(address(vault));
    vm.assume(balanceVaultBefore >= _amount);

    vm.expectEmit(true, true, true, true);
    emit Withdraw(address(someToken), address(this), _amount, address(this));

    vault.withdraw(address(someToken), address(this), _amount);

    assertEq(someToken.balanceOf(address(vault)), balanceVaultBefore - _amount);
    assertEq(someToken.balanceOf(address(this)), balanceThisBefore + _amount);
  }

  // ============ reimburseLiquidityFees ============

  function test_SponsorVault__reimburseLiquidityFees_failsIfNotConnext() public {
    vm.prank(address(0));
    vm.expectRevert(abi.encodeWithSelector(SponsorVault.SponsorVault__onlyConnext.selector));

    vault.reimburseLiquidityFees(address(1), 1, address(1));
  }

  function test_SponsorVault__reimburseLiquidityFees_returns_0_if_no_tokenExchanges_and_no_token_balance() public {
    assertEq(address(vault.tokenExchanges(address(1))), address(0));
    assertEq(localToken2.balanceOf(address(vault)), 0);

    uint256 balanceBefore = address(vault).balance;

    vm.expectEmit(true, true, true, true);
    emit ReimburseLiquidityFees(address(localToken2), 0, address(1));

    uint256 sponsored = vault.reimburseLiquidityFees(address(localToken2), 1, address(1));

    assertEq(sponsored, 0);
    assertEq(address(vault).balance, balanceBefore);
  }

  function test_SponsorVault__reimburseLiquidityFees_returns_should_work_with_tokenExchange_swap_balance_when_no_enough_native_token_to_cover_all_required_in()
    public
  {
    tokenExchange.setSwapResult(1);
    vault.setTokenExchange(address(localToken), payable(address(tokenExchange)));
    vault.setLiquidityFeeCap(address(localToken), 1 ether);

    uint256 balanceBefore = address(vault).balance;

    vm.mockCall(
      address(tokenExchange),
      abi.encodeWithSelector(ITokenExchange.getInGivenExpectedOut.selector),
      abi.encode(uint256(balanceBefore + 1))
    );
    vm.mockCall(
      address(priceOracle),
      abi.encodeWithSelector(IPriceOracle.getPriceFromChainlink.selector, address(0)),
      abi.encode(10)
    );
    vm.mockCall(
      address(priceOracle),
      abi.encodeWithSelector(IPriceOracle.getPriceFromChainlink.selector, address(localToken)),
      abi.encode(1)
    );

    vm.expectEmit(true, true, true, true);
    emit ReimburseLiquidityFees(address(localToken), 1, address(1));

    uint256 sponsored = vault.reimburseLiquidityFees(address(localToken), 10, address(1));

    assertEq(sponsored, 1);
    assertEq(address(vault).balance, 0);
  }

  function test_SponsorVault__reimburseLiquidityFees_should_work_with_tokenExchange_swap_amount_required_amount_of_native_token()
    public
  {
    uint256 liquidityFee = 500;
    tokenExchange.setSwapResult(500);
    vault.setLiquidityFeeCap(address(localToken), 1 ether);
    uint256 amountIn = tokenExchange.getInGivenExpectedOut(address(localToken), liquidityFee);

    vault.setTokenExchange(address(localToken), payable(address(tokenExchange)));

    uint256 balanceBefore = address(vault).balance;

    vm.expectCall(
      address(tokenExchange),
      abi.encodeWithSelector(ITokenExchange.swapExactIn.selector, address(localToken), address(this))
    );
    vm.mockCall(
      address(priceOracle),
      abi.encodeWithSelector(IPriceOracle.getPriceFromChainlink.selector, address(0)),
      abi.encode(98)
    );
    vm.mockCall(
      address(priceOracle),
      abi.encodeWithSelector(IPriceOracle.getPriceFromChainlink.selector, address(localToken)),
      abi.encode(10)
    );

    vm.expectEmit(true, true, true, true);
    emit ReimburseLiquidityFees(address(localToken), liquidityFee, address(1));

    uint256 sponsored = vault.reimburseLiquidityFees(address(localToken), liquidityFee, address(1));

    assertEq(sponsored, liquidityFee);
    assertEq(address(vault).balance, balanceBefore - amountIn);
  }

  function test_SponsorVault__reimburseLiquidityFees_should_work_with_tokenExchange_sponsored_less_than_liquidityFee_due_to_slippage()
    public
  {
    uint256 liquidityFee = 500;
    tokenExchange.setSwapResult(500 - 5);
    vault.setLiquidityFeeCap(address(localToken), 1 ether);
    uint256 amountIn = tokenExchange.getInGivenExpectedOut(address(localToken), liquidityFee);

    vault.setTokenExchange(address(localToken), payable(address(tokenExchange)));

    uint256 balanceBefore = address(vault).balance;

    vm.expectCall(
      address(tokenExchange),
      abi.encodeWithSelector(ITokenExchange.swapExactIn.selector, address(localToken), address(this))
    );

    vm.mockCall(
      address(priceOracle),
      abi.encodeWithSelector(IPriceOracle.getPriceFromChainlink.selector, address(0)),
      abi.encode(98)
    );
    vm.mockCall(
      address(priceOracle),
      abi.encodeWithSelector(IPriceOracle.getPriceFromChainlink.selector, address(localToken)),
      abi.encode(10)
    );

    vm.expectEmit(true, true, true, true);
    emit ReimburseLiquidityFees(address(localToken), liquidityFee - 5, address(1));

    uint256 sponsored = vault.reimburseLiquidityFees(address(localToken), liquidityFee, address(1));

    assertEq(sponsored, liquidityFee - 5);
    assertEq(address(vault).balance, balanceBefore - amountIn);
  }

  function test_SponsorVault__reimburseLiquidityFees_should_work_with_no_tokenExchange_but_token_balance() public {
    uint256 liquidityFee = 500;
    vault.setLiquidityFeeCap(address(localToken), 1 ether);

    assertEq(address(vault.tokenExchanges(address(1))), address(0));

    uint256 balanceBefore = address(vault).balance;
    uint256 balanceLocalBefore = localToken.balanceOf(address(vault));

    vm.expectEmit(true, true, true, true);
    emit ReimburseLiquidityFees(address(localToken), liquidityFee, address(1));

    uint256 sponsored = vault.reimburseLiquidityFees(address(localToken), liquidityFee, address(1));

    assertEq(sponsored, liquidityFee);
    assertEq(address(vault).balance, balanceBefore);
    assertEq(localToken.balanceOf(address(vault)), balanceLocalBefore - liquidityFee);
  }

  function test_SponsorVault__reimburseLiquidityFees_should_work_with_no_tokenExchange_but_token_balance_sending_available_amount_if_no_enough()
    public
  {
    uint256 balanceLocalBefore = localToken.balanceOf(address(vault));
    uint256 liquidityFee = balanceLocalBefore + 10;
    vault.setLiquidityFeeCap(address(localToken), 100 ether);

    assertEq(address(vault.tokenExchanges(address(1))), address(0));

    uint256 balanceBefore = address(vault).balance;

    vm.expectEmit(true, true, true, true);
    emit ReimburseLiquidityFees(address(localToken), balanceLocalBefore, address(1));

    uint256 sponsored = vault.reimburseLiquidityFees(address(localToken), liquidityFee, address(1));

    assertEq(sponsored, balanceLocalBefore);
    assertEq(address(vault).balance, balanceBefore);
    assertEq(localToken.balanceOf(address(vault)), 0);
  }

  function test_SponsorVault__reimburseLiquidityFees_onlyReimbursesToMax() public {
    uint256 balanceLocalBefore = localToken.balanceOf(address(vault));
    uint256 liquidityFee = balanceLocalBefore + 10;
    uint256 liquidityCap = 2;
    vault.setLiquidityFeeCap(address(localToken), liquidityCap);

    assertEq(address(vault.tokenExchanges(address(1))), address(0));

    uint256 balanceBefore = address(vault).balance;

    vm.expectEmit(true, true, true, true);
    emit ReimburseLiquidityFees(address(localToken), liquidityCap, address(1));

    uint256 sponsored = vault.reimburseLiquidityFees(address(localToken), liquidityFee, address(1));

    assertEq(sponsored, liquidityCap);
    assertEq(address(vault).balance, balanceBefore);
    assertEq(localToken.balanceOf(address(vault)), balanceLocalBefore - liquidityCap);
    assertEq(vault.reimbursedLiquidityFees(address(1), address(localToken)), liquidityCap);
  }

  // ============ reimburseRelayerFees ============

  function test_SponsorVault__reimburseRelayerFees_failsIfNotConnext() public {
    vm.prank(address(0));
    vm.expectRevert(abi.encodeWithSelector(SponsorVault.SponsorVault__onlyConnext.selector));

    vault.reimburseRelayerFees(originDomain, payable(address(this)), 1);
  }

  function test_SponsorVault__reimburseRelayerFees_should_not_sponsor_fee_when_no_gasTokenOracle_nor_rate() public {
    assertEq(address(vault.gasTokenOracle()), address(0));

    (uint256 num, uint256 den) = vault.rates(originDomain);
    assertEq(num, 0);
    assertEq(den, 0);

    uint256 relayerFeeCap = 1000;
    uint256 relayerFee = 500;
    address to = address(10);

    vault.setRelayerFeeCap(relayerFeeCap);

    uint256 balanceBefore = to.balance;

    vm.expectEmit(true, true, true, true);
    emit ReimburseRelayerFees(0, to);

    vault.reimburseRelayerFees(originDomain, payable(to), relayerFee);

    assertEq(to.balance, balanceBefore);
  }

  function test_SponsorVault__reimburseRelayerFees_should_use_rate_when_no_gasTokenOracle_is_set() public {
    SponsorVault.Rate memory _rate = SponsorVault.Rate({num: 1, den: 2});
    uint256 relayerFeeCap = 1000;
    uint256 relayerFee = 500;
    address to = address(10);

    vault.setRelayerFeeCap(relayerFeeCap);
    vault.setRate(originDomain, _rate);

    uint256 balanceBefore = to.balance;

    uint256 expectedFee = ((relayerFee * _rate.num) / _rate.den);

    vm.expectEmit(true, true, true, true);
    emit ReimburseRelayerFees(expectedFee, to);

    vault.reimburseRelayerFees(originDomain, payable(to), relayerFee);

    assertEq(to.balance, balanceBefore + expectedFee);
  }

  function test_SponsorVault__reimburseRelayerFees_should_use_rate_when_no_gasTokenOracle_is_set_partially_sponsoring_the_fee_when_no_enough_balance()
    public
  {
    SponsorVault.Rate memory _rate = SponsorVault.Rate({num: 1, den: 1});
    uint256 initialVaultBalance = address(vault).balance;
    uint256 relayerFeeCap = initialVaultBalance * 2;
    uint256 relayerFee = initialVaultBalance + 10;
    address to = address(10);

    vault.setRelayerFeeCap(relayerFeeCap);
    vault.setRate(originDomain, _rate);

    uint256 balanceBefore = to.balance;

    vm.expectEmit(true, true, true, true);
    emit ReimburseRelayerFees(initialVaultBalance, to);

    vault.reimburseRelayerFees(originDomain, payable(to), relayerFee);

    assertEq(to.balance, balanceBefore + initialVaultBalance);
  }

  function test_SponsorVault__reimburseRelayerFees_should_return_relayerFeeCap_if_fee_is_to_high() public {
    SponsorVault.Rate memory _rate = SponsorVault.Rate({num: 1, den: 2});
    uint256 relayerFeeCap = 1000;
    uint256 relayerFee = 3000;
    address to = address(10);

    vault.setRelayerFeeCap(relayerFeeCap);
    vault.setRate(originDomain, _rate);

    uint256 balanceBefore = to.balance;

    vm.expectEmit(true, true, true, true);
    emit ReimburseRelayerFees(relayerFeeCap, to);

    vault.reimburseRelayerFees(originDomain, payable(to), relayerFee);

    assertEq(to.balance, balanceBefore + relayerFeeCap);
  }

  function test_SponsorVault__reimburseRelayerFees_should_use_gasTokenOracle_rate() public {
    SponsorVault.Rate memory _rate = SponsorVault.Rate({num: 1, den: 2});

    uint256 relayerFeeCap = 1000;
    uint256 relayerFee = 500;
    address to = address(10);

    vault.setRelayerFeeCap(relayerFeeCap);
    vault.setRate(originDomain, _rate);
    vault.setGasTokenOracle(gasTokenOracle);

    uint256 balanceBefore = to.balance;

    SponsorVault.Rate memory gasTokenOracleRate = SponsorVault.Rate({num: 1, den: 3});

    vm.mockCall(
      address(gasTokenOracle),
      abi.encodeWithSelector(IGasTokenOracle.getRate.selector),
      abi.encode(gasTokenOracleRate)
    );

    vm.expectCall(address(gasTokenOracle), abi.encodeWithSelector(IGasTokenOracle.getRate.selector, originDomain));

    uint256 expectedFee = ((relayerFee * gasTokenOracleRate.num) / gasTokenOracleRate.den);

    vm.expectEmit(true, true, true, true);
    emit ReimburseRelayerFees(expectedFee, to);

    vault.reimburseRelayerFees(originDomain, payable(to), relayerFee);

    assertEq(to.balance, balanceBefore + expectedFee);
  }

  function test_SponsorVault__reimburseRelayerFees_shouldHandleBadGasOracle() public {
    uint256 relayerFeeCap = 1000;
    uint256 relayerFee = 500;
    address to = address(10);

    vault.setRelayerFeeCap(relayerFeeCap);
    vault.setGasTokenOracle(gasTokenOracle);

    uint256 balanceBefore = to.balance;

    SponsorVault.Rate memory gasTokenOracleRate = SponsorVault.Rate({num: 1, den: 0});

    vm.mockCall(
      address(gasTokenOracle),
      abi.encodeWithSelector(IGasTokenOracle.getRate.selector),
      abi.encode(gasTokenOracleRate)
    );

    vm.expectCall(address(gasTokenOracle), abi.encodeWithSelector(IGasTokenOracle.getRate.selector, originDomain));

    uint256 expectedFee = 0;

    vm.expectEmit(true, true, true, true);
    emit ReimburseRelayerFees(expectedFee, to);

    vault.reimburseRelayerFees(originDomain, payable(to), relayerFee);

    assertEq(to.balance, balanceBefore + expectedFee);
  }

  function test_SponsorVault__reimburseRelayerFees_should_use_gasTokenOracle_rate_but_return_relayerFeeCap_when_fee_is_to_high()
    public
  {
    SponsorVault.Rate memory _rate = SponsorVault.Rate({num: 1, den: 2});

    uint256 relayerFeeCap = 1000;
    uint256 relayerFee = 3300;
    address to = address(10);

    vault.setRelayerFeeCap(relayerFeeCap);
    vault.setRate(originDomain, _rate);
    vault.setGasTokenOracle(gasTokenOracle);

    uint256 balanceBefore = to.balance;

    SponsorVault.Rate memory gasTokenOracleRate = SponsorVault.Rate({num: 1, den: 3});

    vm.mockCall(
      address(gasTokenOracle),
      abi.encodeWithSelector(IGasTokenOracle.getRate.selector),
      abi.encode(gasTokenOracleRate)
    );

    vm.expectCall(address(gasTokenOracle), abi.encodeWithSelector(IGasTokenOracle.getRate.selector, originDomain));

    vm.expectEmit(true, true, true, true);
    emit ReimburseRelayerFees(relayerFeeCap, to);

    vault.reimburseRelayerFees(originDomain, payable(to), relayerFee);

    assertEq(to.balance, balanceBefore + relayerFeeCap);
  }

  function test_SponsorVault__reimburseRelayerFees_should_use_gasTokenOracle_rate_partially_sponsoring_the_fee_when_no_enough_balance()
    public
  {
    SponsorVault.Rate memory _rate = SponsorVault.Rate({num: 1, den: 2});

    address to = address(10);
    uint256 balanceBefore = to.balance;
    uint256 initialVaultBalance = address(vault).balance;
    uint256 relayerFeeCap = initialVaultBalance * 2;
    uint256 relayerFee = initialVaultBalance + 10;

    vault.setRelayerFeeCap(relayerFeeCap);
    vault.setRate(originDomain, _rate);
    vault.setGasTokenOracle(gasTokenOracle);

    SponsorVault.Rate memory gasTokenOracleRate = SponsorVault.Rate({num: 1, den: 1});

    vm.mockCall(
      address(gasTokenOracle),
      abi.encodeWithSelector(IGasTokenOracle.getRate.selector),
      abi.encode(gasTokenOracleRate)
    );

    vm.expectCall(address(gasTokenOracle), abi.encodeWithSelector(IGasTokenOracle.getRate.selector, originDomain));

    vm.expectEmit(true, true, true, true);
    emit ReimburseRelayerFees(initialVaultBalance, to);

    vault.reimburseRelayerFees(originDomain, payable(to), relayerFee);

    assertEq(to.balance, balanceBefore + initialVaultBalance);
  }
}
