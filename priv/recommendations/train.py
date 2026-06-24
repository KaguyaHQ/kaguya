#!/usr/bin/env python3
"""Train one or all of the recommendation models.

Single entrypoint replacing the previous per-method scripts. Loads the shared
training matrix, dispatches to the right `trainers.train_*` function with
method-specific kwargs, and writes the result to `priv/data/{method}_B.npy`.

Usage:
    python3 priv/recommendations/train.py all     # train every method with tuned defaults
    python3 priv/recommendations/train.py ease    [--lambda 500]
    python3 priv/recommendations/train.py svd     [--factors 128] [--weight sigma]
    python3 priv/recommendations/train.py als     [--factors 64]  [--iterations 20] [--alpha 1.0]
    python3 priv/recommendations/train.py lda     [--num-topics 200] [--positive-threshold 7.0]
    python3 priv/recommendations/train.py pmi     [--percentile 70]
    python3 priv/recommendations/train.py lightfm [--epochs 100] [--loss bpr]
    python3 priv/recommendations/train.py surprise_svd [--factors 200]

Common flags (all methods):
    --training PATH    sparse matrix from build_training_matrix.py
    --out-dir DIR      where to write {method}_B.npy + _meta.json (default: priv/data)
"""

import argparse
import json
import os
import sys
import time
from inspect import signature

import numpy as np
from scipy import sparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scoring import mean_center_users
from trainers import (
    train_ease, train_svd, train_als, train_lda, train_pmi,
)


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


# Per-method config: trainer fn, input kind, parser-config callback.
# `add_args` receives a subparser and registers method-specific flags whose
# names match the trainer kwargs (so we can pass them straight through).
def _add_ease_args(p):
    p.add_argument("--lambda", dest="reg_lambda", type=float, default=500.0)


def _add_svd_args(p):
    p.add_argument("--factors", type=int, default=128)
    p.add_argument("--weight", default="sigma",
                   choices=["none", "sigma", "sigma2", "cosine"],
                   help="B = V·f(Σ)·Vᵀ. 'sigma' won the 2026-04-14 sweep.")


def _add_als_args(p):
    p.add_argument("--factors", type=int, default=64,
                   help="Tuned default — 64 beat 128/200 on R@20.")
    p.add_argument("--iterations", type=int, default=20)
    p.add_argument("--regularization", type=float, default=0.01)
    p.add_argument("--alpha", type=float, default=1.0)


def _add_lda_args(p):
    p.add_argument("--num-topics", dest="num_topics", type=int, default=200,
                   help="Tuned default — 200 beats 128 by +44% R@20; 256 plateaus.")
    p.add_argument("--iterations", type=int, default=200)
    p.add_argument("--passes", type=int, default=4)
    p.add_argument("--positive-threshold", dest="positive_threshold",
                   type=float, default=7.0)
    p.add_argument("--min-doc-len", dest="min_doc_len", type=int, default=3)
    p.add_argument("--seed", type=int, default=42)


def _add_pmi_args(p):
    p.add_argument("--percentile", type=float, default=70.0)
    p.add_argument("--min-votes", dest="min_votes", type=int, default=15)


def _add_lightfm_args(p):
    p.add_argument("--factors", type=int, default=64)
    p.add_argument("--epochs", type=int, default=100,
                   help="Tuned default — 100 epochs with BPR clears popularity on NDCG; below on R@20.")
    p.add_argument("--loss", default="bpr", choices=["warp", "bpr", "logistic", "warp-kos"])
    p.add_argument("--no-content", dest="use_content", action="store_false")
    p.set_defaults(use_content=True)


def _add_surprise_svd_args(p):
    p.add_argument("--factors", type=int, default=200,
                   help="Tuned default — 200 factors beats 64 / 128 on R@20.")
    p.add_argument("--n-epochs", dest="n_epochs", type=int, default=20)
    p.add_argument("--lr-all", dest="lr_all", type=float, default=0.005)
    p.add_argument("--reg-all", dest="reg_all", type=float, default=0.02)


# We import here (not at module top) so the script still runs for ease/svd/als/
# lda/pmi even when lightfm or surprise isn't installed locally.
from trainers import train_lightfm, train_surprise_svd  # noqa: E402

METHODS = {
    "ease":         ("centered", train_ease,         _add_ease_args),
    "svd":          ("centered", train_svd,          _add_svd_args),
    "als":          ("raw",      train_als,          _add_als_args),
    "lda":          ("raw",      train_lda,          _add_lda_args),
    "pmi":          ("raw",      train_pmi,          _add_pmi_args),
    "lightfm":      ("raw",      train_lightfm,      _add_lightfm_args),
    "surprise_svd": ("raw",      train_surprise_svd, _add_surprise_svd_args),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--training", default="priv/data/ease_training.npz")
    parser.add_argument("--training-meta", default="priv/data/ease_training_meta.json")
    parser.add_argument("--out-dir", default="priv/data")

    sub = parser.add_subparsers(dest="method", required=True,
                                metavar="{all," + ",".join(METHODS) + "}")
    sub.add_parser("all", help="train every method with its tuned defaults")
    for name, (_kind, _fn, add_args) in METHODS.items():
        p = sub.add_parser(name)
        add_args(p)
    args = parser.parse_args()

    log(f"Loading {args.training}...")
    X = sparse.load_npz(args.training)
    log(f"  X shape={X.shape} nnz={X.nnz:,}")
    with open(args.training_meta) as f:
        train_meta = json.load(f)
    # Mean-center once and reuse across centered methods (saves ~5s per call).
    X_centered = mean_center_users(X)

    if args.method == "all":
        run_all(X, X_centered, train_meta, args.out_dir)
    else:
        input_kind, trainer, _add = METHODS[args.method]
        kwargs = _kwargs_for(args, trainer)
        run_one(args.method, input_kind, trainer, kwargs,
                X, X_centered, train_meta, args.out_dir)


def run_all(X, X_centered, train_meta, out_dir):
    total = len(METHODS)
    overall_t0 = time.time()
    for i, (name, (input_kind, trainer, _)) in enumerate(METHODS.items(), 1):
        log(f"[{i}/{total}] {name}")
        run_one(name, input_kind, trainer, {}, X, X_centered, train_meta, out_dir)
    log(f"All {total} methods trained in {time.time() - overall_t0:.1f}s")


def run_one(name, input_kind, trainer, kwargs, X, X_centered, train_meta, out_dir):
    log(f"Training {name} (input={input_kind}, kwargs={kwargs})")
    X_in = X_centered if input_kind == "centered" else X

    t0 = time.time()
    B = trainer(X_in, dtype=np.float32, **kwargs)
    log(f"  Trained in {time.time() - t0:.1f}s")
    log(f"  B {B.shape} {B.nbytes / 1e9:.2f} GB  range=[{B.min():.4f}, {B.max():.4f}]")

    out_b = os.path.join(out_dir, f"{name}_B.npy")
    out_meta = os.path.join(out_dir, f"{name}_B_meta.json")
    os.makedirs(out_dir, exist_ok=True)

    log(f"  Saving {out_b}")
    np.save(out_b, B)

    meta = {
        "method": name,
        "kwargs": kwargs,
        "shape": list(B.shape),
        "dtype": str(B.dtype),
        "trained_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "model_version": f"{name}-{time.strftime('%Y%m%d')}",
        "idx_to_vndb": train_meta["idx_to_vndb"],
        "vn_counts": train_meta["vn_counts"],
    }
    with open(out_meta, "w") as f:
        json.dump(meta, f)


def _kwargs_for(args, trainer):
    """Pass through only the kwargs the trainer actually accepts."""
    trainer_params = set(signature(trainer).parameters)
    return {k: v for k, v in vars(args).items()
            if k in trainer_params and v is not None}


if __name__ == "__main__":
    main()
