# T-048 — Vision on the CPU: screenshots for the agent, at the smallest RAM cost

- **Summary:** An opt-in vision setting for the Qwen models (Bonsai's projector exists too): the multimodal projector loaded with `--no-mmproj-offload`, so it stays on the CPU and costs no VRAM, with the image tokens capped. The encoder may be slow, it runs rarely; what matters is that the profile's VRAM and the window are untouched and the RAM cost is known. pi then reads the screenshots its e2e tests take
- **Category:** feature
- **Importance:** medium
- **Effort:** M (one setting through config, server flags and pi's `models.json`; a measurement per model)
- **Depends on:** none. Not part of T-042: that one needs a monitor, this one does not

## Why

In B2 ([agent-sessions.md](../docs/agent-sessions.md#b2-qwen36)) Qwen3.6 wrote a Playwright test,
saved screenshots (`/tmp/tron-game.png`, `/tmp/tron-over.png`, …) and tried to look at them: it
piped one through `xxd` and called `read` on another. The server serves text only, so what a screenshot shows
never reached the model. A browser test whose pictures the model can see checks the canvas, which
no DOM assertion does.

## What is there

- **Projectors**, next to the pinned GGUFs: `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` (same revision)
  `mmproj-F16.gguf` 899 MB, `mmproj-BF16.gguf` 903 MB; `unsloth/Qwen3.8-Flash-Next-GGUF`
  `mmproj-F16.gguf` 904 MB; `prism-ml/Ternary-Bonsai-2-27B-gguf` `mmproj-Q8_0.gguf` 629 MB and BF16
  931 MB. No quantized projector for the Qwen models.
- **llama-server** (fork and Unsloth tree): `--mmproj FILE`, `--no-mmproj-offload` (projector on
  the CPU), `--image-max-tokens N` / `--image-min-tokens N` for dynamic-resolution models.
- **pi**: `"input": ["text", "image"]` per model in `models.json`; its `read` tool then returns an
  image to the model, and `images.autoResize` caps images at 2000x2000 before they are sent.
- `qwen-studio` passes `--no-mmproj` today because no profile budgets a projector
  ([agent.md](../docs/agent.md#unsloth-studio)); with this setting it can pass the same file.

## What

1. **Setting**: `VISION=1` (default off) in `config.env`; per model `MMPROJ_FILE` and its sha256 in
   `models/*.env`, fetched by `install.sh model` only when `VISION` is on. `server-flags.sh` adds
   `--mmproj … --no-mmproj-offload --image-max-tokens $IMAGE_MAX_TOKENS`; `pi.sh` writes
   `"input": ["text", "image"]` for the model. Long spellings, for Studio's parser.
2. **Measure per model** (Qwen3.6 first, then Flash, Bonsai last), on the shipped profile:
   - VRAM with and without: must be equal to the MiB (the point of `--no-mmproj-offload`; check
     that no compute buffer for the encoder lands on the card anyway).
   - RAM: RSS and `MemAvailable` with the projector loaded, idle and while encoding. For Flash
     this comes out of the ~58 GB that keep the experts cached, so the number decides whether
     `MODEL_RAM_FULL_MB` moves.
   - Time to encode one 1280x800 screenshot on the CPU, and the tokens it becomes, at two or three
     `IMAGE_MAX_TOKENS` values; then whether the model reads it correctly (the game's state, a
     winner text). Pick the smallest cap that still reads a game screen.
   - The window: image tokens count against `CTX` and stay in the history until a compaction, so
     a few screenshots cost what a large file read costs. State it next to the budget.
3. **F16 against BF16** on the CPU: whichever is faster there, at the same answer.
4. Docs: a `## Vision` section per model file, the setting in the README.

## Done when

`VISION=1 ./install.sh model pi` fetches the projector and writes the image input; `qwen-server`
starts with it at the same VRAM; a `qwen-pi -p` that reads a PNG describes it; the numbers above
are in the model files. Off by default.
