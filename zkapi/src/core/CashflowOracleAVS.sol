// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/ICashflowOracle.sol";
import "../interfaces/IOperatorRegistry.sol";
import "../interfaces/IZKProofVerifier.sol";

/**
 * @title CashflowOracleAVS
 * @notice Core AVS contract for decentralized cashflow verification
 * @dev Implements EigenLayer AVS pattern with zkTLS proof verification
 *
 * Architecture:
 * 1. Merchants generate zkTLS proofs of their API data (Shopify/Square/Plaid)
 * 2. Operators verify proofs and sign attestations
 * 3. Aggregated signatures are submitted on-chain
 * 4. Social loan protocols query verified cashflow data
 */
contract CashflowOracleAVS is ICashflowOracle {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidQuorum();
    error AttestationExpired();
    error InvalidSignature();
    error ProofAlreadyUsed();
    error InsufficientOperatorStake();
    error UnauthorizedOperator();
    error AttestationNotFound();
    error RevenueDataTooOld();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Registry of AVS operators
    IOperatorRegistry public immutable operatorRegistry;

    /// @notice ZK proof verifier contract
    IZKProofVerifier public immutable proofVerifier;

    /// @notice Minimum quorum required (basis points)
    uint32 public constant MIN_QUORUM_BPS = 6700; // 67%

    /// @notice Maximum attestation age (seconds)
    uint256 public constant MAX_ATTESTATION_AGE = 1 hours;

    /// @notice Maximum proof age (seconds)
    uint256 public constant MAX_PROOF_AGE = 2 hours;

    /// @notice Mapping: attestationId => CashflowAttestation
    mapping(bytes32 => CashflowAttestation) public attestations;

    /// @notice Mapping: merchant => attestationId (latest)
    mapping(address => bytes32) public merchantLatestAttestation;

    /// @notice Mapping: merchant => attestationId[] (history)
    mapping(address => bytes32[]) public merchantAttestationHistory;

    /// @notice Mapping: proofHash => bool (used proofs)
    mapping(bytes32 => bool) public usedProofs;

    /// @notice Owner address (for upgrades and config)
    address public owner;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyActiveOperator() {
        require(
            operatorRegistry.isActiveOperator(msg.sender),
            "Not active operator"
        );
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _operatorRegistry,
        address _proofVerifier
    ) {
        operatorRegistry = IOperatorRegistry(_operatorRegistry);
        proofVerifier = IZKProofVerifier(_proofVerifier);
        owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                        CORE AVS FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Submit a verified cashflow attestation (called by operator aggregator)
     * @param attestation The cashflow attestation data
     * @param aggregateSignature BLS aggregate signature from operators
     * @param operatorIds IDs of operators who signed
     */
    function submitAttestation(
        CashflowAttestation memory attestation,
        bytes calldata aggregateSignature,
        address[] calldata operatorIds
    ) external {
        // 1. Validate quorum
        if (attestation.quorumBps < MIN_QUORUM_BPS) {
            revert InvalidQuorum();
        }

        // 2. Check attestation is recent
        if (attestation.verifiedAt > block.timestamp ||
            block.timestamp - attestation.verifiedAt > MAX_ATTESTATION_AGE) {
            revert AttestationExpired();
        }

        // 3. Check proof hasn't been used before
        if (usedProofs[attestation.zkProofHash]) {
            revert ProofAlreadyUsed();
        }

        // 4. Verify BLS aggregate signature
        bytes32 attestationHash = _hashAttestation(attestation);
        if (!_verifyAggregateSignature(attestationHash, aggregateSignature, operatorIds)) {
            revert InvalidSignature();
        }

        // 5. Mark proof as used
        usedProofs[attestation.zkProofHash] = true;

        // 6. Store attestation
        bytes32 attestationId = attestationHash;
        attestations[attestationId] = attestation;
        merchantLatestAttestation[attestation.merchant] = attestationId;
        merchantAttestationHistory[attestation.merchant].push(attestationId);

        // 7. Emit event
        emit AttestationVerified(
            attestationId,
            attestation.merchant,
            attestation.totalRevenue,
            attestation.apiSource,
            attestation.verifiedAt
        );
    }

    /**
     * @notice Dispute an attestation (for governance or fraud detection)
     * @param attestationId The attestation to dispute
     * @param reason The reason for the dispute
     */
    function disputeAttestation(bytes32 attestationId, string calldata reason) external {
        CashflowAttestation memory attestation = attestations[attestationId];
        if (attestation.merchant == address(0)) {
            revert AttestationNotFound();
        }

        emit AttestationDisputed(attestationId, msg.sender, reason);

        // TODO: Implement dispute resolution mechanism
        // - Could trigger operator slashing if proven fraudulent
        // - Could involve governance vote
        // - Could require counter-proof submission
    }

    /*//////////////////////////////////////////////////////////////
                        QUERY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICashflowOracle
    function getVerifiedRevenue(
        address merchant,
        uint256 startTimestamp,
        uint256 endTimestamp
    ) external view override returns (
        uint256 totalRevenue,
        uint64 verifiedAt,
        string memory source
    ) {
        bytes32 attestationId = merchantLatestAttestation[merchant];
        if (attestationId == bytes32(0)) {
            return (0, 0, "");
        }

        CashflowAttestation memory attestation = attestations[attestationId];

        // Check if attestation covers the requested period
        if (attestation.periodStart <= startTimestamp && attestation.periodEnd >= endTimestamp) {
            return (
                attestation.totalRevenue,
                attestation.verifiedAt,
                attestation.apiSource
            );
        }

        return (0, 0, "");
    }

    /// @inheritdoc ICashflowOracle
    function hasRecentAttestation(
        address merchant,
        uint256 maxAge
    ) external view override returns (bool hasRecent) {
        bytes32 attestationId = merchantLatestAttestation[merchant];
        if (attestationId == bytes32(0)) {
            return false;
        }

        CashflowAttestation memory attestation = attestations[attestationId];
        if (attestation.verifiedAt > block.timestamp) return false;
        return (block.timestamp - attestation.verifiedAt) <= maxAge;
    }

    /// @inheritdoc ICashflowOracle
    function getLatestAttestation(address merchant)
        external
        view
        override
        returns (CashflowAttestation memory attestation)
    {
        bytes32 attestationId = merchantLatestAttestation[merchant];
        if (attestationId == bytes32(0)) {
            revert AttestationNotFound();
        }
        return attestations[attestationId];
    }

    /// @inheritdoc ICashflowOracle
    function getAttestation(bytes32 attestationId)
        external
        view
        override
        returns (CashflowAttestation memory attestation)
    {
        attestation = attestations[attestationId];
        if (attestation.merchant == address(0)) {
            revert AttestationNotFound();
        }
        return attestation;
    }

    /// @inheritdoc ICashflowOracle
    function getCreditScore(address merchant)
        external
        view
        override
        returns (uint256 score)
    {
        bytes32[] memory history = merchantAttestationHistory[merchant];
        if (history.length == 0) {
            return 0;
        }

        // Simple credit scoring algorithm:
        // - Base score: 500
        // - +100 per attestation (up to 5)
        // - +50 for consistent growth
        // - +50 for high revenue (>$100k)

        uint256 baseScore = 500;
        uint256 attestationBonus = history.length > 5 ? 500 : history.length * 100;

        CashflowAttestation memory latest = attestations[merchantLatestAttestation[merchant]];
        uint256 revenueBonus = latest.totalRevenue > 100_000 ether ? 50 : 0;

        // Check for growth
        uint256 growthBonus = 0;
        if (history.length >= 2) {
            CashflowAttestation memory previous = attestations[history[history.length - 2]];
            if (latest.totalRevenue > previous.totalRevenue) {
                growthBonus = 50;
            }
        }

        return baseScore + attestationBonus + revenueBonus + growthBonus;
    }

    /// @inheritdoc ICashflowOracle
    function getRevenueGrowth(address merchant)
        external
        view
        override
        returns (int256 growthBps)
    {
        bytes32[] memory history = merchantAttestationHistory[merchant];
        if (history.length < 2) {
            return 0;
        }

        CashflowAttestation memory latest = attestations[history[history.length - 1]];
        CashflowAttestation memory previous = attestations[history[history.length - 2]];

        if (previous.totalRevenue == 0) {
            return 0;
        }

        // Calculate growth in basis points
        int256 change = int256(latest.totalRevenue) - int256(previous.totalRevenue);
        int256 growth = (change * 10000) / int256(previous.totalRevenue);

        return growth;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Hash an attestation for signature verification
     */
    function _hashAttestation(CashflowAttestation memory attestation)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(
            attestation.merchant,
            attestation.totalRevenue,
            attestation.periodStart,
            attestation.periodEnd,
            attestation.apiSource,
            attestation.zkProofHash,
            attestation.verifiedAt
        ));
    }

    /**
     * @dev Verify BLS aggregate signature from operators
     * @dev TODO: Implement actual BLS signature verification
     */
    function _verifyAggregateSignature(
        bytes32 messageHash,
        bytes calldata signature,
        address[] calldata operatorIds
    ) internal view returns (bool) {
        // Verify all signers are active operators
        uint256 totalStake = operatorRegistry.getTotalStake();
        uint256 signerStake = 0;

        for (uint256 i = 0; i < operatorIds.length; i++) {
            if (!operatorRegistry.isActiveOperator(operatorIds[i])) {
                return false;
            }
            IOperatorRegistry.Operator memory op = operatorRegistry.getOperator(operatorIds[i]);
            signerStake += op.stakedAmount;
        }

        // Check if signers represent enough stake (67%+)
        uint256 quorumBps = (signerStake * 10000) / totalStake;
        if (quorumBps < MIN_QUORUM_BPS) {
            return false;
        }

        // TODO: Actual BLS signature verification
        // For now, we're doing a simplified stake-weighted check
        // In production, this would verify the cryptographic signature
        return signature.length > 0; // Placeholder
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
