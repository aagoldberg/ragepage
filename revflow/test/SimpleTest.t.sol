// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/RevenueSplitter.sol";
import "../src/core/LenderVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1000000 * 10**6);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract SimpleTest is Test {
    RevenueSplitter public splitter;
    LenderVault public lenderVault;
    MockERC20 public usdc;
    
    address public treasury = address(0x1);
    address public lender1 = address(0x3);
    address public protocol = address(0x5);
    
    function setUp() public {
        usdc = new MockERC20();
        
        // First deploy LenderVault with a placeholder
        lenderVault = new LenderVault(
            address(0), // Will be overridden
            "RBF Receipt Token",
            "RBF-RECEIPT"
        );
        
        // Deploy RevenueSplitter
        splitter = new RevenueSplitter(
            treasury,
            address(lenderVault),
            1000, // 10% share
            1350000 * 10**6, // 1.35M cap
            180 days, // duration
            500000 * 10**6, // daily cap
            150000 * 10**6   // tx cap
        );
        
        // Setup allowed tokens
        splitter.setAllowedToken(address(usdc), true);
        
        // Mint receipt tokens to lender
        lenderVault.mintReceiptTokens(lender1, 1000000 * 10**18);
        
        // Fund protocol
        usdc.mint(protocol, 10000000 * 10**6);
        vm.deal(address(this), 100 ether);
    }
    
    function testDirectSplitterCall() public {
        uint256 revenue = 100000 * 10**6; // 100k USDC
        
        console.log("Splitter address:", address(splitter));
        console.log("LenderVault splitter:", lenderVault.splitter());
        
        // The issue is that LenderVault.splitter() returns address(0)
        // But RevenueSplitter is trying to call depositFor()
        
        vm.startPrank(protocol);
        usdc.approve(address(splitter), revenue);
        
        // This should fail with "Only splitter" because LenderVault
        // was constructed with address(0) as splitter
        vm.expectRevert("Only splitter");
        splitter.onRevenue(address(usdc), revenue);
        
        vm.stopPrank();
    }
}