// Gelato Web3 Functions task for Revflow automation
// This is a serverless function that runs on Gelato's network

import { Web3Function, Web3FunctionContext } from "@gelatonetwork/web3-functions-sdk";
import { Contract } from "ethers";

// ABI fragments
const REVENUE_ADAPTER_ABI = [
  "function sweep(address token) external",
  "function sweepBatch(address[] calldata tokens) external"
];

const REVENUE_SPLITTER_ABI = [
  "function isCapReached() external view returns (bool)",
  "function isPaused() external view returns (bool)"
];

const ERC20_ABI = [
  "function balanceOf(address) external view returns (uint256)"
];

Web3Function.onRun(async (context: Web3FunctionContext) => {
  const { userArgs, multiChainProvider } = context;

  // Configuration from user args
  const adapterAddress = userArgs.adapterAddress as string;
  const splitterAddress = userArgs.splitterAddress as string;
  const tokensStr = userArgs.tokens as string; // JSON string of token configs
  const minBalanceThreshold = userArgs.minBalanceThreshold as string;

  console.log("Starting Revflow Gelato automation...");

  try {
    // Parse token configuration
    const tokens = JSON.parse(tokensStr);
    
    // Get provider for the network
    const provider = multiChainProvider.default();
    
    // Initialize contracts
    const adapter = new Contract(adapterAddress, REVENUE_ADAPTER_ABI, provider);
    const splitter = new Contract(splitterAddress, REVENUE_SPLITTER_ABI, provider);

    // Check if deal is still active
    const [isCapReached, isPaused] = await Promise.all([
      splitter.isCapReached(),
      splitter.isPaused()
    ]);

    if (isCapReached) {
      return {
        canExec: false,
        message: "Cap reached - no more automation needed"
      };
    }

    if (isPaused) {
      return {
        canExec: false,
        message: "Splitter is paused"
      };
    }

    // Check token balances
    const balanceChecks = tokens.map(async (token: any) => {
      let balance;
      
      if (token.address === "0x0000000000000000000000000000000000000000") {
        // ETH
        balance = await provider.getBalance(adapterAddress);
      } else {
        // ERC20
        const tokenContract = new Contract(token.address, ERC20_ABI, provider);
        balance = await tokenContract.balanceOf(adapterAddress);
      }
      
      return {
        address: token.address,
        symbol: token.symbol,
        balance: balance,
        minBalance: BigInt(token.minBalance),
        shouldSweep: balance >= BigInt(token.minBalance)
      };
    });

    const balanceResults = await Promise.all(balanceChecks);
    const tokensToSweep = balanceResults
      .filter(result => result.shouldSweep)
      .map(result => result.address);

    console.log(`Tokens to sweep: ${tokensToSweep.length}`);
    
    if (tokensToSweep.length === 0) {
      return {
        canExec: false,
        message: "No tokens meet minimum balance threshold"
      };
    }

    // Prepare transaction data
    let callData;
    if (tokensToSweep.length === 1) {
      // Single sweep
      const iface = new ethers.Interface(REVENUE_ADAPTER_ABI);
      callData = iface.encodeFunctionData("sweep", [tokensToSweep[0]]);
    } else {
      // Batch sweep
      const iface = new ethers.Interface(REVENUE_ADAPTER_ABI);
      callData = iface.encodeFunctionData("sweepBatch", [tokensToSweep]);
    }

    return {
      canExec: true,
      callData: [
        {
          to: adapterAddress,
          data: callData
        }
      ]
    };

  } catch (error) {
    console.error("Error in Gelato task:", error);
    
    return {
      canExec: false,
      message: `Execution failed: ${error.message}`
    };
  }
});

export default Web3Function;