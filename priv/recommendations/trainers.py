"""Reusable training functions for each recommendation method.

Each function takes a sparse training matrix X (users × items, mean-centered
or raw depending on the method's expectation) and returns a dense float32 B
matrix (item × item) suitable for `r @ B` scoring.

Used by both `train.py` (for the production B matrices written to priv/data/)
and `eval_harness.py` (for honest holdout evaluation — retrains each method
on the 90% split rather than reusing the production B trained on 100%).

Function defaults reflect the tuned production configs (sweep results in
`priv/data/method_tune_sweep.json`). The TRAINERS registry at the bottom of
this file pins extra eval-only variants used for tuning sweeps.
"""

import numpy as np
from scipy import sparse
from scipy.sparse.linalg import svds


# Lazy imports for heavy optional libs (lightfm, surprise) live inside the
# trainer functions so the module loads even when those libs aren't installed.


def train_ease(X_centered, *, reg_lambda=500.0, dtype=np.float32):
    """EASE closed-form item-item similarity (Steck 2019)."""
    X = X_centered.astype(dtype)
    G = (X.T @ X).toarray()
    del X
    n = G.shape[0]
    G.flat[::n + 1] += reg_lambda
    P = np.linalg.inv(G)
    del G
    diag = np.diag(P).copy()
    P /= -diag[np.newaxis, :]
    np.fill_diagonal(P, 0.0)
    return P


def train_svd(X_centered, *, factors=128, weight="sigma", dtype=np.float32):
    """Truncated SVD.

    weight:
      "none"     — B = V·Vᵀ (PureSVD, Cremonesi 2010)
      "sigma"    — B = V·Σ·Vᵀ (full reconstruction, scales by singular values)
      "sigma2"   — B = V·Σ²·Vᵀ (squared scaling, emphasizes top dims)
      "cosine"   — B = cosine(V) — normalize each item's latent vector
    """
    X = X_centered.astype(dtype)
    U, s, Vt = svds(X, k=factors)
    order = np.argsort(-s)
    s = s[order]
    Vt = Vt[order]
    V = Vt.T  # (n_items, k)

    if weight == "none":
        B = V @ V.T
    elif weight == "sigma":
        B = V * s[np.newaxis, :] @ V.T  # = V·Σ·Vᵀ
    elif weight == "sigma2":
        B = V * (s ** 2)[np.newaxis, :] @ V.T
    elif weight == "cosine":
        norms = np.linalg.norm(V, axis=1, keepdims=True)
        norms[norms == 0] = 1.0
        Vn = V / norms
        B = Vn @ Vn.T
    else:
        raise ValueError(f"unknown weight={weight!r}")

    B = B.astype(dtype)
    np.fill_diagonal(B, 0.0)
    return B


def train_als(X_raw, *, factors=64, iterations=20, regularization=0.01,
              alpha=1.0, dtype=np.float32, show_progress=False):
    """ALS via implicit. Takes RAW (not centered) — confidence-weighted."""
    import os
    os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
    import implicit

    X_conf = X_raw.copy().astype(np.float32)
    X_conf.data = 1.0 + alpha * X_conf.data

    model = implicit.als.AlternatingLeastSquares(
        factors=factors,
        regularization=regularization,
        iterations=iterations,
        use_gpu=False,
        calculate_training_loss=False,
    )
    model.fit(X_conf, show_progress=show_progress)
    V = np.asarray(model.item_factors, dtype=dtype)
    B = (V @ V.T).astype(dtype)
    np.fill_diagonal(B, 0.0)
    return B


def train_lda(X_raw, *, num_topics=200, iterations=200, passes=4,
              positive_threshold=7.0, min_doc_len=3, seed=42, dtype=np.float32):
    """LDA topic model. Binary inclusion at vote ≥ threshold; B = cosine of
    item-topic distributions (analytical, no sampling)."""
    from gensim.models import LdaModel

    n_users, n_items = X_raw.shape

    corpus = []
    for u in range(n_users):
        a, b = X_raw.indptr[u], X_raw.indptr[u + 1]
        if b <= a:
            continue
        items = X_raw.indices[a:b]
        vals = X_raw.data[a:b]
        liked = items[vals >= positive_threshold]
        if len(liked) < min_doc_len:
            continue
        corpus.append([(int(j), 1) for j in liked])

    id2word = {i: str(i) for i in range(n_items)}
    lda = LdaModel(
        corpus=corpus,
        num_topics=num_topics,
        id2word=id2word,
        iterations=iterations,
        passes=passes,
        chunksize=2000,
        random_state=seed,
        eval_every=None,
    )

    item_topic = np.zeros((n_items, num_topics), dtype=dtype)
    for i in range(n_items):
        for topic_id, prob in lda.get_term_topics(i, minimum_probability=0.0):
            item_topic[i, topic_id] = prob

    norms = np.linalg.norm(item_topic, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    item_topic_n = item_topic / norms
    B = (item_topic_n @ item_topic_n.T).astype(dtype)
    np.fill_diagonal(B, 0.0)
    return B


def train_lightfm(X_raw, *, factors=64, epochs=100, loss="bpr",
                  features_meta="priv/data/ease_training_meta.json",
                  features_path="priv/data/vn_features.json",
                  use_content=True, dtype=np.float32):
    """LightFM hybrid factorization with item features.

    The unique value vs ALS/SVD: each item's embedding includes contributions
    from its content features (writers, producers, series). New VNs with few
    ratings still get a meaningful embedding inherited from those features.

    With `use_content=False`, runs as plain LightFM (CF only with WARP loss)
    for a clean comparison vs ALS.
    """
    import json
    from lightfm import LightFM
    from lightfm.data import Dataset

    n_users, n_items = X_raw.shape

    # Load idx_to_vndb so we can attach features by their VNDB id.
    with open(features_meta) as f:
        idx_to_vndb = json.load(f)["idx_to_vndb"]
    with open(features_path) as f:
        features = json.load(f)

    # Per-item feature tags. Namespace each feature so writers/producers/series
    # never collide on a shared int id (e.g. writer aid 42 vs producer "p42").
    if use_content:
        item_feature_lists = []
        for i in range(n_items):
            f = features.get(idx_to_vndb[i], {})
            tags = []
            tags += [f"w:{w}" for w in f.get("writers", [])]
            tags += [f"p:{p}" for p in f.get("producers", [])]
            tags += [f"s:{s}" for s in f.get("series", [])]
            item_feature_lists.append(tags)

        all_feature_tags = sorted({t for tags in item_feature_lists for t in tags})
    else:
        item_feature_lists = [[] for _ in range(n_items)]
        all_feature_tags = []

    dataset = Dataset()
    dataset.fit(
        users=range(n_users),
        items=range(n_items),
        item_features=all_feature_tags,
    )

    interactions, _ = dataset.build_interactions(
        (int(u), int(j), float(v))
        for u in range(n_users)
        for j, v in zip(X_raw[u].indices, X_raw[u].data)
    )

    item_features_matrix = (
        dataset.build_item_features([(i, tags) for i, tags in enumerate(item_feature_lists)])
        if use_content else None
    )

    model = LightFM(no_components=factors, loss=loss, random_state=42)
    model.fit(
        interactions,
        item_features=item_features_matrix,
        epochs=epochs,
        num_threads=4,
    )

    # Item representations: with features, sums per-item bias + sum of feature
    # embeddings. Without features, just the item embedding directly.
    _biases, item_embeddings = model.get_item_representations(features=item_features_matrix)
    V = np.asarray(item_embeddings, dtype=dtype)
    B = (V @ V.T).astype(dtype)
    np.fill_diagonal(B, 0.0)
    return B


def train_surprise_svd(X_raw, *, factors=200, n_epochs=20,
                       lr_all=0.005, reg_all=0.02, dtype=np.float32):
    """Funk SVD via the `surprise` library — matrix factorization with
    explicit user / item bias terms (the variant family that won the
    Netflix Prize). Bias terms are scalars and don't affect item-item
    similarity, so the returned B = qi · qiᵀ uses only the item factors."""
    from surprise import SVD, Dataset, Reader
    import pandas as pd

    n_items = X_raw.shape[1]

    # Build (user, item, rating) triples from the sparse matrix.
    coo = X_raw.tocoo()
    df = pd.DataFrame({
        "uid": coo.row.astype(str),
        "iid": coo.col.astype(str),
        "rating": coo.data.astype(float),
    })
    reader = Reader(rating_scale=(float(coo.data.min()), float(coo.data.max())))
    data = Dataset.load_from_df(df, reader)
    trainset = data.build_full_trainset()

    model = SVD(
        n_factors=factors,
        n_epochs=n_epochs,
        lr_all=lr_all,
        reg_all=reg_all,
        random_state=42,
    )
    model.fit(trainset)

    # Surprise reindexes items internally — re-project back to our ordering.
    V = np.zeros((n_items, factors), dtype=dtype)
    for inner_iid in range(trainset.n_items):
        raw_iid = int(trainset.to_raw_iid(inner_iid))
        V[raw_iid] = model.qi[inner_iid]

    B = (V @ V.T).astype(dtype)
    np.fill_diagonal(B, 0.0)
    return B


def train_pmi(X_raw, *, percentile=70.0, min_votes=15, dtype=np.float32):
    """bunnyadvocate's PMI: per-item percentile-thresholded loved-co-occurrence."""
    Xc = X_raw.tocsc()
    n_users, n_items = Xc.shape

    rows, cols = [], []
    for j in range(n_items):
        a, b = Xc.indptr[j], Xc.indptr[j + 1]
        if b <= a:
            continue
        col_data = Xc.data[a:b]
        col_users = Xc.indices[a:b]
        if len(col_data) >= min_votes:
            threshold = np.percentile(col_data, percentile)
        else:
            threshold = -np.inf
        loved_idx = col_users[col_data >= threshold]
        rows.extend(loved_idx.tolist())
        cols.extend([j] * len(loved_idx))

    L = sparse.csr_matrix(
        (np.ones(len(rows), dtype=dtype), (rows, cols)),
        shape=(n_users, n_items),
    )
    G = (L.T @ L).toarray().astype(dtype)
    pop = np.diag(G).copy()
    n_loved_users = max(int((L.sum(axis=1) > 0).sum()), 1)
    expected = np.outer(pop, pop) / n_loved_users
    B = np.log((G + 1.0) / (expected + 1.0)).astype(dtype)
    np.fill_diagonal(B, 0.0)
    return B


# Method registry. (input_kind, fn, kwargs) — input_kind is "centered" or
# "raw" depending on whether the trainer expects a mean-centered matrix.
#
# `eval_harness.py` enumerates this dict to run sweeps. Production training
# uses train.py, which only references the 5 method names below; the rest are
# eval-only variants kept for tuning reproducibility.
TRAINERS = {
    # Production (function defaults already reflect the tuned config)
    "ease":         ("centered", train_ease,         {}),
    "svd":          ("centered", train_svd,          {}),
    "als":          ("raw",      train_als,          {}),
    "lda":          ("raw",      train_lda,          {}),
    "pmi":          ("raw",      train_pmi,          {}),
    "lightfm":      ("raw",      train_lightfm,      {}),
    "surprise_svd": ("raw",      train_surprise_svd, {}),

    # EASE: regularization sweep
    "ease_l100":   ("centered", train_ease, {"reg_lambda": 100.0}),
    "ease_l250":   ("centered", train_ease, {"reg_lambda": 250.0}),
    "ease_l1000":  ("centered", train_ease, {"reg_lambda": 1000.0}),
    "ease_l2000":  ("centered", train_ease, {"reg_lambda": 2000.0}),

    # LightFM variants
    "lightfm_pure":     ("raw", train_lightfm, {"use_content": False}),
    "lightfm_k128":     ("raw", train_lightfm, {"factors": 128}),
    "lightfm_bpr":      ("raw", train_lightfm, {"loss": "bpr"}),
    "lightfm_e100":     ("raw", train_lightfm, {"epochs": 100}),
    "lightfm_bpr_e100": ("raw", train_lightfm, {"loss": "bpr", "epochs": 100}),

    # Surprise SVD variants
    "surprise_svd_k64":  ("raw", train_surprise_svd, {"factors": 64}),
    "surprise_svd_k200": ("raw", train_surprise_svd, {"factors": 200}),

    # SVD: factor count + weighting variants
    "svd_k32":      ("centered", train_svd, {"factors": 32}),
    "svd_k64":      ("centered", train_svd, {"factors": 64}),
    "svd_k200":     ("centered", train_svd, {"factors": 200}),
    "svd_unweighted": ("centered", train_svd, {"weight": "none"}),
    "svd_sigma2":   ("centered", train_svd, {"weight": "sigma2"}),
    "svd_cosine":   ("centered", train_svd, {"weight": "cosine"}),

    # ALS: factors / iterations / confidence
    "als_k128":     ("raw", train_als, {"factors": 128}),
    "als_k200":     ("raw", train_als, {"factors": 200}),
    "als_iter40":   ("raw", train_als, {"iterations": 40}),
    "als_alpha10":  ("raw", train_als, {"alpha": 10.0}),

    # LDA: topic count + threshold
    "lda_t32":      ("raw", train_lda, {"num_topics": 32}),
    "lda_t50":      ("raw", train_lda, {"num_topics": 50}),  # gist default
    "lda_t64":      ("raw", train_lda, {"num_topics": 64}),
    "lda_t96":      ("raw", train_lda, {"num_topics": 96}),
    "lda_t200":     ("raw", train_lda, {"num_topics": 200}),
    "lda_t256":     ("raw", train_lda, {"num_topics": 256}),
    "lda_thresh6":  ("raw", train_lda, {"positive_threshold": 6.0}),
    "lda_thresh8":  ("raw", train_lda, {"positive_threshold": 8.0}),

    # PMI: percentile threshold
    "pmi_p50":      ("raw", train_pmi, {"percentile": 50.0}),
    "pmi_p80":      ("raw", train_pmi, {"percentile": 80.0}),
    "pmi_p90":      ("raw", train_pmi, {"percentile": 90.0}),
}
