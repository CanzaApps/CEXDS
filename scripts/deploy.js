// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {

  const signer = await hre.ethers.getSigner();

  const CEXDeployer = await hre.ethers.getContractFactory("Deployer");
  const cexDeployer = await CEXDeployer.deploy();

  await cexDeployer.deployed();

  console.log("CEX Deployer deployed to ", cexDeployer.address);

  const tx = await cexDeployer.createSwapContract("SampleEntity", "0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1", "1000", "1686947188", 3);

  await tx.wait();

  console.log("Swap Contracts are now", await cexDeployer.getSwapList());

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
