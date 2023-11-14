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

  // console.log("Swap Contracts are now", await cont.getSwapList());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
