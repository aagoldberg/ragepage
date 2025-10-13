// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/core/RevenueSplitter.sol";
import "../src/core/LenderVault.sol";
import "../src/core/RevenueAdapter.sol";
import "../src/optional/FeeRouter.sol";
import "../src/optional/DefaultVault.sol";

contract Deploy is Script {
    // Configuration
    struct DeploymentConfig {
        address treasury;
        address governance;
        uint256 shareBps;
        uint256 capMultiple; // e.g., 135 for 1.35x
        uint256 advanceAmount; // in wei/smallest unit
        uint256 dealDuration; // in seconds
        uint256 dailyCap;
        uint256 transactionCap;
        uint256 makeWholeAmount;
        uint256 curePeriodDuration;
        uint256 noPaymentThreshold;
        string receiptTokenName;
        string receiptTokenSymbol;
        bool deployFeeRouter;
        bool deployDefaultVault;
    }
    
    // Deployed contracts
    struct DeployedContracts {
        address revenueSplitter;
        address lenderVault;
        address revenueAdapter;
        address feeRouter;
        address defaultVault;
        address receiptToken;
    }
    
    function run() external returns (DeployedContracts memory) {
        // Load configuration from environment or use defaults
        DeploymentConfig memory config = getDeploymentConfig();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy LenderVault first (needs address for RevenueSplitter)
        LenderVault lenderVault = new LenderVault(
            address(0), // Will be set later
            config.receiptTokenName,
            config.receiptTokenSymbol
        );
        
        // Deploy RevenueSplitter
        uint256 repaymentCap = (config.advanceAmount * config.capMultiple) / 100;
        RevenueSplitter revenueSplitter = new RevenueSplitter(
            config.treasury,
            address(lenderVault),
            config.shareBps,
            repaymentCap,
            config.dealDuration,
            config.dailyCap,
            config.transactionCap
        );
        
        // Deploy RevenueAdapter
        RevenueAdapter revenueAdapter = new RevenueAdapter(
            config.treasury,
            address(revenueSplitter),
            config.governance
        );
        
        // Deploy optional contracts
        FeeRouter feeRouter;
        DefaultVault defaultVault;
        
        if (config.deployFeeRouter) {
            feeRouter = new FeeRouter(
                address(revenueAdapter),
                address(revenueSplitter),
                config.dealDuration,
                config.makeWholeAmount
            );
        }
        
        if (config.deployDefaultVault) {
            defaultVault = new DefaultVault(
                address(revenueSplitter),
                address(lenderVault),
                config.curePeriodDuration,
                config.noPaymentThreshold
            );
        }
        
        // Setup initial configurations
        _setupContracts(
            revenueSplitter,
            lenderVault,
            revenueAdapter,
            config
        );
        
        vm.stopBroadcast();
        
        // Log deployment addresses
        console.log("=== Revflow Deployment Complete ===");
        console.log("RevenueSplitter:", address(revenueSplitter));
        console.log("LenderVault:", address(lenderVault));
        console.log("RevenueAdapter:", address(revenueAdapter));
        console.log("ReceiptToken:", lenderVault.getReceiptToken());
        
        if (config.deployFeeRouter) {
            console.log("FeeRouter:", address(feeRouter));
        }
        
        if (config.deployDefaultVault) {
            console.log("DefaultVault:", address(defaultVault));
        }
        
        return DeployedContracts({
            revenueSplitter: address(revenueSplitter),
            lenderVault: address(lenderVault),
            revenueAdapter: address(revenueAdapter),
            feeRouter: address(feeRouter),
            defaultVault: address(defaultVault),
            receiptToken: lenderVault.getReceiptToken()
        });
    }
    
    function getDeploymentConfig() internal view returns (DeploymentConfig memory) {
        // Try to load from environment, fall back to defaults
        return DeploymentConfig({
            treasury: vm.envOr("TREASURY_ADDRESS", address(0)),
            governance: vm.envOr("GOVERNANCE_ADDRESS", address(0)),
            shareBps: vm.envOr("SHARE_BPS", uint256(1000)), // 10%
            capMultiple: vm.envOr("CAP_MULTIPLE", uint256(135)), // 1.35x
            advanceAmount: vm.envOr("ADVANCE_AMOUNT", uint256(1000000 * 10**6)), // 1M USDC
            dealDuration: vm.envOr("DEAL_DURATION", uint256(180 days)),
            dailyCap: vm.envOr("DAILY_CAP", uint256(100000 * 10**6)), // 100k
            transactionCap: vm.envOr("TRANSACTION_CAP", uint256(10000 * 10**6)), // 10k
            makeWholeAmount: vm.envOr("MAKE_WHOLE_AMOUNT", uint256(50000 * 10**6)), // 50k
            curePeriodDuration: vm.envOr("CURE_PERIOD_DURATION", uint256(7 days)),
            noPaymentThreshold: vm.envOr("NO_PAYMENT_THRESHOLD", uint256(14 days)),
            receiptTokenName: vm.envOr("RECEIPT_TOKEN_NAME", string("RBF Receipt Token")),
            receiptTokenSymbol: vm.envOr("RECEIPT_TOKEN_SYMBOL", string("RBF-RECEIPT")),
            deployFeeRouter: vm.envOr("DEPLOY_FEE_ROUTER", true),
            deployDefaultVault: vm.envOr("DEPLOY_DEFAULT_VAULT", true)
        });
    }
    
    function _setupContracts(
        RevenueSplitter revenueSplitter,
        LenderVault lenderVault,
        RevenueAdapter revenueAdapter,
        DeploymentConfig memory config
    ) internal {
        // Setup allowed tokens (USDC, ETH)
        address usdc = vm.envOr("USDC_ADDRESS", address(0));
        if (usdc != address(0)) {
            revenueSplitter.setAllowedToken(usdc, true);
        }
        
        // Allow ETH
        revenueSplitter.setAllowedToken(address(0), true);
        
        // Transfer ownership to governance
        if (config.governance != address(0)) {
            revenueSplitter.transferOwnership(config.governance);
            lenderVault.transferOwnership(config.governance);
            revenueAdapter.transferOwnership(config.governance);
        }
        
        console.log("Initial setup complete");
    }
}

// Separate script for testing deployment on local network
contract DeployLocal is Script {
    function run() external {
        // Use test addresses for local deployment
        vm.setEnv("TREASURY_ADDRESS", "0x1111111111111111111111111111111111111111");
        vm.setEnv("GOVERNANCE_ADDRESS", "0x2222222222222222222222222222222222222222");
        vm.setEnv("PRIVATE_KEY", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
        
        Deploy deployer = new Deploy();
        deployer.run();
    }
}