// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Fixtures} from "./utils/Fixtures.sol";

/// @notice Property I4 of the verification plan: for every input, the 0x0A loop and the batched
///         pairing accept or reject together. Each run takes a valid fixture batch, applies at most
///         one mutation, and runs both halves of the same verifier on the result. (The batched
///         path may also accept an invalid batch with probability 1/q, which a fuzzer cannot reach.)
contract PathEquivalenceTest is Fixtures {
    uint256 constant MUTATIONS = 10;

    /// @dev Apply mutation `kind` to claim `i` of `b`. Mutations are chosen to cover every way an
    ///      input can be wrong: point bytes (padding, x, y, flags), scalars in and out of range,
    ///      swapped or replaced points, infinity, and the versioned hash.
    function _mutate(Batch memory b, uint256 kind, uint256 i, uint256 offset, bytes32 value) internal pure {
        uint256 n = b.y.length;
        i = i % n;
        bytes1 mask = bytes1(uint8(bound(uint256(value), 1, 255)));
        if (kind == 1) {
            b.proofs[i] = _flip(b.proofs[i], offset % 128, mask);
        } else if (kind == 2) {
            b.commitments[i] = _flip(b.commitments[i], offset % 128, mask);
        } else if (kind == 3) {
            unchecked {
                b.y[i] = bytes32(uint256(b.y[i]) + 1 + (uint256(value) % 1024));
            }
        } else if (kind == 4) {
            b.y[i] = value; // anywhere in [0, 2^256): mostly out of range
        } else if (kind == 5) {
            b.z[i] = value;
        } else if (kind == 6) {
            uint256 j = (i + 1) % n;
            (b.proofs[i], b.proofs[j]) = (b.proofs[j], b.proofs[i]);
        } else if (kind == 7) {
            b.proofs[i] = new bytes(128);
        } else if (kind == 8) {
            b.commitments[i] = bytes.concat(b.commitments[(i + 1) % n]); // binds to the wrong hash
        } else if (kind == 9) {
            b.hashes[i] = value;
        }
        // kind 0: unchanged
    }

    // ── Many blobs, one shared point ────────────────────────────────────

    function _sharedZOutcomes(Batch memory b) internal view returns (bool loopOk, bool batchedOk) {
        try harness.verifySinglePointMultipleBlobs128Loop(b.hashes, b.z[0], b.y, b.commitments, b.proofs) {
            loopOk = true;
        } catch {}
        try harness.verifySinglePointMultipleBlobs128Batched(b.hashes, b.z[0], b.y, b.commitments, b.proofs) {
            batchedOk = true;
        } catch {}
    }

    function testFuzz_pathEquivalence_sharedZ(uint256 kind, uint256 i, uint256 offset, bytes32 value) public view {
        Batch memory b = _sharedZ("multi_blob_one_point_z1_128");
        kind = kind % MUTATIONS;
        // The shared shape has one z: a z mutation moves it for every claim.
        if (kind == 5) b.z = _fill(value, b.y.length);
        else _mutate(b, kind, i, offset, value);

        (bool loopOk, bool batchedOk) = _sharedZOutcomes(b);
        assertEq(loopOk, batchedOk, "loop and batched paths disagree");
        if (kind == 0) assertTrue(loopOk, "unmutated batch must verify");
    }

    // ── One blob, many points ───────────────────────────────────────────

    function _oneBlobOutcomes(Batch memory b) internal view returns (bool loopOk, bool batchedOk) {
        try harness.verifyMultiplePoints128Loop(b.hashes[0], b.z, b.y, b.commitments[0], b.proofs) {
            loopOk = true;
        } catch {}
        try harness.verifyMultiplePoints128Batched(b.hashes[0], b.z, b.y, b.commitments[0], b.proofs) {
            batchedOk = true;
        } catch {}
    }

    function testFuzz_pathEquivalence_oneBlob(uint256 kind, uint256 i, uint256 offset, bytes32 value) public view {
        Batch memory b = _oneBlob("multi_point_one_blob_128");
        kind = kind % MUTATIONS;
        // The one-blob shape has one commitment and one hash: those mutations apply to claim 0,
        // which is the only commitment the verifier reads. Swapping in another commitment is
        // replaced by flipping a byte of it.
        if (kind == 8) kind = 2;
        if (kind == 2 || kind == 9) i = 0;
        _mutate(b, kind, i, offset, value);

        (bool loopOk, bool batchedOk) = _oneBlobOutcomes(b);
        assertEq(loopOk, batchedOk, "loop and batched paths disagree");
        if (kind == 0) assertTrue(loopOk, "unmutated batch must verify");
    }

    // ── General shape ───────────────────────────────────────────────────

    function _generalOutcomes(Batch memory b) internal view returns (bool loopOk, bool batchedOk) {
        try harness.verifyMultiplePointsMultipleBlobs128Loop(b.hashes, b.z, b.y, b.commitments, b.proofs) {
            loopOk = true;
        } catch {}
        try harness.verifyMultiplePointsMultipleBlobs128Batched(b.hashes, b.z, b.y, b.commitments, b.proofs) {
            batchedOk = true;
        } catch {}
    }

    function testFuzz_pathEquivalence_general(uint256 kind, uint256 i, uint256 offset, bytes32 value) public view {
        Batch memory b = _general("multi_blob_multi_point_128");
        kind = kind % MUTATIONS;
        _mutate(b, kind, i, offset, value);

        (bool loopOk, bool batchedOk) = _generalOutcomes(b);
        assertEq(loopOk, batchedOk, "loop and batched paths disagree");
        if (kind == 0) assertTrue(loopOk, "unmutated batch must verify");
    }
}
