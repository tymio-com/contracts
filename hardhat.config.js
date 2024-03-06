require('solidity-coverage');
require('@nomicfoundation/hardhat-toolbox');
require('@nomicfoundation/hardhat-chai-matchers');
require('@nomiclabs/hardhat-etherscan');
require('@nomiclabs/hardhat-web3');
require('@nomiclabs/hardhat-truffle5');
require('dotenv').config({ path: __dirname + '/.env' });
require('hardhat-change-network');

const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;

module.exports = {
  solidity: {
    compilers: [
      {
        version: '0.8.20',
        settings: { optimizer: { enabled: true, runs: 50000 } },
      }
    ],
  },
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
      allowUnlimitedContractSize: false,
      accounts: { count: 100 },
    }
  },
  mocha: {
    timeout: 30000,
  },
};
