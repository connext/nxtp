/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import { Provider, TransactionRequest } from "@ethersproject/providers";
import type {
  TestProposedOwnable,
  TestProposedOwnableInterface,
} from "../TestProposedOwnable";

const _abi = [
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "bool",
        name: "renounced",
        type: "bool",
      },
    ],
    name: "AssetOwnershipRenounced",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "uint256",
        name: "timestamp",
        type: "uint256",
      },
    ],
    name: "AssetOwnershipRenunciationProposed",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "proposedOwner",
        type: "address",
      },
    ],
    name: "OwnershipProposed",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "previousOwner",
        type: "address",
      },
      {
        indexed: true,
        internalType: "address",
        name: "newOwner",
        type: "address",
      },
    ],
    name: "OwnershipTransferred",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "bool",
        name: "renounced",
        type: "bool",
      },
    ],
    name: "RouterOwnershipRenounced",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "uint256",
        name: "timestamp",
        type: "uint256",
      },
    ],
    name: "RouterOwnershipRenunciationProposed",
    type: "event",
  },
  {
    inputs: [],
    name: "acceptProposedOwner",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "assetOwnershipTimestamp",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "delay",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getValue",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "_newValue",
        type: "uint256",
      },
    ],
    name: "initialize",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "isAssetOwnershipRenounced",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "isRouterOwnershipRenounced",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "owner",
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
  {
    inputs: [],
    name: "proposeAssetOwnershipRenunciation",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "newlyProposed",
        type: "address",
      },
    ],
    name: "proposeNewOwner",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "proposeRouterOwnershipRenunciation",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "proposed",
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
  {
    inputs: [],
    name: "proposedTimestamp",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "renounceAssetOwnership",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "renounceOwnership",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "renounceRouterOwnership",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "renounced",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "routerOwnershipTimestamp",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "_newValue",
        type: "uint256",
      },
    ],
    name: "setValue",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
];

const _bytecode =
  "0x608060405234801561001057600080fd5b50610c36806100206000396000f3fe608060405234801561001057600080fd5b50600436106101215760003560e01c80638da5cb5b116100ad578063d1851c9211610071578063d1851c92146101f1578063d232c22014610202578063e47602f71461021b578063e8be0dfc14610223578063fe4b84df1461022b57600080fd5b80638da5cb5b1461019b578063b1f8100d146101c6578063c0c17baf146101d9578063c1a04959146101e1578063c5b350df146101e957600080fd5b806355241077116100f457806355241077146101675780636a41633a1461017a5780636a42b8f814610182578063715018a61461018b5780638741eac51461019357600080fd5b80632004ef451461012657806320965255146101435780633855b467146101555780633cf52ffb1461015f575b600080fd5b61012e61023e565b60405190151581526020015b60405180910390f35b6038545b60405190815260200161013a565b61015d610264565b005b600254610147565b61015d610175366004610b26565b603855565b600654610147565b62093a80610147565b61015d61036e565b61015d61047b565b6000546201000090046001600160a01b03165b6040516001600160a01b03909116815260200161013a565b61015d6101d4366004610b3f565b6104f2565b61015d6105d8565b600454610147565b61015d6106d7565b6001546001600160a01b03166101ae565b61012e6000546201000090046001600160a01b03161590565b61015d6107b7565b61012e61082e565b61015d610239366004610b26565b610852565b600080546201000090046001600160a01b0316158061025f575060035460ff165b905090565b6000546201000090046001600160a01b0316331461029d5760405162461bcd60e51b815260040161029490610b6f565b60405180910390fd5b60055460ff16156102db5760405162461bcd60e51b8152602060048201526008602482015267046a4829e746066760c31b6044820152606401610294565b6000600654116103185760405162461bcd60e51b81526020600482015260086024820152672352414f3a30333760c01b6044820152606401610294565b62093a806006544261032a9190610b90565b116103625760405162461bcd60e51b815260206004820152600860248201526702352414f3a3033360c41b6044820152606401610294565b61036c6001610919565b565b6000546201000090046001600160a01b0316331461039e5760405162461bcd60e51b815260040161029490610b6f565b6000600254116103da5760405162461bcd60e51b815260206004820152600760248201526623524f3a30333760c81b6044820152606401610294565b62093a80600254426103ec9190610b90565b116104235760405162461bcd60e51b8152602060048201526007602482015266023524f3a3033360cc1b6044820152606401610294565b6001546001600160a01b0316156104665760405162461bcd60e51b815260206004820152600760248201526611a9279d18199b60c91b6044820152606401610294565b60015461036c906001600160a01b0316610966565b6000546201000090046001600160a01b031633146104ab5760405162461bcd60e51b815260040161029490610b6f565b60055460ff16156104ea5760405162461bcd60e51b8152602060048201526009602482015268046a0829ea4746066760bb1b6044820152606401610294565b61036c6109c6565b6000546201000090046001600160a01b031633146105225760405162461bcd60e51b815260040161029490610b6f565b6001546001600160a01b03828116911614158061054657506001600160a01b038116155b61057d5760405162461bcd60e51b815260206004820152600860248201526711a827279d18199b60c11b6044820152606401610294565b6000546001600160a01b03828116620100009092041614156105cc5760405162461bcd60e51b8152602060048201526008602482015267046a09c9e746066760c31b6044820152606401610294565b6105d581610a02565b50565b6000546201000090046001600160a01b031633146106085760405162461bcd60e51b815260040161029490610b6f565b60035460ff16156106465760405162461bcd60e51b8152602060048201526008602482015267046a4a49e746066760c31b6044820152606401610294565b6000600454116106835760405162461bcd60e51b81526020600482015260086024820152672352524f3a30333760c01b6044820152606401610294565b62093a80600454426106959190610b90565b116106cd5760405162461bcd60e51b815260206004820152600860248201526702352524f3a3033360c41b6044820152606401610294565b61036c6001610a50565b6001546001600160a01b0316331461071b5760405162461bcd60e51b8152602060048201526007602482015266234f503a30333560c81b6044820152606401610294565b6001546000546201000090046001600160a01b039081169116141561076d5760405162461bcd60e51b815260206004820152600860248201526704682a09e746066760c31b6044820152606401610294565b62093a806002544261077f9190610b90565b116104665760405162461bcd60e51b815260206004820152600860248201526702341504f3a3033360c41b6044820152606401610294565b6000546201000090046001600160a01b031633146107e75760405162461bcd60e51b815260040161029490610b6f565b60035460ff16156108265760405162461bcd60e51b8152602060048201526009602482015268046a0a49ea4746066760bb1b6044820152606401610294565b61036c610a96565b600080546201000090046001600160a01b0316158061025f57505060055460ff1690565b600054610100900460ff1661086d5760005460ff1615610871565b303b155b6108d45760405162461bcd60e51b815260206004820152602e60248201527f496e697469616c697a61626c653a20636f6e747261637420697320616c72656160448201526d191e481a5b9a5d1a585b1a5e995960921b6064820152608401610294565b600054610100900460ff161580156108f6576000805461ffff19166101011790555b6108fe610acc565b60388290558015610915576000805461ff00191690555b5050565b6005805460ff191682151590811790915560006006556040519081527f868d89ead22a5d10f456845ac0014901d9af7203e71cf0892d70d9dc262c2fb9906020015b60405180910390a150565b600080546001600160a01b038381166201000081810262010000600160b01b03198516178555600285905560405193049190911692909183917f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e091a35050565b4260068190556040519081527fa78fdca214e4619ef34a695316d423f5b0d8274bc919d29733bf8f92ec8cbb7a906020015b60405180910390a1565b42600255600180546001600160a01b0319166001600160a01b0383169081179091556040517f6ab4d119f23076e8ad491bc65ce85f017fb0591dce08755ba8591059cc51737a90600090a250565b6003805460ff191682151590811790915560006004556040519081527f243ebbb2f905234bbf0556bb38e1f7c23b09ffd2e441a16e58b844eb2ab7a3979060200161095b565b4260048190556040519081527fa52048c5f468d21a62e4644ac4db19bcaa1a20f0cf37d163ba49c7217d35feb8906020016109f8565b600054610100900460ff16610af35760405162461bcd60e51b815260040161029490610bb5565b61036c600054610100900460ff16610b1d5760405162461bcd60e51b815260040161029490610bb5565b61036c33610966565b600060208284031215610b3857600080fd5b5035919050565b600060208284031215610b5157600080fd5b81356001600160a01b0381168114610b6857600080fd5b9392505050565b602080825260079082015266234f4f3a30323960c81b604082015260600190565b600082821015610bb057634e487b7160e01b600052601160045260246000fd5b500390565b6020808252602b908201527f496e697469616c697a61626c653a20636f6e7472616374206973206e6f74206960408201526a6e697469616c697a696e6760a81b60608201526080019056fea26469706673582212207c137152f05ffcf96f2b28d10b67cf7effc55379f679aa38c84986f6cb8b614e64736f6c634300080b0033";

type TestProposedOwnableConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: TestProposedOwnableConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class TestProposedOwnable__factory extends ContractFactory {
  constructor(...args: TestProposedOwnableConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
    this.contractName = "TestProposedOwnable";
  }

  deploy(
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<TestProposedOwnable> {
    return super.deploy(overrides || {}) as Promise<TestProposedOwnable>;
  }
  getDeployTransaction(
    overrides?: Overrides & { from?: string | Promise<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  attach(address: string): TestProposedOwnable {
    return super.attach(address) as TestProposedOwnable;
  }
  connect(signer: Signer): TestProposedOwnable__factory {
    return super.connect(signer) as TestProposedOwnable__factory;
  }
  static readonly contractName: "TestProposedOwnable";
  public readonly contractName: "TestProposedOwnable";
  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): TestProposedOwnableInterface {
    return new utils.Interface(_abi) as TestProposedOwnableInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): TestProposedOwnable {
    return new Contract(address, _abi, signerOrProvider) as TestProposedOwnable;
  }
}
