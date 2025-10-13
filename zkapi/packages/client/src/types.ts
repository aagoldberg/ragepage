/**
 * Core types for zkAPI client
 */

export interface CashflowProof {
  /** Unique proof identifier */
  id: string;

  /** Merchant address */
  merchant: string;

  /** API provider (shopify, square, plaid) */
  provider: 'shopify' | 'square' | 'plaid';

  /** Total revenue in smallest currency unit */
  totalRevenue: bigint;

  /** Revenue period start (Unix timestamp) */
  periodStart: number;

  /** Revenue period end (Unix timestamp) */
  periodEnd: number;

  /** Currency code (USD, EUR, etc) */
  currency: string;

  /** Raw zkTLS proof from Reclaim */
  zkProof: ReclaimProof;

  /** When proof was generated */
  generatedAt: number;
}

export interface ReclaimProof {
  /** Reclaim proof identifier */
  identifier: string;

  /** Claim data */
  claimData: {
    provider: string;
    parameters: string;
    context: string;
  };

  /** Witness signatures */
  signatures: string[];

  /** Witness information */
  witnesses: {
    id: string;
    url: string;
  }[];

  /** Extracted parameters (public) */
  extractedParameters: Record<string, any>;

  /** zkSNARK public data */
  publicData: string;

  /** zkSNARK proof */
  proof: string;
}

export interface ProofGenerationOptions {
  /** API provider */
  provider: 'shopify' | 'square' | 'plaid';

  /** Revenue period in days (default: 90) */
  periodDays?: number;

  /** Access token for API */
  accessToken: string;

  /** Store/merchant identifier */
  storeId: string;

  /** Optional: Specific date range */
  dateRange?: {
    start: Date;
    end: Date;
  };
}

export interface AttestationStatus {
  /** Proof ID */
  proofId: string;

  /** Current status */
  status: 'pending' | 'verifying' | 'verified' | 'rejected';

  /** Number of operator signatures received */
  signatures: number;

  /** Total operators */
  totalOperators: number;

  /** Quorum reached (67%) */
  quorumReached: boolean;

  /** Transaction hash (if on-chain) */
  txHash?: string;

  /** Block number (if on-chain) */
  blockNumber?: number;

  /** Rejection reason (if rejected) */
  rejectionReason?: string;
}

export interface ZkApiConfig {
  /** Ethereum RPC URL */
  rpcUrl: string;

  /** CashflowOracle contract address */
  oracleAddress: string;

  /** Operator network endpoint */
  operatorEndpoint?: string;

  /** Reclaim app ID */
  reclaimAppId: string;

  /** Reclaim app secret */
  reclaimAppSecret: string;
}

export interface OAuthConfig {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  scopes: string[];
}

export interface ShopifyConfig extends OAuthConfig {
  shopDomain: string;
}

export interface SquareConfig extends OAuthConfig {
  environment: 'sandbox' | 'production';
}

export interface PlaidConfig {
  clientId: string;
  secret: string;
  environment: 'sandbox' | 'development' | 'production';
}
