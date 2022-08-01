// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.15;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {Version0} from "../nomad-core/contracts/Version0.sol";
import {TypeCasts} from "../nomad-core/contracts/XAppConnectionManager.sol";

import {ERC20} from "./OZERC20.sol";
import {BridgeMessage} from "./BridgeMessage.sol";
import {IBridgeToken} from "./IBridgeToken.sol";

contract BridgeToken is Version0, IBridgeToken, OwnableUpgradeable, ERC20 {
  // ============ Immutables ============

  // Immutables used in EIP 712 structured data hashing & signing
  // https://eips.ethereum.org/EIPS/eip-712
  bytes32 public immutable _PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
  bytes32 private immutable _EIP712_STRUCTURED_DATA_VERSION = keccak256(bytes("1"));
  uint16 private immutable _EIP712_PREFIX_AND_VERSION = uint16(0x1901);

  // ============ Public Storage ============

  mapping(address => uint256) public nonces;
  /// @dev hash commitment to the name/symbol/decimals
  bytes32 public override detailsHash;

  // ============ Upgrade Gap ============

  uint256[48] private __GAP; // gap for upgrade safety

  // ============ Initializer ============

  function initialize() public override initializer {
    __Ownable_init();
  }

  // ============ Events ============

  event UpdateDetails(string indexed name, string indexed symbol, uint8 indexed decimals);

  // ============ External Functions ============

  /**
   * @notice Destroys `_amnt` tokens from `_from`, reducing the
   * total supply.
   * @dev Emits a {Transfer} event with `to` set to the zero address.
   * Requirements:
   * - `_from` cannot be the zero address.
   * - `_from` must have at least `_amnt` tokens.
   * @param _from The address from which to destroy the tokens
   * @param _amnt The amount of tokens to be destroyed
   */
  function burn(address _from, uint256 _amnt) external override onlyOwner {
    _burn(_from, _amnt);
  }

  /** @notice Creates `_amnt` tokens and assigns them to `_to`, increasing
   * the total supply.
   * @dev Emits a {Transfer} event with `from` set to the zero address.
   * Requirements:
   * - `to` cannot be the zero address.
   * @param _to The destination address
   * @param _amnt The amount of tokens to be minted
   */
  function mint(address _to, uint256 _amnt) external override onlyOwner {
    _mint(_to, _amnt);
  }

  /** @notice allows the owner to set the details hash commitment.
   * @param _detailsHash the new details hash.
   */
  function setDetailsHash(bytes32 _detailsHash) external override onlyOwner {
    if (detailsHash != _detailsHash) {
      detailsHash = _detailsHash;
    }
  }

  /**
   * @notice Set the details of a token
   * @param _newName The new name
   * @param _newSymbol The new symbol
   * @param _newDecimals The new decimals
   */
  function setDetails(
    string calldata _newName,
    string calldata _newSymbol,
    uint8 _newDecimals
  ) external override {
    bool _isFirstDetails = bytes(token.name).length == 0;
    // 0 case is the initial deploy. We allow the deploying registry to set
    // these once. After the first transfer is made, detailsHash will be
    // set, allowing anyone to supply correct name/symbols/decimals
    require(
      _isFirstDetails || BridgeMessage.getDetailsHash(_newName, _newSymbol, _newDecimals) == detailsHash,
      "!committed details"
    );
    // careful with naming convention change here
    token.name = _newName;
    token.symbol = _newSymbol;
    token.decimals = _newDecimals;
    if (!_isFirstDetails) {
      emit UpdateDetails(_newName, _newSymbol, _newDecimals);
    }
  }

  /**
   * @notice Sets approval from owner to spender to value
   * as long as deadline has not passed
   * by submitting a valid signature from owner
   * Uses EIP 712 structured data hashing & signing
   * https://eips.ethereum.org/EIPS/eip-712
   * @param _owner The account setting approval & signing the message
   * @param _spender The account receiving approval to spend owner's tokens
   * @param _value The amount to set approval for
   * @param _deadline The timestamp before which the signature must be submitted
   * @param _v ECDSA signature v
   * @param _r ECDSA signature r
   * @param _s ECDSA signature s
   */
  function permit(
    address _owner,
    address _spender,
    uint256 _value,
    uint256 _deadline,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) external {
    require(block.timestamp <= _deadline, "ERC20Permit: expired deadline");
    require(_owner != address(0), "ERC20Permit: owner zero address");
    uint256 _nonce = nonces[_owner];
    bytes32 _hashStruct = keccak256(abi.encode(_PERMIT_TYPEHASH, _owner, _spender, _value, _nonce, _deadline));
    bytes32 _digest = keccak256(abi.encodePacked(_EIP712_PREFIX_AND_VERSION, domainSeparator(), _hashStruct));
    address _signer = ecrecover(_digest, _v, _r, _s);
    require(_signer == _owner, "ERC20Permit: invalid signature");
    nonces[_owner] = _nonce + 1;
    _approve(_owner, _spender, _value);
  }

  // ============ Public Functions ============

  /**
   * @dev See {IERC20-balanceOf}.
   */
  function balanceOf(address _account) public view override(IBridgeToken, ERC20) returns (uint256) {
    return ERC20.balanceOf(_account);
  }

  /**
   * @dev Returns the name of the token.
   */
  function name() public view override returns (string memory) {
    return token.name;
  }

  /**
   * @dev Returns the symbol of the token, usually a shorter version of the
   * name.
   */
  function symbol() public view override returns (string memory) {
    return token.symbol;
  }

  /**
   * @dev Returns the number of decimals used to get its user representation.
   * For example, if `decimals` equals `2`, a balance of `505` tokens should
   * be displayed to a user as `5,05` (`505 / 10 ** 2`).
   * Tokens usually opt for a value of 18, imitating the relationship between
   * Ether and Wei. This is the value {ERC20} uses, unless {_setupDecimals} is
   * called.
   * NOTE: This information is only used for _display_ purposes: it in
   * no way affects any of the arithmetic of the contract, including
   * {IERC20-balanceOf} and {IERC20-transfer}.
   */
  function decimals() public view override returns (uint8) {
    return token.decimals;
  }

  /**
   * @dev This is ALWAYS calculated at runtime
   * because the token name may change
   */
  function domainSeparator() public view returns (bytes32) {
    uint256 _chainId;
    assembly {
      _chainId := chainid()
    }
    return
      keccak256(
        abi.encode(
          keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
          keccak256(bytes(token.name)),
          _EIP712_STRUCTURED_DATA_VERSION,
          _chainId,
          address(this)
        )
      );
  }

  // required for solidity inheritance
  function transferOwnership(address _newOwner) public override(IBridgeToken, OwnableUpgradeable) onlyOwner {
    OwnableUpgradeable.transferOwnership(_newOwner);
  }
}
