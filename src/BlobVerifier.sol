// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library BlobVerifier {

    // ──────────────────────────────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Address of the EIP-4844 point evaluation precompile.
    address internal constant POINT_EVALUATION_PRECOMPILE = address(0x0A);

    /// @dev Version byte prepended to KZG commitment hashes (EIP-4844 §Helpers).
    bytes1 internal constant VERSIONED_HASH_VERSION_KZG = 0x01;

    /// @dev Byte lengths for KZG G1 points (compressed).
    uint256 internal constant COMMITMENT_LENGTH = 48;
    uint256 internal constant PROOF_LENGTH = 48;

    /// @dev Number of field elements in a blob polynomial (4096).
    ///      First 32 bytes of the expected precompile output.
    bytes32 internal constant FIELD_ELEMENTS_PER_BLOB =
        bytes32(uint256(4096));

    /// @dev BLS12-381 scalar field modulus.
    ///      Second 32 bytes of the expected precompile output.
    bytes32 internal constant BLS_MODULUS =
        bytes32(uint256(52435875175126190479447740508185965837690552500527637822603658699938581184513));

    // @dev The precompile expected output on success:
    // keccak(FIELD_ELEMENTS_PER_BLOB + BLS_MODULUS)
    bytes32 internal constant POINT_EVALUATION_PRECOMPILE_OUTPUT =
        0xb2157d3a40131b14c4c675335465dffde802f0ce5218ad012284d7f275d1b37c;

    // ──────────────────────────────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────────────────────────────

    /// @notice The BLOBHASH opcode returned zero for the given index.
    /// @param blobIndex The blob index that was requested.
    error BlobNotFoundAtIndex(uint256 blobIndex);

    /// @param blobHash The blob hash that was requested.
    error BlobHashNotFound(bytes32 blobHash);

    /// @notice The versioned hash has an unexpected version byte.
    /// @param version The version byte found (expected 0x01).
    error InvalidVersionedHashVersion(bytes1 version);

    /// @notice The KZG commitment is not exactly 48 bytes.
    /// @param length The actual length provided.
    error InvalidCommitmentLength(uint256 length);

    /// @notice The point evaluation precompile returned failure.
    ///         This means the proof is invalid: the blob does NOT evaluate
    ///         to the claimed value at the given point.
    error PointEvaluationPrecompileCallFailed();

    /// @notice The KZG proof is not exactly 48 bytes.
    /// @param length The actual length provided.
    error InvalidProofLength(uint256 length);

    error InvalidPointEvaluationPrecompileOutput();

    // ──────────────────────────────────────────────────────────────────────
    //  Core functions
    // ──────────────────────────────────────────────────────────────────────

    function verifySinglePoint(
        uint256 blobIndex,
        bytes32 z,
        bytes32 y,
        bytes calldata commitment,
        bytes calldata proof
    ) internal view {
        // Retrieve the versioned hash via BLOBHASH opcode
        bytes32 versionedHash = getBlobHash(blobIndex);
        _verifySinglePoint(versionedHash, z, y, commitment, proof);
    }

    function verifySinglePoint(
        bytes32 versionedHash,
        bytes32 z,
        bytes32 y,
        bytes calldata commitment,
        bytes calldata proof
    ) internal view {
        // Check provided hash prefix
        _checkHashPrefix(versionedHash);
        // Retrieve the versioned hash via BLOBHASH opcode
        _verifySinglePoint(versionedHash, z, y, commitment, proof);
    }

    function _verifySinglePoint(
        bytes32 versionedHash,
        bytes32 z,
        bytes32 y,
        bytes calldata commitment,
        bytes calldata proof
    ) private view {
        // Validate input lengths
        if (commitment.length != COMMITMENT_LENGTH) {
            revert InvalidCommitmentLength(commitment.length);
        }
        if (proof.length != PROOF_LENGTH) {
            revert InvalidProofLength(proof.length);
        }

        (bool ok, bytes memory output) = POINT_EVALUATION_PRECOMPILE
            .staticcall(abi.encodePacked(versionedHash, z, y, commitment, proof));

        if (!ok) revert PointEvaluationPrecompileCallFailed();
        // Checks for both blob number of fields and the bls modulus
        if (keccak256(output) != POINT_EVALUATION_PRECOMPILE_OUTPUT) revert InvalidPointEvaluationPrecompileOutput();
    }

    // ──────────────────────────────────────────────────────────────────────
    //  Utility functions
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Retrieve and validate a blob's versioned hash.
    function getBlobHash(uint256 blobIndex) internal view returns (bytes32 versionedHash) {
        versionedHash = blobhash(blobIndex);

        if (versionedHash == bytes32(0)) {
            revert BlobNotFoundAtIndex(blobIndex);
        }

        _checkHashPrefix(versionedHash);
    }

    /// @notice Compute the versioned hash from a KZG commitment.
    /// @dev Matches the EIP-4844 spec: version_byte || sha256(commitment)[1:]
    ///      Useful for validating that a commitment matches a known versioned hash.
    /// @param commitment The 48-byte KZG commitment.
    /// @return versionedHash The computed versioned hash.
    function commitmentToVersionedHash(
        bytes calldata commitment
    ) internal pure returns (bytes32 versionedHash) {
        if (commitment.length != COMMITMENT_LENGTH) {
            revert InvalidCommitmentLength(commitment.length);
        }
        versionedHash = sha256(commitment);

        assembly {
            versionedHash := or(
                and(versionedHash, 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
                0x0100000000000000000000000000000000000000000000000000000000000000
            )
        }
    }

    /// @notice Find an index of a given blob hash.
    /// @param blobHash is a hash to check.
    /// @return blobIndex if `blobHash` is present among transaction blobs.
    function getBlobIndex(bytes32 blobHash) internal view returns (uint256 blobIndex) {
        while (true) {
            bytes32 blobHashAtIndex = blobhash(blobIndex);
            if (blobHashAtIndex == bytes32(0)) revert BlobHashNotFound(blobHash);
            if (blobHashAtIndex == blobHash) return blobIndex;
            blobIndex++;
        }
    }

    /// @notice Check whether a blob exists at the given index in the current transaction.
    /// @param blobIndex Index to check.
    /// @return exists True if a blob hash is available at this index.
    function blobExists(uint256 blobIndex) internal view returns (bool exists) {
        return blobhash(blobIndex) != bytes32(0);
    }

    /// @notice Count the number of blobs in the current transaction.
    /// @dev Iterates from index 0 until `blobhash` returns zero.
    /// @return count Number of blobs found.
    function blobCount() internal view returns (uint256 count) {
        while (true) {
            if (blobhash(count) == bytes32(0)) break;
            count++;
        }
    }

    function _checkHashPrefix(bytes32 blobHash) private view {
        if (versionedHash[0] != VERSIONED_HASH_VERSION_KZG) {
            revert InvalidVersionedHashVersion(versionedHash[0]);
        }
    }
}
