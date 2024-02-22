const hre = require('hardhat');
const { DECIMALS } = require('./constants');

function sToken(amount, token) {
  const decimals = DECIMALS[token];
  let amountWei;

  if (token === 'WETH' || token === 'ETH') {
    amountWei = hre.ethers.utils.parseEther(amount.toString()).toString();
  } else {
    const amountAsBigNumber = hre.ethers.utils.parseUnits(
      amount.toString(),
      decimals
    );
    amountWei = amountAsBigNumber.toString();
  }

  return amountWei;
}

function cToken(amount, token) {
  const decimals = DECIMALS[token];
  let amountHuman;

  if (token === 'WETH' || token === 'ETH') {
    amountHuman = hre.ethers.utils.formatEther(amount.toString()).toString();
  } else {
    const amountAsBigNumber = hre.ethers.utils.formatUnits(
      amount.toString(),
      decimals
    );
    amountHuman = amountAsBigNumber.toString();
  }

  return amountHuman;
}

function thowDotPart(amount) {
  if (!String(amount).includes('.')) {
    if (String(amount) === 'Infinity') return '0';
    return String(amount);
  }
  const [left, _] = String(amount).split('.');
  return left;
}

function convertFloatToBnString(float, decimals) {
  let result;
  let [left, right] = String(float).split('.');
  if (right && right.length > decimals) right = right.slice(0, decimals);
  result = left;
  if (right) {
    right = right.padEnd(decimals, '0');
    result = left.concat(right);
  } else {
    result = result + '0'.repeat(decimals);
  }
  return result.toString().replace(/^0+/, '');
}

function roudToDecimals(target, decimals = 2) {
  if (!target || target === '0') return 0;
  const rounded = parseFloat(target).toFixed(decimals);
  return parseFloat(rounded);
}

function wait(seconds) {
  return new Promise((resolve) => {
    setTimeout(resolve, seconds * 1000);
  });
}

module.exports = {
  sToken,
  cToken,
  thowDotPart,
  convertFloatToBnString,
  wait,
  roudToDecimals,
};
