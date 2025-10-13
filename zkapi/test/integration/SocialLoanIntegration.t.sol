// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/core/CashflowOracleAVS.sol";
import "../../src/core/OperatorRegistry.sol";
import "../../src/core/ZKProofVerifier.sol";
import "../../src/integrations/SocialLoanAdapter.sol";

/**
 * @title SocialLoanIntegration
 * @notice Integration test showing how to use Cashflow Oracle in a social loan protocol
 */
contract SocialLoanIntegration is Test {
    CashflowOracleAVS public oracle;
    OperatorRegistry public registry;
    ZKProofVerifier public verifier;
    SocialLoanAdapter public loanAdapter;

    address public operator1 = address(0x1);
    address public merchant = address(0x3);

    function setUp() public {
        // Set a reasonable timestamp (not 1)
        vm.warp(365 days);

        // Deploy full stack
        registry = new OperatorRegistry();
        verifier = new ZKProofVerifier();
        oracle = new CashflowOracleAVS(address(registry), address(verifier));
        loanAdapter = new SocialLoanAdapter(address(oracle));

        // Register operator
        vm.deal(operator1, 100 ether);
        vm.prank(operator1);
        registry.registerOperator{value: 32 ether}("http://operator1.com", hex"1234");
    }

    function testLoanApprovalFlow() public {
        // 1. Merchant generates zkTLS proof (off-chain)
        // 2. Operators verify and submit attestation

        ICashflowOracle.CashflowAttestation memory attestation = ICashflowOracle
            .CashflowAttestation({
            merchant: merchant,
            totalRevenue: 300_000 ether, // $300k revenue
            periodStart: block.timestamp - 90 days,
            periodEnd: block.timestamp,
            apiSource: "shopify",
            zkProofHash: keccak256("merchant-proof"),
            verifiedAt: uint64(block.timestamp),
            quorumBps: 6700
        });

        address[] memory operators = new address[](1);
        operators[0] = operator1;

        oracle.submitAttestation(attestation, hex"1234", operators);

        // 3. Check loan eligibility through adapter
        uint256 requestedLoan = 100_000 ether; // $100k loan
        (bool eligible, string memory reason) =
            loanAdapter.checkLoanEligibility(merchant, requestedLoan);

        // Should be eligible: 300k revenue > 100k * 3x multiple
        assertTrue(eligible, reason);
    }

    function testLoanRejectionInsufficientRevenue() public {
        // Submit attestation with low revenue
        ICashflowOracle.CashflowAttestation memory attestation = ICashflowOracle
            .CashflowAttestation({
            merchant: merchant,
            totalRevenue: 50_000 ether, // Only $50k revenue
            periodStart: block.timestamp - 90 days,
            periodEnd: block.timestamp,
            apiSource: "square",
            zkProofHash: keccak256("merchant-proof"),
            verifiedAt: uint64(block.timestamp),
            quorumBps: 6700
        });

        address[] memory operators = new address[](1);
        operators[0] = operator1;

        oracle.submitAttestation(attestation, hex"1234", operators);

        // Request loan that's too large
        uint256 requestedLoan = 50_000 ether; // $50k loan needs $150k revenue (3x)
        (bool eligible, string memory reason) =
            loanAdapter.checkLoanEligibility(merchant, requestedLoan);

        // Should be rejected
        assertFalse(eligible);
        assertEq(reason, "Insufficient revenue");
    }

    function testCalculateMaxLoanAmount() public {
        // Submit attestation
        ICashflowOracle.CashflowAttestation memory attestation = ICashflowOracle
            .CashflowAttestation({
            merchant: merchant,
            totalRevenue: 300_000 ether,
            periodStart: block.timestamp - 90 days,
            periodEnd: block.timestamp,
            apiSource: "shopify",
            zkProofHash: keccak256("merchant-proof"),
            verifiedAt: uint64(block.timestamp),
            quorumBps: 6700
        });

        address[] memory operators = new address[](1);
        operators[0] = operator1;

        oracle.submitAttestation(attestation, hex"1234", operators);

        // Calculate max loan
        uint256 maxLoan = loanAdapter.calculateMaxLoanAmount(merchant);

        // Max should be revenue / 3 = 100k
        assertEq(maxLoan, 100_000 ether);
    }

    function testGetBorrowerProfile() public {
        // Submit attestation
        ICashflowOracle.CashflowAttestation memory attestation = ICashflowOracle
            .CashflowAttestation({
            merchant: merchant,
            totalRevenue: 300_000 ether,
            periodStart: block.timestamp - 90 days,
            periodEnd: block.timestamp,
            apiSource: "shopify",
            zkProofHash: keccak256("merchant-proof"),
            verifiedAt: uint64(block.timestamp),
            quorumBps: 6700
        });

        address[] memory operators = new address[](1);
        operators[0] = operator1;

        oracle.submitAttestation(attestation, hex"1234", operators);

        // Get full profile
        SocialLoanAdapter.BorrowerProfile memory profile =
            loanAdapter.getBorrowerProfile(merchant);

        assertEq(profile.totalRevenue, 300_000 ether);
        assertEq(profile.dataSource, "shopify");
        assertTrue(profile.hasRecentData);
        assertEq(profile.maxLoanAmount, 100_000 ether);
    }

    function testInterestRateCalculation() public {
        // Submit multiple attestations to build credit history
        for (uint256 i = 0; i < 3; i++) {
            ICashflowOracle.CashflowAttestation memory attestation = ICashflowOracle
                .CashflowAttestation({
                merchant: merchant,
                totalRevenue: 100_000 ether + (i * 20_000 ether), // Growing revenue
                periodStart: block.timestamp - 90 days,
                periodEnd: block.timestamp,
                apiSource: "shopify",
                zkProofHash: keccak256(abi.encodePacked("proof", i)),
                verifiedAt: uint64(block.timestamp),
                quorumBps: 6700
            });

            address[] memory operators = new address[](1);
            operators[0] = operator1;

            oracle.submitAttestation(attestation, hex"1234", operators);
            vm.warp(block.timestamp + 30 days);
        }

        // Calculate interest rate
        uint256 interestRate = loanAdapter.calculateInterestRate(merchant);

        // Should be < 10% base rate due to good credit and growth
        assertLt(interestRate, 1000);
    }
}
