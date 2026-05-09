// Generate two synthetic benchmark fixtures, both producing compressed (48-byte)
// and uncompressed (128-byte) encodings so the loop and batched verifiers can
// run on identical inputs without on-chain conversions polluting gas measurements.
//
//   1. Multi-blob single-z   →  ../data/fixtures_multi_blob.json
//      N random blobs, all opened at the same z. Powers `verifySinglePointMultipleBlobs`.
//
//   2. Single-blob multi-z   →  ../data/fixtures_multi_point.json
//      One random blob, opened at N distinct z values. Powers `verifyMultiplePoints`.
//
// Run: npm run generate

import { createHash, randomBytes } from "node:crypto";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { bls12_381 } from "@noble/curves/bls12-381.js";
import ckzg from "c-kzg";

const { BYTES_PER_BLOB, blobToKzgCommitment, computeKzgProof, loadTrustedSetup } = ckzg as unknown as {
    BYTES_PER_BLOB: number;
    blobToKzgCommitment: (blob: Uint8Array) => Uint8Array;
    computeKzgProof: (blob: Uint8Array, z: Uint8Array) => [Uint8Array, Uint8Array];
    loadTrustedSetup: (precompute: number, filePath?: string) => void;
};

const __dirname = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = join(__dirname, "..", "data");

const N = 1000;
const FIELD_ELEMENT_SIZE = 32;
// Top byte of BLS12-381 scalar field prime. Capping each field element's top
// byte to < 0x73 keeps the whole value safely < the modulus.
const SCALAR_TOP_BYTE_MAX = 0x73;

// 0 = no precomputed table; uses c-kzg's bundled mainnet setup by default.
loadTrustedSetup(0);

function randomBlob(): Uint8Array {
    const blob = randomBytes(BYTES_PER_BLOB);
    for (let i = 0; i < BYTES_PER_BLOB; i += FIELD_ELEMENT_SIZE) {
        blob[i] = blob[i] % SCALAR_TOP_BYTE_MAX;
    }
    return new Uint8Array(blob);
}

// Encode an Fp value as 64 bytes per EIP-2537: 16 zero bytes + 48-byte big-endian.
const fpHex = (n: bigint): string => n.toString(16).padStart(96, "0").padStart(128, "0");

function decompressG1(compressedHex: string): string {
    const clean = compressedHex.startsWith("0x") ? compressedHex.slice(2) : compressedHex;
    const aff = bls12_381.G1.Point.fromHex(clean).toAffine();
    return "0x" + fpHex(aff.x) + fpHex(aff.y);
}

function versionedHash(compressed: Uint8Array): string {
    const sha = createHash("sha256").update(compressed).digest();
    sha[0] = 0x01; // EIP-4844 KZG version byte
    return "0x" + Buffer.from(sha).toString("hex");
}

function bytes32FromUint(n: number): Uint8Array {
    const out = new Uint8Array(32);
    // Big-endian 32-byte encoding. JS numbers are safe for n up to 2^53; for benchmark
    // sizes this is plenty.
    let value = BigInt(n);
    for (let i = 31; i >= 0 && value > 0n; i--) {
        out[i] = Number(value & 0xffn);
        value >>= 8n;
    }
    return out;
}

function progress(label: string, i: number, total: number, startMs: number) {
    if ((i + 1) % 50 === 0) {
        const elapsed = ((Date.now() - startMs) / 1000).toFixed(1);
        console.log(`  ${label} ${i + 1}/${total} (${elapsed}s)`);
    }
}

// ─── Fixture 1: many blobs, one shared z ─────────────────────────────────
function buildMultiBlobFixture() {
    const z = bytes32FromUint(1);
    const zHex = "0x" + Buffer.from(z).toString("hex");

    console.log(`Multi-blob: ${N} random blobs at z=1...`);
    const startTime = Date.now();

    const blobHashes: string[] = [];
    const commitmentsCompressed: string[] = [];
    const commitmentsUncompressed: string[] = [];
    const ys: string[] = [];
    const proofsCompressed: string[] = [];
    const proofsUncompressed: string[] = [];

    for (let i = 0; i < N; i++) {
        const blob = randomBlob();
        const commitment = blobToKzgCommitment(blob);
        const [proof, y] = computeKzgProof(blob, z);

        const cHex = "0x" + Buffer.from(commitment).toString("hex");
        const pHex = "0x" + Buffer.from(proof).toString("hex");

        blobHashes.push(versionedHash(commitment));
        commitmentsCompressed.push(cHex);
        commitmentsUncompressed.push(decompressG1(cHex));
        ys.push("0x" + Buffer.from(y).toString("hex"));
        proofsCompressed.push(pHex);
        proofsUncompressed.push(decompressG1(pHex));

        progress("multi-blob", i, N, startTime);
    }

    return {
        description: `Multi-blob single-z: ${N} random blobs at z=1, both compressed and uncompressed encodings.`,
        n: N,
        z: zHex,
        blobHashes,
        commitmentsCompressed,
        commitmentsUncompressed,
        y: ys,
        proofsCompressed,
        proofsUncompressed,
    };
}

// ─── Fixture 2: one blob, many distinct z ────────────────────────────────
function buildMultiPointFixture() {
    const blob = randomBlob();
    const commitment = blobToKzgCommitment(blob);
    const cHex = "0x" + Buffer.from(commitment).toString("hex");
    const blobHash = versionedHash(commitment);

    console.log(`Multi-point: 1 random blob, ${N} distinct z values...`);
    const startTime = Date.now();

    const zs: string[] = [];
    const ys: string[] = [];
    const proofsCompressed: string[] = [];
    const proofsUncompressed: string[] = [];

    // z values 1, 2, 3, ..., N — distinct, all well below the BLS scalar modulus.
    for (let i = 0; i < N; i++) {
        const z = bytes32FromUint(i + 1);
        const [proof, y] = computeKzgProof(blob, z);

        const pHex = "0x" + Buffer.from(proof).toString("hex");

        zs.push("0x" + Buffer.from(z).toString("hex"));
        ys.push("0x" + Buffer.from(y).toString("hex"));
        proofsCompressed.push(pHex);
        proofsUncompressed.push(decompressG1(pHex));

        progress("multi-point", i, N, startTime);
    }

    return {
        description: `Single-blob multi-z: 1 random blob opened at N=${N} distinct z values (1..N), both compressed and uncompressed proof encodings.`,
        n: N,
        blobHash,
        commitmentCompressed: cHex,
        commitmentUncompressed: decompressG1(cHex),
        z: zs,
        y: ys,
        proofsCompressed,
        proofsUncompressed,
    };
}

const overallStart = Date.now();

const multiBlob = buildMultiBlobFixture();
const multiBlobPath = join(DATA_DIR, "fixtures_multi_blob.json");
writeFileSync(multiBlobPath, JSON.stringify(multiBlob, null, 2) + "\n");
console.log(`Wrote ${multiBlobPath}`);

const multiPoint = buildMultiPointFixture();
const multiPointPath = join(DATA_DIR, "fixtures_multi_point.json");
writeFileSync(multiPointPath, JSON.stringify(multiPoint, null, 2) + "\n");
console.log(`Wrote ${multiPointPath}`);

console.log(`\nTotal: ${((Date.now() - overallStart) / 1000).toFixed(1)}s`);
