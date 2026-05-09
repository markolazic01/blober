// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Bls12381
/// @notice Thin wrappers around the EIP-2537 BLS12-381 precompiles used for
///         batched KZG proof verification.
/// @dev Encoding (per EIP-2537):
///        - field element: 64 bytes (16 zero bytes || 48-byte big-endian fp)
///        - G1 point:      128 bytes — two field elements (x || y)
///        - G2 point:      256 bytes — two fp2 elements
///        - scalar:        32 bytes  — big-endian
library Bls12381 {
    // ──────────────────────────────────────────────────────────────────────
    //  Precompile addresses (EIP-2537)
    // ──────────────────────────────────────────────────────────────────────

    address internal constant G1ADD_PRECOMPILE   = address(0x0B);
    address internal constant G1MSM_PRECOMPILE   = address(0x0C);
    address internal constant PAIRING_PRECOMPILE = address(0x0F);

    // ──────────────────────────────────────────────────────────────────────
    //  Sizes
    // ──────────────────────────────────────────────────────────────────────

    uint256 internal constant G1_POINT_SIZE = 128;
    uint256 internal constant G2_POINT_SIZE = 256;
    uint256 internal constant PAIRING_OUTPUT_SIZE = 32;

    // ──────────────────────────────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────────────────────────────

    error EmptyInput();
    error LengthMismatch();
    error InvalidG1PointLength(uint256 actual);
    error InvalidG2PointLength(uint256 actual);
    error PrecompileCallFailed(address precompile);
    error UnexpectedPrecompileOutput(address precompile);

    // ──────────────────────────────────────────────────────────────────────
    //  Operations
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Add two G1 points: returns a + b.
    /// @dev Calls the BLS12_G1ADD precompile (0x0B). Cheaper than `g1Msm` with
    ///      scalars [1, 1] and reads more clearly when you just need to compose
    ///      two G1 points (e.g., subtraction via add-with-negated-point).
    /// @param a 128-byte G1 point.
    /// @param b 128-byte G1 point.
    /// @return One G1 point (128 bytes) — the sum a + b.
    function g1Add(bytes memory a, bytes memory b) internal view returns (bytes memory) {
        _requireG1Length(a);
        _requireG1Length(b);
        // Fixed 256-byte input — no loop, no allocation tuning needed.
        return _staticcall(G1ADD_PRECOMPILE, abi.encodePacked(a, b), G1_POINT_SIZE);
    }

    /// @notice Multi-scalar multiplication on G1: returns Σ scalars[i] * points[i].
    /// @dev Calls the BLS12_G1MSM precompile (0x0C). The precompile expects an
    /// input laid out as [128-byte G1 point || 32-byte scalar] per entry.
    /// @param points  G1 points (128 bytes each).
    /// @param scalars Scalars (32 bytes each); scalars[i] pairs with points[i].
    /// @return result One G1 point (128 bytes) — the resulting sum.
    function g1Msm(bytes[] memory points, bytes32[] memory scalars) internal view returns (bytes memory result) {
        uint256 n = points.length;
        if (n == 0) revert EmptyInput();
        if (n != scalars.length) revert LengthMismatch();

        // The precompile expects one contiguous buffer of n slots, each slot
        // = [128-byte G1 point || 32-byte scalar] = 160 bytes. We allocate the
        // final-size buffer up front and write each slot directly into it, so
        // total memory traffic is O(n). (Repeated abi.encodePacked would be
        // O(n²) — each iteration re-allocates and re-copies the running buffer.)
        uint256 slotSize = G1_POINT_SIZE + 32;
        bytes memory input = new bytes(n * slotSize);

        for (uint256 i; i < n; ++i) {
            bytes memory point = points[i];
            _requireG1Length(point);
            bytes32 scalar = scalars[i];

            // Solidity `bytes memory` layout: word-0 holds the length, payload
            // starts at ptr + 0x20. We use mcopy (EIP-5656, Cancun) for the
            // point and mstore for the 32-byte scalar that follows it.
            //
            // "memory-safe" annotation: every write lands inside `input` (which
            // Solidity allocated above) and we don't touch the free memory
            // pointer — so the optimizer is free to reorder memory operations.
            assembly ("memory-safe") {
                let dst := add(add(input, 0x20), mul(i, slotSize))
                mcopy(dst, add(point, 0x20), 128) // copy G1 point
                mstore(add(dst, 128), scalar)     // append scalar
            }
        }

        return _staticcall(G1MSM_PRECOMPILE, input, G1_POINT_SIZE);
    }

    /// @notice Multi-pairing check: returns true iff Π e(g1Points[i], g2Points[i]) == 1 in GT.
    /// @dev Calls the BLS12_PAIRING_CHECK precompile (0x0F). Output is a 32-byte
    ///      big-endian boolean (1 = paired, 0 = not).
    /// @param g1Points G1 points (128 bytes each).
    /// @param g2Points G2 points (256 bytes each); g2Points[i] pairs with g1Points[i].
    function pairingCheck(bytes[] memory g1Points, bytes[] memory g2Points) internal view returns (bool) {
        uint256 n = g1Points.length;
        if (n == 0) revert EmptyInput();
        if (n != g2Points.length) revert LengthMismatch();

        // Each slot: [128-byte G1 point || 256-byte G2 point] = 384 bytes.
        // See g1Msm above for the rationale behind pre-allocate + mcopy.
        uint256 slotSize = G1_POINT_SIZE + G2_POINT_SIZE;
        bytes memory input = new bytes(n * slotSize);

        for (uint256 i; i < n; ++i) {
            bytes memory g1 = g1Points[i];
            bytes memory g2 = g2Points[i];
            _requireG1Length(g1);
            _requireG2Length(g2);

            // mcopy both points; "memory-safe" — writes stay inside `input`
            // and we don't touch the free memory pointer.
            assembly ("memory-safe") {
                let dst := add(add(input, 0x20), mul(i, slotSize))
                mcopy(dst, add(g1, 0x20), 128)
                mcopy(add(dst, 128), add(g2, 0x20), 256)
            }
        }

        bytes memory output = _staticcall(PAIRING_PRECOMPILE, input, PAIRING_OUTPUT_SIZE);
        return abi.decode(output, (uint256)) == 1;
    }

    // ──────────────────────────────────────────────────────────────────────
    //  Internals
    // ──────────────────────────────────────────────────────────────────────

    function _staticcall(address precompile, bytes memory input, uint256 expectedOutputLength)
        private
        view
        returns (bytes memory output)
    {
        bool ok;
        (ok, output) = precompile.staticcall(input);
        if (!ok) revert PrecompileCallFailed(precompile);
        if (output.length != expectedOutputLength) revert UnexpectedPrecompileOutput(precompile);
    }

    function _requireG1Length(bytes memory point) private pure {
        if (point.length != G1_POINT_SIZE) revert InvalidG1PointLength(point.length);
    }

    function _requireG2Length(bytes memory point) private pure {
        if (point.length != G2_POINT_SIZE) revert InvalidG2PointLength(point.length);
    }
}
