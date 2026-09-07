# EXLA scoring benchmark

Run `BENCH_LOADER=binary_first bash scripts/exla_benchmark.sh` on a Linux Docker host with an existing
Kaguya release image and the trained `ease_B.npy` file. The script defaults to
the image used by `kaguya-kaguya-1` and `/home/deploy/kaguya/data`.
Override these with `BENCH_IMAGE` and `BENCH_MODEL_DIR`.

Each timing mode runs in a fresh container with one CPU, one BEAM scheduler, a
1,100 MiB memory limit, no swap, no network, and read-only model/root mounts.
Only EXLA and its dependencies start; Kaguya, Oban, and the database do not.
Each container has a five-minute timeout. Run sequentially and check available
host memory first; the memory limit is a cap, not a reservation.

The default workload uses the actual model and deterministic synthetic histories
of 10, 50, 100, 250, 500, 1,000, and 2,000 ratings. It covers positive and negative
centered preferences without accessing user data. Set `BENCH_SIZES` to a
comma-separated list and `BENCH_REPEATS` to change the default ten repetitions.

- `eager`: `Nx.Defn.Evaluator` over tensors stored on `EXLA.Backend`, matching
  the current application's compiler/backend combination.
- `jit`: the same `Engine.ease_scores/3` function with explicit `EXLA.jit`.
  The matrix remains a runtime argument rather than a captured constant.
- `verify`: compares both modes with identical inputs, checks numerical
  agreement, and reports positive top-50 candidate overlap after excluding
  input VNs. It reads the saved output tensors in a third, lightweight process;
  it neither loads the model nor retains either compiler's cache.

`BENCH_LOADER=current` (the default) reproduces the existing NPY loader.
`BENCH_LOADER=binary_first` reshapes on `Nx.BinaryBackend` before transferring
the tensor to EXLA, avoiding a full-matrix reshape on the native backend.
It uses a short-lived loader process and synchronizes a one-element read before
exiting, keeping source-file buffers out of the scoring process's heap.
This is a benchmark-only alternative; the production loader is unchanged.
The current loader exceeded the container limit in the run below, which is why
the documented scoring command selects the alternative. Both scoring modes
must use the same loader for a fair comparison.

Set `BENCH_MODES=eager` or `BENCH_MODES=jit` for timing only. The default
`eager jit verify` sequence also validates the outputs. Verification requires
both timing modes earlier in the same run; temporary tensors are removed on exit.
Standard output contains JSON lines for model load, each shape, and aggregate
timing. First-call time includes compilation; warm calls reuse the same shape.
For an even repetition count, the reported median is the upper middle sample.
Reading the output tensor synchronizes asynchronous EXLA execution. Peak memory
comes from Linux `VmHWM`, including native allocations, and is cumulative over
the process lifetime. It does not measure container page cache or host-wide RAM.
RSS counts shared mappings, so it can exceed the cgroup memory limit without
the container exceeding its charged memory allocation.

This is a scoring-kernel benchmark, not an end-to-end recommendation job or
quality evaluation. It excludes database work, production masks, fallback
scoring, ranking, explanations, and result persistence. CPU limits and synthetic
histories also mean these are comparative measurements, not production latency
predictions. Changed preference counts may compile new executables; first-pass
and warm-batch totals are both relevant before enabling the compiler in serving.

## Deployment layers

The Dockerfile compiles Elixir dependencies before installing frontend packages.
The final release is divided into a stable layer (ERTS and dependencies, including
EXLA) and an application layer (Kaguya, release metadata, and Sentry). Sentry stays
with the application because `mix sentry.package_source_code` embeds app sources
in its `priv` directory. Moving files out of the application overlay avoids
duplicating native libraries. Dependency or runtime upgrades still replace the
stable layer as expected.

## Results: 2026-09-07

Measured on the existing x86-64 Linux host, using Nx/EXLA 0.11.0 and the
11,273 x 11,273 float32 model (508,322,244 bytes). Source image:
`sha256:f9df9f22f9c3552e0fcf23993d62747464fdf126bdef9c3ce57d932b23d83bfc`.
Both modes used `BENCH_LOADER=binary_first` and the limits described above.
Raw measurements are emitted as JSON lines on standard output. Capture them in
an ignored location (for example, `tmp/exla_benchmark_results.ndjson`); the
summary below is the versioned record.

| Ratings | Eager warm ms | Explicit JIT warm ms |
| --- | ---: | ---: |
| 10 | 2.74 | 0.56 |
| 50 | 4.99 | 1.46 |
| 100 | 9.32 | 5.49 |
| 250 | 25.33 | 7.79 |
| 500 | 75.83 | 17.71 |
| 1,000 | 112.10 | 53.85 |
| 2,000 | 263.88 | 80.60 |

The 70 warm calls took 4.927 seconds with the evaluator and 1.647 seconds with
explicit JIT (2.99x faster). The first call at each of the seven shapes totaled
2.623 versus 1.144 seconds, excluding model loading. Every output score was
identical in this workload: maximum absolute difference was zero at every shape.
All positive top candidates matched, including the larger histories with fewer
than 50 positive candidates. This validates numerical parity for these inputs,
not recommendation quality or the entire serving pipeline.

Peak process RSS was 1,206 MiB for eager execution and 1,230 MiB for JIT. Final
RSS was 1,027 versus 733 MiB. These measurements do not establish a reduction in
peak memory. The unmodified loader was killed with exit 137 under the 1,100 MiB
container cap before scoring; early binary-first experiments also hit that cap
intermittently. The completed run used a separate, synchronized loader process
and compared saved outputs rather than keeping both compilers live together.
There was no higher memory limit or swap allowance for the benchmark containers.

Docker validation repackaged an existing compiled production release twice,
changing one application file between builds. The 542 MB dependency/runtime layer
remained identical; the 26.8 MB application layer changed. This checks the actual
partition and final-image assembly, but does not substitute for a full source
build in CI. Release script permissions, native-library linkage, and both eager
and JIT inference on an 8 x 8 fixture passed in the repackaged image.
The frontend installation now follows `mix deps.compile`, so frontend
package changes no longer invalidate that compilation layer.

The serving compiler and NPY loader remain unchanged. The results support a
follow-up that applies the loader improvement and explicit compilation to the
scoring entry point, with integration coverage for masking, fallback scoring,
and explanations. Keep the full matrix while validating those changes; this
benchmark supplies no quality evidence for pruning or replacing the model.
