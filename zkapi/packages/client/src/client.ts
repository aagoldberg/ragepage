/**
 * Main zkAPI client for proof generation and verification
 */

import { ethers } from 'ethers';
import type {
  ZkApiConfig,
  CashflowProof,
  ProofGenerationOptions,
  AttestationStatus,
} from './types';

export class ZkApiClient {
  private config: ZkApiConfig;
  private provider: ethers.Provider;

  constructor(config: ZkApiConfig) {
    this.config = config;
    this.provider = new ethers.JsonRpcProvider(config.rpcUrl);
  }

  /**
   * Generate a cashflow proof using zkTLS
   *
   * @param options Proof generation options
   * @returns CashflowProof with zkTLS proof
   *
   * @example
   * ```typescript
   * const proof = await client.generateProof({
   *   provider: 'shopify',
   *   accessToken: 'shpat_xxx',
   *   storeId: 'mystore.myshopify.com',
   *   periodDays: 90
   * });
   * ```
   */
  async generateProof(options: ProofGenerationOptions): Promise<CashflowProof> {
    const { provider } = options;

    switch (provider) {
      case 'shopify':
        return this.generateShopifyProof(options);
      case 'square':
        return this.generateSquareProof(options);
      case 'plaid':
        return this.generatePlaidProof(options);
      default:
        throw new Error(`Unsupported provider: ${provider}`);
    }
  }

  /**
   * Submit a proof to the operator network
   *
   * @param proof The cashflow proof to submit
   * @returns Proof submission ID
   *
   * @example
   * ```typescript
   * const proofId = await client.submitProof(proof);
   * console.log(`Proof submitted: ${proofId}`);
   * ```
   */
  async submitProof(proof: CashflowProof): Promise<string> {
    const endpoint = this.config.operatorEndpoint || 'https://operators.zkapi.xyz';

    const response = await fetch(`${endpoint}/api/v1/submit-proof`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        proof: {
          merchant: proof.merchant,
          totalRevenue: proof.totalRevenue.toString(),
          periodStart: proof.periodStart,
          periodEnd: proof.periodEnd,
          provider: proof.provider,
          zkProof: proof.zkProof,
        },
      }),
    });

    if (!response.ok) {
      throw new Error(`Failed to submit proof: ${response.statusText}`);
    }

    const data = await response.json();
    return data.proofId;
  }

  /**
   * Check the status of a submitted proof
   *
   * @param proofId The proof ID from submitProof()
   * @returns Current attestation status
   *
   * @example
   * ```typescript
   * const status = await client.getAttestationStatus(proofId);
   * console.log(`Status: ${status.status}, Signatures: ${status.signatures}/${status.totalOperators}`);
   * ```
   */
  async getAttestationStatus(proofId: string): Promise<AttestationStatus> {
    const endpoint = this.config.operatorEndpoint || 'https://operators.zkapi.xyz';

    const response = await fetch(`${endpoint}/api/v1/status/${proofId}`);

    if (!response.ok) {
      throw new Error(`Failed to get status: ${response.statusText}`);
    }

    return response.json();
  }

  /**
   * Get verified revenue for a merchant from the blockchain
   *
   * @param merchant Merchant address
   * @param periodStart Start timestamp
   * @param periodEnd End timestamp
   * @returns Verified revenue amount
   *
   * @example
   * ```typescript
   * const revenue = await client.getVerifiedRevenue(
   *   '0x123...',
   *   Math.floor(Date.now() / 1000) - 90 * 24 * 60 * 60,
   *   Math.floor(Date.now() / 1000)
   * );
   * console.log(`Verified revenue: ${ethers.formatEther(revenue)} ETH`);
   * ```
   */
  async getVerifiedRevenue(
    merchant: string,
    periodStart: number,
    periodEnd: number
  ): Promise<{
    totalRevenue: bigint;
    verifiedAt: number;
    source: string;
  }> {
    // ABI for getVerifiedRevenue function
    const abi = [
      'function getVerifiedRevenue(address merchant, uint256 startTimestamp, uint256 endTimestamp) view returns (uint256 totalRevenue, uint64 verifiedAt, string memory source)',
    ];

    const contract = new ethers.Contract(
      this.config.oracleAddress,
      abi,
      this.provider
    );

    const result = await contract.getVerifiedRevenue(
      merchant,
      periodStart,
      periodEnd
    );

    return {
      totalRevenue: result[0],
      verifiedAt: Number(result[1]),
      source: result[2],
    };
  }

  /**
   * Check if a merchant has recent verified data
   *
   * @param merchant Merchant address
   * @param maxAge Maximum age in seconds
   * @returns True if recent data exists
   */
  async hasRecentAttestation(
    merchant: string,
    maxAge: number
  ): Promise<boolean> {
    const abi = [
      'function hasRecentAttestation(address merchant, uint256 maxAge) view returns (bool)',
    ];

    const contract = new ethers.Contract(
      this.config.oracleAddress,
      abi,
      this.provider
    );

    return contract.hasRecentAttestation(merchant, maxAge);
  }

  /**
   * Internal: Generate Shopify proof
   */
  private async generateShopifyProof(
    options: ProofGenerationOptions
  ): Promise<CashflowProof> {
    // Import dynamically to avoid circular dependency
    const { ShopifyAdapter } = await import('./adapters/shopify');

    const adapter = new ShopifyAdapter({
      accessToken: options.accessToken,
      shopDomain: options.storeId,
      reclaimConfig: {
        appId: this.config.reclaimAppId,
        appSecret: this.config.reclaimAppSecret,
      },
    });

    return adapter.generateProof({
      periodDays: options.periodDays || 90,
      dateRange: options.dateRange,
    });
  }

  /**
   * Internal: Generate Square proof
   */
  private async generateSquareProof(
    options: ProofGenerationOptions
  ): Promise<CashflowProof> {
    const { SquareAdapter } = await import('./adapters/square');

    const adapter = new SquareAdapter({
      accessToken: options.accessToken,
      merchantId: options.storeId,
      reclaimConfig: {
        appId: this.config.reclaimAppId,
        appSecret: this.config.reclaimAppSecret,
      },
    });

    return adapter.generateProof({
      periodDays: options.periodDays || 90,
      dateRange: options.dateRange,
    });
  }

  /**
   * Internal: Generate Plaid proof
   */
  private async generatePlaidProof(
    options: ProofGenerationOptions
  ): Promise<CashflowProof> {
    const { PlaidAdapter } = await import('./adapters/plaid');

    const adapter = new PlaidAdapter({
      accessToken: options.accessToken,
      accountId: options.storeId,
      reclaimConfig: {
        appId: this.config.reclaimAppId,
        appSecret: this.config.reclaimAppSecret,
      },
    });

    return adapter.generateProof({
      periodDays: options.periodDays || 90,
      dateRange: options.dateRange,
    });
  }
}
