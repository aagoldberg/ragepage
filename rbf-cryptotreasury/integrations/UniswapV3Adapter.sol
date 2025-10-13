// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/core/RevenueAdapter.sol";

interface IUniswapV3Factory {
    function setOwner(address _owner) external;
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
    function collectProtocol(
        address pool,
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
}

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
    function protocolFees() external view returns (uint128 token0, uint128 token1);
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
}

/**
 * @title UniswapV3Adapter
 * @dev Revenue adapter for Uniswap V3 protocol fee collection
 * Implements pull-based revenue claiming from protocol fees
 */
contract UniswapV3Adapter is RevenueAdapter {
    IUniswapV3Factory public immutable factory;
    address[] public monitoredPools;
    
    // Minimum protocol fees required before claiming (per token)
    mapping(address => mapping(address => uint128)) public claimThresholds; // pool -> token -> threshold
    
    event PoolAdded(address indexed pool);
    event PoolRemoved(address indexed pool);
    event ProtocolFeesCollected(address indexed pool, address token0, address token1, uint128 amount0, uint128 amount1);
    event ThresholdUpdated(address indexed pool, address indexed token, uint128 threshold);
    
    constructor(
        address _treasury,
        address _splitter,
        address _governance,
        address _factory,
        address[] memory _initialPools
    ) RevenueAdapter(_treasury, _splitter, _governance) {
        require(_factory != address(0), "Invalid factory");
        
        factory = IUniswapV3Factory(_factory);
        
        // Add initial pools
        for (uint256 i = 0; i < _initialPools.length; i++) {
            _addPool(_initialPools[i]);
        }
    }
    
    /**
     * @dev Override claimAndForward to collect protocol fees from monitored pools
     */
    function claimAndForward() external override nonReentrant {
        require(monitoredPools.length > 0, "No pools configured");
        
        uint256 totalCollected = 0;
        
        for (uint256 i = 0; i < monitoredPools.length; i++) {
            address poolAddress = monitoredPools[i];
            IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
            
            // Check protocol fees available
            (uint128 fees0, uint128 fees1) = pool.protocolFees();
            
            address token0 = pool.token0();
            address token1 = pool.token1();
            
            uint128 threshold0 = claimThresholds[poolAddress][token0];
            uint128 threshold1 = claimThresholds[poolAddress][token1];
            
            // Only collect if fees exceed thresholds
            uint128 amount0ToCollect = fees0 > threshold0 ? fees0 : 0;
            uint128 amount1ToCollect = fees1 > threshold1 ? fees1 : 0;
            
            if (amount0ToCollect > 0 || amount1ToCollect > 0) {
                // Collect protocol fees to this adapter
                (uint128 collected0, uint128 collected1) = pool.collectProtocol(
                    address(this),
                    amount0ToCollect,
                    amount1ToCollect
                );
                
                if (collected0 > 0 || collected1 > 0) {
                    totalCollected++;
                    
                    // Forward collected tokens to splitter
                    if (collected0 > 0) {
                        _sweep(token0);
                    }
                    if (collected1 > 0) {
                        _sweep(token1);
                    }
                    
                    emit ProtocolFeesCollected(poolAddress, token0, token1, collected0, collected1);
                }
            }
        }
        
        require(totalCollected > 0, "No fees collected");
    }
    
    /**
     * @dev Add a pool to monitor for protocol fee collection
     */
    function addPool(
        address pool,
        uint128 threshold0,
        uint128 threshold1
    ) external onlyGovernance {
        require(pool != address(0), "Invalid pool");
        require(!_isPoolMonitored(pool), "Pool already monitored");
        
        _addPool(pool);
        
        IUniswapV3Pool poolContract = IUniswapV3Pool(pool);
        address token0 = poolContract.token0();
        address token1 = poolContract.token1();
        
        claimThresholds[pool][token0] = threshold0;
        claimThresholds[pool][token1] = threshold1;
    }
    
    /**
     * @dev Remove a pool from monitoring
     */
    function removePool(address pool) external onlyGovernance {
        require(_isPoolMonitored(pool), "Pool not monitored");
        
        // Remove from array
        for (uint256 i = 0; i < monitoredPools.length; i++) {
            if (monitoredPools[i] == pool) {
                monitoredPools[i] = monitoredPools[monitoredPools.length - 1];
                monitoredPools.pop();
                break;
            }
        }
        
        // Clean up thresholds
        IUniswapV3Pool poolContract = IUniswapV3Pool(pool);
        address token0 = poolContract.token0();
        address token1 = poolContract.token1();
        
        delete claimThresholds[pool][token0];
        delete claimThresholds[pool][token1];
        
        emit PoolRemoved(pool);
    }
    
    /**
     * @dev Update claiming thresholds for a pool
     */
    function updateThresholds(
        address pool,
        uint128 threshold0,
        uint128 threshold1
    ) external onlyGovernance {
        require(_isPoolMonitored(pool), "Pool not monitored");
        
        IUniswapV3Pool poolContract = IUniswapV3Pool(pool);
        address token0 = poolContract.token0();
        address token1 = poolContract.token1();
        
        claimThresholds[pool][token0] = threshold0;
        claimThresholds[pool][token1] = threshold1;
        
        emit ThresholdUpdated(pool, token0, threshold0);
        emit ThresholdUpdated(pool, token1, threshold1);
    }
    
    /**
     * @dev Get all monitored pools
     */
    function getMonitoredPools() external view returns (address[] memory) {
        return monitoredPools;
    }
    
    /**
     * @dev Get claimable protocol fees for all monitored pools
     */
    function getClaimableFees() external view returns (
        address[] memory pools,
        address[] memory tokens0,
        address[] memory tokens1,
        uint128[] memory claimable0,
        uint128[] memory claimable1
    ) {
        uint256 poolCount = monitoredPools.length;
        pools = new address[](poolCount);
        tokens0 = new address[](poolCount);
        tokens1 = new address[](poolCount);
        claimable0 = new uint128[](poolCount);
        claimable1 = new uint128[](poolCount);
        
        for (uint256 i = 0; i < poolCount; i++) {
            address poolAddress = monitoredPools[i];
            IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
            
            pools[i] = poolAddress;
            tokens0[i] = pool.token0();
            tokens1[i] = pool.token1();
            
            (uint128 fees0, uint128 fees1) = pool.protocolFees();
            
            uint128 threshold0 = claimThresholds[poolAddress][tokens0[i]];
            uint128 threshold1 = claimThresholds[poolAddress][tokens1[i]];
            
            claimable0[i] = fees0 > threshold0 ? fees0 : 0;
            claimable1[i] = fees1 > threshold1 ? fees1 : 0;
        }
    }
    
    /**
     * @dev Emergency function to collect specific amounts from a pool
     */
    function emergencyCollect(
        address pool,
        uint128 amount0,
        uint128 amount1
    ) external onlyGovernance {
        require(_isPoolMonitored(pool), "Pool not monitored");
        
        IUniswapV3Pool poolContract = IUniswapV3Pool(pool);
        (uint128 collected0, uint128 collected1) = poolContract.collectProtocol(
            address(this),
            amount0,
            amount1
        );
        
        if (collected0 > 0) {
            _sweep(poolContract.token0());
        }
        if (collected1 > 0) {
            _sweep(poolContract.token1());
        }
        
        emit ProtocolFeesCollected(pool, poolContract.token0(), poolContract.token1(), collected0, collected1);
    }
    
    function _addPool(address pool) internal {
        monitoredPools.push(pool);
        emit PoolAdded(pool);
    }
    
    function _isPoolMonitored(address pool) internal view returns (bool) {
        for (uint256 i = 0; i < monitoredPools.length; i++) {
            if (monitoredPools[i] == pool) {
                return true;
            }
        }
        return false;
    }
}