// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BlobVerifier} from "../src/BlobVerifier.sol";
import {Bls12381} from "../src/Bls12381.sol";
import {BlobVerifierHarness} from "./BlobVerifierHarness.sol";

contract BlobVerifierTest is Test {
    BlobVerifierHarness harness;

    struct Kzg {
        bytes commitment;
        bytes32 z;
        bytes32 y;
        bytes proof;
    }

    Kzg validProof; // correct_proof_1_0:    non-trivial commitment, valid opening (P(0) = 2)
    Kzg zeroProof; // correct_proof_0_0:    zero polynomial, commitment & proof at infinity
    Kzg badProof; // incorrect_proof_1_0:  same input as validProof but wrong proof (G1 generator)

    /// @dev 128-byte (uncompressed) fixture for verifyMultiplePoints128.
    ///      Many points, one blob — six openings of poly 2 (correct_proof_2_0..5).
    struct KzgMultiPointOneBlob {
        bytes commitment; // 128 bytes, shared
        bytes32[] z; // 6 elements
        bytes32[] y; // 6 elements
        bytes[] proofs; // 6 elements, 128 bytes each
    }

    KzgMultiPointOneBlob multiPointOneBlob;

    /// @dev 128-byte (uncompressed) fixture for verifySinglePointMultipleBlobs128.
    ///      Many blobs, one point — three blobs (polys 2, 3, 4) opened at the same z.
    struct KzgMultiBlobOnePoint {
        bytes32 z; // shared
        bytes[] commitments; // 3 elements, 128 bytes each
        bytes32[] y; // 3 elements
        bytes[] proofs; // 3 elements, 128 bytes each
    }

    KzgMultiBlobOnePoint multiBlobOnePoint; // z = 0 (degenerate path: r_i·z = 0)
    KzgMultiBlobOnePoint multiBlobOnePointZ1; // z = 1 (full LHS proof slots exercised)

    // ── Test constants ──────────────────────────────────────────────────

    // A valid versioned hash (0x01 prefix + 31 random bytes)
    bytes32 constant BLOB_HASH_1 = 0x01aabbccddee00112233445566778899aabbccddee00112233445566778899aa;
    bytes32 constant BLOB_HASH_2 = 0x01112233445566778899aabbccddeeff00112233445566778899aabbccddeeff;
    bytes32 constant BLOB_HASH_3 = 0x01deadbeefcafebabe0123456789abcdef0123456789abcdef0123456789abcd;

    // Invalid version byte (0x02 instead of 0x01)
    bytes32 constant INVALID_VERSION_HASH = 0x02aabbccddee00112233445566778899aabbccddee00112233445566778899aa;

    // Expected precompile output: abi.encodePacked(FIELD_ELEMENTS_PER_BLOB, BLS_MODULUS)
    bytes constant VALID_PRECOMPILE_OUTPUT = abi.encodePacked(
        bytes32(uint256(4096)),
        bytes32(uint256(52435875175126190479447740508185965837690552500527637822603658699938581184513))
    );

    // ── Setup ───────────────────────────────────────────────────────────

    function setUp() public {
        harness = new BlobVerifierHarness();
        validProof = _load("correct_proof_1_0");
        zeroProof = _load("correct_proof_0_0");
        badProof = _load("incorrect_proof_1_0");
        multiPointOneBlob = _loadMultiPointOneBlob("multi_point_one_blob_128");
        multiBlobOnePoint = _loadMultiBlobOnePoint("multi_blob_one_point_128");
        multiBlobOnePointZ1 = _loadMultiBlobOnePoint("multi_blob_one_point_z1_128");
    }

    function _load(string memory name) internal view returns (Kzg memory f) {
        string memory j = vm.readFile(string.concat("test/fixtures/", name, ".json"));
        f.commitment = vm.parseJsonBytes(j, ".commitment");
        f.z = vm.parseJsonBytes32(j, ".z");
        f.y = vm.parseJsonBytes32(j, ".y");
        f.proof = vm.parseJsonBytes(j, ".proof");
    }

    function _loadMultiPointOneBlob(string memory name) internal view returns (KzgMultiPointOneBlob memory f) {
        string memory j = vm.readFile(string.concat("test/fixtures/", name, ".json"));
        f.commitment = vm.parseJsonBytes(j, ".commitment");
        f.z = vm.parseJsonBytes32Array(j, ".z");
        f.y = vm.parseJsonBytes32Array(j, ".y");
        f.proofs = vm.parseJsonBytesArray(j, ".proofs");
    }

    function _loadMultiBlobOnePoint(string memory name) internal view returns (KzgMultiBlobOnePoint memory f) {
        string memory j = vm.readFile(string.concat("test/fixtures/", name, ".json"));
        f.z = vm.parseJsonBytes32(j, ".z");
        f.commitments = vm.parseJsonBytesArray(j, ".commitments");
        f.y = vm.parseJsonBytes32Array(j, ".y");
        f.proofs = vm.parseJsonBytesArray(j, ".proofs");
    }

    function _setSingleBlobHash(bytes32 h) internal {
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = h;
        vm.blobhashes(hashes);
    }

    function _setThreeBlobHashes() internal {
        bytes32[] memory hashes = new bytes32[](3);
        hashes[0] = BLOB_HASH_1;
        hashes[1] = BLOB_HASH_2;
        hashes[2] = BLOB_HASH_3;
        vm.blobhashes(hashes);
    }

    // ════════════════════════════════════════════════════════════════════
    //  PRECOMPILE OUTPUT HASH CONSTANT
    // ════════════════════════════════════════════════════════════════════

    function test_precompileOutputHashIsCorrect() public view {
        bytes32 expected = keccak256(VALID_PRECOMPILE_OUTPUT);
        bytes32 stored = harness.POINT_EVALUATION_PRECOMPILE_OUTPUT();
        assertEq(stored, expected, "POINT_EVALUATION_PRECOMPILE_OUTPUT hash mismatch");
    }

    function test_fieldElementsPerBlobValue() public view {
        assertEq(harness.FIELD_ELEMENTS_PER_BLOB(), bytes32(uint256(4096)), "FIELD_ELEMENTS_PER_BLOB should be 4096");
    }

    // ════════════════════════════════════════════════════════════════════
    //  getBlobHash
    // ════════════════════════════════════════════════════════════════════

    function test_getBlobHash_validIndex() public {
        _setSingleBlobHash(BLOB_HASH_1);
        bytes32 result = harness.getBlobHash(0);
        assertEq(result, BLOB_HASH_1);
    }

    function test_getBlobHash_multipleBlobs() public {
        _setThreeBlobHashes();

        assertEq(harness.getBlobHash(0), BLOB_HASH_1);
        assertEq(harness.getBlobHash(1), BLOB_HASH_2);
        assertEq(harness.getBlobHash(2), BLOB_HASH_3);
    }

    function test_getBlobHash_reverts_noBlobAtIndex() public {
        _setSingleBlobHash(BLOB_HASH_1);

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.BlobNotFoundAtIndex.selector, 1));
        harness.getBlobHash(1);
    }

    function test_getBlobHash_reverts_noBlobs() public {
        bytes32[] memory empty = new bytes32[](0);
        vm.blobhashes(empty);

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.BlobNotFoundAtIndex.selector, 0));
        harness.getBlobHash(0);
    }

    function test_getBlobHash_reverts_invalidVersion() public {
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = INVALID_VERSION_HASH;
        vm.blobhashes(hashes);

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidVersionedHashVersion.selector, bytes1(0x02)));
        harness.getBlobHash(0);
    }

    // ════════════════════════════════════════════════════════════════════
    //  blobExists
    // ════════════════════════════════════════════════════════════════════

    function test_blobExists_true() public {
        _setSingleBlobHash(BLOB_HASH_1);
        assertTrue(harness.blobExists(0));
    }

    function test_blobExists_false() public {
        _setSingleBlobHash(BLOB_HASH_1);
        assertFalse(harness.blobExists(1));
    }

    function test_blobExists_noBlobs() public {
        bytes32[] memory empty = new bytes32[](0);
        vm.blobhashes(empty);
        assertFalse(harness.blobExists(0));
    }

    // ════════════════════════════════════════════════════════════════════
    //  getBlobIndex
    // ════════════════════════════════════════════════════════════════════

    function test_getBlobIndex_reverts_notFound() public {
        _setSingleBlobHash(BLOB_HASH_1);
        bytes32 missingHash = bytes32(uint256(999));

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.BlobHashNotFound.selector, missingHash));
        harness.getBlobIndex(missingHash);
    }

    // ════════════════════════════════════════════════════════════════════
    //  commitmentToVersionedHash
    // ════════════════════════════════════════════════════════════════════

    function test_commitmentToVersionedHash_hasCorrectVersionByte() public view {
        bytes32 result = harness.commitmentToVersionedHash(validProof.commitment);
        assertEq(result[0], bytes1(0x01), "Version byte should be 0x01");
    }

    function test_commitmentToVersionedHash_matchesSha256() public view {
        bytes32 rawSha = sha256(validProof.commitment);
        bytes32 result = harness.commitmentToVersionedHash(validProof.commitment);
        assertEq(
            result & 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
            rawSha & 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
            "Bytes 1-31 should match sha256"
        );
    }

    function test_commitmentToVersionedHash_reverts_wrongLength() public {
        bytes memory tooShort = hex"aabbccddee";

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidCommitmentLength.selector, 5));
        harness.commitmentToVersionedHash(tooShort);
    }

    function test_commitmentToVersionedHash_reverts_tooLong() public {
        bytes memory tooLong = new bytes(49);

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidCommitmentLength.selector, 49));
        harness.commitmentToVersionedHash(tooLong);
    }

    // ════════════════════════════════════════════════════════════════════
    //  verifySinglePoint (by blob index)
    // ════════════════════════════════════════════════════════════════════

    function test_verifySinglePointByIndex_success() public {
        bytes32 vh = harness.commitmentToVersionedHash(validProof.commitment);
        _setSingleBlobHash(vh);

        harness.verifySinglePointByIndex(0, validProof.z, validProof.y, validProof.commitment, validProof.proof);
    }

    function test_verifySinglePointByIndex_reverts_noBlobAtIndex() public {
        _setSingleBlobHash(BLOB_HASH_1);

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.BlobNotFoundAtIndex.selector, 5));
        harness.verifySinglePointByIndex(5, validProof.z, validProof.y, validProof.commitment, validProof.proof);
    }

    function test_verifySinglePointByIndex_reverts_badCommitmentLength() public {
        _setSingleBlobHash(BLOB_HASH_1);
        bytes memory badCommitment = new bytes(32); // too short

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidCommitmentLength.selector, 32));
        harness.verifySinglePointByIndex(0, validProof.z, validProof.y, badCommitment, validProof.proof);
    }

    function test_verifySinglePointByIndex_reverts_badProofLength() public {
        _setSingleBlobHash(BLOB_HASH_1);
        bytes memory wrongLengthProof = new bytes(96); // too long

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidProofLength.selector, 96));
        harness.verifySinglePointByIndex(0, validProof.z, validProof.y, validProof.commitment, wrongLengthProof);
    }

    function test_verifySinglePointByIndex_reverts_precompileFails() public {
        bytes32 vh = harness.commitmentToVersionedHash(badProof.commitment);
        _setSingleBlobHash(vh);

        vm.expectRevert(BlobVerifier.PointEvaluationPrecompileCallFailed.selector);
        harness.verifySinglePointByIndex(0, badProof.z, badProof.y, badProof.commitment, badProof.proof);
    }

    // ════════════════════════════════════════════════════════════════════
    //  verifySinglePoint (by versioned hash)
    // ════════════════════════════════════════════════════════════════════

    function test_verifySinglePointByHash_success() public view {
        bytes32 vh = harness.commitmentToVersionedHash(validProof.commitment);
        // No blob needed in tx — hash is provided directly
        harness.verifySinglePointByHash(vh, validProof.z, validProof.y, validProof.commitment, validProof.proof);
    }

    function test_verifySinglePointByHash_reverts_precompileFails() public {
        bytes32 vh = harness.commitmentToVersionedHash(badProof.commitment);

        vm.expectRevert(BlobVerifier.PointEvaluationPrecompileCallFailed.selector);
        harness.verifySinglePointByHash(vh, badProof.z, badProof.y, badProof.commitment, badProof.proof);
    }

    function test_verifySinglePointByHash_reverts_invalidVersion() public {
        // _checkHashPrefix runs before any other validation, so input lengths/values don't matter
        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidVersionedHashVersion.selector, bytes1(0x02)));
        harness.verifySinglePointByHash(
            INVALID_VERSION_HASH, validProof.z, validProof.y, validProof.commitment, validProof.proof
        );
    }

    // ════════════════════════════════════════════════════════════════════
    //  Input length validation (both overloads share _verifySinglePoint)
    // ════════════════════════════════════════════════════════════════════

    function test_commitmentLength_exactly48() public {
        _setSingleBlobHash(BLOB_HASH_1);

        // 47 bytes — too short
        bytes memory short = new bytes(47);
        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidCommitmentLength.selector, 47));
        harness.verifySinglePointByIndex(0, validProof.z, validProof.y, short, validProof.proof);

        // 49 bytes — too long
        bytes memory long_ = new bytes(49);
        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidCommitmentLength.selector, 49));
        harness.verifySinglePointByIndex(0, validProof.z, validProof.y, long_, validProof.proof);
    }

    function test_proofLength_exactly48() public {
        _setSingleBlobHash(BLOB_HASH_1);

        bytes memory empty = new bytes(0);
        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidProofLength.selector, 0));
        harness.verifySinglePointByIndex(0, validProof.z, validProof.y, validProof.commitment, empty);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Edge cases
    // ════════════════════════════════════════════════════════════════════

    function test_verifySinglePoint_zeroValues() public {
        // z=0 and y=0 with the zero polynomial (commitment at infinity)
        bytes32 vh = harness.commitmentToVersionedHash(zeroProof.commitment);
        _setSingleBlobHash(vh);

        harness.verifySinglePointByIndex(0, zeroProof.z, zeroProof.y, zeroProof.commitment, zeroProof.proof);
    }

    function test_multipleVerificationsInSameCall() public {
        bytes32[] memory hashes = new bytes32[](2);
        hashes[0] = harness.commitmentToVersionedHash(validProof.commitment);
        hashes[1] = harness.commitmentToVersionedHash(zeroProof.commitment);
        vm.blobhashes(hashes);

        harness.verifySinglePointByIndex(0, validProof.z, validProof.y, validProof.commitment, validProof.proof);
        harness.verifySinglePointByIndex(1, zeroProof.z, zeroProof.y, zeroProof.commitment, zeroProof.proof);
    }

    // ════════════════════════════════════════════════════════════════════
    //  verifyMultiplePoints128 (one blob, multiple openings, batched pairing)
    // ════════════════════════════════════════════════════════════════════

    function test_verifyMultiplePoints128_success() public view {
        bytes32 blobHash = _blobHashFor(multiPointOneBlob.commitment);

        harness.verifyMultiplePoints128(
            blobHash, multiPointOneBlob.z, multiPointOneBlob.y, multiPointOneBlob.commitment, multiPointOneBlob.proofs
        );
    }

    function test_verifyMultiplePoints128_reverts_badProof() public {
        bytes32 blobHash = _blobHashFor(multiPointOneBlob.commitment);

        // Replace proofs[0] with G1_GENERATOR — a valid G1 point but not the right proof.
        bytes[] memory tamperedProofs = multiPointOneBlob.proofs;
        tamperedProofs[0] = BlobVerifier.G1_GENERATOR;

        vm.expectRevert(BlobVerifier.PairingCheckFailed.selector);
        harness.verifyMultiplePoints128(
            blobHash, multiPointOneBlob.z, multiPointOneBlob.y, multiPointOneBlob.commitment, tamperedProofs
        );
    }

    function test_verifyMultiplePoints128_reverts_commitmentMismatch() public {
        bytes32 wrongHash = bytes32(uint256(0xdeadbeef));
        bytes32 actualHash = _blobHashFor(multiPointOneBlob.commitment);

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.CommitmentMismatch.selector, wrongHash, actualHash));
        harness.verifyMultiplePoints128(
            wrongHash, multiPointOneBlob.z, multiPointOneBlob.y, multiPointOneBlob.commitment, multiPointOneBlob.proofs
        );
    }

    function test_verifyMultiplePoints128_reverts_invalidScalar_y() public {
        bytes32 blobHash = _blobHashFor(multiPointOneBlob.commitment);

        // y exactly at the modulus is the boundary case — must be rejected.
        bytes32[] memory tamperedY = multiPointOneBlob.y;
        tamperedY[0] = BlobVerifier.BLS_MODULUS;

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidScalar.selector, BlobVerifier.BLS_MODULUS));
        harness.verifyMultiplePoints128(
            blobHash, multiPointOneBlob.z, tamperedY, multiPointOneBlob.commitment, multiPointOneBlob.proofs
        );
    }

    function test_verifyMultiplePoints128_reverts_invalidScalar_z() public {
        bytes32 blobHash = _blobHashFor(multiPointOneBlob.commitment);

        bytes32[] memory tamperedZ = multiPointOneBlob.z;
        tamperedZ[0] = BlobVerifier.BLS_MODULUS;

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidScalar.selector, BlobVerifier.BLS_MODULUS));
        harness.verifyMultiplePoints128(
            blobHash, tamperedZ, multiPointOneBlob.y, multiPointOneBlob.commitment, multiPointOneBlob.proofs
        );
    }

    function test_verifyMultiplePoints128_reverts_badProofLength() public {
        bytes32 blobHash = _blobHashFor(multiPointOneBlob.commitment);

        bytes[] memory tamperedProofs = multiPointOneBlob.proofs;
        tamperedProofs[0] = new bytes(96); // wrong length — should be 128

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidProofLength.selector, 96));
        harness.verifyMultiplePoints128(
            blobHash, multiPointOneBlob.z, multiPointOneBlob.y, multiPointOneBlob.commitment, tamperedProofs
        );
    }

    function test_verifyMultiplePoints128_reverts_arrayLengthMismatch() public {
        bytes32 blobHash = _blobHashFor(multiPointOneBlob.commitment);

        // Build a shorter y array (one less element than z) to trigger the length check.
        bytes32[] memory shortY = new bytes32[](multiPointOneBlob.y.length - 1);
        for (uint256 i; i < shortY.length; ++i) shortY[i] = multiPointOneBlob.y[i];

        vm.expectRevert(BlobVerifier.ArrayLengthMismatch.selector);
        harness.verifyMultiplePoints128(
            blobHash, multiPointOneBlob.z, shortY, multiPointOneBlob.commitment, multiPointOneBlob.proofs
        );
    }

    function test_verifyMultiplePoints128_reverts_empty() public {
        // n == 0 check fires before any commitment/scalar work.
        bytes32[] memory empty32 = new bytes32[](0);
        bytes[] memory emptyBytes = new bytes[](0);

        vm.expectRevert(BlobVerifier.ArrayLengthMismatch.selector);
        harness.verifyMultiplePoints128(bytes32(0), empty32, empty32, multiPointOneBlob.commitment, emptyBytes);
    }

    // ════════════════════════════════════════════════════════════════════
    //  verifySinglePointMultipleBlobs128 (many blobs, one point, batched pairing)
    // ════════════════════════════════════════════════════════════════════

    function test_verifySinglePointMultipleBlobs128_z0_success() public view {
        _runMultiBlobOnePointSuccess(multiBlobOnePoint);
    }

    function test_verifySinglePointMultipleBlobs128_z1_success() public view {
        // z=1 — exercises the Σ(r_i·z)·π_i term in the LHS that's zeroed at z=0.
        _runMultiBlobOnePointSuccess(multiBlobOnePointZ1);
    }

    function test_verifySinglePointMultipleBlobs128_reverts_badProof() public {
        // Use the z=1 fixture so proofs actually weigh into the LHS math (not just the RHS).
        KzgMultiBlobOnePoint memory f = multiBlobOnePointZ1;
        bytes32[] memory blobHashes = _blobHashesFor(f.commitments);

        // Replace proofs[0] with G1_GENERATOR — a valid G1 point that is not the right proof.
        bytes[] memory tamperedProofs = f.proofs;
        tamperedProofs[0] = BlobVerifier.G1_GENERATOR;

        // At n=3 the function takes the threshold-fallback path (0x0A loop), which rejects with
        // PointEvaluationPrecompileCallFailed. The batched path would reject with PairingCheckFailed.
        // Either is correct rejection behaviour, so we just require the call to revert.
        vm.expectRevert();
        harness.verifySinglePointMultipleBlobs128(blobHashes, f.z, f.y, f.commitments, tamperedProofs);
    }

    function test_verifySinglePointMultipleBlobs128_reverts_commitmentMismatch() public {
        KzgMultiBlobOnePoint memory f = multiBlobOnePoint;
        bytes32[] memory blobHashes = _blobHashesFor(f.commitments);

        blobHashes[0] = bytes32(uint256(0xdeadbeef));

        // At n=3 the threshold fallback's 0x0A precompile validates the commitment-to-blobHash
        // binding internally, so a wrong blobHash trips PointEvaluationPrecompileCallFailed.
        // The batched path would trip CommitmentMismatch — either is a valid rejection.
        vm.expectRevert();
        harness.verifySinglePointMultipleBlobs128(blobHashes, f.z, f.y, f.commitments, f.proofs);
    }

    function test_verifySinglePointMultipleBlobs128_reverts_invalidScalar_y() public {
        KzgMultiBlobOnePoint memory f = multiBlobOnePoint;
        bytes32[] memory blobHashes = _blobHashesFor(f.commitments);

        bytes32[] memory tamperedY = f.y;
        tamperedY[0] = BlobVerifier.BLS_MODULUS;

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidScalar.selector, BlobVerifier.BLS_MODULUS));
        harness.verifySinglePointMultipleBlobs128(blobHashes, f.z, tamperedY, f.commitments, f.proofs);
    }

    function test_verifySinglePointMultipleBlobs128_reverts_invalidScalar_z() public {
        KzgMultiBlobOnePoint memory f = multiBlobOnePoint;
        bytes32[] memory blobHashes = _blobHashesFor(f.commitments);

        // z is singular here (vs. an array in verifyMultiplePoints128).
        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidScalar.selector, BlobVerifier.BLS_MODULUS));
        harness.verifySinglePointMultipleBlobs128(blobHashes, BlobVerifier.BLS_MODULUS, f.y, f.commitments, f.proofs);
    }

    function test_verifySinglePointMultipleBlobs128_reverts_badProofLength() public {
        KzgMultiBlobOnePoint memory f = multiBlobOnePoint;
        bytes32[] memory blobHashes = _blobHashesFor(f.commitments);

        bytes[] memory tamperedProofs = f.proofs;
        tamperedProofs[0] = new bytes(96);

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidProofLength.selector, 96));
        harness.verifySinglePointMultipleBlobs128(blobHashes, f.z, f.y, f.commitments, tamperedProofs);
    }

    function test_verifySinglePointMultipleBlobs128_reverts_arrayLengthMismatch() public {
        KzgMultiBlobOnePoint memory f = multiBlobOnePoint;
        bytes32[] memory blobHashes = _blobHashesFor(f.commitments);

        // Shorten commitments by one to break the n != commitments.length check.
        bytes[] memory shortCommitments = new bytes[](f.commitments.length - 1);
        for (uint256 i; i < shortCommitments.length; ++i) shortCommitments[i] = f.commitments[i];

        vm.expectRevert(BlobVerifier.ArrayLengthMismatch.selector);
        harness.verifySinglePointMultipleBlobs128(blobHashes, f.z, f.y, shortCommitments, f.proofs);
    }

    function test_verifySinglePointMultipleBlobs128_reverts_empty() public {
        // n == 0 check fires first, before z bounds or commitment binding.
        bytes32[] memory empty32 = new bytes32[](0);
        bytes[] memory emptyBytes = new bytes[](0);

        vm.expectRevert(BlobVerifier.ArrayLengthMismatch.selector);
        harness.verifySinglePointMultipleBlobs128(empty32, bytes32(0), empty32, emptyBytes, emptyBytes);
    }

    /// @dev Derive the per-commitment versioned hash array used as `blobHashes` input.
    function _blobHashesFor(bytes[] memory commitments) internal pure returns (bytes32[] memory hashes) {
        hashes = new bytes32[](commitments.length);
        for (uint256 i; i < commitments.length; ++i) {
            hashes[i] = _blobHashFor(commitments[i]);
        }
    }

    /// @dev Shared happy-path runner: derive each blobHash from the loaded commitment, call.
    function _runMultiBlobOnePointSuccess(KzgMultiBlobOnePoint memory f) internal view {
        bytes32[] memory blobHashes = new bytes32[](f.commitments.length);
        for (uint256 i; i < f.commitments.length; ++i) {
            blobHashes[i] = _blobHashFor(f.commitments[i]);
        }

        harness.verifySinglePointMultipleBlobs128(blobHashes, f.z, f.y, f.commitments, f.proofs);
    }

    /// @dev Derive the EIP-4844 versioned hash from a 128-byte uncompressed G1 commitment.
    ///      Used by the *128 happy-path tests to construct the blobHash the verifier expects.
    function _blobHashFor(bytes memory uncompressed) internal pure returns (bytes32) {
        return BlobVerifier.commitmentToVersionedHash(Bls12381.compress(uncompressed));
    }
}
