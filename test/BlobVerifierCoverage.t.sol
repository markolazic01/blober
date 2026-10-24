// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {BlobVerifier} from "../src/BlobVerifier.sol";
import {Bls12381} from "../src/Bls12381.sol";
import {Fixtures} from "./utils/Fixtures.sol";

/// @notice Functions and paths the original suite never executed: the 48-byte multi-claim loops,
///         the blob helpers, the Bls12381 wrappers, the one-blob fallback, commitment lengths on
///         the 128-byte paths, the batched z = 0 slot, and points at infinity on every 128-byte path.
contract BlobVerifierCoverageTest is Fixtures {
    // 48-byte fixtures: two valid openings at z = 0 (constant poly 2; zero poly) and one bad proof.
    bytes c1;
    bytes p1;
    bytes c0;
    bytes p0;
    bytes pBad;
    bytes32 y1;

    bytes constant INFINITY_COMPRESSED =
        hex"c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    function setUp() public override {
        super.setUp();
        string memory j1 = vm.readFile("test/fixtures/correct_proof_1_0.json");
        c1 = vm.parseJsonBytes(j1, ".commitment");
        p1 = vm.parseJsonBytes(j1, ".proof");
        y1 = vm.parseJsonBytes32(j1, ".y");
        string memory j0 = vm.readFile("test/fixtures/correct_proof_0_0.json");
        c0 = vm.parseJsonBytes(j0, ".commitment");
        p0 = vm.parseJsonBytes(j0, ".proof");
        pBad = vm.parseJsonBytes(vm.readFile("test/fixtures/incorrect_proof_1_0.json"), ".proof");
    }

    // ════════════════════════════════════════════════════════════════════
    //  48-byte loops
    // ════════════════════════════════════════════════════════════════════

    function _twoBlobs48(bytes memory secondProof)
        internal
        view
        returns (bytes32[] memory hashes, bytes32[] memory ys, bytes[] memory cs, bytes[] memory ps)
    {
        cs = new bytes[](2);
        cs[0] = c1;
        cs[1] = c0;
        ps = new bytes[](2);
        ps[0] = p1;
        ps[1] = secondProof;
        ys = new bytes32[](2);
        ys[0] = y1;
        hashes = new bytes32[](2);
        hashes[0] = BlobVerifier.commitmentToVersionedHash(c1);
        hashes[1] = BlobVerifier.commitmentToVersionedHash(c0);
    }

    function test_verifySinglePointMultipleBlobs_success() public view {
        (bytes32[] memory h, bytes32[] memory ys, bytes[] memory cs, bytes[] memory ps) = _twoBlobs48(p0);
        harness.verifySinglePointMultipleBlobs(h, bytes32(0), ys, cs, ps);
    }

    function test_verifySinglePointMultipleBlobs_reverts_badProof() public {
        (bytes32[] memory h, bytes32[] memory ys, bytes[] memory cs, bytes[] memory ps) = _twoBlobs48(pBad);
        vm.expectRevert(BlobVerifier.PointEvaluationPrecompileCallFailed.selector);
        harness.verifySinglePointMultipleBlobs(h, bytes32(0), ys, cs, ps);
    }

    function test_verifySinglePointMultipleBlobs_reverts_arrayLengthMismatch() public {
        (bytes32[] memory h, bytes32[] memory ys, bytes[] memory cs,) = _twoBlobs48(p0);
        vm.expectRevert(BlobVerifier.ArrayLengthMismatch.selector);
        harness.verifySinglePointMultipleBlobs(h, bytes32(0), ys, cs, new bytes[](1));
    }

    /// @dev The one-blob 128-byte fixture, compressed to the 48-byte wire format.
    function _oneBlob48() internal view returns (Batch memory b, bytes memory c48, bytes[] memory p48) {
        b = _oneBlob("multi_point_one_blob_128");
        c48 = Bls12381.compress(b.commitments[0]);
        p48 = new bytes[](b.proofs.length);
        for (uint256 i; i < b.proofs.length; ++i) {
            p48[i] = Bls12381.compress(b.proofs[i]);
        }
    }

    function test_verifyMultiplePoints_success() public view {
        (Batch memory b, bytes memory c48, bytes[] memory p48) = _oneBlob48();
        harness.verifyMultiplePoints(b.hashes[0], b.z, b.y, c48, p48);
    }

    function test_verifyMultiplePoints_reverts_tamperedY() public {
        (Batch memory b, bytes memory c48, bytes[] memory p48) = _oneBlob48();
        b.y[3] = bytes32(uint256(b.y[3]) + 1);
        vm.expectRevert(BlobVerifier.PointEvaluationPrecompileCallFailed.selector);
        harness.verifyMultiplePoints(b.hashes[0], b.z, b.y, c48, p48);
    }

    function test_verifyMultiplePoints_reverts_arrayLengthMismatch() public {
        (Batch memory b, bytes memory c48,) = _oneBlob48();
        vm.expectRevert(BlobVerifier.ArrayLengthMismatch.selector);
        harness.verifyMultiplePoints(b.hashes[0], b.z, b.y, c48, new bytes[](1));
    }

    // ════════════════════════════════════════════════════════════════════
    //  Blob helpers
    // ════════════════════════════════════════════════════════════════════

    function _setHashes(uint256 n) internal returns (bytes32[] memory hashes) {
        hashes = new bytes32[](n);
        for (uint256 i; i < n; ++i) {
            hashes[i] = bytes32(uint256(0x01) << 248 | (i + 1));
        }
        vm.blobhashes(hashes);
    }

    function test_getBlobCount() public {
        _setHashes(0);
        assertEq(harness.blobCount(), 0);
        _setHashes(1);
        assertEq(harness.blobCount(), 1);
        _setHashes(6);
        assertEq(harness.blobCount(), 6);
    }

    function test_getBlobIndex_found() public {
        bytes32[] memory hashes = _setHashes(3);
        assertEq(harness.getBlobIndex(hashes[0]), 0);
        assertEq(harness.getBlobIndex(hashes[2]), 2);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Bls12381 wrappers
    // ════════════════════════════════════════════════════════════════════

    function test_compress_infinity() public view {
        assertEq(harness.compress(new bytes(128)), INFINITY_COMPRESSED);
    }

    function test_compress_generator() public view {
        // incorrect_proof_1_0 uses the compressed G1 generator as its (wrong) proof.
        assertEq(harness.compress(BlobVerifier.G1_GENERATOR), pBad);
    }

    function test_g1Add_matchesMsm() public view {
        bytes[] memory pts = new bytes[](1);
        pts[0] = BlobVerifier.G1_GENERATOR;
        bytes32[] memory scalars = new bytes32[](1);
        scalars[0] = bytes32(uint256(2));
        assertEq(harness.g1Add(BlobVerifier.G1_GENERATOR, BlobVerifier.G1_GENERATOR), harness.g1Msm(pts, scalars));
    }

    function test_g1Add_infinityIsIdentity() public view {
        assertEq(harness.g1Add(BlobVerifier.G1_GENERATOR, new bytes(128)), BlobVerifier.G1_GENERATOR);
    }

    function test_g1Add_reverts_badLength() public {
        vm.expectRevert(abi.encodeWithSelector(Bls12381.InvalidG1PointLength.selector, 127));
        harness.g1Add(BlobVerifier.G1_GENERATOR, new bytes(127));
    }

    function test_g1Msm_reverts_empty() public {
        vm.expectRevert(Bls12381.EmptyInput.selector);
        harness.g1Msm(new bytes[](0), new bytes32[](0));
    }

    function test_g1Msm_reverts_lengthMismatch() public {
        vm.expectRevert(Bls12381.LengthMismatch.selector);
        harness.g1Msm(new bytes[](1), new bytes32[](2));
    }

    // ════════════════════════════════════════════════════════════════════
    //  128-byte paths not reached before
    // ════════════════════════════════════════════════════════════════════

    function test_verifyMultiplePoints128_fallback_success() public view {
        _callOneBlob(_take(_oneBlob("multi_point_one_blob_128"), 3));
    }

    function test_verifyMultiplePoints128_fallback_reverts_tamperedY() public {
        Batch memory b = _take(_oneBlob("multi_point_one_blob_128"), 3);
        b.y[1] = bytes32(uint256(b.y[1]) + 1);
        vm.expectRevert(BlobVerifier.PointEvaluationPrecompileCallFailed.selector);
        _callOneBlob(b);
    }

    /// @dev z = 0 zeroes the (RHS, z) slot of the shared-z LHS MSM. The three-claim fixture only
    ///      reaches the fallback, so repeat it to six claims to run the batched path.
    function test_verifySinglePointMultipleBlobs128_batched_z0_success() public view {
        _callSharedZ(_take(_sharedZ("multi_blob_one_point_128"), 6));
    }

    function test_verifySinglePointMultipleBlobs128_batched_z0_reverts_tamperedY() public {
        Batch memory b = _take(_sharedZ("multi_blob_one_point_128"), 6);
        b.y[4] = bytes32(uint256(b.y[4]) + 1);
        vm.expectRevert(BlobVerifier.PairingCheckFailed.selector);
        _callSharedZ(b);
    }

    // ── Commitment length on every 128-byte shape and path ──────────────

    function _shortCommitment(Batch memory b, uint256 i) internal pure returns (Batch memory) {
        b.commitments[i] = new bytes(127);
        return b;
    }

    function test_commitmentLength_sharedZ_bothPaths() public {
        Batch memory small = _shortCommitment(_take(_sharedZ("multi_blob_one_point_z1_128"), 3), 1);
        vm.expectRevert(abi.encodeWithSelector(Bls12381.InvalidG1PointLength.selector, 127));
        _callSharedZ(small);

        Batch memory big = _shortCommitment(_take(_sharedZ("multi_blob_one_point_z1_128"), 6), 1);
        vm.expectRevert(abi.encodeWithSelector(Bls12381.InvalidG1PointLength.selector, 127));
        _callSharedZ(big);
    }

    function test_commitmentLength_oneBlob_bothPaths() public {
        Batch memory small = _take(_oneBlob("multi_point_one_blob_128"), 3);
        small.commitments[0] = new bytes(129);
        vm.expectRevert(abi.encodeWithSelector(Bls12381.InvalidG1PointLength.selector, 129));
        _callOneBlob(small);

        Batch memory big = _oneBlob("multi_point_one_blob_128");
        big.commitments[0] = new bytes(129);
        vm.expectRevert(abi.encodeWithSelector(Bls12381.InvalidG1PointLength.selector, 129));
        _callOneBlob(big);
    }

    function test_commitmentLength_general_bothPaths() public {
        Batch memory small = _shortCommitment(_take(_general("multi_blob_multi_point_128"), 3), 2);
        vm.expectRevert(abi.encodeWithSelector(Bls12381.InvalidG1PointLength.selector, 127));
        _callGeneral(small);

        Batch memory big = _shortCommitment(_general("multi_blob_multi_point_128"), 2);
        vm.expectRevert(abi.encodeWithSelector(Bls12381.InvalidG1PointLength.selector, 127));
        _callGeneral(big);
    }

    // ── Points at infinity (zero polynomial; constant polynomial with proof at infinity) ──

    function test_infinity_sharedZ_fallback() public view {
        _callSharedZ(_sharedZ("infinity_128"));
    }

    function test_infinity_sharedZ_batched() public view {
        _callSharedZ(_take(_sharedZ("infinity_128"), 6));
    }

    function test_infinity_general_batched() public view {
        _callGeneral(_take(_sharedZ("infinity_128"), 6));
    }

    function test_infinity_batched_reverts_tamperedY() public {
        Batch memory b = _take(_sharedZ("infinity_128"), 6);
        b.y[1] = bytes32(uint256(3)); // the constant polynomial is 2 everywhere
        vm.expectRevert(BlobVerifier.PairingCheckFailed.selector);
        _callSharedZ(b);
    }

    /// @dev The zero polynomial opened at six points: commitment and every proof at infinity.
    function _zeroPolyOneBlob(uint256 n) internal pure returns (Batch memory b) {
        b.commitments = new bytes[](n);
        b.proofs = new bytes[](n);
        b.z = new bytes32[](n);
        b.y = new bytes32[](n);
        for (uint256 i; i < n; ++i) {
            b.commitments[i] = new bytes(128);
            b.proofs[i] = new bytes(128);
            b.z[i] = bytes32(i);
        }
        b.hashes = _hashesFor(b.commitments);
    }

    function test_infinity_oneBlob_bothPaths() public view {
        _callOneBlob(_zeroPolyOneBlob(3));
        _callOneBlob(_zeroPolyOneBlob(6));
    }
}
