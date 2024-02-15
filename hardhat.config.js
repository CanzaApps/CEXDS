require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-web3");
require("solidity-coverage");
require("hardhat-deploy");
require("hardhat-gas-reporter");
require("@nomiclabs/hardhat-solhint");
require("hardhat-spdx-license-identifier");
require("hardhat-docgen");
require("@nomiclabs/hardhat-etherscan");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-contract-sizer");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-waffle");

const dotenv = require('dotenv');

dotenv.config();

const config = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true
      /*, debug: {
        revertStrings: "strip"
      }*/
    }
  },
  namedAccounts: {
    deployer: {
      default: 0
    }
  },
  paths: {
    sources: "./contracts/cexDS"
  },
  networks: {
    mainnet: {
      url: "https://mainnet.infura.io/v3/9e5f0d08ad19483193cc86092b7512f2",
      chainId: 1,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    ganache: {
      url: "http://127.0.0.1:8545"
    },
    localhost: {
      url: "http://127.0.0.1:8545"
    },
    alfajores: {
      url: "https://alfajores-forno.celo-testnet.org",
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      chainId: 44787
    },
    celo: {
      url: "https://forno.celo.org",
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      chainId: 42220
    },
    fuji: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      chainId: 43113
    },
    hardhat: {
      /*forking: {
        url:
          "https://eth-mainnet.alchemyapi.io/v2/pvGDp1uf8J7QZ7MXpLhYs_SnMnsE0TY5"
      },*/
      /*forking: {
        url:
          "https://eth-rinkeby.alchemyapi.io/v2/2LxgvUYd5FzgiXVoAWlq-KyM4v-E7KJ4"
      },*/
      /*forking: {
        url:
          "https://polygon-rpc.com"
      },*/
      allowUnlimitedContractSize: true
    },
    rinkeby: {
      url:
        "https://eth-rinkeby.alchemyapi.io/v2/2LxgvUYd5FzgiXVoAWlq-KyM4v-E7KJ4",
      chainId: 4,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : []
    },
    goerli: {
      url:
        "https://eth-goerli.alchemyapi.io/v2/2LxgvUYd5FzgiXVoAWlq-KyM4v-E7KJ4",
      chainId: 5,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : []
    },
    

    polygon: {
      url: `https://polygon-mumbai.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : []
    },

    // avalanche: {
    //   url: "https://api.avax.network/ext/bc/C/rpc",
    //   chainId: 43114,
    //   from: secret.account,
    //   accounts: {
    //     mnemonic: secret.mnemonic
    //   }
    // },
    // fantom: {
    //   url: "https://rpc.ftm.tools",
    //   chainId: 250,
    //   from: secret.account,
    //   accounts: {
    //     mnemonic: secret.mnemonic
    //   }
    // }
  },
  spdxLicenseIdentifier: {
    runOnCompile: true
  },
  etherscan: {
    apiKey: process.env.CELOSCAN_KEY
  },
  gasReporter: {
    currency: "USD",
    coinmarketcap: "b0c64afd-6aca-4201-8779-db8dc03e9793"
  },
  typechain: {
    target: "ethers-v5"
  }
};

module.exports = config;

