// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.20;
pragma abicoder v2;
import "hardhat/console.sol";
interface IERC20Debug {
    function balanceOf(address account) external view returns (uint256);
    function approve(address account, uint amount) external returns (bool);
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
    function decimals() external view returns (uint8);
}
contract TestSwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    mapping(address => mapping(address => uint256)) public ratios;
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut)
    {
        IERC20Debug tokenIn = IERC20Debug(params.tokenIn);
        IERC20Debug tokenOut = IERC20Debug(params.tokenOut);
        tokenIn.transferFrom(address(msg.sender), address(this), params.amountIn);
        amountOut = calcAmount(params.tokenIn, params.tokenOut, params.amountIn );
        tokenOut.mint(msg.sender, amountOut);
    }
    function setRatio(address tokenIn,address tokenOut, uint256 ratio) external{
        ratios[tokenIn][tokenOut] = ratio;
    }
    function calcAmount(address tokenIn,address tokenOut, uint256 amountIn) public view returns (uint256){
        
        return amountIn * ratios[tokenIn][tokenOut] / 10 ** IERC20Debug(tokenIn).decimals();
    }
}