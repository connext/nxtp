/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import { Provider, TransactionRequest } from "@ethersproject/providers";
import type {
  FulfillInterpreter,
  FulfillInterpreterInterface,
} from "../FulfillInterpreter";

const _abi = [
  {
    inputs: [
      {
        internalType: "address",
        name: "transactionManager",
        type: "address",
      },
    ],
    stateMutability: "nonpayable",
    type: "constructor",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "bytes32",
        name: "transactionId",
        type: "bytes32",
      },
      {
        indexed: false,
        internalType: "address payable",
        name: "callTo",
        type: "address",
      },
      {
        indexed: false,
        internalType: "address",
        name: "assetId",
        type: "address",
      },
      {
        indexed: false,
        internalType: "address payable",
        name: "fallbackAddress",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "bytes",
        name: "callData",
        type: "bytes",
      },
      {
        indexed: false,
        internalType: "bytes",
        name: "returnData",
        type: "bytes",
      },
      {
        indexed: false,
        internalType: "bool",
        name: "success",
        type: "bool",
      },
    ],
    name: "Executed",
    type: "event",
  },
  {
    inputs: [
      {
        internalType: "bytes32",
        name: "transactionId",
        type: "bytes32",
      },
      {
        internalType: "address payable",
        name: "callTo",
        type: "address",
      },
      {
        internalType: "address",
        name: "assetId",
        type: "address",
      },
      {
        internalType: "address payable",
        name: "fallbackAddress",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
      {
        internalType: "bytes",
        name: "callData",
        type: "bytes",
      },
    ],
    name: "execute",
    outputs: [],
    stateMutability: "payable",
    type: "function",
  },
  {
    inputs: [],
    name: "getTransactionManager",
    outputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
];

const _bytecode =
  "0x608060405234801561001057600080fd5b50604051610b10380380610b1083398101604081905261002f91610059565b6001600081905580546001600160a01b0319166001600160a01b0392909216919091179055610087565b60006020828403121561006a578081fd5b81516001600160a01b0381168114610080578182fd5b9392505050565b610a7a806100966000396000f3fe6080604052600436106100295760003560e01c806396f32fb81461002e578063cf9a36041461005a575b600080fd5b34801561003a57600080fd5b50600154604080516001600160a01b039092168252519081900360200190f35b61006d610068366004610824565b61006f565b005b600260005414156100c75760405162461bcd60e51b815260206004820152601f60248201527f5265656e7472616e637947756172643a207265656e7472616e742063616c6c0060448201526064015b60405180910390fd5b60026000556001546001600160a01b031633146101115760405162461bcd60e51b8152602060048201526008602482015267234f544d3a30323760c01b60448201526064016100be565b6001600160a01b038516158061012c5761012c868886610215565b600080886001600160a01b031683610145576000610147565b865b8686604051610157929190610921565b60006040518083038185875af1925050503d8060008114610194576040519150601f19603f3d011682016040523d82523d6000602084013e610199565b606091505b5091509150816101be576101ae888888610265565b826101be576101be888a88610289565b897fbf49bd2de448d90a19e0510ab1030fead50ebfc64a4f112ca42535ae79fbab798a8a8a8a8a8a888a6040516101fc98979695949392919061094d565b60405180910390a2505060016000555050505050505050565b6001600160a01b0383166102555760405162461bcd60e51b815260206004820152600760248201526608d2504e8c0ccd60ca1b60448201526064016100be565b6102608383836102d4565b505050565b6001600160a01b0383161561027f576102608383836103ce565b61026082826103d9565b6001600160a01b0383166102c95760405162461bcd60e51b815260206004820152600760248201526608d1104e8c0ccd60ca1b60448201526064016100be565b610260838383610466565b604051636eb1769f60e11b81523060048201526001600160a01b038381166024830152600091839186169063dd62ed3e9060440160206040518083038186803b15801561032057600080fd5b505afa158015610334573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061035891906108dd565b61036291906109dc565b6040516001600160a01b0385166024820152604481018290529091506103c890859063095ea7b360e01b906064015b60408051601f198184030181529190526020810180516001600160e01b03166001600160e01b031990931692909217909152610588565b50505050565b61026083838361065a565b6000826001600160a01b03168260405160006040518083038185875af1925050503d8060008114610426576040519150601f19603f3d011682016040523d82523d6000602084013e61042b565b606091505b50509050806102605760405162461bcd60e51b8152602060048201526007602482015266046a88a746064760cb1b60448201526064016100be565b604051636eb1769f60e11b81523060048201526001600160a01b0383811660248301526000919085169063dd62ed3e9060440160206040518083038186803b1580156104b157600080fd5b505afa1580156104c5573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906104e991906108dd565b90508181101561054d5760405162461bcd60e51b815260206004820152602960248201527f5361666545524332303a2064656372656173656420616c6c6f77616e63652062604482015268656c6f77207a65726f60b81b60648201526084016100be565b6040516001600160a01b0384166024820152828203604482018190529061058190869063095ea7b360e01b90606401610391565b5050505050565b60006105dd826040518060400160405280602081526020017f5361666545524332303a206c6f772d6c6576656c2063616c6c206661696c6564815250856001600160a01b031661068a9092919063ffffffff16565b80519091501561026057808060200190518101906105fb9190610804565b6102605760405162461bcd60e51b815260206004820152602a60248201527f5361666545524332303a204552433230206f7065726174696f6e20646964206e6044820152691bdd081cdd58d8d9595960b21b60648201526084016100be565b6040516001600160a01b03831660248201526044810182905261026090849063a9059cbb60e01b90606401610391565b606061069984846000856106a3565b90505b9392505050565b6060824710156107045760405162461bcd60e51b815260206004820152602660248201527f416464726573733a20696e73756666696369656e742062616c616e636520666f6044820152651c8818d85b1b60d21b60648201526084016100be565b843b6107525760405162461bcd60e51b815260206004820152601d60248201527f416464726573733a2063616c6c20746f206e6f6e2d636f6e747261637400000060448201526064016100be565b600080866001600160a01b0316858760405161076e9190610931565b60006040518083038185875af1925050503d80600081146107ab576040519150601f19603f3d011682016040523d82523d6000602084013e6107b0565b606091505b50915091506107c08282866107cb565b979650505050505050565b606083156107da57508161069c565b8251156107ea5782518084602001fd5b8160405162461bcd60e51b81526004016100be91906109c9565b600060208284031215610815578081fd5b8151801515811461069c578182fd5b600080600080600080600060c0888a03121561083e578283fd5b87359650602088013561085081610a2c565b9550604088013561086081610a2c565b9450606088013561087081610a2c565b93506080880135925060a088013567ffffffffffffffff80821115610893578384fd5b818a0191508a601f8301126108a6578384fd5b8135818111156108b4578485fd5b8b60208285010111156108c5578485fd5b60208301945080935050505092959891949750929550565b6000602082840312156108ee578081fd5b5051919050565b6000815180845261090d816020860160208601610a00565b601f01601f19169290920160200192915050565b8183823760009101908152919050565b60008251610943818460208701610a00565b9190910192915050565b6001600160a01b0389811682528881166020830152871660408201526060810186905260e0608082018190528101849052600061010085878285013781818785010152601f19601f8701168301818482030160a08501526109b0828201876108f5565b9250505082151560c08301529998505050505050505050565b60208152600061069c60208301846108f5565b600082198211156109fb57634e487b7160e01b81526011600452602481fd5b500190565b60005b83811015610a1b578181015183820152602001610a03565b838111156103c85750506000910152565b6001600160a01b0381168114610a4157600080fd5b5056fea26469706673582212208a96d54108de94865976e145d75766b08aa2e124de582ce55d0331cc3297594564736f6c63430008040033";

export class FulfillInterpreter__factory extends ContractFactory {
  constructor(signer?: Signer) {
    super(_abi, _bytecode, signer);
  }

  deploy(
    transactionManager: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<FulfillInterpreter> {
    return super.deploy(
      transactionManager,
      overrides || {}
    ) as Promise<FulfillInterpreter>;
  }
  getDeployTransaction(
    transactionManager: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(transactionManager, overrides || {});
  }
  attach(address: string): FulfillInterpreter {
    return super.attach(address) as FulfillInterpreter;
  }
  connect(signer: Signer): FulfillInterpreter__factory {
    return super.connect(signer) as FulfillInterpreter__factory;
  }
  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): FulfillInterpreterInterface {
    return new utils.Interface(_abi) as FulfillInterpreterInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): FulfillInterpreter {
    return new Contract(address, _abi, signerOrProvider) as FulfillInterpreter;
  }
}
