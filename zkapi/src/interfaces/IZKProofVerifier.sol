// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IZKProofVerifier
 * @notice Interface for verifying zkTLS proofs from Reclaim Protocol
 */
interface IZKProofVerifier {
    /// @notice Structure containing a zkTLS proof
    struct ZKProof {
        bytes32 proofHash;          // Hash of the full proof
        bytes32 tlsSessionHash;     // Hash of the TLS session
        bytes zkProofData;          // The actual ZK proof bytes
        bytes32 claimHash;          // Hash of the claimed data
        uint64 timestamp;           // When proof was generated
        string apiEndpoint;         // Which API this proof is for
    }

    /// @notice Verified claim extracted from proof
    struct VerifiedClaim {
        uint256 totalRevenue;       // Extracted revenue value
        uint256 periodStart;
        uint256 periodEnd;
        string apiSource;
        bytes32 dataHash;           // Hash of the raw API response
    }

    /// @notice Emitted when a proof is verified
    event ProofVerified(
        bytes32 indexed proofHash,
        address indexed submitter,
        uint256 totalRevenue,
        uint64 timestamp
    );

    /// @notice Emitted when a proof verification fails
    event ProofVerificationFailed(
        bytes32 indexed proofHash,
        address indexed submitter,
        string reason
    );

    /**
     * @notice Verify a zkTLS proof
     * @param proof The ZK proof to verify
     * @return isValid True if proof is valid
     * @return claim The extracted claim data
     */
    function verifyProof(ZKProof calldata proof)
        external
        returns (bool isValid, VerifiedClaim memory claim);

    /**
     * @notice Check if a proof has been used before (prevent replay attacks)
     * @param proofHash Hash of the proof
     * @return hasBeenUsed True if proof was already submitted
     */
    function isProofUsed(bytes32 proofHash) external view returns (bool hasBeenUsed);

    /**
     * @notice Verify proof is not expired
     * @param proof The proof to check
     * @param maxAge Maximum age in seconds
     * @return isValid True if proof is recent enough
     */
    function isProofRecent(ZKProof calldata proof, uint256 maxAge)
        external
        view
        returns (bool isValid);

    /**
     * @notice Get verification statistics
     * @return totalVerified Total number of proofs verified
     * @return totalRejected Total number of proofs rejected
     */
    function getVerificationStats()
        external
        view
        returns (uint256 totalVerified, uint256 totalRejected);
}
