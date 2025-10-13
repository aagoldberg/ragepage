// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICashflowOracle
 * @notice Interface for querying verified cashflow data from the ZK API Oracle
 * @dev This is the main interface your social loan protocol will interact with
 */
interface ICashflowOracle {
    /// @notice Structure containing verified cashflow data
    struct CashflowAttestation {
        address merchant;           // Address of the merchant
        uint256 totalRevenue;       // Total revenue in wei (or smallest unit)
        uint256 periodStart;        // Unix timestamp of period start
        uint256 periodEnd;          // Unix timestamp of period end
        string apiSource;           // Source API: "shopify", "square", "plaid"
        bytes32 zkProofHash;        // Hash of the zkTLS proof
        uint64 verifiedAt;          // When attestation was verified on-chain
        uint32 quorumBps;           // Basis points of operator consensus (10000 = 100%)
    }

    /// @notice Emitted when a new cashflow attestation is verified
    event AttestationVerified(
        bytes32 indexed attestationId,
        address indexed merchant,
        uint256 totalRevenue,
        string apiSource,
        uint64 verifiedAt
    );

    /// @notice Emitted when an attestation is disputed
    event AttestationDisputed(
        bytes32 indexed attestationId,
        address indexed disputer,
        string reason
    );

    /**
     * @notice Get verified revenue for a merchant within a time period
     * @param merchant The merchant's address
     * @param startTimestamp Start of the revenue period
     * @param endTimestamp End of the revenue period
     * @return totalRevenue The verified total revenue
     * @return verifiedAt Timestamp when this was verified on-chain
     * @return source The data source (e.g., "shopify")
     */
    function getVerifiedRevenue(
        address merchant,
        uint256 startTimestamp,
        uint256 endTimestamp
    ) external view returns (
        uint256 totalRevenue,
        uint64 verifiedAt,
        string memory source
    );

    /**
     * @notice Check if merchant has recent verified cashflow data
     * @param merchant The merchant's address
     * @param maxAge Maximum age of attestation in seconds
     * @return hasRecent True if merchant has attestation newer than maxAge
     */
    function hasRecentAttestation(
        address merchant,
        uint256 maxAge
    ) external view returns (bool hasRecent);

    /**
     * @notice Get the most recent attestation for a merchant
     * @param merchant The merchant's address
     * @return attestation The full attestation struct
     */
    function getLatestAttestation(address merchant)
        external
        view
        returns (CashflowAttestation memory attestation);

    /**
     * @notice Get a specific attestation by its ID
     * @param attestationId The unique ID of the attestation
     * @return attestation The full attestation struct
     */
    function getAttestation(bytes32 attestationId)
        external
        view
        returns (CashflowAttestation memory attestation);

    /**
     * @notice Calculate a credit score based on cashflow history
     * @dev Score is 0-1000, higher is better
     * @param merchant The merchant's address
     * @return score Credit score based on verified cashflow
     */
    function getCreditScore(address merchant)
        external
        view
        returns (uint256 score);

    /**
     * @notice Get merchant's revenue growth rate
     * @dev Compares most recent period to previous period
     * @param merchant The merchant's address
     * @return growthBps Growth rate in basis points (100 = 1% growth)
     */
    function getRevenueGrowth(address merchant)
        external
        view
        returns (int256 growthBps);
}
