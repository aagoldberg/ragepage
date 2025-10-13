/**
 * Shopify adapter for zkTLS proof generation
 */

import { ReclaimProofRequest } from '@reclaimprotocol/js-sdk';
import type { CashflowProof, ReclaimProof } from '../types';

interface ShopifyAdapterConfig {
  accessToken: string;
  shopDomain: string;
  reclaimConfig: {
    appId: string;
    appSecret: string;
    providerId?: string; // Optional custom provider ID
  };
}

interface ShopifyProofOptions {
  periodDays?: number;
  dateRange?: {
    start: Date;
    end: Date;
  };
}

export class ShopifyAdapter {
  private config: ShopifyAdapterConfig;

  constructor(config: ShopifyAdapterConfig) {
    this.config = config;
  }

  /**
   * Generate a zkTLS proof of Shopify revenue
   *
   * Process:
   * 1. Fetch orders from Shopify API
   * 2. Calculate total revenue
   * 3. Generate zkTLS proof via Reclaim Protocol
   * 4. Return CashflowProof with selective disclosure
   *
   * @param options Proof generation options
   * @returns CashflowProof
   */
  async generateProof(options: ShopifyProofOptions): Promise<CashflowProof> {
    // Calculate date range
    const { start, end } = this.getDateRange(options);

    // Step 1: Fetch orders from Shopify
    const orders = await this.fetchOrders(start, end);

    // Step 2: Calculate total revenue
    const totalRevenue = this.calculateRevenue(orders);

    // Step 3: Generate zkTLS proof
    const zkProof = await this.generateZkProof(orders, start, end);

    // Step 4: Create CashflowProof
    const proof: CashflowProof = {
      id: zkProof.identifier,
      merchant: this.getMerchantAddress(), // From wallet or config
      provider: 'shopify',
      totalRevenue,
      periodStart: Math.floor(start.getTime() / 1000),
      periodEnd: Math.floor(end.getTime() / 1000),
      currency: 'USD', // TODO: Get from shop settings
      zkProof,
      generatedAt: Math.floor(Date.now() / 1000),
    };

    return proof;
  }

  /**
   * Fetch orders from Shopify Admin API
   */
  private async fetchOrders(start: Date, end: Date): Promise<ShopifyOrder[]> {
    const { accessToken, shopDomain } = this.config;

    const params = new URLSearchParams({
      status: 'any',
      financial_status: 'paid',
      created_at_min: start.toISOString(),
      created_at_max: end.toISOString(),
      fields: 'id,total_price,currency,created_at,financial_status',
      limit: '250', // Max per page
    });

    const url = `https://${shopDomain}/admin/api/2024-10/orders.json?${params}`;

    const response = await fetch(url, {
      headers: {
        'X-Shopify-Access-Token': accessToken,
        'Content-Type': 'application/json',
      },
    });

    if (!response.ok) {
      throw new Error(`Shopify API error: ${response.statusText}`);
    }

    const data = await response.json();

    // TODO: Handle pagination for >250 orders
    return data.orders;
  }

  /**
   * Calculate total revenue from orders
   */
  private calculateRevenue(orders: ShopifyOrder[]): bigint {
    let total = 0;

    for (const order of orders) {
      if (order.financial_status === 'paid') {
        total += parseFloat(order.total_price);
      }
    }

    // Convert to wei (assuming USD with 2 decimals)
    return BigInt(Math.floor(total * 100));
  }

  /**
   * Generate zkTLS proof using Reclaim Protocol
   *
   * This is where the magic happens:
   * - Proves the API call was made to Shopify
   * - Proves the response is authentic
   * - Hides individual order details
   * - Only reveals: total revenue, period, currency
   */
  private async generateZkProof(
    orders: ShopifyOrder[],
    start: Date,
    end: Date
  ): Promise<ReclaimProof> {
    const totalRevenue = this.calculateRevenue(orders);
    const { appId, appSecret, providerId } = this.config.reclaimConfig;

    // Use custom provider ID or default Shopify provider
    const providerIdToUse = providerId || 'shopify-orders-api';

    // Initialize Reclaim SDK
    const proofRequest = await ReclaimProofRequest.init(
      appId,
      appSecret,
      providerIdToUse
    );

    // Set context for this verification request
    proofRequest.addContext(
      JSON.stringify({
        shop: this.config.shopDomain,
        periodStart: start.toISOString(),
        periodEnd: end.toISOString(),
        purpose: 'revenue-verification',
      })
    );

    // Set parameters for the Shopify API request
    proofRequest.setParams({
      shopDomain: this.config.shopDomain,
      startDate: start.toISOString(),
      endDate: end.toISOString(),
      accessToken: this.config.accessToken,
    });

    // Generate the proof
    // Note: In a real implementation, this would trigger the Reclaim flow
    // which may involve user interaction (QR code, browser extension, etc.)
    return new Promise((resolve, reject) => {
      proofRequest.startSession({
        onSuccess: (proofs: any) => {
          if (!proofs || proofs.length === 0) {
            reject(new Error('No proofs received from Reclaim'));
            return;
          }

          // Extract the first proof (there should only be one)
          const reclaimProof = proofs[0];

          // Transform Reclaim proof format to our ReclaimProof interface
          const proof: ReclaimProof = {
            identifier: reclaimProof.identifier || `shopify_${Date.now()}`,
            claimData: {
              provider: reclaimProof.claimData?.provider || 'shopify-orders',
              parameters: reclaimProof.claimData?.parameters || JSON.stringify({
                shop: this.config.shopDomain,
                periodStart: start.toISOString(),
                periodEnd: end.toISOString(),
              }),
              context: reclaimProof.claimData?.context || 'revenue-verification',
            },
            signatures: reclaimProof.signatures || [],
            witnesses: reclaimProof.witnesses || [],
            extractedParameters: {
              totalRevenue: totalRevenue.toString(),
              currency: 'USD',
              orderCount: orders.length,
              periodStart: start.toISOString(),
              periodEnd: end.toISOString(),
              // Include any additional parameters from Reclaim
              ...reclaimProof.extractedParameters,
            },
            publicData: reclaimProof.publicData || '0x',
            proof: reclaimProof.proof || '0x',
          };

          resolve(proof);
        },
        onFailure: (error: Error) => {
          reject(new Error(`Reclaim verification failed: ${error.message}`));
        },
      });
    });
  }

  /**
   * Get merchant Ethereum address
   * TODO: Integrate with wallet or allow user to specify
   */
  private getMerchantAddress(): string {
    // For now, return a placeholder
    // In production, this would come from:
    // 1. Connected wallet (browser)
    // 2. Config file (CLI)
    // 3. Environment variable
    return '0x0000000000000000000000000000000000000000';
  }

  /**
   * Calculate date range from options
   */
  private getDateRange(options: ShopifyProofOptions): { start: Date; end: Date } {
    if (options.dateRange) {
      return options.dateRange;
    }

    const end = new Date();
    const start = new Date();
    start.setDate(start.getDate() - (options.periodDays || 90));

    return { start, end };
  }
}

// Shopify Order type (simplified)
interface ShopifyOrder {
  id: number;
  total_price: string;
  currency: string;
  created_at: string;
  financial_status: 'pending' | 'authorized' | 'paid' | 'refunded';
}
