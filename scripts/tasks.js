const { task } = require("hardhat/config");
// Define the 'deployment' task
task("deployment", "Deploys contracts with configurable options")
  .addOptionalParam("reuse", "Reuse previous deployments", "true", types.string)
  .addOptionalParam("startat", "Stage to start deployment", "controller", types.string)
  .addOptionalParam("redeployallswaps", "Redeploy all swaps", "true", types.string)
  .setAction(async (taskArgs, hre) => {
    // Parse task arguments
    const reuse = taskArgs.reuse === "true";
    const startat = taskArgs.startat;
    const redeployallswaps = taskArgs.redeployallswaps === "true";
    console.log("Running deployment task with options:");
    console.log(`  reuse: ${reuse}`);
    console.log(`  startat: ${startat}`);
    console.log(`  redeployallswaps: ${redeployallswaps}`);
    // Import the main deployment script
    const mainDeployment = require("../scripts/deploy.js");
    // Execute the deployment script with the provided arguments
    await mainDeployment({
      reuse: reuse,
      startat: startat,
      redeployallswaps: redeployallswaps,
    }, hre);
    console.log("Deployment task completed successfully.");
  });