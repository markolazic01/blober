// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {SymbolicHarness} from "./SymbolicHarness.sol";

/// @notice Halmos: the encoding check and the 128 → 48-byte compression match their specs for
///         every 128-byte input. The specs split each 48-byte coordinate into three 16-byte limbs,
///         a different decomposition from the library's 16 + 32-byte words, so they are not a copy
///         of the code under test. Run with `make symbolic`.
contract EncodingSymbolicTest is Test {
    SymbolicHarness h;

    /// @dev BLS12-381 base field modulus p and (p − 1) / 2, as three big-endian 16-byte limbs.
    uint128 constant P0 = 0x1a0111ea397fe69a4b1ba7b6434bacd7;
    uint128 constant P1 = 0x64774b84f38512bf6730d2a0f6b0f624;
    uint128 constant P2 = 0x1eabfffeb153ffffb9feffffffffaaab;
    uint128 constant H0 = 0x0d0088f51cbff34d258dd3db21a5d66b;
    uint128 constant H1 = 0xb23ba5c279c2895fb39869507b587b12;
    uint128 constant H2 = 0x0f55ffff58a9ffffdcff7fffffffd555;

    function setUp() public {
        h = new SymbolicHarness();
    }

    /// @dev EIP-2537: a G1 point is canonical iff both 16-byte paddings are zero and x, y < p.
    function check_requireCanonical_matchesSpec(bytes32 w0, bytes32 w1, bytes32 w2, bytes32 w3) public view {
        bool spec = _canonical(w0, w1, w2, w3);
        try h.requireCanonical(bytes.concat(w0, w1, w2, w3)) {
            assertTrue(spec);
        } catch {
            assertFalse(spec);
        }
    }

    /// @dev ZCash / EIP-4844 compression of a canonical point: infinity is 0xc0 || 0^47; otherwise
    ///      x with flag 0x80 (compressed) and 0x20 iff y > (p − 1) / 2.
    function check_compress_matchesSpec(bytes32 w0, bytes32 w1, bytes32 w2, bytes32 w3) public view {
        vm.assume(_canonical(w0, w1, w2, w3));
        bytes memory out = h.compress(bytes.concat(w0, w1, w2, w3));
        assertEq(out.length, 48);

        (uint128 x0, uint128 x1, uint128 x2) = _limbs(w0, w1);
        (uint128 y0, uint128 y1, uint128 y2) = _limbs(w2, w3);
        uint256 flags;
        if (x0 | x1 | x2 | y0 | y1 | y2 == 0) {
            flags = 0xc0;
        } else {
            flags = _lt(H0, H1, H2, y0, y1, y2) ? 0xa0 : 0x80;
        }
        assertEq(_word(out, 0), bytes32((flags << 248) | (uint256(x0) << 128) | uint256(x1)));
        assertEq(_word(out, 16), bytes32((uint256(x1) << 128) | uint256(x2)));
    }

    function _canonical(bytes32 w0, bytes32 w1, bytes32 w2, bytes32 w3) internal pure returns (bool) {
        (uint128 x0, uint128 x1, uint128 x2) = _limbs(w0, w1);
        (uint128 y0, uint128 y1, uint128 y2) = _limbs(w2, w3);
        bool padsZero = uint256(w0) >> 128 == 0 && uint256(w2) >> 128 == 0;
        return padsZero && _lt(x0, x1, x2, P0, P1, P2) && _lt(y0, y1, y2, P0, P1, P2);
    }

    /// @dev The coordinate in (16 B pad || 16 B) and (32 B) words, as limbs of its 48 bytes.
    function _limbs(bytes32 hi, bytes32 lo) internal pure returns (uint128, uint128, uint128) {
        return (uint128(uint256(hi)), uint128(uint256(lo) >> 128), uint128(uint256(lo)));
    }

    /// @dev (a0, a1, a2) < (b0, b1, b2), lexicographically.
    function _lt(uint128 a0, uint128 a1, uint128 a2, uint128 b0, uint128 b1, uint128 b2) internal pure returns (bool) {
        return a0 < b0 || (a0 == b0 && (a1 < b1 || (a1 == b1 && a2 < b2)));
    }

    function _word(bytes memory b, uint256 off) internal pure returns (bytes32 v) {
        assembly ("memory-safe") {
            v := mload(add(add(b, 0x20), off))
        }
    }
}
