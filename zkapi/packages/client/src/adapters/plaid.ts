/**
 * Plaid adapter for zkTLS proof generation
 * TODO: Implement in Week 6
 */

import type { CashflowProof } from '../types';

export class PlaidAdapter {
  async generateProof(options: any): Promise<CashflowProof> {
    throw new Error('Plaid adapter not yet implemented - coming in Week 6');
  }
}
