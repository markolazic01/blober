// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {BlobVerifier} from "../src/BlobVerifier.sol";
import {Bls12381} from "../src/Bls12381.sol";
import {Fixtures} from "./utils/Fixtures.sol";

/// @notice Malformed 128-byte points. Before the encoding checks, the 0x0A fallback accepted
///         non-zero padding and off-curve points (compression reads only x and the sign of y),
///         while the batched path rejected them and burned all forwarded gas.
contract BlobVerifierEncodingTest is Fixtures {
    /// @dev Last byte of y: flipping its low bit keeps y < p and the sign of y, but leaves the curve.
    uint256 constant Y_LAST_BYTE = 127;

    function _small() internal view returns (Batch memory) {
        return _take(_sharedZ("multi_blob_one_point_z1_128"), 3); // fallback path
    }

    function _big() internal view returns (Batch memory) {
        return _take(_sharedZ("multi_blob_one_point_z1_128"), 6); // batched path
    }

    // ── Non-canonical encodings: rejected on both paths before any precompile ──

    function test_nonZeroPadding_rejected_bothPaths() public {
        Batch memory small = _small();
        small.proofs[0] = _flip(small.proofs[0], 0, 0xff);
        vm.expectRevert(Bls12381.NonCanonicalG1Point.selector);
        _callSharedZ(small);

        Batch memory big = _big();
        big.proofs[0] = _flip(big.proofs[0], 64, 0x01); // y padding
        vm.expectRevert(Bls12381.NonCanonicalG1Point.selector);
        _callSharedZ(big);
    }

    function test_coordinateEqualToP_rejected_bothPaths() public {
        Batch memory small = _small();
        small.commitments[1] = _xEqualsP(small.commitments[1]);
        vm.expectRevert(Bls12381.NonCanonicalG1Point.selector);
        _callSharedZ(small);

        Batch memory big = _big();
        big.commitments[1] = _xEqualsP(big.commitments[1]);
        vm.expectRevert(Bls12381.NonCanonicalG1Point.selector);
        _callSharedZ(big);
    }

    // ── Off-curve points ────────────────────────────────────────────────

    function test_offCurveProof_rejected_fallback() public {
        Batch memory b = _small();
        b.proofs[0] = _flip(b.proofs[0], Y_LAST_BYTE, 0x01);
        vm.expectRevert(Bls12381.G1PointNotOnCurve.selector);
        _callSharedZ(b);
    }

    function test_offCurveCommitment_rejected_fallback() public {
        Batch memory b = _small();
        // The hash still binds: compression reads only x and the sign of y.
        b.commitments[1] = _flip(b.commitments[1], Y_LAST_BYTE, 0x01);
        vm.expectRevert(Bls12381.G1PointNotOnCurve.selector);
        _callSharedZ(b);
    }

    function test_offCurveProof_rejected_batched_withBoundedGas() public {
        Batch memory b = _big();
        b.proofs[0] = _flip(b.proofs[0], Y_LAST_BYTE, 0x01);

        uint256 before = gasleft();
        try harness.verifySinglePointMultipleBlobs128(b.hashes, b.z[0], b.y, b.commitments, b.proofs) {
            fail();
        } catch (bytes memory reason) {
            assertEq(reason, abi.encodeWithSelector(Bls12381.PrecompileCallFailed.selector, address(0x0C)));
        }
        // The RHS MSM (6 points) runs first and is capped at 6 * 12,000 gas; everything else is
        // validation. Without the cap this burned all forwarded gas (~1e9 in a test frame).
        assertLt(before - gasleft(), 250_000);
    }

    // ── Bls12381 validators in isolation ────────────────────────────────

    function test_requireOnCurve_acceptsFixturePointsAndInfinity() public view {
        Batch memory b = _general("multi_blob_multi_point_128");
        for (uint256 i; i < b.proofs.length; ++i) {
            harness.requireOnCurve(b.commitments[i]);
            harness.requireOnCurve(b.proofs[i]);
        }
        harness.requireOnCurve(BlobVerifier.G1_GENERATOR);
        harness.requireOnCurve(new bytes(128));
    }

    function testFuzz_requireOnCurve_rejectsOtherY(uint256 delta) public {
        // Any other y below p is off the curve unless it is -y; skip that one value.
        bytes memory g = BlobVerifier.G1_GENERATOR;
        uint256 yLo;
        assembly {
            yLo := mload(add(g, 0x80)) // last 32 bytes of the 128-byte payload
        }
        delta = bound(delta, 1, type(uint64).max);
        uint256 newLo;
        unchecked {
            newLo = yLo + delta;
        }
        // No carry into the high half: the generator's high half is far below p's, so y stays
        // canonical, and -y (which differs in the high half) cannot be hit.
        vm.assume(newLo > yLo);
        bytes memory moved = bytes.concat(g);
        assembly {
            mstore(add(moved, 0x80), newLo)
        }
        vm.expectRevert(Bls12381.G1PointNotOnCurve.selector);
        harness.requireOnCurve(moved);
    }

    /// @dev x = p - 1 is the largest canonical x; with the generator's y it is off the curve.
    function test_requireOnCurve_largestX_rejects() public {
        bytes memory point = bytes.concat(BlobVerifier.G1_GENERATOR);
        for (uint256 i; i < 48; ++i) {
            point[16 + i] = P_BYTES[i];
        }
        point[63] = bytes1(uint8(point[63]) - 1); // x = p - 1
        vm.expectRevert(Bls12381.G1PointNotOnCurve.selector);
        harness.requireOnCurve(point);
    }

    function test_requireCanonical_boundaries() public {
        // y = p - 1 is canonical (though off-curve); y = p is not.
        bytes memory g = BlobVerifier.G1_GENERATOR;
        bytes memory yIsP = bytes.concat(g);
        for (uint256 i; i < 48; ++i) {
            yIsP[80 + i] = P_BYTES[i];
        }
        vm.expectRevert(Bls12381.NonCanonicalG1Point.selector);
        harness.requireCanonical(yIsP);

        bytes memory yIsPMinus1 = bytes.concat(yIsP);
        yIsPMinus1[127] = bytes1(uint8(yIsPMinus1[127]) - 1);
        harness.requireCanonical(yIsPMinus1);
    }
}
