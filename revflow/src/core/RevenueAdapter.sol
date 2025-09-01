// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IRevenueAdapter.sol";
import "../interfaces/IRevenueSplitter.sol";

contract RevenueAdapter is IRevenueAdapter, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    address public splitter;
    address public treasury;
    address public governance;
    uint256 public constant TIMELOCK_DELAY = 2 days;
    
    mapping(address => uint256) public pendingChanges;
    
    modifier onlyGovernance() {
        require(msg.sender == governance || msg.sender == owner(), "Not authorized");
        _;
    }
    
    constructor(address _treasury, address _splitter, address _governance) Ownable(msg.sender) {
        require(_treasury != address(0), "Invalid treasury");
        require(_splitter != address(0), "Invalid splitter");
        
        treasury = _treasury;
        splitter = _splitter;
        governance = _governance;
    }
    
    receive() external payable {
        _forwardETH();
    }
    
    function sweep(address token) external nonReentrant {
        _sweep(token);
    }
    
    function sweepBatch(address[] calldata tokens) external nonReentrant {
        for (uint256 i = 0; i < tokens.length; i++) {
            _sweep(tokens[i]);
        }
    }
    
    function claimAndForward() external nonReentrant {
        // This is a placeholder for protocol-specific claiming logic
        // Each integration would override this based on their needs
        revert("Not implemented - override in specific adapter");
    }
    
    function setSplitter(address newSplitter) external onlyGovernance {
        require(newSplitter != address(0), "Invalid splitter");
        pendingChanges[newSplitter] = block.timestamp + TIMELOCK_DELAY;
    }
    
    function executeSplitterChange(address newSplitter) external {
        require(pendingChanges[newSplitter] != 0, "No pending change");
        require(block.timestamp >= pendingChanges[newSplitter], "Timelock not passed");
        
        splitter = newSplitter;
        delete pendingChanges[newSplitter];
    }
    
    function setTreasury(address newTreasury) external onlyGovernance {
        require(newTreasury != address(0), "Invalid treasury");
        treasury = newTreasury;
    }
    
    function _sweep(address token) internal {
        if (token == address(0)) {
            _forwardETH();
        } else {
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                _forwardToken(token, balance);
            }
        }
    }
    
    function _forwardETH() internal {
        uint256 balance = address(this).balance;
        if (balance == 0) return;
        
        bool toSplitter = _shouldForwardToSplitter();
        address recipient = toSplitter ? splitter : treasury;
        
        (bool success, ) = recipient.call{value: balance}("");
        require(success, "ETH transfer failed");
        
        emit Forwarded(address(0), balance, toSplitter);
    }
    
    function _forwardToken(address token, uint256 amount) internal {
        bool toSplitter = _shouldForwardToSplitter();
        address recipient = toSplitter ? splitter : treasury;
        
        IERC20(token).safeTransfer(recipient, amount);
        
        emit Forwarded(token, amount, toSplitter);
    }
    
    function _shouldForwardToSplitter() internal view returns (bool) {
        if (splitter == address(0)) return false;
        
        IRevenueSplitter splitterContract = IRevenueSplitter(splitter);
        
        // Forward to splitter if not paused and cap not reached
        return !splitterContract.isPaused() && !splitterContract.isCapReached();
    }
}