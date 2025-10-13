# Revflow Protocol Integrations

This directory contains specialized adapters for integrating Revflow with major DeFi protocols and revenue sources.

## Integration Overview

Each adapter inherits from the base `RevenueAdapter` and implements protocol-specific revenue claiming logic:

- **Push-based**: Protocol directly sends fees to adapter
- **Pull-based**: Adapter periodically claims fees from protocol
- **Hybrid**: Combination of both patterns

## Available Integrations

### 1. AaveAdapter.sol
**Type**: Pull-based  
**Purpose**: Claims protocol fees from Aave v3 lending pools

**Key Features**:
- Monitors multiple reserve assets (USDC, WETH, DAI, etc.)
- Configurable claiming thresholds per asset
- Uses `mintToTreasury()` to claim accumulated fees
- Automatic asset discovery via Aave pool registry

**Setup Example**:
```solidity
address[] memory assets = [USDC, WETH, DAI];
uint256[] memory thresholds = [1000e6, 1e18, 1000e18]; // 1k USDC, 1 WETH, 1k DAI

AaveAdapter adapter = new AaveAdapter(
    treasury,
    splitter,
    governance,
    aavePool, // 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2 for mainnet
    assets,
    thresholds
);
```

**Automation**: Call `claimAndForward()` every 6-24 hours depending on volume

### 2. UniswapV3Adapter.sol
**Type**: Pull-based  
**Purpose**: Collects protocol fees from Uniswap V3 pools

**Key Features**:
- Monitors specific high-volume pools
- Collects both token0 and token1 protocol fees
- Configurable thresholds per pool per token
- Factory integration for pool management

**Setup Example**:
```solidity
address[] memory pools = [
    0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640, // USDC/WETH 0.05%
    0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8  // USDC/WETH 0.3%
];

UniswapV3Adapter adapter = new UniswapV3Adapter(
    treasury,
    splitter, 
    governance,
    uniswapV3Factory,
    pools
);

// Set thresholds for each pool
adapter.addPool(pools[0], 1000e6, 1e18); // 1k USDC, 1 WETH
```

**Automation**: Call `claimAndForward()` every 12-24 hours

### 3. L2SequencerAdapter.sol
**Type**: Pull-based  
**Purpose**: Withdraws sequencer revenue from L2 fee vaults

**Key Features**:
- Supports Optimism, Arbitrum, Base, Polygon
- Handles multiple fee vault types (sequencer, base fee, L1 fee)
- Emergency mode for critical situations
- Auto-withdrawal based on vault balance thresholds

**Setup Example**:
```solidity
// For Optimism mainnet
L2SequencerAdapter adapter = new L2SequencerAdapter(
    treasury,
    splitter,
    governance,
    1, // L2 type: Optimism
    0x4200000000000000000000000000000000000011, // SequencerFeeVault
    5 ether // 5 ETH threshold
);

// Configure additional vaults
adapter.configureBaseFeeVault(
    0x4200000000000000000000000000000000000019, // BaseFeeVault
    2 ether
);
```

**Automation**: Call `claimAndForward()` every 1-6 hours depending on transaction volume

## Integration Patterns

### Pattern 1: Simple Push Integration
For protocols with configurable fee recipients:

```solidity
// In protocol governance proposal
protocol.setFeeRecipient(address(revenueAdapter));
```

**Examples**: Most DEXs, NFT marketplaces, simple fee-generating contracts

### Pattern 2: Pull Integration with Automation
For protocols with treasury claiming functions:

```solidity
// Deploy specialized adapter
ProtocolAdapter adapter = new ProtocolAdapter(...);

// Set up automation (Defender/Gelato)
automation.createTask(
    address(adapter),
    adapter.claimAndForward.selector,
    interval // e.g., every 12 hours
);
```

**Examples**: Aave, Compound, Uniswap, complex protocols

### Pattern 3: Hybrid Integration
For protocols with multiple revenue streams:

```solidity
// Deploy multiple adapters
PushAdapter pushAdapter = new PushAdapter(...);
PullAdapter pullAdapter = new PullAdapter(...);

// Both forward to same splitter
assert(pushAdapter.splitter() == pullAdapter.splitter());
```

## Deployment Guide

### Step 1: Deploy Core Contracts
```bash
forge script script/Deploy.s.sol --broadcast --verify
```

### Step 2: Deploy Integration Adapter
```bash
# Example for Aave integration
AAVE_POOL=0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2 \
ASSETS="[0xA0b86a33E6417C42e8BE7CC4b06a76C8C3A3b2a0,0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2]" \
forge create src/integrations/AaveAdapter.sol:AaveAdapter --constructor-args $TREASURY $SPLITTER $GOVERNANCE $AAVE_POOL "$ASSETS" "[1000000000,1000000000000000000]"
```

### Step 3: Configure Protocol Integration
```solidity
// For push-based (via governance)
protocol.setFeeRecipient(address(adapter));

// For pull-based (set up automation)
defender.createAutotask({
    target: address(adapter),
    selector: "claimAndForward()",
    schedule: "0 0 */12 * * *" // Every 12 hours
});
```

### Step 4: Monitor and Validate
- Set up subgraph to track revenue flows
- Configure alerts for unusual activity
- Validate revenue splitting percentages
- Monitor gas costs and optimization

## Security Considerations

### Access Control
- All adapters inherit governance controls from base `RevenueAdapter`
- Critical functions require multi-sig approval
- Timelock delays on parameter changes

### Risk Mitigation
- Claiming thresholds prevent dust attacks
- Emergency modes for critical situations
- Circuit breakers for unusual patterns
- Regular balance reconciliation

### Gas Optimization
- Batch operations where possible
- Configurable thresholds to avoid unprofitable claims
- Gas price monitoring in automation

## Testing Integrations

### Local Testing
```bash
# Test specific adapter
forge test --match-path test/integrations/AaveAdapter.t.sol -vvv

# Test with mainnet fork
forge test --fork-url $MAINNET_RPC_URL --match-test testMainnetFork
```

### Testnet Validation
1. Deploy to testnet with small amounts
2. Validate revenue collection and splitting
3. Test automation reliability
4. Confirm gas costs are reasonable

### Mainnet Deployment
1. Start with conservative parameters
2. Monitor for 1-2 weeks with small amounts
3. Gradually increase limits after validation
4. Set up comprehensive monitoring

## Monitoring & Alerts

### Key Metrics
- Revenue collection frequency and amounts
- Gas costs per collection
- Splitter distribution accuracy
- Vault balance trends

### Alert Conditions
- Failed collections (3+ consecutive failures)
- Unusual revenue amounts (>5x normal)
- High gas costs (>2x expected)
- Splitter cap approaching (>90%)

### Dashboard Integration
All adapters emit standardized events for dashboard integration:
- `FeesWithdrawn(string source, uint256 amount)`
- `ThresholdUpdated(string parameter, uint256 value)`
- `EmergencyModeToggled(bool enabled)`

## Maintenance

### Regular Tasks
- Review and adjust claiming thresholds monthly
- Update gas price parameters for automation
- Validate protocol integration still functional
- Check for protocol upgrades affecting integration

### Emergency Procedures
- Emergency mode activation process
- Manual intervention procedures
- Recovery from failed transactions
- Protocol communication channels

## Adding New Integrations

To add a new protocol integration:

1. **Inherit from RevenueAdapter**:
```solidity
contract NewProtocolAdapter is RevenueAdapter {
    constructor(...) RevenueAdapter(_treasury, _splitter, _governance) {}
}
```

2. **Override `claimAndForward()`**:
```solidity
function claimAndForward() external override nonReentrant {
    // Protocol-specific claiming logic
    // Forward collected tokens via _sweep()
}
```

3. **Add configuration functions**:
```solidity
function configureProtocol(address target, uint256 threshold) external onlyGovernance {
    // Protocol-specific setup
}
```

4. **Implement monitoring functions**:
```solidity
function getClaimableAmount() external view returns (uint256) {
    // Return how much can be claimed
}
```

5. **Add comprehensive tests**:
```solidity
// Test claiming logic, edge cases, and failure modes
```

For questions or support with integrations, see the main [README](../README.md) or open an issue.