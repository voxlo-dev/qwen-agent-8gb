# T-039 — Qwen3.8-Flash, 125B with every expert in RAM, as a third experimental model

- **Summary:** `MODEL=qwen38-flash` serves Qwen3.8-Flash-Next (UD-IQ4_XS, 87 GiB) at 9-10 tok/s and a 131k window on the 4060 Ti with 50 GB of WSL2 RAM, on Unsloth's prebuilt llama.cpp. Built and measured for speed; never run as an agent. Left: one agent session, and KV quality at `q4_0` if the 262k option is to be recommended
- **Category:** spike
- **Importance:** low
- **Effort:** S (one session, ~2 h of wall time at this speed)
- **Depends on:** the 4060 Ti machine with `memory=50GB` in `.wslconfig` and the display on the iGPU; T-038 for a tree this repo builds

## Done (2026-09-29)

- A side study on 2026-09-28 found the flags (harness, logs and results copied to
  `runs/T-039-qwen38-flash/side-study/`, the original in `~/.local/share/qwen38-flash-bench/`,
  the launcher it produced in `~/.local/bin/qwen38-flash`).
- Moved into the repo: `models/qwen38-flash.env`, `profiles/qwen38-flash/{dedicated,display}.env`;
  `scripts/model.sh` handles a split GGUF (one checksum per part, all three verified);
  `SERVER_ARGS` for flags no setting covers; `LLAMA_PREBUILT`/`LLAMA_BUILD`/`LLAMA_LIB_PATH` for a
  llama.cpp this repo does not build.
- Mainline `8212c78` died twice at ~2.5k tokens of prefill (VRAM, dense sparse attention), so the
  model runs on Unsloth's prebuilt b11160; T-038 takes it from there.
- Measured through `bonsai-server`: [docs/qwen.md](../docs/qwen.md#qwen38-flash-125b-experimental).
  Run script and logs: `runs/T-039-qwen38-flash/`.

## What to run

1. **One agent session**, the study's Tron prompt in a plain `MODEL=qwen38-flash bonsai-pi`,
   `dedicated`, `-t 7` passed by hand, the same way T-035's behaviour day ran Qwen3.6. Record wall
   time, steps, compactions, the largest thinking block, `length` stops, and whether the result runs.
   Expect it to be long: pi's first prompt and every compaction are read at ~36 tok/s.
   `SERVER_START_TIMEOUT` 300 is enough warm (loads in 9-32 s), not certain cold.
2. **If 262k is to be named as an option**: T-034's KV quality test at `q4_0`/`q4_0` against
   `q8_0`/`q8_0`, since that is what the window costs.

## Deciding

- The session produces something that runs: the model stays in as experimental, with the result
  in `docs/qwen.md`, and this file is deleted.
- It does not, or it takes hours: it stays in as a documented experiment, the budget values get
  whatever the session showed, and this file is deleted.
