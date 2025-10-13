// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IZKProofVerifier.sol";

/**
 * @title ZKProofVerifier
 * @notice Verifies zkTLS proofs from Reclaim Protocol
 * @dev Integrates with Reclaim Protocol via interface for version compatibility
 *
 * The Reclaim Protocol SDK uses Solidity 0.8.4, while our contracts use ^0.8.20.
 * We interact with Reclaim through low-level calls to maintain compatibility.
 */
contract ZKProofVerifier is IZKProofVerifier {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of used proof hashes (prevent replay attacks)
    mapping(bytes32 => bool) public proofUsed;

    /// @notice Statistics
    uint256 public totalProofsVerified;
    uint256 public totalProofsRejected;

    /// @notice Trusted verifier addresses (for MVP)
    mapping(address => bool) public trustedVerifiers;

    /// @notice Owner
    address public owner;

    /// @notice Reclaim Protocol contract address
    address public reclaimAddress;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param _reclaimAddress Address of deployed Reclaim Protocol contract
     * @dev Use addresses from @reclaimprotocol/verifier-solidity-sdk/contracts/Addresses.sol
     * @dev Pass address(0) for MVP/testing mode (proofs won't be verified)
     */
    constructor(address _reclaimAddress) {
        owner = msg.sender;
        reclaimAddress = _reclaimAddress;
    }

    /*//////////////////////////////////////////////////////////////
                        VERIFICATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IZKProofVerifier
    function verifyProof(ZKProof calldata proof)
        external
        override
        returns (bool isValid, VerifiedClaim memory claim)
    {
        // 1. Check proof hasn't been used
        if (proofUsed[proof.proofHash]) {
            totalProofsRejected++;
            emit ProofVerificationFailed(proof.proofHash, msg.sender, "Proof already used");
            return (false, claim);
        }

        // 2. Check proof is recent (not expired)
        if (block.timestamp - proof.timestamp > 2 hours) {
            totalProofsRejected++;
            emit ProofVerificationFailed(proof.proofHash, msg.sender, "Proof expired");
            return (false, claim);
        }

        // 3. Verify the zkTLS proof
        // TODO: Integrate actual Reclaim Protocol verifier
        // For MVP, we'll do a simplified verification
        isValid = _verifyReclaimProof(proof);

        if (!isValid) {
            totalProofsRejected++;
            emit ProofVerificationFailed(proof.proofHash, msg.sender, "Invalid ZK proof");
            return (false, claim);
        }

        // 4. Extract claim from proof
        claim = _extractClaim(proof);

        // 5. Mark proof as used
        proofUsed[proof.proofHash] = true;
        totalProofsVerified++;

        emit ProofVerified(proof.proofHash, msg.sender, claim.totalRevenue, proof.timestamp);

        return (true, claim);
    }

    /// @inheritdoc IZKProofVerifier
    function isProofUsed(bytes32 proofHash) external view override returns (bool hasBeenUsed) {
        return proofUsed[proofHash];
    }

    /// @inheritdoc IZKProofVerifier
    function isProofRecent(ZKProof calldata proof, uint256 maxAge)
        external
        view
        override
        returns (bool isValid)
    {
        return (block.timestamp - proof.timestamp) <= maxAge;
    }

    /// @inheritdoc IZKProofVerifier
    function getVerificationStats()
        external
        view
        override
        returns (uint256 verified, uint256 rejected)
    {
        return (totalProofsVerified, totalProofsRejected);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Verify Reclaim Protocol ZK proof
     * @dev Calls the Reclaim contract to cryptographically verify the proof
     * @param proof Our ZKProof struct containing encoded Reclaim proof
     * @return bool True if proof is valid
     */
    function _verifyReclaimProof(ZKProof calldata proof) internal view returns (bool) {
        // Basic sanity checks
        if (proof.proofHash == bytes32(0)) return false;
        if (proof.zkProofData.length == 0) return false;
        if (bytes(proof.apiEndpoint).length == 0) return false;

        // If no Reclaim address is set, return false
        if (reclaimAddress == address(0)) {
            return false;
        }

        // Call Reclaim's verifyProof function via low-level call
        // This maintains compatibility across Solidity versions
        // Function signature: verifyProof(Proof memory proof)
        bytes4 selector = bytes4(keccak256("verifyProof((((bytes32,address,uint32,uint32),bytes[]),(string,string,string)))"));

        (bool success,) = reclaimAddress.staticcall(
            abi.encodeWithSelector(selector, proof.zkProofData)
        );

        // Reclaim.verifyProof() reverts on failure, succeeds silently on success
        return success;
    }

    /**
     * @dev Extract claim data from ZK proof
     * @dev In production, this would parse the proof output
     */
    function _extractClaim(ZKProof calldata proof)
        internal
        pure
        returns (VerifiedClaim memory claim)
    {
        // TODO: Parse actual proof data structure
        // For now, we'll encode the claim in the claimHash
        // In production, this would extract from zkProofData

        // Placeholder extraction
        claim = VerifiedClaim({
            totalRevenue: 0, // Would be extracted from proof
            periodStart: proof.timestamp - 90 days, // Example
            periodEnd: proof.timestamp,
            apiSource: proof.apiEndpoint,
            dataHash: proof.claimHash
        });

        return claim;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add trusted verifier (for MVP phase)
     */
    function addTrustedVerifier(address verifier) external onlyOwner {
        trustedVerifiers[verifier] = true;
    }

    /**
     * @notice Remove trusted verifier
     */
    function removeTrustedVerifier(address verifier) external onlyOwner {
        trustedVerifiers[verifier] = false;
    }

    /**
     * @notice Manual proof verification (for testing/MVP)
     * @dev Allows owner to manually verify proofs during testing phase
     */
    function manualVerifyProof(
        bytes32 proofHash,
        VerifiedClaim calldata claim
    ) external onlyOwner {
        require(!proofUsed[proofHash], "Proof already used");

        proofUsed[proofHash] = true;
        totalProofsVerified++;

        emit ProofVerified(proofHash, msg.sender, claim.totalRevenue, uint64(block.timestamp));
    }

    /**
     * @notice Update Reclaim contract address
     * @dev Allows updating if Reclaim deploys new version
     */
    function updateReclaimAddress(address _reclaimAddress) external onlyOwner {
        require(_reclaimAddress != address(0), "Invalid Reclaim address");
        reclaimAddress = _reclaimAddress;
    }
}
