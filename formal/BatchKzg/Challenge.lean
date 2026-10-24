/-
  The challenge derivation as the Solidity computes it, and the concrete error bound it gives.

  Blober derives `r_i = keccak256(abi.encode(seed, i)) mod q`, clamped to `1` when it is `0`.
  A keccak output is a number `h < 2^256`. Since `2^256 / q = 2`, each residue has at most three
  preimages, and the clamp sends the preimages of `0` to `1`, so no challenge value has more than
  six. Combined with `bad_challenges_card_le_one`, an invalid claim passes for at most six of the
  `2^256` possible outputs of its challenge query.
-/
import BatchKzg.Soundness

open Finset

namespace BatchKzg

set_option linter.unusedSectionVars false

/-- The BLS12-381 scalar field order (`BLS_MODULUS` in `BlobVerifier.sol`). -/
def q : ℕ := 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001

/-- `_challengeScalar`: a keccak output `h`, reduced mod `q`, with `0` clamped to `1`. -/
def chal (h : ℕ) : ℕ := if h % q = 0 then 1 else h % q

theorem q_pos : 0 < q := by norm_num [q]

theorem chal_pos_lt (h : ℕ) : 1 ≤ chal h ∧ chal h < q := by
  unfold chal
  split_ifs with h0
  · exact ⟨le_rfl, by norm_num [q]⟩
  · exact ⟨Nat.pos_of_ne_zero h0, Nat.mod_lt _ q_pos⟩

/-- Below `N`, a residue mod `m` occurs at most `N / m + 1` times: `h ↦ h / m` is injective on
those `h` and lands in `[0, N / m]`. -/
theorem card_mod_eq_le (N m v : ℕ) :
    ((range N).filter fun h => h % m = v).card ≤ N / m + 1 := by
  calc ((range N).filter fun h => h % m = v).card
      ≤ (range (N / m + 1)).card := by
        refine card_le_card_of_injOn (fun h => h / m) ?_ ?_
        · intro h hh
          simp only [coe_filter, mem_range, Set.mem_setOf_eq] at hh
          simp only [coe_range, Set.mem_Iio]
          exact Nat.lt_succ_of_le (Nat.div_le_div_right hh.1.le)
        · intro a ha b hb hab
          simp only [coe_filter, mem_range, Set.mem_setOf_eq] at ha hb
          rw [← Nat.div_add_mod a m, ← Nat.div_add_mod b m, ha.2, hb.2]
          simp only at hab
          rw [hab]
    _ = N / m + 1 := card_range _

theorem two_pow_div_q : 2 ^ 256 / q = 2 := by norm_num [q]

/-- No challenge value has more than six keccak preimages. -/
theorem chal_preimage_card_le (v : ℕ) :
    ((range (2 ^ 256)).filter fun h => chal h = v).card ≤ 6 := by
  have sub : ((range (2 ^ 256)).filter fun h => chal h = v)
      ⊆ ((range (2 ^ 256)).filter fun h => h % q = v)
        ∪ ((range (2 ^ 256)).filter fun h => h % q = 0) := by
    intro h hh
    simp only [mem_filter, mem_union, chal] at hh ⊢
    split_ifs at hh with h0
    · exact Or.inr ⟨hh.1, h0⟩
    · exact Or.inl hh
  calc _ ≤ _ := card_le_card sub
    _ ≤ _ := card_union_le _ _
    _ ≤ (2 ^ 256 / q + 1) + (2 ^ 256 / q + 1) := add_le_add (card_mod_eq_le _ _ _) (card_mod_eq_le _ _ _)
    _ = 6 := by rw [two_pow_div_q]

/-! ### The end-to-end bound

`F` is the scalar field as in `Soundness.lean`; `[CharP F q]` says it has characteristic `q`
(for `F = ZMod q` this holds because `q` is prime, which is standard and not re-proved here). -/

variable {F : Type*} [Field F]
variable {G₁ G₂ Gₜ : Type*} [AddCommGroup G₁] [Module F G₁] [AddCommGroup G₂] [Module F G₂]
  [AddCommGroup Gₜ] [Module F Gₜ]
variable {ι : Type*} [Fintype ι] [DecidableEq ι]
variable (e : G₁ →ₗ[F] G₂ →ₗ[F] Gₜ) (g₁ : G₁) (g₂ τ₂ : G₂)

/-- Distinct naturals below `q` stay distinct in a field of characteristic `q`. -/
theorem natCast_inj_of_lt [CharP F q] {a b : ℕ} (h : (a : F) = b) (ha : a < q) (hb : b < q) :
    a = b := by
  rw [CharP.natCast_eq_natCast F q] at h
  unfold Nat.ModEq at h
  rwa [Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb] at h

/-- If claim `j` is invalid then, whatever the other challenges, at most six of the `2^256`
keccak outputs for `r_j`'s query make the batch pass: error `≤ 6 / 2^256` per query. -/
theorem bad_keccak_outputs_card_le_six [CharP F q] [DecidableEq Gₜ] (cs : ι → Claim F G₁)
    (r : ι → F) (j : ι) (hj : defect e g₁ g₂ τ₂ (cs j) ≠ 0) :
    ((range (2 ^ 256)).filter fun h =>
      batchedCheck e g₁ g₂ τ₂ cs (Function.update r j ((chal h : ℕ) : F)) = 0).card ≤ 6 := by
  rcases ((range (2 ^ 256)).filter fun h =>
      batchedCheck e g₁ g₂ τ₂ cs (Function.update r j ((chal h : ℕ) : F)) = 0).eq_empty_or_nonempty
    with hempty | ⟨h₀, h₀mem⟩
  · rw [hempty, card_empty]; norm_num
  · refine le_trans (card_le_card fun h hmem => ?_) (chal_preimage_card_le (chal h₀))
    simp only [mem_filter] at hmem h₀mem ⊢
    exact ⟨hmem.1, natCast_inj_of_lt
      (at_most_one_bad_challenge e g₁ g₂ τ₂ cs r j hj hmem.2 h₀mem.2)
      (chal_pos_lt h).2 (chal_pos_lt h₀).2⟩

/-- The `G₁` generator's scalar, `ySum == 0 ? 0 : BLS_MODULUS - ySum`, is `-ySum` mod `q`. -/
theorem neg_scalar_encoding (s : ℕ) (hs : s < q) :
    (((if s = 0 then 0 else q - s : ℕ)) : ZMod q) = -(s : ZMod q) := by
  split_ifs with h
  · simp [h]
  · rw [Nat.cast_sub hs.le, ZMod.natCast_self, zero_sub]

end BatchKzg
