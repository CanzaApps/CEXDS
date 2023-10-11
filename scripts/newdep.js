// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers } = require("hardhat");
const hre = require("hardhat");

async function main() {

const acc0 = await hre.ethers.getSigner();
//   let signers = [acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10];
  const secondAdmin = "0x940F80Cd7cA57a2565DAF3D79980f90A32233b80";

  // const MockToken = await hre.ethers.getContractFactory("ERC20Mock");
  // const mockToken = await MockToken.deploy();

  // await mockToken.deployed();
  // console.log("Mock Token deployed to ", mockToken.address);

  // const CEXDeployer = await hre.ethers.getContractFactory("SwapController");
  // const cexDeployer = await CEXDeployer.deploy(secondAdmin);

  // await cexDeployer.deployed();

  // console.log("CEX Deployer deployed to ", cexDeployer.address);

  // const superAdmin = await cexDeployer.SUPER_ADMIN();
  // const doIhaverole = await cexDeployer.hasRole(superAdmin, acc0.address);

  // console.log({ superAdmin, doIhaverole })

  // const Oracle = await hre.ethers.getContractFactory("RateOracle");
  // const oracle = await Oracle.deploy(cexDeployer.address, secondAdmin, 1, 2, 1, 3, 7, (30*24*3600).toString());

  // await oracle.deployed();

  // console.log("Oracle deployed to ", oracle.address);
  const cexDeployer = await hre.ethers.getContractAt("SwapController", "0xC11c96eF0E984a52E10Ed091E0983704a53bAce4")
  const oracleAddress = await cexDeployer.oracleContract();
  console.log({oracleAddress})

  const Voting = await hre.ethers.getContractFactory("Voting");
  const voting = await Voting.deploy(secondAdmin, cexDeployer.address, oracleAddress);

  await voting.deployed();
  console.log("Voting deployed to ", voting.address);
  
  // Add Voting Contract to controller
  const trx = await cexDeployer.setVotingContract(voting.address);
  await trx.wait();
  // const trx2 = await cexDeployer.setOracleContract(oracle.address);
  // await trx2.wait();
  // console.log("Here");

  // const poolMatureTime = Math.round(Date.now()/1000) + (4*86400);

  // let txSwap = await cexDeployer.createSwapContract("Binance", "0x5bd836f690c299F8912135d36812889B6C369780", "100", poolMatureTime.toString(), 3);

  // await txSwap.wait();

  // txSwap = await cexDeployer.createSwapContract("Gate.io", "0x0E57b62ABe5873c0eF25d576C3a098d872102330", "120", (poolMatureTime + (2*86400)).toString(), 3);

  // await txSwap.wait();



  // txSwap = await cexDeployer.createSwapContractAsThirdParty("Gate.io", "0x5bd836f690c299F8912135d36812889B6C369780", "80", (poolMatureTime + (5*86400)).toString(), 5, "0xa1123e43adf338C40a9697780FBe55C8182f6dE0", ["0x42d28494FA5735f53AFd233358C4E494A13007b4",
  // "0xec9af0A93b9664d5eC97F1271b11e8A3868E7FEC", 
  // "0x82fCE39f1f2EF722D5128DfB0b8139735C7C24aC"]);

  // console.log("Here now")
  // await txSwap.wait();

  // const voting = await hre.ethers.getContractAt("Voting", "0x91a4689b15b2Ca3eA3016FA3E6316A4bcD8395b6");

  // // await cexDeployer.grantRole(superAdmin, "0xBc61e22271fbf9f6840911a49588C95c1225cD56");

  console.log("Swap Contracts are now", await cexDeployer.getSwapList());

  // const mockToken = await hre.ethers.getContractAt("ERC20Mock", "0xA55046342cD3E44fAD34152A0e5771ee592D94ca");

  // const poolMatureTime = Math.round(Date.now()/1000) + (10*86400);

// const cont = await hre.ethers.getContractAt("Voting", "0x6Fc5f617d704B4b25F242DB8d9beFEfe09CD6876");

  // // let tx = await cont.createSwapContract("Binance", "0x5bd836f690c299F8912135d36812889B6C369780", "1500", poolMatureTime.toString(), 10);

  // // await tx.wait();
  // // tx = await cont.createSwapContract("Canza", "0x0E57b62ABe5873c0eF25d576C3a098d872102330", "1800", poolMatureTime.toString(), 10);
  const tx = await voting.whiteListVoters(["0x42d28494FA5735f53AFd233358C4E494A13007b4",
    "0xec9af0A93b9664d5eC97F1271b11e8A3868E7FEC", 
    "0x82fCE39f1f2EF722D5128DfB0b8139735C7C24aC", 
    "0xd48B7065eFd80156cE62963eF58Ae9b7f4b5f07d",
    "0x120920E61C00989B7F7554DC79fBf2c47f360aEA",
    "0xc4466d3fD3A6c84E41dD65534c7ddc3f444EF438",
    "0xD5AEF93E99Df1cd19E580Dbf92b144A19177cF4D"
])
  await tx.wait();
  // console.log("Swap Contracts are now", await cont.getSwapList());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
