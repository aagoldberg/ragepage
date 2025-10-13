// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/ILenderVault.sol";

contract LenderVault is ILenderVault, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // Receipt token for this deal
    address public immutable receiptToken;
    address public immutable splitter;
    
    // Token -> total deposited
    mapping(address => uint256) public totalDeposited;
    
    // Lender -> Token -> claimed amount
    mapping(address => mapping(address => uint256)) public claimed;
    
    // Token -> total claimed
    mapping(address => uint256) public totalClaimed;
    
    modifier onlySplitter() {
        require(msg.sender == splitter, "Only splitter");
        _;
    }
    
    constructor(
        address _splitter,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol
    ) Ownable(msg.sender) {
        require(_splitter != address(0), "Invalid splitter");
        
        splitter = _splitter;
        
        // Deploy receipt token
        RBFReceiptToken token = new RBFReceiptToken(_receiptTokenName, _receiptTokenSymbol, address(this));
        receiptToken = address(token);
    }
    
    receive() external payable {
        // Accept ETH from splitter
        require(msg.sender == splitter, "Only splitter can send ETH");
    }
    
    function depositFor(address token, uint256 amount) external onlySplitter {
        require(amount > 0, "Zero amount");
        
        totalDeposited[token] += amount;
        
        emit Deposited(token, amount, block.timestamp);
    }
    
    function claim(address token) external nonReentrant {
        uint256 claimable = getClaimableAmount(msg.sender, token);
        require(claimable > 0, "Nothing to claim");
        
        claimed[msg.sender][token] += claimable;
        totalClaimed[token] += claimable;
        
        // Transfer tokens
        if (token == address(0)) {
            // ETH
            (bool success, ) = msg.sender.call{value: claimable}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20
            IERC20(token).safeTransfer(msg.sender, claimable);
        }
        
        emit Claimed(msg.sender, token, claimable);
    }
    
    function claimAll() external nonReentrant {
        // This would iterate through all deposited tokens
        // For gas efficiency, we'll keep it simple for now
        revert("Use claim(token) for specific tokens");
    }
    
    function getClaimableAmount(address lender, address token) public view returns (uint256) {
        uint256 lenderBalance = IERC20(receiptToken).balanceOf(lender);
        uint256 totalSupply = IERC20(receiptToken).totalSupply();
        
        if (totalSupply == 0) return 0;
        
        uint256 lenderShare = (totalDeposited[token] * lenderBalance) / totalSupply;
        uint256 alreadyClaimed = claimed[lender][token];
        
        if (lenderShare <= alreadyClaimed) return 0;
        
        return lenderShare - alreadyClaimed;
    }
    
    function getTotalDeposited(address token) external view returns (uint256) {
        return totalDeposited[token];
    }
    
    function getReceiptToken() external view returns (address) {
        return receiptToken;
    }
    
    // Allow lenders to mint receipt tokens when they provide initial capital
    function mintReceiptTokens(address to, uint256 amount) external onlyOwner {
        RBFReceiptToken(receiptToken).mint(to, amount);
        emit ReceiptTokenMinted(to, amount);
    }
}

// Simple ERC20 receipt token
contract RBFReceiptToken is ERC20, Ownable {
    address public immutable vault;
    
    constructor(
        string memory name,
        string memory symbol,
        address _vault
    ) ERC20(name, symbol) Ownable(msg.sender) {
        vault = _vault;
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}