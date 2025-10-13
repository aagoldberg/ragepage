// OpenZeppelin Defender Autotask for Revenue Claiming and Sweeping
// This script handles pull-based revenue sources that need periodic claiming

const { ethers } = require('ethers');
const { DefenderRelaySigner, DefenderRelayProvider } = require('defender-relay-client/lib/ethers');

// ABI fragments for the contracts we'll interact with
const REVENUE_ADAPTER_ABI = [
  'function sweep(address token) external',
  'function sweepBatch(address[] calldata tokens) external',
  'function claimAndForward() external',
  'function splitter() external view returns (address)',
  'function treasury() external view returns (address)'
];

const REVENUE_SPLITTER_ABI = [
  'function isCapReached() external view returns (bool)',
  'function isPaused() external view returns (bool)',
  'function getTotalPaid() external view returns (uint256)',
  'function getRemainingCap() external view returns (uint256)'
];

const ERC20_ABI = [
  'function balanceOf(address) external view returns (uint256)',
  'function symbol() external view returns (string)'
];

// Configuration
const REVFLOW_CONFIG = {
  // Contract addresses - these should be loaded from environment
  REVENUE_ADAPTER: process.env.REVENUE_ADAPTER_ADDRESS,
  REVENUE_SPLITTER: process.env.REVENUE_SPLITTER_ADDRESS,
  
  // Tokens to monitor and sweep
  TOKENS: [
    {
      address: process.env.USDC_ADDRESS || '0xA0b86a33E6417C42e8BE7CC4b06a76C8C3A3b2a0', // USDC
      symbol: 'USDC',
      minBalance: ethers.parseUnits('100', 6) // Only sweep if balance > 100 USDC
    },
    {
      address: '0x0000000000000000000000000000000000000000', // ETH
      symbol: 'ETH',
      minBalance: ethers.parseEther('0.1') // Only sweep if balance > 0.1 ETH
    }
  ],
  
  // Thresholds
  MIN_GAS_PRICE: ethers.parseUnits('10', 'gwei'), // Don't execute if gas too high
  MAX_GAS_PRICE: ethers.parseUnits('100', 'gwei')
};

async function handler(event) {
  console.log('Starting Revflow automation...');
  
  // Initialize provider and signer
  const provider = new DefenderRelayProvider(event);
  const signer = new DefenderRelaySigner(event, provider, { speed: 'fast' });
  
  try {
    // Check gas price
    const gasPrice = await provider.getGasPrice();
    console.log(`Current gas price: ${ethers.formatUnits(gasPrice, 'gwei')} gwei`);
    
    if (gasPrice > REVFLOW_CONFIG.MAX_GAS_PRICE) {
      console.log('Gas price too high, skipping execution');
      return { success: false, reason: 'Gas price too high' };
    }
    
    // Initialize contracts
    const adapter = new ethers.Contract(
      REVFLOW_CONFIG.REVENUE_ADAPTER,
      REVENUE_ADAPTER_ABI,
      signer
    );
    
    const splitter = new ethers.Contract(
      REVFLOW_CONFIG.REVENUE_SPLITTER,
      REVENUE_SPLITTER_ABI,
      provider
    );
    
    // Check if deal is still active
    const isCapReached = await splitter.isCapReached();
    const isPaused = await splitter.isPaused();
    
    if (isCapReached) {
      console.log('Cap reached, no more processing needed');
      return { success: true, reason: 'Cap reached' };
    }
    
    if (isPaused) {
      console.log('Splitter is paused, skipping');
      return { success: false, reason: 'Splitter paused' };
    }
    
    // Check balances and determine what to sweep
    const tokensToSweep = [];
    let totalValue = ethers.parseEther('0');
    
    for (const tokenConfig of REVFLOW_CONFIG.TOKENS) {
      let balance;
      
      if (tokenConfig.address === '0x0000000000000000000000000000000000000000') {
        // ETH balance
        balance = await provider.getBalance(REVFLOW_CONFIG.REVENUE_ADAPTER);
      } else {
        // ERC20 balance
        const tokenContract = new ethers.Contract(
          tokenConfig.address,
          ERC20_ABI,
          provider
        );
        balance = await tokenContract.balanceOf(REVFLOW_CONFIG.REVENUE_ADAPTER);
      }
      
      console.log(`${tokenConfig.symbol} balance: ${ethers.formatUnits(balance, tokenConfig.address === '0x0000000000000000000000000000000000000000' ? 18 : 6)}`);
      
      if (balance >= tokenConfig.minBalance) {
        tokensToSweep.push(tokenConfig.address);
        
        // Rough USD value estimation (simplified)
        if (tokenConfig.symbol === 'USDC') {
          totalValue += balance; // 1:1 with USD
        } else if (tokenConfig.symbol === 'ETH') {
          totalValue += balance * BigInt(2000); // Assume $2000 ETH
        }
      }
    }
    
    if (tokensToSweep.length === 0) {
      console.log('No tokens meet minimum balance threshold');
      return { success: true, reason: 'No tokens to sweep' };
    }
    
    console.log(`Found ${tokensToSweep.length} tokens to sweep`);
    
    // Execute sweep
    let tx;
    if (tokensToSweep.length === 1) {
      // Single token sweep
      console.log(`Sweeping single token: ${tokensToSweep[0]}`);
      tx = await adapter.sweep(tokensToSweep[0], {
        gasLimit: 200000 // Conservative gas limit
      });
    } else {
      // Batch sweep
      console.log(`Batch sweeping ${tokensToSweep.length} tokens`);
      tx = await adapter.sweepBatch(tokensToSweep, {
        gasLimit: 300000 + (tokensToSweep.length * 100000) // Scale with number of tokens
      });
    }
    
    console.log(`Transaction submitted: ${tx.hash}`);
    
    // Wait for confirmation
    const receipt = await tx.wait();
    console.log(`Transaction confirmed in block ${receipt.blockNumber}`);
    
    // Check updated balances
    const remainingCap = await splitter.getRemainingCap();
    const totalPaid = await splitter.getTotalPaid();
    
    return {
      success: true,
      transactionHash: tx.hash,
      gasUsed: receipt.gasUsed.toString(),
      tokensSwept: tokensToSweep,
      totalPaid: totalPaid.toString(),
      remainingCap: remainingCap.toString()
    };
    
  } catch (error) {
    console.error('Error in automation:', error);
    
    // Check if it's a known error we can handle
    if (error.message.includes('Cap reached')) {
      return { success: true, reason: 'Cap reached during execution' };
    }
    
    if (error.message.includes('Pausable: paused')) {
      return { success: false, reason: 'Contract paused during execution' };
    }
    
    return {
      success: false,
      error: error.message,
      reason: 'Execution failed'
    };
  }
}

// For testing locally
if (require.main === module) {
  // Mock event for testing
  const mockEvent = {
    apiKey: process.env.DEFENDER_API_KEY,
    apiSecret: process.env.DEFENDER_API_SECRET,
    relayerApiKey: process.env.RELAYER_API_KEY,
    relayerApiSecret: process.env.RELAYER_API_SECRET
  };
  
  handler(mockEvent)
    .then(result => {
      console.log('Result:', result);
      process.exit(0);
    })
    .catch(error => {
      console.error('Error:', error);
      process.exit(1);
    });
}

module.exports = { handler };