// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/core/RevenueAdapter.sol";

interface IAavePool {
    function mintToTreasury(address[] calldata assets) external;
    function getReserveData(address asset) external view returns (
        uint256 configuration,
        uint128 liquidityIndex,
        uint128 variableBorrowIndex,
        uint128 currentLiquidityRate,
        uint128 currentVariableBorrowRate,
        uint128 currentStableBorrowRate,
        uint40 lastUpdateTimestamp,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint8 id
    );
}

interface IAToken {
    function balanceOf(address user) external view returns (uint256);
}

/**
 * @title AaveAdapter
 * @dev Revenue adapter specifically for Aave v3 protocol integration
 * Implements pull-based revenue claiming via mintToTreasury()
 */
contract AaveAdapter is RevenueAdapter {
    IAavePool public immutable aavePool;
    address[] public monitoredAssets;
    
    // Thresholds for claiming (only claim if balance > threshold)
    mapping(address => uint256) public claimThresholds;
    
    event AssetAdded(address indexed asset, uint256 threshold);
    event AssetRemoved(address indexed asset);
    event ThresholdUpdated(address indexed asset, uint256 oldThreshold, uint256 newThreshold);
    event ClaimExecuted(address[] assets, uint256[] amounts);
    
    constructor(
        address _treasury,
        address _splitter,
        address _governance,
        address _aavePool,
        address[] memory _initialAssets,
        uint256[] memory _thresholds
    ) RevenueAdapter(_treasury, _splitter, _governance) {
        require(_aavePool != address(0), "Invalid Aave pool");
        require(_initialAssets.length == _thresholds.length, "Arrays length mismatch");
        
        aavePool = IAavePool(_aavePool);
        
        // Set up initial monitored assets
        for (uint256 i = 0; i < _initialAssets.length; i++) {
            _addAsset(_initialAssets[i], _thresholds[i]);
        }
    }
    
    /**
     * @dev Override claimAndForward to implement Aave-specific claiming
     * Calls mintToTreasury for assets that have accumulated sufficient fees
     */
    function claimAndForward() external override nonReentrant {
        require(monitoredAssets.length > 0, "No assets configured");
        
        // Check which assets have sufficient treasury balance to claim
        address[] memory assetsToClaim = new address[](monitoredAssets.length);
        uint256[] memory balancesToClaim = new uint256[](monitoredAssets.length);
        uint256 assetsCount = 0;
        
        for (uint256 i = 0; i < monitoredAssets.length; i++) {
            address asset = monitoredAssets[i];
            uint256 threshold = claimThresholds[asset];
            
            // Get aToken balance for the treasury
            (, , , , , , , address aTokenAddress, , , , ) = aavePool.getReserveData(asset);
            
            if (aTokenAddress != address(0)) {
                uint256 treasuryBalance = IAToken(aTokenAddress).balanceOf(treasury);
                
                if (treasuryBalance > threshold) {
                    assetsToClaim[assetsCount] = asset;
                    balancesToClaim[assetsCount] = treasuryBalance;
                    assetsCount++;
                }
            }
        }
        
        if (assetsCount == 0) {
            return; // No assets meet threshold
        }
        
        // Create properly sized array for assets to claim
        address[] memory finalAssets = new address[](assetsCount);
        uint256[] memory finalBalances = new uint256[](assetsCount);
        
        for (uint256 i = 0; i < assetsCount; i++) {
            finalAssets[i] = assetsToClaim[i];
            finalBalances[i] = balancesToClaim[i];
        }
        
        // Call Aave's mintToTreasury to claim fees
        aavePool.mintToTreasury(finalAssets);
        
        // Sweep claimed tokens to the splitter
        for (uint256 i = 0; i < assetsCount; i++) {
            _sweep(finalAssets[i]);
        }
        
        emit ClaimExecuted(finalAssets, finalBalances);
    }
    
    /**
     * @dev Add a new asset to monitor for treasury claiming
     */
    function addAsset(address asset, uint256 threshold) external onlyGovernance {
        require(asset != address(0), "Invalid asset");
        require(!_isAssetMonitored(asset), "Asset already monitored");
        
        _addAsset(asset, threshold);
    }
    
    /**
     * @dev Remove an asset from monitoring
     */
    function removeAsset(address asset) external onlyGovernance {
        require(_isAssetMonitored(asset), "Asset not monitored");
        
        // Remove from array
        for (uint256 i = 0; i < monitoredAssets.length; i++) {
            if (monitoredAssets[i] == asset) {
                monitoredAssets[i] = monitoredAssets[monitoredAssets.length - 1];
                monitoredAssets.pop();
                break;
            }
        }
        
        delete claimThresholds[asset];
        emit AssetRemoved(asset);
    }
    
    /**
     * @dev Update claiming threshold for an asset
     */
    function updateThreshold(address asset, uint256 newThreshold) external onlyGovernance {
        require(_isAssetMonitored(asset), "Asset not monitored");
        
        uint256 oldThreshold = claimThresholds[asset];
        claimThresholds[asset] = newThreshold;
        
        emit ThresholdUpdated(asset, oldThreshold, newThreshold);
    }
    
    /**
     * @dev Get list of monitored assets
     */
    function getMonitoredAssets() external view returns (address[] memory) {
        return monitoredAssets;
    }
    
    /**
     * @dev Check claimable amounts for all monitored assets
     */
    function getClaimableAmounts() external view returns (address[] memory assets, uint256[] memory amounts) {
        assets = new address[](monitoredAssets.length);
        amounts = new uint256[](monitoredAssets.length);
        
        for (uint256 i = 0; i < monitoredAssets.length; i++) {
            address asset = monitoredAssets[i];
            assets[i] = asset;
            
            // Get aToken balance for treasury
            (, , , , , , , address aTokenAddress, , , , ) = aavePool.getReserveData(asset);
            
            if (aTokenAddress != address(0)) {
                uint256 treasuryBalance = IAToken(aTokenAddress).balanceOf(treasury);
                amounts[i] = treasuryBalance > claimThresholds[asset] ? treasuryBalance : 0;
            }
        }
    }
    
    function _addAsset(address asset, uint256 threshold) internal {
        monitoredAssets.push(asset);
        claimThresholds[asset] = threshold;
        emit AssetAdded(asset, threshold);
    }
    
    function _isAssetMonitored(address asset) internal view returns (bool) {
        for (uint256 i = 0; i < monitoredAssets.length; i++) {
            if (monitoredAssets[i] == asset) {
                return true;
            }
        }
        return false;
    }
}