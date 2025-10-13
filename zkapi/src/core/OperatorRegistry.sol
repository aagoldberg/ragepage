// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IOperatorRegistry.sol";

/**
 * @title OperatorRegistry
 * @notice Manages AVS operator registration, staking, and slashing
 * @dev Operators stake ETH (or wrapped restaked ETH from EigenLayer) to participate
 */
contract OperatorRegistry is IOperatorRegistry {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientStake();
    error OperatorAlreadyRegistered();
    error OperatorNotFound();
    error UnstakingPeriodNotComplete();
    error NoUnstakeInProgress();
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Staking configuration
    StakingConfig public config;

    /// @notice Mapping: operator address => Operator
    mapping(address => Operator) public operators;

    /// @notice Mapping: operator => BLS public key
    mapping(address => bytes) public operatorBlsPubKeys;

    /// @notice List of all operator addresses
    address[] public operatorList;

    /// @notice Mapping: operator => unstake info
    mapping(address => UnstakeInfo) public pendingUnstakes;

    /// @notice Insurance fund for slashing compensation
    uint256 public insuranceFund;

    /// @notice Owner/governance address
    address public owner;

    /// @notice Total stake in the system
    uint256 public totalStaked;

    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct UnstakeInfo {
        uint256 amount;
        uint64 unstakeTime;
        bool pending;
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        owner = msg.sender;

        // Set default staking configuration
        config = StakingConfig({
            minStake: 32 ether,         // Minimum 32 ETH (1 validator)
            targetStake: 320 ether,     // Target 320 ETH (~$1M at $3k ETH)
            unstakingPeriod: 7 days,    // 7 day unstaking period
            minQuorumBps: 6700          // 67% minimum quorum
        });
    }

    /*//////////////////////////////////////////////////////////////
                        OPERATOR FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOperatorRegistry
    function registerOperator(
        string calldata endpoint,
        bytes calldata blsPubKey
    ) external payable override {
        if (msg.value < config.minStake) {
            revert InsufficientStake();
        }

        if (operators[msg.sender].operatorAddress != address(0)) {
            revert OperatorAlreadyRegistered();
        }

        // Register operator
        operators[msg.sender] = Operator({
            operatorAddress: msg.sender,
            stakedAmount: msg.value,
            registeredAt: uint64(block.timestamp),
            lastActiveAt: uint64(block.timestamp),
            slashingCount: 0,
            isActive: true,
            endpoint: endpoint
        });

        operatorBlsPubKeys[msg.sender] = blsPubKey;
        operatorList.push(msg.sender);
        totalStaked += msg.value;

        emit OperatorRegistered(msg.sender, msg.value, endpoint);
    }

    /// @inheritdoc IOperatorRegistry
    function increaseStake() external payable override {
        Operator storage operator = operators[msg.sender];
        if (operator.operatorAddress == address(0)) {
            revert OperatorNotFound();
        }

        operator.stakedAmount += msg.value;
        totalStaked += msg.value;

        emit StakeIncreased(msg.sender, msg.value, operator.stakedAmount);
    }

    /// @inheritdoc IOperatorRegistry
    function initiateUnstake(uint256 amount) external override {
        Operator storage operator = operators[msg.sender];
        if (operator.operatorAddress == address(0)) {
            revert OperatorNotFound();
        }

        require(operator.stakedAmount >= amount, "Insufficient stake");
        require(
            operator.stakedAmount - amount >= config.minStake || operator.stakedAmount - amount == 0,
            "Must maintain min stake or unstake all"
        );

        // Initiate unstaking period
        pendingUnstakes[msg.sender] = UnstakeInfo({
            amount: amount,
            unstakeTime: uint64(block.timestamp + config.unstakingPeriod),
            pending: true
        });

        // If unstaking all, deactivate operator
        if (operator.stakedAmount == amount) {
            operator.isActive = false;
        }

        emit UnstakeInitiated(msg.sender, amount, uint64(block.timestamp + config.unstakingPeriod));
    }

    /// @inheritdoc IOperatorRegistry
    function completeUnstake() external override {
        UnstakeInfo storage unstakeInfo = pendingUnstakes[msg.sender];
        if (!unstakeInfo.pending) {
            revert NoUnstakeInProgress();
        }

        if (block.timestamp < unstakeInfo.unstakeTime) {
            revert UnstakingPeriodNotComplete();
        }

        Operator storage operator = operators[msg.sender];
        uint256 amount = unstakeInfo.amount;

        // Update state
        operator.stakedAmount -= amount;
        totalStaked -= amount;
        delete pendingUnstakes[msg.sender];

        // Transfer ETH
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /*//////////////////////////////////////////////////////////////
                        SLASHING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOperatorRegistry
    function slashOperator(
        address operator,
        SlashingReason reason,
        uint32 slashPercentageBps
    ) external override onlyOwner {
        Operator storage op = operators[operator];
        if (op.operatorAddress == address(0)) {
            revert OperatorNotFound();
        }

        // Calculate slash amount
        uint256 slashAmount = (op.stakedAmount * slashPercentageBps) / 10000;

        // Update operator state
        op.stakedAmount -= slashAmount;
        op.slashingCount += 1;
        totalStaked -= slashAmount;

        // If stake falls below minimum, deactivate
        if (op.stakedAmount < config.minStake) {
            op.isActive = false;
        }

        // Add to insurance fund
        insuranceFund += slashAmount;

        emit OperatorSlashed(operator, reason, slashAmount, op.stakedAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOperatorRegistry
    function getOperator(address operator)
        external
        view
        override
        returns (Operator memory info)
    {
        return operators[operator];
    }

    /// @inheritdoc IOperatorRegistry
    function isActiveOperator(address operator)
        external
        view
        override
        returns (bool isActive)
    {
        Operator memory op = operators[operator];
        return op.isActive && op.stakedAmount >= config.minStake;
    }

    /// @inheritdoc IOperatorRegistry
    function getTotalStake() external view override returns (uint256 totalStake) {
        return totalStaked;
    }

    /// @inheritdoc IOperatorRegistry
    function getActiveOperators()
        external
        view
        override
        returns (address[] memory activeOps)
    {
        // Count active operators
        uint256 activeCount = 0;
        for (uint256 i = 0; i < operatorList.length; i++) {
            if (operators[operatorList[i]].isActive) {
                activeCount++;
            }
        }

        // Build array of active operators
        activeOps = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < operatorList.length; i++) {
            if (operators[operatorList[i]].isActive) {
                activeOps[index] = operatorList[i];
                index++;
            }
        }

        return activeOps;
    }

    /**
     * @notice Get operator's BLS public key
     */
    function getOperatorBlsPubKey(address operator) external view returns (bytes memory) {
        return operatorBlsPubKeys[operator];
    }

    /**
     * @notice Get total number of operators
     */
    function getOperatorCount() external view returns (uint256) {
        return operatorList.length;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update staking configuration
     */
    function updateStakingConfig(StakingConfig calldata newConfig) external onlyOwner {
        config = newConfig;
    }

    /**
     * @notice Withdraw from insurance fund (governance only)
     */
    function withdrawInsuranceFund(address recipient, uint256 amount) external onlyOwner {
        require(amount <= insuranceFund, "Insufficient funds");
        insuranceFund -= amount;

        (bool success,) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
     * @notice Transfer ownership
     */
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /**
     * @notice Update operator activity timestamp (called by AVS)
     */
    function updateOperatorActivity(address operator) external {
        // Only allow CashflowOracleAVS to update activity
        // In production, this would check msg.sender == cashflowOracleAVS address
        Operator storage op = operators[operator];
        if (op.operatorAddress != address(0)) {
            op.lastActiveAt = uint64(block.timestamp);
        }
    }

    /**
     * @notice Emergency pause operator
     */
    function pauseOperator(address operator) external onlyOwner {
        Operator storage op = operators[operator];
        op.isActive = false;
    }

    /**
     * @notice Unpause operator
     */
    function unpauseOperator(address operator) external onlyOwner {
        Operator storage op = operators[operator];
        require(op.stakedAmount >= config.minStake, "Insufficient stake");
        op.isActive = true;
    }
}
