// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {BlobVerifier} from "../../src/BlobVerifier.sol";
import {Bls12381} from "../../src/Bls12381.sol";

/// @dev Exposes the pure parts of the batched verifiers (challenge derivation, transcript seeds,
///      MSM buffer builders, encoding checks) for symbolic execution. None of them touches a
///      precompile, so Halmos can reason about them for all inputs.
contract SymbolicHarness {
    function challengeScalar(bytes32 seed, uint256 i) external pure returns (uint256) {
        return BlobVerifier._challengeScalar(seed, i, BlobVerifier.BLS_MODULUS);
    }

    function seedSharedC(
        bytes32 blobHash,
        bytes32[] calldata zs,
        bytes32[] calldata ys,
        bytes calldata commitment,
        bytes[] calldata proofs
    ) external pure returns (bytes32) {
        return BlobVerifier._challengeSeed128(blobHash, zs, ys, commitment, proofs);
    }

    function seedSharedZ(
        bytes32[] calldata blobHashes,
        bytes32 z,
        bytes32[] calldata ys,
        bytes[] calldata commitments,
        bytes[] calldata proofs
    ) external pure returns (bytes32) {
        return BlobVerifier._challengeSeed128(blobHashes, z, ys, commitments, proofs);
    }

    function seedGeneral(
        bytes32[] calldata blobHashes,
        bytes32[] calldata zs,
        bytes32[] calldata ys,
        bytes[] calldata commitments,
        bytes[] calldata proofs
    ) external pure returns (bytes32) {
        return BlobVerifier._challengeSeed128(blobHashes, zs, ys, commitments, proofs);
    }

    function sharedCMsmInputs(
        bytes32 seed,
        bytes32[] calldata zs,
        bytes32[] calldata ys,
        bytes calldata commitment,
        bytes[] calldata proofs
    ) external pure returns (bytes memory, bytes memory) {
        return BlobVerifier._sharedCMsmInputs(seed, zs, ys, commitment, proofs);
    }

    function sharedZMsmInputs(
        bytes32 seed,
        bytes32 z,
        bytes32[] calldata ys,
        bytes[] calldata commitments,
        bytes[] calldata proofs
    ) external pure returns (bytes memory, bytes memory) {
        return BlobVerifier._sharedZMsmInputs(seed, z, ys, commitments, proofs);
    }

    function generalMsmInputs(
        bytes32 seed,
        bytes32[] calldata zs,
        bytes32[] calldata ys,
        bytes[] calldata commitments,
        bytes[] calldata proofs
    ) external pure returns (bytes memory, bytes memory) {
        return BlobVerifier._generalMsmInputs(seed, zs, ys, commitments, proofs);
    }

    function requireCanonical(bytes calldata point) external pure {
        Bls12381.requireCanonical(point);
    }

    function compress(bytes calldata point) external pure returns (bytes memory) {
        return Bls12381.compress(point);
    }
}
