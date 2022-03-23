import { task } from "hardhat/config";

export default task("get-chain-id", "Get chainId")
  .addOptionalParam("connextAddress", "Override tx manager address")
  .setAction(async ({ connextAddress: _connextAddress }, { deployments, getNamedAccounts, ethers }) => {
    const namedAccounts = await getNamedAccounts();

    console.log("namedAccounts: ", namedAccounts);

    let connextAddress = _connextAddress;
    if (!connextAddress) {
      const connextDeployment = await deployments.get("ConnextUpgradeBeaconProxy");
      connextAddress = connextDeployment.address;
    }
    console.log("connextAddress: ", connextAddress);

    const connext = await ethers.getContractAt("Connext", connextAddress);
    const chainId = await connext.getChainId();
    console.log("chainId: ", chainId.toString());
  });
