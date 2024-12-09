// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const fs = require("fs");
// const { program } = require('commander');

async function getConfiguration(contract) {
  const networkName = hre.network.name;

  const config = {
    voterFeeRatio: 1,
    voterFeeComplementaryRatio: 2,
    maxSellerCount: 10,
    maxBuyerCount: 10,
    recurringFeeRatio: 1,
    recurringFeeComplementaryRatio: 3,
    votersRequired: 7,
    recurringPaymentInterval: 604800,
    secondSuperAdmin:"0x7F880bFDd349Df9d74ae7e93dd169a43D516777A",
    universalVoters: [
      "0x7F880bFDd349Df9d74ae7e93dd169a43D516777A",
      "0x7F880bFDd349Df9d74ae7e93dd169a43D516777A",
      "0x7F880bFDd349Df9d74ae7e93dd169a43D516777A",
      "0x7F880bFDd349Df9d74ae7e93dd169a43D516777A",
      "0x7F880bFDd349Df9d74ae7e93dd169a43D516777A",
      "0x7F880bFDd349Df9d74ae7e93dd169a43D516777A",
      "0x7F880bFDd349Df9d74ae7e93dd169a43D516777A",
    ],
    ownedSwaps: [
      {
        entityName: "Binance",
        entityUrl: "https://binance.com",
        tokenAddress: "0x791e2a9F7671A90A04465691eAE56CC9CF2FD92E",
        premium: 0.01,
        makerFee: 0.003,
        initialMaturityTimestamp: "",
        intialEpochDays: 7,
      },
      {
        entityName: "Gate.io",
        entityUrl: "https://gate.io",
        tokenAddress: "0xA3057965dFd404096e1e307a3Cf0f40e0250730D",
        premium: 0.01,
        makerFee: 0.003,
        initialMaturityTimestamp: "",
        intialEpochDays: 7,
      },
    ],

    thirdPartySwaps: [
      {
        entityName: "Gate.io",
        entityUrl: "https://gate.io",
        tokenAddress: "0x791e2a9F7671A90A04465691eAE56CC9CF2FD92E",
        premium: 0.01,
        makerFee: 0.003,
        initialMaturityTimestamp: "",
        intialEpochDays: 7,
        owner: "0x41f200Fa5Cb56082D7515637A3649Ecf07784F6D",
        voters: [
          "0x42d28494FA5735f53AFd233358C4E494A13007b4",
          "0xec9af0A93b9664d5eC97F1271b11e8A3868E7FEC",
          "0x82fCE39f1f2EF722D5128DfB0b8139735C7C24aC",
        ],
      },
    ],
  };

  let allPools = [];
  if (contract === "cexdefaultswap") {
    const ownedSwapConfigs = config.ownedSwaps;
    for (const conf of ownedSwapConfigs) {
      if (!conf.entityName || !conf.entityUrl || !conf.initialEpochDays)
        throw new Error("Requires fields in configs to be set");

      conf.initialMaturityTimestamp =
        conf.initialMaturityTimestamp || Math.round(Date.now() / 1000) + 604800;

      if (!conf.tokenAddress) {
        conf.tokenAddress = (
          await (
            await (await ethers.getContractFactory("ERC20Mock")).deploy()
          ).deployed()
        ).address;
      }

      conf.isThirdParty = false;
    }

    const thirdPartySwapConfigs = config.thirdPartySwaps;
    for (const conf of thirdPartySwapConfigs) {
      if (
        !conf.entityName ||
        !conf.entityUrl ||
        !conf.initialEpochDays ||
        !conf.owner
      )
        throw new Error("Requires fields in configs to be set");

      conf.initialMaturityTimestamp =
        conf.initialMaturityTimestamp || Math.round(Date.now() / 1000) + 604800;

      if (!conf.tokenAddress) {
        conf.tokenAddress = (await (await (await hre.ethers.getContractFactory("ERC20Mock")).deploy()).deployed()).address;
      }

      conf.isThirdParty = true;
    }

    allPools = [...allPools, ...ownedSwapConfigs, ...thirdPartySwapConfigs];
    return allPools;
  }

  if (!config.secondSuperAdmin)
    throw new Error("Requires secondSuperAdmin to be set in configs");

  if (contract === "controller") {
    config.maxSellerCount = config.maxSellerCount || 10;
    config.maxBuyerCount = config.maxBuyerCount || 10;
  }

  if (contract === "voting") {
    if (config.universalVoters.length < 7)
      throw new Error("Requires voter address to be set in configs");
  }

  if (contract === "oracle") {
    config.voterFeeRatio = config.voterFeeRatio || 1;
    config.voterFeeComplementaryRatio = config.voterFeeComplementaryRatio || 2;
    config.recurringFeeRatio = config.recurringFeeRatio || 1;
    config.recurringFeeComplementaryRatio =
      config.recurringFeeComplementaryRatio || 3;
    config.votersRequired = config.votersRequired || 7;
    config.recurringPaymentInterval = config.recurringPaymentInterval || 604800;
  }

  return config;
}

async function main(params, hre) {

  const [acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10] = await hre.ethers.getSigners();
  let signers = [acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10];
  // const secondAdmin = "0x1d80b14fc72d953eDfD87bF4d6Acd08547E3f1F6";
  let reuseAddresses = {};

  const runOpts = readCommandArgs(params);

  if (runOpts.reuse) {
    reuseAddresses = getReuseAddresses();
    console.log({reuseAddresses});
    if (!reuseAddresses.controller) {
      console.log("No previous controller deployment found. Forcing reuse to false");
      runOpts.reuse = false;
    }
    if (!reuseAddresses.oracle && runOpts.startAt !== 'oracle' && runOpts.reuse) {
      console.log("No previous oracle deployment found. Forcing startAt to oracle");
      runOpts.startAt = 'oracle';
    }
    if (!reuseAddresses.voting && runOpts.startAt === 'cxdefaultswap' && runOpts.reuse) {
      console.log("No previous Voting deployment found. Forcing startAt to Voting");
      runOpts.startAt = 'voting';
    }
  }

  try {
    if (!runOpts.reuse) {
      const controllerConfig = await getConfiguration("controller", hre);

      const CEXDeployer = await hre.ethers.getContractFactory("SwapController");
      const cexDeployer = await CEXDeployer.deploy(controllerConfig.secondSuperAdmin
        , controllerConfig.maxSellerCount
        , controllerConfig.maxBuyerCount
      );

      await cexDeployer.deployed();

      console.log("CEX Deployer deployed to ", cexDeployer.address);
      reuseAddresses = { ...reuseAddresses, controller: cexDeployer.address};
    }


    if ((runOpts.reuse && runOpts.startAt === 'oracle') || !runOpts.reuse) {
      const oracleConfig = await getConfiguration("oracle", hre);

      const Oracle = await hre.ethers.getContractFactory("RateOracle");
      const oracle = await Oracle.deploy(reuseAddresses.controller
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
      reuseAddresses = { ...reuseAddresses, oracle: oracle.address};
    }
    const cexDeployer = await hre.ethers.getContractAt("SwapController", reuseAddresses.controller);
    
    if ((runOpts.reuse && runOpts.startAt !== 'cxdefaultswap') || !runOpts.reuse) {
      const votingConfig = await getConfiguration("voting", hre);

      const Voting = await hre.ethers.getContractFactory("Voting");
      const voting = await Voting.deploy(votingConfig.secondSuperAdmin, reuseAddresses.controller, reuseAddresses.oracle);

      await voting.deployed();
      console.log("Voting deployed to ", voting.address);

      const whitelistTx = await voting.whiteListVoters(votingConfig.universalVoters);
      await whitelistTx.wait();

      // Add Voting Contract to controller
      let trx = await cexDeployer.setVotingContract(voting.address);
      await trx.wait();
      console.log("Here");

      // Add Voting Contract to controller
      trx = await cexDeployer.setOracleContract(reuseAddresses.oracle);
      await trx.wait();
      reuseAddresses = { ...reuseAddresses, voting: voting.address};
    }

    const swapsToCreate = await getConfiguration("cxdefaultswap", hre);

    let swapIds = [];
    for (const swap of swapsToCreate) {
      let txSwap;
      if (!runOpts.redeployAllSwaps && swap.id in reuseAddresses.swaps) continue;
      if(!swap.isThirdParty) {
        txSwap = await cexDeployer.createSwapContract(swap.entityName
          , swap.entityUrl
          , swap.tokenAddress
          , (swap.premium * 10000).toString()
          , (swap.makerFee * 10000).toString()
          , swap.initialEpochDays.toString()
          , swap.withVoterConsensus
        );
      }

      else {
        txSwap = await cexDeployer.createSwapContractAsThirdParty(swap.entityName
          , swap.entityUrl
          , swap.tokenAddress
          , (swap.premium * 10000).toString()
          , (swap.makerFee * 10000).toString()
          , swap.initialEpochDays.toString()
          , swap.withVoterConsensus
          , swap.owner
          , swap.voters
        );
      }

      await txSwap.wait();
      swapIds.push(swap.id)
    }

    const swaps = await cexDeployer.getSwapList();
    console.log(`Swaps are at ${swaps}`);
    const newlyCreated = swaps.slice(swaps.length - swapIds.length);

    const swapsCreated = swapIds.reduce((acc, curr, index) => {
      return {...acc, [curr.toString()]: newlyCreated[index]}
    }, reuseAddresses.swaps || {})

    reuseAddresses = {...reuseAddresses, swaps: swapsCreated}
    fs.writeFileSync(`./deployments/${hre.network.name}.json`, JSON.stringify(reuseAddresses));
  } catch (e) {
    console.log("Writing to deployments")
    fs.writeFileSync(`./deployments/${hre.network.name}.json`, JSON.stringify(reuseAddresses));
    throw e;
  }

}


function readCommandArgs(options) {
  const reuse = options.reuse === 'true';
  const startAt = ['controller', 'oracle', 'voting', 'cxdefaultswap'].includes(options.startat) 
  ? options.startat 
  : 'cxdefaultswap';
  const redeployAllSwaps = startAt !== 'cxdefaultswap' ? true : options.redeployallswaps || true;

  return {
    reuse: reuse ? startAt !== 'controller' : reuse
    , startAt, redeployAllSwaps
  }
}

function getReuseAddresses() {
  try {
    const config = require(`../deployments/${hre.network.name}.json`)
    console.log({config})
    return config;
  } catch (e) {
    return {};
  }
  
}

// console.log(getReuseAddresses())

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
// main().catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

module.exports = main;
