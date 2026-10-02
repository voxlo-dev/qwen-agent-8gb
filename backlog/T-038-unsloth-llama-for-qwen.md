# T-038 — Unsloth's llama.cpp as the tree every Qwen model runs on

- **Summary:** Qwen3.8-Flash runs only on Unsloth's llama.cpp (its banded sparse-attention kernel). `build` now compiles it from the pinned release tarball, and `bonsai-studio` opens any model in Unsloth Studio on this repo's build. Left, all on the card: the built tree against the prebuilt, Qwen3.6 on it, then the prebuilt support goes
- **Category:** feature
- **Importance:** medium
- **Effort:** M
- **Depends on:** none. Found in T-039 (closed; the model is in [qwen.md](../docs/qwen.md#qwen38-flash-125b-experimental))

## Why

On 2026-09-29, Qwen3.8-Flash-Next at the side study's exact config (131k, `q8_0`/`q8_0`, ub 512,
every expert in RAM, 7 386 MiB of buffers) died twice on mainline `8212c78` with `CUDA error:
device not ready` in the VMM pool (`cuMemSetAccess`), at ~2.5k tokens of prefill. Unsloth's
prebuilt b11160 ran the same buffers to 31k of depth. The difference is in the tree: Unsloth's has
`GGML_OP_FLASH_ATTN_EXT_BANDED` for the sparse attention, mainline (8212c78 and master of the
same day) builds a full mask and runs dense flash attention, which needs VRAM at runtime the
profile leaves no room for. Logs: `runs/T-039-qwen38-flash/logs/mainline-crash/`.

The user's decision (2026-09-29): use the prebuilt now, and move Unsloth in as the default tree for
all Qwen models in the long run.

The prebuilt is the weak part: `build` cannot reproduce it, it needs the Studio venv's CUDA 13
runtime on the library path (without it, it runs on the CPU and says nothing), and the pin is only
a build number that `build` warns on.

## Done (2026-10-02)

- **A buildable source.** `build.sh` takes `LLAMA_TARBALL` + `LLAMA_TARBALL_SHA256` next to the
  git path: download, checksum, then everything but `build/` replaced, so the tree is as clean as
  a forced checkout. It refuses a mismatching checksum and a non-empty directory it did not unpack
  (both tried). `models/qwen38-flash.env` pins the tarball of b11160 (`a3c12db`, sha256 from the
  prebuilt's `UNSLOTH_PREBUILT_INFO.json`, matched on download).
- **Built** into `$BONSAI_HOME/llama.cpp-unsloth`, CUDA, `sm_89`, static like the other trees,
  against CUDA 12.9: `version: 0.5.0-dev (build 11160, commit a3c12db9d)`. A second `build` says
  "already built". `CUDA_ARCH` is new, to build where `nvidia-smi` sees no card (the agent sandbox).
  Log: `runs/T-038-unsloth-tree/build.log`.
- **On the CPU** (sandbox, no GPU) the build runs Qwen3.8-Flash and answers correctly through
  Unsloth Studio, 6.2 tok/s.
- **Bonus: `bin/bonsai-studio`**, the same model and flags in Unsloth Studio, with
  `scripts/server-flags.sh` shared by both launchers ([dev.md](../docs/dev.md#unsloth-studio)).
  `bonsai-server`'s command line has the same flags for all 12 model/profile/backend
  combinations, in long spellings and with `--parallel 1` moved, checked with a stub server.

## What is left, all on the card

The agent sandbox has no GPU; a new binary reaches it only once it is listed in
`sandbox.excludedCommands` (and its `build/bin` in `denyWrite`, like the other two trees).

1. **Qwen3.8-Flash on the built tree against the prebuilt**: the T-040 `full` run, same buffers
   (7 386 MiB), tg and pp against [Native Linux](../docs/qwen.md#native-linux) (18.6-18.9, pp
   ~100). Within the noise: `LLAMA_PREBUILT`, `LLAMA_BUILD`, `LLAMA_LIB_PATH` and their branches
   in `build.sh`, `preflight.sh`, `server-flags.sh` and `config.env` go, and `~/.local/bin/qwen38-llama-server`
   is no longer needed.
2. **Qwen3.6 on it**: MTP drafting (`--spec-type draft-mtp`) must still work, then the shipped
   row of [qwen.md](../docs/qwen.md#native-linux) re-run natively (131k, `CPU_MOE` 38, `UB` 2048):
   tg @1k/@43k, pp, VRAM. Within the noise, `models/qwen36-35b.env` moves to the Unsloth tree on
   `cuda`; worse, it stays on mainline and this ticket says why.
3. **Vulkan**: whether Unsloth's tree builds for Vulkan and runs on the RX 570. Until measured,
   Qwen3.6 keeps mainline on `vulkan` (the model file can choose per `BACKEND`).
4. **`bonsai-studio` with the card**: VRAM and tg against `bonsai-server` for Qwen3.6 and Bonsai.
   Studio adds `--slot-save-path`, `--metrics` and its own system prompt; a difference beyond the
   noise goes into dev.md.
5. `docs/qwen.md` gets the tree decision; this file is deleted.
