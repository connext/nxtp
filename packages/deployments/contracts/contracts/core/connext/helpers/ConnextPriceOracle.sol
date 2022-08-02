// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20Extended} from "../interfaces/IERC20Extended.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

import {ProposedOwnable} from "../../shared/ProposedOwnable.sol";
import {PriceOracle} from "./PriceOracle.sol";

interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  // getRoundData and latestRoundData should both raise "No data present"
  // if they do not have data to report, instead of returning unset values
  // which could be misinterpreted as actual reported values.
  function getRoundData(uint80 _roundId)
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

contract ConnextPriceOracle is PriceOracle, ProposedOwnable {
  using SafeERC20 for IERC20Extended;

  address public wrapped;
  address public v1PriceOracle;

  uint256 public constant VALID_PERIOD = 1 minutes;

  /// @notice Price sources
  enum PriceSource {
    NA,
    DIRECT,
    CHAINLINK,
    DEX,
    V1_ORACLE
  }

  /// @notice Chainlink Aggregators
  mapping(address => AggregatorV3Interface) public aggregators;

  struct Price {
    uint256 updatedAt;
    uint256 price;
  }

  mapping(address => Price) public assetPrices;

  event NewAdmin(address oldAdmin, address newAdmin);
  event PriceRecordUpdated(address token, address baseToken, address lpToken, bool _active);
  event DirectPriceUpdated(address token, uint256 oldPrice, uint256 newPrice);
  event AggregatorUpdated(address tokenAddress, address source);
  event V1PriceOracleUpdated(address oldAddress, address newAddress);

  constructor(address _wrapped) {
    wrapped = _wrapped;
    _setOwner(msg.sender);
  }

  function getTokenPrice(address _tokenAddress) public view override returns (uint256, uint256) {
    address tokenAddress = _tokenAddress;
    PriceSource source = PriceSource.NA;

    if (_tokenAddress == address(0)) {
      tokenAddress = wrapped;
    }
    uint256 tokenPrice = assetPrices[tokenAddress].price;
    if (tokenPrice != 0 && ((block.timestamp - assetPrices[tokenAddress].updatedAt) <= VALID_PERIOD)) {
      return (tokenPrice, uint256(PriceSource.DIRECT));
    } else {
      tokenPrice = 0;
    }

    if (tokenPrice == 0) {
      tokenPrice = getPriceFromOracle(tokenAddress);
      source = PriceSource.CHAINLINK;
    }
    if (tokenPrice == 0 && v1PriceOracle != address(0)) {
      tokenPrice = IPriceOracle(v1PriceOracle).getTokenPrice(tokenAddress);
      source = PriceSource.V1_ORACLE;
    }

    return (tokenPrice, uint256(source));
  }

  function getPriceFromOracle(address _tokenAddress) public view returns (uint256) {
    uint256 chainLinkPrice = getPriceFromChainlink(_tokenAddress);
    return chainLinkPrice;
  }

  function getPriceFromChainlink(address _tokenAddress) public view returns (uint256) {
    AggregatorV3Interface aggregator = aggregators[_tokenAddress];
    if (address(aggregator) != address(0)) {
      try aggregator.latestRoundData() returns (
        uint80 roundId,
        int256 answer,
        uint256,
        uint256 updateAt,
        uint80 answeredInRound
      ) {
        // It's fine for price to be 0. We have more price feeds.
        if (answer == 0 || answeredInRound < roundId || updateAt == 0 || block.timestamp > updateAt + VALID_PERIOD) {
          // answeredInRound > roundId ===> ChainLink Error: Stale price
          // updatedAt = 0 ===> ChainLink Error: Round not complete
          // block.timestamp - updateAt > VALID_PERIOD ===> too old data
          return 0;
        }

        uint256 retVal = uint256(answer);
        uint256 price;
        // Make the decimals to 1e18.
        uint256 aggregatorDecimals = uint256(aggregator.decimals());
        if (aggregatorDecimals > 18) {
          price = retVal / (10**(aggregatorDecimals - 18));
        } else {
          price = retVal * (10**(18 - aggregatorDecimals));
        }

        return price;
      } catch {
        // return 0 to be able to fetch the price from next oracles
        return 0;
      }
    }

    return 0;
  }

  function setDirectPrice(
    address _token,
    uint256 _price,
    uint256 _timestamp
  ) external onlyOwner {
    require(_price != 0, "bad price");
    if (block.timestamp > _timestamp) {
      // reject stale price
      require(block.timestamp - _timestamp < VALID_PERIOD, "bad timestamp");
    } else {
      // reject future timestamp (<3s is allowed)
      require(_timestamp - block.timestamp < 3, "in future");
      _timestamp = block.timestamp;
    }

    emit DirectPriceUpdated(_token, assetPrices[_token].price, _price);

    assetPrices[_token].price = _price;
    assetPrices[_token].updatedAt = _timestamp;
  }

  function setV1PriceOracle(address _v1PriceOracle) external onlyOwner {
    emit V1PriceOracleUpdated(v1PriceOracle, _v1PriceOracle);
    v1PriceOracle = _v1PriceOracle;
  }

  function setAggregators(address[] calldata tokenAddresses, address[] calldata sources) external onlyOwner {
    uint256 numTokens = tokenAddresses.length;
    for (uint256 i; i < numTokens; ) {
      aggregators[tokenAddresses[i]] = AggregatorV3Interface(sources[i]);
      emit AggregatorUpdated(tokenAddresses[i], sources[i]);

      unchecked {
        ++i;
      }
    }
  }
}
