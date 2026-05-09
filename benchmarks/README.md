# Benchmarks

Gas comparison and demo data for `blob-verifier`'s batched KZG verification (EIP-2537) versus the industry-standard EIP-4844 loop pattern (`0x0A` per blob).

➡ **Headline numbers, charts, and full methodology are in [`RESULTS.md`](RESULTS.md).**

## Why this exists

Production rollups today verify multiple blob openings by looping the EIP-4844 point-evaluation precompile (`0x0A`) per blob. Our `blob-verifier` uses EIP-2537's BLS12-381 precompiles (`0x0C`, `0x0F`) to do **batched** verification with one pairing check across all blobs. This directory measures the gap — synthetically (Foundry tests) and against real mainnet workloads (90-day replay of a representative production rollup).

## Demo narrative — five-beat story

1. **The standard.** A textbook loop of `0x0A` per blob is what every production rollup using EIP-4844 does today (we ship `LoopVerifier.sol` as a stripped reference).
2. **The asymptote.** Per-blob loop cost ≈ 50k gas. Per-blob marginal of batched ≈ 14k. Linear → near-constant amortization.
3. **The diff.** A 30-line per-blob loop becomes one library call. Drop-in replacement (modulo 48→128 byte G1 encoding).
4. **The chart.** Gas vs N — two curves cross at N=5, batched dominates asymptotically (~66% saved at N=200). See `data/chart_gas_curves.svg`.
5. **The replay.** 4,102 real KZG state-update txs from a representative rollup over 90 days, batched-cost computed against actual gas prices. 0.172 ETH saved at observed gas; **104 ETH/yr per rollup if N grows to 100**.

## Layout

| Path | Purpose |
|---|---|
| `foundry.toml` | Foundry config; remaps `blob-verifier/` → `../src/` |
| `src/LoopVerifier.sol` | Stripped industry-standard `0x0A`-loop verifier — the comparison reference |
| `src/BatchedVerifier.sol` | Thin wrapper around `BlobVerifier` for the comparison harness |
| `test/Compare.t.sol` | Side-by-side gas measurement, both verifiers on identical inputs |
| `scripts/generate_fixtures.ts` | `c-kzg`-bound fixture generator (real KZG proofs) |
| `scripts/fetch_reference_txs.ts` | 90-day mainnet replay (Blockscout + public RPC, no API keys) |
| `scripts/generate_charts.py` | Builds the demo PNGs from the CSVs (matplotlib) |
| `data/fixtures_multi_blob.json` | 1000 random blobs at z=1 (input) |
| `data/fixtures_multi_point.json` | 1 blob at 1000 distinct z (input) |
| `data/synthetic_gas_multi_blob_one_point.csv` | Output: `forge test` regenerates |
| `data/synthetic_gas_multi_point_one_blob.csv` | Output: `forge test` regenerates |
| `data/avg_gas_price_daily.csv` | Etherscan historical export, 2015–2026 |
| `data/reference_replay.json` | 4102-tx mainnet replay + cost matrices |
| `data/chart_gas_curves_multi_blob.png` | Multi-blob gas curves (N up to 100) |
| `data/chart_gas_curves_multi_point.png` | Multi-point gas curves (N up to 100) |
| `data/chart_savings.png` | Combined % savings chart |
| `data/chart_eth_saved_today.png` | ETH/yr saved at today's N=6 across 4 gas baselines |
| `data/chart_eth_saved_scaling.png` | ETH/yr saved vs N (1→100), one line per gas baseline |
| `RESULTS.md` | Full results, methodology, caveats |

## How to run

From `benchmarks/scripts/`:

```bash
npm install            # one-time, installs c-kzg + @noble/curves + tsx
npm run generate       # regenerates the two fixture JSONs (~50s)
```

From `benchmarks/`:

```bash
forge test -vv         # regenerates both synthetic_gas_*.csv (~5s)
```

From `benchmarks/scripts/`:

```bash
npm run replay         # regenerates reference_replay.json (~45s, ~4000 txs)
```

Knobs (env vars):

```bash
WINDOW_DAYS=90 MAX_SAMPLE=5000 RPC_CONCURRENCY=10 npm run replay
```

To regenerate the PNG charts (one-time venv setup, then run anytime):

```bash
cd benchmarks
python3 -m venv .venv && .venv/bin/pip install matplotlib
.venv/bin/python scripts/generate_charts.py
```
