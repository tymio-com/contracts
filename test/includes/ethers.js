const hre = require('hardhat');
const { expect } = require('chai');
const { sToken, cToken, convertFloatToBnString } = require('./utils');
const { DECIMALS, tokensV1 } = require('./constants');

async function getSigners() {
  const accounts = await hre.ethers.getSigners();
  const service = accounts[0];
  const owner = accounts[1];
  const owner2 = accounts[2];
  const users = [];
  for (let i = 3; i < accounts.length; i++) {
    users.push(accounts[i]);
  }
  return [service, owner, owner2, users];
}

async function deployTokens() {
  const Usdc = await hre.ethers.getContractFactory('ERC20');
  let usdc = await Usdc.deploy('USDC', 'USDC', DECIMALS.USDC);
  usdc = await usdc.deployed();

  const Usdt = await hre.ethers.getContractFactory('ERC20');
  let usdt = await Usdt.deploy('USDT', 'USDT', DECIMALS.USDT);
  usdt = await usdt.deployed();

  const Wbtc = await hre.ethers.getContractFactory('ERC20');
  let wbtc = await Wbtc.deploy('WBTC', 'WBTC', DECIMALS.WBTC);
  wbtc = await wbtc.deployed();

  const WETH = await hre.ethers.getContractFactory('WETH9');
  let weth = await WETH.deploy();
  weth = await weth.deployed();
  return { usdc, usdt, weth, wbtc };
}

async function setAdditionalAmountToContract(
  payer,
  additionalAmount,
  owner,
  tokensV3
) {
  const usdc = tokensV3['USDC'];
  const usdcAddress = usdc.address;
  tx = await usdc
    .connect(owner)
    .approve(payer.address, sToken(additionalAmount, 'USDC'));
  tx = await tx.wait();
  tx = await payer
    .connect(owner)
    .deposit(usdcAddress, sToken(additionalAmount, 'USDC'));
  tx = await tx.wait();
}

async function deploySwapRouter() {
  const TestSwapRouter = await hre.ethers.getContractFactory('TestSwapRouter');
  let testSwapRouter = await TestSwapRouter.deploy();
  testSwapRouter = await testSwapRouter.deployed();
  return testSwapRouter;
}

async function deployPayer() {
  const Payer = await hre.ethers.getContractFactory('PayerV3');
  let payer = await Payer.deploy();
  payer = await payer.deployed();
  return payer;
}

async function compareBalanceUsdc(
  payer,
  balanceUsdcNeed,
  usdcAddress,
  usdcSymbol,
  address
) {
  const balanceUsdc = cToken(
    await payer.balanceOf(usdcAddress, address),
    usdcSymbol
  );
  balanceUsdcNeed = cToken(
    convertFloatToBnString(balanceUsdcNeed, DECIMALS.USDC),
    'USDC'
  );
  expect(parseFloat(balanceUsdc)).to.be.above(0);
  expect(parseFloat(balanceUsdc) - parseFloat(balanceUsdcNeed)).to.be.below(
    0.001
  );
}

async function checkEmptyBalances(payer, expiration, tokensV3) {
  for (const order of expiration.orders) {
    const user = order.user;
    const balanceUsdc = cToken(
      await payer.balanceOf(tokensV3['USDC'].address, user),
      ['USDC']
    );
    const balanceWeth = cToken(
      await payer.balanceOf(tokensV3['WETH'].address, user),
      ['WETH']
    );
    const balanceWbtc = cToken(
      await payer.balanceOf(tokensV3['WBTC'].address, user),
      ['WBTC']
    );
    expect(parseFloat(balanceUsdc)).to.equal(0);
    expect(parseFloat(balanceWeth)).to.equal(0);
    expect(parseFloat(balanceWbtc)).to.equal(0);
  }
}

async function checkContractBalances(payer, expiration, tokensV3) {
  const balanceNeed = {};
  for (const order of expiration.orders) {
    const tokenOutSymbol = tokensV1[order.tokenOut];
    const usdcSymbol = 'USDC';
    const address = order.user;
    if (tokenOutSymbol === usdcSymbol) {
      const additionalAmount = parseFloat(order.additionalAmount);
      const amountOut = parseFloat(order.amountOut);
      const balanceUsdcNeed = amountOut + additionalAmount;
      if (balanceNeed[address]) {
        if (balanceNeed[address]['USDC'])
          balanceNeed[address]['USDC'] =
            balanceNeed[address]['USDC'] + balanceUsdcNeed;
        else balanceNeed[address]['USDC'] = balanceUsdcNeed;
      } else balanceNeed[address] = { USDC: balanceUsdcNeed };
    } else {
      const additionalAmount = parseFloat(order.additionalAmount);
      const balanceUsdcNeed = additionalAmount;
      if (balanceNeed[address]) {
        if (balanceNeed[address]['USDC'])
          balanceNeed[address]['USDC'] =
            balanceNeed[address]['USDC'] + balanceUsdcNeed;
        else balanceNeed[address]['USDC'] = balanceUsdcNeed;
      } else balanceNeed[address] = { USDC: balanceUsdcNeed };

      if (balanceNeed[address][tokenOutSymbol])
        balanceNeed[address][tokenOutSymbol] =
          balanceNeed[address][tokenOutSymbol] + order.amountOut;
      else balanceNeed[address][tokenOutSymbol] = order.amountOut;
    }
  }

  for (const [address, tokens] of Object.entries(balanceNeed)) {
    for (const [tokenSymbol, value] of Object.entries(tokens)) {
      const tokenAddress = tokensV3[tokenSymbol].address;

      if (tokenSymbol === 'USDC')
        await compareBalanceUsdc(
          payer,
          value,
          tokenAddress,
          tokenSymbol,
          address
        );
      else {
        const balance = cToken(
          await payer.balanceOf(tokenAddress, address),
          tokenSymbol
        );
        const valueNeed = cToken(
          convertFloatToBnString(value, DECIMALS[tokenSymbol]),
          tokenSymbol
        );
        expect(parseFloat(balance)).to.be.above(0);
        expect(parseFloat(balance) - parseFloat(valueNeed)).to.be.below(
          0.0000001
        );
      }
    }
  }
}

async function mintTokens(accounts, tokensV3) {
  for (const account of accounts) {
    tx = await tokensV3['USDC'].mint(account.address, sToken(1000000, 'USDC'));
    await tx.wait();
    tx = await tokensV3['WBTC'].mint(account.address, sToken(100, 'WBTC'));
    await tx.wait();
  }
}

async function sendEthForTransfer(owner, wethAddress) {
  await owner.sendTransaction({ to: wethAddress, value: sToken(5000, 'ETH') });
}

module.exports = {
  deployTokens,
  deploySwapRouter,
  deployPayer,
  mintTokens,
  getSigners,
  setAdditionalAmountToContract,
  checkContractBalances,
  sendEthForTransfer,
  checkEmptyBalances,
};
