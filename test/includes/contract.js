const { expect } = require('chai');
const { DECIMALS } = require('./constants');
const { sToken, thowDotPart, cToken, roudToDecimals } = require('./utils');

async function setAcceptableTokens(payer, tokens) {
  tx = await payer.editAcceptableToken(tokens['USDC'].address, true, true, tokens['USDC'].minimalAmount);
  await tx.wait();
  tx = await payer.editAcceptableToken(tokens['WETH'].address, true, false, tokens['WETH'].minimalAmount);
  await tx.wait();
  tx = await payer.editAcceptableToken(tokens['WBTC'].address, true, false, tokens['WBTC'].minimalAmount);
  await tx.wait();
  expect(await payer.acceptableTokensArray(0)).to.equal(tokens['USDC'].address);
  expect(await payer.acceptableTokensArray(1)).to.equal(tokens['WETH'].address);
  expect(await payer.acceptableTokensArray(2)).to.equal(tokens['WBTC'].address);
}

async function setRatio(swapRouter, tokens, prices) {
  const usdWbtcPrice = thowDotPart(sToken(1, 'WBTC') / prices['WBTC']);
  const wbtcUsdPrice = sToken(prices['WBTC'], 'USD');
  const ethUsdPrice = sToken(prices['WETH'], 'USD');
  const usdEthPrice = thowDotPart(sToken(1, 'WETH') / prices['WETH']);
  tx = await swapRouter.setRatio(
    tokens['USDC'].address,
    tokens['WETH'].address,
    usdEthPrice
  );
  await tx.wait();
  tx = await swapRouter.setRatio(
    tokens['WETH'].address,
    tokens['USDC'].address,
    ethUsdPrice
  );
  await tx.wait();
  if (prices['WBTC']) {
    tx = await swapRouter.setRatio(
      tokens['WBTC'].address,
      tokens['USDC'].address,
      wbtcUsdPrice
    );
    await tx.wait();
    tx = await swapRouter.setRatio(
      tokens['USDC'].address,
      tokens['WBTC'].address,
      usdWbtcPrice
    );
    await tx.wait();
  }
}

async function getAcceptableTokens(payer) {
  const acceptableTokensArray = [];
  let cnt = 0;
  while (true) {
    try {
      const token = await payer.acceptableTokensArray(cnt);
      acceptableTokensArray.push(token);
      cnt++;
    } catch (e) {
      break;
    }
  }
  return acceptableTokensArray;
}

async function getOrder(payer, id) {
  const token = await payer.orders(id);
  return token;
}

async function getSwapsOutMinimal(payer, args, prices, tokensV3) {
  const swapsIn = {};
  const swapsOut = {};
  const swapsOutMinimal = {};
  const acceptableTokensArray = await getAcceptableTokens(payer);
  const params = {
    orderIds: args[0],
    swap: args[1],
    additionalAmount: args[2],
    swapMinimal: [],
  };

  if (
    params.orderIds.length !== params.swap.length ||
    params.swap.length !== params.additionalAmount.length
  )
    throw new Error('DIFFERENT LENGTH');

  for (let i = 0; i < acceptableTokensArray.length; i++) {
    for (let j = 0; j < acceptableTokensArray.length; j++) {
      if (acceptableTokensArray[i] === acceptableTokensArray[j]) continue;
      if (!swapsIn[acceptableTokensArray[i]])
        swapsIn[acceptableTokensArray[i]] = {};
      if (!swapsOut[acceptableTokensArray[i]])
        swapsOut[acceptableTokensArray[i]] = {};
      if (!swapsOutMinimal[acceptableTokensArray[i]])
        swapsOutMinimal[acceptableTokensArray[i]] = {};
      swapsOutMinimal[acceptableTokensArray[i]][acceptableTokensArray[j]] = 0;
      swapsIn[acceptableTokensArray[i]][acceptableTokensArray[j]] = 0;
      swapsOut[acceptableTokensArray[i]][acceptableTokensArray[j]] = 0;
    }
  }

  for (let i = 0; i < params.orderIds.length; i++) {
    if (params.swap[i]) {
      const order = await getOrder(payer, params.orderIds[i]);
      swapsIn[order.tokenIn][order.tokenOut] =
        swapsIn[order.tokenIn][order.tokenOut] +
        parseFloat(cToken(order.amountIn, tokensV3[order.tokenIn]));
      const isUsd = await payer.isUsdToken(order.tokenIn);
      if (isUsd) {
        swapsOut[order.tokenIn][order.tokenOut] =
          swapsOut[order.tokenIn][order.tokenOut] +
          parseFloat(cToken(order.amountIn, tokensV3[order.tokenIn])) /
            prices[tokensV3[order.tokenOut]];
      } else {
        swapsOut[order.tokenIn][order.tokenOut] =
          swapsOut[order.tokenIn][order.tokenOut] +
          parseFloat(cToken(order.amountIn, tokensV3[order.tokenIn])) *
            prices[tokensV3[order.tokenIn]];
      }
    }
  }

  for (let i = 0; i < acceptableTokensArray.length; i++) {
    for (let j = 0; j < acceptableTokensArray.length; j++) {
      if (swapsOut[acceptableTokensArray[i]][acceptableTokensArray[j]] > 0) {
        const tokenIn = acceptableTokensArray[i];
        const tokenOut = acceptableTokensArray[j];
        const amount = swapsOut[tokenIn][tokenOut];
        swapsOutMinimal[tokenIn][tokenOut] = roudToDecimals(
          amount - (amount / 100) * 5,
          DECIMALS[tokensV3[tokenOut]]
        );
      }
    }
  }
  let swapsCount = 0;
  const result = [];
  for (let i = 0; i < acceptableTokensArray.length; i++) {
    for (let j = 0; j < acceptableTokensArray.length; j++) {
      if (swapsIn[acceptableTokensArray[i]][acceptableTokensArray[j]] > 0) {
        const tokenIn = acceptableTokensArray[i];
        const tokenOut = acceptableTokensArray[j];
        const amountIn =
          swapsIn[acceptableTokensArray[i]][acceptableTokensArray[j]];
        const amountOutDesired =
          swapsOut[acceptableTokensArray[i]][acceptableTokensArray[j]];
        const amountOutMinimum =
          swapsOutMinimal[acceptableTokensArray[i]][acceptableTokensArray[j]];

        expect(amountOutMinimum).to.equal(
          roudToDecimals(
            amountOutDesired - (amountOutDesired / 100) * 5,
            DECIMALS[tokensV3[tokenOut]]
          )
        );
        result.push(sToken(amountOutMinimum, tokensV3[tokenOut]));
        swapsCount++;
      }
    }
  }

  return result;
}

module.exports = {
  setRatio,
  setAcceptableTokens,
  getAcceptableTokens,
  getSwapsOutMinimal,
};
