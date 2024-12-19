# :rocket: Introducing CXDS: A Revolutionary Risk Mitigation Solution for Centralized Exchange Deposits

## What is CXDS?
CXDS (Centralized eXchange Default Swaps) is an innovative financial product that enables users to create credit default swaps (CDS) for deposits held in centralized exchanges. It provides a safeguard against the risks of exchange defaults, empowering users to:
- Purchase CDSs to protect their funds held in centralized exchanges.
- Sell CDSs to earn a weekly yield while participating in a dynamic risk market.  

Unlike traditional insurance protocols that focus on specific risks and require proof of personal losses, CXDS creates a more advanced and flexible risk mitigation market.

## Why CXDS Matters
- **Increased Confidence in Centralized Exchanges:** CXDS enhances user trust by mitigating potential losses tied to centralized exchange failures.
- **Addressing a Key Pain Point:** By tackling issues like exchange collapses (e.g., FTX), CXDS positions itself as a must-have solution for digital asset investors.
- **Collaboration with the HSK Ecosystem:** The HashKey Token (HSK) plays a pivotal role, serving as collateral for CXDS users. CXDS integrates HSK for premium payments and voting rewards, enhancing utility and strengthening the HashKey ecosystem.

## Key Features of CXDS
- **Dynamic Market Creation:** Facilitates broader, more versatile markets for managing risks in the digital asset space.
- **Weekly Yield Opportunities:** Sellers of CDSs earn consistent returns, contributing to a more robust financial ecosystem.
- **Collateral Optimization:** Leverages the HashKey blockchain infrastructure to provide diverse collateral options.

## What Does This Mean for You?
With CXDS, you gain access to a revolutionary product that redefines risk management for centralized exchanges. Whether you are a risk-averse user looking to protect your deposits or an active participant seeking yield opportunities, CXDS caters to your needs.

## :star2: Join the Discussion
We’re excited to bring CXDS to the HashKey ecosystem! Share your thoughts, ask questions, or contribute ideas to shape the future of decentralized risk management.
- :speech_balloon: **Get involved:** [Link to the GitHub repository]
- :link: **Learn more about HashKey and CXDS:** [Link to official documentation]

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
