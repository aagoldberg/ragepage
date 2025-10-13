# A Non-Dilutive, On-Chain Revenue-Based Financing Protocol for Crypto Project Treasuries

**White paper — v0.9 (2025-09-01)**

## Abstract

We propose a crypto-native revenue-based financing (RBF) protocol that advances stablecoins to on-chain treasuries (DAOs, L2s, DeFi apps, NFT programs) in exchange for a fixed percentage of future protocol revenue until a capped multiple is repaid. The system is non-custodial, trust-minimized, and integrates with existing protocols without invasive rewrites via a Revenue Adapter that becomes the fee recipient or fee claimer and autohooks into a Revenue Splitter enforcing (i) revenue share, (ii) repayment cap, and (iii) safety rails. Lender claims are tokenized for secondary liquidity. Governance guarantees (timelock, make-whole, default vault) protect lenders even if a protocol attempts to unhook the adapter. We detail architecture, economics, risk, legal posture, and deployment patterns (Aave-style, DEX, NFT royalties, L2 sequencers, etc.), plus formulas to price deals and size repayment horizons.

---

## 1. Motivation & Problem

Crypto treasuries are large, volatile, and increasingly revenue-generating (fees, royalties, sequencer surplus, staking spreads). Traditional fundraising (token sales, equity) is dilutive and cyclical; undercollateralized loans require off-chain covenants and legal enforcement. An on-chain RBF primitive provides:
- **Non-dilutive capital** with cash flows matched to actual performance.
- **Automatic, transparent repayment** enforced by code, not reminders.
- **Composability with DeFi** (tokenized lender claims, streaming, insurance).
- **Governance-friendly reversibility** (sunset/cap, make-whole to early exit).

---

## 2. High-Level Design

**Advance**: protocol receives A USDC upfront.  
**Repayment**: a fixed share s (bps) of future eligible revenue is routed to lenders until M × A has been repaid (cap multiple M, e.g., 1.25–1.50×).  
**Stop**: upon hitting the cap or term end, revenue reverts 100% to the treasury.

### Key modules
1. **RevenueAdapter** (drop-in integration): fee recipient/claimer → forwards funds to Splitter.
2. **RevenueSplitter**: enforces share%, repaymentCap = M×A, safety rails; pays LenderVault and Treasury.
3. **LenderVault**: holds and accounts lender entitlements; issues liquid receipt tokens (ERC-20 "RBF-notes" or ERC-721 positions).
4. **FeeRouter** (optional, strong guarantees): non-upgradeable router that only allows changing the recipient after cap/term or make-whole payment.
5. **DefaultVault** (optional): collateral escrow that auto-pays lenders if integration is removed early or payments lapse.
6. **Governance & Timelock**: DAO controlled; changes to fee routing pass through notice periods.
7. **Automation**: Gelato/Chainlink/Defender upkeeps for "pull" integrations (claim & sweep).

### Flow (ASCII)

```
[Revenue Source/Protocol]
        │ (fees/royalties/seq. surplus)
        ▼
  (set recipient or claimer)
[RevenueAdapter] ──▶ [RevenueSplitter] ──┬──▶ [LenderVault] (RBF notes)
                                         └──▶ [Treasury Safe]
                       ▲  ▲
                       │  └── Safety Rails (caps, allowlist, pause)
                       └──── Governance & Timelock / FeeRouter
```

---

## 3. Integration Surfaces (no rewrites required)
- **Aave v3 / Lending**: call mintToTreasury(assets) periodically (pull), adapter sweeps and forwards.
- **DEX / Perps with fee recipient**: set recipient to adapter (push).
- **NFT royalties / routers**: set payout to adapter (push).
- **L2 sequencers**: set surplus receiver to adapter or escrow (push).
- **Staking / restaking services**: set protocol fee sink to adapter (push) or schedule claims (pull).

For multi-token revenues, the adapter forwards per-token to the Splitter; optional FX normalization uses a price oracle to track cap in USD terms.

---

## 4. Smart Contract Architecture

### 4.1 RevenueAdapter (stateless pass-through)
- **Role**: designated fee recipient or sole authorized claimer; immediately forwards to Splitter.
- **Fail-safe**: if Splitter paused or cap reached → 100% to Treasury.
- **Ops**: optional sweepBatch(tokens[]) and claimAndForward() for pull-based sources.
- **Security**: reentrancy guard; no residual balances; governed setSplitter() (timelocked).

### 4.2 RevenueSplitter (core enforcement)
- **Inputs**: shareBps, repaymentCap, treasury, lenderVault.
- **Logic**:
  - Compute toLenders = amount × shareBps / 10_000.
  - Clamp to not exceed repaymentCap - totalPaid.
  - Transfer toLenders to LenderVault; remainder to Treasury.
  - Emit SplitExecuted, CapReached.
- **Rails**: per-tx/day max, token allowlist, optional price-oracle checks, pause().

### 4.3 LenderVault
- **Accounting**: pro-rata claims; supports ERC-20 notes (fungible per deal) or ERC-721 (position-based).
- **Payouts**: claim on demand or via streaming (Sablier v2 / Superfluid).
- **Admin**: immutable once initialized; accepts only from authorized Splitter.

### 4.4 FeeRouter (optional, for hard guarantees)
- **Gate**: setRecipient(new) only if capReached || (block.timestamp > termEnd && makeWholePaid).
- **Records**: proposal/execute events; integrates with Timelock.

### 4.5 DefaultVault (optional, for recourse)
- **Collateral**: stablecoins / blue chips / vested emissions.
- **Trigger**: declareDefault() if (a) recipient changed early; or (b) no revenue for N days post-cure.
- **Payout**: min(remainingCap, vaultBalance) to LenderVault.

---

## 5. Automation & Observability
- **Automation**:
  - Push sources: none required.
  - Pull sources: upkeep calls claimAndForward() (e.g., hourly / threshold-based).
- **Events**: Forwarded, SplitExecuted, CapReached, RecipientChangeProposed, DefaultDeclared.
- **Subgraph/Dashboard**: live chart of paid-to-date, remaining cap, next upkeep ETA.

---

## 6. Economics & Pricing

### 6.1 Variables and Definitions
- A = advance size (USDC).
- M = cap multiple (e.g., 1.35×).
- Cap = M × A.
- s = revenue share (as a fraction, e.g., 0.10).
- R_t = eligible revenue in period t.
- D_t = repayment to lenders in period t = min( s × R_t , Cap − Σ_{τ<t} D_τ ).

**Expected time to repay (back-of-envelope)**:  
If E[R_t] = μ per period and i.i.d., then E[T] ≈ Cap / (s × μ).

### 6.2 Lender Return Metrics
- **Gross return**: M − 1 (before protocol fee).
- **IRR approximation**: treat cash flows as A out at t=0, inflows D_t until Cap.  
For constant μ and period length Δ, IRR ≈ (M)^{1/(T/Δ)} − 1.

### 6.3 Choosing s and M

Given a target expected tenor T* and mean revenue μ:
- **Solve for share**: s ≈ Cap / (μ × T*) = (M × A) / (μ × T*).
- **Sensitivity**: add cushion for volatility (σ), seasonality, and drawdown scenarios; require insurance or collateral for tail risk.

### 6.4 Protocol Revenue (this RBF platform)
- Take a platform fee f (bps) on lender inflows or on the advance.
- Optionally stake platform fee to an insurance pool that backstops defaults.

---

## 7. Guarantees & Default Handling

### 7.1 Donor/Lender Protections
- **Hard gate**: FeeRouter prevents unhooking until cap or term+make-whole.
- **Timelock**: 2–7 days notice on routing changes.
- **Collateral**: DefaultVault pays remaining cap on early removal or payment failure.
- **Make-whole**: protocol may terminate by paying a pre-agreed fee or PV of the remainder.
- **Data transparency**: on-chain events + dashboards.

### 7.2 Default Triggers (examples)
- No onRevenue for N = 7–14 days while fee source active.
- Recipient change proposed/executed before cap/term.
- Collateral ratio < threshold for X hours without cure.

---

## 8. Security & Risk

### Contract Risks
- **Reentrancy** → guard on Adapter/Splitter/Vault.
- **Token quirks** → use SafeERC20; block fee-on-transfer tokens unless allowlisted.
- **Oracle risk** (if USD normalization) → stale/zero checks; fail-shut to Treasury.

### Operational Risks
- **Automation outage** (pull sources) → safe to defer; funds accrue and sweep later.
- **Bridge risk** (multichain consolidation) → prefer CCTP or per-chain splitters.

### Economic Risks
- **Revenue collapse** → slower payback; mitigate with conservative s/M, collateral, insurance.
- **Governance risk** → timelocks, public monitoring, clear charters.

### Audit Plan
- **Phase 1**: internal + formal verification on cap clamp / invariants.
- **Phase 2**: external audit (2 firms) on Adapter/Splitter/Vault/Router.
- **Phase 3**: monitored mainnet with strict caps; bug bounty.

---

## 9. Legal & Custody Posture (Non-Custodial)
- **Contracts are non-custodial**: users interact directly; the operator cannot move funds arbitrarily.
- **Keys**: upgrades/pauses are DAO-timelocked; operator lacks unilateral control.
- **Lenders hold on-chain claims**; no off-chain IOUs.
- **Marketing**: position as software protocol, not a money transmitter/custodian.
- **Jurisdiction-specific analysis** recommended for insurance pools and SPV wrappers where needed.

---

## 10. Reference Integration Patterns

### 10.1 Aave v3-style (pull)
- Upkeep calls Pool.mintToTreasury(assets) → fees materialize.
- Adapter sweepBatch([USDC, WETH, ...]) → Splitter.enforce().

### 10.2 DEX / Perps with fee recipient (push)
- DAO sets fee recipient = Adapter.
- Adapter forwards instantly; Splitter enforces cap.
- Governance package includes FeeRouter for hard guarantees.

### 10.3 NFT Royalty Routers (push)
- Marketplace/router sets payout to Adapter; multi-collection allowlist to prevent griefing.

### 10.4 L2 Sequencer Surplus (push)
- Surplus receiver = Adapter or Escrow → Splitter.
- Net/gross options mirrored via a light "ProfitFilter" if needed.

---

## 11. Multichain Designs

**Model A — Per-chain Splitters (mirrored state)**
- Each chain: Adapter + Splitter; CCIP message updates totalPaidGlobal.
- When global cap reached → all local splitters forward 100% to Treasury.

**Model B — Consolidate to Home Chain**
- Per-chain Adapters bridge USDC via CCTP at thresholds to home-chain Splitter.
- Simpler state but adds bridge latency (batch to reduce fees).

---

## 12. Tokenization, Secondary Liquidity & Insurance

### RBF-Note
- ERC-20 receipts per deal enable AMM/Orderbook trading of lender exposure.
- Optional vesting curve to reduce adverse selection at the start of a deal.

### Insurance Pool
- Stakers earn premiums π (bps of advance or repayments).
- Slashed to cover shortfalls on default; governed risk limits per sector/chain.

---

## 13. Governance & Adoption Playbook

### Proposal Menu (for target DAOs/L2s)
- **Option A (Autoroute)** — strongest, no ops.
- **Option B (Escrow-First)** — reversible, low ops.
- **Option C (Manual + Penalty)** — lowest friction + collateralized recourse.

### Standard Parameters
- Advance A, Share s, Cap M×A, Term N months, Tokens allowlist, Daily/Tx caps, Timelock, DefaultVault size, Make-whole.

### Rollout Phases
- **P0**: testnet shadow runs, public dashboards.
- **P1**: mainnet pilot (2–3% share, tight caps, 30–60d).
- **P2**: scale (target share), multiple chains/sources, insurance pool active.

---

## 14. Example Numerical Deal
- **Advance A** = 1,000,000 USDC, **Cap multiple M** = 1.35, **Cap** = 1,350,000.
- **Share s** = 10%.
- **Expected monthly eligible revenue μ** = 350,000.
- **Expected tenor T** ≈ 1,350,000 / (0.10 × 350,000) ≈ 3.86 months.
- If realized monthly revenue follows a log-normal with 25% CV, target s may be lowered to 8–9% or require 20–40% collateral to keep 95%-ile tenor under 6 months.

---

## 15. Minimal Interface Sketches (for implementers)

```solidity
interface IRevenueSplitter {
  function onRevenue(address token, uint256 amount) external;
  function isCapReached() external view returns (bool);
  function isPaused() external view returns (bool);
}

interface IRevenueAdapter {
  function sweep(address token) external;
  function sweepBatch(address[] calldata tokens) external;
  function claimAndForward() external; // for pull sources
}

interface ILenderVault {
  function depositFor(address token, uint256 amount) external;
  function claim(address token) external; // or stream via Sablier
}

interface IFeeRouter {
  function setRecipient(address newRecipient) external; // gated by cap/term/make-whole
  function recipient() external view returns (address);
}
```

**Events to index**:

```solidity
event Forwarded(address indexed token, uint256 amount, bool toSplitter);
event SplitExecuted(address indexed token, uint256 toLenders, uint256 toTreasury, uint256 totalPaid);
event CapReached(uint256 totalPaid);
event RecipientChangeProposed(address indexed newRecipient);
event DefaultDeclared(uint256 remainingPaid);
```

---

## 16. Threat Model (non-exhaustive)
- **Adapter griefing**: malicious tokens → token allowlist.
- **Price oracle manipulation** (if USD caps): TWAP, circuit breakers, stale checks.
- **Reentrancy on onRevenue**: guard + transfer-then-notify pattern.
- **Governance capture**: timelock + multisig with independent signers; emergency pause with make-whole.
- **Automation key misuse**: Safe Guard so bots can call only sweep/claim.
- **Bridge risk**: allowlisted routes/providers; thresholds; rate limiting.

---

## 17. Implementation Status

### Core Contracts ✅ COMPLETE
- RevenueAdapter, RevenueSplitter, LenderVault
- FeeRouter, DefaultVault (optional)
- Full Solidity implementation with OpenZeppelin dependencies

### Testing & Security ⚠️ IN PROGRESS  
- Comprehensive Foundry test suite (some issues in progress)
- Internal security audit completed
- Gas optimization analysis
- **Required**: External professional audit before mainnet

### Integration Examples ✅ COMPLETE
- AaveAdapter (pull-based fee claiming)
- UniswapV3Adapter (protocol fee collection)
- L2SequencerAdapter (sequencer revenue withdrawal)

### Deployment & Operations ✅ READY
- Pilot deployment scripts with conservative parameters
- Automation scripts (Defender/Gelato integration)
- Subgraph configuration for monitoring
- Comprehensive documentation and guides

---

## 18. Roadmap

### v1: Pilot Launch (Q4 2025)
- Single-chain push integrations, ERC-20 receipts, audits, dashboards.
- Conservative parameters: 3-10% share, 1.20-1.35x cap, 60-120 day terms
- Target protocols: Established DeFi with predictable revenue

### v1.1: Pull Integrations (Q1 2026)
- Pull integrations (Aave-style), automation library, reference Safe Guard.
- Expanded protocol support, optimized gas costs

### v1.2: Enhanced Safety (Q2 2026)
- USD-normalized caps, insurance pool, FeeRouter & DefaultVault templates.
- Cross-protocol risk management

### v2: Scale & Multichain (Q3 2026)
- Multichain (CCIP/CCTP), cross-deal portfolio notes, oracle attestation marketplace.
- Secondary markets for RBF notes

---

## 19. Conclusion

This protocol delivers a credibly neutral, non-custodial RBF primitive for on-chain treasuries. By meeting DAOs where they are—via a drop-in RevenueAdapter—and backing lender protections with code (Splitter, FeeRouter, DefaultVault, Timelocks), it unlocks non-dilutive growth capital with clear, automated cash-flow rights. The design is modular, governance-friendly, and integrable across DeFi verticals and L2s, enabling a standardized, transparent market for revenue-backed advances.

The implementation is production-ready for testnet deployment and pilot programs with conservative parameters. With proper external auditing and gradual scaling, this protocol can provide a new funding primitive that aligns capital providers with protocol success while preserving token holder equity.

---

## Implementation Repository

The complete implementation is available at: [RBF Crypto Treasury Protocol Repository](https://github.com/aagoldberg/rbf-cryptotreasury)

**Key Components:**
- `/src/core/` - Core protocol contracts
- `/src/optional/` - Optional safety modules  
- `/integrations/` - Protocol-specific adapters
- `/config/` - Deployment configurations
- `/script/` - Deployment and management scripts
- `/test/` - Comprehensive test suite
- `/automation/` - Defender/Gelato automation
- `/subgraph/` - Monitoring and analytics

For questions, contributions, or integration support, please see the repository documentation or open an issue.