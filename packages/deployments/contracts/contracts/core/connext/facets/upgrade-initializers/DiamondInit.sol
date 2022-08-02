// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
*
* Implementation of a diamond.
/******************************************************************************/

import {IDiamondLoupe} from "../../interfaces/IDiamondLoupe.sol";
import {IDiamondCut} from "../../interfaces/IDiamondCut.sol";
import {IERC165} from "../../interfaces/IERC165.sol";
import {IWeth} from "../../interfaces/IWeth.sol";
import {ITokenRegistry} from "../../interfaces/ITokenRegistry.sol";

import {Executor} from "../../helpers/Executor.sol";

import {LibDiamond} from "../../libraries/LibDiamond.sol";

import {BaseConnextFacet} from "../BaseConnextFacet.sol";

import {IProposedOwnable} from "../../../shared/interfaces/IProposedOwnable.sol";
import {RelayerFeeRouter} from "../../../relayer-fee/RelayerFeeRouter.sol";
import {PromiseRouter} from "../../../promise/PromiseRouter.sol";

import {XAppConnectionManager} from "../../../../nomad-core/contracts/XAppConnectionManager.sol";

// It is expected that this contract is customized if you want to deploy your diamond
// with data from a deployment script. Use the init function to initialize state variables
// of your diamond. Add parameters to the init funciton if you need to.

contract DiamondInit is BaseConnextFacet {
  // You can add parameters to this function in order to pass in
  // data to set your own state variables
  function init(
    uint32 _domain,
    address _tokenRegistry, // Nomad token registry
    address _relayerFeeRouter,
    address payable _promiseRouter
  ) external {
    // adding ERC165 data
    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    ds.supportedInterfaces[type(IERC165).interfaceId] = true;
    ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
    ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
    ds.supportedInterfaces[type(IProposedOwnable).interfaceId] = true;

    // add your own state variables
    // EIP-2535 specifies that the `diamondCut` function takes two optional
    // arguments: address _init and bytes calldata _calldata
    // These arguments are used to execute an arbitrary function using delegatecall
    // in order to set state variables in the diamond during deployment or an upgrade
    // More info here: https://eips.ethereum.org/EIPS/eip-2535#diamond-interface

    if (!s.initialized) {
      // ensure this is the owner
      LibDiamond.enforceIsContractOwner();

      s.initialized = true;

      // __ReentrancyGuard_init_unchained
      s._status = _NOT_ENTERED;

      // ConnextHandler
      s.domain = _domain;
      s.relayerFeeRouter = RelayerFeeRouter(_relayerFeeRouter);
      s.promiseRouter = PromiseRouter(_promiseRouter);
      s.executor = new Executor(address(this));
      s.tokenRegistry = ITokenRegistry(_tokenRegistry);
      s.LIQUIDITY_FEE_NUMERATOR = 9995;
      s.maxRoutersPerTransfer = 5;
    }
  }
}
