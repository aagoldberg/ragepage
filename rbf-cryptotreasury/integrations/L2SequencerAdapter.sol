// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/core/RevenueAdapter.sol";

interface IL2OutputOracle {
    function proposeL2Output(
        bytes32 _outputRoot,
        uint256 _l2BlockNumber,
        bytes32 _l1BlockHash,
        uint256 _l1BlockNumber
    ) external payable;
}

interface ISequencerFeeVault {
    function withdraw() external;
    function l2Sender() external view returns (address);
    function recipient() external view returns (address);
    function minWithdrawalAmount() external view returns (uint256);
    function withdrawalNetwork() external view returns (uint8);
}

interface IBaseFeeVault {
    function withdraw() external;
    function recipient() external view returns (address);
}

interface IL1FeeVault {
    function withdraw() external;
    function recipient() external view returns (address);
}

/**
 * @title L2SequencerAdapter  
 * @dev Revenue adapter for L2 sequencer fee collection (Optimism/Arbitrum/Base/Polygon)
 * Handles multiple fee vaults and automatically withdraws when thresholds are met
 */
contract L2SequencerAdapter is RevenueAdapter {
    // Fee vault interfaces for different L2s
    address public sequencerFeeVault;
    address public baseFeeVault;
    address public l1FeeVault;
    
    // Withdrawal thresholds (only withdraw if vault balance > threshold)
    uint256 public sequencerThreshold;
    uint256 public baseFeeThreshold;
    uint256 public l1FeeThreshold;
    
    // L2-specific parameters
    uint8 public immutable l2Type; // 1=Optimism, 2=Arbitrum, 3=Base, 4=Polygon
    bool public autoWithdrawEnabled;
    
    // Emergency controls
    address public emergencyRecipient;
    bool public emergencyMode;
    
    event VaultConfigured(string vaultType, address vault, uint256 threshold);
    event ThresholdUpdated(string vaultType, uint256 oldThreshold, uint256 newThreshold);
    event FeesWithdrawn(string vaultType, address vault, uint256 amount);
    event EmergencyModeToggled(bool enabled, address recipient);
    
    modifier onlyInNormalMode() {
        require(!emergencyMode, "Emergency mode active");
        _;
    }
    
    constructor(
        address _treasury,
        address _splitter, 
        address _governance,
        uint8 _l2Type,
        address _sequencerFeeVault,
        uint256 _sequencerThreshold
    ) RevenueAdapter(_treasury, _splitter, _governance) {
        require(_l2Type >= 1 && _l2Type <= 4, "Invalid L2 type");
        require(_sequencerFeeVault != address(0), "Invalid sequencer vault");
        
        l2Type = _l2Type;
        sequencerFeeVault = _sequencerFeeVault;
        sequencerThreshold = _sequencerThreshold;
        autoWithdrawEnabled = true;
        emergencyRecipient = _treasury;
        
        emit VaultConfigured("sequencer", _sequencerFeeVault, _sequencerThreshold);
    }
    
    /**
     * @dev Override claimAndForward to withdraw from L2 fee vaults
     */
    function claimAndForward() external override nonReentrant onlyInNormalMode {
        require(autoWithdrawEnabled, "Auto-withdraw disabled");
        
        uint256 totalWithdrawn = 0;
        
        // Withdraw from sequencer fee vault
        if (sequencerFeeVault != address(0) && sequencerFeeVault.balance > sequencerThreshold) {
            uint256 balanceBefore = address(this).balance;
            
            try ISequencerFeeVault(sequencerFeeVault).withdraw() {
                uint256 withdrawn = address(this).balance - balanceBefore;
                if (withdrawn > 0) {
                    totalWithdrawn += withdrawn;
                    emit FeesWithdrawn("sequencer", sequencerFeeVault, withdrawn);
                }
            } catch {
                // Vault withdrawal failed, continue with other vaults
            }
        }
        
        // Withdraw from base fee vault (if configured)
        if (baseFeeVault != address(0) && baseFeeVault.balance > baseFeeThreshold) {
            uint256 balanceBefore = address(this).balance;
            
            try IBaseFeeVault(baseFeeVault).withdraw() {
                uint256 withdrawn = address(this).balance - balanceBefore;
                if (withdrawn > 0) {
                    totalWithdrawn += withdrawn;
                    emit FeesWithdrawn("baseFee", baseFeeVault, withdrawn);
                }
            } catch {
                // Vault withdrawal failed, continue
            }
        }
        
        // Withdraw from L1 fee vault (if configured)
        if (l1FeeVault != address(0) && l1FeeVault.balance > l1FeeThreshold) {
            uint256 balanceBefore = address(this).balance;
            
            try IL1FeeVault(l1FeeVault).withdraw() {
                uint256 withdrawn = address(this).balance - balanceBefore;
                if (withdrawn > 0) {
                    totalWithdrawn += withdrawn;
                    emit FeesWithdrawn("l1Fee", l1FeeVault, withdrawn);
                }
            } catch {
                // Vault withdrawal failed, continue
            }
        }
        
        // Forward ETH to splitter if any was withdrawn
        if (totalWithdrawn > 0) {
            _sweep(address(0)); // Sweep ETH
        }
    }
    
    /**
     * @dev Configure base fee vault (Optimism/Base)
     */
    function configureBaseFeeVault(address _vault, uint256 _threshold) external onlyGovernance {
        require(_vault != address(0), "Invalid vault");
        
        baseFeeVault = _vault;
        baseFeeThreshold = _threshold;
        
        emit VaultConfigured("baseFee", _vault, _threshold);
    }
    
    /**
     * @dev Configure L1 fee vault (Optimism/Base)  
     */
    function configureL1FeeVault(address _vault, uint256 _threshold) external onlyGovernance {
        require(_vault != address(0), "Invalid vault");
        
        l1FeeVault = _vault;
        l1FeeThreshold = _threshold;
        
        emit VaultConfigured("l1Fee", _vault, _threshold);
    }
    
    /**
     * @dev Update withdrawal thresholds
     */
    function updateThresholds(
        uint256 _sequencerThreshold,
        uint256 _baseFeeThreshold,
        uint256 _l1FeeThreshold
    ) external onlyGovernance {
        if (_sequencerThreshold != sequencerThreshold) {
            emit ThresholdUpdated("sequencer", sequencerThreshold, _sequencerThreshold);
            sequencerThreshold = _sequencerThreshold;
        }
        
        if (_baseFeeThreshold != baseFeeThreshold) {
            emit ThresholdUpdated("baseFee", baseFeeThreshold, _baseFeeThreshold);
            baseFeeThreshold = _baseFeeThreshold;
        }
        
        if (_l1FeeThreshold != l1FeeThreshold) {
            emit ThresholdUpdated("l1Fee", l1FeeThreshold, _l1FeeThreshold);
            l1FeeThreshold = _l1FeeThreshold;
        }
    }
    
    /**
     * @dev Enable/disable automatic withdrawals
     */
    function setAutoWithdrawEnabled(bool _enabled) external onlyGovernance {
        autoWithdrawEnabled = _enabled;
    }
    
    /**
     * @dev Emergency mode - redirects all withdrawals to emergency recipient
     */
    function setEmergencyMode(bool _enabled, address _recipient) external onlyGovernance {
        emergencyMode = _enabled;
        
        if (_enabled) {
            require(_recipient != address(0), "Invalid emergency recipient");
            emergencyRecipient = _recipient;
        }
        
        emit EmergencyModeToggled(_enabled, _recipient);
    }
    
    /**
     * @dev Emergency withdrawal - bypasses normal flow
     */
    function emergencyWithdraw() external onlyGovernance {
        require(emergencyMode, "Not in emergency mode");
        
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = emergencyRecipient.call{value: balance}("");
            require(success, "Emergency withdrawal failed");
        }
        
        // Also try to withdraw from vaults in emergency
        if (sequencerFeeVault != address(0)) {
            try ISequencerFeeVault(sequencerFeeVault).withdraw() {} catch {}
        }
        
        if (baseFeeVault != address(0)) {
            try IBaseFeeVault(baseFeeVault).withdraw() {} catch {}
        }
        
        if (l1FeeVault != address(0)) {
            try IL1FeeVault(l1FeeVault).withdraw() {} catch {}
        }
        
        // Send any additional balance to emergency recipient
        balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = emergencyRecipient.call{value: balance}("");
            require(success, "Final emergency transfer failed");
        }
    }
    
    /**
     * @dev Get vault balances and withdrawal status
     */
    function getVaultStatus() external view returns (
        uint256 sequencerBalance,
        uint256 baseFeeBalance,
        uint256 l1FeeBalance,
        bool canWithdrawSequencer,
        bool canWithdrawBaseFee,
        bool canWithdrawL1Fee
    ) {
        sequencerBalance = sequencerFeeVault != address(0) ? sequencerFeeVault.balance : 0;
        baseFeeBalance = baseFeeVault != address(0) ? baseFeeVault.balance : 0;
        l1FeeBalance = l1FeeVault != address(0) ? l1FeeVault.balance : 0;
        
        canWithdrawSequencer = sequencerBalance > sequencerThreshold;
        canWithdrawBaseFee = baseFeeBalance > baseFeeThreshold;
        canWithdrawL1Fee = l1FeeBalance > l1FeeThreshold;
    }
    
    /**
     * @dev Get L2 configuration info
     */
    function getL2Info() external view returns (
        uint8 l2TypeValue,
        string memory l2Name,
        bool autoWithdraw,
        bool emergency
    ) {
        l2TypeValue = l2Type;
        autoWithdraw = autoWithdrawEnabled;
        emergency = emergencyMode;
        
        if (l2Type == 1) l2Name = "Optimism";
        else if (l2Type == 2) l2Name = "Arbitrum";
        else if (l2Type == 3) l2Name = "Base";
        else if (l2Type == 4) l2Name = "Polygon";
        else l2Name = "Unknown";
    }
    
    /**
     * @dev Manual withdrawal from specific vault (governance only)
     */
    function manualWithdraw(uint8 vaultType) external onlyGovernance onlyInNormalMode {
        if (vaultType == 1 && sequencerFeeVault != address(0)) {
            ISequencerFeeVault(sequencerFeeVault).withdraw();
            _sweep(address(0));
        } else if (vaultType == 2 && baseFeeVault != address(0)) {
            IBaseFeeVault(baseFeeVault).withdraw();
            _sweep(address(0));
        } else if (vaultType == 3 && l1FeeVault != address(0)) {
            IL1FeeVault(l1FeeVault).withdraw();
            _sweep(address(0));
        } else {
            revert("Invalid vault type");
        }
    }
    
    // Override receive to handle ETH from vault withdrawals
    receive() external payable override {
        // ETH received from vault withdrawals
        // Will be swept to splitter in claimAndForward()
    }
}