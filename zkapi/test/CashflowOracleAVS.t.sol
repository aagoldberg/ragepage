// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/CashflowOracleAVS.sol";
import "../src/core/OperatorRegistry.sol";
import "../src/core/ZKProofVerifier.sol";

contract CashflowOracleAVSTest is Test {
    CashflowOracleAVS public oracle;
    OperatorRegistry public registry;
    ZKProofVerifier public verifier;

    address public owner = address(this);
    address public operator1 = address(0x1);
    address public operator2 = address(0x2);
    address public merchant = address(0x3);

    function setUp() public {
        // Set a reasonable timestamp (not 1)
        vm.warp(365 days);

        // Deploy contracts
        registry = new OperatorRegistry();
        verifier = new ZKProofVerifier();
        oracle = new CashflowOracleAVS(address(registry), address(verifier));

        // Register operators
        vm.deal(operator1, 100 ether);
        vm.deal(operator2, 100 ether);

        vm.prank(operator1);
        registry.registerOperator{value: 32 ether}("http://operator1.com", hex"1234");

        vm.prank(operator2);
        registry.registerOperator{value: 32 ether}("http://operator2.com", hex"5678");
    }

    function testSubmitAttestation() public {
        // Create attestation
        ICashflowOracle.CashflowAttestation memory attestation = ICashflowOracle
            .CashflowAttestation({
            merchant: merchant,
            totalRevenue: 100_000 ether,
            periodStart: block.timestamp - 90 days,
            periodEnd: block.timestamp,
            apiSource: "shopify",
            zkProofHash: keccak256("test-proof"),
            verifiedAt: uint64(block.timestamp),
            quorumBps: 6700 // 67%
        });

        // Create operator list
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        // Submit attestation
        bytes memory dummySig = hex"1234567890";
        oracle.submitAttestation(attestation, dummySig, operators);

        // Verify attestation was stored
        (uint256 revenue, uint64 verifiedAt, string memory source) = oracle.getVerifiedRevenue(
            merchant,
            block.timestamp - 90 days,
            block.timestamp
        );

        assertEq(revenue, 100_000 ether);
        assertEq(source, "shopify");
    }

    function testRejectDuplicateProof() public {
        // Create attestation
        ICashflowOracle.CashflowAttestation memory attestation = ICashflowOracle
            .CashflowAttestation({
            merchant: merchant,
            totalRevenue: 100_000 ether,
            periodStart: block.timestamp - 90 days,
            periodEnd: block.timestamp,
            apiSource: "shopify",
            zkProofHash: keccak256("test-proof"),
            verifiedAt: uint64(block.timestamp),
            quorumBps: 6700
        });

        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        bytes memory dummySig = hex"1234567890";

        // Submit first time (should succeed)
        oracle.submitAttestation(attestation, dummySig, operators);

        // Submit second time (should fail)
        vm.expectRevert(CashflowOracleAVS.ProofAlreadyUsed.selector);
        oracle.submitAttestation(attestation, dummySig, operators);
    }

    function testGetCreditScore() public {
        // Submit multiple attestations to build history
        for (uint256 i = 0; i < 3; i++) {
            ICashflowOracle.CashflowAttestation memory attestation = ICashflowOracle
                .CashflowAttestation({
                merchant: merchant,
                totalRevenue: 100_000 ether + (i * 10_000 ether),
                periodStart: block.timestamp - 90 days,
                periodEnd: block.timestamp,
                apiSource: "shopify",
                zkProofHash: keccak256(abi.encodePacked("test-proof", i)),
                verifiedAt: uint64(block.timestamp),
                quorumBps: 6700
            });

            address[] memory operators = new address[](2);
            operators[0] = operator1;
            operators[1] = operator2;

            oracle.submitAttestation(attestation, hex"1234", operators);

            vm.warp(block.timestamp + 1 days);
        }

        // Get credit score
        uint256 score = oracle.getCreditScore(merchant);

        // Score should be > 500 (base) due to history and growth
        assertGt(score, 500);
    }

    function testHasRecentAttestation() public {
        // Submit attestation
        ICashflowOracle.CashflowAttestation memory attestation = ICashflowOracle
            .CashflowAttestation({
            merchant: merchant,
            totalRevenue: 100_000 ether,
            periodStart: block.timestamp - 90 days,
            periodEnd: block.timestamp,
            apiSource: "shopify",
            zkProofHash: keccak256("test-proof"),
            verifiedAt: uint64(block.timestamp),
            quorumBps: 6700
        });

        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        oracle.submitAttestation(attestation, hex"1234", operators);

        // Check immediately - should be recent
        assertTrue(oracle.hasRecentAttestation(merchant, 1 days));

        // Warp forward 8 days
        vm.warp(block.timestamp + 8 days);

        // Check again - should NOT be recent for 7 days
        assertFalse(oracle.hasRecentAttestation(merchant, 7 days));
    }
}
