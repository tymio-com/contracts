# Tymio core contract v3
## Tests
To run the tests, you need to change the parameters in the PlayerV3.sol file to these:
```solidity
ISwapRouter public swapRouter = ISwapRouter(0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9);// custom deployed swapRouter
address public wethAddress = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9;// custom deployed weth address
uint public maxExecutionTime = 1 seconds;
uint public fullAccessAfter = 5 seconds;
```
Use `npm test`

## Coverage

Use `npm run cover`