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

Not covered here, and stated as assumptions: KZG evaluation binding (q-SDH), keccak as a random
oracle for the Fiat-Shamir challenges, bilinearity of the concrete BLS12-381 pairing, and that the
EIP-2537 / EIP-4844 precompiles compute what their specs say.

## Build

```bash
cd formal
lake exe cache get   # prebuilt Mathlib
lake build
lake env lean Axioms.lean   # prints the axioms each theorem depends on
```

Every theorem depends only on Lean's standard axioms (`propext`, `Classical.choice`, `Quot.sound`);
CI fails if `sorryAx` ever appears.
