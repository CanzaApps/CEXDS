const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const RWAOracle = await ethers.getContractFactory("RWAOracle");
  const rwaOracle = await RWAOracle.deploy();

  console.log("RWA Oracle address:", rwaOracle.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });