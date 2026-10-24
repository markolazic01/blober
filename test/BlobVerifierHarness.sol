// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {BlobVerifier} from "../src/BlobVerifier.sol";
import {Bls12381} from "../src/Bls12381.sol";

/// @dev Thin wrapper that exposes BlobVerifier's internal functions for testing.
contract BlobVerifierHarness {
    using BlobVerifier for *;

    function verifySinglePointMultipleBlobs(
        bytes32[] calldata blobHashes,
        bytes32 z,
        bytes32[] calldata y_coordinates,
        bytes[] calldata commitments,
        bytes[] calldata proofs
    ) external view {
        BlobVerifier.verifySinglePointMultipleBlobs(blobHashes, z, y_coordinates, commitments, proofs);
    }

    function verifyMultiplePoints(
        bytes32 blobHash,
        bytes32[] calldata z_coordinates,
        bytes32[] calldata y_coordinates,
        bytes calldata commitment,
        bytes[] calldata proofs
    ) external view {
        BlobVerifier.verifyMultiplePoints(blobHash, z_coordinates, y_coordinates, commitment, proofs);
    }

    function verifySinglePointByIndex(
        uint256 blobIndex,
        bytes32 z,
        bytes32 y,
        bytes calldata commitment,
        bytes calldata proof
    ) external view {
        BlobVerifier.verifySinglePoint(blobIndex, z, y, commitment, proof);
    }

    function verifySinglePointByHash(
        bytes32 versionedHash,
        bytes32 z,
        bytes32 y,
        bytes calldata commitment,
        bytes calldata proof
    ) external view {
        BlobVerifier.verifySinglePoint(versionedHash, z, y, commitment, proof);
    }

    function verifyMultiplePoints128(
        bytes32 blobHash,
        bytes32[] calldata z_coordinates,
        bytes32[] calldata y_coordinates,
        bytes calldata commitment,
        bytes[] calldata proofs
    ) external view {
        BlobVerifier.verifyMultiplePoints128(blobHash, z_coordinates, y_coordinates, commitment, proofs);
    }

    function verifySinglePointMultipleBlobs128(
        bytes32[] calldata blobHashes,
        bytes32 z,
        bytes32[] calldata y_coordinates,
        bytes[] calldata commitments,
        bytes[] calldata proofs
    ) external view {
        BlobVerifier.verifySinglePointMultipleBlobs128(blobHashes, z, y_coordinates, commitments, proofs);
    }

    function verifyMultiplePointsMultipleBlobs128(
        bytes32[] calldata blobHashes,
        bytes32[] calldata z_coordinates,
        bytes32[] calldata y_coordinates,
        bytes[] calldata commitments,
        bytes[] calldata proofs
    ) external view {
        BlobVerifier.verifyMultiplePointsMultipleBlobs128(blobHashes, z_coordinates, y_coordinates, commitments, proofs);
    }

    // ── Path-level entry points: the loop and batched halves of each *128 verifier, so tests can
    //    run both on the same input (array shapes must already be valid).

    function verifyMultiplePoints128Loop(
        bytes32 blobHash,
        bytes32[] calldata z_coordinates,
        bytes32[] calldata y_coordinates,
        bytes calldata commitment,
        bytes[] calldata proofs
    ) external view {
        BlobVerifier._verifyMultiplePoints128Loop(blobHash, z_coordinates, y_coordinates, commitment, proofs);
    }

    function verifyMultiplePoints128Batched(
        bytes32 blobHash,
        bytes32[] calldata z_coordinates,
        bytes32[] calldata y_coordinates,
        bytes calldata commitment,
        bytes[] calldata proofs
    ) external view {
        BlobVerifier._verifyMultiplePoints128Batched(blobHash, z_coordinates, y_coordinates, commitment, proofs);
    }

    function verifySinglePointMultipleBlobs128Loop(
        bytes32[] calldata blobHashes,
        bytes32 z,
        bytes32[] calldata y_coordinates,
        bytes[] calldata commitments,
        bytes[] calldata proofs
    ) external view {
        BlobVerifier._verifySinglePointMultipleBlobs128Loop(blobHashes, z, y_coordinates, commitments, proofs);
    }

    function verifySinglePointMultipleBlobs128Batched(
        bytes32[] calldata blobHashes,
        bytes32 z,
        bytes32[] calldata y_coordinates,
        bytes[] calldata commitments,
        bytes[] calldata proofs
    ) external view {
        BlobVerifier._verifySinglePointMultipleBlobs128Batched(blobHashes, z, y_coordinates, commitments, proofs);
    }

    function verifyMultiplePointsMultipleBlobs128Loop(
        bytes32[] calldata blobHashes,
        bytes32[] calldata z_coordinates,
        bytes32[] calldata y_coordinates,
        bytes[] calldata commitments,
        bytes[] calldata proofs
    ) external view {
        BlobVerifier._verifyMultiplePointsMultipleBlobs128Loop(
            blobHashes, z_coordinates, y_coordinates, commitments, proofs
        );
    }

    function verifyMultiplePointsMultipleBlobs128Batched(
        bytes32[] calldata blobHashes,
        bytes32[] calldata z_coordinates,
        bytes32[] calldata y_coordinates,
        bytes[] calldata commitments,
        bytes[] calldata proofs
    ) external view {
        BlobVerifier._verifyMultiplePointsMultipleBlobs128Batched(
            blobHashes, z_coordinates, y_coordinates, commitments, proofs
        );
    }

    // ── Bls12381 wrappers

    function g1Add(bytes calldata a, bytes calldata b) external view returns (bytes memory) {
        return Bls12381.g1Add(a, b);
    }

    function g1Msm(bytes[] calldata points, bytes32[] calldata scalars) external view returns (bytes memory) {
        return Bls12381.g1Msm(points, scalars);
    }

    function compress(bytes calldata uncompressed) external pure returns (bytes memory) {
        return Bls12381.compress(uncompressed);
    }

    function requireCanonical(bytes calldata point) external pure {
        Bls12381.requireCanonical(point);
    }

    function requireOnCurve(bytes calldata point) external view {
        Bls12381.requireOnCurve(point);
    }

    function getBlobHash(uint256 blobIndex) external view returns (bytes32) {
        return BlobVerifier.getBlobHash(blobIndex);
    }

    function commitmentToVersionedHash(bytes calldata commitment) external pure returns (bytes32) {
        return BlobVerifier.commitmentToVersionedHash(commitment);
    }

    function getBlobIndex(bytes32 blobHash) external view returns (uint256) {
        return BlobVerifier.getBlobIndex(blobHash);
    }

    function blobExists(uint256 blobIndex) external view returns (bool) {
        return BlobVerifier.blobExists(blobIndex);
    }

    function blobCount() external view returns (uint256) {
        return BlobVerifier.getBlobCount();
    }

    /// @dev Expose constants for test assertions
    // function FIELD_ELEMENTS_PER_BLOB() external pure returns (bytes32) {
    //     return BlobVerifier.FIELD_ELEMENTS_PER_BLOB;
    // }

    function BLS_MODULUS() external pure returns (uint256) {
        return BlobVerifier.BLS_MODULUS;
    }

    function POINT_EVALUATION_PRECOMPILE_OUTPUT() external pure returns (bytes32) {
        return BlobVerifier.POINT_EVALUATION_PRECOMPILE_OUTPUT;
    }
}
