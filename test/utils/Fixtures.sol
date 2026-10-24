// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {BlobVerifier} from "../../src/BlobVerifier.sol";
import {Bls12381} from "../../src/Bls12381.sol";
import {BlobVerifierHarness} from "../BlobVerifierHarness.sol";

/// @dev Shared fixture loading for the 128-byte verifiers. Every fixture is loaded into one
///      general-shape `Batch` (one entry per claim); shape-specific callers read `z[0]` or
///      `commitments[0]` when the shape shares that value.
abstract contract Fixtures is Test {
    BlobVerifierHarness internal harness;

    struct Batch {
        bytes32[] hashes;
        bytes32[] z;
        bytes32[] y;
        bytes[] commitments;
        bytes[] proofs;
    }

    uint256 internal constant Q = BlobVerifier.BLS_MODULUS;

    /// @dev BLS12-381 base field modulus p, as the 48-byte big-endian value used in encodings.
    bytes internal constant P_BYTES =
        hex"1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab";

    function setUp() public virtual {
        harness = new BlobVerifierHarness();
    }

    // ── Loaders ─────────────────────────────────────────────────────────

    /// @dev multi_blob_multi_point_128: every value per claim.
    function _general(string memory name) internal view returns (Batch memory b) {
        string memory j = _read(name);
        b.commitments = vm.parseJsonBytesArray(j, ".commitments");
        b.z = vm.parseJsonBytes32Array(j, ".z");
        b.y = vm.parseJsonBytes32Array(j, ".y");
        b.proofs = vm.parseJsonBytesArray(j, ".proofs");
        b.hashes = _hashesFor(b.commitments);
    }

    /// @dev multi_blob_one_point_* and infinity_128: one shared z, broadcast to every claim.
    function _sharedZ(string memory name) internal view returns (Batch memory b) {
        string memory j = _read(name);
        b.commitments = vm.parseJsonBytesArray(j, ".commitments");
        b.y = vm.parseJsonBytes32Array(j, ".y");
        b.proofs = vm.parseJsonBytesArray(j, ".proofs");
        b.z = _fill(vm.parseJsonBytes32(j, ".z"), b.y.length);
        b.hashes = _hashesFor(b.commitments);
    }

    /// @dev multi_point_one_blob_128: one shared commitment, broadcast to every claim.
    function _oneBlob(string memory name) internal view returns (Batch memory b) {
        string memory j = _read(name);
        bytes memory c = vm.parseJsonBytes(j, ".commitment");
        b.z = vm.parseJsonBytes32Array(j, ".z");
        b.y = vm.parseJsonBytes32Array(j, ".y");
        b.proofs = vm.parseJsonBytesArray(j, ".proofs");
        b.commitments = new bytes[](b.y.length);
        for (uint256 i; i < b.y.length; ++i) {
            b.commitments[i] = c;
        }
        b.hashes = _hashesFor(b.commitments);
    }

    // ── Shape adapters ──────────────────────────────────────────────────

    /// @dev The first `n` claims of `b`, cycling when n > length (a repeated claim is a valid claim).
    function _take(Batch memory b, uint256 n) internal pure returns (Batch memory out) {
        out.hashes = new bytes32[](n);
        out.z = new bytes32[](n);
        out.y = new bytes32[](n);
        out.commitments = new bytes[](n);
        out.proofs = new bytes[](n);
        uint256 len = b.y.length;
        for (uint256 i; i < n; ++i) {
            out.hashes[i] = b.hashes[i % len];
            out.z[i] = b.z[i % len];
            out.y[i] = b.y[i % len];
            out.commitments[i] = bytes.concat(b.commitments[i % len]);
            out.proofs[i] = bytes.concat(b.proofs[i % len]);
        }
    }

    // ── Calls by shape (wrapper, loop path, batched path) ────────────────

    function _callSharedZ(Batch memory b) internal view {
        harness.verifySinglePointMultipleBlobs128(b.hashes, b.z[0], b.y, b.commitments, b.proofs);
    }

    function _callOneBlob(Batch memory b) internal view {
        harness.verifyMultiplePoints128(b.hashes[0], b.z, b.y, b.commitments[0], b.proofs);
    }

    function _callGeneral(Batch memory b) internal view {
        harness.verifyMultiplePointsMultipleBlobs128(b.hashes, b.z, b.y, b.commitments, b.proofs);
    }

    // ── Byte helpers ────────────────────────────────────────────────────

    function _hashesFor(bytes[] memory commitments) internal pure returns (bytes32[] memory hashes) {
        hashes = new bytes32[](commitments.length);
        for (uint256 i; i < commitments.length; ++i) {
            hashes[i] = BlobVerifier.commitmentToVersionedHash(Bls12381.compress(commitments[i]));
        }
    }

    function _fill(bytes32 v, uint256 n) internal pure returns (bytes32[] memory out) {
        out = new bytes32[](n);
        for (uint256 i; i < n; ++i) {
            out[i] = v;
        }
    }

    /// @dev Copy of `point` with byte `i` XOR-ed with `mask` (mask must be non-zero to change it).
    function _flip(bytes memory point, uint256 i, bytes1 mask) internal pure returns (bytes memory out) {
        out = bytes.concat(point);
        out[i] = out[i] ^ mask;
    }

    /// @dev Copy of `point` with its x coordinate (bytes 16..64) replaced by p: canonical padding,
    ///      non-canonical value.
    function _xEqualsP(bytes memory point) internal pure returns (bytes memory out) {
        out = bytes.concat(point);
        for (uint256 i; i < 48; ++i) {
            out[16 + i] = P_BYTES[i];
        }
    }

    function _read(string memory name) private view returns (string memory) {
        return vm.readFile(string.concat("test/fixtures/", name, ".json"));
    }
}
