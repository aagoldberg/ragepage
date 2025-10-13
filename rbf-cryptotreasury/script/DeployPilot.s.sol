// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/core/RevenueSplitter.sol";
import "../src/core/LenderVault.sol";
import "../src/core/RevenueAdapter.sol";
import "../src/optional/FeeRouter.sol";
import "../src/optional/DefaultVault.sol";

contract DeployPilot is Script {
    // Pilot configuration for conservative deployment
    struct PilotConfig {
        string name;
        address treasury;
        address governance;
        uint256 shareBps;
        uint256 capMultiple;
        uint256 advanceAmount;
        uint256 dealDuration;
        uint256 dailyCap;
        uint256 transactionCap;
        uint256 makeWholeAmount;
        uint256 curePeriodDuration;
        uint256 noPaymentThreshold;
        bool deployFeeRouter;
        bool deployDefaultVault;
    }
    
    // Deployed contracts for pilot
    struct PilotDeployment {
        address revenueSplitter;
        address lenderVault;
        address revenueAdapter;
        address feeRouter;
        address defaultVault;
        address receiptToken;
        uint256 deploymentBlock;
        uint256 deploymentTime;
        string configUsed;
    }
    
    function deployTestnetPilot() external returns (PilotDeployment memory) {
        PilotConfig memory config = PilotConfig({
            name: "Testnet Conservative Pilot",
            treasury: vm.envOr("TREASURY_ADDRESS", address(0x1111111111111111111111111111111111111111)),
            governance: vm.envOr("GOVERNANCE_ADDRESS", address(0x2222222222222222222222222222222222222222)),
            shareBps: 300, // 3%
            capMultiple: 120, // 1.20x
            advanceAmount: 100000 * 10**6, // 100k USDC
            dealDuration: 60 days,
            dailyCap: 10000 * 10**6, // 10k USDC
            transactionCap: 5000 * 10**6, // 5k USDC
            makeWholeAmount: 5000 * 10**6, // 5k USDC
            curePeriodDuration: 7 days,
            noPaymentThreshold: 14 days,
            deployFeeRouter: true,
            deployDefaultVault: true
        });
        
        return _deployWithConfig(config, "testnet_pilot");
    }
    
    function deployMainnetConservative() external returns (PilotDeployment memory) {
        PilotConfig memory config = PilotConfig({
            name: "Mainnet Ultra-Conservative Pilot",
            treasury: vm.envAddress("TREASURY_ADDRESS"),
            governance: vm.envAddress("GOVERNANCE_ADDRESS"),
            shareBps: 500, // 5%
            capMultiple: 125, // 1.25x
            advanceAmount: 500000 * 10**6, // 500k USDC
            dealDuration: 90 days,
            dailyCap: 25000 * 10**6, // 25k USDC
            transactionCap: 10000 * 10**6, // 10k USDC
            makeWholeAmount: 25000 * 10**6, // 25k USDC
            curePeriodDuration: 7 days,
            noPaymentThreshold: 14 days,
            deployFeeRouter: true,
            deployDefaultVault: true
        });
        
        return _deployWithConfig(config, "mainnet_conservative");
    }
    
    function deployDeFiProtocolPilot() external returns (PilotDeployment memory) {
        PilotConfig memory config = PilotConfig({
            name: "DeFi Protocol Pilot",
            treasury: vm.envAddress("TREASURY_ADDRESS"),
            governance: vm.envAddress("GOVERNANCE_ADDRESS"),
            shareBps: 800, // 8%
            capMultiple: 130, // 1.30x
            advanceAmount: 1000000 * 10**6, // 1M USDC
            dealDuration: 120 days,
            dailyCap: 50000 * 10**6, // 50k USDC
            transactionCap: 20000 * 10**6, // 20k USDC
            makeWholeAmount: 50000 * 10**6, // 50k USDC
            curePeriodDuration: 5 days,
            noPaymentThreshold: 10 days,
            deployFeeRouter: true,
            deployDefaultVault: true
        });
        
        return _deployWithConfig(config, "defi_protocol_pilot");
    }
    
    function _deployWithConfig(
        PilotConfig memory config,
        string memory configName
    ) internal returns (PilotDeployment memory deployment) {
        console.log("=== Deploying Revflow Pilot: %s ===", config.name);
        console.log("Treasury: %s", config.treasury);
        console.log("Share: %d bps (%d%%)", config.shareBps, config.shareBps / 100);
        console.log("Advance: %d USDC", config.advanceAmount / 10**6);
        console.log("Cap Multiple: %d.%02d x", config.capMultiple / 100, config.capMultiple % 100);
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Calculate repayment cap
        uint256 repaymentCap = (config.advanceAmount * config.capMultiple) / 100;
        console.log("Repayment Cap: %d USDC", repaymentCap / 10**6);
        
        // Deploy LenderVault with temporary splitter address
        // We'll use CREATE2 to predict the splitter address, or deploy with a factory
        // For now, using a simpler approach with address prediction
        
        address predictedSplitterAddr = vm.computeCreateAddress(
            vm.addr(deployerPrivateKey),
            vm.getNonce(vm.addr(deployerPrivateKey)) + 1
        );
        
        LenderVault lenderVault = new LenderVault(
            predictedSplitterAddr,
            string.concat(config.name, " Receipt"),
            "RBF-PILOT"
        );
        
        // Deploy RevenueSplitter (should match predicted address)
        RevenueSplitter revenueSplitter = new RevenueSplitter(
            config.treasury,
            address(lenderVault),
            config.shareBps,
            repaymentCap,
            config.dealDuration,
            config.dailyCap,
            config.transactionCap
        );
        
        // Verify address prediction worked
        require(
            address(revenueSplitter) == predictedSplitterAddr,
            "Address prediction failed"
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
            console.log("FeeRouter deployed: %s", address(feeRouter));
        }
        
        if (config.deployDefaultVault) {
            defaultVault = new DefaultVault(
                address(revenueSplitter),
                address(lenderVault),
                config.curePeriodDuration,
                config.noPaymentThreshold
            );
            console.log("DefaultVault deployed: %s", address(defaultVault));
        }
        
        // Setup initial configurations with conservative settings
        _setupPilotConfiguration(
            revenueSplitter,
            revenueAdapter,
            config
        );
        
        vm.stopBroadcast();
        
        // Prepare deployment info
        deployment = PilotDeployment({
            revenueSplitter: address(revenueSplitter),
            lenderVault: address(lenderVault),
            revenueAdapter: address(revenueAdapter),
            feeRouter: address(feeRouter),
            defaultVault: address(defaultVault),
            receiptToken: lenderVault.getReceiptToken(),
            deploymentBlock: block.number,
            deploymentTime: block.timestamp,
            configUsed: configName
        });
        
        _logDeploymentSummary(deployment, config);
    }
    
    function _setupPilotConfiguration(
        RevenueSplitter splitter,
        RevenueAdapter adapter,
        PilotConfig memory config
    ) internal {
        console.log("Setting up pilot configuration...");
        
        // Setup allowed tokens (conservative list)
        address usdc = vm.envOr("USDC_ADDRESS", address(0xA0b86a33E6417C42e8BE7CC4b06a76C8C3A3b2a0));
        if (usdc != address(0)) {
            splitter.setAllowedToken(usdc, true);
            console.log("USDC allowed: %s", usdc);
        }
        
        // Allow ETH for L2 sequencer revenue
        splitter.setAllowedToken(address(0), true);
        console.log("ETH allowed for sequencer revenue");
        
        // Transfer ownership to governance with timelock
        if (config.governance != address(0)) {
            splitter.transferOwnership(config.governance);
            adapter.transferOwnership(config.governance);
            console.log("Ownership transferred to governance: %s", config.governance);
        }
        
        console.log("Pilot configuration complete");
    }
    
    function _logDeploymentSummary(
        PilotDeployment memory deployment,
        PilotConfig memory config
    ) internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Config: %s", config.name);
        console.log("Block: %d", deployment.deploymentBlock);
        console.log("Timestamp: %d", deployment.deploymentTime);
        console.log("");
        console.log("Core Contracts:");
        console.log("  RevenueSplitter: %s", deployment.revenueSplitter);
        console.log("  LenderVault: %s", deployment.lenderVault);
        console.log("  RevenueAdapter: %s", deployment.revenueAdapter);
        console.log("  ReceiptToken: %s", deployment.receiptToken);
        
        if (deployment.feeRouter != address(0)) {
            console.log("  FeeRouter: %s", deployment.feeRouter);
        }
        
        if (deployment.defaultVault != address(0)) {
            console.log("  DefaultVault: %s", deployment.defaultVault);
        }
        
        console.log("");
        console.log("Parameters:");
        console.log("  Share: %d%% (%d bps)", config.shareBps / 100, config.shareBps);
        console.log("  Advance: %d USDC", config.advanceAmount / 10**6);
        console.log("  Cap: %d USDC (%.2fx)", 
            (config.advanceAmount * config.capMultiple / 100) / 10**6,
            config.capMultiple / 100
        );
        console.log("  Duration: %d days", config.dealDuration / 1 days);
        console.log("  Daily Cap: %d USDC", config.dailyCap / 10**6);
        console.log("  Transaction Cap: %d USDC", config.transactionCap / 10**6);
        
        console.log("\n=== NEXT STEPS ===");
        console.log("1. Verify contracts on Etherscan");
        console.log("2. Set up subgraph monitoring");
        console.log("3. Configure automation (Defender/Gelato)");
        console.log("4. Test with small amounts first");
        console.log("5. Gradually increase limits after validation");
        console.log("========================");
    }
}

// Simplified deployment for local testing
contract DeployPilotLocal is Script {
    function run() external {
        // Use minimal config for local testing
        vm.setEnv("TREASURY_ADDRESS", "0x1111111111111111111111111111111111111111");
        vm.setEnv("GOVERNANCE_ADDRESS", "0x2222222222222222222222222222222222222222");
        vm.setEnv("PRIVATE_KEY", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
        
        DeployPilot deployer = new DeployPilot();
        deployer.deployTestnetPilot();
    }
}