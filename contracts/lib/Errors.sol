// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

library Errors {
    error AvailableOnlyOwner();
    error DifferentLength();
    error DuplicateToken();
    error DurationMoreMaximum();
    error FailedToSendEther();
    error IncorrectAmountOut();
    error NoTokenBalance();
    error NotAllowedToken();
    error NotAllowedZero();
    error NotAllowedAddress();
    error OrderAlreadyClaimed();
    error OrderNotCompleted();
    error OrderAlreadyCompleted();
    error SameTokens();
    error WrongAdditionalAmount();
    error WrongAmount();
    error WrongExpirationTime();
    error WrongTimestamp();
    error IsNotUsdToken();
}