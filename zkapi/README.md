# zkAPI: Decentralized Cashflow Oracle for Social Lending

**Zero-knowledge API connector for decentralized crowdsourcing of cashflow data**

Built on EigenLayer AVS with zkTLS proofs from Shopify, Square, Plaid, and more.

---

## Overview

zkAPI is a decentralized oracle network that verifies merchant cashflow data using zero-knowledge proofs. It enables:

✅ **Privacy-preserving revenue verification** - Prove revenue without revealing transactions
✅ **Decentralized validation** - Operator network secured by restaked ETH
✅ **Trustless integration** - Smart contracts query verified data on-chain
✅ **Multi-source support** - Shopify, Square, Plaid, and more

Perfect for: Revenue-based financing, social lending, credit scoring, merchant cash advances.

---

## Architecture

```
Merchant (Shopify/Square/Plaid)
    ↓ OAuth + zkTLS proof
Operator Network (EigenLayer AVS)
    ↓ BLS aggregate signature
Smart Contract (On-chain)
    ↓ Query verified data
Your Social Loan Protocol
```

**Key Components:**
1. **CashflowOracleAVS** - Core oracle contract
2. **OperatorRegistry** - Operator staking and slashing
3. **ZKProofVerifier** - zkTLS proof verification
4. **SocialLoanAdapter** - Easy integration for loan protocols

---

## Quick Start

### Installation

```bash
# Clone and install
git clone https://github.com/yourusername/zkapi
cd zkapi
forge install
```

### Deploy Contracts

```bash
# Build contracts
forge build

# Set your private key
export PRIVATE_KEY=0x...

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast

# Addresses saved to deployments/latest.json
```

### Integrate into Your Protocol

```solidity
import "zkapi/src/interfaces/ICashflowOracle.sol";

contract YourLoanProtocol {
    ICashflowOracle public cashflowOracle;

    constructor(address _oracle) {
        cashflowOracle = ICashflowOracle(_oracle);
    }

    function requestLoan(uint256 amount) external {
        // Get verified revenue
        (uint256 revenue, uint64 verifiedAt,) =
            cashflowOracle.getVerifiedRevenue(
                msg.sender,
                block.timestamp - 90 days,
                block.timestamp
            );

        // Require 3x revenue coverage
        require(revenue >= amount * 3, "Insufficient revenue");

        // Your social underwriting logic...

        // Approve loan
        _issueLoan(msg.sender, amount);
    }
}
```

---

## For Your Social Loan Protocol

### You Focus On:
- Social graph verification
- Endorsement systems
- Reputation scoring
- Community governance
- Default handling

### We Provide:
- Verified cashflow data
- Credit scoring
- Revenue trend analysis
- Data freshness checks
- Risk metrics

### Integration Example:

```solidity
import "zkapi/src/integrations/SocialLoanAdapter.sol";

contract SocialLoan is SocialLoanAdapter {
    constructor(address _oracle) SocialLoanAdapter(_oracle) {}

    function approveLoan(address borrower, uint256 amount)
        external
        returns (bool)
    {
        // ✅ Cashflow check (from zkAPI)
        (bool cashflowOk,) = checkLoanEligibility(borrower, amount);

        // ✅ Social check (your logic)
        bool socialOk = checkEndorsements(borrower);

        return cashflowOk && socialOk;
    }
}
```

---

## Project Structure

```
zkapi/
├── src/
│   ├── core/
│   │   ├── CashflowOracleAVS.sol      # Main AVS contract
│   │   ├── OperatorRegistry.sol        # Operator staking
│   │   └── ZKProofVerifier.sol         # zkTLS verification
│   ├── interfaces/
│   │   ├── ICashflowOracle.sol         # ⭐ Use this in your protocol
│   │   └── ...
│   ├── integrations/
│   │   └── SocialLoanAdapter.sol       # Helper for loan protocols
│   └── libraries/
├── test/
│   ├── CashflowOracleAVS.t.sol
│   └── integration/
│       └── SocialLoanIntegration.t.sol # ⭐ See example here
├── script/
│   └── Deploy.s.sol
└── docs/
    └── INTEGRATION.md                  # ⭐ Start here
```

---

## Documentation

- **[Integration Guide](docs/INTEGRATION.md)** - How to use in your protocol
- **[API Reference](src/interfaces/ICashflowOracle.sol)** - Complete function reference
- **[Examples](test/integration/)** - Working integration examples

---

## Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testLoanApprovalFlow

# Run integration tests
forge test --match-path test/integration/*
```

---

## Economics

### Merchant Costs
- **Attestation fee**: $5-20 per proof
- **Frequency**: On-demand (e.g., when applying for loan)

### Operator Revenue
- **Fee share**: 70% of attestation fees
- **Requirements**: 32 ETH minimum stake
- **Returns**: ~5-15% APY (fee + slashing rewards)

### Protocol Revenue
- **Treasury**: 20% of fees
- **Insurance fund**: 10% of fees

---

## Development Roadmap

### ✅ Phase 1: Core Protocol (Current)
- [x] Smart contract architecture
- [x] Operator staking/slashing
- [x] Basic zkTLS verification
- [x] Integration adapter
- [x] Test suite

### 🚧 Phase 2: zkTLS Integration (Next 2-3 weeks)
- [ ] Reclaim Protocol integration
- [ ] Shopify API support
- [ ] Square API support
- [ ] Client SDK for merchants
- [ ] Testnet deployment

### 📋 Phase 3: Decentralization (Weeks 4-6)
- [ ] EigenLayer mainnet integration
- [ ] 15+ operator network
- [ ] Full slashing implementation
- [ ] Governance DAO
- [ ] Insurance fund

### 🔮 Phase 4: Scale
- [ ] Plaid integration
- [ ] Stripe, PayPal, QuickBooks
- [ ] Cross-chain deployment
- [ ] Advanced analytics
- [ ] Enterprise features

---

## License

MIT License - see [LICENSE](LICENSE)

---

**Ready to integrate cashflow verification into your social loan protocol?**

👉 Start with [docs/INTEGRATION.md](docs/INTEGRATION.md)

👉 See examples in [test/integration/](test/integration/)

👉 Deploy with `forge script script/Deploy.s.sol`
