// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BlobVerifier} from "../src/BlobVerifier.sol";
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
    }

    function _load(string memory name) internal view returns (Kzg memory f) {
        string memory j = vm.readFile(string.concat("test/fixtures/", name, ".json"));
        f.commitment = vm.parseJsonBytes(j, ".commitment");
        f.z = vm.parseJsonBytes32(j, ".z");
        f.y = vm.parseJsonBytes32(j, ".y");
        f.proof = vm.parseJsonBytes(j, ".proof");
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
}
