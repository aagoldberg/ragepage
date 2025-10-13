// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/core/OperatorRegistry.sol";
import "../src/core/ZKProofVerifier.sol";
import "../src/core/CashflowOracleAVS.sol";
import "../src/integrations/SocialLoanAdapter.sol";

/**
 * @title Deploy
 * @notice Deployment script for Cashflow Oracle AVS
 *
 * Usage:
 * forge script script/Deploy.s.sol:Deploy --rpc-url <RPC_URL> --broadcast
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy OperatorRegistry
        console.log("Deploying OperatorRegistry...");
        OperatorRegistry operatorRegistry = new OperatorRegistry();
        console.log("OperatorRegistry deployed at:", address(operatorRegistry));

        // 2. Deploy ZKProofVerifier
        console.log("Deploying ZKProofVerifier...");
        // For MVP/testing, use zero address. In production, use actual Reclaim contract address
        // from @reclaimprotocol/verifier-solidity-sdk/contracts/Addresses.sol
        address reclaimAddress = address(0); // TODO: Set to actual Reclaim address for testnet/mainnet
        ZKProofVerifier proofVerifier = new ZKProofVerifier(reclaimAddress);
        console.log("ZKProofVerifier deployed at:", address(proofVerifier));

        // 3. Deploy CashflowOracleAVS
        console.log("Deploying CashflowOracleAVS...");
        CashflowOracleAVS cashflowOracle = new CashflowOracleAVS(
            address(operatorRegistry),
            address(proofVerifier)
        );
        console.log("CashflowOracleAVS deployed at:", address(cashflowOracle));

        // 4. Deploy SocialLoanAdapter
        console.log("Deploying SocialLoanAdapter...");
        SocialLoanAdapter loanAdapter = new SocialLoanAdapter(address(cashflowOracle));
        console.log("SocialLoanAdapter deployed at:", address(loanAdapter));

        // 5. Print summary
        console.log("\n=== Deployment Summary ===");
        console.log("OperatorRegistry:", address(operatorRegistry));
        console.log("ZKProofVerifier:", address(proofVerifier));
        console.log("CashflowOracleAVS:", address(cashflowOracle));
        console.log("SocialLoanAdapter:", address(loanAdapter));
        console.log("========================\n");

        vm.stopBroadcast();

        // 6. Save deployment addresses
        string memory json = string.concat(
            '{"operatorRegistry":"',
            vm.toString(address(operatorRegistry)),
            '","proofVerifier":"',
            vm.toString(address(proofVerifier)),
            '","cashflowOracle":"',
            vm.toString(address(cashflowOracle)),
            '","loanAdapter":"',
            vm.toString(address(loanAdapter)),
            '"}'
        );

        vm.writeFile("deployments/latest.json", json);
        console.log("Deployment addresses saved to deployments/latest.json");
    }
}
