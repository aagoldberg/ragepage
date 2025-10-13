// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/RevenueSplitter.sol";
import "../src/core/LenderVault.sol";
import "../src/core/RevenueAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        // Mint with 6 decimals like real USDC
        _mint(msg.sender, 1000000 * 10**6);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract RevenueSplitterFixedTest is Test {
    RevenueSplitter public splitter;
    LenderVault public lenderVault;
    RevenueAdapter public adapter;
    MockERC20 public usdc;
    
    address public treasury = address(0x1);
    address public governance = address(0x2);
    address public lender1 = address(0x3);
    address public lender2 = address(0x4);
    address public protocol = address(0x5);
    
    uint256 public constant ADVANCE_AMOUNT = 1000000 * 10**6; // 1M USDC (6 decimals)
    uint256 public constant CAP_MULTIPLE = 135; // 1.35x
    uint256 public constant SHARE_BPS = 1000; // 10%
    uint256 public constant DEAL_DURATION = 180 days;
    
    function setUp() public {
        // Deploy mock USDC
        usdc = new MockERC20();
        
        // Calculate repayment cap
        uint256 repaymentCap = (ADVANCE_AMOUNT * CAP_MULTIPLE) / 100;
        
        // Deploy lender vault (will be connected to splitter after)
        lenderVault = new LenderVault(
            address(this), // Temporary - will be overridden by splitter
            "RBF Receipt Token",
            "RBF-RECEIPT"
        );
        
        // Deploy revenue splitter
        splitter = new RevenueSplitter(
            treasury,
            address(lenderVault),
            SHARE_BPS,
            repaymentCap,
            DEAL_DURATION,
            500000 * 10**6, // 500k daily cap
            150000 * 10**6   // 150k transaction cap  
        );
        
        // Deploy adapter
        adapter = new RevenueAdapter(
            treasury,
            address(splitter),
            governance
        );
        
        // Setup allowed tokens
        splitter.setAllowedToken(address(usdc), true);
        splitter.setAllowedToken(address(0), true); // ETH
        
        // Mint receipt tokens to lenders (representing their initial investment)
        lenderVault.mintReceiptTokens(lender1, 600000 * 10**18); // 60% share
        lenderVault.mintReceiptTokens(lender2, 400000 * 10**18); // 40% share
        
        // Fund protocol with USDC for testing
        usdc.mint(protocol, 10000000 * 10**6); // 10M USDC
        
        // Fund treasury and protocol with ETH
        vm.deal(treasury, 100 ether);
        vm.deal(protocol, 100 ether);
        vm.deal(address(this), 100 ether);
    }
    
    function testBasicRevenueSplit() public {
        uint256 revenue = 100000 * 10**6; // 100k USDC revenue
        
        // Protocol approves and calls splitter directly
        vm.startPrank(protocol);
        usdc.approve(address(splitter), revenue);
        
        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);
        uint256 vaultBalanceBefore = usdc.balanceOf(address(lenderVault));
        
        // Send revenue through splitter
        splitter.onRevenue(address(usdc), revenue);
        
        // Check balances
        uint256 expectedToLenders = (revenue * SHARE_BPS) / 10000; // 10% = 10k
        uint256 expectedToTreasury = revenue - expectedToLenders; // 90k
        
        assertEq(usdc.balanceOf(address(lenderVault)) - vaultBalanceBefore, expectedToLenders);
        assertEq(usdc.balanceOf(treasury) - treasuryBalanceBefore, expectedToTreasury);
        
        // Check splitter state
        assertEq(splitter.getTotalPaid(), expectedToLenders);
        assertFalse(splitter.isCapReached());
        
        vm.stopPrank();
    }
    
    function testETHRevenue() public {
        uint256 revenue = 1 ether;
        
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 vaultBalanceBefore = address(lenderVault).balance;
        
        // Send ETH revenue directly to splitter
        (bool success, ) = address(splitter).call{value: revenue}("");
        assertTrue(success);
        
        // Check balances
        uint256 expectedToLenders = (revenue * SHARE_BPS) / 10000; // 10% = 0.1 ETH
        uint256 expectedToTreasury = revenue - expectedToLenders; // 0.9 ETH
        
        assertEq(address(lenderVault).balance - vaultBalanceBefore, expectedToLenders);
        assertEq(treasury.balance - treasuryBalanceBefore, expectedToTreasury);
    }
    
    function testCapEnforcement() public {
        uint256 repaymentCap = (ADVANCE_AMOUNT * CAP_MULTIPLE) / 100;
        uint256 revenuePerTx = 100000 * 10**6; // 100k USDC per transaction
        uint256 revenueNeededForCap = (repaymentCap * 10000) / SHARE_BPS; // Total revenue needed
        
        vm.startPrank(protocol);
        
        // Send revenue until almost at cap
        uint256 totalSentRevenue = 0;
        while (totalSentRevenue + revenuePerTx <= revenueNeededForCap) {
            usdc.approve(address(splitter), revenuePerTx);
            splitter.onRevenue(address(usdc), revenuePerTx);
            totalSentRevenue += revenuePerTx;
            
            if (splitter.isCapReached()) {
                break;
            }
        }
        
        assertTrue(splitter.isCapReached());
        
        // Try to send more revenue after cap reached - should revert
        usdc.approve(address(splitter), 10000 * 10**6);
        vm.expectRevert("Cap reached");
        splitter.onRevenue(address(usdc), 10000 * 10**6);
        
        vm.stopPrank();
    }
    
    function testSafetyRails() public {
        vm.startPrank(protocol);
        
        // Test transaction cap
        uint256 largeTx = 200000 * 10**6; // 200k USDC (exceeds 150k cap)
        usdc.approve(address(splitter), largeTx);
        
        vm.expectRevert("Exceeds transaction cap");
        splitter.onRevenue(address(usdc), largeTx);
        
        vm.stopPrank();
    }
    
    function testPauseUnpause() public {
        uint256 revenue = 50000 * 10**6; // 50k USDC
        
        // Pause the splitter
        splitter.pause();
        assertTrue(splitter.isPaused());
        
        // Try to send revenue while paused
        vm.startPrank(protocol);
        usdc.approve(address(splitter), revenue);
        
        vm.expectRevert();
        splitter.onRevenue(address(usdc), revenue);
        vm.stopPrank();
        
        // Unpause
        splitter.unpause();
        assertFalse(splitter.isPaused());
        
        // Now revenue should go through
        vm.startPrank(protocol);
        splitter.onRevenue(address(usdc), revenue);
        vm.stopPrank();
        
        assertEq(splitter.getTotalPaid(), (revenue * SHARE_BPS) / 10000);
    }
    
    function testAdapterForwarding() public {
        uint256 amount = 50000 * 10**6; // 50k USDC
        
        // Send USDC to adapter
        usdc.transfer(address(adapter), amount);
        
        uint256 vaultBalanceBefore = usdc.balanceOf(address(lenderVault));
        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);
        
        // Sweep tokens from adapter
        adapter.sweep(address(usdc));
        
        // Check that funds were forwarded to splitter and split correctly
        uint256 expectedToLenders = (amount * SHARE_BPS) / 10000;
        uint256 expectedToTreasury = amount - expectedToLenders;
        
        assertEq(usdc.balanceOf(address(lenderVault)) - vaultBalanceBefore, expectedToLenders);
        assertEq(usdc.balanceOf(treasury) - treasuryBalanceBefore, expectedToTreasury);
    }
    
    function testLenderClaims() public {
        uint256 revenue = 100000 * 10**6; // 100k USDC revenue
        
        // Send revenue through splitter
        vm.startPrank(protocol);
        usdc.approve(address(splitter), revenue);
        splitter.onRevenue(address(usdc), revenue);
        vm.stopPrank();
        
        // Lender 1 claims (60% share)
        vm.startPrank(lender1);
        uint256 claimable1 = lenderVault.getClaimableAmount(lender1, address(usdc));
        uint256 expectedClaim1 = (revenue * SHARE_BPS * 60) / (10000 * 100); // 60% of 10% = 6k
        
        assertEq(claimable1, expectedClaim1);
        
        uint256 balanceBefore1 = usdc.balanceOf(lender1);
        lenderVault.claim(address(usdc));
        assertEq(usdc.balanceOf(lender1) - balanceBefore1, expectedClaim1);
        vm.stopPrank();
        
        // Lender 2 claims (40% share)
        vm.startPrank(lender2);
        uint256 claimable2 = lenderVault.getClaimableAmount(lender2, address(usdc));
        uint256 expectedClaim2 = (revenue * SHARE_BPS * 40) / (10000 * 100); // 40% of 10% = 4k
        
        assertEq(claimable2, expectedClaim2);
        
        uint256 balanceBefore2 = usdc.balanceOf(lender2);
        lenderVault.claim(address(usdc));
        assertEq(usdc.balanceOf(lender2) - balanceBefore2, expectedClaim2);
        vm.stopPrank();
    }
}