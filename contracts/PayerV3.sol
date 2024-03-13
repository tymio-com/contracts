// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;
pragma abicoder v2;
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol"; // Interface for Uniswap v3's swap router, for executing token swaps.
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./lib/ArrayUtils.sol";
import {Errors} from "./lib/Errors.sol";

interface IWETH9 is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external payable;
}

contract PayerV3 {
    using SafeERC20 for IERC20;
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
        if (msg.sender != owner1 && msg.sender != owner2) {
            revert Errors.NotAllowedAddress();
        }
        _;
    }
    modifier onlyOwnerOrService() {
        // Ensures only the owners or the service account can call the modified function.
        if (
            msg.sender != owner1 &&
            msg.sender != owner2 &&
            msg.sender != service
        ) {
            revert Errors.NotAllowedAddress();
        }
        _;
    }
    ISwapRouter public constant swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Uniswap swap router
    uint24 public poolFee = 3000; // Fee for liquidity pool usage, in basis points.
    uint24 public constant maxAdditionalAmountPercentage = 750; // Maximum allowed percentage for additionalAmount, in basis points.
    uint256 public acceptableTokensArrayLength; // Array length of acceptable token addresses.
    uint256 constant swapDeadline = 10 minutes; // Deadline for completing swaps.
    mapping(address => mapping(address => uint256)) public balances; // Tracks user balances of various tokens.
    mapping(address => mapping(address => uint256)) public swapsIn; // Tracks incoming swaps.
    mapping(address => mapping(address => uint256)) public swapsOut; // Tracks outgoing swaps.
    mapping(address => uint256) public lastUserActionTime; // Tracks the last action time of users.
    Order[] public orders; // Array of all orders.
    mapping(address => bool) public acceptableTokens; // Tracks tokens that are acceptable for trading.
    mapping(address => bool) public isUsdToken; // Tracks if a token is considered a USD token.
    mapping(address => uint256) public minimalTokenAmounts; // Tracks minimal token amounts.
    address[] public acceptableTokensArray; // Array of acceptable token addresses.
    address public constant wethAddress =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Address of Wrapped ETH (WETH) contract.
    address public payerAddress; // Address used for making payments.
    uint public constant maxDuration = 90 days; // Maximum duration for orders.
    uint public constant maxExecutionTime = 1 hours; // Maximum time for executing orders
    uint public constant fullAccessAfter = 365 days; // The time that must pass after the user is inactive to gain access to his balances
    // Events for logging contract actions
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event NewOrder(
        uint256 indexed orderId,
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 duration
    );
    event ClaimOrder(uint256 indexed orderId);
    event FullWithdrawal(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    /**
     * @dev This combines deposit and makeOrder placement in a single transaction for user convenience.
     * Emits a {Deposit}, {NewOrder} events.
     */
    function depositAndOrder(
        address _tokenAddressIn,
        address _tokenAddressOut,
        uint256 _amountDeposit,
        uint256 _amountOrder,
        uint256 _price,
        uint256 _duration
    ) public {
        deposit(_tokenAddressIn, _amountDeposit);
        makeOrder(
            _tokenAddressIn,
            _tokenAddressOut,
            _amountOrder,
            _price,
            _duration
        );
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
    ) public payable {
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
        if (!(balances[_tokenAddressIn][msg.sender] >= _amountIn)) {
            revert Errors.NoTokenBalance();
        }
        if (!(_tokenAddressIn != _tokenAddressOut)) {
            revert Errors.SameTokens();
        }
        if (!(_duration < maxDuration)) {
            revert Errors.DurationMoreMaximum();
        }
        if (!(_amountIn >= minimalTokenAmounts[_tokenAddressIn])) {
            revert Errors.WrongAmount();
        }
        balances[_tokenAddressIn][msg.sender] =
            balances[_tokenAddressIn][msg.sender] -
            _amountIn; // Deduct the amount from the user's balance and create the order.
        orders.push(
            Order(
                msg.sender,
                _tokenAddressIn,
                _amountIn,
                _tokenAddressOut,
                0,
                _price,
                0,
                block.timestamp + _duration,
                false,
                false
            )
        );
        _updateUserActionTime(); // Updates the timestamp of the user's last action.
        emit NewOrder(
            orders.length - 1,
            msg.sender,
            address(_tokenAddressIn),
            _amountIn,
            _duration
        );
    }

    /**
     * @dev Allows a user to deposit a specific token into their account on the contract.
     * Emits a {Deposit} events.
     */
    function deposit(address _tokenAddress, uint256 _amount) public payable {
        // Checks for token acceptability and non-zero amounts are performed.
        if (!acceptableTokens[_tokenAddress]) {
            revert Errors.NotAllowedToken();
        }
        if (_amount == 0) {
            revert Errors.NotAllowedZero();
        }
        IERC20(_tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        // Adds the amount to the user's balance and performs the token transfer.
        balances[_tokenAddress][msg.sender] =
            balances[_tokenAddress][msg.sender] +
            _amount;
        _updateUserActionTime(); // Updates the timestamp of the user's last action.
        emit Deposit(msg.sender, _tokenAddress, _amount);
    }

    /**
     * @dev Allows a user to deposit ETH, which is automatically wrapped into WETH.
     * Emits a {Deposit} events.
     */
    function depositEth() public payable {
        // Checks for non-zero ETH amount.
        if (!(msg.value > 0)) {
            revert Errors.NotAllowedZero();
        }
        // Wraps the deposited ETH into WETH and updates the user's balance.
        IWETH9(wethAddress).deposit{value: msg.value}();
        balances[wethAddress][msg.sender] =
            balances[wethAddress][msg.sender] +
            msg.value;
        _updateUserActionTime(); // Updates the timestamp of the user's last action.
        emit Deposit(msg.sender, wethAddress, msg.value);
    }

    /**
     * @dev Allows batch execution of orders based on the provided parameters.
     */
    function executeOrders(
        ExecuteOrderParams calldata _params,
        uint256[] calldata _amountOutMinimum,
        bool _claimOrders,
        address _usdClaimToken
    ) public onlyOwnerOrService {
        uint256 orderIdsLength = _params.orderIds.length;
        // Ensures the consistency of the arrays' lengths and performs initial validations.
        if (
            !(orderIdsLength == _params.swap.length &&
                _params.swap.length == _params.additionalAmount.length)
        ) {
            revert Errors.DifferentLength();
        }
        // Loop through each order to perform initial checks and accumulate swap amounts.
        for (uint256 i; i < orderIdsLength; ) {
            Order storage order = orders[_params.orderIds[i]];
            if (!(block.timestamp >= order.endTimestamp)) {
                revert Errors.WrongExpirationTime();
            }
            if (order.claimed) {
                revert Errors.OrderAlreadyClaimed();
            }
            if (order.completed) {
                revert Errors.OrderAlreadyCompleted();
            }
            if (_params.swap[i]) {
                swapsIn[order.tokenIn][order.tokenOut] += order.amountIn;
            }
            unchecked {
                ++i;
            }
        }
        // Perform the swaps and update balances accordingly.
        uint256 swapsCount;
        for (uint256 i; i < acceptableTokensArrayLength; ) {
            for (uint256 j; j < acceptableTokensArrayLength; ) {
                if (
                    swapsIn[acceptableTokensArray[i]][
                        acceptableTokensArray[j]
                    ] > 0
                ) {
                    IERC20(acceptableTokensArray[i]).forceApprove(
                        address(swapRouter),
                        swapsIn[acceptableTokensArray[i]][
                            acceptableTokensArray[j]
                        ]
                    );
                    ISwapRouter.ExactInputSingleParams
                        memory swapParams = ISwapRouter.ExactInputSingleParams({
                            tokenIn: acceptableTokensArray[i],
                            tokenOut: acceptableTokensArray[j],
                            fee: poolFee,
                            recipient: address(this),
                            deadline: block.timestamp + swapDeadline,
                            amountIn: swapsIn[acceptableTokensArray[i]][
                                acceptableTokensArray[j]
                            ],
                            amountOutMinimum: _amountOutMinimum[swapsCount],
                            sqrtPriceLimitX96: 0
                        });
                    uint256 amountOut = swapRouter.exactInputSingle(swapParams);
                    if (!(amountOut > _amountOutMinimum[swapsCount])) {
                        revert Errors.IncorrectAmountOut();
                    }
                    swapsOut[acceptableTokensArray[i]][
                        acceptableTokensArray[j]
                    ] = amountOut;
                    swapsCount++;
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
        for (uint256 i; i < orderIdsLength; ) {
            _executeOrder(
                _params.orderIds[i],
                _params.swap[i],
                _params.additionalAmount[i]
            );
            unchecked {
                ++i;
            }
        }
        // A service on cheap ether networks can brand orders for the user, thereby reducing the user's interaction with the contact
        if (_claimOrders) {
            for (uint256 i; i < orderIdsLength; ) {
                claimOrder(_params.orderIds[i], _usdClaimToken, false);
                unchecked {
                    ++i;
                }
            }
        }
        // Reset swapsIn map
        for (uint256 i; i < acceptableTokensArrayLength; ) {
            for (uint256 j; j < acceptableTokensArrayLength; ) {
                swapsIn[acceptableTokensArray[i]][acceptableTokensArray[j]] = 0;
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Execution of the order. If the order requires swap then the swap is carried out in accordance with the amounts and proportions received after the exchange of tokens.
     * There is also a record of additional funds allocated to the user
     */
    function _executeOrder(
        uint256 orderId,
        bool swap,
        uint256 additionalAmount
    ) private {
        Order storage order = orders[orderId];
        order.additionalAmount = additionalAmount;
        order.completed = true;
        if (swap) {
            uint256 accuracy = wethAddress == order.tokenOut
                ? 1e10
                : 10 ** IERC20Metadata(order.tokenOut).decimals();
            uint256 proportionIn = calculateProportion(
                swapsIn[order.tokenIn][order.tokenOut],
                order.amountIn,
                accuracy
            );
            uint256 swapAmountOut = (swapsOut[order.tokenIn][order.tokenOut] *
                accuracy) / proportionIn;
            uint256 remainder;
            if (isUsdToken[order.tokenIn]) {
                remainder =
                    swapAmountOut -
                    (order.amountIn *
                        10 ** IERC20Metadata(order.tokenOut).decimals()) /
                    order.price;
                if (
                    !(order.additionalAmount <
                        calculatePercentage(
                            order.amountIn,
                            maxAdditionalAmountPercentage
                        ))
                ) {
                    revert Errors.WrongAdditionalAmount();
                }
            } else {
                remainder =
                    swapAmountOut -
                    (order.amountIn * order.price) /
                    10 ** IERC20Metadata(order.tokenIn).decimals();
                if (
                    !(order.additionalAmount <
                        calculatePercentage(
                            swapAmountOut - remainder,
                            maxAdditionalAmountPercentage
                        ))
                ) {
                    revert Errors.WrongAdditionalAmount();
                }
            }
            order.amountOut = swapAmountOut - remainder;
            balances[order.tokenOut][payerAddress] =
                balances[order.tokenOut][payerAddress] +
                remainder;
        } else {
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
        if (order.claimed) {
            revert Errors.OrderAlreadyClaimed();
        }
        if (
            !(order.completed ||
                block.timestamp > order.endTimestamp + maxExecutionTime)
        ) {
            revert Errors.OrderNotCompleted();
        }
        // Handle forced claims differently from regular claims.
        if (!_force) {
            // For regular claims, verify the USD token and manage additional amounts if applicable.
            if (!isUsdToken[_usdToken]) {
                revert Errors.IsNotUsdToken();
            }
            if (
                order.additionalAmount > 0 &&
                balances[_usdToken][payerAddress] >= order.additionalAmount
            ) {
                _balanceTransfer(
                    _usdToken,
                    payerAddress,
                    order.user,
                    order.additionalAmount
                );
            }
        } else {
            // Forced claims are only available to the order's creator.
            if (msg.sender != order.user) {
                revert Errors.AvailableOnlyOwner();
            }
        }
        if (
            !order.completed &&
            block.timestamp > order.endTimestamp + maxExecutionTime
        ) {
            // If the order wasn't completed in time, revert to the original token and amount.
            order.tokenOut = order.tokenIn;
            order.amountOut = order.amountIn;
        }
        balances[order.tokenOut][order.user] =
            balances[order.tokenOut][order.user] +
            order.amountOut;
        order.claimed = true;
        if (msg.sender == order.user) {
            _updateUserActionTime();
            emit ClaimOrder(_orderId);
        }
    }

    /**
     * @dev Allows the user to withdraw their ERC20 tokens from the contract balance
     */
    function fullWithdrawal(address _tokenAddress, uint256 _amount) public {
        if (balances[_tokenAddress][msg.sender] < _amount) {
            revert Errors.NoTokenBalance();
        }
        balances[_tokenAddress][msg.sender] =
            balances[_tokenAddress][msg.sender] -
            _amount;
        IERC20(_tokenAddress).safeTransfer(msg.sender, _amount);
        _updateUserActionTime();
        emit FullWithdrawal(msg.sender, _tokenAddress, _amount);
    }

    /**
     * @dev Allows the user to withdraw their ETH from the contract balance
     */
    function fullWithdrawalETH(uint256 _amount) public payable {
        if (balances[wethAddress][msg.sender] < _amount) {
            revert Errors.NoTokenBalance();
        }
        balances[wethAddress][msg.sender] =
            balances[wethAddress][msg.sender] -
            _amount;
        IWETH9(wethAddress).withdraw(_amount);
        (bool sent, ) = msg.sender.call{value: _amount}("");
        if (!sent) {
            revert Errors.FailedToSendEther();
        }
        _updateUserActionTime();
        emit FullWithdrawal(msg.sender, wethAddress, _amount);
    }

    /**
     * @dev Сalculating the amount from the percentage
     */
    function calculatePercentage(
        uint256 _quantity,
        uint256 _percentage
    ) public pure returns (uint256) {
        return (_quantity * _percentage) / 10000;
    }

    /**
     * @dev Сalculating Proportion
     */
    function calculateProportion(
        uint256 _quantity,
        uint256 _total,
        uint256 _accuracy
    ) public pure returns (uint256) {
        return (_quantity * _accuracy) / _total;
    }

    /**
     * @dev Provides the balance of a given token for a specified user.
     */
    function balanceOf(
        address _tokenAddress,
        address _user
    ) public view returns (uint256) {
        return balances[_tokenAddress][_user];
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
        balances[_tokenAddress][_sender] =
            balances[_tokenAddress][_sender] -
            _amount;
        balances[_tokenAddress][_recipient] =
            balances[_tokenAddress][_recipient] +
            _amount;
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
    function editAcceptableToken(
        address _token,
        bool _value,
        bool _isUsd,
        uint256 _minimalAmount
    ) public onlyOwners {
        isUsdToken[_token] = _isUsd;
        if (_value) {
            if (acceptableTokens[_token]) {
                revert Errors.DuplicateToken();
            }
            if (_minimalAmount == 0) {
                revert Errors.NotAllowedZero();
            }
            acceptableTokensArray.push(_token);
            minimalTokenAmounts[_token] = _minimalAmount;
        } else {
            acceptableTokensArray.deleteItem(_token);
        }
        acceptableTokens[_token] = _value;
        acceptableTokensArrayLength = acceptableTokensArray.length;
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
        if (!sent) {
            revert Errors.FailedToSendEther();
        }
    }

    /**
     * @dev Allows owners to transfer out a user's tokens in emergency situations.
     * NOTE: This function is intended as a last resort, for example if a user loses access to their account.
     */
    function emergencyQuit(
        address _user,
        address _tokenAddress,
        uint256 _amount
    ) external onlyOwners {
        if (!(block.timestamp > lastUserActionTime[_user] + fullAccessAfter)) {
            revert Errors.WrongTimestamp();
        }
        _balanceTransfer(_tokenAddress, _user, payerAddress, _amount);
    }

    /**
     * @dev Returns the balance of a given token held by the contract.
     */
    function getTokenBalance(IERC20 token) public view returns (uint256) {
        return token.balanceOf(address(this));
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
    function setPayerAddress() external onlyOwners {
        payerAddress = msg.sender;
    }

    /**
     * @dev Adjusts the pool fee for swaps conducted through Uniswap V3.
     */
    function setPoolFee(uint24 _poolFee) external onlyOwners {
        poolFee = _poolFee;
    }
}
