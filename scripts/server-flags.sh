# SPDX-License-Identifier: MIT
# The llama-server flags of the model and profile config.env selected, for the two launchers that
# start one: bin/bonsai-server directly, bin/bonsai-studio through Unsloth Studio. Sourced after
# config.env. Exports the environment the server needs, and sets LOAD_FLAGS (placement, cache,
# reasoning, the model file's SERVER_ARGS) and the sampling defaults. The model path, the window,
# where it listens, the slot count and the drafting stay with each launcher, because Studio takes
# those as options of its own. Rationale: docs/dev.md.

if [[ "$BACKEND" == vulkan ]]; then
  # RADV puts buffers in GTT although VRAM is free; this keeps the compute buffer in VRAM,
  # worth 1.22x on this model. Needs Mesa >= 25.2, silently ignored below.
  # See docs/dev.md#other-gpu-backends.
  export RADV_PERFTEST="${RADV_PERFTEST:-nogttspill}"
  # Without Resizable BAR only 256 MiB of VRAM are CPU-visible, and llama.cpp puts buffers there
  # that the host then writes directly: Qwen's checkpoint restores moved them to GTT, 2.3x slower
  # from the second request on. Off, writes go through a staging copy; Bonsai measures the same.
  # See docs/qwen.md#on-the-rx-570-vulkan.
  export GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM="${GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM:-1}"
fi

# Long spellings throughout: Studio's command line parser reads a short cluster like -ctxcp as
# options of its own (-p is its port), so only long ones pass through it intact.
LOAD_FLAGS=(--n-gpu-layers 99 --fit off --flash-attn on)
# A MoE model keeps the experts of CPU_MOE layers in RAM, and reads prompts at ~250 tok/s with
# the default ubatch of 512 against ~1 050 at 4096. Both set by its profile. See docs/qwen.md.
if [[ -n "$CPU_MOE" ]]; then LOAD_FLAGS+=(--n-cpu-moe "$CPU_MOE"); fi
if [[ -n "$UB" ]]; then LOAD_FLAGS+=(--batch-size "$UB" --ubatch-size "$UB"); fi
LOAD_FLAGS+=(--cache-type-k "$KV_K" --cache-type-v "$KV_V" --no-context-shift --jinja --reasoning on)
if [[ -n "$EFFORT" ]]; then LOAD_FLAGS+=(--reasoning-effort "$EFFORT"); fi
LOAD_FLAGS+=(--reasoning-budget "$BUDGET" --reasoning-budget-message "$BUDGET_MSG")
if [[ "$PRESERVE_THINKING" == "true" ]]; then
  LOAD_FLAGS+=(--reasoning-preserve)
else
  LOAD_FLAGS+=(--no-reasoning-preserve)
fi
if [[ -n "$SERVER_ARGS" ]]; then read -ra _extra <<<"$SERVER_ARGS"; LOAD_FLAGS+=("${_extra[@]}"); fi

# Bonsai's recommended sampling, kept for Qwen too: it is what Qwen used for its own agent
# benchmarks. See docs/dev.md#sampling.
SAMPLING_TEMP=1.0 SAMPLING_TOP_P=0.95 SAMPLING_TOP_K=20 SAMPLING_MIN_P=0.0
