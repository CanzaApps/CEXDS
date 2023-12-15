// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers } = require("hardhat");
const hre = require("hardhat");
const fs = require("fs");

async function getConfiguration(contract) {

  const networkName = hre.network.name;

  const config = require(`../deploy-configs/${networkName}/${contract.toLowerCase()}.json`)
  let allPools = []
  if (contract === "cexdefaultswap") {
    const ownedSwapConfigs = config.ownedSwaps
    for (const conf of ownedSwapConfigs) {

      if (!conf.entityName || !conf.entityUrl || !conf.initialEpochDays) 
      throw new Error("Requires fields in configs to be set");

      conf.initialMaturityTimestamp = conf.initialMaturityTimestamp || Math.round(Date.now()/1000) + 604800;

      if (!conf.tokenAddress) {
        conf.tokenAddress = (await (await (await ethers.getContractFactory("ERC20Mock")).deploy()).deployed()).address;
      }

      conf.isThirdParty = false;
    }
    
    const thirdPartySwapConfigs = config.thirdPartySwaps;
    for (const conf of thirdPartySwapConfigs) {

      if (!conf.entityName || !conf.entityUrl || !conf.initialEpochDays || !conf.owner) 
      throw new Error("Requires fields in configs to be set");

      conf.initialMaturityTimestamp = conf.initialMaturityTimestamp || Math.round(Date.now()/1000) + 604800;

      if (!conf.tokenAddress) {
        conf.tokenAddress = (await (await (await ethers.getContractFactory("ERC20Mock")).deploy()).deployed()).address;
      }

      conf.isThirdParty = true;

    }

    allPools = [...allPools, ...ownedSwapConfigs, ...thirdPartySwapConfigs];
    return allPools;
  }

  if (!config.secondSuperAdmin) throw new Error("Requires secondSuperAdmin to be set in configs")

  if (contract === "controller") {
    config.maxSellerCount = config.maxSellerCount || 10;
    config.maxBuyerCount = config.maxBuyerCount || 10;
  }

  if (contract === "voting") {
    if(config.universalVoters.length < 7) throw new Error("Requires voter address to be set in configs")
  }

  if (contract === "oracle") {
    config.voterFeeRatio = config.voterFeeRatio || 1;
    config.voterFeeComplementaryRatio = config.voterFeeComplementaryRatio || 2;
    config.recurringFeeRatio = config.recurringFeeRatio || 1;
    config.recurringFeeComplementaryRatio = config.recurringFeeComplementaryRatio || 3;
    config.votersRequired = config.votersRequired || 7;
    config.recurringPaymentInterval = config.recurringPaymentInterval || 604800;

  }

  return config;


}

async function main() {

  const [acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10] = await hre.ethers.getSigners();
  let signers = [acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10];
  // const secondAdmin = "0x1d80b14fc72d953eDfD87bF4d6Acd08547E3f1F6";

  const controllerConfig = await getConfiguration("controller");

  const CEXDeployer = await hre.ethers.getContractFactory("SwapController");
  const cexDeployer = await CEXDeployer.deploy(controllerConfig.secondSuperAdmin
    , controllerConfig.maxSellerCount
    , controllerConfig.maxBuyerCount
  );

  await cexDeployer.deployed();

  console.log("CEX Deployer deployed to ", cexDeployer.address);

  const oracleConfig = await getConfiguration("oracle");

  const Oracle = await hre.ethers.getContractFactory("RateOracle");
  const oracle = await Oracle.deploy(cexDeployer.address
    , oracleConfig.secondSuperAdmin
    , oracleConfig.voterFeeRatio
    , oracleConfig.voterFeeComplementaryRatio
    , oracleConfig.recurringFeeRatio
    , oracleConfig.recurringFeeComplementaryRatio
    , oracleConfig.votersRequired
    , oracleConfig.recurringPaymentInterval.toString()
  );

  await oracle.deployed();
  console.log("Oracle deployed to ", oracle.address);

  const votingConfig = await getConfiguration("voting");

  const Voting = await hre.ethers.getContractFactory("Voting");
  const voting = await Voting.deploy(votingConfig.secondSuperAdmin, cexDeployer.address, oracle.address);

  await voting.deployed();
  console.log("Voting deployed to ", voting.address);

  const whitelistTx = await voting.whiteListVoters(votingConfig.universalVoters);
  await whitelistTx.wait();

  // Add Voting Contract to controller
  let trx = await cexDeployer.setVotingContract(voting.address);
  await trx.wait();
  console.log("Here");

  // Add Voting Contract to controller
  trx = await cexDeployer.setOracleContract(oracle.address);
  await trx.wait();

  const swapsToCreate = await getConfiguration("cexdefaultswap");

  for (const swap of swapsToCreate) {
    let txSwap;
    if(!swap.isThirdParty) {
      txSwap = await cexDeployer.createSwapContract(swap.entityName
        , swap.entityUrl
        , swap.tokenAddress
        , (swap.premium * 10000).toString()
        , (swap.makerFee * 10000).toString()
        , swap.initialMaturityTimestamp.toString()
        , swap.initialEpochDays.toString()
      );
    }

    else {
      txSwap = await cexDeployer.createSwapContract(swap.entityName
        , swap.entityUrl
        , swap.tokenAddress
        , (swap.premium * 10000).toString()
        , (swap.makerFee * 10000).toString()
        , swap.initialMaturityTimestamp.toString()
        , swap.initialEpochDays.toString()
        , swap.owner
        , swap.voters
      );
    }

    await txSwap.wait();
  }

  const swaps = await cexDeployer.getSwapList();

  const deployments = {
    controller: cexDeployer.address,
    voting: voting.address,
    oracle: oracle.address,
    swapsCreated: swaps
  }

  fs.writeFileSync(`../deployments/${hre.network.name}.json`, JSON.stringify(deployments))

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
