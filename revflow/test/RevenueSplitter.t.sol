// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/RevenueSplitter.sol";
import "../src/core/LenderVault.sol";
import "../src/core/RevenueAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RevenueSplitterTest is Test {
    RevenueSplitter public splitter;
    LenderVault public lenderVault;
    RevenueAdapter public adapter;
    MockERC20 public usdc;
    
    address public treasury = address(0x1);
    address public governance = address(0x2);
    address public lender1 = address(0x3);
    address public lender2 = address(0x4);
    address public protocol = address(0x5);
    
    uint256 public constant ADVANCE_AMOUNT = 1000000 * 10**6; // 1M USDC
    uint256 public constant CAP_MULTIPLE = 135; // 1.35x
    uint256 public constant SHARE_BPS = 1000; // 10%
    uint256 public constant DEAL_DURATION = 180 days;
    
    function setUp() public {
        // Deploy mock USDC
        usdc = new MockERC20();
        
        // Deploy revenue splitter first
        uint256 repaymentCap = (ADVANCE_AMOUNT * CAP_MULTIPLE) / 100;
        
        // Deploy lender vault with placeholder splitter
        lenderVault = new LenderVault(
            address(0x123), // Temporary address - will fix after splitter deployment
            "RBF Receipt Token",
            "RBF-RECEIPT"
        );
        
        splitter = new RevenueSplitter(
            treasury,
            address(lenderVault),
            SHARE_BPS,
            repaymentCap,
            DEAL_DURATION,
            1000000 * 10**6, // 1M daily cap
            200000 * 10**6   // 200k transaction cap
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
    }
    
    function testBasicRevenueSplit() public {
        uint256 revenue = 100000 * 10**6; // 100k USDC revenue
        
        // Protocol approves splitter
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
        
        vm.stopPrank();
    }
    
    function testCapEnforcement() public {
        uint256 repaymentCap = (ADVANCE_AMOUNT * CAP_MULTIPLE) / 100;
        uint256 revenuePerTx = 1000000 * 10**6; // 1M USDC per transaction
        
        vm.startPrank(protocol);
        
        // Send revenue until cap is almost reached
        uint256 totalSent = 0;
        while (totalSent < repaymentCap) {
            usdc.approve(address(splitter), revenuePerTx);
            
            if (totalSent + (revenuePerTx * SHARE_BPS) / 10000 > repaymentCap) {
                // This should be the last transaction that partially fills the cap
                uint256 remainingCap = repaymentCap - splitter.getTotalPaid();
                splitter.onRevenue(address(usdc), revenuePerTx);
                
                // Check that only remaining cap was sent to lenders
                assertEq(splitter.getTotalPaid(), repaymentCap);
                assertTrue(splitter.isCapReached());
                break;
            }
            
            splitter.onRevenue(address(usdc), revenuePerTx);
            totalSent = splitter.getTotalPaid();
        }
        
        // Try to send more revenue after cap reached - should revert
        usdc.approve(address(splitter), 100000 * 10**6);
        vm.expectRevert("Cap reached");
        splitter.onRevenue(address(usdc), 100000 * 10**6);
        
        vm.stopPrank();
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
    
    function testETHRevenue() public {
        uint256 revenue = 10 ether;
        
        // Fund protocol with ETH
        vm.deal(protocol, revenue);
        
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 vaultBalanceBefore = address(lenderVault).balance;
        
        // Send ETH revenue through splitter
        vm.startPrank(protocol);
        (bool success, ) = address(splitter).call{value: revenue}("");
        assertTrue(success);
        vm.stopPrank();
        
        // Check balances
        uint256 expectedToLenders = (revenue * SHARE_BPS) / 10000; // 10% = 1 ETH
        uint256 expectedToTreasury = revenue - expectedToLenders; // 9 ETH
        
        assertEq(address(lenderVault).balance - vaultBalanceBefore, expectedToLenders);
        assertEq(treasury.balance - treasuryBalanceBefore, expectedToTreasury);
    }
    
    function testSafetyRails() public {
        // Test transaction cap
        uint256 largeTx = 20000 * 10**6; // 20k USDC (exceeds 10k cap)
        
        vm.startPrank(protocol);
        usdc.approve(address(splitter), largeTx);
        
        vm.expectRevert("Exceeds transaction cap");
        splitter.onRevenue(address(usdc), largeTx);
        
        // Test daily cap
        uint256 normalTx = 5000 * 10**6; // 5k USDC
        
        // Send multiple transactions to exceed daily cap
        for (uint i = 0; i < 20; i++) {
            usdc.approve(address(splitter), normalTx);
            
            if (i < 20) { // First 20 txs should succeed (100k daily cap)
                splitter.onRevenue(address(usdc), normalTx);
            }
        }
        
        // Next transaction should fail
        usdc.approve(address(splitter), normalTx);
        vm.expectRevert("Exceeds daily cap");
        splitter.onRevenue(address(usdc), normalTx);
        
        vm.stopPrank();
    }
    
    function testPauseUnpause() public {
        uint256 revenue = 100000 * 10**6;
        
        // Pause the splitter
        splitter.pause();
        assertTrue(splitter.isPaused());
        
        // Try to send revenue while paused
        vm.startPrank(protocol);
        usdc.approve(address(splitter), revenue);
        
        vm.expectRevert("Pausable: paused");
        splitter.onRevenue(address(usdc), revenue);
        vm.stopPrank();
        
        // Unpause
        splitter.unpause();
        assertFalse(splitter.isPaused());
        
        // Now revenue should go through
        vm.startPrank(protocol);
        splitter.onRevenue(address(usdc), revenue);
        vm.stopPrank();
    }
    
    function testAdapterForwarding() public {
        uint256 amount = 100000 * 10**6;
        
        // Send USDC to adapter
        usdc.mint(address(adapter), amount);
        
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
}