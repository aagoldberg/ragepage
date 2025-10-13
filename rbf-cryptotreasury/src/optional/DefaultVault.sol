// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IDefaultVault.sol";
import "../interfaces/IRevenueSplitter.sol";
import "../interfaces/ILenderVault.sol";

contract DefaultVault is IDefaultVault, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    address public immutable splitter;
    address public immutable lenderVault;
    uint256 public immutable curePeriodDuration;
    uint256 public immutable noPaymentThreshold;
    
    bool public defaultDeclared;
    uint256 public curePeriodStart;
    uint256 public lastPaymentTime;
    
    mapping(address => uint256) public collateralBalance;
    
    event PaymentReceived(uint256 timestamp);
    
    constructor(
        address _splitter,
        address _lenderVault,
        uint256 _curePeriodDuration,
        uint256 _noPaymentThreshold
    ) Ownable(msg.sender) {
        require(_splitter != address(0), "Invalid splitter");
        require(_lenderVault != address(0), "Invalid lender vault");
        require(_curePeriodDuration > 0, "Invalid cure period");
        require(_noPaymentThreshold > 0, "Invalid threshold");
        
        splitter = _splitter;
        lenderVault = _lenderVault;
        curePeriodDuration = _curePeriodDuration;
        noPaymentThreshold = _noPaymentThreshold;
        lastPaymentTime = block.timestamp;
    }
    
    function depositCollateral(address token, uint256 amount) external payable nonReentrant {
        require(amount > 0, "Zero amount");
        require(!defaultDeclared, "Already defaulted");
        
        if (token == address(0)) {
            // ETH
            require(msg.value == amount, "Incorrect ETH amount");
            collateralBalance[address(0)] += amount;
        } else {
            // ERC20
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            collateralBalance[token] += amount;
        }
        
        emit CollateralDeposited(token, amount);
    }
    
    function declareDefault() external onlyOwner nonReentrant {
        require(!defaultDeclared, "Already defaulted");
        require(canDeclareDefault(), "Cannot declare default");
        
        defaultDeclared = true;
        
        // Calculate remaining cap
        IRevenueSplitter splitterContract = IRevenueSplitter(splitter);
        uint256 remainingCap = splitterContract.getRemainingCap();
        
        // Transfer collateral to lender vault up to remaining cap
        _transferCollateralToLenders(remainingCap);
        
        emit DefaultDeclared(remainingCap, block.timestamp);
    }
    
    function startCurePeriod() external onlyOwner {
        require(!defaultDeclared, "Already defaulted");
        require(curePeriodStart == 0, "Cure period already started");
        
        // Check if no payments for threshold period
        require(
            block.timestamp >= lastPaymentTime + noPaymentThreshold,
            "Payment threshold not met"
        );
        
        curePeriodStart = block.timestamp;
        emit CurePeriodStarted(block.timestamp);
    }
    
    function releaseCollateral(address recipient) external onlyOwner nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        require(!defaultDeclared, "Already defaulted");
        
        // Can only release if cap reached or term ended
        IRevenueSplitter splitterContract = IRevenueSplitter(splitter);
        require(
            splitterContract.isCapReached(),
            "Cap not reached"
        );
        
        // Transfer all collateral to recipient (typically treasury)
        _releaseAllCollateral(recipient);
    }
    
    function getCollateralBalance(address token) external view returns (uint256) {
        return collateralBalance[token];
    }
    
    function isDefaulted() external view returns (bool) {
        return defaultDeclared;
    }
    
    function canDeclareDefault() public view returns (bool) {
        if (defaultDeclared) return false;
        
        // Can declare default if:
        // 1. Cure period has expired without cure
        // 2. Recipient was changed before cap/term
        
        if (curePeriodStart > 0) {
            return block.timestamp >= curePeriodStart + curePeriodDuration;
        }
        
        return false;
    }
    
    function getRemainingCurePeriod() external view returns (uint256) {
        if (curePeriodStart == 0) return 0;
        
        uint256 elapsed = block.timestamp - curePeriodStart;
        if (elapsed >= curePeriodDuration) return 0;
        
        return curePeriodDuration - elapsed;
    }
    
    function recordPayment() external {
        require(msg.sender == splitter, "Only splitter");
        lastPaymentTime = block.timestamp;
        
        // Reset cure period if payment received during cure
        if (curePeriodStart > 0 && !defaultDeclared) {
            curePeriodStart = 0;
        }
        
        emit PaymentReceived(block.timestamp);
    }
    
    function _transferCollateralToLenders(uint256 maxAmount) internal {
        uint256 transferred = 0;
        
        // First try ETH
        uint256 ethBalance = collateralBalance[address(0)];
        if (ethBalance > 0 && transferred < maxAmount) {
            uint256 toTransfer = ethBalance;
            if (transferred + toTransfer > maxAmount) {
                toTransfer = maxAmount - transferred;
            }
            
            collateralBalance[address(0)] -= toTransfer;
            transferred += toTransfer;
            
            (bool success, ) = lenderVault.call{value: toTransfer}("");
            require(success, "ETH transfer failed");
            ILenderVault(lenderVault).depositFor(address(0), toTransfer);
        }
        
        // Then try stablecoins (simplified - would iterate through allowed tokens)
        // This is a simplified version - production would handle multiple tokens
    }
    
    function _releaseAllCollateral(address recipient) internal {
        // Release ETH
        uint256 ethBalance = collateralBalance[address(0)];
        if (ethBalance > 0) {
            collateralBalance[address(0)] = 0;
            (bool success, ) = recipient.call{value: ethBalance}("");
            require(success, "ETH transfer failed");
            emit CollateralReleased(address(0), ethBalance, recipient);
        }
        
        // Release tokens (simplified - would iterate through all deposited tokens)
        // This is a simplified version - production would handle multiple tokens
    }
    
    receive() external payable {
        // Accept ETH collateral
    }
}