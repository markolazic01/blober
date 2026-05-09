# Benchmarks

Gas comparison and demo data for `blob-verifier`'s batched KZG verification (EIP-2537) versus the industry-standard EIP-4844 loop pattern (`0x0A` per blob).

## Why this exists

Production rollups today verify multiple blob openings by looping the EIP-4844 point-evaluation precompile (`0x0A`) per blob. Our `blob-verifier` uses EIP-2537's BLS12-381 precompiles (`0x0C`, `0x0F`) to do **batched** verification with one pairing check across all blobs. This directory measures the gap — synthetically and against real mainnet workloads of representative production rollup contracts.

## Demo narrative

Five-beat story for the demo:

1. **The standard.** Show a deployed industry-reference verifier — a textbook loop of `0x0A` per blob (this is what every production rollup using EIP-4844 does today).
2. **The asymptote.** Per-blob loop cost ≈ 50k gas. Per-blob marginal of batched ≈ 6k. Linear → near-constant.
3. **The diff.** A 30-line per-blob loop becomes one library call. Drop-in replacement (modulo 48→128 byte encoding).
4. **The chart.** Gas vs N, two curves diverge after N ≈ 5–7. Asymptotic dominance is the headline.
5. **The replay.** Pick a recent KZG-based state-update tx from a representative production rollup, compute hypothetical batched cost, show concrete dollars saved.

## Plan

### Phase 0 — scaffolding *(done)*
- Foundry mini-project remapping to `../src/` (parent `blob-verifier`)
- README with the demo narrative outline

### Phase 1 — synthetic benchmarks
- Port the industry-standard `verifyKzgProofs` loop pattern into `src/LoopVerifier.sol`
- Generate fixtures up to N≈500 using real `c-kzg-4844` Node bindings (c-kzg test vectors top out at N=6)
- Foundry test runs both verifiers across N ∈ {1, 3, 5, 10, 25, 50, 100, 200, 500}; emits `data/synthetic_gas.csv`
- Fit a linear model: `gas_batched = a + b·N`. Lock `(a, b)` for downstream replay calculations.

### Phase 2 — mainnet replay ⭐
- Pull 30–50 recent KZG state-update txs from a representative production rollup contract via `cast` + etherscan
- Parse `nBlobs` from each tx's calldata; capture actual gas used + gas price + ETH/USD
- Compute hypothetical batched gas (using `(a, b)` from Phase 1), saved gas, saved USD
- Aggregate to a quarterly figure → `data/reference_replay.json`

### Phase 3 — visualization & narrative
- Charts (gas vs N curve; savings histogram across mainnet replay)
- `report.md` with the headline numbers and demo talking points
- Slides

## Layout (target)

| Path | Phase | Contents |
|---|---|---|
| `foundry.toml` | 0 | Project config; remaps `blob-verifier/` → `../src/` |
| `src/LoopVerifier.sol` | 1 | Port of an industry-standard `0x0A`-loop verifier for direct comparison |
| `test/Compare.t.sol` | 1 | Side-by-side gas measurement, both verifiers on identical inputs |
| `data/synthetic_gas.csv` | 1 | Output: `N, gas_loop, gas_batched, ratio` |
| `data/fixtures_*.json` | 1 | N-up-to-500 KZG fixtures for the benchmark suite |
| `scripts/generate_fixtures.mjs` | 1 | `c-kzg-4844`-bound fixture generator |
| `scripts/fetch_reference_txs.mjs` | 2 | Etherscan pull + calldata decoder |
| `data/reference_replay.json` | 2 | Output: per-tx hypothetical savings |
| `report.md` | 3 | Demo numbers + talking points |

## Headline numbers we want to mine

| # | Number | Source |
|---|---|---|
| 1 | "**X% gas saved at N=100**" | Phase 1 synthetic |
| 2 | "**$Y saved on a reference rollup's last 30 days**" | Phase 2 replay |
| 3 | "**Crossover at N=Z**" | Phase 1 fit |
| 4 | "**Annualized $ projection if rollups adopted this**" | Phase 2 aggregate |
| 5 | "**Bytecode / API surface diff**" | Phase 1 (counted from sources) |
