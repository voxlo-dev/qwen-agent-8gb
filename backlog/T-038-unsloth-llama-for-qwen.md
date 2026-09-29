# T-038 — Unsloth's llama.cpp as the tree every Qwen model runs on

- **Summary:** Qwen3.8-Flash runs only on Unsloth's llama.cpp (its banded sparse-attention kernel), and today uses the prebuilt that Unsloth Studio installs. Make Unsloth's tree the default for all Qwen model files, built by `build.sh` from a pinned source like the other two trees, so no model depends on a Studio install, and re-measure Qwen3.6 on it
- **Category:** feature
- **Importance:** medium
- **Effort:** M
- **Depends on:** none. Found in T-039

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

## What

1. **A buildable source.** Unsloth publishes its "mix" source as a release tarball
   (`llama.cpp-source-commit-{sha}.tar.gz`, SHA256 in the prebuilt's `UNSLOTH_PREBUILT_INFO.json`);
   its source commit is not fetchable from `unslothai/llama.cpp` (`not our ref`), and the release
   tag points at the CI tree, not the source. So `build.sh` needs a tarball source next to
   `git fetch`: URL plus SHA256 as the pin, same stamp logic. Or a fetchable commit if Unsloth
   pushes one.
2. **Build it** into `$BONSAI_HOME/llama.cpp-unsloth`, CUDA, and check Qwen3.8-Flash against the
   prebuilt: same buffers, same tg/pp (T-039's numbers).
3. **Qwen3.6 on it**: MTP drafting (`--spec-type draft-mtp`) must still work, then T-034's
   shipped row re-run (131k, `CPU_MOE` 38, `UB` 2048): tg @1k/@43k, pp, VRAM. Within the noise,
   `models/qwen36-35b.env` moves; worse, it stays on mainline and this ticket says why.
4. **Vulkan**: Qwen3.6 is measured on the RX 570. Whether Unsloth's tree builds for Vulkan and runs
   there is part of the decision; if not, Qwen3.6 keeps mainline on `vulkan`.
5. Then `LLAMA_PREBUILT`/`LLAMA_LIB_PATH` go if nothing uses them, and `docs/qwen.md` gets the tree
   decision.
