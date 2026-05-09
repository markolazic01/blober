"""Regenerates the demo charts in benchmarks/data/ from the synthetic CSVs
and the mainnet-replay cost matrix.

Run from the project root:
    benchmarks/.venv/bin/python benchmarks/scripts/generate_charts.py
"""
from __future__ import annotations

import csv
import json
from pathlib import Path

import matplotlib.pyplot as plt
import matplotlib.ticker as mtick
from matplotlib.offsetbox import AnnotationBbox, HPacker, TextArea

DATA_DIR = Path(__file__).resolve().parents[1] / "data"
LOOP_COLOR = "#d62728"
BATCHED_COLOR = "#2ca02c"
MULTI_BLOB_COLOR = "#1f77b4"
MULTI_POINT_COLOR = "#c44569"
N_LIMIT = 100

# Baseline display order + labels (matches reference_replay.json keys)
BASELINES = [
    ("last90d", "Trailing 90d (0.94 gwei)", "#9ecae1"),
    ("last30d", "Trailing 30d (1.57 gwei)", "#4292c6"),
    ("last1y",  "Trailing 1y (1.85 gwei)",  "#08519c"),
    ("last2y",  "Trailing 2y (6.04 gwei)",  "#08306b"),
]


def load_csv(path: Path) -> list[dict]:
    with path.open() as f:
        return [
            {k: int(v) if k != "" else v for k, v in row.items()}
            for row in csv.DictReader(f)
        ]


def filter_to_limit(rows: list[dict], limit: int) -> list[dict]:
    return [r for r in rows if r["n"] <= limit]


def fmt_gas(g: float) -> str:
    return f"{g/1e6:.2f}M" if g >= 1e6 else f"{int(round(g/1e3))}K"


def plot_curves(rows: list[dict], title: str, subtitle: str, out_path: Path) -> None:
    ns = [r["n"] for r in rows]
    loop = [r["gas_loop"] for r in rows]
    batched = [r["gas_batched"] for r in rows]

    fig, ax = plt.subplots(figsize=(10, 5.6), dpi=130)
    # Show all markers at N>=5, plus 2 representative ones below the crossover
    # (N=1 and N=3) — the full cluster of N=1..4 dots is visually noisy.
    sub_crossover_keep = {1, 3}
    marker_idxs = [
        i for i, r in enumerate(rows)
        if r["n"] >= 5 or r["n"] in sub_crossover_keep
    ]
    ax.plot(ns, loop, color=LOOP_COLOR, marker="o", markersize=7,
            linewidth=2.4, label="Industry standard", zorder=3,
            markevery=marker_idxs)
    ax.plot(ns, batched, color=BATCHED_COLOR, marker="o", markersize=7,
            linewidth=2.4, label="Blober", zorder=3,
            markevery=marker_idxs)

    # Crossover marker — orange and emphasized
    crossover_row = next((r for r in rows if r["saved_pct"] > 0), None)
    if crossover_row is not None:
        crossover_n = crossover_row["n"]
        crossover_saved = crossover_row["saved_pct"]
        ax.axvline(crossover_n, color="#ff7f0e", linestyle="--",
                   linewidth=2.2, alpha=0.95, zorder=2)
        ax.annotate(
            f"crossover\nN={crossover_n}  ·  (-{crossover_saved}%)",
            xy=(crossover_n, max(loop) * 0.45),
            xytext=(crossover_n + 4, max(loop) * 0.5),
            fontsize=10, color="#cc5e00", fontweight="700",
            arrowprops=dict(arrowstyle="-", color="#ff7f0e", lw=1.2),
        )

    # Strategic intermediate-point labels: gas values + savings %
    label_ns = {10, 25, 50}
    for r in rows:
        if r["n"] in label_ns:
            ax.annotate(fmt_gas(r["gas_loop"]),
                        xy=(r["n"], r["gas_loop"]),
                        xytext=(0, 11), textcoords="offset points",
                        ha="center", fontsize=10, color=LOOP_COLOR,
                        fontweight="600")
            ax.annotate(f"{fmt_gas(r['gas_batched'])}  (-{r['saved_pct']}%)",
                        xy=(r["n"], r["gas_batched"]),
                        xytext=(0, -18), textcoords="offset points",
                        ha="center", fontsize=10, color=BATCHED_COLOR,
                        fontweight="600")

    # End-of-line value labels (N=100)
    last = rows[-1]
    ax.annotate(fmt_gas(last["gas_loop"]),
                xy=(last["n"], last["gas_loop"]),
                xytext=(8, 0), textcoords="offset points",
                fontsize=11, color=LOOP_COLOR, fontweight="bold", va="center")
    ax.annotate(f"{fmt_gas(last['gas_batched'])}  (-{last['saved_pct']}%)",
                xy=(last["n"], last["gas_batched"]),
                xytext=(8, 0), textcoords="offset points",
                fontsize=11, color=BATCHED_COLOR, fontweight="bold", va="center")

    ax.set_xlabel("N (number of blobs in batch)", fontsize=11)
    ax.set_ylabel("gas used", fontsize=11)
    ax.yaxis.set_major_formatter(mtick.FuncFormatter(lambda v, _: f"{v/1e6:.1f}M"))
    ax.grid(True, linestyle="-", linewidth=0.5, alpha=0.3)
    ax.set_axisbelow(True)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.legend(loc="lower right", frameon=False, fontsize=11)
    ax.set_title(title, fontsize=14, fontweight="600", loc="left", pad=18)
    ax.text(0, 1.02, subtitle, transform=ax.transAxes, fontsize=10, color="#555")

    fig.tight_layout()
    fig.savefig(out_path, dpi=130, bbox_inches="tight")
    plt.close(fig)
    print(f"wrote {out_path.relative_to(DATA_DIR.parent.parent)}")


def plot_savings(multi_blob: list[dict], multi_point: list[dict], out_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(9, 5.2), dpi=130)

    ns_mb = [r["n"] for r in multi_blob]
    saved_mb = [r["saved_pct"] for r in multi_blob]
    ns_mp = [r["n"] for r in multi_point]
    saved_mp = [r["saved_pct"] for r in multi_point]

    # Same marker-thinning as the gas-curves chart: under the crossover the
    # cluster of N=1..4 dots is noisy; keep only N=1 and N=3 below the
    # threshold, plus everything from N=5 onward.
    sub_crossover_keep = {1, 3}
    mb_marker_idxs = [i for i, n in enumerate(ns_mb)
                      if n >= 5 or n in sub_crossover_keep]
    mp_marker_idxs = [i for i, n in enumerate(ns_mp)
                      if n >= 5 or n in sub_crossover_keep]
    ax.plot(ns_mb, saved_mb, color=MULTI_BLOB_COLOR, marker="o", linewidth=2.2,
            label="multi-blob, shared z (verifySinglePointMultipleBlobs128)",
            markevery=mb_marker_idxs)
    ax.plot(ns_mp, saved_mp, color=MULTI_POINT_COLOR, marker="s", linewidth=2.2,
            label="multi-point, one blob (verifyMultiplePoints128)",
            markevery=mp_marker_idxs)

    ax.axhline(0, color="#666", linewidth=0.8)
    ax.axvline(5, color="#ff7f0e", linestyle="--", linewidth=2.2, alpha=0.95)
    crossover_mb = next((r["saved_pct"] for r in multi_blob if r["n"] == 5), None)
    crossover_mp = next((r["saved_pct"] for r in multi_point if r["n"] == 5), None)
    if crossover_mb is not None and crossover_mp is not None:
        # Each percentage uses its line's color — orange for the framing text.
        text_props = dict(fontsize=10, fontweight="700")
        orange = "#cc5e00"
        parts = [
            TextArea("crossover  N=5  ·  ", textprops={**text_props, "color": orange}),
            TextArea(f"{crossover_mb}%", textprops={**text_props, "color": MULTI_BLOB_COLOR}),
            TextArea(" / ", textprops={**text_props, "color": orange}),
            TextArea(f"{crossover_mp}%", textprops={**text_props, "color": MULTI_POINT_COLOR}),
        ]
        hbox = HPacker(children=parts, align="center", pad=0, sep=0)
        ab = AnnotationBbox(hbox, xy=(7, 68), xycoords="data",
                            box_alignment=(0, 0.5), frameon=False, pad=0)
        ax.add_artist(ab)
    else:
        ax.annotate("crossover  N=5", xy=(5, 70), xytext=(7, 68),
                    fontsize=10, color="#cc5e00", fontweight="700")
    ax.axvline(6, color="#888", linestyle=":", linewidth=1, alpha=0.5)
    ax.annotate("N=6 (today)", xy=(6, 5), xytext=(7, 3),
                fontsize=9, color="#555")

    # Strategic point labels — staggered across N so labels for the two
    # series don't compete for the same vertical space. The two lines run
    # within a few percentage points of each other, so we annotate
    # alternate Ns rather than both lines at every N.
    blob_label_ns = {10, 50}
    point_label_ns = {25}
    for r in multi_blob:
        if r["n"] in blob_label_ns:
            ax.annotate(f"{r['saved_pct']}%",
                        xy=(r["n"], r["saved_pct"]),
                        xytext=(0, -18), textcoords="offset points",
                        ha="center", fontsize=10, color=MULTI_BLOB_COLOR,
                        fontweight="700")
    for r in multi_point:
        if r["n"] in point_label_ns:
            ax.annotate(f"{r['saved_pct']}%",
                        xy=(r["n"], r["saved_pct"]),
                        xytext=(0, 12), textcoords="offset points",
                        ha="center", fontsize=10, color=MULTI_POINT_COLOR,
                        fontweight="700")

    last_mb = multi_blob[-1]
    last_mp = multi_point[-1]
    ax.annotate(f"{last_mb['saved_pct']}%", xy=(last_mb["n"], last_mb["saved_pct"]),
                xytext=(6, 0), textcoords="offset points",
                fontsize=10, color=MULTI_BLOB_COLOR, fontweight="bold", va="center")
    ax.annotate(f"{last_mp['saved_pct']}%", xy=(last_mp["n"], last_mp["saved_pct"]),
                xytext=(6, 0), textcoords="offset points",
                fontsize=10, color=MULTI_POINT_COLOR, fontweight="bold", va="center")

    ax.set_xlabel("N (batch size)", fontsize=11)
    ax.set_ylabel("gas saved vs 0x0A loop", fontsize=11)
    ax.yaxis.set_major_formatter(mtick.PercentFormatter(decimals=0))
    ax.set_ylim(-15, 80)
    ax.grid(True, linestyle="-", linewidth=0.5, alpha=0.3)
    ax.set_axisbelow(True)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.legend(loc="lower right", frameon=False, fontsize=10)
    ax.set_title("Gas savings vs. batch size", fontsize=14, fontweight="600",
                 loc="left", pad=18)
    ax.text(0, 1.02, "Negative below the crossover (threshold fallback overhead, ≤3% in absolute terms)",
            transform=ax.transAxes, fontsize=10, color="#555")

    fig.tight_layout()
    fig.savefig(out_path, dpi=130, bbox_inches="tight")
    plt.close(fig)
    print(f"wrote {out_path.relative_to(DATA_DIR.parent.parent)}")


def load_cost_matrix() -> dict:
    return json.load((DATA_DIR / "reference_replay.json").open())["costMatrix"]


def saved_for(rows: list[dict], n: int, baseline: str) -> float:
    """Look up annualized ETH saved for a specific N + baseline."""
    for r in rows:
        if r["n"] == n:
            return r["perYear"][baseline]["saved"]
    raise KeyError(n)


def plot_eth_saved_today(cm: dict, out_path: Path) -> None:
    """Bar chart: ETH/yr saved at TODAY's batch size (N=6), 4 baselines × 2 modes."""
    mb_rows = cm["multiBlob"]["rows"]
    mp_rows = cm["multiPoint"]["rows"]

    labels = [b[1] for b in BASELINES]
    mb_vals = [saved_for(mb_rows, 6, b[0]) for b in BASELINES]
    mp_vals = [saved_for(mp_rows, 6, b[0]) for b in BASELINES]

    fig, ax = plt.subplots(figsize=(9.5, 5.4), dpi=130)
    x = list(range(len(labels)))
    width = 0.38
    bars_mb = ax.bar([i - width / 2 for i in x], mb_vals, width,
                     label="Multi-blob, shared z", color=MULTI_BLOB_COLOR)
    bars_mp = ax.bar([i + width / 2 for i in x], mp_vals, width,
                     label="Multi-point, one blob", color=MULTI_POINT_COLOR)

    for bar, v in list(zip(bars_mb, mb_vals)) + list(zip(bars_mp, mp_vals)):
        ax.annotate(f"{v:.2f}",
                    xy=(bar.get_x() + bar.get_width() / 2, bar.get_height()),
                    xytext=(0, 3), textcoords="offset points",
                    ha="center", va="bottom", fontsize=9, fontweight="500")

    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=10)
    ax.set_ylabel("ETH saved per year", fontsize=11)
    ax.yaxis.set_major_formatter(mtick.FuncFormatter(lambda v, _: f"{v:.1f}"))
    ax.grid(True, axis="y", linestyle="-", linewidth=0.5, alpha=0.3)
    ax.set_axisbelow(True)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.legend(loc="upper left", frameon=False, fontsize=10)
    ax.set_title("ETH/yr left on the table at today's batch size (N=6)",
                 fontsize=14, fontweight="600", loc="left", pad=18)
    ax.text(0, 1.02,
            "Per-rollup annualized savings — 4,102 real txs over 90 days "
            "≈ 16,706 txs/yr, priced at historical Ethereum gas baselines",
            transform=ax.transAxes, fontsize=10, color="#555")

    fig.tight_layout()
    fig.savefig(out_path, dpi=130, bbox_inches="tight")
    plt.close(fig)
    print(f"wrote {out_path.relative_to(DATA_DIR.parent.parent)}")


def plot_eth_saved_scaling(cm: dict, out_path: Path) -> None:
    """Single panel: multi-blob ETH/yr saved at trailing-1y gas, vs N (capped at 100)."""
    baseline_key = "last1y"
    baseline_gwei = cm["baselines"][baseline_key]["gwei"]
    line_color = "#08519c"

    rows = [r for r in cm["multiBlob"]["rows"] if 5 <= r["n"] <= N_LIMIT]
    ns = [r["n"] for r in rows]
    ys = [r["perYear"][baseline_key]["saved"] for r in rows]

    fig, ax = plt.subplots(figsize=(10.5, 5.5), dpi=130)
    ax.plot(ns, ys, color=line_color, marker="o", markersize=8, linewidth=2.4,
            label=f"Trailing 1y ({baseline_gwei:.2f} gwei)")

    # Label every measured point with its ETH/yr value
    for n, y in zip(ns, ys):
        fmt = f"{y:.2f} ETH" if y < 10 else f"{y:.1f} ETH"
        # Slight upward offset; smaller font for crowded low-N region
        offset = (0, 11)
        ax.annotate(fmt, xy=(n, y), xytext=offset, textcoords="offset points",
                    ha="center", fontsize=10, color=line_color, fontweight="600")

    # Today marker
    ax.axvline(6, color="#ff7f0e", linestyle="--", linewidth=2.2, alpha=0.95)
    ax.annotate("today (N=6)", xy=(6, max(ys) * 0.4),
                xytext=(9, 0), textcoords="offset points",
                fontsize=10, color="#cc5e00", va="center", fontweight="700")

    ax.set_yscale("log")
    ax.set_xlim(0, 110)
    ax.yaxis.set_major_formatter(mtick.FuncFormatter(
        lambda v, _: f"{v:,.0f}" if v >= 1 else f"{v:.2f}"))
    ax.set_xlabel("N (batch size)", fontsize=11)
    ax.set_ylabel("ETH saved per year", fontsize=11)
    ax.grid(True, which="both", linestyle="-", linewidth=0.5, alpha=0.25)
    ax.set_axisbelow(True)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.legend(loc="lower right", frameon=False, fontsize=11)
    ax.set_title("Annualized ETH saved by Blober (multi-blob, shared z)",
                 fontsize=15, fontweight="700", loc="left", pad=14)

    fig.tight_layout()
    fig.savefig(out_path, dpi=130, bbox_inches="tight")
    plt.close(fig)
    print(f"wrote {out_path.relative_to(DATA_DIR.parent.parent)}")


def main() -> None:
    multi_blob_all = load_csv(DATA_DIR / "synthetic_gas_multi_blob_one_point.csv")
    multi_point_all = load_csv(DATA_DIR / "synthetic_gas_multi_point_one_blob.csv")

    multi_blob = filter_to_limit(multi_blob_all, N_LIMIT)
    multi_point = filter_to_limit(multi_point_all, N_LIMIT)

    plot_curves(
        multi_blob,
        title="Gas usage — industry standard vs. Blober",
        subtitle="Multi-blob, shared z (verifySinglePointMultipleBlobs128)",
        out_path=DATA_DIR / "chart_gas_curves_multi_blob.png",
    )
    plot_curves(
        multi_point,
        title="Gas usage — industry standard vs. Blober",
        subtitle="Multi-point, one blob (verifyMultiplePoints128)",
        out_path=DATA_DIR / "chart_gas_curves_multi_point.png",
    )
    plot_savings(
        multi_blob,
        multi_point,
        out_path=DATA_DIR / "chart_savings.png",
    )

    cm = load_cost_matrix()
    plot_eth_saved_today(cm, DATA_DIR / "chart_eth_saved_today.png")
    plot_eth_saved_scaling(cm, DATA_DIR / "chart_eth_saved_scaling.png")


if __name__ == "__main__":
    main()
