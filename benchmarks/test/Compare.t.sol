// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {BlobVerifier} from "blob-verifier/BlobVerifier.sol";
import {LoopVerifier} from "../src/LoopVerifier.sol";

/// @dev Tiny harness exposing the batched verifiers as external view functions,
///      matching the surface of `LoopVerifier` so we measure same-shape calls.
contract BatchedVerifier {
    function verifyBatchedMultiBlob(
        bytes32[] calldata blobHashes,
        bytes32 z,
        bytes32[] calldata y,
        bytes[] calldata commitments,
        bytes[] calldata proofs
    ) external view {
        BlobVerifier.verifySinglePointMultipleBlobs128(blobHashes, z, y, commitments, proofs);
    }

    function verifyBatchedMultiPoint(
        bytes32 blobHash,
        bytes32[] calldata z,
        bytes32[] calldata y,
        bytes calldata commitment,
        bytes[] calldata proofs
    ) external view {
        BlobVerifier.verifyMultiplePoints128(blobHash, z, y, commitment, proofs);
    }
}

/// @notice Side-by-side gas comparison: industry-standard 0x0A loop vs. our
///         EIP-2537 batched verifiers. Two scenarios:
///           - many blobs, one shared z (verifySinglePointMultipleBlobs128)
///           - one blob, many distinct z   (verifyMultiplePoints128)
contract Compare is Test {
    LoopVerifier loopVerifier;
    BatchedVerifier batchedVerifier;

    // ── Multi-blob fixture (one shared z) ───────────────────────────────
    bytes32 mbZ;
    bytes32[] mbBlobHashes;
    bytes[] mbCommitmentsCompressed;
    bytes[] mbCommitmentsUncompressed;
    bytes32[] mbY;
    bytes[] mbProofsCompressed;
    bytes[] mbProofsUncompressed;

    // ── Multi-point fixture (one blob, many z) ──────────────────────────
    bytes32 mpBlobHash;
    bytes mpCommitmentCompressed;
    bytes mpCommitmentUncompressed;
    bytes32[] mpZ;
    bytes32[] mpY;
    bytes[] mpProofsCompressed;
    bytes[] mpProofsUncompressed;

    uint256[16] internal SWEEP = [uint256(1), 2, 3, 4, 5, 10, 25, 50, 100, 150, 200, 300, 400, 500, 700, 1000];

    function setUp() public {
        loopVerifier = new LoopVerifier();
        batchedVerifier = new BatchedVerifier();

        // Multi-blob fixture
        string memory mb = vm.readFile("data/fixtures_multi_blob.json");
        mbZ = vm.parseJsonBytes32(mb, ".z");
        mbBlobHashes = vm.parseJsonBytes32Array(mb, ".blobHashes");
        mbCommitmentsCompressed = vm.parseJsonBytesArray(mb, ".commitmentsCompressed");
        mbCommitmentsUncompressed = vm.parseJsonBytesArray(mb, ".commitmentsUncompressed");
        mbY = vm.parseJsonBytes32Array(mb, ".y");
        mbProofsCompressed = vm.parseJsonBytesArray(mb, ".proofsCompressed");
        mbProofsUncompressed = vm.parseJsonBytesArray(mb, ".proofsUncompressed");

        // Multi-point fixture
        string memory mp = vm.readFile("data/fixtures_multi_point.json");
        mpBlobHash = vm.parseJsonBytes32(mp, ".blobHash");
        mpCommitmentCompressed = vm.parseJsonBytes(mp, ".commitmentCompressed");
        mpCommitmentUncompressed = vm.parseJsonBytes(mp, ".commitmentUncompressed");
        mpZ = vm.parseJsonBytes32Array(mp, ".z");
        mpY = vm.parseJsonBytes32Array(mp, ".y");
        mpProofsCompressed = vm.parseJsonBytesArray(mp, ".proofsCompressed");
        mpProofsUncompressed = vm.parseJsonBytesArray(mp, ".proofsUncompressed");
    }

    // ────────────────────────────────────────────────────────────────────
    //  Multi-blob, shared z (verifySinglePointMultipleBlobs128)
    // ────────────────────────────────────────────────────────────────────

    function test_compare_gas_multi_blob_one_point() public {
        string memory csv = "n,gas_loop,gas_batched,batched_pct_of_loop,saved_pct\n";

        console2.log("=== Multi-blob, shared z ===");
        for (uint256 i; i < SWEEP.length; ++i) {
            (uint256 gasLoop, uint256 gasBatched) = _measureMultiBlob(SWEEP[i]);
            _logRow(SWEEP[i], gasLoop, gasBatched);
            csv = _appendRow(csv, SWEEP[i], gasLoop, gasBatched);
        }

        vm.writeFile("data/synthetic_gas_multi_blob_one_point.csv", csv);
        console2.log("Wrote data/synthetic_gas_multi_blob_one_point.csv");
    }

    function _measureMultiBlob(uint256 n) internal view returns (uint256 gasLoop, uint256 gasBatched) {
        bytes32[] memory blobHashes = _sliceBytes32(mbBlobHashes, n);
        bytes32[] memory ys = _sliceBytes32(mbY, n);
        bytes[] memory comm48 = _sliceBytes(mbCommitmentsCompressed, n);
        bytes[] memory proof48 = _sliceBytes(mbProofsCompressed, n);
        bytes[] memory comm128 = _sliceBytes(mbCommitmentsUncompressed, n);
        bytes[] memory proof128 = _sliceBytes(mbProofsUncompressed, n);

        uint256 g1 = gasleft();
        loopVerifier.verifyLoop(blobHashes, mbZ, ys, comm48, proof48);
        gasLoop = g1 - gasleft();

        uint256 g2 = gasleft();
        batchedVerifier.verifyBatchedMultiBlob(blobHashes, mbZ, ys, comm128, proof128);
        gasBatched = g2 - gasleft();
    }

    // ────────────────────────────────────────────────────────────────────
    //  Multi-point, one blob (verifyMultiplePoints128)
    // ────────────────────────────────────────────────────────────────────

    function test_compare_gas_multi_point_one_blob() public {
        string memory csv = "n,gas_loop,gas_batched,batched_pct_of_loop,saved_pct\n";

        console2.log("=== Multi-point, one blob ===");
        for (uint256 i; i < SWEEP.length; ++i) {
            (uint256 gasLoop, uint256 gasBatched) = _measureMultiPoint(SWEEP[i]);
            _logRow(SWEEP[i], gasLoop, gasBatched);
            csv = _appendRow(csv, SWEEP[i], gasLoop, gasBatched);
        }

        vm.writeFile("data/synthetic_gas_multi_point_one_blob.csv", csv);
        console2.log("Wrote data/synthetic_gas_multi_point_one_blob.csv");
    }

    function _measureMultiPoint(uint256 n) internal view returns (uint256 gasLoop, uint256 gasBatched) {
        bytes32[] memory zs = _sliceBytes32(mpZ, n);
        bytes32[] memory ys = _sliceBytes32(mpY, n);
        bytes[] memory proof48 = _sliceBytes(mpProofsCompressed, n);
        bytes[] memory proof128 = _sliceBytes(mpProofsUncompressed, n);

        uint256 g1 = gasleft();
        loopVerifier.verifyLoopMultiPoint(mpBlobHash, zs, ys, mpCommitmentCompressed, proof48);
        gasLoop = g1 - gasleft();

        uint256 g2 = gasleft();
        batchedVerifier.verifyBatchedMultiPoint(mpBlobHash, zs, ys, mpCommitmentUncompressed, proof128);
        gasBatched = g2 - gasleft();
    }

    // ────────────────────────────────────────────────────────────────────
    //  Shared helpers
    // ────────────────────────────────────────────────────────────────────

    function _logRow(uint256 n, uint256 gasLoop, uint256 gasBatched) internal pure {
        uint256 saved = gasLoop == 0 || gasBatched >= gasLoop ? 0 : 100 - (gasBatched * 100) / gasLoop;
        console2.log("N=", n);
        console2.log("  gas_loop   ", gasLoop);
        console2.log("  gas_batched", gasBatched);
        console2.log("  saved%     ", saved);
    }

    function _appendRow(string memory csv, uint256 n, uint256 gasLoop, uint256 gasBatched)
        internal
        view
        returns (string memory)
    {
        uint256 ratio = gasLoop == 0 ? 0 : (gasBatched * 100) / gasLoop;
        int256 saved = int256(100) - int256(ratio);
        return string.concat(
            csv,
            vm.toString(n),
            ",",
            vm.toString(gasLoop),
            ",",
            vm.toString(gasBatched),
            ",",
            vm.toString(ratio),
            ",",
            vm.toString(saved),
            "\n"
        );
    }

    function _sliceBytes32(bytes32[] storage arr, uint256 n) internal view returns (bytes32[] memory out) {
        out = new bytes32[](n);
        for (uint256 i; i < n; ++i) out[i] = arr[i];
    }

    function _sliceBytes(bytes[] storage arr, uint256 n) internal view returns (bytes[] memory out) {
        out = new bytes[](n);
        for (uint256 i; i < n; ++i) out[i] = arr[i];
    }
}
