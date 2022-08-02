// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, Address} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {ISponsorVault} from "../interfaces/ISponsorVault.sol";
import {ITokenExchange} from "../interfaces/ITokenExchange.sol";
import {IGasTokenOracle} from "../interfaces/IGasTokenOracle.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IERC20Extended} from "../interfaces/IERC20Extended.sol";

/**
 * @title SponsorVault
 * @author Connext Labs
 * @notice Contains logic for sponsoring liquidity and relayer fees
 */
contract SponsorVault is ISponsorVault, ReentrancyGuard, Ownable {
  // ============ Libraries ============
  using SafeERC20 for IERC20;

  // ============ Struct ============
  struct Rate {
    uint256 num;
    uint256 den;
  }

  // ============ Private storage ============

  // ============ Public storage ============

  /**
   * @notice The address of connext
   */
  address public connext;

  /**
   * @notice The origin domain to this domain native token rates
   * @dev Used when no oracle is available
   */
  mapping(uint32 => Rate) public rates;

  /**
   * @notice Tracks the total liquidity fees reimbursed to this address for the asset
   * @dev Used to prevent the same address from repeatedly claiming up to the cap
   */
  mapping(address => mapping(address => uint256)) public reimbursedLiquidityFees;

  /**
   * @notice The maximum amount this domain native token to be sponsored for relayer fee
   */
  uint256 public relayerFeeCap;

  /**
   * @notice The maximum amount to be sponsored for liquidity fee of a given asset
   * @dev Caps should be set by asset
   */
  mapping(address => uint256) public liquidityFeeCaps;

  /**
   * @notice The origin domain to this domain native token oracle
   * @dev Used to calculate sponsored relayer fee
   */
  IGasTokenOracle public gasTokenOracle;

  /**
   * @notice The ChainLink Oracle
   * @dev Used to check if the dex spot price is valid to prevent manipulate
   */
  IPriceOracle public priceOracle;

  /**
   * @notice The this domain native token to token exchange
   * @dev Used to exchange this domain native token to the token used to pay liquidity fees
   */
  mapping(address => ITokenExchange) public tokenExchanges;

  /**
   * @notice The maximum percentage which dex spot price is allowed to be higher than the oracle price
   */
  uint256 public maxPriceDiffPercent;

  // ============ Errors ============

  error SponsorVault__setConnext_invalidConnext();
  error SponsorVault__setRate_invalidOriginDomain();
  error SponsorVault__setGasTokenOracle_invalidOriginDomain();
  error SponsorVault__setTokenExchange_invalidAdopted();
  error SponsorVault__setMaxPriceDiffPercent_tooLarge();
  error SponsorVault__onlyConnext();
  error SponsorVault__withdraw_invalidAmount();

  // ============ Events ============

  /**
   * @notice Emitted when a new connext is set
   */
  event ConnextUpdated(address oldConnext, address newConnext, address caller);

  /**
   * @notice Emitted when a new rate is set
   */
  event RateUpdated(uint32 originDomain, Rate oldRate, Rate newRate, address caller);

  /**
   * @notice Emitted when a new relayerFeeCap is set
   */
  event RelayerFeeCapUpdated(uint256 oldRelayerFeeCap, uint256 newRelayerFeeCap, address caller);

  /**
   * @notice Emitted when a new liquidityFeeCap is set
   */
  event LiquidityFeeCapUpdated(
    address indexed asset,
    uint256 oldLiquidityFeeCap,
    uint256 newLiquidityFeeCap,
    address caller
  );

  /**
   * @notice Emitted when a new native token oracle is set
   */
  event GasTokenOracleUpdated(address oldOracle, address newOracle, address caller);

  /**
   * @notice Emitted when a new token exchange is set
   */
  event TokenExchangeUpdated(address token, address oldTokenExchange, address newTokenExchange, address caller);

  /**
   * @notice Emitted when a new price oracle is set
   */
  event PriceOracleUpdated(address oldOracle, address newOracle, address caller);

  /**
   * @notice Emitted when a new maxPriceDiffPercent is set
   */
  event MaxPriceDiffPercentUpdated(uint256 oldMaxPriceDiffPercent, uint256 newMaxPriceDiffPercent, address caller);

  /**
   * @notice Emitted when a liquidity fee is reimbursed
   */
  event ReimburseLiquidityFees(address token, uint256 amount, address receiver);

  /**
   * @notice Emitted when a relayer fee is reimbursed
   */
  event ReimburseRelayerFees(uint256 amount, address receiver);

  /**
   * @notice Emitted when liquidity is added
   */
  event Deposit(address token, uint256 amount, address caller);

  /**
   * @notice Emitted when liquidity is removed
   */
  event Withdraw(address token, address receiver, uint256 amount, address caller);

  // ============ Modifiers ============

  /**
   * @notice Restricts the caller to connext
   */
  modifier onlyConnext() {
    if (msg.sender != connext) revert SponsorVault__onlyConnext();
    _;
  }

  // ============ Constructor ============

  constructor(address _connext) Ownable() {
    _setConnext(_connext);

    maxPriceDiffPercent = 5; // default 5%
  }

  // ============ Owner Functions ============

  /**
   * @notice Sets the Connext.
   * @dev Connext and sponsor vault store references to each other
   * @param _connext The address of the Connext implementation
   */
  function setConnext(address _connext) external onlyOwner {
    _setConnext(_connext);
  }

  /**
   * @notice Sets default origin domain native token to this domain native token rate.
   * @param _originDomain The origin domain
   * @param _rate The default rate
   */
  function setRate(uint32 _originDomain, Rate calldata _rate) external onlyOwner {
    if (_originDomain == 0) revert SponsorVault__setRate_invalidOriginDomain();

    emit RateUpdated(_originDomain, rates[_originDomain], _rate, msg.sender);

    rates[_originDomain] = _rate;
  }

  /**
   * @notice Sets the maximum sponsored relayer fee amount.
   * @param _relayerFeeCap The new relayerFeeCap
   */
  function setRelayerFeeCap(uint256 _relayerFeeCap) external onlyOwner {
    emit RelayerFeeCapUpdated(relayerFeeCap, _relayerFeeCap, msg.sender);
    relayerFeeCap = _relayerFeeCap;
  }

  /**
   * @notice Sets the maximum sponsored liquidity fee amount.
   * @param _liquidityFeeCap The new liquidityFeeCap
   */
  function setLiquidityFeeCap(address _asset, uint256 _liquidityFeeCap) external onlyOwner {
    emit LiquidityFeeCapUpdated(_asset, liquidityFeeCaps[_asset], _liquidityFeeCap, msg.sender);
    liquidityFeeCaps[_asset] = _liquidityFeeCap;
  }

  /**
   * @notice Sets of an oracle that provides origin domain native token to this domain native token rates.
   * @param _gasTokenOracle The oracle address
   */
  function setGasTokenOracle(address _gasTokenOracle) external onlyOwner {
    emit GasTokenOracleUpdated(address(gasTokenOracle), _gasTokenOracle, msg.sender);
    gasTokenOracle = IGasTokenOracle(_gasTokenOracle);
  }

  /**
   * @notice Sets the address of an exchange used for swapping this domain native token for a given token.
   * @param _token The address of the token
   * @param _tokenExchange The oracle of the exchange
   */
  function setTokenExchange(address _token, address payable _tokenExchange) external onlyOwner {
    if (_token == address(0)) revert SponsorVault__setTokenExchange_invalidAdopted();

    emit TokenExchangeUpdated(_token, address(tokenExchanges[_token]), _tokenExchange, msg.sender);
    tokenExchanges[_token] = ITokenExchange(_tokenExchange);
  }

  /**
   * @notice Sets of an oracle that provides native token - liquidity fee token price
   * @param _priceOracle The oracle address
   */
  function setPriceOracle(address _priceOracle) external onlyOwner {
    emit PriceOracleUpdated(address(priceOracle), _priceOracle, msg.sender);
    priceOracle = IPriceOracle(_priceOracle);
  }

  /**
   * @notice Sets the maximum price difference percentage
   * @param _maxPriceDiffPercent The new maxPriceDiffPercent
   */
  function setMaxPriceDiffPercent(uint256 _maxPriceDiffPercent) external onlyOwner {
    if (_maxPriceDiffPercent >= 30) revert SponsorVault__setMaxPriceDiffPercent_tooLarge();
    emit MaxPriceDiffPercentUpdated(maxPriceDiffPercent, _maxPriceDiffPercent, msg.sender);
    maxPriceDiffPercent = _maxPriceDiffPercent;
  }

  // ============ External functions ============

  /**
   * @notice Performs liquidity fee reimbursement.
   * @dev Uses the token exchange or liquidity deposited in this contract.
   *      The `_receiver` address is only used for emitting in the event.
   * @param _token The address of the token
   * @param _liquidityFee The liquidity fee amount
   * @param _receiver The address of the receiver
   * @return Sponsored liquidity fee amount
   */
  function reimburseLiquidityFees(
    address _token,
    uint256 _liquidityFee,
    address _receiver
  ) external override onlyConnext nonReentrant returns (uint256) {
    uint256 sponsoredFee;

    // Don't reimburse past the cap for this asset
    uint256 maxReimbursement = liquidityFeeCaps[_token];
    uint256 cumulative = reimbursedLiquidityFees[_receiver][_token];
    if (cumulative >= maxReimbursement) {
      emit ReimburseLiquidityFees(_token, 0, _receiver);
      return 0;
    }

    uint256 available = maxReimbursement - cumulative;
    uint256 toReimburse = available > _liquidityFee ? _liquidityFee : available;

    ITokenExchange tokenExchange = tokenExchanges[_token];
    if (address(tokenExchange) != address(0)) {
      uint256 currentBalance = address(this).balance;

      uint256 amountIn = tokenExchange.getInGivenExpectedOut(_token, toReimburse);

      // compare with spot price and ChainLink oracle price to prevent manipulate
      if (amountIn == 0 || !_checkDexSpotPrice(_token, amountIn, toReimburse)) {
        return 0;
      }

      amountIn = currentBalance >= amountIn ? amountIn : currentBalance;

      // sponsored fee may end being less than _liquidityFee due to slippage. This will swap and transfer to msg.sender
      sponsoredFee = tokenExchange.swapExactIn{value: amountIn}(_token, msg.sender);
    } else {
      uint256 balance = IERC20(_token).balanceOf(address(this));
      sponsoredFee = balance <= toReimburse ? balance : toReimburse;

      // only transfer if it is more than 0
      if (sponsoredFee != 0) {
        IERC20(_token).safeTransfer(msg.sender, sponsoredFee);
      }
    }

    reimbursedLiquidityFees[_receiver][_token] += sponsoredFee;

    emit ReimburseLiquidityFees(_token, sponsoredFee, _receiver);

    return sponsoredFee;
  }

  /**
   * @notice Performs relayer fee reimbursement sending the corresponding amount of this domain native token to `_to`.
   * @dev Uses the configured oracle or default rate otherwise.
   * @param _originDomain The origin domain id
   * @param _to The fee recipient
   * @param _originRelayerFee The relayer fee amount in origin domain native token
   */
  function reimburseRelayerFees(
    uint32 _originDomain,
    address payable _to,
    uint256 _originRelayerFee
  ) external override onlyConnext {
    uint256 sponsoredFee;
    uint256 num;
    uint256 den;

    uint256 destBal = _to.balance;
    if (destBal > relayerFeeCap || Address.isContract(_to)) {
      // Already has fees, and the address is a contract
      return;
    }

    if (address(gasTokenOracle) != address(0)) {
      (num, den) = gasTokenOracle.getRate(_originDomain);

      sponsoredFee = den == 0 ? 0 : (_originRelayerFee * num) / den;
    } else {
      num = rates[_originDomain].num;
      den = rates[_originDomain].den;
    }

    if (den != 0) {
      sponsoredFee = (_originRelayerFee * num) / den;

      // calculated or max
      uint256 remaining = relayerFeeCap - destBal;
      sponsoredFee = sponsoredFee >= remaining ? remaining : sponsoredFee;
      // calculated or leftover
      uint256 balance = address(this).balance;
      sponsoredFee = sponsoredFee >= balance ? balance : sponsoredFee;

      Address.sendValue(_to, sponsoredFee);
    }

    emit ReimburseRelayerFees(sponsoredFee, _to);
  }

  /**
   * @notice Adds liquidity to the sponsor vault, native token or ERC20.
   * @dev Anyone can add liquidity.
   * @param _token The ERC20 token address or address zero for native token
   * @param _amount The amount of ERC20 to deposit or zero for native token since the amount is sent in msg.value
   */
  function deposit(address _token, uint256 _amount) external payable nonReentrant {
    if (_token != address(0)) {
      IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
      emit Deposit(_token, _amount, msg.sender);
    }

    if (msg.value > 0) {
      emit Deposit(address(0), msg.value, msg.sender);
    }
  }

  /**
   * @notice Removes liquidity from the sponsor vault, native token or ERC20.
   * @dev Only the owner can remove liquidity.
   * @param _token The ERC20 token address or address zero for native token
   * @param _receiver The receiver of the tokens
   * @param _amount The amount to remove
   */
  function withdraw(
    address _token,
    address _receiver,
    uint256 _amount
  ) external onlyOwner nonReentrant {
    if (_token == address(0)) {
      if (address(this).balance < _amount) revert SponsorVault__withdraw_invalidAmount();
      Address.sendValue(payable(_receiver), _amount);
    } else {
      if (IERC20(_token).balanceOf(address(this)) < _amount) revert SponsorVault__withdraw_invalidAmount();
      IERC20(_token).safeTransfer(_receiver, _amount);
    }

    emit Withdraw(_token, _receiver, _amount, msg.sender);
  }

  // ============ Internal functions ============

  function _setConnext(address _connext) internal {
    if (_connext == address(0)) revert SponsorVault__setConnext_invalidConnext();

    emit ConnextUpdated(connext, _connext, msg.sender);

    connext = _connext;
  }

  /**
   * @notice Compare dex spot price and ChainLink oracle price to prevent manipulate
   * @dev First fetch the price of the Native token and liquidity fee token from chainlink oracle.
   *      If the aggregator of them not exist, return `false`
   *      Compare (native_price_oracle / token_price_oracle) ~ (token_amount / eth_amount) = (native_price_dex / token_price_dex)
   * @param _token The ERC20 token address of liquidity fee
   * @param _ethAmount The amount of native token which got from `getInGivenExpectedOut`
   * @param _tokenAmount The amount of liquidity fee to reimburse
   */
  function _checkDexSpotPrice(
    address _token,
    uint256 _ethAmount,
    uint256 _tokenAmount
  ) internal view returns (bool) {
    uint256 ethPrice = priceOracle.getPriceFromChainlink(address(0));
    if (ethPrice == 0) {
      return false;
    }

    uint256 tokenPrice = priceOracle.getPriceFromChainlink(_token);
    if (tokenPrice == 0) {
      return false;
    }

    uint256 decimals = IERC20Extended(_token).decimals();
    if (
      (((ethPrice * 1e18) / tokenPrice) * (100 + maxPriceDiffPercent)) / 100 <
      ((_tokenAmount * (10**(36 - decimals))) / _ethAmount)
    ) {
      return false;
    }
    return true;
  }
}
