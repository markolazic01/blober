# Formal proofs

Lean 4 + Mathlib proofs of the algebra behind Blober's batched KZG verifiers.

`BatchKzg/Soundness.lean` models the pairing as an abstract `F`-bilinear map
`e : G₁ →ₗ[F] G₂ →ₗ[F] Gₜ`, so nothing depends on BLS12-381 specifically. It proves:

| Theorem | Statement |
| --- | --- |
| `batchedCheck_eq` | The batched pairing value `e(LHS, −G₂) + e(RHS, [τ]₂)` equals `Σ rᵢ · defectᵢ`, where `defectᵢ` is claim i's single-opening check |
| `complete` | If every claim is valid, the batch passes for every choice of challenges |
| `at_most_one_bad_challenge` | If claim j is invalid, at most one value of `r_j` (others fixed) makes the batch pass |
| `bad_challenges_card_le_one` | The same, as a count over the scalar field: soundness error ≤ 1/q per challenge |
| `sharedZ_eq`, `sharedC_eq` | The many-blobs (shared z) and one-blob (shared C) LHS factorisations equal the general LHS |
| `chal_pos_lt` | The challenge as the Solidity computes it (`keccak mod q`, `0` clamped to `1`) is always in `[1, q)` |
| `chal_preimage_card_le` | No challenge value has more than 6 of the `2^256` keccak outputs as preimages |
| `bad_keccak_outputs_card_le_six` | If claim j is invalid, at most 6 keccak outputs for `r_j`'s query make the batch pass |
| `neg_scalar_encoding` | The generator's scalar `ySum == 0 ? 0 : q - ySum` is `-ySum` mod q |

`BatchKzg/Challenge.lean` turns the 1/q bound into the concrete one for the deployed derivation.
Since `2^256 / q = 2`, a residue has at most 3 keccak preimages, and the clamp gives the value 1
the preimages of 0 as well, so the error per oracle query is at most `6 / 2^256` (about
`2^-253.4`). In the random-oracle model an attacker making Q keccak queries therefore succeeds
with probability at most `Q · 6 / 2^256`. That union bound is argued rather than proven here. That
the transcript hashes every input is proven against the Solidity code with Halmos, in
`test/symbolic/Transcript.t.sol`.

Not covered here, and stated as assumptions: KZG evaluation binding (q-SDH), keccak as a random
oracle for the Fiat-Shamir challenges, bilinearity of the concrete BLS12-381 pairing, that the
EIP-2537 / EIP-4844 precompiles compute what their specs say, and that `q` is prime (the end-to-end
bound takes the scalar field as any field of characteristic `q`).

## Build

```bash
cd formal
lake exe cache get   # prebuilt Mathlib
lake build
lake env lean Axioms.lean   # prints the axioms each theorem depends on
```

Every theorem depends only on Lean's standard axioms (`propext`, `Classical.choice`, `Quot.sound`);
CI fails if `sorryAx` ever appears.
