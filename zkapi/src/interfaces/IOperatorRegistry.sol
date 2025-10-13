// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IOperatorRegistry
 * @notice Interface for managing AVS operators and their stakes
 */
interface IOperatorRegistry {
    /// @notice Operator information
    struct Operator {
        address operatorAddress;
        uint256 stakedAmount;       // Amount of restaked ETH/tokens
        uint64 registeredAt;
        uint64 lastActiveAt;
        uint32 slashingCount;
        bool isActive;
        string endpoint;            // API endpoint for the operator node
    }

    /// @notice Staking parameters
    struct StakingConfig {
        uint256 minStake;           // Minimum stake required
        uint256 targetStake;        // Target stake amount
        uint32 unstakingPeriod;     // Time in seconds before unstake completes
        uint32 minQuorumBps;        // Minimum quorum in basis points (6700 = 67%)
    }

    /// @notice Slashing reasons
    enum SlashingReason {
        InvalidProof,               // Verified an invalid zkTLS proof
        ReplayAttack,              // Attempted to reuse old proof
        Downtime,                  // Excessive downtime
        DataWithholding,           // Failed to respond to queries
        Collusion                  // Attempted to collude with other operators
    }

    /// @notice Emitted when an operator registers
    event OperatorRegistered(address indexed operator, uint256 stakedAmount, string endpoint);

    /// @notice Emitted when an operator is slashed
    event OperatorSlashed(
        address indexed operator,
        SlashingReason reason,
        uint256 slashedAmount,
        uint256 remainingStake
    );

    /// @notice Emitted when stake is increased
    event StakeIncreased(address indexed operator, uint256 additionalStake, uint256 totalStake);

    /// @notice Emitted when unstaking is initiated
    event UnstakeInitiated(address indexed operator, uint256 amount, uint64 unstakeTime);

    /**
     * @notice Register as an AVS operator
     * @param endpoint The operator's API endpoint
     * @param blsPubKey The operator's BLS public key for signing
     */
    function registerOperator(string calldata endpoint, bytes calldata blsPubKey) external payable;

    /**
     * @notice Add more stake to an existing operator
     */
    function increaseStake() external payable;

    /**
     * @notice Initiate unstaking process
     * @param amount Amount to unstake
     */
    function initiateUnstake(uint256 amount) external;

    /**
     * @notice Complete unstaking after waiting period
     */
    function completeUnstake() external;

    /**
     * @notice Slash an operator for misbehavior
     * @param operator The operator to slash
     * @param reason The reason for slashing
     * @param slashPercentageBps Percentage to slash in basis points
     */
    function slashOperator(
        address operator,
        SlashingReason reason,
        uint32 slashPercentageBps
    ) external;

    /**
     * @notice Get operator information
     * @param operator The operator's address
     * @return info Operator struct
     */
    function getOperator(address operator) external view returns (Operator memory info);

    /**
     * @notice Check if address is an active operator
     * @param operator The address to check
     * @return isActive True if operator is active and properly staked
     */
    function isActiveOperator(address operator) external view returns (bool isActive);

    /**
     * @notice Get total active stake in the system
     * @return totalStake Sum of all active operators' stakes
     */
    function getTotalStake() external view returns (uint256 totalStake);

    /**
     * @notice Get list of all active operators
     * @return operators Array of active operator addresses
     */
    function getActiveOperators() external view returns (address[] memory operators);
}
