# Second model: Qwen3.6-35B-A3B

`MODEL=qwen36-35b` serves Qwen3.6-35B-A3B instead of Bonsai. It is a mixture-of-experts model with
35B parameters, 3B of them active per token. The experts live in system RAM; the card holds
attention, the shared expert, the KV cache and the MTP head. **Experimental**: measured for speed
and KV quality, and in one agent session, where it built the study's game in 7 minutes with one
feature broken ([below](#in-an-agent-session)). Whether that ships it as supported is open (T-034).
Bonsai stays the default.

It is also the slot for Qwen 4. If a Qwen 4 35B-A3B ships, it becomes a model file of its own plus
one re-run of the measurement below. The code does not change.

A third, `MODEL=qwen38-flash`, runs the 125B Qwen3.8-Flash-Next with every expert in RAM, at
~10 tok/s on a 64 GB machine: [below](#qwen38-flash-125b-experimental).

## Why a MoE, and why this one

The study behind this repo ([model-comparison.md](model-comparison.md)) found Qwen3.6-35B-A3B the
best agent *by process* on an 8 GB card, but its result was broken. Bonsai answers that with a
dense 27B squeezed into VRAM. A MoE answers it the other way: with 3B active parameters the experts
are cheap to run from RAM, which frees the card for what Bonsai is short of, the window. Its KV
cache is also small. 40 layers, every 4th full attention, 2 KV heads of 256 dims: 10.6 MiB per 1k
tokens at `q8_0`/`q8_0`, against Bonsai's 34.

| Pin | Value |
| --- | --- |
| Model | `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` rev `5bc3e238d916f48a861bac2f8a1990a0e9b7e98d`, `Qwen3.6-35B-A3B-UD-Q4_K_M.gguf`, 22 663 387 424 bytes |
| sha256 | `0b21525e972670ed59e1812e170b27c26355381f0656ecc4e25617ece7dac58b` |
| llama.cpp | mainline, ggml-org `8212c7802455255460ab8e18fc34754560031b34` (2026-09-24), in its own `$BONSAI_HOME/llama.cpp-mainline` |

The `-MTP-` repo carries the same weights as `unsloth/Qwen3.6-35B-A3B-GGUF` plus one MTP layer
(`blk.40.nextn.*`), which the fork ignores and mainline drafts with. Not
`empero-ai/Qwen3.8-35B-A3B-Distill`: despite its name it is a community fine-tune of this same
model.

## What was measured

T-034, 2026-09-24 to 26. Same machine, corpus and prompts as Bonsai's measurement in
[context-window.md](context-window.md). `CPU_MOE` is the number of layers whose experts stay in
RAM (`--n-cpu-moe`, 40 = all); `ub` is `-b`/`-ub`. K is `q8_0` throughout. tg and pp in tok/s,
`@43k` a 42 803-token prompt, `@112k` 112 032. Repeated configs varied < 2 %.

Fork `1a07bfa`:

| ctx | `CPU_MOE` | V | ub | VRAM | tg @1k | tg @43k | pp @43k | tg @112k | pp @112k |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 262 144 | 40 | q4_0 | 4096 | 7 312 | 29.9 | 26.1 | 1 012 | 21.9 | 903 |
| 262 144 | 40 | q8_0 | 2048 | 6 728 | 29.6 | 26.6 | 687 | 22.1 | 623 |
| 262 144 | 36 | q8_0 | 512 | 7 780 | 31.2 | 27.7 | 261 | 23.4 | 246 |
| 131 072 | 35 | q8_0 | 4096 | 7 812 | 32.0 | 28.5 | 1 090 | 23.7 | 962 |
| 131 072 | 33 | q8_0 | 512 | 7 464 | 32.9 | 29.5 | 282 | 24.2 | 265 |
| 65 536 | 33 | q8_0 | 4096 | 7 518 | 33.7 | 29.3 | 1 124 | – | – |
| 65 536 | 31 | q8_0 | 512 | 7 558 | 34.4 | 30.0 | 296 | – | – |

Mainline `8212c78`; `+mtp` is `--spec-type draft-mtp` at the default draft length 3:

| ctx | `CPU_MOE` | V | ub | VRAM | tg @1k | tg @43k | pp @43k | tg @112k | pp @112k |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 131 072 | 36 | q8_0 | 4096 | 7 540 | 29.7 | 27.7 | 1 090 | 23.5 | 947 |
| 262 144 | 40 | q4_0 | 4096 | 7 568 | 29.1 | 25.9 | 1 017 | 22.0 | 899 |
| 262 144 +mtp | 40 | q4_0 | 1024 | 7 396 | 40.9 | 33.0 | 409 | 30.0 | 370 |
| **131 072 +mtp** | **38** | **q8_0** | **2048** | **7 374** | **42.8** | **33.6** | **700** | **29.5** | **611** |
| 65 536 +mtp | 35 | q8_0 | 2048 | 7 380 | 40.7 | 32.2 | 734 | – | – |

The corpus prompts continue C++ code, so what MTP drafts there is not typical output. The fair
number is **natural output**: three chat prompts with thinking, 1 024 tokens each, at the shipped
config with the model card's sampling. That gives **29.0 tok/s without MTP and 38.7-44.7 with it**, with 63-80 % of drafts accepted.

## What it decides

**Mainline with MTP, not the fork.** Without MTP the two builds are equal: at 131k, tg 27.7 against
28.5, with one expert layer fewer on the card for mainline, which needs ~120 MiB more VRAM; pp is
the same. MTP adds 33-54 % on natural output and still 25 % at 112k of context. It costs ~1.66 GB of
VRAM, paid in expert layers and ubatch, which puts pp at ~700 instead of ~1 050. The fork cannot
draft at all. This is also the path a Qwen 4 will need: mainline knows `qwen4exp` (the architecture
of `Qwen/Qwen3.8-Flash-Next`), the fork does not.

**131 072 tokens, `q8_0`/`q8_0`.** With MTP, tg at 43k is 32.2-33.6 across every window from 65k to
262k, so speed does not pick the window. The KV cache does. 262k needs V at `q4_0` to fit, and
Qwen's cache takes that badly at depth ([context-window.md](context-window.md#kv-cache-quality)).
262k also needs ub 1024, and its pp of ~400 turns a compaction that re-reads 100k of kept context
from ~3 minutes into ~4.5.

**`UB` 2048.** The default ubatch of 512 reads prompts at ~250 tok/s with the experts in RAM; 4096
reads them at ~1 050 for 1.3 GB more VRAM and no tg cost. With MTP on the card, 2048 is what fits,
at ~700.

**`CPU_MOE` 38.** One expert layer on the card costs ~470 MiB and buys ~0.8 tok/s. 38 leaves the
shipped config at 7 374 MiB, ~480 below the edge ([context-window.md](context-window.md#the-edge-you-cannot-see)).
37 would sit at ~7 840, too close.

**Thinking in the prompt** behaves as with Bonsai: `--reasoning-preserve` renders every earlier
thinking block, `--no-reasoning-preserve` only those after the last user message. Mainline has the
same switch, so `PRESERVE_THINKING` works unchanged. The template reads `enable_thinking` and
`preserve_thinking`, not `reasoning_effort`, so `EFFORT` is empty for this model.

**Sampling** is Bonsai's: temperature 1.0, top-p 0.95, top-k 20, min-p 0. That is what Qwen used for
its own agent benchmarks (SWE-bench, Terminal-Bench, per the model card), and it keeps sampling out
of the comparison between the two models. The card's 0.6 "for precise coding" is untested here.

**RAM: ~24 GB resident, ~28 GB total.** RSS was 20-23.5 GB across the configs (the model is
mmapped), and available memory fell by another 2-3 GB of page cache during a run. 30.9 GB in WSL2
was enough, with ~25 GB still available. WSL2 sees half the Windows RAM by default, so a 32 GB PC
has to raise `memory=` in `%UserProfile%\.wslconfig`; `preflight` checks for it.

## The profiles

| | `dedicated` | `display` |
| --- | --- | --- |
| ctx | 131 072 | 131 072 |
| `CPU_MOE` / `UB` | 38 / 2048 | 40 / 2048 |
| VRAM | 7 374 MiB, measured | ~6 430 MiB, **by arithmetic**, which leaves ~1 GB for a desktop. Verify once |
| `BUDGET` / `MAX_TOKENS` / `RESERVE_TOKENS` / `KEEP_RECENT_TOKENS` | 16384 / 32000 / 32000 / 24000 | the same |

The budget is a starting point, not a measurement. It follows the rules in
[dev.md](dev.md#context-budget): `RESERVE_TOKENS` >= `BUDGET` + a ~4k tool call + pi's 4096 clamp,
and `KEEP_RECENT_TOKENS` at a real cost of 1.4-2x (~48k) is far below the 99k trigger. `BUDGET` is
twice Bonsai's because the study measured this model at 91 % reasoning share. The
[agent session](#in-an-agent-session) left it where it is: its thinking never came near 16k and
its context never near the trigger, so nothing there asks for a change.

Not tried: draft lengths other than 3, `UB` 1536 or 3072, `f16` for the cache (at 131k it costs
~1.3 GB more, three expert layers or the ubatch).

## In an agent session

T-035's behaviour day, 2026-09-27, on the 4060 Ti with the `dedicated` profile as shipped: the
study's Tron prompt in a plain `bonsai-pi` session, next to two Bonsai sessions on the same prompt
([dev.md](dev.md#context-budget)). Logs: `runs/T-035-bonsai-measured/day/` on that machine.

| | |
| --- | --- |
| Wall time / steps | 36 min / 101; the first "done" after 7 min and 22 steps |
| Output tokens | 60 114 |
| Compactions | none: peak context 76.8k, against the trigger at 99k |
| `length` stops | 0 |
| Largest thinking block | ~1.5k tokens (est.), so `BUDGET` 16384 was never reached |
| tok/s per step, median, incl. prompt | 33.1 |
| Result, judged by hand | **runs**: two browsers log in, host and join, a round plays. The winner is not shown, and rematch does not work |

The second message was a bug report on exactly those two ("The winning player is not displayed
and rematching does not work. Test it and get it to work."), not the study's bare follow-up. The
model wrote 11 tests and fixed two bugs by its own account; rematch still did not work.

The best and the fastest of the day's three sessions, at n = 1. Against the study's run of this
model (OpenCode, 64k, >60 min, three compactions, the canvas does not load) it differs in harness,
window and MTP at once, so it shows what this setup does, not which change did it. Its thinking
stayed short without the budget ever cutting it, unlike Bonsai, which drafts whole
implementations in its thinking when nothing stops it ([dev.md](dev.md#reasoning)).

## On the RX 570 (Vulkan)

The same GGUF on the AMD box (RX 570 8 GB, Polaris, RADV with Mesa 26.1.2 and
`RADV_PERFTEST=nogttspill`, Ryzen 7 3700X, 28 GB in the VM), on mainline `8212c78` built with
`BACKEND=vulkan`. 2026-09-27, one pass; scripts and logs in `runs/T-034-qwen-moe-rx570/`. K and V
are `q8_0`. `chat` is a 256-token coding turn with thinking; `prompt` is T-016's 847-token prompt.

| ctx | `CPU_MOE` | ub | MTP | VRAM | tg short | tg chat | pp 847 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 32 768 | 40 | 512 | – | 2 777 | 17.9 | 17.8 | 77 |
| 32 768 | 34 | 512 | – | 5 632 | 19.5 | 19.4 | 90 |
| 32 768 | 31 | 512 | – | 7 040 | 19.3 | 19.5 | 97 |
| 32 768 | 34 | 512 | on | 6 471 | 27.9 | 23.3 | 90 |
| 32 768 | 34 | 2048 | – | 5 783 | 19.4 | 19.5 | 132 |
| 65 536 | 38 | 2048 | on | 5 645 | 26.4 | 24.1 | 119 |
| 131 072 | 40 | 2048 | on | 5 971 | 24.6 | 25.0 | 116 |

**2.5-3.5x Bonsai on the same card** (7.06 tok/s, 54 tok/s on the prompt). The experts in RAM are
not the limit here: nine expert layers on the card buy 9 %, then nothing. That makes the card
a better home for the window, MTP (+20-30 %, 63-75 % accepted) and the ubatch (prompts +47 %)
than for experts. RSS was 16.7-21.4 GB, and `MemAvailable` stayed above 22 GB, because the
mmapped experts count as page cache.

**At depth, and the repeat slowdown (T-036, fixed).** At 131k with MTP, a 32 781-token prompt was
read at 120 tok/s and then generated at 18.8 tok/s, and **the next request on the same cache at
7.8**, with GTT growing from 1.5 to 2.2 GB while VRAM shrank. An agent session is nothing but
repeats on one cache. The cause is where llama.cpp puts small buffers on a card without Resizable
BAR, and one environment variable removes it. Measured 2026-09-26, T-034's ~25k-token prompt three
times on one cache (`cache_prompt`, 128 tokens, greedy), `CPU_MOE` 40, ub 2048, q8_0/q8_0;
scripts and logs in `runs/T-036-qwen-vulkan-repeat/`:

| Run | ctx | tg 1st | tg 2nd | tg 3rd | VRAM → GTT after the 1st |
| --- | --- | --- | --- | --- | --- |
| MTP | 32k | 21.96 | 16.20 | 16.40 | 251 MiB |
| no MTP | 32k | 16.15 | 16.33 | 16.56 | – |
| MTP, `--ctx-checkpoints 0` | 32k | 23.55 | 23.47 | 23.10 | – (but every request re-reads the prompt: 190 s) |
| MTP, `--cache-ram 0` | 32k | 21.94 | 12.98 | 12.60 | 252 MiB |
| MTP, `GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1` | 32k | 22.06 | 21.87 | 22.32 | – |
| MTP | 131k | 22.34 | 9.89 | 9.94 | 508 MiB |
| MTP, `GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1` | 131k | 22.67 | 22.83 | 22.42 | – |

- **The mechanism.** The RX 570 has 256 MiB of CPU-visible VRAM. Mainline's Vulkan backend asks
  for device-local *and* host-visible memory first ("use rebar if available") and writes such
  buffers with a plain CPU `memcpy` through the mapping. Checkpoints of the hybrid model's
  recurrent state are saved and restored that way, and with MTP on every draft step. Once
  the host keeps writing into VRAM it cannot see, the kernel moves those buffers to GTT, and every
  token reads them across PCIe from then on. Without MTP there are no per-step checkpoints and no
  drop; without checkpoints there is no drop, but no prefix reuse either.
- **The fix.** `GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1` allocates device-local only, and writes go
  through a staging copy. Prefix reuse stays intact (`prompt_n` 4 on each repeat), nothing moves,
  and at 131k the repeat is **2.3x** faster. `bonsai-server` sets it for every `vulkan` run:
  Bonsai measures the same with it (143.81 vs 144.07 ms/token and 53.5 vs 53.7 tok/s on the
  847-token prompt at 64k), since it has no recurrent state to checkpoint. On a card with
  Resizable BAR, all of VRAM is CPU-visible, so this problem should not occur there. It is not
  measured.
- **Through `bonsai-server`**, with the profile below and normal sampling: 21.5, 20.3 and 20.2 tok/s
  at 131k, VRAM and GTT unchanged across the three requests.

**Where a token's time goes.** One generated token at 25k depth, 32k window, no MTP, 62 ms: 35 ms
of it are GPU kernels (`GGML_VK_PERF_LOGGER`; on `8212c78` it trips an assert in
`graph_compute` when an async upload is pending, so it was measured with that assert removed in a
throwaway binary). The rest goes to the experts on the CPU and to the ~41 CPU/GPU handoffs a token
makes with every expert in RAM. Of the GPU time, the attention, SSM and shared-expert weights
(`MUL_MAT_VEC q8_0`) take 35 % at ~165 GB/s, about three quarters of the card's bandwidth.
FlashAttention over the q8_0 cache takes 18 %, and that share grows with depth. The output head
(`q6_K`) takes 7 %, and the Gated DeltaNet kernel 3 %. **No op dominates, so no kernel ticket
follows.** The knobs tried around it:

- **An f16 cache is slower**, not faster: 15.5 against 16.6 tok/s at 25k depth. The attention is
  bandwidth-bound on this card too, so q8_0 stays.
- **One CPU thread fewer is worth ~10 %.** With every expert in RAM, 8 threads on the VM's 8 vCPUs
  compete with the thread that drives the GPU. A 256-token turn without MTP: `-t 8` 17.2 and
  17.1, `-t 7` 18.9 and 19.0, `-t 6` 19.0 and 17.9, `-t 5` 19.4, `-t 4` 18.8. Not a default: it is
  one VM's core count, and the 4060 Ti machine, where Qwen is bounded by RAM, may well behave
  similarly. That is [T-037](../backlog/T-037-moe-cpu-threads.md). Until then, pass `-t` to
  `bonsai-server` by hand.
- **`--load-mode none`**, which llama.cpp suggests for experts in RAM, loses the Vulkan device while
  loading (`ErrorDeviceLost`) on this card. It stays on mmap.

**The Vulkan profile.** `profiles/qwen36-35b/dedicated-vulkan.env` is read before `dedicated.env`
and only sets `CPU_MOE` to 40. More expert layers on the card buy 9 % at most. At 131k with
every expert in RAM, 6 GB of VRAM are in use, leaving ~2 GB free. The window stays at 131k.
`display` already has `CPU_MOE` 40 and needs no override. Any `$PROFILE-$BACKEND.env` works the
same way, and Bonsai has none because its 64k fits both cards.

## Qwen3.8-Flash, 125B (experimental)

`MODEL=qwen38-flash` serves [Qwen3.8-Flash-Next](https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF),
the architecture mainline calls `qwen4exp`: 125B, 512 experts of which 10 are active, 48 layers
(36 Gated DeltaNet, 12 sparse attention with a lightning indexer). A side experiment that matured,
not a candidate for the default: at ~10 tok/s it is a third of Qwen3.6's speed, and it needs a
machine few have. Measured for speed on one machine, never in an agent session (T-039).

**What it needs.** 87.2 GiB of `UD-IQ4_XS` on disk in three parts: routed experts 55.4 GiB, an
n-gram embedding table 26.8 GiB that is read lazily and does not limit speed, the rest ~4.4 GiB on
the card. Every expert stays in RAM (`CPU_MOE` 48), read through the page cache. With 50 GB for
WSL2 (`memory=50GB`, `autoMemoryReclaim=disabled` in `.wslconfig`, a 64 GB PC) the cache holds
~48 GB of the file and decode runs at ~10 tok/s; at 30 GB the SSD is in the loop and it drops to
~6. `preflight` asks for 48 GB. And the card must drive no display: the profile fills it to
7.39 GB, which is within reach only with the monitor on an iGPU (CUDA under WDDM reports 7 063 MiB
free, but ~7.7 GB of buffers fit; past that Windows spills into shared memory without an error, and
speed collapses).

**Unsloth's prebuilt llama.cpp, not mainline.** The sparse attention is the reason. Unsloth's
tree (b11160) runs it with a banded flash-attention kernel over the selected blocks. Mainline
`8212c78`, and master of 2026-09-29, builds a full mask and runs dense flash attention, which
takes VRAM at runtime outside the reserved buffers: with the same 7 386 MiB loaded it died twice at
~2.5k tokens of prefill (`CUDA error: device not ready` in the VMM pool), where the prebuilt ran
to 31k. So the model file points `LLAMA_DIR` at the llama.cpp Unsloth Studio installs, `build`
only checks its build number, and `bonsai-server` puts the Studio venv's CUDA 13 runtime on the
library path, without which the prebuilt runs on the CPU alone and does not say so. T-038 is
making Unsloth's tree one this repo builds, for every Qwen model.

**The flags**, each measured in the side study (2026-09-28, harness and logs in
`runs/T-039-qwen38-flash/side-study/`):

| Flag | Why |
| --- | --- |
| `--n-cpu-moe 48` | every routed expert in RAM; the 4.4 GiB of the rest is what the card holds |
| `--no-repack` | keeps the experts file-backed, so the page cache holds them instead of anonymous memory WSL2 swaps out |
| `--no-op-offload` | prompt processing on the CPU instead of copying 55 GB of experts over PCIe per ubatch: less VRAM, faster on short prompts. With op-offload at ub 2048 a 5k prompt reads at 58 tok/s, but that ubatch does not fit next to 131k |
| `-cram 0`, `-ctxcp 4` | llama.cpp's defaults (8 GB of prompt cache, 32 checkpoints) sit in the same RAM as the experts |
| no MTP | the shared-Q8_0 head gives +0-5 % once the experts are cached, costs ~1.1 GB of VRAM, and ran the card out at 64k |
| `EFFORT` medium | unlike Qwen3.6, this template reads `reasoning_effort` (default `xhigh`); at ~10 tok/s thinking is the expensive part |

**The window.** The indexer's compute buffer is ~13 B x context x ubatch, and that, not the KV
cache, bounds it. 131k at `q8_0`/`q8_0` and ub 512 is 7 386 MiB. 262k fits with `q4_0`/`q4_0` and ub
256 (7.56 GB, the same tg, prompts at ~29 tok/s): `CTX=262144 KV_K=q4_0 KV_V=q4_0 UB=256
bonsai-server`. KV quality at `q4_0` is not measured for this model.

**Measured through `bonsai-server`** (T-039, 2026-09-29, prebuilt b11160, `dedicated`, 50 GB WSL2):

| Threads | tg, 256-token turns (2 x 3) | pp, 5 064-token prompt | a chat turn with thinking |
| --- | --- | --- | --- |
| llama.cpp's default (8 of 16) | 8.9-9.8, mean 9.3 | 36.3, 37.0 | 9.9, 9.6 |
| `-t 7` | 9.7-10.1, mean 9.85 | 35.6, 36.9 | 10.4 |

Two interleaved pairs, since the page cache warms across runs. `-t 7` won both by ~6 %, which is
T-037's question answered on this CPU for this model; until T-037 decides, pass it by hand:
`bonsai-server -t 7`. The chat turns ended with `stop`, their thinking in `reasoning_content`,
300-570 tokens for a short bash function at `EFFORT` medium. RSS after a run: ~48 GB of the file
in the page cache, ~0.2 GB anonymous.

The side study measured 8.3 tok/s at 31k of context and 45.6 tok/s reading a 31k prompt, on the
same flags.

| | `dedicated` | `display` |
| --- | --- | --- |
| ctx / KV / `UB` | 131 072 / `q8_0` / 512 | 65 536 / `q8_0` / 512 |
| VRAM (buffers) | 7 386 MiB, measured | 6 052 MiB, measured without a desktop on the card, which leaves ~1.6 GB for one |
| `BUDGET` / `MAX_TOKENS` / `RESERVE_TOKENS` / `KEEP_RECENT_TOKENS` | 8192 / 32000 / 32000 / 24000 | 8192 / 16000 / 16000 / 12000 |

The budgets follow [dev.md](dev.md#context-budget) and are not measured in a session. `BUDGET` is
Bonsai's, not Qwen3.6's 16k: 8k of thinking already takes ~14 minutes here. The cost that will
decide whether this is usable as an agent is the prompt: pi's first turn and every compaction are
read at ~36 tok/s, so a compaction that keeps 24k takes ~11 minutes.

## When Qwen 4 lands

`models/qwen4-35b.env` with its pin and a mainline commit that knows its architecture,
`profiles/qwen4-35b/` copied from this one, then the grid above re-run with `M=` and `SERVER=`
changed, the KV quality test, and one agent session. If its KV geometry differs, the window moves.
