# Centralized eXChange Default Swaps (CXDS)

CXDS (Centralized eXchange Default Swaps) provides credit default swaps (CDS) for deposits in centralized exchanges. This solves a fundamental risk associated with using centralized exchanges, by offering a hedge against exchanges defaulting. Users will be able to buy CDSs for specific exchanges to provide protection, or sell CDSs to earn a weekly yield. Moreover, unlike other insurance protocols which only provide security on certain risks and require the purchaser to prove that they personally incurred a loss. This opens the door for more advanced and dynamic markets.

## Background

Credit Default Swaps (CDS) is a financial instrument that acts like insurance on a loan. In exchange for a premium, the buyer of a CDS can claim the collateral should the covered loan default. The seller gets exposure to yield on their collateral in exchange for taking on the risk of the loan.

For more details, check our [Docs](https://docs.cxds.fi).

## Smart Contract Architecture

The Smart Contract Implementation is basically based on 4 key contracts, with functionality as follows

- CEXDefaultSwap - This houses the implementation of the Swap pool and provides the interfaces for the users to interact with the Swap pools. A single swap contract exists for a single token insured on a singular loan entity.

- SwapController - Entity with Administrative privileges over all existing swap pools. Provides the interface with Access Control to create swap pools, and implement other management functions on existing pools.

- Voting - Provides the interface to manage Decentralized multi-sig decision making from trusted pool voters at periods where a loan is defaulted.

- RateOracle - Provides interface for rate computations and other required variables.

## Technical Requirements

- YARN
- Solidity ~0.8.0
- Openzeppelin Contracts (AccessControl, SafeERC20, ERC20, Address)
- Hardhat

## Getting Started

Get a workaround with a simple local test.

```shell
git clone https://github.com/CanzaApps/CEXDS.git
cd CEXDS
yarn install
npx hardhat test
```

## Deployments

To deploy, the configurations for each contract would need to be set at deploy-configs/[<NETWORK>]/. Some of these configurations are mandatory and deployment would fail without them in place.

After updating configs, run the following

```shell
export PRIVATE_KEY=[<WALLET_PRIVATE_KEY>]

npx hardhat compile
npx hardhat deployment --reuse [true|false] --startat [swaps|controller|oracle|voting] --redeployallswaps [true|false] --network [<NETWORK_NAME>]
```

Deployment outputs can be found in `deployments/[<NETWORK_NAME>].json`

## Deployment Arguments

Parameter     | Optional | Description
--------------|----------------|----------------
`--reuse`| No | A `true` value informs the deployer to look into the deployment output file and use some of the existing deployment addresses for some of the contracts, and not redeploy them.
`--startat` | Yes | Informs the deployer from which contract to start new deployment. It is only essential when `reuse` is `true`. If otherwise, this argument is ignored. Hierarchy of contracts dependency have to be considered here. `controller >> oracle >> voting >> swaps`
`--redeployallswaps`| Yes | Informs the deployer whether to redeploy the previous existing swaps contracts in the deployment outputs file. If `true`, it only deploys the newly added swap configurations in `deploy-configs`
