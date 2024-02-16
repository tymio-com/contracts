// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.5 <0.9.0;
interface IERC20 {
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
    function decimals() external view returns (uint8);
}
interface IWETH9 is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external payable;
}
