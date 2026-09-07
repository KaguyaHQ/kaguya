#!/usr/bin/env bash
# Run on the Linux Docker host. Uses the existing image without starting Kaguya.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
image="${BENCH_IMAGE:-$(docker inspect --format '{{.Image}}' kaguya-kaguya-1)}"
model_dir="${BENCH_MODEL_DIR:-/home/deploy/kaguya/data}"
container="kaguya-exla-bench-$$"
output_dir="$(mktemp -d /tmp/kaguya-exla-output.XXXXXX)"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true; rm -rf -- "$output_dir"' EXIT

for mode in ${BENCH_MODES:-eager jit verify}; do
  timeout 300 docker run --rm --pull never --init \
    --user "$(id -u):$(id -g)" \
    --name "$container" --network none --cpus 1 \
    --memory 1100m --memory-swap 1100m --read-only \
    --tmpfs /tmp:rw,size=128m \
    --mount "type=bind,src=$script_dir/exla_benchmark.exs,dst=/bench.exs,readonly" \
    --mount "type=bind,src=$model_dir,dst=/model,readonly" \
    --mount "type=bind,src=$output_dir,dst=/results" \
    -e BENCH_OUTPUT_DIR=/results \
    -e "BENCH_MODE=$mode" -e BENCH_MODEL=/model/ease_B.npy \
    -e "BENCH_LOADER=${BENCH_LOADER:-current}" \
    -e "BENCH_SIZES=${BENCH_SIZES:-10,50,100,250,500,1000,2000}" \
    -e "BENCH_REPEATS=${BENCH_REPEATS:-10}" \
    --entrypoint /bin/sh "$image" -c \
    'set -- /app/releases/*/start_clean.boot; boot=${1%.boot}; exec /app/erts-*/bin/erl +S 1:1 +SDcpu 1 +SDio 1 -boot "$boot" -boot_var RELEASE_LIB /app/lib -pa /app/lib/*/ebin -noshell -s elixir start_cli -extra /bench.exs'
done
