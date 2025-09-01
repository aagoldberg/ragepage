# Revflow - On-Chain Revenue-Based Financing Protocol

A crypto-native RBF protocol that advances stablecoins to on-chain treasuries in exchange for a fixed percentage of future protocol revenue until a capped multiple is repaid.

📄 **[Read the Full Whitepaper](WHITEPAPER.md)** - Complete technical specification and economic analysis

🔗 **Quick Links**: [Contracts](src/) | [Tests](test/) | [Deploy Scripts](script/) | [Subgraph](subgraph/) | [Automation](automation/)

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Architecture](#architecture)
- [Key Features](#key-features)
- [Installation & Setup](#installation--setup)
- [Usage & Integration](#usage--integration)
- [Testing & Validation](#testing--validation)
- [Deployment](#deployment)
- [Automation](#automation)
- [Monitoring & Analytics](#monitoring--analytics)
- [Security](#security)
- [Economics & Pricing](#economics--pricing)
- [Governance](#governance)
- [Roadmap](#roadmap)
- [Contributing](#contributing)

## Overview

Revflow enables non-dilutive capital for crypto treasuries (DAOs, L2s, DeFi protocols, NFT projects) through:

- **🔒 Non-custodial**: Smart contracts enforce revenue sharing automatically
- **🤝 Trust-minimized**: No off-chain agreements or legal enforcement needed
- **🔄 Composable**: Tokenized lender claims for secondary liquidity
- **🔌 Drop-in integration**: Revenue Adapter becomes fee recipient without protocol rewrites
- **⚡ Automated**: Built-in automation for pull-based revenue sources
- **🛡️ Protected**: Multiple safety rails and governance guarantees

### Problem Statement

Traditional crypto fundraising is either:
- **Dilutive** (token sales, equity) and cyclical with market conditions
- **Over-collateralized** (DeFi lending) requiring 150%+ backing
- **Legal-dependent** (TradFi RBF) requiring off-chain enforcement

Revflow provides **non-dilutive, undercollateralized financing** matched to actual protocol performance.

## How It Works

### Simple 3-Step Process

1. **💰 Advance**: Protocol receives upfront stablecoin capital (e.g., $1M USDC)
2. **📈 Share**: Fixed percentage of future revenue (e.g., 10%) automatically flows to lenders
3. **🎯 Complete**: Stops when cap reached (e.g., 1.35× = $1.35M) or term ends

### Example Deal Flow

```
Month 0: Protocol receives $1,000,000 USDC advance
Month 1: $300k revenue → $30k to lenders (10%), $270k to treasury
Month 2: $350k revenue → $35k to lenders, $315k to treasury
Month 3: $400k revenue → $40k to lenders, $360k to treasury
Month 4: $450k revenue → $45k to lenders, $405k to treasury
...
When $1,350,000 paid to lenders → Deal complete, 100% revenue to treasury
```

## Architecture

```
[Revenue Source/Protocol]
        │ (fees/royalties/sequencer surplus)
        ▼
  (set recipient or claimer)
[RevenueAdapter] ──▶ [RevenueSplitter] ──┬──▶ [LenderVault] (RBF notes)
                                         └──▶ [Treasury Safe]
                       ▲  ▲
                       │  └── Safety Rails (caps, allowlist, pause)
                       └──── Governance & Timelock / FeeRouter
```

### Core Contracts

- **RevenueAdapter**: Drop-in fee recipient that forwards funds to splitter
- **RevenueSplitter**: Enforces revenue share, repayment cap, and safety rails
- **LenderVault**: Manages lender claims and issues receipt tokens (ERC-20)

### Optional Contracts

- **FeeRouter**: Prevents unhooking adapter until cap reached or make-whole paid
- **DefaultVault**: Collateral escrow that auto-pays lenders on early removal

## Key Features

### Revenue Splitting
- Fixed percentage (e.g., 10%) of eligible revenue goes to lenders
- Automatic stop when cap reached (e.g., 1.35× advance)
- Multiple revenue tokens supported with price oracle normalization

### Safety Rails
- Daily and per-transaction volume caps
- Token allowlist to prevent griefing
- Pause/unpause functionality
- Governance timelock on critical changes

### Lender Protection
- Tokenized claims (ERC-20 receipt tokens)
- Pro-rata distribution based on receipt token holdings
- On-demand claiming or streaming payouts
- Make-whole provisions for early termination

## Installation & Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (latest version)
- [Node.js](https://nodejs.org/) v16+ (for automation scripts)
- [Git](https://git-scm.com/)

### Quick Start

```bash
# Clone the repository
git clone https://github.com/your-org/revflow
cd revflow

# Install Solidity dependencies
forge install

# Install Node.js dependencies for automation
npm install

# Copy environment template
cp .env.example .env
# Edit .env with your configuration

# Build contracts
forge build

# Run tests
forge test

# Run with gas reporting
forge test --gas-report
```

### Verify Installation

```bash
# Check Foundry version
forge --version

# Compile contracts
forge build

# Run a specific test
forge test --match-test testBasicRevenueSplit -vv

# Check contract sizes
forge build --sizes
```

## Usage & Integration

### Protocol Integration Patterns

Revflow supports multiple integration patterns without requiring protocol rewrites:

#### Pattern 1: Push-Based (Recommended)
Protocol sets revenue adapter as fee recipient. Funds automatically flow through splitter.

```solidity
// In your protocol's governance proposal
protocol.setFeeRecipient(address(revenueAdapter));
// That's it! Revenue automatically splits from now on
```

**Supported Protocols:**
- DEXs with configurable fee recipients
- NFT royalty systems  
- L2 sequencer fee collectors
- Staking/restaking protocols with fee sinks

#### Pattern 2: Pull-Based (Automated)
Automation bots periodically claim fees and forward to splitter.

```solidity
// RevenueAdapter calls protocol's fee claiming function
adapter.claimAndForward(); // Protocol-specific implementation
```

**Supported Protocols:**
- Aave-style lending (mintToTreasury)
- Compound forks
- Custom treasury management systems

### Deploy Contracts

```bash
# Set up environment
export PRIVATE_KEY="your-deployer-private-key"
export TREASURY_ADDRESS="0x..." # Protocol treasury
export GOVERNANCE_ADDRESS="0x..." # Governance multisig

# Deploy to mainnet
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify

# Deploy to testnet for testing
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify

# Deploy locally
anvil &
forge script script/Deploy.s.sol:DeployLocal --fork-url http://localhost:8545 --broadcast
```

### Integration Examples

#### 1. Aave-style Protocol (Pull)
```solidity
// Set up upkeep to claim fees periodically
adapter.claimAndForward();  // Calls protocol's mintToTreasury()
```

#### 2. DEX with Fee Recipient (Push)
```solidity
// DAO governance proposal
protocol.setFeeRecipient(address(adapter));
// Fees automatically flow through splitter
```

#### 3. NFT Royalties (Push)
```solidity
// Set marketplace payout address
marketplace.setRoyaltyRecipient(address(adapter));
```

## Configuration

### Environment Variables

Create a `.env` file:

```bash
# Deployment
PRIVATE_KEY=0x...
MAINNET_RPC_URL=https://...
ETHERSCAN_API_KEY=...

# Contract addresses
TREASURY_ADDRESS=0x...
GOVERNANCE_ADDRESS=0x...
USDC_ADDRESS=0xA0b86a33E6417C42e8BE7CC4b06a76C8C3A3b2a0

# Deal parameters
SHARE_BPS=1000                  # 10%
CAP_MULTIPLE=135               # 1.35x
ADVANCE_AMOUNT=1000000000000   # 1M USDC (6 decimals)
DEAL_DURATION=15552000         # 180 days in seconds
DAILY_CAP=100000000000         # 100k USDC daily cap
TRANSACTION_CAP=10000000000    # 10k USDC per transaction cap

# Optional features
DEPLOY_FEE_ROUTER=true
DEPLOY_DEFAULT_VAULT=true
MAKE_WHOLE_AMOUNT=50000000000  # 50k USDC
CURE_PERIOD_DURATION=604800    # 7 days
NO_PAYMENT_THRESHOLD=1209600   # 14 days
```

## Testing & Validation

### Comprehensive Test Suite

Our test suite covers all critical functionality and edge cases:

```bash
# Run all tests with gas reporting
forge test --gas-report

# Run specific test categories
forge test --match-path "test/*Splitter*" -v  # Revenue splitting tests
forge test --match-path "test/*Vault*" -v     # Lender vault tests  
forge test --match-path "test/*Adapter*" -v   # Revenue adapter tests

# Run with extreme verbosity (shows all logs)
forge test -vvvv

# Generate coverage report
forge coverage

# Run fuzz testing (built into Foundry tests)
forge test --ffi # Enables foreign function interface for advanced testing
```

### Test Categories

#### 1. Core Functionality Tests
- ✅ Revenue splitting with correct percentages
- ✅ Cap enforcement (stops at 1.35× exactly)  
- ✅ Multi-token support (USDC, WETH, etc.)
- ✅ ETH handling via receive() functions
- ✅ Pro-rata claim distribution

#### 2. Safety & Security Tests  
- ✅ Daily and transaction cap enforcement
- ✅ Token allowlist protection
- ✅ Pause/unpause functionality
- ✅ Reentrancy protection
- ✅ Zero amount handling
- ✅ Integer overflow/underflow protection

#### 3. Integration Tests
- ✅ Adapter → Splitter → Vault flow
- ✅ Batch token sweeping
- ✅ Timelock governance changes
- ✅ Fee router hard guarantees
- ✅ Default vault collateral handling

#### 4. Edge Case Tests
- ✅ Cap reached mid-transaction
- ✅ Deal expiration handling
- ✅ Splitter paused during revenue
- ✅ Very small and very large amounts
- ✅ Rapid successive transactions

### Gas Usage Analysis

```bash
# Generate detailed gas report
forge test --gas-report > gas-report.txt

# Typical gas costs:
# - Revenue split: ~45,000 gas
# - Claim rewards: ~35,000 gas  
# - Batch sweep: ~65,000 gas + 25k per token
```

### Load Testing

```bash
# Run stress tests with high transaction volumes
forge test --match-test testHighVolumeRevenue -vv

# Test with maximum number of lenders (gas limit testing)
forge test --match-test testManyLendersScenario -vv
```

### Integration Testing

Test against forked mainnet with real protocols:

```bash
# Fork Ethereum mainnet for realistic testing
forge test --fork-url $MAINNET_RPC_URL --match-test testMainnetFork -vvv

# Test with real USDC contract
forge test --fork-url $MAINNET_RPC_URL --match-test testRealUSDC -vvv
```

## Automation

### OpenZeppelin Defender

Deploy the autotask in `automation/defender-autotask.js`:

```bash
npm install @openzeppelin/defender-autotask-client
# Upload to Defender and configure environment variables
```

### Gelato Network

Deploy the Web3 Function in `automation/gelato-task.js`:

```bash
npx @gelatonetwork/web3-functions-sdk deploy gelato-task.js
```

## Subgraph

Deploy the subgraph for real-time data:

```bash
cd subgraph
npm install
npx graph codegen
npx graph build
npx graph deploy your-username/revflow-mainnet
```

## Example Queries

### GraphQL Queries

```graphql
# Get deal information
query GetDeal($id: ID!) {
  deal(id: $id) {
    id
    shareBps
    repaymentCap
    totalPaid
    isCapReached
    splits(first: 10, orderBy: timestamp, orderDirection: desc) {
      timestamp
      toLenders
      toTreasury
      token
    }
  }
}

# Get lender positions
query GetLender($address: Bytes!) {
  lender(id: $address) {
    receiptTokenBalance
    totalClaimed
    claims(first: 10, orderBy: timestamp, orderDirection: desc) {
      amount
      token
      timestamp
    }
  }
}
```

### Contract Interactions

```solidity
// Check claimable amount
uint256 claimable = lenderVault.getClaimableAmount(lender, address(usdc));

// Claim rewards
lenderVault.claim(address(usdc));

// Check deal status
bool capReached = splitter.isCapReached();
uint256 remainingCap = splitter.getRemainingCap();
```

## Security

### Audit Status
- [ ] Internal review
- [ ] External audit #1 
- [ ] External audit #2
- [ ] Bug bounty program

### Known Risks
- **Revenue volatility**: Slower payback if protocol revenue drops
- **Governance risk**: DAO could attempt to unhook adapter (mitigated by FeeRouter)
- **Smart contract risk**: Bugs in splitting logic or cap enforcement
- **Oracle risk**: Price manipulation if using USD normalization

## Governance

### Proposal Templates

See `GOVERNANCE_PROPOSALS.md` for DAO proposal templates covering:
- Option A: Autoroute (strongest guarantees)
- Option B: Escrow-first (reversible)
- Option C: Manual + penalty (lowest friction)

### Parameter Guidelines
- **Share**: 5-12% based on revenue volatility
- **Cap Multiple**: 1.20-1.50× based on risk/tenor
- **Daily Caps**: 10-30% of average daily revenue
- **Timelock**: 72-168 hours for routing changes

## Economics

### Pricing Formula

For a given advance `A`, share `s`, and cap multiple `M`:

```
Expected time to repay = (M × A) / (s × μ)
```

Where `μ` is expected monthly revenue.

### Example Deal
- **Advance**: $1,000,000 USDC
- **Share**: 10% of eligible revenue  
- **Cap**: $1,350,000 (1.35× multiple)
- **Expected monthly revenue**: $350,000
- **Expected payback time**: ~3.9 months
- **Lender IRR**: ~27% annualized

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Disclaimer

This software is experimental and unaudited. Use at your own risk. Not intended as investment advice.
