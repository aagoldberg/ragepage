// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IFeeRouter.sol";
import "../interfaces/IRevenueSplitter.sol";

contract FeeRouter is IFeeRouter, Ownable {
    using SafeERC20 for IERC20;
    
    address public recipient;
    address public immutable splitter;
    uint256 public immutable termEndTime;
    uint256 public immutable makeWholeAmount;
    
    uint256 public makeWholePaid;
    address public pendingRecipient;
    uint256 public pendingRecipientTime;
    
    uint256 public constant TIMELOCK_DELAY = 2 days;
    
    constructor(
        address _initialRecipient,
        address _splitter,
        uint256 _termDuration,
        uint256 _makeWholeAmount
    ) Ownable(msg.sender) {
        require(_initialRecipient != address(0), "Invalid recipient");
        require(_splitter != address(0), "Invalid splitter");
        
        recipient = _initialRecipient;
        splitter = _splitter;
        termEndTime = block.timestamp + _termDuration;
        makeWholeAmount = _makeWholeAmount;
    }
    
    receive() external payable {
        // Forward to current recipient
        (bool success, ) = recipient.call{value: msg.value}("");
        require(success, "ETH forward failed");
    }
    
    function setRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid recipient");
        require(canChangeRecipient(), "Cannot change recipient yet");
        
        pendingRecipient = newRecipient;
        pendingRecipientTime = block.timestamp + TIMELOCK_DELAY;
        
        emit RecipientChangeProposed(newRecipient, pendingRecipientTime);
    }
    
    function executeRecipientChange() external {
        require(pendingRecipient != address(0), "No pending change");
        require(block.timestamp >= pendingRecipientTime, "Timelock not passed");
        require(canChangeRecipient(), "Cannot change recipient");
        
        address oldRecipient = recipient;
        recipient = pendingRecipient;
        pendingRecipient = address(0);
        pendingRecipientTime = 0;
        
        emit RecipientChanged(oldRecipient, recipient);
    }
    
    function canChangeRecipient() public view returns (bool) {
        // Can change if:
        // 1. Cap is reached, OR
        // 2. Term has ended AND make-whole is paid
        return isCapReached() || (isTermEnded() && isMakeWholePaid());
    }
    
    function makeWholePayment(uint256 amount) external onlyOwner {
        require(amount > 0, "Zero amount");
        require(makeWholePaid + amount <= makeWholeAmount, "Exceeds make-whole amount");
        
        makeWholePaid += amount;
        
        // Transfer make-whole payment to lender vault
        IRevenueSplitter splitterContract = IRevenueSplitter(splitter);
        // This is simplified - in production would get lender vault from splitter
        
        emit MakeWholePaymentMade(amount);
    }
    
    function isCapReached() public view returns (bool) {
        return IRevenueSplitter(splitter).isCapReached();
    }
    
    function isTermEnded() public view returns (bool) {
        return block.timestamp >= termEndTime;
    }
    
    function isMakeWholePaid() public view returns (bool) {
        return makeWholePaid >= makeWholeAmount;
    }
    
    // Forward any token accidentally sent here
    function forwardToken(address token) external {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(recipient, balance);
        }
    }
}