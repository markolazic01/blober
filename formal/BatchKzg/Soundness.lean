/-
  Batched KZG point evaluation: the algebraic core of the soundness argument.

  The pairing is modelled abstractly as an `F`-bilinear map `e : G₁ →ₗ G₂ →ₗ Gₜ` over the
  scalar field `F` (for BLS12-381, `F = ZMod q`). The group laws are written additively, so
  "the pairing product equals 1" becomes "the sum equals 0". Nothing here depends on the curve.
-/
import Mathlib

open Finset

namespace BatchKzg

variable {F : Type*} [Field F]
variable {G₁ G₂ Gₜ : Type*} [AddCommGroup G₁] [Module F G₁] [AddCommGroup G₂] [Module F G₂]
  [AddCommGroup Gₜ] [Module F Gₜ]
variable {ι : Type*} [Fintype ι] [DecidableEq ι]
set_option linter.unusedSectionVars false

/-- One opening claim with the versioned hash already checked: commitment, point, value, proof. -/
structure Claim (F G₁ : Type*) where
  C : G₁
  z : F
  y : F
  π : G₁

variable (e : G₁ →ₗ[F] G₂ →ₗ[F] Gₜ) (g₁ : G₁) (g₂ τ₂ : G₂)

/-- Per-claim left side `A = C − y·G₁ + z·π` of `e(A, G₂) = e(π, [τ]₂)`. -/
def lhsOne (c : Claim F G₁) : G₁ := c.C - c.y • g₁ + c.z • c.π

/-- The per-claim defect in `Gₜ`: zero iff the single-opening KZG equation holds. -/
def defect (c : Claim F G₁) : Gₜ := e (lhsOne g₁ c) (-g₂) + e c.π τ₂

/-- `RHS = Σ rᵢ·πᵢ` (every shape). -/
def rhs (cs : ι → Claim F G₁) (r : ι → F) : G₁ := ∑ i, r i • (cs i).π

/-- General-shape `LHS = Σ rᵢ·Cᵢ + Σ (rᵢ zᵢ)·πᵢ − (Σ rᵢ yᵢ)·G₁`, exactly as the EIP writes it. -/
def lhsGeneral (cs : ι → Claim F G₁) (r : ι → F) : G₁ :=
  ∑ i, r i • (cs i).C + ∑ i, (r i * (cs i).z) • (cs i).π - (∑ i, r i * (cs i).y) • g₁

/-- What the pairing-check precompile evaluates: `e(LHS, −G₂) · e(RHS, [τ]₂)`. -/
def batchedCheck (cs : ι → Claim F G₁) (r : ι → F) : Gₜ :=
  e (lhsGeneral g₁ cs r) (-g₂) + e (rhs cs r) τ₂

/-! ### M4 + M5: the general LHS is the random combination of per-claim sides, and the
batched pairing value is the same combination of per-claim defects. -/

theorem lhsGeneral_eq (cs : ι → Claim F G₁) (r : ι → F) :
    lhsGeneral g₁ cs r = ∑ i, r i • lhsOne g₁ (cs i) := by
  simp only [lhsGeneral, lhsOne, smul_add, smul_sub, sum_add_distrib, sum_sub_distrib,
    mul_smul, sum_smul]
  abel

theorem batchedCheck_eq (cs : ι → Claim F G₁) (r : ι → F) :
    batchedCheck e g₁ g₂ τ₂ cs r = ∑ i, r i • defect e g₁ g₂ τ₂ (cs i) := by
  simp only [batchedCheck, defect, lhsGeneral_eq, rhs, map_sum, map_smul, LinearMap.sum_apply,
    LinearMap.smul_apply, smul_add, sum_add_distrib]

/-! ### M1: completeness. -/

theorem complete (cs : ι → Claim F G₁) (h : ∀ i, defect e g₁ g₂ τ₂ (cs i) = 0) (r : ι → F) :
    batchedCheck e g₁ g₂ τ₂ cs r = 0 := by
  simp [batchedCheck_eq, h]

/-! ### M2: soundness of the random linear combination.

If claim `j` is false, then once every other challenge is fixed, at most one value of `r j`
makes the batch pass. With `r j` uniform on a field of size `q` that is probability `≤ 1/q`,
whatever the number of claims and however many of them are false. -/

theorem at_most_one_bad_challenge (cs : ι → Claim F G₁) (r : ι → F) (j : ι)
    (hj : defect e g₁ g₂ τ₂ (cs j) ≠ 0) {x x' : F}
    (hx : batchedCheck e g₁ g₂ τ₂ cs (Function.update r j x) = 0)
    (hx' : batchedCheck e g₁ g₂ τ₂ cs (Function.update r j x') = 0) : x = x' := by
  set t := fun i => defect e g₁ g₂ τ₂ (cs i)
  have split : ∀ w : F, batchedCheck e g₁ g₂ τ₂ cs (Function.update r j w)
      = w • t j + ∑ i ∈ univ.erase j, r i • t i := by
    intro w
    rw [batchedCheck_eq, ← add_sum_erase _ _ (mem_univ j), Function.update_self]
    congr 1
    refine sum_congr rfl fun i hi => ?_
    rw [Function.update_of_ne (ne_of_mem_erase hi)]
  rw [split] at hx hx'
  have : (x - x') • t j = 0 := by rw [sub_smul]; linear_combination (norm := module) hx - hx'
  rcases smul_eq_zero.mp this with h | h
  · exact sub_eq_zero.mp h
  · exact absurd h hj

/-- M2 as a count: among all `|F|` values of the challenge for a false claim, at most one is bad. -/
theorem bad_challenges_card_le_one [Fintype F] [DecidableEq Gₜ] (cs : ι → Claim F G₁) (r : ι → F)
    (j : ι) (hj : defect e g₁ g₂ τ₂ (cs j) ≠ 0) :
    (univ.filter fun x : F => batchedCheck e g₁ g₂ τ₂ cs (Function.update r j x) = 0).card ≤ 1 :=
  card_le_one.mpr fun _ hx _ hx' =>
    at_most_one_bad_challenge e g₁ g₂ τ₂ cs r j hj (mem_filter.mp hx).2 (mem_filter.mp hx').2

/-! ### M4: the two factorisations used by Blober agree with the general shape. -/

/-- Many blobs, one shared point: `Σ (rᵢ z)·πᵢ = z · RHS`. -/
theorem sharedZ_eq (cs : ι → Claim F G₁) (r : ι → F) (z : F) (hz : ∀ i, (cs i).z = z) :
    lhsGeneral g₁ cs r
      = ∑ i, r i • (cs i).C + z • rhs cs r - (∑ i, r i * (cs i).y) • g₁ := by
  simp only [lhsGeneral, rhs, hz, smul_sum, smul_smul, mul_comm z]

/-- One blob, many points: `Σ rᵢ·C = (Σ rᵢ)·C`. -/
theorem sharedC_eq (cs : ι → Claim F G₁) (r : ι → F) (C : G₁) (hC : ∀ i, (cs i).C = C) :
    lhsGeneral g₁ cs r
      = ∑ i, (r i * (cs i).z) • (cs i).π + (∑ i, r i) • C - (∑ i, r i * (cs i).y) • g₁ := by
  simp only [lhsGeneral, hC, sum_smul]
  abel

end BatchKzg
