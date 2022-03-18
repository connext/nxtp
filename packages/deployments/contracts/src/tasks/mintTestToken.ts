import { Wallet } from "ethers";
import { task } from "hardhat/config";

export default task("mint", "Mint test tokens")
  .addParam("amount", "Amount (real units)")
  .addOptionalParam("to", "Override address to mint to")
  .addOptionalParam("assetid", "Override token address")
  .setAction(async ({ to: _to, assetid: _assetId, amount }, { deployments, getNamedAccounts, ethers }) => {
    const namedAccounts = await getNamedAccounts();
    console.log("namedAccounts: ", namedAccounts);

    let assetIdAddress = _assetId;
    if (!assetIdAddress) {
      const assetIdDeployment = await deployments.get("TestERC20");
      assetIdAddress = assetIdDeployment.address;
    }

    let to = _to;
    if (!to) {
      to = namedAccounts.deployer;
    }

    console.log("asset address: ", assetIdAddress);
    console.log("mint to: ", to);

    const erc20 = await ethers.getContractAt("TestERC20", assetIdAddress);
    const tx = await erc20.mint(to, amount, { from: namedAccounts.deployer });
    console.log("mint tx: ", tx);
    const receipt = await tx.wait();
    console.log("mint tx mined: ", receipt.transactionHash);

    const balance = await erc20.balanceOf(to);
    console.log("balance: ", balance.toString());
  });
