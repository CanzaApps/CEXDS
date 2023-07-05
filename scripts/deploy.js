// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {

  const signer = await hre.ethers.getSigner();
  const secondAdmin = "0x1d80b14fc72d953eDfD87bF4d6Acd08547E3f1F6";

  const CEXDeployer = await hre.ethers.getContractFactory("SwapController");
  const cexDeployer = await CEXDeployer.deploy(secondAdmin);

  await cexDeployer.deployed();

  console.log("CEX Deployer deployed to ", cexDeployer.address);

  const superAdmin = await cexDeployer.SUPER_ADMIN();
  const doIhaverole = await cexDeployer.hasRole(superAdmin, signer.address);

  console.log({ superAdmin, doIhaverole })

  const Voting = await hre.ethers.getContractFactory("Voting");
  const voting = await Voting.deploy(secondAdmin, cexDeployer.address);

  await voting.deployed();
  console.log("Voting deployed to ", voting.address);

  // Add Voting Contract to controller
  const trx = await cexDeployer.setVotingContract(voting.address);
  await trx.wait();

  const poolMatureTime = Math.round(Date.now()/1000) + (2*86400);

  const tx = await cexDeployer.createSwapContract("SampleEntity", "0x1d80b14fc72d953eDfD87bF4d6Acd08547E3f1F6", poolMatureTime.toString(), "1687119988", 3);

  await tx.wait();

  // await cexDeployer.grantRole(superAdmin, "0xBc61e22271fbf9f6840911a49588C95c1225cD56");

  console.log("Swap Contracts are now", await cexDeployer.getSwapList());

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
