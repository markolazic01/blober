"""Derives the EIP-2537 encodings of the KZG constants BlobVerifier hard-codes from the
official EIP-4844 trusted setup, and writes test/fixtures/trusted_setup_constants.json.

    curl -sLO https://raw.githubusercontent.com/ethereum/c-kzg-4844/37140215cd6fcd99363b7f02bf52f8bf7f6f5968/src/trusted_setup.txt
    pip install py_ecc
    python3 test/fixtures/scripts/trusted_setup_constants.py trusted_setup.txt

trusted_setup.txt layout: "4096", "65", then 4096 G1 Lagrange points, 65 G2 monomial points
[τ^i]₂ and 4096 G1 monomial points [τ^i]₁, all compressed hex.
"""
import hashlib
import json
import sys
from pathlib import Path

from py_ecc.bls.point_compression import decompress_G1, decompress_G2
from py_ecc.optimized_bls12_381 import neg, normalize

SOURCE = "https://raw.githubusercontent.com/ethereum/c-kzg-4844/37140215cd6fcd99363b7f02bf52f8bf7f6f5968/src/trusted_setup.txt"
SHA256 = "d39b9f2d047cc9dca2de58f264b6a09448ccd34db967881a6713eacacf0f26b7"
OUT = Path(__file__).resolve().parents[1] / "trusted_setup_constants.json"


def fp(x) -> str:
    return int(x).to_bytes(64, "big").hex()  # 16 zero bytes || 48-byte big-endian


def g1(point) -> str:
    x, y = normalize(point)
    return "0x" + fp(x) + fp(y)


def g2(point) -> str:
    # EIP-2537 Fp2 order: c0 then c1, for x then y.
    x, y = normalize(point)
    return "0x" + fp(x.coeffs[0]) + fp(x.coeffs[1]) + fp(y.coeffs[0]) + fp(y.coeffs[1])


def main(path: str) -> None:
    raw = Path(path).read_bytes()
    if hashlib.sha256(raw).hexdigest() != SHA256:
        sys.exit(f"{path} is not the pinned trusted setup (sha256 {SHA256})")
    lines = raw.decode().split()
    n1, n2 = int(lines[0]), int(lines[1])
    g2_monomial = lines[2 + n1 : 2 + n1 + n2]
    g1_monomial = lines[2 + n1 + n2 :]

    def d1(h):
        return decompress_G1(int(h, 16))

    def d2(h):
        b = bytes.fromhex(h)
        return decompress_G2((int.from_bytes(b[:48], "big"), int.from_bytes(b[48:], "big")))

    out = {
        "source": SOURCE,
        "sha256": SHA256,
        "g1MonomialCompressed0": "0x" + g1_monomial[0],
        "g1MonomialCompressed1": "0x" + g1_monomial[1],
        "g1Generator": g1(d1(g1_monomial[0])),
        "tauG1": g1(d1(g1_monomial[1])),
        "g2Generator": g2(d2(g2_monomial[0])),
        "negG2Generator": g2(neg(d2(g2_monomial[0]))),
        "tauG2": g2(d2(g2_monomial[1])),
    }
    OUT.write_text(json.dumps(out, indent=2) + "\n")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main(sys.argv[1])
