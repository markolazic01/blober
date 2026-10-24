// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {SymbolicHarness} from "./SymbolicHarness.sol";

/// @notice Halmos: the Fiat-Shamir seed binds every caller-controlled input. If two inputs give
///         the same seed, they are the same input, so a prover cannot change any proof, value,
///         point or commitment after the challenges are fixed (the Last Challenge Attack class,
///         ePrint 2024/398). Halmos models keccak256 as collision-free, which is exactly the
///         assumption under which this holds. Checked for n = 2; the encoding is abi.encode with
///         a per-shape domain string, so the argument does not depend on n.
///         Run with `make symbolic`.
contract TranscriptSymbolicTest is Test {
    SymbolicHarness h;

    struct Claims {
        bytes32[] hashes;
        bytes32[] zs;
        bytes32[] ys;
        bytes[] cs;
        bytes[] ps;
    }

    function setUp() public {
        h = new SymbolicHarness();
    }

    function check_seedGeneral_bindsEveryInput(bytes32[26] calldata a, bytes32[26] calldata b) public view {
        Claims memory x = _claims(a);
        Claims memory y = _claims(b);
        vm.assume(h.seedGeneral(x.hashes, x.zs, x.ys, x.cs, x.ps) == h.seedGeneral(y.hashes, y.zs, y.ys, y.cs, y.ps));
        _assertSame(x, y);
        for (uint256 i; i < 2; ++i) {
            assertEq(x.zs[i], y.zs[i]);
        }
    }

    function check_seedSharedZ_bindsEveryInput(bytes32[26] calldata a, bytes32[26] calldata b) public view {
        Claims memory x = _claims(a);
        Claims memory y = _claims(b);
        vm.assume(
            h.seedSharedZ(x.hashes, x.zs[0], x.ys, x.cs, x.ps) == h.seedSharedZ(y.hashes, y.zs[0], y.ys, y.cs, y.ps)
        );
        _assertSame(x, y);
        assertEq(x.zs[0], y.zs[0]);
    }

    function check_seedSharedC_bindsEveryInput(bytes32[26] calldata a, bytes32[26] calldata b) public view {
        Claims memory x = _claims(a);
        Claims memory y = _claims(b);
        vm.assume(
            h.seedSharedC(x.hashes[0], x.zs, x.ys, x.cs[0], x.ps)
                == h.seedSharedC(y.hashes[0], y.zs, y.ys, y.cs[0], y.ps)
        );
        assertEq(x.hashes[0], y.hashes[0]);
        assertEq(keccak256(x.cs[0]), keccak256(y.cs[0]));
        for (uint256 i; i < 2; ++i) {
            assertEq(x.zs[i], y.zs[i]);
            assertEq(x.ys[i], y.ys[i]);
            assertEq(keccak256(x.ps[i]), keccak256(y.ps[i]));
        }
    }

    /// @dev Different shapes never share a seed, even on overlapping inputs (domain separation).
    function check_seeds_domainSeparated(bytes32[26] calldata a) public view {
        Claims memory x = _claims(a);
        bytes32 g = h.seedGeneral(x.hashes, x.zs, x.ys, x.cs, x.ps);
        assertNotEq(g, h.seedSharedZ(x.hashes, x.zs[0], x.ys, x.cs, x.ps));
        assertNotEq(g, h.seedSharedC(x.hashes[0], x.zs, x.ys, x.cs[0], x.ps));
    }

    /// @dev Layout of the 26 words for two claims: hash, z, y, then 4 commitment and 4 proof words, per claim.
    function _claims(bytes32[26] calldata w) internal pure returns (Claims memory c) {
        c.hashes = new bytes32[](2);
        c.zs = new bytes32[](2);
        c.ys = new bytes32[](2);
        c.cs = new bytes[](2);
        c.ps = new bytes[](2);
        for (uint256 i; i < 2; ++i) {
            uint256 o = 13 * i;
            c.hashes[i] = w[o];
            c.zs[i] = w[o + 1];
            c.ys[i] = w[o + 2];
            c.cs[i] = bytes.concat(w[o + 3], w[o + 4], w[o + 5], w[o + 6]);
            c.ps[i] = bytes.concat(w[o + 7], w[o + 8], w[o + 9], w[o + 10]);
        }
    }

    function _assertSame(Claims memory x, Claims memory y) internal pure {
        for (uint256 i; i < 2; ++i) {
            assertEq(x.hashes[i], y.hashes[i]);
            assertEq(x.ys[i], y.ys[i]);
            assertEq(keccak256(x.cs[i]), keccak256(y.cs[i]));
            assertEq(keccak256(x.ps[i]), keccak256(y.ps[i]));
        }
    }
}
