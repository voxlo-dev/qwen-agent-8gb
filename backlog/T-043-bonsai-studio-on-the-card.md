# T-043 — `bonsai-studio` on the card: VRAM and speed against `bonsai-server`

- **Summary:** `bonsai-studio` was verified headless on the CPU only. Run Qwen3.6 and Bonsai through it once with the GPU and compare VRAM and tg with `bonsai-server`; Studio adds `--slot-save-path`, `--metrics`, its own system prompt and, for Bonsai, `--ctx-checkpoints 21`
- **Category:** chore
- **Importance:** low
- **Effort:** S (~20 min, from your own shell)
- **Depends on:** none. Found in T-038 (closed)

## Why

The agent sandbox has no GPU, and Studio's llama-server is Studio's child, so an agent can only
run it on the CPU. There every flag of the profile reached the command line and the models
answered ([agent.md](../docs/agent.md#unsloth-studio)). Whether Studio's additions cost VRAM or speed
on the 8 GB card is unknown: at 131k Qwen3.6 has ~900 MiB left, Bonsai at 64k ~440.

## What

From your own shell, nothing else on the card:

1. `MODEL=qwen36-35b bonsai-studio`, then in Studio's chat (`ssh -L 8888:127.0.0.1:8888`) one
   question with a few hundred tokens of answer. `nvidia-smi` after the load and after the answer;
   the tok/s Studio's log prints (`engine_stats`, or the llama-server log under
   `~/.unsloth/studio/logs/llama-server/`).
2. The same with `MODEL=bonsai`.
3. Against `bonsai-server`: Qwen3.6 7 278 MiB and 52-65 tok/s
   ([qwen36.md](../docs/qwen36.md#native-linux)), Bonsai 36.6 tok/s.

Within ~100 MiB and the noise: dev.md says so and this file is deleted. More VRAM: name the flag
that costs it and override it in `bonsai-studio`.
