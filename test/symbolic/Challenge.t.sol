// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {BlobVerifier} from "../../src/BlobVerifier.sol";
import {SymbolicHarness} from "./SymbolicHarness.sol";

/// @notice Halmos: the challenge scalar is keccak(seed, i) mod q with 0 clamped to 1, so it is
///         always a non-zero scalar-field element. Run with `make symbolic`.
contract ChallengeSymbolicTest is Test {
    uint256 constant Q = BlobVerifier.BLS_MODULUS;
    SymbolicHarness h;

    function setUp() public {
        h = new SymbolicHarness();
    }

    function check_challengeScalar_matchesSpecAndIsNonZeroScalar(bytes32 seed, uint256 i) public view {
        uint256 r = h.challengeScalar(seed, i);
        uint256 spec = uint256(keccak256(abi.encode(seed, i))) % Q;
        if (spec == 0) spec = 1;
        assertEq(r, spec);
        assertGe(r, 1);
        assertLt(r, Q);
    }
}
