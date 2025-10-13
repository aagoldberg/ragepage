# zkAPI Architecture & Implementation Decisions

**Last Updated**: October 2025
**Status**: Phase 1 Complete (Smart Contracts) | Phase 2 In Progress (zkTLS Integration)

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture Decisions](#architecture-decisions)
3. [Phase 1: Smart Contracts (Complete)](#phase-1-smart-contracts-complete)
4. [Phase 2: zkTLS Integration (Current)](#phase-2-zktls-integration-current)
5. [Phase 3: Operator Network](#phase-3-operator-network)
6. [Phase 4: Production Deployment](#phase-4-production-deployment)
7. [Technology Stack](#technology-stack)
8. [Trade-offs & Alternatives](#trade-offs--alternatives)

---

## Overview

zkAPI is a **decentralized oracle network** for privacy-preserving cashflow verification. It enables merchants to prove their revenue from platforms like Shopify, Square, and Plaid **without revealing individual transactions or customer data**.

### Core Innovation

We combine three technologies:
1. **zkTLS** (Reclaim Protocol) - Prove API data authenticity
2. **EigenLayer AVS** - Decentralized operator validation
3. **Zero-Knowledge Proofs** - Selective disclosure of financial data

---

## Architecture Decisions

### Decision 1: zkTLS Provider

**Options Evaluated:**
- ✅ **Reclaim Protocol** (CHOSEN)
- TLSNotary (MPC-based)
- zkPass
- Custom zkTLS implementation

**Why Reclaim Protocol?**

| Criteria | Reclaim | TLSNotary | zkPass | Custom |
|----------|---------|-----------|--------|--------|
| **Ease of Integration** | ✅ Best | ⚠️ Medium | ⚠️ Medium | ❌ Hard |
| **Platform Coverage** | ✅ 2500+ | ⚠️ Limited | ⚠️ Limited | ❌ 0 |
| **Performance** | ✅ Fast (gnark) | ⚠️ Slower (MPC) | ✅ Fast | ❓ Unknown |
| **SDK Quality** | ✅ Excellent | ⚠️ Basic | ⚠️ Basic | ❌ None |
| **On-chain Verification** | ✅ Native | ✅ Yes | ✅ Yes | ❌ Build from scratch |
| **Production Ready** | ✅ Yes | ⚠️ Beta | ⚠️ Beta | ❌ No |
| **Cost** | ✅ Free/Open | ✅ Free | ❓ Unknown | 💰💰💰 |

**Decision**: Reclaim Protocol
- Best SDK ecosystem (React, RN, iOS, Android, Flutter)
- Already supports Shopify/Square/Plaid
- Proven on EigenLayer AVS
- Active development & support

**Implementation**:
```typescript
// @reclaimprotocol/js-sdk
import { ReclaimClient } from '@reclaimprotocol/reclaim-sdk';
```

---

### Decision 2: Proof Verification Architecture

**Options Evaluated:**
- ✅ **On-chain verification via operators** (CHOSEN)
- Direct on-chain verification (every merchant)
- Off-chain verification with fraud proofs
- Centralized verification service

**Why Operator-Based Verification?**

**CHOSEN**: On-chain verification via operators

**Pros:**
- ✅ Gas efficient (operators aggregate proofs)
- ✅ Decentralized (15+ independent operators)
- ✅ Slashable stake ($15M+ security)
- ✅ Scalable (batch verification)

**Cons:**
- ⚠️ Latency (consensus takes ~1 min)
- ⚠️ Complexity (operator network required)

**Alternatives Considered:**

**Direct On-Chain** (Every merchant verifies own proof)
- ✅ Instant verification
- ❌ High gas costs (~$50 per proof at 50 gwei)
- ❌ Not scalable

**Off-Chain with Fraud Proofs**
- ✅ Very low cost
- ❌ Optimistic delays (7 days)
- ❌ Complex dispute resolution

**Centralized Service**
- ✅ Fast & cheap
- ❌ Single point of failure
- ❌ Not trustless

**Decision Rationale**:
Operator-based strikes best balance between cost, security, and decentralization. The ~1 minute latency is acceptable for loan underwriting (not DeFi trading).

---

### Decision 3: Operator Consensus Mechanism

**Options Evaluated:**
- ✅ **BLS Signature Aggregation** (CHOSEN)
- Multi-sig (ECDSA)
- Threshold signatures (TSS)
- Optimistic verification

**Why BLS Signatures?**

| Criteria | BLS | ECDSA Multi-sig | TSS | Optimistic |
|----------|-----|-----------------|-----|------------|
| **Signature Size** | ✅ Constant (96 bytes) | ❌ Linear (65 * N) | ✅ Constant | ✅ None |
| **Verification Cost** | ✅ O(1) gas | ❌ O(N) gas | ✅ O(1) gas | ✅ O(1) gas |
| **Setup Complexity** | ✅ Simple | ✅ Simple | ⚠️ Complex | ✅ Simple |
| **EigenLayer Native** | ✅ Yes | ❌ No | ❌ No | ❌ No |
| **Aggregation** | ✅ Native | ❌ Not possible | ✅ Via protocol | ❌ N/A |

**Decision**: BLS12-381 Signature Aggregation
- Used by EigenLayer natively
- Constant-size proofs regardless of operator count
- O(1) gas verification cost
- Industry standard (Ethereum 2.0, Dfinity, Chia)

**Implementation**:
```typescript
// @noble/curves BLS12-381
import { bls12_381 } from '@noble/curves/bls12-381';

// Aggregate N signatures into one
const aggregated = bls12_381.aggregateSignatures(signatures);
```

---

### Decision 4: Programming Language for Operator Nodes

**Options Evaluated:**
- ✅ **TypeScript** (CHOSEN for MVP)
- Rust
- Go
- Python

**Why TypeScript (initially)?**

| Criteria | TypeScript | Rust | Go | Python |
|----------|-----------|------|-----|---------|
| **Development Speed** | ✅ Fastest | ⚠️ Slower | ✅ Fast | ✅ Fast |
| **SDK Compatibility** | ✅ Native | ⚠️ Bindings needed | ⚠️ Bindings needed | ✅ Native |
| **Performance** | ⚠️ Good enough | ✅ Excellent | ✅ Excellent | ❌ Poor |
| **Hiring Pool** | ✅ Large | ⚠️ Medium | ✅ Large | ✅ Large |
| **Type Safety** | ✅ Excellent | ✅ Excellent | ⚠️ Good | ❌ Poor |

**Decision**: Start with TypeScript, migrate to Rust later

**Phase 2 (MVP)**: TypeScript
- Faster development
- Native Reclaim SDK support
- Easier to iterate
- Good enough performance for 10-20 operators

**Phase 3 (Production)**: Consider Rust
- 10x better performance
- Lower infrastructure costs
- Better for 100+ operator network
- MEV resistance (if needed)

**Implementation Path**:
```
Week 1-4: TypeScript MVP
Week 5-8: Optimize critical paths
Week 9+: Evaluate Rust migration
```

---

### Decision 5: API Priority Order

**Options:**
- ✅ **Shopify first** (CHOSEN)
- Square first
- Plaid first
- All three simultaneously

**Why Shopify First?**

| Criteria | Shopify | Square | Plaid |
|----------|---------|--------|-------|
| **OAuth Complexity** | ✅ Simple | ⚠️ Medium | ❌ Complex |
| **Revenue Data Structure** | ✅ Clear | ✅ Clear | ⚠️ Transactions only |
| **Use Case Fit** | ✅ Perfect (e-commerce) | ✅ Good (retail) | ⚠️ Indirect |
| **API Documentation** | ✅ Excellent | ✅ Good | ⚠️ Complex |
| **Rate Limits** | ✅ Generous | ✅ Generous | ⚠️ Strict |
| **Reclaim Support** | ✅ Ready | ✅ Ready | ✅ Ready |

**Decision**: Shopify → Square → Plaid

**Reasoning**:
1. **Shopify** (Week 2-3)
   - Cleanest OAuth flow
   - Direct revenue metrics
   - Large merchant base
   - Perfect for e-commerce loans

2. **Square** (Week 4-5)
   - Similar to Shopify
   - Adds retail/POS coverage
   - Broad merchant adoption

3. **Plaid** (Week 6-7)
   - Most complex (bank aggregator)
   - Requires transaction aggregation
   - More comprehensive financial view
   - Adds traditional businesses

---

### Decision 6: Merchant Client Architecture

**Options Evaluated:**
- ✅ **CLI Tool + Web SDK** (CHOSEN)
- Browser Extension
- Mobile App
- Desktop App

**Why CLI + Web SDK?**

**Phase 2 (MVP)**: CLI Tool
```bash
zkapi generate-proof --provider shopify --period 90d
```

**Pros:**
- ✅ Fastest to build
- ✅ Developer-friendly
- ✅ Easy to test/debug
- ✅ Works everywhere (Mac/Linux/Windows)

**Cons:**
- ❌ Not user-friendly for non-technical merchants

**Phase 3**: Web SDK
```typescript
import { ZkApiClient } from '@zkapi/client-sdk';

const client = new ZkApiClient();
const proof = await client.generateProof({
  provider: 'shopify',
  period: '90d'
});
```

**Pros:**
- ✅ Better UX
- ✅ Integrates with your dApp
- ✅ Browser-based (no install)

**Phase 4**: Optional Browser Extension
- For power users
- Automatic proof generation
- Background attestation renewal

**Decision Rationale**:
Iterate from simple (CLI) to complex (browser extension) based on user feedback.

---

### Decision 7: Data Freshness & Attestation Validity

**Options Evaluated:**
- ✅ **7-day default, configurable** (CHOSEN)
- Real-time (on-demand)
- Monthly snapshots
- Perpetual (cached)

**Why 7-Day Default?**

**CHOSEN**: 7-day default validity
- Proof generated: Day 0
- Valid until: Day 7
- After Day 7: Merchant must regenerate

**Pros:**
- ✅ Balances freshness & cost
- ✅ Merchants don't generate proof daily
- ✅ Lenders get recent data
- ✅ Prevents stale data attacks

**Configurable by Protocol:**
```solidity
// Your loan protocol can require fresher data
adapter.checkLoanEligibilityWithParams(
    borrower,
    amount,
    UnderwritingParams({
        minRevenueMultiple: 3,
        maxDataAge: 2 days,  // Require 2-day fresh data
        minCreditScore: 600,
        minGrowthBps: 0
    })
);
```

**Alternatives Considered:**

**Real-time (on-demand)**
- ✅ Always fresh
- ❌ High cost (proof per query)
- ❌ Poor UX (merchants must approve each time)

**Monthly snapshots**
- ✅ Very cheap
- ❌ Too stale for lending
- ❌ Exploit window

**Perpetual caching**
- ✅ Cheapest
- ❌ Dangerous (outdated data)
- ❌ No fraud protection

---

### Decision 8: Gas Optimization Strategy

**Options Evaluated:**
- ✅ **Operator aggregation + batch submission** (CHOSEN)
- Per-merchant on-chain verification
- L2 deployment only
- Optimistic rollup pattern

**Why Operator Aggregation?**

**CHOSEN Approach**:
1. Operators verify proofs off-chain
2. Aggregate BLS signatures (constant size)
3. Submit batches every 1 hour or 100 proofs
4. Single transaction for all proofs in batch

**Gas Costs**:
```
Traditional (per-merchant verification):
- Proof verification: ~500k gas (~$50 at 50 gwei, $4k ETH)
- Per merchant: $50

zkAPI (operator aggregation):
- Batch submission: ~200k gas + (10k * N proofs)
- Per merchant (100 batch): $2.50
- Per merchant (10 batch): $8

Savings: 95% at scale
```

**Implementation**:
```solidity
// Operators submit batches
function submitAttestationBatch(
    CashflowAttestation[] memory attestations,
    bytes calldata aggregateSignature
) external {
    // Verify once for entire batch
    require(verifyBatchSignature(attestations, aggregateSignature));

    for (uint i = 0; i < attestations.length; i++) {
        _storeAttestation(attestations[i]);
    }
}
```

**Future Optimization** (Phase 4):
- Deploy to Arbitrum/Base (10x cheaper)
- Merkle tree batching (100x cheaper)
- ZK proof aggregation (1000x cheaper)

---

## Phase 1: Smart Contracts (Complete ✅)

### What's Built

**Core Contracts:**
- `CashflowOracleAVS.sol` - Main AVS logic
- `OperatorRegistry.sol` - Staking & slashing
- `ZKProofVerifier.sol` - Proof verification
- `SocialLoanAdapter.sol` - Integration helper

**Testing:**
- ✅ 9/9 tests passing
- ✅ Integration examples
- ✅ Gas benchmarks

**Documentation:**
- ✅ README.md
- ✅ INTEGRATION.md
- ✅ Inline code comments

### Technology Stack

**Smart Contracts:**
- Solidity 0.8.20
- Foundry (testing & deployment)
- OpenZeppelin (base contracts)

**Why Foundry?**
- ✅ Fastest Solidity testing
- ✅ Better debugging (Rust)
- ✅ Native fuzzing
- ✅ Gas profiling
- vs Hardhat (slower, JS-based)

---

## Phase 2: zkTLS Integration (Current 🚧)

### Week 1-2: Reclaim Protocol Integration

**Tasks:**
1. ✅ Research Reclaim SDK options
2. 🚧 Install & configure SDK
3. 🚧 Test proof generation locally
4. 🚧 Update `ZKProofVerifier.sol`

**Technology Stack:**

**SDK Choice**: `@reclaimprotocol/js-sdk`
```json
{
  "dependencies": {
    "@reclaimprotocol/js-sdk": "^latest",
    "@noble/curves": "^1.0.0"
  }
}
```

**Why JS SDK (not Rust/Python)?**
- Native TypeScript support
- Best documentation
- Active development
- Easiest integration with operator nodes

**Proof Structure** (Reclaim):
```typescript
interface ReclaimProof {
  identifier: string;        // Unique proof ID
  claimData: {
    provider: string;         // "shopify"
    parameters: string;       // JSON params
    context: string;          // "revenue:90d"
  };
  signatures: string[];       // Witness signatures
  witnesses: {
    id: string;
    url: string;
  }[];
  extractedParameters: {
    totalRevenue: string;
    periodStart: string;
    periodEnd: string;
  };
  publicData: string;         // zkSNARK public inputs
  proof: string;              // zkSNARK proof
}
```

**On-Chain Verification**:
```solidity
// Update ZKProofVerifier.sol
function verifyReclaimProof(
    bytes calldata proofBytes
) external returns (bool) {
    ReclaimProof memory proof = abi.decode(proofBytes, (ReclaimProof));

    // 1. Verify witness signatures
    require(verifyWitnessSignatures(proof.signatures, proof.witnesses));

    // 2. Verify zkSNARK proof
    require(verifyZkSnark(proof.proof, proof.publicData));

    // 3. Check proof is recent
    require(block.timestamp - proof.claimData.timestamp < MAX_PROOF_AGE);

    return true;
}
```

**Deliverables**:
- Updated `ZKProofVerifier.sol` with Reclaim support
- CLI tool: `zkapi verify-proof <proof.json>`
- Integration tests with real proof format
- Documentation: `docs/PROOF_FORMAT.md`

---

### Week 3-4: Shopify Integration

**Tasks:**
1. 🚧 OAuth 2.0 flow implementation
2. 🚧 Shopify Admin API integration
3. 🚧 Revenue data extraction
4. 🚧 Selective disclosure (hide transactions)
5. 🚧 CLI proof generation tool

**Shopify API Endpoint**:
```typescript
// Get orders for revenue calculation
GET /admin/api/2024-10/orders.json
  ?status=any
  &financial_status=paid
  &created_at_min=2024-07-01
  &created_at_max=2024-09-30
  &fields=total_price,currency,created_at
```

**OAuth Flow**:
```
1. Merchant clicks "Connect Shopify"
2. Redirect to Shopify OAuth
3. User approves app permissions
4. Receive access token
5. Make API call with token
6. Generate zkTLS proof of response
7. Extract revenue (hide individual orders)
```

**Selective Disclosure**:
```typescript
// Prove: "Total revenue = $50,000"
// Hide: Individual orders, customer emails, addresses

const proof = await reclaimClient.generateProof({
  provider: 'shopify-orders',
  apiUrl: 'https://mystore.myshopify.com/admin/api/2024-10/orders.json',
  accessToken: shopifyToken,
  revealFields: ['totalRevenue', 'currency', 'periodStart', 'periodEnd'],
  hideFields: ['orders[].customer', 'orders[].line_items']
});
```

**CLI Tool**:
```bash
# Interactive OAuth flow
zkapi connect shopify

# Generate proof
zkapi generate-proof \
  --provider shopify \
  --period 90d \
  --output proof.json

# Submit to operator network
zkapi submit-proof proof.json

# Check attestation status
zkapi status 0x1234...
```

**Deliverables**:
- `packages/shopify-adapter/` (TypeScript)
- CLI tool with Shopify support
- OAuth flow documentation
- Example proof files
- Integration tests

---

### Week 5-6: Square & Plaid Integration

**Square** (Week 5):
- OAuth 2.0 flow (similar to Shopify)
- Payments API integration
- POS + online transactions
- Revenue aggregation

**Plaid** (Week 6):
- Link token flow
- Transactions API
- Bank account verification
- Transaction aggregation → revenue

**Deliverables**:
- `packages/square-adapter/`
- `packages/plaid-adapter/`
- Updated CLI with all three providers
- Comparison docs (which provider for what use case)

---

## Phase 3: Operator Network

### Week 7-8: Operator Node Implementation

**Architecture**:
```
┌─────────────────────────────────────────┐
│         Operator Node (TypeScript)       │
├─────────────────────────────────────────┤
│  1. REST API (receive proofs)            │
│  2. Proof Verification Engine            │
│  3. BLS Signature Generation             │
│  4. Attestation Submission               │
│  5. Health Monitoring                    │
└─────────────────────────────────────────┘
```

**Technology Stack**:

**Framework**: Express.js + TypeScript
```json
{
  "dependencies": {
    "express": "^4.18.0",
    "ethers": "^6.0.0",
    "@noble/curves": "^1.0.0",
    "@reclaimprotocol/js-sdk": "^latest",
    "bull": "^4.0.0"  // Job queue
  }
}
```

**Why Express (not Fastify/Nest)?**
- ✅ Battle-tested
- ✅ Large ecosystem
- ✅ Easy to deploy
- ✅ Good enough performance

**Components**:

**1. Proof Reception**:
```typescript
app.post('/api/v1/submit-proof', async (req, res) => {
  const { proof, merchantAddress } = req.body;

  // Add to verification queue
  await verificationQueue.add({
    proof,
    merchant: merchantAddress,
    receivedAt: Date.now()
  });

  res.json({ status: 'queued', id: job.id });
});
```

**2. Verification Engine**:
```typescript
verificationQueue.process(async (job) => {
  const { proof } = job.data;

  // Verify zkTLS proof
  const isValid = await reclaimClient.verifyProof(proof);

  if (isValid) {
    // Sign with BLS
    const signature = blsSign(proof);

    // Submit to coordination service
    await submitToCoordinator(proof, signature);
  }
});
```

**3. Coordination Service**:
```typescript
// Operators submit signatures here
// Coordinator aggregates when quorum reached (67%)
// Submits to blockchain

class AttestationCoordinator {
  async receiveSignature(proofHash, operatorId, signature) {
    this.signatures[proofHash].push({ operatorId, signature });

    if (this.hasQuorum(proofHash)) {
      const aggregated = bls12_381.aggregateSignatures(
        this.signatures[proofHash]
      );

      await this.submitToBlockchain(proofHash, aggregated);
    }
  }
}
```

**Deliverables**:
- `packages/operator-node/` (TypeScript)
- Docker image
- Deployment guide (AWS/GCP/DO)
- Monitoring dashboard
- Operator docs

---

### Week 9-10: Testnet Deployment

**Networks**:
1. **Sepolia** (Ethereum testnet)
2. **Arbitrum Sepolia** (L2 testnet)

**Deployment Steps**:
1. Deploy contracts to Sepolia
2. Run 5 operator nodes
3. Generate test proofs
4. Verify full flow works
5. Load testing (100 proofs/hour)

**Testing Checklist**:
- [ ] Merchant can generate proof
- [ ] Operators verify proof
- [ ] Signatures aggregated correctly
- [ ] On-chain verification succeeds
- [ ] Gas costs acceptable
- [ ] Latency < 2 minutes
- [ ] Works with your social loan protocol

---

## Phase 4: Production Deployment

### Mainnet Launch (Week 11-12)

**Pre-Launch Checklist**:
- [ ] Security audit (Trail of Bits / OpenZeppelin)
- [ ] Economic model finalized
- [ ] 15+ operators committed
- [ ] Insurance fund seeded
- [ ] Documentation complete
- [ ] Legal review (if needed)

**Go-Live**:
1. Deploy to Ethereum mainnet
2. Integrate with EigenLayer AVS registry
3. Operators stake ETH
4. Announce launch
5. Onboard first merchants
6. Monitor closely

**Post-Launch** (Month 2-3):
- Add Square/Plaid support
- Deploy to Arbitrum (cheaper gas)
- Recruit more operators (target: 30+)
- Launch governance DAO
- Add advanced features

---

## Technology Stack Summary

### Smart Contracts
- **Language**: Solidity 0.8.20
- **Framework**: Foundry
- **Libraries**: OpenZeppelin
- **Testing**: Forge
- **Deployment**: Forge scripts

### Operator Nodes
- **Language**: TypeScript (Node.js 20+)
- **Framework**: Express.js
- **Queue**: Bull (Redis)
- **Blockchain**: ethers.js v6
- **Crypto**: @noble/curves (BLS)
- **zkTLS**: @reclaimprotocol/js-sdk

### Client SDK
- **Language**: TypeScript
- **Target**: Browser + Node.js
- **Build**: tsup
- **Package Manager**: npm

### Infrastructure
- **Hosting**: AWS / GCP / DigitalOcean
- **Database**: PostgreSQL (attestation logs)
- **Cache**: Redis (job queue)
- **Monitoring**: Grafana + Prometheus
- **Logs**: Winston → CloudWatch

---

## Trade-offs & Alternatives

### Major Trade-offs Made

**1. Latency vs Cost**
- **Choice**: 1-2 minute latency for 95% cost savings
- **Alternative**: Real-time verification (50x more expensive)
- **Rationale**: Lending decisions can wait 2 minutes

**2. Decentralization vs Simplicity**
- **Choice**: 15+ operators (decentralized)
- **Alternative**: Single oracle (simpler)
- **Rationale**: Trust is critical for financial data

**3. TypeScript vs Rust**
- **Choice**: TypeScript initially
- **Alternative**: Rust from day 1
- **Rationale**: Faster iteration, good enough performance

**4. zkTLS Provider**
- **Choice**: Reclaim Protocol
- **Alternative**: Custom zkTLS implementation
- **Rationale**: Don't reinvent the wheel, focus on product

---

## Open Questions / Future Decisions

**1. Token Economics**
- Native token or use existing (EIGEN, LINK)?
- Staking rewards structure?
- Fee distribution model?

**2. Cross-Chain Strategy**
- Ethereum only or multi-chain?
- Which L2s to support?
- Bridge architecture?

**3. Privacy Enhancements**
- Fully homomorphic encryption?
- Multi-party computation for aggregation?
- Differential privacy for analytics?

**4. Governance**
- DAO from day 1 or wait?
- What parameters should be governable?
- Token holder vs operator voting?

---

## Contributing

Have suggestions on architecture decisions? Open an issue or PR:
- Technical discussions: GitHub Issues
- Architecture proposals: Create RFC in `docs/rfcs/`
- Implementation feedback: PR comments

---

## References

**Research Papers**:
- Reclaim Protocol Whitepaper
- EigenLayer Whitepaper
- TLS 1.3 RFC 8446

**Prior Art**:
- Chainlink (oracle networks)
- API3 (first-party oracles)
- RedStone (push oracles)
- TLSNotary (zkTLS implementation)

**Libraries Used**:
- @reclaimprotocol/js-sdk
- @noble/curves
- ethers.js
- OpenZeppelin Contracts

---

**Last Updated**: October 2025
**Maintained by**: zkAPI Core Team
**Questions**: Open an issue on GitHub
