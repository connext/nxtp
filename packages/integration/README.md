# Integration

A test script to validate the end-to-end cross-chain transfer process.

# E2E Local Environment

## External Dependencies

Make sure you have docker installed globally.

## Environment Variables

In your local environment, run the following commands to export env variables which will be used in the local e2e runtime environment:

```sh
export GRAPH_1337_ENDPOINT="http://localhost:8010/subgraphs/name/connext/nxtp"
export GRAPH_1338_ENDPOINT="http://localhost:9010/subgraphs/name/connext/nxtp"
```

## Build Local Images

If you need to run the test locally against local changes, you can build the images yourself.

```sh
./packages/integration/build-docker-images.sh
```

## Edit Config If Needed

In `setup-integration-test.sh` there is a section that creates a `.env` file. Anything here such as image tags can be changed to reflect the test design. For example, if you want to run the test against a different image, you can change the tag in the bash file variables for `ROUTER_IMAGE` and `SEQUENCER_IMAGE`.

## Steps

1. Run `./packages/integration/setup-integration-test.sh`
2. Run `yarn workspace @connext/nxtp-integration run test`

## Logs from Deployment

Used to get local addresses for use in test scripts.

```
============================= Deploying Nomad Core ===============================
deployer:  0x627306090abaB3A6e1400e9345bC60c78a8BEf57
deploying "UpgradeBeaconController" (tx: 0x5f33aa7fbe0285511702677fc5a455a1e1cb8d24ee6ccfb563b09368385fbc50)...: deployed at 0x8CdaF0CD259887258Bc13a92C0a6dA92698644C0 with 307518 gas
Deploying BridgeToken with nomad upgradeable scheme
deploying "BridgeToken" (tx: 0x9c4fdf9ef48cedd92e0b102d08bb82af6880bef493027ce79502837d12dba963)...: deployed at 0xF12b5dd4EAD5F743C6BaA640B0216200e89B60Da with 1389032 gas
deployed implementation: 0xF12b5dd4EAD5F743C6BaA640B0216200e89B60Da
deploying "BridgeTokenUpgradeBeacon" (tx: 0x9ffdc19e0a58659deedb7a0068ad9ed534825762760ef528e76d4688e2d52e29)...: deployed at 0x345cA3e014Aaf5dcA488057592ee47305D9B3e10 with 168911 gas
deploying "BridgeTokenUpgradeBeaconProxy" (tx: 0xd40fd92aa309ad031befb4820639d1a310ebacc08746bcf8bc0b61bc7e256f3b)...: deployed at 0xf25186B5081Ff5cE73482AD761DB0eB0d25abfBF with 229159 gas
bridgeTokenBeacon address:  0x345cA3e014Aaf5dcA488057592ee47305D9B3e10
bridgeToken proxy address: 0xf25186B5081Ff5cE73482AD761DB0eB0d25abfBF
deploying "UpdaterManager" (tx: 0xdd6396206c037488c382fb79bbe528f6ab61b2f12bdaa07f64cbba42bab516f4)...: deployed at 0x8f0483125FCb9aaAEFA9209D8E9d7b9C8B9Fb90F with 365477 gas
updaterManager address:  0x8f0483125FCb9aaAEFA9209D8E9d7b9C8B9Fb90F
Deploying Home with nomad upgradeable scheme
deploying "Home" (tx: 0x7d3195e158decd20058a1a2ca6631f5a9f4f2e3367d63cc9dcb3f7a06f9040d3)...: deployed at 0x9FBDa871d559710256a2502A2517b794B482Db40 with 2048403 gas
deployed implementation: 0x9FBDa871d559710256a2502A2517b794B482Db40
deploying "HomeUpgradeBeacon" (tx: 0x39308252a7272d6f9e9409a8be4cd6b0ff03944bb0d6aa813414c8f4500c7769)...: deployed at 0x2C2B9C9a4a25e24B174f26114e8926a9f2128FE4 with 168923 gas
deploying "HomeUpgradeBeaconProxy" (tx: 0xb4311a6a61baa71887495dca52677db43a99345c26b7b6817f618a59401b3b79)...: deployed at 0x30753E4A8aad7F8597332E813735Def5dD395028 with 305696 gas
home address:  0x30753E4A8aad7F8597332E813735Def5dD395028

============================= Deploying Nomad ===============================
deployer:  0x627306090abaB3A6e1400e9345bC60c78a8BEf57
Deploying xapp connection manager...
deploying "XAppConnectionManager" (tx: 0xb9a28003d8b1ec910b31806c45e47f8205f26bc2fb9f46c312ae98db1a519ad1)...: deployed at 0xFB88dE099e13c3ED21F80a7a1E49f8CAEcF10df6 with 934450 gas
deploy tx: 0xb9a28003d8b1ec910b31806c45e47f8205f26bc2fb9f46c312ae98db1a519ad1
xappConnectionManagerAddress: 0xFB88dE099e13c3ED21F80a7a1E49f8CAEcF10df6
Deploying token registry...
Deploying TokenRegistry with nomad upgradeable scheme
deploying "TokenRegistry" (tx: 0xdfef1d568c561f1cc7b096f41708c1c02835e91e8fa7182005eece7291823ec1)...: deployed at 0xAa588d3737B611baFD7bD713445b314BD453a5C8 with 1580743 gas
deployed implementation: 0xAa588d3737B611baFD7bD713445b314BD453a5C8
deploying "TokenRegistryUpgradeBeacon" (tx: 0x9a245ec29e3b46766571f23423e4f5e69e76fb04e2225504dccec63f34ab4d09)...: deployed at 0xf204a4Ef082f5c04bB89F7D5E6568B796096735a with 168923 gas
deploying "TokenRegistryUpgradeBeaconProxy" (tx: 0xc634910c249a0f19ded6a41df4880cd1fe4cd1cf969f376db2f86aac97f63b44)...: deployed at 0x75c35C980C0d37ef46DF04d31A140b65503c0eEd with 257835 gas
Setting local domain of token registry as 1337...
setDomain tx: 0xd47445205ccb219bed5b1c565142a3107bfd980a29b9ee9c6f47437a825d13bc
setDomain tx mined: {
  to: '0x75c35C980C0d37ef46DF04d31A140b65503c0eEd',
  from: '0x627306090abaB3A6e1400e9345bC60c78a8BEf57',
  contractAddress: null,
  transactionIndex: 0,
  gasUsed: BigNumber { _hex: '0x86cf', _isBigNumber: true },
  logsBloom: '0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  blockHash: '0x2619153ce23a814774b2523cd8f5d2370214771809c32604a273b980302c31f5',
  transactionHash: '0xd47445205ccb219bed5b1c565142a3107bfd980a29b9ee9c6f47437a825d13bc',
  logs: [],
  blockNumber: 67,
  confirmations: 4,
  cumulativeGasUsed: BigNumber { _hex: '0x86cf', _isBigNumber: true },
  effectiveGasPrice: BigNumber { _hex: '0x022425', _isBigNumber: true },
  status: 1,
  type: 2,
  byzantium: true,
  events: []
}
xapp owner 0x627306090abaB3A6e1400e9345bC60c78a8BEf57
setting home as 0x30753e4a8aad7f8597332e813735def5dd395028 on local1337....
setHome: 0x6c4024da3ab525bbae827e5e6f515a85ef9b475a985466bc396976889988e235
Deploying relayer fee router...
Deploying RelayerFeeRouter with nomad upgradeable scheme
deploying "RelayerFeeRouter" (tx: 0xb8409d638c907377449c9ffbdbca697a16e5405d1d1b6911bbad1b7298cd9687)...: deployed at 0xeec918d74c746167564401103096D45BbD494B74 with 1522613 gas
deployed implementation: 0xeec918d74c746167564401103096D45BbD494B74
deploying "RelayerFeeRouterUpgradeBeacon" (tx: 0x3f596e4873198fc5fa66bb5734338075f0f05df84e9f1d496a5139132e9094a9)...: deployed at 0x0d8cc4b8d15D4c3eF1d70af0071376fb26B5669b with 168923 gas
deploying "RelayerFeeRouterUpgradeBeaconProxy" (tx: 0x721ac3b93ac269164eb90e90b1113088a00d468d229f812a252c7b6995110501)...: deployed at 0xEcFcaB0A285d3380E488A39B4BB21e777f8A4EaC with 235028 gas
relayer fee router address: 0xEcFcaB0A285d3380E488A39B4BB21e777f8A4EaC
relayer fee router owner: 0x627306090abaB3A6e1400e9345bC60c78a8BEf57
Deploying promise router...
Deploying PromiseRouter with nomad upgradeable scheme
deploying "PromiseRouter" (tx: 0xba031e7073a975cd8a85149c1c3e3cf9ed599a1b2e0e0bc5bbba367c87402edb)...: deployed at 0x38cF23C52Bb4B13F051Aec09580a2dE845a7FA35 with 2034905 gas
deployed implementation: 0x38cF23C52Bb4B13F051Aec09580a2dE845a7FA35
deploying "PromiseRouterUpgradeBeacon" (tx: 0x607f50d6756cfdf79ed8c4fb5eea99ca634cfbc89a1f5b4daccdda0551ca44f9)...: deployed at 0x4E72770760c011647D4873f60A3CF6cDeA896CD8 with 168923 gas
deploying "PromiseRouterUpgradeBeaconProxy" (tx: 0x4bb45895b9f4e2d4c2c78631e4b95a7885009c6bf24297c3a1e5ca1344b653e1)...: deployed at 0xbaAA2a3237035A2c7fA2A33c76B44a8C6Fe18e87 with 235072 gas
promise router address: 0xbaAA2a3237035A2c7fA2A33c76B44a8C6Fe18e87
promise router owner: 0x627306090abaB3A6e1400e9345bC60c78a8BEf57

============================= Deploying Connext Diamond ===============================
deployer:  0x627306090abaB3A6e1400e9345bC60c78a8BEf57
Fetching relayer fee router...
Fetching promise router...
Fetching token registry...
deploying "LPToken" (tx: 0xaba94bca2af99947d67da0d710d50c21775497fbfa8ec998cda8dbe7edbbccfa)...: deployed at 0x13274Fe19C0178208bCbee397af8167A7be27f6f with 1048571 gas
executing LPToken.initialize (tx: 0x55319254dc848b859be5592c431e716ad4eaf31ad291d67e74c716cd006a2642) ...: performed with 115486 gas
Deploying connext diamond...
sending eth to create2 contract deployer address (0x3fab184622dc19b6109349b94811493bf2a45362) (tx: 0x5123716cd17cea55bd29e19616ff19a64196e0484f9ff46652b157c60b7415fa)...
deploying create2 deployer contract (at 0x4e59b44847b379578588920ca78fbf26c0b4956c) using deterministic deployment (https://github.com/Arachnid/deterministic-deployment-proxy) (tx: 0xeddf9e61fb9d8f5111840daef55e5fde0041f5702856532cdbb5a02998033d26)...
deploying "AssetFacet" (tx: 0x94ff6aea4ee6246d790f7520c2c23cb5d3a20d7a46c0d2c9401d4a9b41de4ae4)...: deployed at 0xbE7fF776173bB96815Cf5d0922BDf876333B341f with 557678 gas
deploying "BridgeFacet" (tx: 0x93382c33cbb42d28446c67a3700c6e03cb8fe5379c3a4f90726de7b1ea52e0c0)...: deployed at 0xE6697ac8d837Dd54b96E83B3aA1Dfe2fdA58d8e2 with 6089665 gas
deploying "NomadFacet" (tx: 0x8896d7634200b5a9b56675319f1753d5012d4423520fdac410633f43b6268976)...: deployed at 0x8f27980BD219be49A8E17Da107fb7C2C281b93F0 with 191520 gas
deploying "ProposedOwnableFacet" (tx: 0x57994b2e46b6c7544d22ebe0d6b2a72a2c55a383879322c96d9493620146dcfb)...: deployed at 0x771fD2A2943f03De99943E00Ee0765a857E36E94 with 596310 gas
deploying "RelayerFacet" (tx: 0x923c79e7222ccee10fd8314fe57345757ff277890873ad5910b79adf65705f27)...: deployed at 0x030f2cf04F4F97c4e3ce0a5879d549Fe4D570c90 with 622904 gas
deploying "RoutersFacet" (tx: 0xbeb1963784682b9cf307e3a47aa517a1db03acda34976735ef7428d5eead8c5a)...: deployed at 0xC7041266D9990F8C7b7ED01d3CB5c9B1b01C7B4E with 1793301 gas
deploying "StableSwapFacet" (tx: 0x93ca74e880db39ea6a06f6ffd28bad35d89cc69ea5954517382b9d8018044af7)...: deployed at 0x24Bb73B9d54C0F66192C9995e3f290CDF9985c74 with 5402095 gas
deploying "VersionFacet" (tx: 0x8225e46072c7d041dba7f5611d369baad11c57c95e1abf2c7fe5de329dfe3372)...: deployed at 0xc4DBE9fEe1A97544ae010D1fB58ef6F60adF52e5 with 86869 gas
deploying "_DefaultDiamondCutFacet" (tx: 0xe9fb7583bb7ffd2089825f802e596fdb2051c66e67d97d21f0612385126c4b9c)...: deployed at 0x429dbdE7913c0Ed51E4B21163760B92eE66Ff5f5 with 1648898 gas
deploying "_DefaultDiamondLoupeFacet" (tx: 0x5ce9866cd3e5ebe25986f817ec64245c5fe259b5a99ef3d167e8abe8e9781bab)...: deployed at 0x51d21E284392bb7f652a47A6fEFf514071673B3e with 481329 gas
deploying "DiamondInit" (tx: 0xda71b3f081e60e290e39c540ee9b6d4eb46e6c6c0f9788116f8f76803effa119)...: deployed at 0x2DBDa7b9B956ee981e520fD1cd2EA8B612497eBe with 1664174 gas
deploying "_DefaultDiamondERC165Init" (tx: 0x5f8e4f9d4aaa673fcdc42138950fd58d45849d1bfea4a12964c1454a740d98b9)...: deployed at 0xe68d85348f227d2ebEE814C38918F8A2D7d9B603 with 279490 gas
deploying "ConnextHandler_DiamondProxy" (tx: 0xb60e26f0c86763385f219f8ac2cc081e4d8c3353ebfd9f92bc1cee435d200644)...: deployed at 0xF08dF3eFDD854FEDE77Ed3b2E515090EEe765154 with 7197940 gas
connextAddress:  0xF08dF3eFDD854FEDE77Ed3b2E515090EEe765154
setting connext on relayer fee router
setting connext on promiseRouter router
Deploying multicall...
deploying "Multicall" (tx: 0x62a95ba5dee3777da86dfcf820f19db4e4b75655a7140a6f7cfb68c11fe735fb)...: deployed at 0x98d9f9e8DEbd4A632682ba207670d2a5ACD3c489 with 314025 gas
Deploying test token on non-mainnet chain...
deploying "TestERC20" (tx: 0x1e8563ea78ec99d864f3829aefb3773e3597e961ae6c629f489bef75a292ec8e)...: deployed at 0x8e4C131B37383E431B9cd0635D3cF9f3F628EDae with 915139 gas
TestERC20:  0x8e4C131B37383E431B9cd0635D3cF9f3F628EDae

============================= Deploying StableSwap ===============================
deployer:  0x627306090abaB3A6e1400e9345bC60c78a8BEf57
reusing "LPToken" at 0x13274Fe19C0178208bCbee397af8167A7be27f6f
deploying "StableSwap" (tx: 0x1467c50c5ba73f3eb41567cf8c20b5c91c7280d390374df15b7926bbc386ada2)...: deployed at 0x1411CB266FCEd1587b0AA29E9d5a9Ef3Db64A9C5 with 5556729 gas
Deployed contracts to 1337
```

# E2E Live Environment (Testnet)

## Setup

1. ENVIRONMENT

Create a .env file and fill in the following information:

```sh
ROUTER_MNEMONIC="<...>"
USER_MNEMONIC="<...>"
DEPLOYER_MNEMONIC="<...>"
INFURA_KEY="<...>"
```

**If you don't specify a `ROUTER_MNEMONIC`, we won't run a local router/sequencer instance. Instead, the test will be conducted using any active live counterparts.**

The `USER_MNEMONIC` can literally be any random mnemonic. While it's not necessary (the integration test will just generate a fresh random wallet), it's recommended that you specify one to use continually so as to recycle dust and save ETH on additional setup steps during execution.

You can generate a random wallet easily using node shell, assuming you have `ethers.js` installed globally (or locally)

```s
$ node
Welcome to Node.js v16.14.2.
Type ".help" for more information.
> require("ethers").Wallet.createRandom()._mnemonic().phrase
'provide tray domain smooth gentle now dad mesh artwork coast estate great'
>
```

`DEPLOYER_MNEMONIC` is only necessary if you want to run your router locally and the router hasn't been approved (on the destination domain) yet.

If you don't have an `INFURA_API_KEY`, head over to [infura.io](https://infura.io/) and make an account (it's free). It should be under Project Settings > Project ID (_not Project Secret!_). If you really don't want to use Infura, you can specify `ORIGIN_PROVIDER` and `DESTINATION_PROVIDER` directly, although it's less flexible. At the time of writing this README, the default transfer route for the test is Kovan (origin) => Rinkeby (destination).

2. FUNDING

#### With a local router

Your router's wallet (the wallet to which `ROUTER_MNEMONIC` belongs) must have some ETH supplied on both the origin and destination domains. Ultimately, once initial setup transactions are taken care of, the router _should not_ be using any ETH on the destination domain. However, it will require additional ETH on origin to fund the user agent as needed.

If you're not sure which domains to fund your router wallet for, you can check `constants.ts` under `Integration Settings`.

#### With live router

If `ROUTER_MNEMONIC` isn't specified, the `USER_MNEMONIC` will need to be pre-funded with ETH.

And that's it! No additional set up is required. All pre-flight tasking will be taken care of.

## Execution

To execute the test, just run (in NXTP root):

```s
yarn workspace @connext/nxtp-integration run test
```

NOTE: Do **NOT** run the router or sequencer separately, both will be initialized within the test itself.

## FAQ:

- Q: Do I need to run the router or sequencer separately for this to work? A: No. Both will be run inside the test, assuming a `ROUTER_MNEMONIC` is specified.
- Q: How can I save the test execution logs? A: They are saved automatically by timestamp in the ops/data folder.
- Q: Does this have to run on testnet? A: Yes.
- Q: Can I change the execution router and/or domains? A: Not yet.
- Q: Is this test intended to be run as a step in the CI pipeline? A: No.
- Q: How can I get the `DEPLOYER_MNEMONIC`? A: Ask the team.
