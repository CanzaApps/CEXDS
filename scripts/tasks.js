const { task } = require("hardhat/config");
const deployer = require('./deploy');

task("deployment", "Smart Contract deployer")
  .addParam("reuse")
  .addOptionalParam("startat")
  .addOptionalParam("redeployallswaps")
  .setAction(async (taskArgs, hre) => {
    console.log(taskArgs)
    await deployer(taskArgs, hre).catch((error) => {
      console.error(error);
      process.exitCode = 1;
    });
  });