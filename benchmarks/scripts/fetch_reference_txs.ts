// Mainnet replay: pull recent KZG state-update txs from a representative
// production rollup contract, compute their actual gas vs. our hypothetical
// batched cost, and emit a summary of dollars saved.
//
// Tx hashes are fetched via Blockscout's public API (no key needed). Tx
// details (gas, gas price, blob count) come from a public Ethereum RPC.
// All costs are denominated in ETH (no USD conversion — gas economics speak ETH).
//
// Override with environment variables if you prefer:
//   ETH_RPC_URL          (default: https://ethereum-rpc.publicnode.com)
//   SAMPLE_LIMIT         (default: 30)
//   TX_HASHES_FILE       (overrides Blockscout fetch, one hash per line)
//
// Run:    npm run replay
// Output: ../data/reference_replay.json

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ──────────────────────────────────────────────────────────────────────
//  Config
// ──────────────────────────────────────────────────────────────────────

// A representative production rollup contract that uses on-chain KZG verification.
// (User-facing proxy; the implementation at 0x9961... is the same code we've been
// referencing throughout the benchmarks.)
const CONTRACT_ADDRESS = "0xc662c410C0ECf747543f5bA90660f6ABeBD9C8c4";

// First 4 bytes of keccak256("updateStateKzgDA(uint256[],bytes[])"). Used to
// filter the contract's tx list down to only state-updates that exercise the
// KZG verification path.
const SELECTOR_KZG_DA = "0x507ee528";

const RPC_URL = process.env.ETH_RPC_URL ?? "https://ethereum-rpc.publicnode.com";
const SAMPLE_LIMIT = Number.parseInt(process.env.SAMPLE_LIMIT ?? "30", 10);

const HASHES_FILE = process.env.TX_HASHES_FILE ?? join(__dirname, "tx_hashes.txt");
const BENCHMARK_MULTI_BLOB_CSV = join(__dirname, "..", "data", "synthetic_gas_multi_blob_one_point.csv");
const BENCHMARK_MULTI_POINT_CSV = join(__dirname, "..", "data", "synthetic_gas_multi_point_one_blob.csv");
const GAS_HISTORY_CSV = join(__dirname, "..", "data", "avg_gas_price_daily.csv");
const OUT_PATH = join(__dirname, "..", "data", "reference_replay.json");

// ──────────────────────────────────────────────────────────────────────
//  Gas model: linear interpolation over our N-vs-gas benchmark
// ──────────────────────────────────────────────────────────────────────

type Sample = { n: number; gasLoop: number; gasBatched: number };

function loadBenchmark(path: string): Sample[] {
    const csv = readFileSync(path, "utf8").trim();
    const lines = csv.split("\n").slice(1);
    return lines
        .map((l) => {
            const [n, gasLoop, gasBatched] = l.split(",").map(Number);
            return { n, gasLoop, gasBatched };
        })
        .sort((a, b) => a.n - b.n);
}

// ──────────────────────────────────────────────────────────────────────
//  Historical gas prices (Etherscan daily-average export, in wei)
// ──────────────────────────────────────────────────────────────────────

type GasPoint = { unixTs: number; gwei: number };

function loadGasHistory(): GasPoint[] {
    const csv = readFileSync(GAS_HISTORY_CSV, "utf8").trim();
    const lines = csv.split("\n").slice(1);
    return lines
        .map((l) => {
            // CSV cells are quoted: "Date","UnixTimeStamp","Value (Wei)"
            const cells = l.split(",").map((c) => c.replace(/"/g, "").trim());
            const unixTs = Number.parseInt(cells[1], 10);
            const wei = Number(cells[2]);
            return { unixTs, gwei: wei / 1e9 };
        })
        .filter((p) => p.gwei > 0);
}

function gweiAvgOverWindow(points: GasPoint[], days: number): number {
    const latest = points[points.length - 1].unixTs;
    const cutoff = latest - days * 86400;
    const window = points.filter((p) => p.unixTs >= cutoff);
    if (window.length === 0) return 0;
    return window.reduce((s, p) => s + p.gwei, 0) / window.length;
}

function interp(samples: Sample[], n: number, key: "gasLoop" | "gasBatched"): number {
    if (n <= samples[0].n) {
        return Math.round((samples[0][key] * n) / samples[0].n);
    }
    for (let i = 1; i < samples.length; i++) {
        if (samples[i].n >= n) {
            const a = samples[i - 1];
            const b = samples[i];
            const t = (n - a.n) / (b.n - a.n);
            return Math.round(a[key] + t * (b[key] - a[key]));
        }
    }
    // Extrapolate beyond the largest sample using the last marginal.
    const last = samples[samples.length - 1];
    const prev = samples[samples.length - 2];
    const slope = (last[key] - prev[key]) / (last.n - prev.n);
    return Math.round(last[key] + slope * (n - last.n));
}

// ──────────────────────────────────────────────────────────────────────
//  Tx hash sourcing
// ──────────────────────────────────────────────────────────────────────

async function fetchHashesFromBlockscout(limit: number): Promise<string[]> {
    // Blockscout is open + free; no API key required.
    const url = new URL("https://eth.blockscout.com/api");
    url.searchParams.set("module", "account");
    url.searchParams.set("action", "txlist");
    url.searchParams.set("address", CONTRACT_ADDRESS);
    url.searchParams.set("page", "1");
    url.searchParams.set("offset", String(limit * 4)); // overshoot, then filter to KZG-DA selector
    url.searchParams.set("sort", "desc");

    const r = await fetch(url);
    const j = (await r.json()) as { result?: { hash: string; input: string }[]; message?: string };
    if (!Array.isArray(j.result)) throw new Error(`Blockscout: ${j.message ?? "unknown"}`);

    return j.result
        .filter((t) => t.input?.startsWith(SELECTOR_KZG_DA))
        .slice(0, limit)
        .map((t) => t.hash);
}

function readHashesFromFile(): string[] {
    return readFileSync(HASHES_FILE, "utf8")
        .split("\n")
        .map((l) => l.trim())
        .filter((l) => l && !l.startsWith("#"));
}

// ──────────────────────────────────────────────────────────────────────
//  RPC: per-tx details
// ──────────────────────────────────────────────────────────────────────

async function rpc<T>(method: string, params: unknown[]): Promise<T> {
    const r = await fetch(RPC_URL, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    });
    const j = (await r.json()) as { result?: T; error?: { message: string } };
    if (j.error) throw new Error(`${method}: ${j.error.message}`);
    return j.result as T;
}

type RpcTx = {
    blockNumber: string;
    gasPrice: string;
    blobVersionedHashes?: string[];
    input: string;
};
type RpcReceipt = { gasUsed: string };

async function fetchTx(hash: string) {
    const tx = await rpc<RpcTx | null>("eth_getTransactionByHash", [hash]);
    if (!tx) throw new Error("not found");
    const receipt = await rpc<RpcReceipt | null>("eth_getTransactionReceipt", [hash]);
    if (!receipt) throw new Error("no receipt");
    return {
        blockNumber: Number.parseInt(tx.blockNumber, 16),
        gasUsed: Number.parseInt(receipt.gasUsed, 16),
        gasPriceWei: BigInt(tx.gasPrice),
        nBlobs: (tx.blobVersionedHashes ?? []).length,
        input: tx.input,
    };
}

// ──────────────────────────────────────────────────────────────────────
//  Main
// ──────────────────────────────────────────────────────────────────────

async function main() {
    const samplesMultiBlob = loadBenchmark(BENCHMARK_MULTI_BLOB_CSV);
    const samplesMultiPoint = loadBenchmark(BENCHMARK_MULTI_POINT_CSV);
    // Multi-blob is the path that maps to the rollup we're replaying; multi-point
    // is shown alongside as a separate use-case projection.
    const samples = samplesMultiBlob;

    const hashes = existsSync(HASHES_FILE) && process.env.TX_HASHES_FILE
        ? readHashesFromFile()
        : await fetchHashesFromBlockscout(SAMPLE_LIMIT);
    console.log(`Processing ${hashes.length} tx${hashes.length === 1 ? "" : "es"} for ${CONTRACT_ADDRESS}...`);

    type Row = {
        hash: string;
        blockNumber: number;
        nBlobs: number;
        actualGasUsed: number;
        gasPriceGwei: number;
        referenceLoopGas: number;
        hypotheticalBatchedGas: number;
        savedGas: number;
        savedEth: number;
    };

    const rows: Row[] = [];
    for (const h of hashes) {
        try {
            const tx = await fetchTx(h);
            if (tx.nBlobs === 0) {
                console.log(`  skip ${h.slice(0, 10)}… (no blobs)`);
                continue;
            }
            const referenceLoopGas = interp(samples, tx.nBlobs, "gasLoop");
            const hypotheticalBatchedGas = interp(samples, tx.nBlobs, "gasBatched");
            const savedGas = referenceLoopGas - hypotheticalBatchedGas;
            // savedGas (units) × gasPrice (wei) / 1e18 → ETH
            const savedEth = Number(BigInt(savedGas) * tx.gasPriceWei) / 1e18;

            rows.push({
                hash: h,
                blockNumber: tx.blockNumber,
                nBlobs: tx.nBlobs,
                actualGasUsed: tx.gasUsed,
                gasPriceGwei: Number(tx.gasPriceWei) / 1e9,
                referenceLoopGas,
                hypotheticalBatchedGas,
                savedGas,
                savedEth,
            });
            console.log(
                `  ${h.slice(0, 10)}…  block=${tx.blockNumber}  N=${tx.nBlobs}  saved=${savedGas.toLocaleString()} gas / ${savedEth.toFixed(6)} ETH`,
            );
        } catch (e) {
            console.warn(`  fail ${h.slice(0, 10)}…  ${(e as Error).message}`);
        }
    }

    if (rows.length === 0) {
        console.error("No KZG-DA txs processed. Check tx_hashes.txt or ETHERSCAN_API_KEY.");
        process.exit(1);
    }

    const totalBlobs = rows.reduce((s, r) => s + r.nBlobs, 0);
    const totalSavedGas = rows.reduce((s, r) => s + r.savedGas, 0);
    const totalSavedEth = rows.reduce((s, r) => s + r.savedEth, 0);

    const blocks = rows.map((r) => r.blockNumber).sort((a, b) => a - b);
    const blockSpan = blocks[blocks.length - 1] - blocks[0];
    const hoursSpan = (blockSpan * 12) / 3600; // ~12 sec/block
    const txPerHour = rows.length / Math.max(hoursSpan, 1);

    const gasPrices = rows.map((r) => r.gasPriceGwei).sort((a, b) => a - b);
    const avgGwei = gasPrices.reduce((s, g) => s + g, 0) / gasPrices.length;
    const medianGwei = gasPrices[Math.floor(gasPrices.length / 2)];

    // Pull empirical gas-price baselines from Etherscan's daily-average export
    // (../data/avg_gas_price_daily.csv) so projections are grounded, not guesses.
    // Historical gas-price baselines. We project all annualized savings against
    // these — they're reproducible (Etherscan daily-average export), defensible,
    // and don't depend on which 30 txs we happened to sample.
    const gasHistory = loadGasHistory();
    const baselines = {
        last30d: gweiAvgOverWindow(gasHistory, 30),
        last90d: gweiAvgOverWindow(gasHistory, 90),
        last1y: gweiAvgOverWindow(gasHistory, 365),
        last2y: gweiAvgOverWindow(gasHistory, 365 * 2),
    };

    const txPerYear = txPerHour * 24 * 365;
    const avgN = totalBlobs / rows.length;

    // Saved ETH per tx at a given gas price, using the OBSERVED average N from
    // the sampled rollup. Directly applies the synthetic benchmark gas curve.
    const savedPerTxAtGweiEth = (gwei: number) => {
        const sg = interp(samples, avgN, "gasLoop") - interp(samples, avgN, "gasBatched");
        return (sg * gwei) / 1e9;
    };
    const annualized = {
        last30d: { gwei: baselines.last30d, eth: savedPerTxAtGweiEth(baselines.last30d) * txPerYear },
        last90d: { gwei: baselines.last90d, eth: savedPerTxAtGweiEth(baselines.last90d) * txPerYear },
        last1y: { gwei: baselines.last1y, eth: savedPerTxAtGweiEth(baselines.last1y) * txPerYear },
        last2y: { gwei: baselines.last2y, eth: savedPerTxAtGweiEth(baselines.last2y) * txPerYear },
    };

    // What-if projection: same fee market (trailing-1y gwei baseline), but the
    // rollup batches more blobs per state-update.
    const projectionGwei = baselines.last1y;
    const savedPerTxAtNEth = (n: number) => {
        const sg = interp(samples, n, "gasLoop") - interp(samples, n, "gasBatched");
        return (sg * projectionGwei) / 1e9;
    };
    const baseline = savedPerTxAtNEth(avgN);
    const projectionByN = [10, 20, 50, 100].map((n) => ({
        nBlobs: n,
        savedEthPerTx: savedPerTxAtNEth(n),
        scalingVsObserved: savedPerTxAtNEth(n) / Math.max(baseline, 1e-12),
    }));

    // ── Annualized cost matrices per use case ─────────────────────────────
    // Two scenarios share the same gas-price baselines and traffic assumption,
    // but use different gas curves (multi-blob vs multi-point) since each maps
    // to a different verifier function and a different protocol pattern.
    const COST_NS = [1, 3, 5, 6, 10, 25, 50, 100, 200, 500, 1000];
    const costBaselines = [
        { key: "last30d", label: `trailing 30d (${baselines.last30d.toFixed(2)} gwei)`, gwei: baselines.last30d },
        { key: "last90d", label: `trailing 90d (${baselines.last90d.toFixed(2)} gwei)`, gwei: baselines.last90d },
        { key: "last1y", label: `trailing 1y (${baselines.last1y.toFixed(2)} gwei)`, gwei: baselines.last1y },
        { key: "last2y", label: `trailing 2y (${baselines.last2y.toFixed(2)} gwei)`, gwei: baselines.last2y },
    ];
    // gas (units) × gwei × 1e9 (wei/gwei) / 1e18 (wei/ETH) = ETH
    const costEth = (gas: number, gwei: number) => (gas * gwei) / 1e9;

    function buildCostMatrix(curve: Sample[]) {
        return COST_NS.map((n) => {
            const loopGas = interp(curve, n, "gasLoop");
            const batchedGas = interp(curve, n, "gasBatched");
            const perTx: Record<string, { loop: number; batched: number; saved: number; savedPct: number }> = {};
            const perYear: Record<string, { loop: number; batched: number; saved: number }> = {};
            for (const b of costBaselines) {
                const loop = costEth(loopGas, b.gwei);
                const batched = costEth(batchedGas, b.gwei);
                const saved = loop - batched;
                perTx[b.key] = { loop, batched, saved, savedPct: loop > 0 ? (saved / loop) * 100 : 0 };
                perYear[b.key] = { loop: loop * txPerYear, batched: batched * txPerYear, saved: saved * txPerYear };
            }
            return { n, loopGas, batchedGas, perTx, perYear };
        });
    }

    const costMatrixMultiBlob = buildCostMatrix(samplesMultiBlob);
    const costMatrixMultiPoint = buildCostMatrix(samplesMultiPoint);
    const costMatrix = costMatrixMultiBlob; // backwards-compat alias for the rollup-mapped scenario

    const summary = {
        contractAddress: CONTRACT_ADDRESS,
        sample: {
            size: rows.length,
            blockRange: { from: blocks[0], to: blocks[blocks.length - 1], spanBlocks: blockSpan, spanHours: hoursSpan },
            avgBlobsPerTx: avgN,
            txPerHour,
        },
        gasPrice: { avgGwei, medianGwei, minGwei: gasPrices[0], maxGwei: gasPrices[gasPrices.length - 1] },
        totals: { savedGas: totalSavedGas, savedEth: totalSavedEth },
        perTx: { savedGas: Math.round(totalSavedGas / rows.length), savedEth: totalSavedEth / rows.length },
        annualizedProjection: {
            note: "Same observed traffic rate, gas-price scenarios from the historical mainnet daily-average export.",
            at30DayAvg: annualized.last30d,
            at90DayAvg: annualized.last90d,
            at1YearAvg: annualized.last1y,
            at2YearAvg: annualized.last2y,
        },
        whatIfMoreBlobsPerTx: {
            note: "Hypothetical: if the rollup batched more blobs into a single state-update, per-tx savings scale super-linearly.",
            projection: projectionByN,
        },
        costMatrix: {
            note: "Per-tx + annualized verification cost (ETH) at each (N, historical baseline) for each use case. The multi-blob curve maps to the rollup we replayed; multi-point is shown alongside as a separate use-case projection.",
            assumedTxPerYear: txPerYear,
            baselines: Object.fromEntries(costBaselines.map((b) => [b.key, b])),
            multiBlob: { rows: costMatrixMultiBlob },
            multiPoint: { rows: costMatrixMultiPoint },
        },
        txs: rows,
    };

    writeFileSync(OUT_PATH, JSON.stringify(summary, null, 2) + "\n");
    console.log(`\nWrote ${OUT_PATH}`);
    console.log(`\n=== Sample of ${rows.length} txs ===`);
    console.log(`  Block range:        ${blocks[0]} → ${blocks[blocks.length - 1]} (${hoursSpan.toFixed(1)}h, ~${txPerHour.toFixed(1)} tx/hr)`);
    console.log(`  Avg blobs / tx:     ${avgN.toFixed(1)}`);
    console.log(`  Gas price (gwei):   median=${medianGwei.toFixed(2)} avg=${avgGwei.toFixed(2)}  range=[${gasPrices[0].toFixed(2)} … ${gasPrices[gasPrices.length - 1].toFixed(2)}]`);
    console.log(`  Total gas saved:    ${totalSavedGas.toLocaleString()}`);
    console.log(`  Total ETH saved:    ${totalSavedEth.toFixed(6)} ETH`);
    console.log(`  Per tx:             ${Math.round(totalSavedGas / rows.length).toLocaleString()} gas / ${(totalSavedEth / rows.length).toFixed(6)} ETH`);
    console.log(`\n=== Annualized (${txPerYear.toFixed(0)} txs/yr at current rate, projecting at historical baselines) ===`);
    console.log(`  Trailing 30d (${baselines.last30d.toFixed(2)} gwei): ${annualized.last30d.eth.toFixed(4)} ETH/yr`);
    console.log(`  Trailing 90d (${baselines.last90d.toFixed(2)} gwei): ${annualized.last90d.eth.toFixed(4)} ETH/yr`);
    console.log(`  Trailing 1y  (${baselines.last1y.toFixed(2)} gwei): ${annualized.last1y.eth.toFixed(4)} ETH/yr`);
    console.log(`  Trailing 2y  (${baselines.last2y.toFixed(2)} gwei): ${annualized.last2y.eth.toFixed(4)} ETH/yr`);
    console.log(`\n=== What-if (same fee market, more blobs per tx) ===`);
    for (const p of projectionByN) {
        console.log(`  N=${p.nBlobs.toString().padStart(3)}:  ${p.savedEthPerTx.toFixed(6)} ETH/tx  (${p.scalingVsObserved.toFixed(1)}× current)`);
    }

    // ── Cost tables: annualized ETH across N and gas-price baselines ─────
    const eth = (v: number) => {
        if (v >= 100) return `${v.toFixed(0)} ETH`;
        if (v >= 1) return `${v.toFixed(2)} ETH`;
        if (v >= 0.001) return `${v.toFixed(4)} ETH`;
        return `${v.toFixed(6)} ETH`;
    };

    function printCostMatrix(label: string, matrix: typeof costMatrix) {
        console.log(`\n${label}`);
        for (const b of costBaselines) {
            console.log(`\n  ${b.label}`);
            console.log(`     N      Loop /yr           Batched /yr        Saved /yr          Saved %`);
            console.log(`     ─────  ─────────────────  ─────────────────  ─────────────────  ───────`);
            for (const r of matrix) {
                const yr = r.perYear[b.key];
                const pct = r.perTx[b.key].savedPct;
                console.log(
                    `     ${r.n.toString().padStart(5)}  ${eth(yr.loop).padStart(16)}  ${eth(yr.batched).padStart(16)}  ${eth(yr.saved).padStart(16)}  ${pct.toFixed(0).padStart(5)}%`,
                );
            }
        }
    }

    console.log(`\n=== Annualized cost (assuming ${txPerYear.toFixed(0)} txs/yr) ===`);
    printCostMatrix("--- Multi-blob single-z (the rollup pattern we replayed) ---", costMatrixMultiBlob);
    printCostMatrix("--- Multi-point single-blob (different use case, same traffic assumption) ---", costMatrixMultiPoint);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
