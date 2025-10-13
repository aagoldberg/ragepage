# @zkapi/client

**TypeScript SDK for generating zkTLS proofs of cashflow data**

Generate zero-knowledge proofs of your revenue from Shopify, Square, or Plaid without revealing individual transactions or customer data.

---

## Installation

```bash
npm install @zkapi/client
# or
yarn add @zkapi/client
# or
pnpm add @zkapi/client
```

---

## Quick Start

```typescript
import { ZkApiClient } from '@zkapi/client';

// Initialize client
const client = new ZkApiClient({
  rpcUrl: 'https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY',
  oracleAddress: '0x...', // CashflowOracle contract
  reclaimAppId: 'YOUR_RECLAIM_APP_ID',
  reclaimAppSecret: 'YOUR_RECLAIM_SECRET',
});

// Generate proof of Shopify revenue
const proof = await client.generateProof({
  provider: 'shopify',
  accessToken: 'shpat_xxxxx',
  storeId: 'mystore.myshopify.com',
  periodDays: 90,
});

// Submit to operator network
const proofId = await client.submitProof(proof);

// Check status
const status = await client.getAttestationStatus(proofId);
console.log(`Status: ${status.status}`);
```

---

## Features

- ✅ **Shopify Integration** - E-commerce revenue verification
- 🚧 **Square Integration** - POS + online payments (Coming Week 5)
- 🚧 **Plaid Integration** - Bank transaction data (Coming Week 6)
- ✅ **Zero-Knowledge Proofs** - Privacy-preserving via zkTLS
- ✅ **On-Chain Verification** - Decentralized operator network
- ✅ **TypeScript First** - Full type safety

---

## API Reference

### `ZkApiClient`

Main client for interacting with zkAPI.

#### Constructor

```typescript
new ZkApiClient(config: ZkApiConfig)
```

**Config**:
- `rpcUrl` - Ethereum RPC endpoint
- `oracleAddress` - CashflowOracle contract address
- `reclaimAppId` - Your Reclaim Protocol app ID
- `reclaimAppSecret` - Your Reclaim Protocol secret
- `operatorEndpoint` - (Optional) Custom operator network URL

#### Methods

**`generateProof(options)`**

Generate a zkTLS proof of cashflow data.

```typescript
await client.generateProof({
  provider: 'shopify' | 'square' | 'plaid',
  accessToken: string,
  storeId: string,
  periodDays: number,
});
```

**`submitProof(proof)`**

Submit proof to operator network for verification.

```typescript
const proofId = await client.submitProof(proof);
```

**`getAttestationStatus(proofId)`**

Check verification status.

```typescript
const status = await client.getAttestationStatus(proofId);
// status.status: 'pending' | 'verifying' | 'verified' | 'rejected'
```

**`getVerifiedRevenue(merchant, start, end)`**

Query verified revenue from blockchain.

```typescript
const { totalRevenue, verifiedAt, source } = await client.getVerifiedRevenue(
  '0x123...',
  startTimestamp,
  endTimestamp
);
```

**`hasRecentAttestation(merchant, maxAge)`**

Check if merchant has recent verified data.

```typescript
const hasRecent = await client.hasRecentAttestation(
  '0x123...',
  7 * 24 * 60 * 60 // 7 days
);
```

---

## Supported Providers

### Shopify

```typescript
const proof = await client.generateProof({
  provider: 'shopify',
  accessToken: 'shpat_xxxxx',
  storeId: 'mystore.myshopify.com',
  periodDays: 90,
});
```

**What's Proven**:
- ✅ Total revenue for period
- ✅ Currency
- ✅ Number of orders
- ✅ Time period

**What's Hidden**:
- 🔒 Individual order details
- 🔒 Customer information
- 🔒 Product details
- 🔒 Shipping addresses

### Square (Coming Soon)

```typescript
const proof = await client.generateProof({
  provider: 'square',
  accessToken: 'sq0atp-xxxxx',
  storeId: 'merchant-id',
  periodDays: 90,
});
```

### Plaid (Coming Soon)

```typescript
const proof = await client.generateProof({
  provider: 'plaid',
  accessToken: 'access-xxxxx',
  storeId: 'account-id',
  periodDays: 90,
});
```

---

## Examples

### Generate Proof for Loan Application

```typescript
import { ZkApiClient } from '@zkapi/client';
import { ethers } from 'ethers';

async function applyForLoan() {
  // 1. Generate proof
  const client = new ZkApiClient({ /* config */ });

  const proof = await client.generateProof({
    provider: 'shopify',
    accessToken: process.env.SHOPIFY_TOKEN!,
    storeId: process.env.SHOP_DOMAIN!,
    periodDays: 90,
  });

  console.log(`Generated proof for $${proof.totalRevenue / 100n} revenue`);

  // 2. Submit to operator network
  const proofId = await client.submitProof(proof);

  // 3. Wait for verification
  let status;
  do {
    await new Promise(resolve => setTimeout(resolve, 5000));
    status = await client.getAttestationStatus(proofId);
    console.log(`Status: ${status.status} (${status.signatures}/${status.totalOperators} sigs)`);
  } while (status.status !== 'verified' && status.status !== 'rejected');

  if (status.status === 'rejected') {
    throw new Error(`Proof rejected: ${status.rejectionReason}`);
  }

  console.log(`✅ Proof verified on-chain: ${status.txHash}`);

  // 4. Apply for loan (proof is now on-chain)
  const signer = new ethers.Wallet(process.env.PRIVATE_KEY!);
  const loanContract = new ethers.Contract(LOAN_ADDRESS, LOAN_ABI, signer);

  const tx = await loanContract.requestLoan(
    ethers.parseEther('10000') // Request $10k loan
  );

  console.log(`Loan requested: ${tx.hash}`);
}
```

### Check Existing Verification

```typescript
import { ZkApiClient } from '@zkapi/client';

async function checkMerchantRevenue(merchantAddress: string) {
  const client = new ZkApiClient({ /* config */ });

  // Check if recent data exists
  const hasRecent = await client.hasRecentAttestation(
    merchantAddress,
    7 * 24 * 60 * 60 // 7 days
  );

  if (!hasRecent) {
    console.log('No recent verification found');
    return;
  }

  // Get verified revenue
  const now = Math.floor(Date.now() / 1000);
  const { totalRevenue, verifiedAt, source } = await client.getVerifiedRevenue(
    merchantAddress,
    now - 90 * 24 * 60 * 60, // Last 90 days
    now
  );

  console.log(`Verified Revenue: $${totalRevenue / 100n}`);
  console.log(`Source: ${source}`);
  console.log(`Verified: ${new Date(verifiedAt * 1000).toISOString()}`);
}
```

---

## Development Status

| Feature | Status | Week |
|---------|--------|------|
| TypeScript SDK | ✅ Complete | Week 2 |
| Shopify Adapter | 🚧 In Progress | Week 3 |
| Square Adapter | 📋 Planned | Week 5 |
| Plaid Adapter | 📋 Planned | Week 6 |
| CLI Tool | 📋 Planned | Week 4 |
| Real zkTLS Proofs | 🚧 In Progress | Week 2-3 |
| Operator Network | 📋 Planned | Week 7-8 |

---

## Architecture

```
┌──────────────────────────────────────────────┐
│           Merchant Application               │
│         (Your Loan Request dApp)             │
└────────────────┬─────────────────────────────┘
                 │
                 │ 1. generateProof()
                 ▼
┌──────────────────────────────────────────────┐
│          @zkapi/client SDK                   │
│  ┌────────────────────────────────────────┐  │
│  │  ShopifyAdapter                        │  │
│  │  • OAuth flow                          │  │
│  │  • API call                            │  │
│  │  • zkTLS proof via Reclaim             │  │
│  └────────────────────────────────────────┘  │
└────────────────┬─────────────────────────────┘
                 │
                 │ 2. submitProof()
                 ▼
┌──────────────────────────────────────────────┐
│        Operator Network (15+ nodes)          │
│  • Verify zkTLS proofs                       │
│  • Sign with BLS                             │
│  • Aggregate signatures                      │
└────────────────┬─────────────────────────────┘
                 │
                 │ 3. submitAttestation()
                 ▼
┌──────────────────────────────────────────────┐
│   CashflowOracleAVS.sol (Blockchain)         │
│  • Store verified revenue                    │
│  • Provide query interface                   │
└──────────────────────────────────────────────┘
```

---

## Security

**Zero-Knowledge Proofs**:
- Individual transactions are never revealed
- Only aggregate revenue is proven
- zkTLS ensures API response authenticity

**Operator Network**:
- 15+ independent operators
- 67% consensus required
- $15M+ in slashable stake
- Economically secured by EigenLayer

**Smart Contract**:
- Audited by [TBD]
- Open source
- Battle-tested EigenLayer AVS pattern

---

## Contributing

See [ARCHITECTURE.md](../../ARCHITECTURE.md) for design decisions and implementation roadmap.

---

## License

MIT
