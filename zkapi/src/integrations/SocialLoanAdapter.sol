// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/ICashflowOracle.sol";

/**
 * @title SocialLoanAdapter
 * @notice Adapter contract for integrating cashflow verification into social loan protocols
 * @dev This provides helper functions and business logic for loan underwriting
 *
 * INTEGRATION GUIDE:
 * Your social loan protocol should inherit from this contract or use it as a library.
 * It provides ready-to-use functions for:
 * - Verifying merchant revenue
 * - Calculating loan eligibility
 * - Risk scoring
 * - Default prediction
 */
contract SocialLoanAdapter {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Reference to the Cashflow Oracle
    ICashflowOracle public immutable cashflowOracle;

    /// @notice Loan underwriting parameters
    struct UnderwritingParams {
        uint256 minRevenueMultiple;     // Minimum revenue as multiple of loan (e.g., 3x)
        uint256 maxDataAge;             // Maximum age of revenue data (e.g., 7 days)
        uint256 minCreditScore;         // Minimum credit score (0-1000)
        int256 minGrowthBps;            // Minimum growth rate in bps (-10000 to 10000)
    }

    /// @notice Default underwriting parameters
    UnderwritingParams public defaultParams;

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    event LoanEligibilityChecked(
        address indexed borrower,
        uint256 loanAmount,
        bool eligible,
        string reason
    );

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _cashflowOracle) {
        cashflowOracle = ICashflowOracle(_cashflowOracle);

        // Set default underwriting parameters
        defaultParams = UnderwritingParams({
            minRevenueMultiple: 3,      // 3x revenue to loan ratio
            maxDataAge: 7 days,         // Revenue data must be <7 days old
            minCreditScore: 500,        // Minimum score of 500
            minGrowthBps: -1000         // Allow up to -10% decline
        });
    }

    /*//////////////////////////////////////////////////////////////
                        UNDERWRITING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if borrower is eligible for a loan
     * @param borrower The merchant/borrower address
     * @param loanAmount The requested loan amount
     * @return eligible True if eligible
     * @return reason Explanation of decision
     */
    function checkLoanEligibility(
        address borrower,
        uint256 loanAmount
    ) public view returns (bool eligible, string memory reason) {
        return checkLoanEligibilityWithParams(borrower, loanAmount, defaultParams);
    }

    /**
     * @notice Check loan eligibility with custom parameters
     * @param borrower The merchant/borrower address
     * @param loanAmount The requested loan amount
     * @param params Custom underwriting parameters
     * @return eligible True if eligible
     * @return reason Explanation of decision
     */
    function checkLoanEligibilityWithParams(
        address borrower,
        uint256 loanAmount,
        UnderwritingParams memory params
    ) public view returns (bool eligible, string memory reason) {
        // 1. Check if merchant has recent revenue data
        if (!cashflowOracle.hasRecentAttestation(borrower, params.maxDataAge)) {
            return (false, "No recent revenue data");
        }

        // 2. Get verified revenue
        (uint256 totalRevenue, uint64 verifiedAt, string memory source) =
            cashflowOracle.getVerifiedRevenue(
                borrower,
                block.timestamp - 90 days,
                block.timestamp
            );

        // 3. Check revenue is sufficient (minimum multiple)
        uint256 requiredRevenue = loanAmount * params.minRevenueMultiple;
        if (totalRevenue < requiredRevenue) {
            return (false, "Insufficient revenue");
        }

        // 4. Check credit score
        uint256 creditScore = cashflowOracle.getCreditScore(borrower);
        if (creditScore < params.minCreditScore) {
            return (false, "Credit score too low");
        }

        // 5. Check revenue growth
        int256 growthBps = cashflowOracle.getRevenueGrowth(borrower);
        if (growthBps < params.minGrowthBps) {
            return (false, "Negative revenue trend");
        }

        // 6. All checks passed
        return (true, "Eligible for loan");
    }

    /**
     * @notice Calculate maximum loan amount for a borrower
     * @param borrower The merchant address
     * @return maxLoan Maximum loan amount based on verified revenue
     */
    function calculateMaxLoanAmount(address borrower)
        public
        view
        returns (uint256 maxLoan)
    {
        // Get latest revenue
        (uint256 totalRevenue,,) = cashflowOracle.getVerifiedRevenue(
            borrower,
            block.timestamp - 90 days,
            block.timestamp
        );

        // Max loan is revenue / minRevenueMultiple
        maxLoan = totalRevenue / defaultParams.minRevenueMultiple;

        return maxLoan;
    }

    /**
     * @notice Get comprehensive borrower profile
     * @param borrower The merchant address
     * @return profile Struct containing all borrower metrics
     */
    function getBorrowerProfile(address borrower)
        external
        view
        returns (BorrowerProfile memory profile)
    {
        (uint256 revenue, uint64 verifiedAt, string memory source) =
            cashflowOracle.getVerifiedRevenue(
                borrower,
                block.timestamp - 90 days,
                block.timestamp
            );

        profile = BorrowerProfile({
            totalRevenue: revenue,
            lastVerifiedAt: verifiedAt,
            dataSource: source,
            creditScore: cashflowOracle.getCreditScore(borrower),
            revenueGrowthBps: cashflowOracle.getRevenueGrowth(borrower),
            maxLoanAmount: calculateMaxLoanAmount(borrower),
            hasRecentData: cashflowOracle.hasRecentAttestation(borrower, defaultParams.maxDataAge)
        });

        return profile;
    }

    /**
     * @notice Calculate interest rate based on risk profile
     * @param borrower The merchant address
     * @return interestRateBps Interest rate in basis points (e.g., 500 = 5%)
     */
    function calculateInterestRate(address borrower)
        external
        view
        returns (uint256 interestRateBps)
    {
        uint256 creditScore = cashflowOracle.getCreditScore(borrower);
        int256 growthBps = cashflowOracle.getRevenueGrowth(borrower);

        // Base rate: 10%
        uint256 baseRate = 1000;

        // Adjust based on credit score (0-1000 scale)
        // High score (800+): -300 bps
        // Low score (0-400): +500 bps
        int256 scoreAdjustment;
        if (creditScore >= 800) {
            scoreAdjustment = -300;
        } else if (creditScore >= 600) {
            scoreAdjustment = -100;
        } else if (creditScore >= 400) {
            scoreAdjustment = 100;
        } else {
            scoreAdjustment = 500;
        }

        // Adjust based on growth
        // High growth (>20%): -200 bps
        // Negative growth: +300 bps
        int256 growthAdjustment;
        if (growthBps >= 2000) {
            growthAdjustment = -200;
        } else if (growthBps >= 1000) {
            growthAdjustment = -100;
        } else if (growthBps < 0) {
            growthAdjustment = 300;
        }

        // Calculate final rate
        int256 finalRate = int256(baseRate) + scoreAdjustment + growthAdjustment;

        // Clamp between 3% and 30%
        if (finalRate < 300) finalRate = 300;
        if (finalRate > 3000) finalRate = 3000;

        return uint256(finalRate);
    }

    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct BorrowerProfile {
        uint256 totalRevenue;
        uint64 lastVerifiedAt;
        string dataSource;
        uint256 creditScore;
        int256 revenueGrowthBps;
        uint256 maxLoanAmount;
        bool hasRecentData;
    }

    /*//////////////////////////////////////////////////////////////
                        EXAMPLE USAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Example function showing how to use this adapter in your loan contract
     * @dev You would call this from your social loan contract
     */
    function exampleLoanRequest(address borrower, uint256 loanAmount)
        external
        view
        returns (bool approved, string memory reason)
    {
        // Step 1: Check eligibility using cashflow oracle
        (bool eligible, string memory eligibilityReason) =
            checkLoanEligibility(borrower, loanAmount);

        if (!eligible) {
            return (false, eligibilityReason);
        }

        // Step 2: Your social underwriting logic here
        // - Check social endorsements
        // - Check reputation score
        // - Check community standing
        // etc.

        // Step 3: Combined decision
        return (true, "Loan approved - cashflow and social checks passed");
    }
}
