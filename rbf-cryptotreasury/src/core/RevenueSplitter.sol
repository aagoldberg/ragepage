// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IRevenueSplitter.sol";
import "../interfaces/ILenderVault.sol";

contract RevenueSplitter is IRevenueSplitter, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    address public immutable treasury;
    address public immutable lenderVault;
    uint256 public immutable shareBps;
    uint256 public immutable repaymentCap;
    uint256 public immutable dealStartTime;
    uint256 public immutable dealEndTime;
    
    uint256 public totalPaid;
    uint256 public dailyCap;
    uint256 public transactionCap;
    
    mapping(uint256 => uint256) public dailyVolume;
    mapping(address => bool) public allowedTokens;
    
    modifier onlyAllowedToken(address token) {
        require(allowedTokens[token] || token == address(0), "Token not allowed");
        _;
    }
    
    constructor(
        address _treasury,
        address _lenderVault,
        uint256 _shareBps,
        uint256 _repaymentCap,
        uint256 _dealDuration,
        uint256 _dailyCap,
        uint256 _transactionCap
    ) Ownable(msg.sender) {
        require(_treasury != address(0), "Invalid treasury");
        require(_lenderVault != address(0), "Invalid lender vault");
        require(_shareBps > 0 && _shareBps <= BPS_DENOMINATOR, "Invalid share");
        require(_repaymentCap > 0, "Invalid cap");
        require(_dealDuration > 0, "Invalid duration");
        
        treasury = _treasury;
        lenderVault = _lenderVault;
        shareBps = _shareBps;
        repaymentCap = _repaymentCap;
        dealStartTime = block.timestamp;
        dealEndTime = block.timestamp + _dealDuration;
        dailyCap = _dailyCap;
        transactionCap = _transactionCap;
    }
    
    function onRevenue(address token, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused
        onlyAllowedToken(token)
    {
        require(amount > 0, "Zero amount");
        require(!isCapReached(), "Cap reached");
        require(block.timestamp < dealEndTime, "Deal ended");
        
        // Safety rails
        _checkSafetyRails(amount);
        
        // Calculate split
        uint256 toLenders = (amount * shareBps) / BPS_DENOMINATOR;
        uint256 remainingCap = getRemainingCap();
        
        // Clamp to not exceed cap
        if (toLenders > remainingCap) {
            toLenders = remainingCap;
        }
        
        uint256 toTreasury = amount - toLenders;
        
        // Update state
        totalPaid += toLenders;
        uint256 today = block.timestamp / 1 days;
        dailyVolume[today] += toLenders;
        
        // Transfer funds
        if (token == address(0)) {
            // ETH transfer
            if (toLenders > 0) {
                (bool success, ) = lenderVault.call{value: toLenders}("");
                require(success, "ETH transfer to lenders failed");
                ILenderVault(lenderVault).depositFor(address(0), toLenders);
            }
            
            if (toTreasury > 0) {
                (bool success, ) = treasury.call{value: toTreasury}("");
                require(success, "ETH transfer to treasury failed");
            }
        } else {
            // Token transfer
            if (toLenders > 0) {
                IERC20(token).safeTransferFrom(msg.sender, lenderVault, toLenders);
                ILenderVault(lenderVault).depositFor(token, toLenders);
            }
            
            if (toTreasury > 0) {
                IERC20(token).safeTransferFrom(msg.sender, treasury, toTreasury);
            }
        }
        
        emit SplitExecuted(token, toLenders, toTreasury, totalPaid);
        
        if (isCapReached()) {
            emit CapReached(totalPaid);
        }
    }
    
    function isCapReached() public view returns (bool) {
        return totalPaid >= repaymentCap;
    }
    
    function isPaused() public view returns (bool) {
        return paused();
    }
    
    function getTotalPaid() external view returns (uint256) {
        return totalPaid;
    }
    
    function getRemainingCap() public view returns (uint256) {
        if (totalPaid >= repaymentCap) return 0;
        return repaymentCap - totalPaid;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function setDailyCap(uint256 newCap) external onlyOwner {
        dailyCap = newCap;
    }
    
    function setTransactionCap(uint256 newCap) external onlyOwner {
        transactionCap = newCap;
    }
    
    function setAllowedToken(address token, bool allowed) external onlyOwner {
        allowedTokens[token] = allowed;
    }
    
    function _checkSafetyRails(uint256 amount) internal view {
        // Transaction cap check
        if (transactionCap > 0 && amount > transactionCap) {
            revert("Exceeds transaction cap");
        }
        
        // Daily cap check
        if (dailyCap > 0) {
            uint256 today = block.timestamp / 1 days;
            if (dailyVolume[today] + amount > dailyCap) {
                revert("Exceeds daily cap");
            }
        }
    }
    
    receive() external payable {
        this.onRevenue(address(0), msg.value);
    }
}