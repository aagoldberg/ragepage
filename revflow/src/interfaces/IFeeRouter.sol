// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFeeRouter {
    event RecipientChangeProposed(address indexed newRecipient, uint256 executeTime);
    event RecipientChanged(address indexed oldRecipient, address indexed newRecipient);
    event MakeWholePaymentMade(uint256 amount);
    
    function setRecipient(address newRecipient) external;
    function executeRecipientChange() external;
    function recipient() external view returns (address);
    function canChangeRecipient() external view returns (bool);
    function makeWholePayment(uint256 amount) external;
    function isCapReached() external view returns (bool);
    function isTermEnded() external view returns (bool);
    function isMakeWholePaid() external view returns (bool);
}