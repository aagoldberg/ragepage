/**
 * zkAPI Client SDK
 *
 * Generate zkTLS proofs of cashflow data from Shopify, Square, Plaid
 * Submit proofs to the zkAPI operator network
 * Query verified attestations on-chain
 */

export { ZkApiClient } from './client';
export { ShopifyAdapter } from './adapters/shopify';
export { SquareAdapter } from './adapters/square';
export { PlaidAdapter } from './adapters/plaid';
export * from './types';
