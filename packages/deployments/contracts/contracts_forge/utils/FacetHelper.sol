// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {ITokenRegistry} from "../../contracts/core/connext/interfaces/ITokenRegistry.sol";
import {IStableSwap} from "../../contracts/core/connext/interfaces/IStableSwap.sol";
import {IWeth} from "../../contracts/core/connext/interfaces/IWeth.sol";

import {LibConnextStorage, AppStorage, TokenId} from "../../contracts/core/connext/libraries/LibConnextStorage.sol";
import {IStableSwap} from "../../contracts/core/connext/interfaces/IStableSwap.sol";

import {TestERC20} from "../../contracts/test/TestERC20.sol";

import "./ForgeHelper.sol";

contract FacetHelper is ForgeHelper {
  // ============ Storage ============
  // ============ Domains
  // domains
  uint32 _originDomain = 1000;
  uint32 _destinationDomain = 2000;
  // destination remote handler id
  bytes32 _remote = bytes32("remote");

  // ============ Assets
  // canonical token details
  address _canonical;
  bytes32 _canonicalId;
  uint32 _canonicalDomain = _originDomain;
  bytes32 _canonicalKey;

  // adopted asset for this domain
  address _adopted;
  // local asset for this domain
  address _local;

  // token registry
  address _tokenRegistry = address(6);
  // stable swap address
  address _stableSwap = address(5555555555555555555);

  // ============ Fees
  // fees
  uint256 _liquidityFeeNumerator = 9995;
  uint256 _liquidityFeeDenominator = 10000;
  // fees for credit
  uint256 _portalFeeNumerator = 5;

  // ============ Utils ============

  // Sets fee values
  function utils_setFees() public {
    AppStorage storage s = LibConnextStorage.connextStorage();
    s.LIQUIDITY_FEE_NUMERATOR = _liquidityFeeNumerator;
    s.aavePortalFeeNumerator = _portalFeeNumerator;
  }

  // Deploys the local, adopted, and canonical tokens. Also sets the
  // canonical id, token registry
  function utils_deployAssetContracts() public {
    AppStorage storage s = LibConnextStorage.connextStorage();
    // Deploy the adopted token.
    _adopted = address(new TestERC20("Test Token", "TEST"));
    // Deploy the local token.
    _local = address(new TestERC20("Test Token", "TEST"));
    // Deploy the canonical token.
    _canonical = address(new TestERC20("Test Token", "TEST"));
    _canonicalId = bytes32(abi.encodePacked(_canonical));
    _canonicalKey = keccak256(abi.encode(_canonicalId, _canonicalDomain));
    // Set token registry
    s.tokenRegistry = ITokenRegistry(_tokenRegistry);
  }

  // Sets the storage and token registry return results.
  function utils_setupAsset(bool localIsAdopted, bool onCanonical) public {
    AppStorage storage s = LibConnextStorage.connextStorage();
    if (onCanonical) {
      _local = _canonical;
      _canonicalDomain = _originDomain;
    } else {
      // If the local is already set to the canonical (i.e. from some defaults)
      // redeploy
      if (_local == _canonical) {
        _local = address(new TestERC20("Test Token", "TEST"));
      }
      _canonicalDomain = _destinationDomain;
    }
    if (localIsAdopted) {
      _adopted = _local;
      _stableSwap = address(0);
    } else {
      // If the adopted is already set as the local, redeploy
      if (_adopted == _local) {
        _adopted = address(new TestERC20("Test Token", "TEST"));
      }
      if (_stableSwap == address(0)) {
        _stableSwap = address(5555555555555555555);
      }
    }
    // token registry should always return the canonical
    vm.mockCall(
      _tokenRegistry,
      abi.encodeWithSelector(ITokenRegistry.getTokenId.selector),
      abi.encode(_canonicalDomain, _canonicalId)
    );

    // if you are not on canonical domain, ensure the local origin returns false
    // (indicates whether token should be burned or not)
    vm.mockCall(
      _tokenRegistry,
      abi.encodeWithSelector(ITokenRegistry.isLocalOrigin.selector, _local),
      abi.encode(onCanonical)
    );

    // ensure local token should always return the local token wrt current domain
    vm.mockCall(_tokenRegistry, abi.encodeWithSelector(ITokenRegistry.ensureLocalToken.selector), abi.encode(_local));

    // Ensure token registry is always returned properly
    vm.mockCall(_tokenRegistry, abi.encodeWithSelector(ITokenRegistry.getLocalAddress.selector), abi.encode(_local));

    // Setup the storage variables
    _canonicalKey = keccak256(abi.encode(_canonicalId, _canonicalDomain));
    s.adoptedToCanonical[_adopted] = TokenId(_canonicalDomain, _canonicalId);
    s.adoptedToLocalPools[_canonicalKey] = IStableSwap(_stableSwap);
    s.canonicalToAdopted[_canonicalKey] = _adopted;

    // // Log stored vars
    // console.log("setup asset:");
    // console.log("- adopted:", _adopted);
    // console.log("- local:", _local);
    // console.log("- canonical:", _canonical);
    // console.log("- stableSwap:", _stableSwap);
    // console.log("- isLocalOrigin", onCanonical);
  }
}
