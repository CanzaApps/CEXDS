// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers } = require("hardhat");
const hre = require("hardhat");

async function main() {

  const [acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10] = await hre.ethers.getSigners();
  let signers = [acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10];
  // const secondAdmin = "0x1d80b14fc72d953eDfD87bF4d6Acd08547E3f1F6";

  const MockToken = await hre.ethers.getContractFactory("ERC20Mock");
  const mockToken = await MockToken.deploy();

  await mockToken.deployed();
  console.log("Mock Token deployed to ", mockToken.address);

  const CEXDeployer = await hre.ethers.getContractFactory("SwapController");
  const cexDeployer = await CEXDeployer.deploy(acc1.address);

  await cexDeployer.deployed();

  console.log("CEX Deployer deployed to ", cexDeployer.address);

  const superAdmin = await cexDeployer.SUPER_ADMIN();
  const doIhaverole = await cexDeployer.hasRole(superAdmin, acc0.address);

  console.log({ superAdmin, doIhaverole })

  const Voting = await hre.ethers.getContractFactory("Voting");
  const voting = await Voting.deploy(acc1.address, cexDeployer.address);

  await voting.deployed();
  console.log("Voting deployed to ", voting.address);

  // Add Voting Contract to controller
  const trx = await cexDeployer.setVotingContract(voting.address);
  await trx.wait();
  console.log("Here");

  const poolMatureTime = Math.round(Date.now()/1000) + (2*86400);

  const txSwap = await cexDeployer.createSwapContract("SampleEntity", mockToken.address, "1000", poolMatureTime.toString(), 3);

  await txSwap.wait();
  const swaps = await cexDeployer.getSwapList();

  const voterAddrs = signers.slice(4).map(sgr => sgr.address);

  const whitelistTx = await voting.whiteListVoters(voterAddrs);
  await whitelistTx.wait();

  for (const sgr of signers.slice(2, 4)) {

    let mintTx = await mockToken.mint(sgr.address, ethers.utils.parseEther("1000000"));
    await mintTx.wait();

    let approveTx = await mockToken.connect(sgr).approve(swaps[0], ethers.utils.parseEther("500000"))
    await approveTx.wait()
  }

  const swapContract = await hre.ethers.getContractAt("CEXDefaultSwap", swaps[0]);

  console.log(swapContract.address)

  let trx_ = await swapContract.connect(signers[2]).deposit(ethers.utils.parseEther("300000"))

  await trx_.wait();

  trx_ = await swapContract.connect(signers[3]).purchase(ethers.utils.parseEther("200000"));
  console.log(trx_)

  const bp = await trx_.wait();
  console.log(bp)

  let totalPremium = await swapContract.unclaimedPremium_Total();
  let totalCollateral = await swapContract.claimableCollateral_Total();
  let isPaused = await swapContract.isPaused();
  let defaulted = await swapContract.defaulted();

  console.log({ totalCollateral: totalCollateral.toString(), prem: totalPremium.toString(), isPaused, defaulted })

  let tb = await voting.connect(signers[4]).vote(swaps[0], true);
  await tb.wait()
  for (const sgr of signers.slice(5)) {

    let tx = await voting.connect(sgr).vote(swaps[0], false);
    await tx.wait()
  }

  totalPremium = await swapContract.unclaimedPremium_Total();
  totalCollateral = await swapContract.claimableCollateral_Total();
  isPaused = await swapContract.isPaused();
  defaulted = await swapContract.defaulted();

  console.log({ totalCollateral: totalCollateral.toString(), prem: totalPremium.toString(), isPaused, defaulted })

  // for (const vtr of signers.slice(4)) {

  //   let bal = await mockToken.balanceOf(vtr.address);

  //   console.log({ vtr: vtr.address, bal: bal.toString()})
  // }


  // // await cexDeployer.grantRole(superAdmin, "0xBc61e22271fbf9f6840911a49588C95c1225cD56");

  // console.log("Swap Contracts are now", await cexDeployer.getSwapList());

  // const mockToken = await hre.ethers.getContractAt("ERC20Mock", "0xA55046342cD3E44fAD34152A0e5771ee592D94ca");

  // const poolMatureTime = Math.round(Date.now()/1000) + (10*86400);

  // const cont = await hre.ethers.getContractAt("Voting", "0xb06849DC29a8565CFF104F536F6D94de6AD2Ad15");

  // // // let tx = await cont.createSwapContract("Binance", "0x5bd836f690c299F8912135d36812889B6C369780", "1500", poolMatureTime.toString(), 10);

  // // // await tx.wait();
  // // // tx = await cont.createSwapContract("Canza", "0x0E57b62ABe5873c0eF25d576C3a098d872102330", "1800", poolMatureTime.toString(), 10);
  // const tx = await cont.whiteListVoters(["0x42d28494FA5735f53AFd233358C4E494A13007b4",
  //   "0xec9af0A93b9664d5eC97F1271b11e8A3868E7FEC", "0x82fCE39f1f2EF722D5128DfB0b8139735C7C24aC", "0xd48B7065eFd80156cE62963eF58Ae9b7f4b5f07d"])
  // await tx.wait();
  // console.log("Swap Contracts are now", await cont.getSwapList());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
