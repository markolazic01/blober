// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library BlobVerifier {

    // ──────────────────────────────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Version byte prepended to KZG commitment hashes (EIP-4844 §Helpers).
    bytes1 internal constant VERSIONED_HASH_VERSION_KZG = 0x01;

    /// @dev Byte lengths for KZG G1 points (compressed).
    uint256 internal constant COMMITMENT_LENGTH = 48;
    uint256 internal constant PROOF_LENGTH = 48;

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

    // ──────────────────────────────────────────────────────────────────────
    //  Utility functions
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Retrieve and validate a blob's versioned hash.
    function getBlobHash(uint256 blobIndex) internal view returns (bytes32 versionedHash) {
        versionedHash = blobhash(blobIndex);

        if (versionedHash == bytes32(0)) {
            revert BlobNotFoundAtIndex(blobIndex);
        }

        if (versionedHash[0] != VERSIONED_HASH_VERSION_KZG) {
            revert InvalidVersionedHashVersion(versionedHash[0]);
        }
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
            bytes32 blobHashAtIndex = blobhash(blobIndex++);
            if (blobHashAtIndex == bytes32(0)) revert BlobHashNotFound(blobHash);
            if (blobHashAtIndex == blobHash) return blobIndex;
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
            if (blobhash(count++) == bytes32(0)) break;
        }
    }
}
