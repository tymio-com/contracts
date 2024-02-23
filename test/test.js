const { expect } = require('chai');
const Web3 = require('web3');
const expirationsOriginal = require('../data/expirations.json');
const { cToken, sToken, wait } = require('./includes/utils');
const {
  getAdditionalAmount,
  postOrders,
  replaceUserAddresses,
  executeOrders,
  claimOrders,
  fullWithdrawal,
  getArgsForExecuteOrders,
} = require('./includes/expiration');
const {
  setRatio,
  setAcceptableTokens,
  getSwapsOutMinimal,
} = require('./includes/contract');
const {
  deployTokens,
  deploySwapRouter,
  deployPayer,
  mintTokens,
  getSigners,
  setAdditionalAmountToContract,
  checkContractBalances,
  sendEthForTransfer,
  checkEmptyBalances,
} = require('./includes/ethers');
const { tokensV1 } = require('./includes/constants');
const BN = Web3.utils.BN;

let owner,
  owner2,
  service,
  users,
  tokens,
  swapRouter,
  payer,
  tokensV3,
  expiration,
  signers,
  ethBalance;
let expirations = expirationsOriginal;

describe('Expiration', async () => {
  it('Deploy contracts', async () => {
    tokens = await deployTokens();
    swapRouter = await deploySwapRouter();
    payer = await deployPayer(swapRouter.address, tokens.weth.address);
  });
  it('Prepare contract for expiration', async () => {
    expiration = expirations[60];
    tokensV3 = {
      USDC: tokens.usdc,
      WETH: tokens.weth,
      WBTC: tokens.wbtc,
      ETH: tokens.weth,
    };
    tokensV3[tokens.usdc.address] = 'USDC';
    tokensV3[tokens.weth.address] = 'WETH';
    tokensV3[tokens.wbtc.address] = 'WBTC';
    await setRatio(swapRouter, tokensV3, expiration.prices);
  });
  it('Prepare accounts', async () => {
    signers = await getSigners();
    service = signers[0];
    owner = signers[1];
    owner2 = signers[2];
    users = signers.slice(3)[0];
    await sendEthForTransfer(owner, tokens.weth.address);
    await mintTokens([service, owner, owner2, ...users], tokensV3);
  });
  it('Set acceptable tokens', async () => {
    await setAcceptableTokens(payer, tokensV3);
  });
  it('Set payer address', async () => {
    const user = users[0];
    const args = [owner.address];
    expect(payer.connect(user).setPayerAddress(...args)).to.be.revertedWith(
      'NOT THE OWNERS'
    );
    tx = await payer.setPayerAddress(...args);
    tx = await tx.wait();
    const payerAddress = await payer.payerAddress();
    expect(payerAddress).to.equal(owner.address);
  });
  it('Replace user addresses', async () => {
    expiration = await replaceUserAddresses(expiration, users);
  });
  it('Set additional amount to contract', async () => {
    const additionalAmount = getAdditionalAmount(expiration);
    await setAdditionalAmountToContract(
      payer,
      additionalAmount,
      owner,
      tokensV3
    );
    const balance = await payer
      .connect(owner)
      .getTokenBalance(tokensV3['USDC'].address);
    expect(cToken(balance, 'USDC')).to.equal(additionalAmount);
  });
  it('Post orders', async () => {
    const orderDuration = 2;
    expiration = await postOrders(payer, expiration, orderDuration, tokensV3);
    const now = new BN(new Date().getTime() / 1000);
    for (const order of expiration.orders) {
      const contractOrder = await payer.orders(order.contract_id);
      expect(contractOrder.user).to.equal(order.user);
      expect(contractOrder.tokenIn).to.equal(
        tokensV3[tokensV1[order.tokenIn]].address
      );
      expect(contractOrder.amountIn).to.equal(
        sToken(order.amountIn, tokensV1[order.tokenIn])
      );
      expect(contractOrder.tokenOut).to.equal(
        tokensV3[order.targetTokenSymbolOut].address
      );
      expect(contractOrder.amountOut).to.equal(sToken(0));
      expect(contractOrder.price).to.equal(sToken(order.price, 'USD'));
      expect(contractOrder.additionalAmount).to.equal(sToken(0));
      expect(contractOrder.completed).to.be.false;
      expect(contractOrder.claimed).to.be.false;
    }
  });
  it('Execute orders', async () => {
    const expirationDuration = 2;
    const args = await getArgsForExecuteOrders(expiration);
    expect(args[0].length).to.equal(expiration.orders.length);
    expect(args[1].length).to.equal(expiration.orders.length);
    expect(args[2].length).to.equal(expiration.orders.length);
    const swapOutMinimal = await getSwapsOutMinimal(
      payer,
      args,
      expiration.prices,
      tokensV3
    );
    await wait(expirationDuration);
    await executeOrders(payer, args, swapOutMinimal, false, tokensV3);
    const now = new BN(new Date().getTime() / 1000);
    for (const order of expiration.orders) {
      const contractOrder = await payer.orders(order.contract_id);
      expect(contractOrder.user).to.equal(order.user);
      expect(contractOrder.tokenIn).to.equal(
        tokensV3[tokensV1[order.tokenIn]].address
      );
      expect(contractOrder.amountIn).to.equal(
        sToken(order.amountIn, tokensV1[order.tokenIn])
      );
      expect(contractOrder.tokenOut).to.equal(
        tokensV3[tokensV1[order.tokenOut]].address
      );
      expect(contractOrder.amountOut).to.equal(
        sToken(order.amountOut, tokensV1[order.tokenOut])
      );
      expect(contractOrder.price).to.equal(sToken(order.price, 'USD'));
      expect(contractOrder.additionalAmount).to.equal(
        sToken(order.additionalAmount, 'USD')
      );
      expect(contractOrder.completed).to.be.true;
      expect(contractOrder.claimed).to.be.false;
    }
  });
  it('Claim orders', async () => {
    await claimOrders(payer, expiration, tokensV3);

    const now = new BN(new Date().getTime() / 1000);
    for (const order of expiration.orders) {
      const contractOrder = await payer.orders(order.contract_id);
      expect(contractOrder.user).to.equal(order.user);
      expect(contractOrder.tokenIn).to.equal(
        tokensV3[tokensV1[order.tokenIn]].address
      );
      expect(contractOrder.amountIn).to.equal(
        sToken(order.amountIn, tokensV1[order.tokenIn])
      );
      expect(contractOrder.tokenOut).to.equal(
        tokensV3[tokensV1[order.tokenOut]].address
      );
      expect(contractOrder.amountOut).to.equal(
        sToken(order.amountOut, tokensV1[order.tokenOut])
      );
      expect(contractOrder.price).to.equal(sToken(order.price, 'USD'));
      expect(contractOrder.additionalAmount).to.equal(
        sToken(order.additionalAmount, 'USD')
      );
      expect(contractOrder.completed).to.be.true;
      expect(contractOrder.claimed).to.be.true;
    }
  });
  it('Check contract balances', async () => {
    await checkContractBalances(payer, expiration, tokensV3);
  });
  it('Full withdrawal', async () => {
    await fullWithdrawal(payer, expiration, tokensV3);
  });
  it('Check empty balances', async () => {
    await checkEmptyBalances(payer, expiration, tokensV3);
  });
  it('Set pool see', async () => {
    const basicPoolFee = await payer.poolFee();
    const newPoolFee = basicPoolFee + 1;
    const args = [newPoolFee];
    const user = users[0];

    expect(payer.connect(user).setPoolFee(...args)).to.be.revertedWith(
      'NOT THE OWNERS'
    );
    await payer.setPoolFee(...args);
    const poolFee = await payer.poolFee();
    expect(poolFee).to.equal(newPoolFee);
  });
  it('Set max additional amount percentage', async () => {
    const basicMaxAdditionalAmountPercentage =
      await payer.maxAdditionalAmountPercentage();
    const newMaxAdditionalAmountPercentage =
      basicMaxAdditionalAmountPercentage + 1;
    const args = [newMaxAdditionalAmountPercentage];
    const user = users[0];

    expect(
      payer.connect(user).setMaxAdditionalAmountPercentage(...args)
    ).to.be.revertedWith('NOT THE OWNERS');
    await payer.setMaxAdditionalAmountPercentage(...args);
    const maxAdditionalAmountPercentage =
      await payer.maxAdditionalAmountPercentage();
    expect(maxAdditionalAmountPercentage).to.equal(
      newMaxAdditionalAmountPercentage
    );
  });
  it('Set owner1 address', async () => {
    const args = [service.address];
    const user = users[0];
    expect(payer.connect(user).setOwner1Address(...args)).to.be.revertedWith(
      'NOT THE OWNERS'
    );
    await payer.setOwner1Address(...args);
    const owner1 = await payer.owner1();
    expect(owner1).to.equal(service.address);
  });
  it('Set owner2 address', async () => {
    const args = [owner.address];
    const user = users[0];
    expect(payer.connect(user).setOwner2Address(...args)).to.be.revertedWith(
      'NOT THE OWNERS'
    );
    await payer.setOwner2Address(...args);
    const owner2 = await payer.owner2();
    expect(owner2).to.equal(owner.address);
  });
  it('Set service address', async () => {
    const args = [owner2.address];
    const user = users[0];
    expect(payer.connect(user).setServiceAddress(...args)).to.be.revertedWith(
      'NOT THE OWNERS'
    );
    await payer.setServiceAddress(...args);
    const serviceAddress = await payer.service();
    expect(serviceAddress).to.equal(owner2.address);
  });
  it('Get eth balance', async () => {
    await owner.sendTransaction({ to: payer.address, value: sToken(1, 'ETH') });
    ethBalance = await payer.getEthBalance();
    expect(ethBalance).to.equal(sToken(1, 'ETH'));
  });
  it('Get back eth', async () => {
    const args = [owner.address, ethBalance];
    const user = users[0];
    expect(payer.connect(user).getBackEth(...args)).to.be.revertedWith(
      'NOT THE OWNERS'
    );
    await payer.getBackEth(...args);
    ethBalance = await payer.getEthBalance();
    expect(cToken(ethBalance, 'ETH')).to.equal(cToken(0, 'ETH'));
  });
  it('Edit acceptable token', async () => {
    const args = [tokensV3['WBTC'].address, false, false];
    const user = users[0];
    expect(payer.connect(user).editAcceptableToken(...args)).to.be.revertedWith(
      'NOT THE OWNERS'
    );
    await payer.connect(owner).editAcceptableToken(...args);
    expect(await payer.acceptableTokensArray(0)).to.equal(
      tokensV3['USDC'].address
    );
    expect(await payer.acceptableTokensArray(1)).to.equal(
      tokensV3['WETH'].address
    );
    tx = await payer.editAcceptableToken(tokensV3['WBTC'].address, true, false);
    await tx.wait();
    expect(await payer.acceptableTokensArray(2)).to.equal(
      tokensV3['WBTC'].address
    );
  });
  it("If the order wasn't completed in time, revert to the original token and amount", async () => {
    const orderDuration = 1;
    const expirationCopy = await postOrders(
      payer,
      { ...expiration, orders: [expiration.orders[0]] },
      orderDuration,
      tokensV3
    );
    const order = expirationCopy.orders[0];
    const expirationDuration = 1;
    await wait(expirationDuration);
    const maxExecutionTime = await payer.maxExecutionTime();
    const now = new Date().getTime() / 1000;
    let contractOrder = await payer.orders(order.contract_id);
    if (
      !contractOrder.completed &&
      now > order.endTimestamp + maxExecutionTime
    ) {
      await claimOrders(payer, expirationCopy, tokensV3);
      contractOrder = await payer.orders(order.contract_id);
      expect(contractOrder.tokenOut).to.equal(contractOrder.tokenIn);
      expect(contractOrder.amountOut).to.equal(contractOrder.amountIn);
    }
  });
  it("Forced claims are only available to the order's creator", async () => {
    const orderDuration = 1;
    const expirationCopy = await postOrders(
      payer,
      { ...expiration, orders: [expiration.orders[0]] },
      orderDuration,
      tokensV3
    );
    const order = expirationCopy.orders[0];
    const expirationDuration = 1;
    const args = await getArgsForExecuteOrders(expirationCopy);
    const swapOutMinimal = await getSwapsOutMinimal(
      payer,
      args,
      expirationCopy.prices,
      tokensV3
    );
    await wait(expirationDuration);
    await executeOrders(payer, args, swapOutMinimal, false, tokensV3);
    const id = order.contract_id;
    const user = order.signer;
    const claimTokenAddress = tokensV3['USDC'].address;
    expect(
      payer.connect(user).claimOrder(id, claimTokenAddress, true)
    ).to.be.revertedWith('AVAILABLE ONLY OWNER');
    payer.claimOrder(id, claimTokenAddress, true);
  });
  it('Execute orders exceptions trigger', async () => {
    const user = users[0];
    const orderDuration = 5;
    const orders = expiration.orders.filter((order) => order.order_executed);
    const expirationCopy = await postOrders(
      payer,
      {
        ...expiration,
        orders,
      },
      orderDuration,
      tokensV3
    );
    const expirationDuration = 5;
    const args = await getArgsForExecuteOrders(expirationCopy);
    const swapOutMinimal = await getSwapsOutMinimal(
      payer,
      args,
      expirationCopy.prices,
      tokensV3
    );
    expect(
      payer
        .connect(user)
        .executeOrders(args, swapOutMinimal, false, tokensV3['USDC'].address)
    ).to.be.revertedWith('NOT THE ALLOWED ADDRESS');
    expect(
      payer.executeOrders(args, swapOutMinimal, false, tokensV3['USDC'].address)
    ).to.be.revertedWith('WRONG EXPIRATION TIME');
    await wait(expirationDuration);
    const fakeArgs = JSON.parse(JSON.stringify(args));
    fakeArgs[1].push(false);
    expect(
      payer.executeOrders(
        fakeArgs,
        swapOutMinimal,
        false,
        tokensV3['USDC'].address
      )
    ).to.be.revertedWith('DIFFERENT LENGTH');

    let swapOutMinimalCopy = JSON.parse(JSON.stringify(swapOutMinimal));
    swapOutMinimalCopy = swapOutMinimalCopy.map((item) => `${item}0`);
    expect(
      payer.executeOrders(
        args,
        swapOutMinimalCopy,
        false,
        tokensV3['USDC'].address
      )
    ).to.be.revertedWith('INCORRECT AMOUNT OUT');

    let fakeArgs2 = JSON.parse(JSON.stringify(args));
    for (const [index, id] of fakeArgs2[0].entries()) {
      const contractOrder = await payer.orders(id);
      const isUsd = tokensV3['USDC'].address === contractOrder.tokenIn;
      if (isUsd) fakeArgs2[2][index] = `${fakeArgs2[2][index]}0`;
    }
    expect(
      payer.executeOrders(
        fakeArgs2,
        swapOutMinimal,
        false,
        tokensV3['USDC'].address
      )
    ).to.be.revertedWith('WRONG ADDITIONAL AMOUNT');

    fakeArgs2 = JSON.parse(JSON.stringify(args));
    for (const [index, id] of fakeArgs2[0].entries()) {
      const contractOrder = await payer.orders(id);
      const isUsd = tokensV3['USDC'].address === contractOrder.tokenIn;
      if (!isUsd) fakeArgs2[2][index] = `${fakeArgs2[2][index]}0`;
    }
    expect(
      payer.executeOrders(
        fakeArgs2,
        swapOutMinimal,
        false,
        tokensV3['USDC'].address
      )
    ).to.be.revertedWith('WRONG ADDITIONAL AMOUNT');

    await executeOrders(payer, args, swapOutMinimal, false, tokensV3, service);

    expect(
      payer.executeOrders(args, swapOutMinimal, false, tokensV3['USDC'].address)
    ).to.be.revertedWith('ORDER ALREADY COMPLETED');

    await claimOrders(payer, expirationCopy, tokensV3);

    expect(
      payer.executeOrders(args, swapOutMinimal, false, tokensV3['USDC'].address)
    ).to.be.revertedWith('ORDER ALREADY CLAIMED');
  });
  it('Execute orders force claim', async () => {
    const orderDuration = 1;
    const expirationCopy = await postOrders(
      payer,
      { ...expiration, orders: [expiration.orders[0]] },
      orderDuration,
      tokensV3
    );
    const expirationDuration = 1;
    const args = await getArgsForExecuteOrders(expirationCopy);
    const swapOutMinimal = await getSwapsOutMinimal(
      payer,
      args,
      expirationCopy.prices,
      tokensV3
    );
    await wait(expirationDuration);
    await executeOrders(payer, args, swapOutMinimal, true, tokensV3, owner);
  });
  it('Deposit 0 eth exception', async () => {
    const user = users[0];
    const value = sToken(0, 'ETH');
    expect(
      payer.connect(user).depositEth({
        value,
      })
    ).to.be.revertedWith('NOT ALLOWED ZERO');
  });
  it('Deposit token exceptions trigger', async () => {
    const user = users[0];
    let token = tokensV3['USDC'].address;
    let amount = sToken(0, 'USDC');
    expect(payer.connect(user).deposit(token, amount)).to.be.revertedWith(
      'NOT ALLOWED ZERO'
    );
    token = users[1].address;
    amount = sToken(1, 'USDC');
    expect(payer.connect(user).deposit(token, amount)).to.be.revertedWith(
      'NOT ALLOWED TOKEN'
    );
  });
  it('Make order exceptions trigger', async () => {
    const user = users[0];
    const tokenAddressIn = tokensV3['USDC'].address;
    let tokenAddressOut = tokensV3['USDC'].address;
    const amountIn = sToken(500, 'USDC');
    const price = 2500;
    let duration = 1;

    const balanceUsdc = await payer.balanceOf(tokenAddressIn, user.address);
    tx = await payer.connect(user).fullWithdrawal(tokenAddressIn, balanceUsdc);
    tx = await tx.wait();

    expect(
      payer
        .connect(user)
        .makeOrder(tokenAddressIn, tokenAddressOut, amountIn, price, duration)
    ).to.be.revertedWith('NO TOKEN BALANCE');

    await mintTokens([user], tokensV3);
    expect(
      payer.connect(user).deposit(tokenAddressIn, amountIn)
    ).to.be.revertedWith('TRANSFER FROM ERROR');
    tx = await tokensV3['USDC'].connect(user).approve(payer.address, amountIn);
    tx = await tx.wait();
    tx = await payer.connect(user).deposit(tokenAddressIn, amountIn);
    tx = await tx.wait();

    expect(
      payer
        .connect(user)
        .makeOrder(tokenAddressIn, tokenAddressOut, amountIn, price, duration)
    ).to.be.revertedWith('SAME TOKENS');

    const maxDuration = await payer.maxDuration();
    duration += Number(maxDuration.toString());
    tokenAddressOut = tokensV3['WETH'].address;
    expect(
      payer
        .connect(user)
        .makeOrder(tokenAddressIn, tokenAddressOut, amountIn, price, duration)
    ).to.be.revertedWith('DURATION MORE MAXIMUM');
  });
  it('Emergency quit', async () => {
    const tokens = [
      { address: tokensV3['USDC'].address, symbol: 'USDC' },
      { address: tokensV3['WETH'].address, symbol: 'WETH' },
      { address: tokensV3['WBTC'].address, symbol: 'WBTC' },
    ];
    const user = users[0];
    const orderDuration = 1;
    const expirationCopy = await postOrders(
      payer,
      { ...expiration, orders: [expiration.orders[0]] },
      orderDuration,
      tokensV3
    );
    const contract_id = expirationCopy.orders[0].contract_id;
    const order = await payer.orders(contract_id);
    const expirationDuration = orderDuration;
    const args = await getArgsForExecuteOrders(expirationCopy);
    const swapOutMinimal = await getSwapsOutMinimal(
      payer,
      args,
      expirationCopy.prices,
      tokensV3
    );
    await wait(expirationDuration);
    await executeOrders(payer, args, swapOutMinimal, false, tokensV3, owner2);
    const fullAccessAfter = await payer.fullAccessAfter();

    expect(
      payer.emergencyQuit(order.user, tokens[0].address, sToken(1, 'USDC'))
    ).to.be.revertedWith('');

    await wait(fullAccessAfter);

    const claimTokenAddress = tokensV3['USDC'].address;
    tx = await payer.claimOrder(contract_id, claimTokenAddress, false);
    tx = await tx.wait();

    for (const token of tokens) {
      const balance = await payer.balanceOf(token.address, order.user);
      if (cToken(balance, token.symbol) > 0) {
        expect(
          payer.connect(user).emergencyQuit(order.user, token.address, balance)
        ).to.be.revertedWith('AVAILABLE ONLY OWNER');
        tx = await payer.emergencyQuit(order.user, token.address, balance);
        tx = await tx.wait();
      }
    }
  });
});
