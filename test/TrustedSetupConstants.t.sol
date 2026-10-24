// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {BlobVerifier} from "../src/BlobVerifier.sol";
import {Bls12381} from "../src/Bls12381.sol";

/// @notice Pins the hard-coded KZG constants to the EIP-4844 trusted setup. A wrong [τ]₂ or −G₂
///         breaks soundness, so each constant is checked two ways: byte-for-byte against
///         test/fixtures/trusted_setup_constants.json (derived from the ceremony output by
///         test/fixtures/scripts/trusted_setup_constants.py, which checks the file's sha256), and
///         by pairing checks on the real precompiles that do not trust the fixture's derivation.
contract TrustedSetupConstantsTest is Test {
    string json;

    function setUp() public {
        json = vm.readFile("test/fixtures/trusted_setup_constants.json");
    }

    function _fixture(string memory key) internal view returns (bytes memory) {
        return vm.parseJsonBytes(json, string.concat(".", key));
    }

    // ── Byte-for-byte: constants equal the ceremony's points ────────────

    function test_g1Generator_isSetupG1Monomial0() public view {
        assertEq(BlobVerifier.G1_GENERATOR, _fixture("g1Generator"));
    }

    function test_negG2Generator_isMinusSetupG2Monomial0() public view {
        assertEq(BlobVerifier.NEG_G2_GENERATOR, _fixture("negG2Generator"));
    }

    function test_tauG2_isSetupG2Monomial1() public view {
        assertEq(BlobVerifier.KZG_S_G2_MAINNET, _fixture("tauG2"));
    }

    /// @dev Ties the fixture's G1 encodings back to the raw compressed bytes of the setup file,
    ///      through the library's own compression rather than the fixture script.
    function test_g1Encodings_compressToSetupBytes() public view {
        assertEq(Bls12381.compress(_fixture("g1Generator")), _fixture("g1MonomialCompressed0"));
        assertEq(Bls12381.compress(_fixture("tauG1")), _fixture("g1MonomialCompressed1"));
    }

    // ── Pairing checks on the precompiles ───────────────────────────────

    /// @dev e(G₁, G₂) · e(G₁, NEG_G2) = 1 iff NEG_G2 = −G₂ (and both are valid G2 points).
    function test_negG2Generator_negatesG2Generator() public view {
        assertTrue(
            _pair(
                BlobVerifier.G1_GENERATOR,
                _fixture("g2Generator"),
                BlobVerifier.G1_GENERATOR,
                BlobVerifier.NEG_G2_GENERATOR
            )
        );
    }

    /// @dev e([τ]₁, −G₂) · e(G₁, [τ]₂) = 1 iff the hard-coded [τ]₂ carries the same τ as the setup's
    ///      [τ]₁: two independent outputs of the ceremony must agree.
    function test_tauG2_matchesSetupTauG1() public view {
        assertTrue(
            _pair(
                _fixture("tauG1"),
                BlobVerifier.NEG_G2_GENERATOR,
                BlobVerifier.G1_GENERATOR,
                BlobVerifier.KZG_S_G2_MAINNET
            )
        );
    }

    /// @dev And τ ≠ 1: [τ]₂ is not just the generator, so the check above is not trivially true.
    function test_tauG2_isNotGenerator() public view {
        assertFalse(
            _pair(
                BlobVerifier.G1_GENERATOR,
                BlobVerifier.NEG_G2_GENERATOR,
                BlobVerifier.G1_GENERATOR,
                BlobVerifier.KZG_S_G2_MAINNET
            )
        );
    }

    function _pair(bytes memory a1, bytes memory a2, bytes memory b1, bytes memory b2) internal view returns (bool) {
        bytes[] memory g1s = new bytes[](2);
        bytes[] memory g2s = new bytes[](2);
        (g1s[0], g2s[0], g1s[1], g2s[1]) = (a1, a2, b1, b2);
        return Bls12381.pairingCheck(g1s, g2s);
    }
}
