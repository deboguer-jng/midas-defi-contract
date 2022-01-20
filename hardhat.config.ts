import "hardhat-deploy";
import "@nomiclabs/hardhat-waffle";
import "@tenderly/hardhat-tenderly";
// import "@typechain/hardhat";

import { config as dotEnvConfig } from "dotenv";
import { HardhatUserConfig } from "hardhat/types";

dotEnvConfig();

const urlOverride = process.env.ETH_PROVIDER_URL;

const mnemonic =
  process.env.SUGAR_DADDY ||
  process.env.MNEMONIC ||
  "candy maple cake sugar pudding cream honey rich smooth crumble sweet treat";

const config: HardhatUserConfig = {
  tenderly: {
    username: "carlomazzaferro",
    project: "midas-contracts",
  },
  solidity: {
    compilers: [
      {
        version: "0.7.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.5.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  external: {
    contracts: [
      {
        artifacts: "./artifacts/contracts/compound",
      },
    ],
  },
  paths: {
    artifacts: "./artifacts",
    sources: "./contracts",
    tests: "./test",
  },
  defaultNetwork: "hardhat",
  namedAccounts: {
    deployer: { default: 0 },
    alice: { default: 1 },
    bob: { default: 2 },
    rando: { default: 3 },
  },
  networks: {
    hardhat: {
      saveDeployments: true,
      chainId: 1337,
      gasPrice: 20e9,
      gas: 25e6,
      allowUnlimitedContractSize: true,
    },
    localhost: {
      url: urlOverride || "http://localhost:8545",
      saveDeployments: true,
      chainId: 1337,
      gasPrice: 20e9,
      gas: 25e6,
      allowUnlimitedContractSize: true,
      accounts: [
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
        "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
        "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
        "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
        "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a",
        "0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba",
        "0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e",
        "0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356",
        "0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97",
        "0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6",
      ],
    },
    rinkeby: {
      accounts: { mnemonic },
      chainId: 4,
      url: urlOverride || process.env.RINKEBY_ETH_PROVIDER_URL || "http://localhost:8545",
    },
    bsc: {
      accounts: { mnemonic },
      chainId: 56,
      url: urlOverride || process.env.BSC_PROVIDER_URL || "https://bsc-dataseed.binance.org/",
    },
    chapel: {
      accounts: { mnemonic },
      chainId: 97,
      url: "https://data-seed-prebsc-2-s1.binance.org:8545/",
    },
    mainnet: {
      accounts: { mnemonic },
      chainId: 1,
      url: "https://eth-mainnet.alchemyapi.io/v2/2Mt-6brbJvTA4w9cpiDtnbTo6qOoySnN",
    },
  },
  // TODO: this doesnt work for me
  // typechain: {
  //   outDir: "./typechain"
  // }
};

export default config;
