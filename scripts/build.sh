#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Builds llama-server from the tree the model file pins (the PrismML fork for Bonsai, mainline or
# Unsloth's for Qwen) into its own LLAMA_DIR: static, CUDA or Vulkan (BACKEND), with the model
# file's PATCH_DIR applied. The source is a git commit, or a release tarball checked against
# LLAMA_TARBALL_SHA256 where the commit cannot be fetched. FORCE=1 rebuilds even when the pinned
# binary is there.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The stamp names commit, backend and patch set, so a change to any of them triggers a rebuild.
patches=()
patch_dir="$ROOT/${PATCH_DIR:-no-patches}"
[[ -n "$PATCH_DIR" && -d "$patch_dir" ]] && mapfile -t patches < <(ls "$patch_dir"/*.patch 2>/dev/null | sort)
want="$LLAMA_COMMIT $BACKEND $(cat "${patches[@]}" /dev/null | sha256sum | cut -c1-12)"
# An unpatched CUDA build keeps the old stamp format, so existing installs do not rebuild for nothing.
[[ "$BACKEND" == cuda && ${#patches[@]} -eq 0 ]] && want="$LLAMA_COMMIT"
[[ -n "$LLAMA_TARBALL" ]] && want="$want ${LLAMA_TARBALL_SHA256:0:12}"

stamp="$LLAMA_DIR/build/.bonsai-commit"
if [[ -z "${FORCE:-}" && -x "$LLAMA_SERVER" && "$(cat "$stamp" 2>/dev/null)" == "$want" ]]; then
  log "llama-server at ${LLAMA_COMMIT:0:7} ($BACKEND) already built"
  exit 0
fi

case "$BACKEND" in
  cuda)   has nvcc  || die "nvcc not found - run ./install.sh deps, or install CUDA >= 12.4 yourself (docs/setup.md#toolchain)" ;;
  vulkan) has glslc || die "glslc not found - run ./install.sh deps, or install the Vulkan SDK yourself (docs/setup.md#toolchain)" ;;
esac

mkdir -p "$LLAMA_DIR"
cd "$LLAMA_DIR"
if [[ -n "$LLAMA_TARBALL" ]]; then
  # Unsloth's source commit is not fetchable ("not our ref"), so its release tarball is the source
  # and its checksum the pin. Everything but build/ is replaced, which keeps the tree as clean as
  # a forced checkout and the cmake cache and ccache as warm.
  [[ -n "$LLAMA_TARBALL_SHA256" ]] || die "LLAMA_TARBALL is set without LLAMA_TARBALL_SHA256 - a tarball source needs its checksum in the model file"
  [[ -z "$(ls -A)" || -f .bonsai-tarball ]] \
    || die "$LLAMA_DIR is not empty and not a tarball tree this script unpacked - point LLAMA_DIR elsewhere or empty it"
  log "fetching ${LLAMA_TARBALL##*/} (${LLAMA_COMMIT:0:7})"
  tarball="$(mktemp)"
  curl -fsSL --retry 3 -o "$tarball" "$LLAMA_TARBALL" || { rm -f "$tarball"; die "could not download $LLAMA_TARBALL"; }
  have_sha="$(sha256sum "$tarball" | cut -d' ' -f1)"
  [[ "$have_sha" == "$LLAMA_TARBALL_SHA256" ]] \
    || { rm -f "$tarball"; die "$LLAMA_TARBALL has sha256 $have_sha, the model file pins $LLAMA_TARBALL_SHA256 - not unpacking it"; }
  find . -mindepth 1 -maxdepth 1 ! -name build -exec rm -rf {} +
  tar xzf "$tarball" --strip-components=1
  rm -f "$tarball"
  echo "$LLAMA_TARBALL_SHA256" > .bonsai-tarball
else
  log "fetching ${LLAMA_REPO#https://github.com/} at ${LLAMA_COMMIT:0:7}"
  [[ -d .git ]] || { git init -q; git remote add origin "$LLAMA_REPO"; }
  git fetch -q --depth 1 origin "$LLAMA_COMMIT"
  git checkout -q --force FETCH_HEAD
fi

# The tree above is clean, so the patches always apply to the pinned tree, never on top
# of themselves. Moving LLAMA_COMMIT means re-checking that they still apply.
for p in "${patches[@]}"; do
  log "applying $PATCH_DIR/$(basename "$p")"
  git apply --check "$p" || die "patch does not apply to ${LLAMA_COMMIT:0:7} - the pin moved without rebasing $PATCH_DIR"
  git apply "$p"
done

launchers=()
has ccache && launchers=(-DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_C_COMPILER_LAUNCHER=ccache)

backend_flags=()
case "$BACKEND" in
  cuda)
    arch="$CUDA_ARCH"
    [[ -n "$arch" ]] || arch="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.')" || true
    [[ "$arch" =~ ^[0-9]+$ ]] || arch=native

    # nvcc before 12.8 does not know Blackwell (sm_120, RTX 50xx) and fails mid-build
    nvcc_ver="$(nvcc --version | sed -n 's/.*release \([0-9]*\.[0-9]*\).*/\1/p')"
    if [[ "$arch" =~ ^[0-9]+$ ]] && ((arch >= 100)) && [[ "$(printf '%s\n' 12.8 "$nvcc_ver" | sort -V | head -1)" != 12.8 ]]; then
      die "GPU arch sm_$arch needs CUDA >= 12.8, found nvcc $nvcc_ver - see docs/setup.md#toolchain"
    fi

    has ccache && launchers+=(-DCMAKE_CUDA_COMPILER_LAUNCHER=ccache)
    if has g++-13; then
      export CC=gcc-13 CXX=g++-13
      backend_flags+=(-DCMAKE_CUDA_HOST_COMPILER="$(command -v g++-13)")
    fi
    backend_flags+=(-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES="$arch" -DGGML_CUDA_FA_ALL_QUANTS=ON)
    log "configuring (CUDA arch $arch)"
    ;;
  vulkan)
    # The Vulkan flash attention takes mixed KV types as is; the shaders are compiled by glslc
    # at build time (vulkan-shaders-gen), which is where the patches from patches/vulkan land.
    backend_flags+=(-DGGML_VULKAN=ON)
    log "configuring (Vulkan)"
    ;;
esac

cmake -B build -S . \
  -DCMAKE_BUILD_TYPE=Release \
  "${backend_flags[@]}" \
  -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=ON -DLLAMA_CURL=OFF \
  "${launchers[@]}" \
  >/dev/null

# One Vulkan shader unit (mul_mm.comp.cpp) peaks at 4.4 GB and the whole -j8 build at 5.7 GB,
# so on a machine with fewer GB than cores x 2 the default -j nproc is what runs it out of
# memory. Measured in docs/setup.md#ram-and-build-memory.
jobs="$BUILD_JOBS"
if [[ -z "$jobs" ]]; then
  cores="$(nproc)"
  avail_mb="$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo)"
  by_mem=$(( avail_mb / 2048 ))
  (( by_mem < 1 )) && by_mem=1
  jobs=$(( by_mem < cores ? by_mem : cores ))
  (( jobs < cores )) && warn "only ${avail_mb} MB free - building with -j$jobs instead of -j$cores"
fi

case "$BACKEND" in
  cuda)   est="10-30 minutes, and nvcc is quiet for long stretches" ;;
  vulkan) est="the shaders alone are ~4 minutes; the whole build 10-20" ;;
esac
log "building llama-server with -j$jobs ($est)"
nice -n "${NICE:-10}" cmake --build build --target llama-server -j "$jobs"

echo "$want" > "$stamp"
"$LLAMA_SERVER" --version 2>&1 | tail -2
