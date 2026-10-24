// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {BlobVerifier} from "../../src/BlobVerifier.sol";
import {SymbolicHarness} from "./SymbolicHarness.sol";

/// @notice Halmos: for all inputs, the MSM buffers each batched verifier hands to 0x0C hold exactly
///         the points and scalars of the batched equation proven in formal/BatchKzg/Soundness.lean:
///           general:  LHS = Σ r_i·C_i + Σ (r_i·z_i)·π_i − (Σ r_i·y_i)·G     RHS = Σ r_i·π_i
///           shared z: LHS = Σ r_i·C_i + z·RHS − (Σ r_i·y_i)·G
///           shared C: LHS = Σ (r_i·z_i)·π_i + (Σ r_i)·C − (Σ r_i·y_i)·G
///         with r_i = keccak(seed, i) mod q (0 → 1). Points are fully symbolic 128-byte strings;
///         z_i, y_i are symbolic scalars below q (validated before the builders run).
///         Every check takes room for three claims and uses the first n.
///         Checked for n = 1, 2, 3: the builders have no n-dependent branches, so the layout
///         argument is the same for every n. Run with `make symbolic`.
contract MsmInputsSymbolicTest is Test {
    uint256 constant Q = BlobVerifier.BLS_MODULUS;
    uint256 constant SLOT = 160;
    SymbolicHarness h;

    function setUp() public {
        h = new SymbolicHarness();
    }

    // ── General shape ───────────────────────────────────────────────────

    function check_generalMsmInputs_n1(bytes32 seed, bytes32[24] calldata w, bytes32[6] calldata s) public view {
        _checkGeneral(seed, 1, w, s);
    }

    function check_generalMsmInputs_n2(bytes32 seed, bytes32[24] calldata w, bytes32[6] calldata s) public view {
        _checkGeneral(seed, 2, w, s);
    }

    function check_generalMsmInputs_n3(bytes32 seed, bytes32[24] calldata w, bytes32[6] calldata s) public view {
        _checkGeneral(seed, 3, w, s);
    }

    /// @dev Claim i: commitment = w[8i..8i+4], proof = w[8i+4..8i+8], z = s[2i], y = s[2i+1].
    function _checkGeneral(bytes32 seed, uint256 n, bytes32[24] calldata w, bytes32[6] calldata s) internal view {
        (bytes32[] memory zs, bytes32[] memory ys, bytes[] memory cs, bytes[] memory ps) = _claims(n, w, s);
        (bytes memory lhs, bytes memory rhs) = h.generalMsmInputs(seed, zs, ys, cs, ps);

        assertEq(lhs.length, (2 * n + 1) * SLOT);
        assertEq(rhs.length, n * SLOT);
        uint256 ySum;
        for (uint256 i; i < n; ++i) {
            uint256 r = _r(seed, i);
            ySum = addmod(ySum, mulmod(r, uint256(ys[i]), Q), Q);
            _assertSlot(lhs, i, cs[i], r);
            _assertSlot(lhs, n + i, ps[i], mulmod(r, uint256(zs[i]), Q));
            _assertSlot(rhs, i, ps[i], r);
        }
        _assertSlot(lhs, 2 * n, BlobVerifier.G1_GENERATOR, _neg(ySum));
    }

    // ── Shared z (many blobs, one point) ────────────────────────────────

    function check_sharedZMsmInputs_n1(bytes32 seed, bytes32 z, bytes32[24] calldata w, bytes32[6] calldata s)
        public
        view
    {
        _checkSharedZ(seed, z, 1, w, s);
    }

    function check_sharedZMsmInputs_n2(bytes32 seed, bytes32 z, bytes32[24] calldata w, bytes32[6] calldata s)
        public
        view
    {
        _checkSharedZ(seed, z, 2, w, s);
    }

    function check_sharedZMsmInputs_n3(bytes32 seed, bytes32 z, bytes32[24] calldata w, bytes32[6] calldata s)
        public
        view
    {
        _checkSharedZ(seed, z, 3, w, s);
    }

    function _checkSharedZ(bytes32 seed, bytes32 z, uint256 n, bytes32[24] calldata w, bytes32[6] calldata s)
        internal
        view
    {
        vm.assume(uint256(z) < Q);
        (, bytes32[] memory ys, bytes[] memory cs, bytes[] memory ps) = _claims(n, w, s);
        (bytes memory lhs, bytes memory rhs) = h.sharedZMsmInputs(seed, z, ys, cs, ps);

        assertEq(lhs.length, (n + 2) * SLOT);
        assertEq(rhs.length, n * SLOT);
        uint256 ySum;
        for (uint256 i; i < n; ++i) {
            uint256 r = _r(seed, i);
            ySum = addmod(ySum, mulmod(r, uint256(ys[i]), Q), Q);
            _assertSlot(lhs, i, cs[i], r);
            _assertSlot(rhs, i, ps[i], r);
        }
        // Slot n carries z; the verifier writes RHS = Σ r_i·π_i into its point after the RHS MSM.
        assertEq(_word(lhs, n * SLOT + 128), z);
        _assertSlot(lhs, n + 1, BlobVerifier.G1_GENERATOR, _neg(ySum));
    }

    // ── Shared C (one blob, many points) ────────────────────────────────

    function check_sharedCMsmInputs_n1(bytes32 seed, bytes32[24] calldata w, bytes32[6] calldata s) public view {
        _checkSharedC(seed, 1, w, s);
    }

    function check_sharedCMsmInputs_n2(bytes32 seed, bytes32[24] calldata w, bytes32[6] calldata s) public view {
        _checkSharedC(seed, 2, w, s);
    }

    function check_sharedCMsmInputs_n3(bytes32 seed, bytes32[24] calldata w, bytes32[6] calldata s) public view {
        _checkSharedC(seed, 3, w, s);
    }

    /// @dev The shared commitment is claim 0's commitment words; the other claims' are unused.
    function _checkSharedC(bytes32 seed, uint256 n, bytes32[24] calldata w, bytes32[6] calldata s) internal view {
        (bytes32[] memory zs, bytes32[] memory ys, bytes[] memory cs, bytes[] memory ps) = _claims(n, w, s);
        (bytes memory lhs, bytes memory rhs) = h.sharedCMsmInputs(seed, zs, ys, cs[0], ps);

        assertEq(lhs.length, (n + 2) * SLOT);
        assertEq(rhs.length, n * SLOT);
        uint256 rSum;
        uint256 ySum;
        for (uint256 i; i < n; ++i) {
            uint256 r = _r(seed, i);
            rSum = addmod(rSum, r, Q);
            ySum = addmod(ySum, mulmod(r, uint256(ys[i]), Q), Q);
            _assertSlot(lhs, i, ps[i], mulmod(r, uint256(zs[i]), Q));
            _assertSlot(rhs, i, ps[i], r);
        }
        _assertSlot(lhs, n, cs[0], rSum);
        _assertSlot(lhs, n + 1, BlobVerifier.G1_GENERATOR, _neg(ySum));
    }

    // ── Spec helpers ────────────────────────────────────────────────────

    /// @dev The challenge as specified: keccak(seed, i) mod q, with 0 mapped to 1.
    function _r(bytes32 seed, uint256 i) internal pure returns (uint256 r) {
        r = uint256(keccak256(abi.encode(seed, i))) % Q;
        if (r == 0) r = 1;
    }

    /// @dev −x in the scalar field, written as (q − x) mod q.
    function _neg(uint256 x) internal pure returns (uint256) {
        return (Q - x) % Q;
    }

    function _claims(uint256 n, bytes32[24] calldata w, bytes32[6] calldata s)
        internal
        pure
        returns (bytes32[] memory zs, bytes32[] memory ys, bytes[] memory cs, bytes[] memory ps)
    {
        zs = new bytes32[](n);
        ys = new bytes32[](n);
        cs = new bytes[](n);
        ps = new bytes[](n);
        for (uint256 i; i < n; ++i) {
            zs[i] = s[2 * i];
            ys[i] = s[2 * i + 1];
            vm.assume(uint256(zs[i]) < Q && uint256(ys[i]) < Q);
            uint256 b = 8 * i;
            cs[i] = bytes.concat(w[b], w[b + 1], w[b + 2], w[b + 3]);
            ps[i] = bytes.concat(w[b + 4], w[b + 5], w[b + 6], w[b + 7]);
        }
    }

    function _assertSlot(bytes memory buf, uint256 k, bytes memory point, uint256 scalar) internal pure {
        uint256 off = k * SLOT;
        for (uint256 j; j < 4; ++j) {
            assertEq(_word(buf, off + 32 * j), _word(point, 32 * j));
        }
        assertEq(uint256(_word(buf, off + 128)), scalar);
    }

    function _word(bytes memory buf, uint256 off) internal pure returns (bytes32 v) {
        assembly ("memory-safe") {
            v := mload(add(add(buf, 0x20), off))
        }
    }
}
