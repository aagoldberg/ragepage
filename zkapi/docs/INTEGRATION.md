# Integration Guide: Cashflow Oracle + Social Loan Protocol

This guide shows you how to integrate the Cashflow Oracle AVS into your social underwriting loan protocol.

## Quick Start

### 1. Import the Interface

```solidity
import "zkapi/src/interfaces/ICashflowOracle.sol";
```

### 2. Reference the Oracle

```solidity
contract YourSocialLoanProtocol {
    ICashflowOracle public cashflowOracle;

    constructor(address _cashflowOracle) {
        cashflowOracle = ICashflowOracle(_cashflowOracle);
    }
}
```

### 3. Query Verified Revenue

```solidity
function requestLoan(uint256 amount) external {
    // Get verified revenue for the borrower
    (uint256 revenue, uint64 verifiedAt, string memory source) =
        cashflowOracle.getVerifiedRevenue(
            msg.sender,
            block.timestamp - 90 days,  // Last 90 days
            block.timestamp
        );

    // Check revenue is sufficient (e.g., 3x loan amount)
    require(revenue >= amount * 3, "Insufficient revenue");

    // Check data is recent (< 7 days old)
    require(block.timestamp - verifiedAt < 7 days, "Stale data");

    // Your social underwriting logic here...
    // - Check endorsements
    // - Check reputation
    // - etc.

    // Approve loan...
}
```

## Using the Social Loan Adapter

For convenience, we provide `SocialLoanAdapter` with ready-to-use functions:

### Option A: Inherit from Adapter

```solidity
import "zkapi/src/integrations/SocialLoanAdapter.sol";

contract YourLoanProtocol is SocialLoanAdapter {
    constructor(address _cashflowOracle)
        SocialLoanAdapter(_cashflowOracle)
    {}

    function requestLoan(uint256 amount) external {
        // Check cashflow eligibility
        (bool eligible, string memory reason) =
            checkLoanEligibility(msg.sender, amount);

        require(eligible, reason);

        // Your social checks...
        require(checkSocialEndorsements(msg.sender), "No endorsements");

        // Approve loan
        _issueLoan(msg.sender, amount);
    }
}
```

### Option B: Use Adapter as Library

```solidity
contract YourLoanProtocol {
    SocialLoanAdapter public adapter;

    function requestLoan(uint256 amount) external {
        // Get borrower profile
        SocialLoanAdapter.BorrowerProfile memory profile =
            adapter.getBorrowerProfile(msg.sender);

        // Calculate interest rate
        uint256 interestRate = adapter.calculateInterestRate(msg.sender);

        // Your logic...
    }
}
```

## Common Integration Patterns

### Pattern 1: Two-Factor Underwriting (Cashflow + Social)

```solidity
function approveLoan(address borrower, uint256 amount)
    external
    returns (bool approved)
{
    // Factor 1: Cashflow verification (objective)
    (bool cashflowOk,) = checkLoanEligibility(borrower, amount);
    if (!cashflowOk) return false;

    // Factor 2: Social verification (community-driven)
    uint256 endorsements = getEndorsementCount(borrower);
    uint256 reputation = getReputationScore(borrower);

    bool socialOk = endorsements >= 3 && reputation >= 500;

    return cashflowOk && socialOk;
}
```

### Pattern 2: Risk-Adjusted Pricing

```solidity
function calculateLoanTerms(address borrower, uint256 amount)
    external
    view
    returns (uint256 interestRate, uint256 maxAmount)
{
    // Get cashflow metrics
    uint256 creditScore = cashflowOracle.getCreditScore(borrower);
    int256 growth = cashflowOracle.getRevenueGrowth(borrower);

    // Get social metrics
    uint256 socialScore = getSocialScore(borrower);

    // Combined scoring
    uint256 baseRate = 1000; // 10%

    // Adjust for cashflow
    if (creditScore >= 800) baseRate -= 200;
    else if (creditScore < 400) baseRate += 300;

    // Adjust for social trust
    if (socialScore >= 900) baseRate -= 100;
    else if (socialScore < 300) baseRate += 200;

    return (baseRate, calculateMaxAmount(borrower));
}
```

### Pattern 3: Progressive Trust Building

```solidity
mapping(address => uint256) public loanTier;

function getMaxLoanForTier(address borrower)
    external
    view
    returns (uint256)
{
    uint256 tier = loanTier[borrower];
    uint256 cashflowMax = calculateMaxLoanAmount(borrower);

    // Tier 0: New borrower - 10% of cashflow limit
    if (tier == 0) return cashflowMax / 10;

    // Tier 1: 1 successful loan - 30% of limit
    if (tier == 1) return cashflowMax * 3 / 10;

    // Tier 2: 3+ successful loans - 100% of limit
    return cashflowMax;
}
```

## API Reference

### Core Functions

#### `getVerifiedRevenue()`
```solidity
function getVerifiedRevenue(
    address merchant,
    uint256 startTimestamp,
    uint256 endTimestamp
) external view returns (
    uint256 totalRevenue,
    uint64 verifiedAt,
    string memory source
)
```

**Returns:**
- `totalRevenue`: Total revenue in the period (in wei)
- `verifiedAt`: Unix timestamp when verified
- `source`: Data source ("shopify", "square", "plaid")

#### `getCreditScore()`
```solidity
function getCreditScore(address merchant)
    external view returns (uint256 score)
```

**Returns:**
- `score`: Credit score 0-1000 (higher is better)

**Scoring factors:**
- Base: 500
- History: +100 per attestation (max 5)
- Growth: +50 for consistent growth
- High revenue: +50 for >$100k

#### `getRevenueGrowth()`
```solidity
function getRevenueGrowth(address merchant)
    external view returns (int256 growthBps)
```

**Returns:**
- `growthBps`: Growth rate in basis points (100 = 1%)
  - Positive = revenue growing
  - Negative = revenue declining

#### `hasRecentAttestation()`
```solidity
function hasRecentAttestation(address merchant, uint256 maxAge)
    external view returns (bool)
```

**Parameters:**
- `maxAge`: Maximum age in seconds (e.g., 7 days)

## Example: Complete Loan Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "zkapi/src/interfaces/ICashflowOracle.sol";

contract SocialLoan {
    ICashflowOracle public cashflowOracle;

    struct Loan {
        uint256 amount;
        uint256 interestRate;
        uint256 dueDate;
        bool repaid;
    }

    mapping(address => Loan) public loans;
    mapping(address => uint256) public socialScore;

    constructor(address _cashflowOracle) {
        cashflowOracle = ICashflowOracle(_cashflowOracle);
    }

    function requestLoan(uint256 amount) external {
        // 1. Cashflow check
        (uint256 revenue, uint64 verifiedAt,) =
            cashflowOracle.getVerifiedRevenue(
                msg.sender,
                block.timestamp - 90 days,
                block.timestamp
            );

        require(revenue >= amount * 3, "Need 3x revenue");
        require(block.timestamp - verifiedAt < 7 days, "Data too old");

        // 2. Social check
        require(socialScore[msg.sender] >= 500, "Low social score");

        // 3. Calculate terms
        uint256 creditScore = cashflowOracle.getCreditScore(msg.sender);
        uint256 interestRate = calculateRate(creditScore);

        // 4. Issue loan
        loans[msg.sender] = Loan({
            amount: amount,
            interestRate: interestRate,
            dueDate: block.timestamp + 90 days,
            repaid: false
        });

        // Transfer funds
        payable(msg.sender).transfer(amount);
    }

    function calculateRate(uint256 creditScore)
        internal
        pure
        returns (uint256)
    {
        if (creditScore >= 800) return 500;  // 5%
        if (creditScore >= 600) return 800;  // 8%
        return 1200; // 12%
    }

    // ... repayment functions ...
}
```

## Testing Your Integration

```solidity
// test/YourLoanProtocol.t.sol
import "forge-std/Test.sol";

contract YourLoanProtocolTest is Test {
    function testLoanWithCashflowVerification() public {
        // Setup
        // ... deploy contracts ...

        // Submit cashflow attestation
        // ... operator submits proof ...

        // Request loan
        vm.prank(borrower);
        protocol.requestLoan(100_000 ether);

        // Verify loan was approved
        // ...
    }
}
```

Run tests:
```bash
forge test
```

## Deployment

1. Deploy the oracle contracts:
```bash
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

2. Use the deployed addresses in your protocol:
```solidity
address cashflowOracle = 0x...; // From deployments/latest.json
YourProtocol protocol = new YourProtocol(cashflowOracle);
```

## Need Help?

- Check `test/integration/SocialLoanIntegration.t.sol` for more examples
- See `src/integrations/SocialLoanAdapter.sol` for helper functions
- Review `docs/ARCHITECTURE.md` for system design details
