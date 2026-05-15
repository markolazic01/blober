// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title LoopVerifier
/// @notice Reference port of the industry-standard EIP-4844 verification loop
///         deployed by major production rollups today: one call to the 0x0A
///         point-evaluation precompile per blob, looped across all blobs.
/// @dev    Pure benchmarking surface — exposed as an external function for
///         direct gas comparison against the EIP-2537 batched verifier in
///         `BlobVerifier.verifySinglePointMultipleBlobs128`.
///
///         Inputs match the batched function's contract: caller provides the
///         versioned hashes directly (rather than via BLOBHASH) so the gas
///         comparison reflects only the verification path, not blob-attachment
///         plumbing.
contract LoopVerifier {
    address internal constant POINT_EVALUATION_PRECOMPILE = address(0x0A);

    /// keccak256(abi.encodePacked(uint256(4096), BLS_MODULUS)) — the canonical
    /// success-output hash documented in EIP-4844.
    bytes32 internal constant POINT_EVALUATION_OUTPUT_HASH =
        0xb2157d3a40131b14c4c675335465dffde802f0ce5218ad012284d7f275d1b37c;

    bytes1 internal constant VERSIONED_HASH_VERSION_KZG = 0x01;
    uint256 internal constant COMMITMENT_LENGTH = 48;
    uint256 internal constant PROOF_LENGTH = 48;

    error InvalidBlobHashVersion(bytes1 version);
    error InvalidCommitmentLength(uint256 length);
    error InvalidProofLength(uint256 length);
    error ArrayLengthMismatch();
    error PrecompileCallFailed();
    error UnexpectedPrecompileOutput();

    /// @notice Verify N blobs at a shared z by looping 0x0A per blob.
    /// @param  blobHashes   Versioned hashes (32 bytes each).
    /// @param  z            Shared evaluation point.
    /// @param  y            One claimed value per blob.
    /// @param  commitments  Compressed KZG commitments (48 bytes each).
    /// @param  proofs       Compressed KZG opening proofs (48 bytes each).
    function verifyLoop(
        bytes32[] calldata blobHashes,
        bytes32 z,
        bytes32[] calldata y,
        bytes[] calldata commitments,
        bytes[] calldata proofs
    ) external view {
        uint256 n = blobHashes.length;
        if (n != y.length || n != commitments.length || n != proofs.length) revert ArrayLengthMismatch();

        for (uint256 i; i < n; ++i) {
            bytes32 vHash = blobHashes[i];
            if (vHash[0] != VERSIONED_HASH_VERSION_KZG) revert InvalidBlobHashVersion(vHash[0]);
            if (commitments[i].length != COMMITMENT_LENGTH) revert InvalidCommitmentLength(commitments[i].length);
            if (proofs[i].length != PROOF_LENGTH) revert InvalidProofLength(proofs[i].length);

            (bool ok, bytes memory output) =
                POINT_EVALUATION_PRECOMPILE.staticcall(abi.encodePacked(vHash, z, y[i], commitments[i], proofs[i]));
            if (!ok) revert PrecompileCallFailed();
            if (keccak256(output) != POINT_EVALUATION_OUTPUT_HASH) revert UnexpectedPrecompileOutput();
        }
    }

    /// @notice Verify N openings of a single blob (multi-point) by looping 0x0A per opening.
    /// @dev    Same blob commitment + blobHash for every iteration; only z, y, proof vary.
    function verifyLoopMultiPoint(
        bytes32 blobHash,
        bytes32[] calldata z,
        bytes32[] calldata y,
        bytes calldata commitment,
        bytes[] calldata proofs
    ) external view {
        uint256 n = z.length;
        if (n != y.length || n != proofs.length) revert ArrayLengthMismatch();
        if (blobHash[0] != VERSIONED_HASH_VERSION_KZG) revert InvalidBlobHashVersion(blobHash[0]);
        if (commitment.length != COMMITMENT_LENGTH) revert InvalidCommitmentLength(commitment.length);

        for (uint256 i; i < n; ++i) {
            if (proofs[i].length != PROOF_LENGTH) revert InvalidProofLength(proofs[i].length);

            (bool ok, bytes memory output) =
                POINT_EVALUATION_PRECOMPILE.staticcall(abi.encodePacked(blobHash, z[i], y[i], commitment, proofs[i]));
            if (!ok) revert PrecompileCallFailed();
            if (keccak256(output) != POINT_EVALUATION_OUTPUT_HASH) revert UnexpectedPrecompileOutput();
        }
    }
}
