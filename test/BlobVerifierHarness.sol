// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BlobVerifier} from "../src/BlobVerifier.sol";

/// @dev Thin wrapper that exposes BlobVerifier's internal functions for testing.
contract BlobVerifierHarness {
    using BlobVerifier for *;

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

    function getBlobHash(uint256 blobIndex) external view returns (bytes32) {
        return BlobVerifier.getBlobHash(blobIndex);
    }

    function commitmentToVersionedHash(
        bytes calldata commitment
    ) external pure returns (bytes32) {
        return BlobVerifier.commitmentToVersionedHash(commitment);
    }

    function getBlobIndex(bytes32 blobHash) external view returns (uint256) {
        return BlobVerifier.getBlobIndex(blobHash);
    }

    function blobExists(uint256 blobIndex) external view returns (bool) {
        return BlobVerifier.blobExists(blobIndex);
    }

    function blobCount() external view returns (uint256) {
        return BlobVerifier.blobCount();
    }

    /// @dev Expose constants for test assertions
    function FIELD_ELEMENTS_PER_BLOB() external pure returns (bytes32) {
        return BlobVerifier.FIELD_ELEMENTS_PER_BLOB;
    }

    function BLS_MODULUS() external pure returns (bytes32) {
        return BlobVerifier.BLS_MODULUS;
    }

    function POINT_EVALUATION_PRECOMPILE_OUTPUT() external pure returns (bytes32) {
        return BlobVerifier.POINT_EVALUATION_PRECOMPILE_OUTPUT;
    }
}
