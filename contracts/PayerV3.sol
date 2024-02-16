// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.7.5 <0.9.0;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol"; // Interface for Uniswap v3's swap router, for executing token swaps.
import "./interface/Tokens.sol"; // Custom interface for token interactions.
import "./lib/ArrayUtils.sol"; // Utility library for array operations.
import "./lib/SafeMath.sol"; // SafeMath library for arithmetic operations without overflows.

contract PayerV3 {    
    using SafeMath for uint256; // Enables SafeMath operations for uint256 types.
    using ArrayUtils for address[]; // Enables ArrayUtils operations for address arrays.
    address public owner1; // Address of the first owner.
    address public owner2; // Address of the second owner.
    address public service; // Address of a service account, for automated tasks.
    struct Order {
        address user; // The address of the user who created the order.
        address tokenIn; // The address of the token being sold.
        uint256 amountIn; // The amount of tokenIn being sold.
        address tokenOut; // The address of the token being bought.
        uint256 amountOut; // The amount of tokenOut being bought.
        uint256 price; // The price at which the swap is executed.
        uint256 additionalAmount; // Additional amount to be paid to the user
        uint256 endTimestamp; // Timestamp when the order expires.
        bool completed; // Whether the order has been completed.
        bool claimed; // Whether the result of the order has been claimed.
    }
    struct ExecuteOrderParams {
        // Parameters for executing multiple orders.
        uint256[] orderIds; // Array of order IDs to execute.
        bool[] swap; // Array indicating which orders should perform a swap.
        uint256[] additionalAmount; // Array of additional amounts for each order.
    }
    constructor() {
        owner1 = msg.sender; // Sets the deployer as the first owner.
        payerAddress = owner1; // Initializes payerAddress to the first owner's address.
    }
    // Fallback and receive functions for handling direct ether transfers.
    receive() external payable {}

    modifier onlyOwners() {
        // Ensures only the owners can call the modified function.
        require(msg.sender == owner1 || msg.sender == owner2, "NOT THE OWNERS");
        _;
    }
    modifier onlyOwnerOrService() {
        // Ensures only the owners or the service account can call the modified function.
        require(
            msg.sender == owner1 ||
                msg.sender == owner2 ||
                msg.sender == service,
            "NOT THE ALLOWED ADDRESS"
        );
        _;
    }
    ISwapRouter public swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    uint24 poolFee = 3000; // Fee for liquidity pool usage, in basis points.
    uint24 maxAdditionalAmountPercentage  = 500; // Maximum allowed percentage for additionalAmount, in basis points.
    uint256 swapDeadline  = 10 minutes; // Deadline for completing swaps.
    mapping(address => mapping(address => uint256)) public balances; // Tracks user balances of various tokens.
    mapping(address => mapping(address => uint256)) public swapsIn; // Tracks incoming swaps.
    mapping(address => mapping(address => uint256)) public swapsOut; // Tracks outgoing swaps.
    mapping(address => uint256) public lastUserActionTime; // Tracks the last action time of users.
    Order[] public orders; // Array of all orders.
    mapping(address => bool) public acceptableTokens; // Tracks tokens that are acceptable for trading.
    mapping(address => bool) public isUsdToken; // Tracks if a token is considered a USD token.
    address[] public acceptableTokensArray; // Array of acceptable token addresses.
    address public wethAddress; // Address of Wrapped ETH (WETH) contract.
    address public payerAddress; // Address used for making payments.
    uint maxDuration = 90 days; // Maximum duration for orders.
    uint maxExecutionTime = 1 hours;// Maximum time for executing orders 
    uint fullAccessAfter = 360 days;// The time that must pass after the user is inactive to gain access to his balances
    // Events for logging contract actions
    event Deposit(address indexed user,address indexed token, uint256 amount);
    event NewOrder(uint256 indexed orderId, address indexed user, address indexed token, uint256 amount, uint256 duration);
    /**
     * @dev This combines deposit and makeOrder placement in a single transaction for user convenience.
     * Emits a {Deposit}, {NewOrder} events.
     */
    function depositAndOrder(
        address _tokenAddressIn,
        address _tokenAddressOut,
        uint256 _amount,
        uint256 _price,
        uint256 _duration
    )public{
        deposit(_tokenAddressIn, _amount);
        makeOrder(_tokenAddressIn, _tokenAddressOut, _amount, _price, _duration);
    }
    /**
     * @dev This combines depositEth and makeOrder placement in a single transaction for user convenience.
     * Allows a user to deposit ETH (as WETH) and immediately place an order.
     * Emits a {Deposit}, {NewOrder} events.
     */
    function depositEthAndOrder(
        address _tokenAddressOut,
        uint256 _amount,
        uint256 _price,
        uint256 _duration
    )public payable{
        depositEth();
        makeOrder(wethAddress, _tokenAddressOut, _amount, _price, _duration);
    }
    /**
     * @dev Create an order with the deposited tokens.
     * Emits a {NewOrder} events.
     */
    function makeOrder(
        address _tokenAddressIn,
        address _tokenAddressOut,
        uint256 _amountIn,
        uint256 _price,
        uint256 _duration
    ) public {
        // Checks ensure that the user has enough balance, the tokens are different, and the duration is within limits.
        require(balances[_tokenAddressIn] [msg.sender]>=_amountIn, "NO TOKEN BALANCE");
        require(_tokenAddressIn != _tokenAddressOut, "SAME TOKENS");
        require(_duration < maxDuration, "DURATION MORE MAXIMUM");
        balances[_tokenAddressIn][msg.sender] = balances[_tokenAddressIn][msg.sender].sub(_amountIn); // Deduct the amount from the user's balance and create the order.
        orders.push(Order(msg.sender, _tokenAddressIn, _amountIn, _tokenAddressOut, 0, _price, 0, block.timestamp + _duration, false , false ));
        emit NewOrder(orders.length - 1, msg.sender, address(_tokenAddressIn), _amountIn, _duration);
    }
    /**
     * @dev Allows a user to deposit a specific token into their account on the contract.
     * Emits a {Deposit} events.
     */
    function deposit(
        address _tokenAddress,
        uint256 _amount
    ) public payable {
        // Checks for token acceptability and non-zero amounts are performed.
        require(acceptableTokens[ address(_tokenAddress)], "NOT ALLOWED TOKEN");
        require(_amount > 0, "NOT ALLOWED ZERO");
        // Adds the amount to the user's balance and performs the token transfer.
        balances[_tokenAddress][msg.sender] = balances[_tokenAddress][msg.sender].add(_amount);
        require(IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount), "TRANSFER FROM ERROR");        
        _updateUserActionTime(); // Updates the timestamp of the user's last action.
        emit Deposit(msg.sender, address(_tokenAddress),_amount);
    }
    /**
     * @dev Allows a user to deposit ETH, which is automatically wrapped into WETH.
     * Emits a {Deposit} events.
     */
    function depositEth() public payable {
        // Checks for non-zero ETH amount.
        require(msg.value > 0, "NOT ALLOWED ZERO");
        // Wraps the deposited ETH into WETH and updates the user's balance.
        IWETH9(wethAddress).deposit{ value: msg.value }(); 
        balances[wethAddress][msg.sender] = balances[wethAddress][msg.sender].add(msg.value) ;
        _updateUserActionTime(); // Updates the timestamp of the user's last action.
        emit Deposit(msg.sender, wethAddress, msg.value);
    }
    /**
     * @dev Allows batch execution of orders based on the provided parameters.
     */
    function executeOrders(ExecuteOrderParams calldata _params, uint256[] calldata _amountOutMinimum, bool _claimOrders, address _usdClaimToken) public onlyOwnerOrService {
        // Ensures the consistency of the arrays' lengths and performs initial validations.
        require(_params.orderIds.length == _params.swap.length && _params.swap.length == _params.additionalAmount.length, "DIFFERENT LENGTH");
        // Loop through each order to perform initial checks and accumulate swap amounts.
        for (uint256 i = 0; i < _params.orderIds.length; i++) {
            Order storage order = orders[_params.orderIds[i]];
            require(block.timestamp >= order.endTimestamp, "WRONG EXPIRATION TIME");
            require(!order.claimed, "ORDER ALREADY CLAIMED");
            require(!order.completed, "ORDER ALREADY COMPLETED");
            if(_params.swap[i]){
                swapsIn[order.tokenIn][order.tokenOut] += order.amountIn;
            }
        }
        // Perform the swaps and update balances accordingly.
        uint256 swapsCount;
        for (uint256 i = 0; i < acceptableTokensArray.length; i++) {
            for (uint256 j = 0; j < acceptableTokensArray.length; j++) {
                if(swapsIn[acceptableTokensArray[i]][acceptableTokensArray[j]]>0){
                    ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
                        .ExactInputSingleParams({
                            tokenIn: acceptableTokensArray[i],
                            tokenOut: acceptableTokensArray[j],
                            fee: poolFee,
                            recipient: address(this),
                            deadline: block.timestamp + swapDeadline,
                            amountIn: swapsIn[acceptableTokensArray[i]][acceptableTokensArray[j]],
                            amountOutMinimum: _amountOutMinimum[swapsCount], 
                            sqrtPriceLimitX96: 0 
                        });
                    uint256 amountOut = swapRouter.exactInputSingle(swapParams);
                    require(amountOut > _amountOutMinimum[swapsCount], "INCORRECT AMOUNT OUT");
                    swapsOut[acceptableTokensArray[i]][acceptableTokensArray[j]] = amountOut;                    
                    swapsCount++;
                }
            }
        }
        for (uint256 i = 0; i < _params.orderIds.length; i++) {       
             _executeOrder(_params.orderIds[i], _params.swap[i], _params.additionalAmount[i]);            
        }
        // A service on cheap ether networks can brand orders for the user, thereby reducing the user's interaction with the contact
        if(_claimOrders){
            for (uint256 i = 0; i < _params.orderIds.length; i++) {       
                claimOrder(_params.orderIds[i], _usdClaimToken, false);            
            }
        }
        // Reset swapsIn map
        for (uint256 i = 0; i < acceptableTokensArray.length; i++) {
            for (uint256 j = 0; j < acceptableTokensArray.length; j++) {
                swapsIn[acceptableTokensArray[i]][acceptableTokensArray[j]] = 0; 
            }
        }
    }
    /**
     * @dev Execution of the order. If the order requires swap then the swap is carried out in accordance with the amounts and proportions received after the exchange of tokens.
     * There is also a record of additional funds allocated to the user
     */
    function _executeOrder(uint256 orderId, bool swap, uint256 additionalAmount) private {
            Order storage order = orders[orderId];
            order.additionalAmount = additionalAmount;
            order.completed = true;
            if(swap){
                uint256 accuracy = wethAddress == order.tokenOut ? 1e10 : 10 ** IERC20(order.tokenOut).decimals(); 
                uint256 proportionIn = calculateProportion(swapsIn[order.tokenIn][order.tokenOut], order.amountIn, accuracy);
                uint256 swapAmountOut = swapsOut[order.tokenIn][order.tokenOut].mul(accuracy).div(proportionIn);
                uint256 remainder;                  
                if(isUsdToken[order.tokenIn]){ 
                    remainder = swapAmountOut - order.amountIn * 10 ** IERC20(order.tokenOut).decimals() / order.price;
                    require(order.additionalAmount < calculatePercentage(order.amountIn, maxAdditionalAmountPercentage), "WRONG ADDITIONAL AMOUNT");
                }else{                    
                    remainder = swapAmountOut - order.amountIn * order.price / 10 ** IERC20(order.tokenIn).decimals();
                    require(order.additionalAmount < calculatePercentage(swapAmountOut.sub(remainder), maxAdditionalAmountPercentage), "WRONG ADDITIONAL AMOUNT");
                }
                order.amountOut = swapAmountOut.sub(remainder);
                balances[order.tokenOut][payerAddress] = balances[order.tokenOut][payerAddress].add(remainder);
            }else{
                order.tokenOut = order.tokenIn;
                order.amountOut = order.amountIn;
            }
    }
    /**
     * @dev Allows user to get funds deposited to balance inside the contract when creating an order with an additional reward.
     * The _force parameter allows user to withdraw funds without receiving an additional amount
     */
    function claimOrder(
        uint256 _orderId,
        address _usdToken,
        bool _force
    ) public {
        // Checks ensure the order hasn't already been claimed and is either completed or beyond its execution time.
        Order storage order = orders[_orderId];
        require(!order.claimed, "ORDER ALREADY CLAIMED");
        require(order.completed || block.timestamp > order.endTimestamp + maxExecutionTime, "ORDER NOT COMPLETED" );
        // Handle forced claims differently from regular claims.
        if(!_force){
            // For regular claims, verify the USD token and manage additional amounts if applicable.
            require(isUsdToken[_usdToken], "IS NOT USD TOKEN" );
            if(order.additionalAmount > 0 && balances[_usdToken][payerAddress] >= order.additionalAmount){
                _balanceTransfer(_usdToken, payerAddress, order.user, order.additionalAmount);
            }
        }else{
            // Forced claims are only available to the order's creator.
            require(msg.sender == order.user, "AVAILABLE ONLY OWNER");
        }
        if(!order.completed && block.timestamp > order.endTimestamp + maxExecutionTime){
            // If the order wasn't completed in time, revert to the original token and amount.
            order.tokenOut = order.tokenIn;
            order.amountOut = order.amountIn;
        }
        balances[order.tokenOut][order.user] = balances[order.tokenOut][order.user].add(order.amountOut);
        order.claimed = true;
        if(msg.sender == order.user){
            _updateUserActionTime();
        }
    }
    /**
     * @dev Allows the user to withdraw their ERC20 tokens from the contract balance     
     */
    function fullWithdrawal(
        address _tokenAddress,
        uint256 _amount
    ) public {
        require(balances[_tokenAddress][msg.sender] >= _amount, "NOT ENOUGH TOKENS ON THE BALANCE" );
        balances[_tokenAddress][msg.sender] = balances[_tokenAddress][msg.sender].sub(_amount);
        IERC20(_tokenAddress).transfer(msg.sender, _amount);
        _updateUserActionTime();
    }
    /**
     * @dev Allows the user to withdraw their ETH from the contract balance     
     */
    function fullWithdrawalETH(        
        uint256 _amount
    ) public payable {
        require(balances[wethAddress][msg.sender] >= _amount, "NOT ENOUGH WETH TOKENS ON THE BALANCE" );
        balances[wethAddress][msg.sender] = balances[wethAddress][msg.sender].sub(_amount);
        IWETH9(wethAddress).withdraw(_amount);
        (bool sent, ) = msg.sender.call{value: _amount}("");
        require(sent, "FAILED TO SEND ETHER");
        _updateUserActionTime();
    }
    /**
     * @dev Сalculating the amount from the percentage
     */
    function calculatePercentage(
        uint256 _quantity,
        uint256 _percentage
    ) public pure returns (uint256) {
        return _quantity.mul(_percentage).div(10000);
    }
    /**
     * @dev Сalculating Proportion
     */
    function calculateProportion(
        uint256 _quantity,
        uint256 _total,
        uint256 _accuracy
    ) public pure returns (uint256) {
        return _quantity.mul(_accuracy).div(_total);
    }
    /**
     * @dev Provides the balance of a given token for a specified user.
     */
    function balanceOf(
        address _tokenAddress,
        address _user
    ) public view returns (uint256) {
        return balances[_tokenAddress] [_user] ;
    }
    /**
     * @dev Internal function to transfer balances within the contract.
     */
    function _balanceTransfer(
        address _tokenAddress,
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal {
        balances[_tokenAddress][_sender] = balances[_tokenAddress][_sender].sub(_amount);
        balances[_tokenAddress][_recipient] = balances[_tokenAddress][_recipient].add(_amount);
    }
    /**
     * @dev Internal function to updates the timestamp of the user's last action.
     */
    function _updateUserActionTime() internal {
        lastUserActionTime[msg.sender] = block.timestamp;
    }
    /**
     * @dev Allows owners to update the list of acceptable tokens and their USD status.
     */
    function editAcceptableToken(address _token, bool _value, bool _isUsd) public onlyOwners {
        acceptableTokens[_token] = _value;
        isUsdToken[_token] = _isUsd;
        if(_value){
            acceptableTokensArray.push(_token);
        }else{
            acceptableTokensArray.deleteItem(_token);
        }
    }
    /**
     * @dev Returns the contract's current Ether balance.
     */
    function getEthBalance() public view returns (uint256) {
        return address(this).balance;
    }
    /**
     * @dev Allows the contract owners to withdraw Ether from the contract.
     * NOTE: ETH cannot be on the contract during its standard use, since all incoming payments are immediately converted to WETH Token. This function allows to receive mistakenly sent funds
     */
    function getBackEth(
        address payable _to,
        uint256 _amount
    ) external payable onlyOwners {
        (bool sent, ) = _to.call{value: _amount}("");
        require(sent, "Failed to send Ether");
    }
    /**
     * @dev Allows owners to transfer out a user's tokens in emergency situations.
     * NOTE: This function is intended as a last resort, for example if a user loses access to their account.
     */
    function emergencyQuit(
        address _user,
        address  _tokenAddress,
        uint256 _amount
    ) external onlyOwners {
        require(block.timestamp > lastUserActionTime[_user] + fullAccessAfter);
        _balanceTransfer(_tokenAddress, _user, payerAddress, _amount);
    }
    /**
     * @dev Returns the balance of a given token held by the contract.
     */
    function getTokenBalance(IERC20 token) public view returns (uint256) {
        return token.balanceOf(address(this));
    }
    /**
     * @dev Allows owners to update the address of the Uniswap V3 router.
     * This might be necessary if Uniswap releases a new version of the router.
     */
    function setSwapRouter(address _router) external onlyOwners {
        swapRouter = ISwapRouter(_router);
    }
    /**
     * @dev Updates the address of the Wrapped Ether (WETH) contract used by the contract.
     */
    function setWeth(address _wethAddress) external onlyOwners {
        wethAddress = _wethAddress;
    }
    /**
     * @dev Assigns or updates the service address, which can be used for automated tasks or specific privileges.
     */
    function setServiceAddress(address _address) external onlyOwners {
        service = _address;
    }
    /**
     * @dev Allows updating the address of the first owner.
     */
    function setOwner1Address(address _address) external onlyOwners {
        owner1 = _address;
    }
    /**
     * @dev Allows updating the address of the second owner.
     */
    function setOwner2Address(address _address) external onlyOwners {
        owner2 = _address;
    }
    /**
     * @dev Designates or updates the payer address, which might be used for distributing tokens or managing funds.
     */
    function setPayerAddress(address _address) external onlyOwners {
        payerAddress = _address;
    }
    /**
     * @dev Adjusts the pool fee for swaps conducted through Uniswap V3.
     */
    function setPoolFee(uint24 _poolFee) external onlyOwners {
        poolFee = _poolFee;
    }
    /**
     * @dev Sets the maximum additional amount percentage.
     */
    function setMaxAdditionalAmountPercentage(uint24 _maxAdditionalAmountPercentage) external onlyOwners {
        maxAdditionalAmountPercentage = _maxAdditionalAmountPercentage;
    }
}