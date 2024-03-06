const { cToken, convertFloatToBnString, sToken } = require('./utils');
const { tokensV1, DECIMALS } = require('./constants');

function getAdditionalAmount(expiration) {
  let additionalAmountSum = 0;
  for (const order of expiration.orders) {
    additionalAmountSum += Number(order.additionalAmount);
  }
  additionalAmountSum = cToken(
    convertFloatToBnString(
      Math.round(additionalAmountSum * 10 ** DECIMALS.USDC) /
        10 ** DECIMALS.USDC,
      DECIMALS.USDC
    ),
    'USDC'
  );
  return additionalAmountSum;
}

async function replaceUserAddresses(expiration, users) {
  const usersObj = {};
  let cnt = 0;
  for (const [_, order] of expiration.orders.entries()) {
    if (usersObj[order.user]) continue;
    else {
      usersObj[order.user] = users[cnt];
      cnt++;
    }
  }
  for (const [_, order] of expiration.orders.entries()) {
    order.signer = usersObj[order.user];
    order.user = usersObj[order.user].address;
  }
  return expiration;
}

async function postOrders(payer, expiration, orderDuration, tokensV3) {
  for (const order of expiration.orders) {
    const tokenInSymbol = tokensV1[order.tokenIn];
    const signer = order.signer;
    const amountIn = order.amountIn;
    const price = order.price;
    const payerAddress = payer.address;
    const targetTokenSymbolOut = order.targetTokenSymbolOut;
    if (tokenInSymbol === 'ETH') {
      const _tokenAddressOut = tokensV3['USDC'].address;
      const _amount = sToken(amountIn, 'WETH');
      const _price = sToken(price, 'USDC');
      const _duration = orderDuration;
      const value = sToken(amountIn, 'ETH');
      tx = await payer
        .connect(signer)
        .depositEthAndOrder(_tokenAddressOut, _amount, _price, _duration, {
          value,
        });
      tx = await tx.wait();
    } else {
      const token = tokensV3[tokenInSymbol];
      const _tokenAddressIn = tokensV3[tokenInSymbol].address;
      const _tokenAddressOut = tokensV3[targetTokenSymbolOut].address;
      const _amount = sToken(amountIn, tokenInSymbol);
      const _price = sToken(price, 'USDC');
      const _duration = orderDuration;

      tx = await token.connect(signer).approve(payerAddress, _amount);
      tx = await tx.wait();
      tx = await payer
        .connect(signer)
        .depositAndOrder(
          _tokenAddressIn,
          _tokenAddressOut,
          _amount,
          _amount,
          _price,
          _duration
        );
      tx = await tx.wait();
    }
    for (const event of tx.events) {
      if (event.event === 'NewOrder') {
        order.contract_id = event.args.orderId.toString();
        order.endTimestamp = new Date().getTime() / 1000 + orderDuration;
      }
    }
  }

  const id = expiration.orders[expiration.orders.length - 1].contract_id;
  const user = expiration.orders[expiration.orders.length - 1].signer;
  const claimTokenAddress = tokensV3['USDC'].address;
  const args = [id, claimTokenAddress, false];
  expect(payer.connect(user).claimOrder(...args)).to.be.revertedWith(
    'ORDER NOT COMPLETED'
  );
  return expiration;
}

async function getArgsForExecuteOrders(expiration) {
  let args = [[], [], []];
  for (const order of expiration.orders) {
    args[0].push(order.contract_id);
    args[1].push(order.order_executed);
    args[2].push(sToken(order.additionalAmount, 'USD'));
  }
  return args;
}

async function executeOrders(
  payer,
  args,
  swapOutMinimal,
  claimOrders,
  tokensV3,
  from = ''
) {
  if (from) {
    tx = await payer
      .connect(from)
      .executeOrders(
        args,
        swapOutMinimal,
        claimOrders,
        tokensV3['USDC'].address
      );
    tx = await tx.wait();
  } else {
    tx = await payer.executeOrders(
      args,
      swapOutMinimal,
      claimOrders,
      tokensV3['USDC'].address
    );
    tx = await tx.wait();
  }
}

async function claimOrders(payer, expiration, tokensV3) {
  const id = 0;
  const user = expiration.orders[0].signer;
  let claimTokenAddress = tokensV3['WBTC'].address;
  const args = [id, claimTokenAddress, false];
  expect(
    payer.connect(user).claimOrder(id, claimTokenAddress, false)
  ).to.be.revertedWith('IS NOT USD TOKEN');
  for (const order of expiration.orders) {
    const id = order.contract_id;
    const user = order.signer;
    const claimTokenAddress = tokensV3['USDC'].address;
    expect(user.address).to.equal(order.user);
    tx = await payer.connect(user).claimOrder(id, claimTokenAddress, false);
    tx = await tx.wait();
  }
  expect(payer.connect(user).claimOrder(...args)).to.be.revertedWith(
    'ORDER ALREADY CLAIMED'
  );
}

async function fullWithdrawal(payer, expiration, tokensV3) {
  const usdcAddress = tokensV3['USDC'].address;
  const wethAddress = tokensV3['WETH'].address;
  const wbtcAddress = tokensV3['WBTC'].address;
  for (const order of expiration.orders) {
    const signer = order.signer;
    const address = order.user;
    const balanceWeth = await payer.balanceOf(wethAddress, address);
    const balanceWbtc = await payer.balanceOf(wbtcAddress, address);
    const balanceUsdc = await payer.balanceOf(usdcAddress, address);
    if (cToken(balanceWeth, 'WETH') > 0) {
      tx = await payer.connect(signer).fullWithdrawalETH(balanceWeth);
      tx = await tx.wait();
    }
    if (cToken(balanceWbtc, 'WBTC') > 0) {
      tx = await payer.connect(signer).fullWithdrawal(wbtcAddress, balanceWbtc);
      tx = await tx.wait();
    }
    if (cToken(balanceUsdc, 'USDC') > 0) {
      tx = await payer.connect(signer).fullWithdrawal(usdcAddress, balanceUsdc);
      tx = await tx.wait();
    }
  }

  const user = expiration.orders[0].signer;
  let args = [sToken(1, 'ETH')];
  expect(payer.connect(user).fullWithdrawalETH(...args)).to.be.revertedWith(
    'NOT ENOUGH WETH TOKENS ON THE BALANCE'
  );
  args = [usdcAddress, sToken(1, 'USDC')];
  expect(payer.connect(user).fullWithdrawal(...args)).to.be.revertedWith(
    'NOT ENOUGH TOKENS ON THE BALANCE'
  );
}

module.exports = {
  getAdditionalAmount,
  postOrders,
  replaceUserAddresses,
  executeOrders,
  claimOrders,
  fullWithdrawal,
  getArgsForExecuteOrders,
};
