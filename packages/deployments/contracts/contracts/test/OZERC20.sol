// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// This is modified from "@openzeppelin/contracts/token/ERC20/IERC20.sol"
// Modifications were made to make the tokenName, tokenSymbol, and
// tokenDecimals fields internal instead of private. Getters for them were
// removed to silence solidity inheritance issues

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is IERC20 {
  using SafeMath for uint256;

  mapping(address => uint256) private balances;

  mapping(address => mapping(address => uint256)) private allowances;

  uint256 private supply;

  struct Token {
    string name;
    string symbol;
    uint8 decimals;
  }

  Token internal token;

  /**
   * @dev See {IERC20-transfer}.
   *
   * Requirements:
   *
   * - `_recipient` cannot be the zero address.
   * - the caller must have a balance of at least `_amount`.
   */
  function transfer(address _recipient, uint256 _amount) public virtual override returns (bool) {
    _transfer(msg.sender, _recipient, _amount);
    return true;
  }

  /**
   * @dev See {IERC20-approve}.
   *
   * Requirements:
   *
   * - `_spender` cannot be the zero address.
   */
  function approve(address _spender, uint256 _amount) public virtual override returns (bool) {
    _approve(msg.sender, _spender, _amount);
    return true;
  }

  /**
   * @dev See {IERC20-transferFrom}.
   *
   * Emits an {Approval} event indicating the updated allowance. This is not
   * required by the EIP. See the note at the beginning of {ERC20}.
   *
   * Requirements:
   *
   * - `_sender` and `recipient` cannot be the zero address.
   * - `_sender` must have a balance of at least `amount`.
   * - the caller must have allowance for ``_sender``'s tokens of at least
   * `amount`.
   */
  function transferFrom(
    address _sender,
    address _recipient,
    uint256 _amount
  ) public virtual override returns (bool) {
    _transfer(_sender, _recipient, _amount);
    _approve(
      _sender,
      msg.sender,
      allowances[_sender][msg.sender].sub(_amount, "ERC20: transfer amount exceeds allowance")
    );
    return true;
  }

  /**
   * @dev Atomically increases the allowance granted to `spender` by the caller.
   *
   * This is an alternative to {approve} that can be used as a mitigation for
   * problems described in {IERC20-approve}.
   *
   * Emits an {Approval} event indicating the updated allowance.
   *
   * Requirements:
   *
   * - `_spender` cannot be the zero address.
   */
  function increaseAllowance(address _spender, uint256 _addedValue) public virtual returns (bool) {
    _approve(msg.sender, _spender, allowances[msg.sender][_spender].add(_addedValue));
    return true;
  }

  /**
   * @dev Atomically decreases the allowance granted to `spender` by the caller.
   *
   * This is an alternative to {approve} that can be used as a mitigation for
   * problems described in {IERC20-approve}.
   *
   * Emits an {Approval} event indicating the updated allowance.
   *
   * Requirements:
   *
   * - `_spender` cannot be the zero address.
   * - `_spender` must have allowance for the caller of at least
   * `_subtractedValue`.
   */
  function decreaseAllowance(address _spender, uint256 _subtractedValue) public virtual returns (bool) {
    _approve(
      msg.sender,
      _spender,
      allowances[msg.sender][_spender].sub(_subtractedValue, "ERC20: decreased allowance below zero")
    );
    return true;
  }

  /**
   * @dev See {IERC20-totalSupply}.
   */
  function totalSupply() public view override returns (uint256) {
    return supply;
  }

  /**
   * @dev See {IERC20-balanceOf}.
   */
  function balanceOf(address _account) public view virtual override returns (uint256) {
    return balances[_account];
  }

  /**
   * @dev See {IERC20-allowance}.
   */
  function allowance(address _owner, address _spender) public view virtual override returns (uint256) {
    return allowances[_owner][_spender];
  }

  /**
   * @dev Moves tokens `amount` from `_sender` to `_recipient`.
   *
   * This is internal function is equivalent to {transfer}, and can be used to
   * e.g. implement automatic token fees, slashing mechanisms, etc.
   *
   * Emits a {Transfer} event.
   *
   * Requirements:
   *
   * - `_sender` cannot be the zero address.
   * - `_recipient` cannot be the zero address.
   * - `_sender` must have a balance of at least `amount`.
   */
  function _transfer(
    address _sender,
    address _recipient,
    uint256 amount
  ) internal virtual {
    require(_sender != address(0), "ERC20: transfer from the zero address");
    require(_recipient != address(0), "ERC20: transfer to the zero address");

    _beforeTokenTransfer(_sender, _recipient, amount);

    balances[_sender] = balances[_sender].sub(amount, "ERC20: transfer amount exceeds balance");
    balances[_recipient] = balances[_recipient].add(amount);
    emit Transfer(_sender, _recipient, amount);
  }

  /** @dev Creates `_amount` tokens and assigns them to `_account`, increasing
   * the total supply.
   *
   * Emits a {Transfer} event with `from` set to the zero address.
   *
   * Requirements:
   *
   * - `to` cannot be the zero address.
   */
  function _mint(address _account, uint256 _amount) internal virtual {
    require(_account != address(0), "ERC20: mint to the zero address");

    _beforeTokenTransfer(address(0), _account, _amount);

    supply = supply.add(_amount);
    balances[_account] = balances[_account].add(_amount);
    emit Transfer(address(0), _account, _amount);
  }

  /**
   * @dev Destroys `_amount` tokens from `_account`, reducing the
   * total supply.
   *
   * Emits a {Transfer} event with `to` set to the zero address.
   *
   * Requirements:
   *
   * - `_account` cannot be the zero address.
   * - `_account` must have at least `_amount` tokens.
   */
  function _burn(address _account, uint256 _amount) internal virtual {
    require(_account != address(0), "ERC20: burn from the zero address");

    _beforeTokenTransfer(_account, address(0), _amount);

    balances[_account] = balances[_account].sub(_amount, "ERC20: burn amount exceeds balance");
    supply = supply.sub(_amount);
    emit Transfer(_account, address(0), _amount);
  }

  /**
   * @dev Sets `_amount` as the allowance of `_spender` over the `_owner` s tokens.
   *
   * This internal function is equivalent to `approve`, and can be used to
   * e.g. set automatic allowances for certain subsystems, etc.
   *
   * Emits an {Approval} event.
   *
   * Requirements:
   *
   * - `_owner` cannot be the zero address.
   * - `_spender` cannot be the zero address.
   */
  function _approve(
    address _owner,
    address _spender,
    uint256 _amount
  ) internal virtual {
    require(_owner != address(0), "ERC20: approve from the zero address");
    require(_spender != address(0), "ERC20: approve to the zero address");

    allowances[_owner][_spender] = _amount;
    emit Approval(_owner, _spender, _amount);
  }

  /**
   * @dev Sets {decimals_} to a value other than the default one of 18.
   *
   * WARNING: This function should only be called from the constructor. Most
   * applications that interact with token contracts will not expect
   * {decimals_} to ever change, and may work incorrectly if it does.
   */
  function _setupDecimals(uint8 decimals_) internal {
    token.decimals = decimals_;
  }

  /**
   * @dev Hook that is called before any transfer of tokens. This includes
   * minting and burning.
   *
   * Calling conditions:
   *
   * - when `_from` and `_to` are both non-zero, `_amount` of ``_from``'s tokens
   * will be to transferred to `_to`.
   * - when `_from` is zero, `_amount` tokens will be minted for `_to`.
   * - when `_to` is zero, `_amount` of ``_from``'s tokens will be burned.
   * - `_from` and `_to` are never both zero.
   *
   * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
   */
  function _beforeTokenTransfer(
    address _from,
    address _to,
    uint256 _amount
  ) internal virtual {}
}
