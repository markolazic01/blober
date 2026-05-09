// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {BlobVerifier} from "../src/BlobVerifier.sol";
import {BlobVerifierHarness} from "./BlobVerifierHarness.sol";

contract BlobVerifierTest is Test {
    BlobVerifierHarness harness;

    // ── Test constants ──────────────────────────────────────────────────

    // A valid versioned hash (0x01 prefix + 31 random bytes)
    bytes32 constant BLOB_HASH_1 = 0x01aabbccddee00112233445566778899aabbccddee00112233445566778899aa;
    bytes32 constant BLOB_HASH_2 = 0x01112233445566778899aabbccddeeff00112233445566778899aabbccddeeff;
    bytes32 constant BLOB_HASH_3 = 0x01deadbeefcafebabe0123456789abcdef0123456789abcdef0123456789abcd;

    // Invalid version byte (0x02 instead of 0x01)
    bytes32 constant INVALID_VERSION_HASH = 0x02aabbccddee00112233445566778899aabbccddee00112233445566778899aa;

    // Dummy z, y values
    bytes32 constant Z_VALUE = bytes32(uint256(42));
    bytes32 constant Y_VALUE = bytes32(uint256(123));

    // Dummy 48-byte commitment and proof (content doesn't matter for mock tests)
    bytes constant DUMMY_COMMITMENT = hex"aabbccddee00112233445566778899aabbccddee00112233445566778899aabbccddee00112233445566778899aabbcc";
    bytes constant DUMMY_PROOF      = hex"112233445566778899aabbccddee00112233445566778899aabbccddee00112233445566778899aabbccddee00112233";

    // Expected precompile output: abi.encodePacked(FIELD_ELEMENTS_PER_BLOB, BLS_MODULUS)
    bytes constant VALID_PRECOMPILE_OUTPUT = abi.encodePacked(
        bytes32(uint256(4096)),
        bytes32(uint256(52435875175126190479447740508185965837690552500527637822603658699938581184513))
    );

    // Point 1 Data - Valid Blob
    bytes32 constant BLOB_1_VERSIONED_COMMITMENT_HASH = 0x01cf45213dd7b4716864d378f3c6d861467987e4d94b7f79a1f814a697e38637;
    bytes constant BLOB_1_COMMITMENT = bytes(hex'a572cbea904d67468808c8eb50a9450c9721db309128012543902d0ac358a62ae28f75bb8f1c7c42c39a8c5529bf0f4e');
    bytes32 constant BLOB_1_POINT_1_Z = 0x0000000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant BLOB_1_POINT_1_Y = 0x0000000000000000000000000000000000000000000000000000000000000002;
    bytes constant BLOB_1_POINT_PROOF = bytes(hex'c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000');

    // ── Setup ───────────────────────────────────────────────────────────

    function setUp() public {
        harness = new BlobVerifierHarness();
    }

    // ── Helper to set blob hashes via cheatcode ─────────────────────────

    function _setBlobHashes(bytes32[] memory hashes) internal {
        vm.blobhashes(hashes);
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

    /// @dev Builds the exact calldata the library sends to the precompile
    function _buildPrecompileInput(
        bytes32 vHash,
        bytes32 z,
        bytes32 y,
        bytes memory commitment,
        bytes memory proof
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(vHash, z, y, commitment, proof);
    }

    /// @dev Mocks a successful precompile call for the given input
    function _mockPrecompileSuccess(
        bytes32 vHash,
        bytes32 z,
        bytes32 y,
        bytes memory commitment,
        bytes memory proof
    ) internal {
        bytes memory input = _buildPrecompileInput(vHash, z, y, commitment, proof);
        vm.mockCall(
            address(0x0A),
            input,
            VALID_PRECOMPILE_OUTPUT
        );
    }

    /// @dev Mocks a failed precompile call (returns false)
    function _mockPrecompileFailure(
        bytes32 vHash,
        bytes32 z,
        bytes32 y,
        bytes memory commitment,
        bytes memory proof
    ) internal {
        bytes memory input = _buildPrecompileInput(vHash, z, y, commitment, proof);
        vm.mockCallRevert(
            address(0x0A),
            input,
            ""
        );
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
        assertEq(
            harness.FIELD_ELEMENTS_PER_BLOB(),
            bytes32(uint256(4096)),
            "FIELD_ELEMENTS_PER_BLOB should be 4096"
        );
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
        bytes32 result = harness.commitmentToVersionedHash(DUMMY_COMMITMENT);

        // First byte must be 0x01
        assertEq(result[0], bytes1(0x01), "Version byte should be 0x01");
    }

    function test_commitmentToVersionedHash_matchesSha256() public view {
        bytes32 rawSha = sha256(DUMMY_COMMITMENT);
        bytes32 result = harness.commitmentToVersionedHash(DUMMY_COMMITMENT);

        // Bytes 1-31 should match sha256 output
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
        _setSingleBlobHash(BLOB_1_VERSIONED_COMMITMENT_HASH);

        // Should not revert
        harness.verifySinglePointByIndex(0, BLOB_1_POINT_1_Z, BLOB_1_POINT_1_Y, BLOB_1_COMMITMENT, BLOB_1_POINT_PROOF);
    }

    function test_verifySinglePointByIndex_reverts_noBlobAtIndex() public {
        _setSingleBlobHash(BLOB_HASH_1);

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.BlobNotFoundAtIndex.selector, 5));
        harness.verifySinglePointByIndex(5, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, DUMMY_PROOF);
    }

    function test_verifySinglePointByIndex_reverts_badCommitmentLength() public {
        _setSingleBlobHash(BLOB_HASH_1);
        bytes memory badCommitment = new bytes(32); // too short

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidCommitmentLength.selector, 32));
        harness.verifySinglePointByIndex(0, Z_VALUE, Y_VALUE, badCommitment, DUMMY_PROOF);
    }

    function test_verifySinglePointByIndex_reverts_badProofLength() public {
        _setSingleBlobHash(BLOB_HASH_1);
        bytes memory badProof = new bytes(96); // too long

        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidProofLength.selector, 96));
        harness.verifySinglePointByIndex(0, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, badProof);
    }

    function test_verifySinglePointByIndex_reverts_precompileFails() public {
        _setSingleBlobHash(BLOB_HASH_1);
        _mockPrecompileFailure(BLOB_HASH_1, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, DUMMY_PROOF);

        vm.expectRevert(BlobVerifier.PointEvaluationPrecompileCallFailed.selector);
        harness.verifySinglePointByIndex(0, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, DUMMY_PROOF);
    }

    // ════════════════════════════════════════════════════════════════════
    //  verifySinglePoint (by versioned hash)
    // ════════════════════════════════════════════════════════════════════

    function test_verifySinglePointByHash_success() public {
        _mockPrecompileSuccess(BLOB_HASH_1, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, DUMMY_PROOF);

        // Should not revert — no blob needed in tx, hash is provided directly
        harness.verifySinglePointByHash(BLOB_HASH_1, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, DUMMY_PROOF);
    }

    function test_verifySinglePointByHash_reverts_precompileFails() public {
        _mockPrecompileFailure(BLOB_HASH_1, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, DUMMY_PROOF);

        vm.expectRevert(BlobVerifier.PointEvaluationPrecompileCallFailed.selector);
        harness.verifySinglePointByHash(BLOB_HASH_1, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, DUMMY_PROOF);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Input length validation (both overloads share _verifySinglePoint)
    // ════════════════════════════════════════════════════════════════════

    function test_commitmentLength_exactly48() public {
        _setSingleBlobHash(BLOB_HASH_1);

        // 47 bytes — too short
        bytes memory short = new bytes(47);
        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidCommitmentLength.selector, 47));
        harness.verifySinglePointByIndex(0, Z_VALUE, Y_VALUE, short, DUMMY_PROOF);

        // 49 bytes — too long
        bytes memory long_ = new bytes(49);
        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidCommitmentLength.selector, 49));
        harness.verifySinglePointByIndex(0, Z_VALUE, Y_VALUE, long_, DUMMY_PROOF);
    }

    function test_proofLength_exactly48() public {
        _setSingleBlobHash(BLOB_HASH_1);

        // 0 bytes
        bytes memory empty = new bytes(0);
        vm.expectRevert(abi.encodeWithSelector(BlobVerifier.InvalidProofLength.selector, 0));
        harness.verifySinglePointByIndex(0, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, empty);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Edge cases
    // ════════════════════════════════════════════════════════════════════

    function test_verifySinglePoint_zeroValues() public {
        _setSingleBlobHash(BLOB_HASH_1);

        bytes32 zeroZ = bytes32(0);
        bytes32 zeroY = bytes32(0);

        _mockPrecompileSuccess(BLOB_HASH_1, zeroZ, zeroY, DUMMY_COMMITMENT, DUMMY_PROOF);

        // z=0 and y=0 are valid field elements
        harness.verifySinglePointByIndex(0, zeroZ, zeroY, DUMMY_COMMITMENT, DUMMY_PROOF);
    }

    function test_multipleVerificationsInSameCall() public {
        _setThreeBlobHashes();

        // Mock precompile for each blob
        _mockPrecompileSuccess(BLOB_HASH_1, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, DUMMY_PROOF);
        _mockPrecompileSuccess(BLOB_HASH_2, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, DUMMY_PROOF);
        _mockPrecompileSuccess(BLOB_HASH_3, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, DUMMY_PROOF);

        // All should succeed
        harness.verifySinglePointByIndex(0, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, DUMMY_PROOF);
        harness.verifySinglePointByIndex(1, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, DUMMY_PROOF);
        harness.verifySinglePointByIndex(2, Z_VALUE, Y_VALUE, DUMMY_COMMITMENT, DUMMY_PROOF);
    }
}
