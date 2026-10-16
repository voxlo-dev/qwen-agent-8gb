# Qwen3.8-Flash-Next, 125B

`MODEL=qwen38-flash` serves [Qwen3.8-Flash-Next](https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF),
the architecture mainline calls `qwen4exp`: 125B, 512 experts of which 10 are active, 48 layers
(36 Gated DeltaNet, 12 sparse attention with a lightning indexer). The strongest of the
three models, for a 64 GB machine; not the default, because at ~19 tok/s natively it is under half
of Qwen3.6's speed and needs a machine few have. Tested like the others since T-049 and T-043
(2026-10-03/04): speed, its window filled to the edge, VRAM under `qwen-studio`, and three agent
sessions, the first of which built the only game of its day whose rematch works
([agent-sessions.md](agent-sessions.md#d-qwen38-flash)).

**What it needs.** 87.2 GiB of `UD-IQ4_XS` on disk in three parts: routed experts 55.4 GiB, an
n-gram embedding table 26.8 GiB that is read lazily and does not limit speed, the rest ~4.4 GiB on
the card. Every expert stays in RAM (`CPU_MOE` 48), read through the page cache. With 50 GB for
WSL2 (`memory=50GB`, `autoMemoryReclaim=disabled` in `.wslconfig`, a 64 GB PC) the cache holds
~48 GB of the file and decode runs at ~10 tok/s; at 30 GB the SSD is in the loop and it drops to
~6. `preflight` asks for 48 GB. On native Linux all 55.4 GiB fit, at ~19 tok/s, once ~59 GB are
available before start: [below](#native-linux-every-expert-cached). And the card must drive no display: the profile fills it to
7.39 GB, which is within reach only with the monitor on an iGPU (CUDA under WDDM reports 7 063 MiB
free, but ~7.7 GB of buffers fit; past that Windows spills into shared memory without an error, and
speed collapses).

**Unsloth's llama.cpp, not mainline.** The sparse attention is the reason. Unsloth's tree
(b11160) runs it with a banded flash-attention kernel over the selected blocks. Mainline
`8212c78`, and master of 2026-09-29, builds a full mask and runs dense flash attention, which
takes VRAM at runtime outside the reserved buffers: with the same 7 386 MiB loaded it died twice at
~2.5k tokens of prefill (`CUDA error: device not ready` in the VMM pool), where Unsloth's tree ran
to 31k. The measurements below ran on the prebuilt Unsloth Studio installs, which needs the Studio
venv's CUDA 13 runtime on the library path and runs on the CPU alone, silently, without it. Since
T-038 `build` compiles the same source itself into `llama.cpp-unsloth`: the source commit
`a3c12db` cannot be fetched from Unsloth's repository, so the pin is the release tarball the
prebuilt was built from, with its sha256, and the result reports the same build 11160. Statically
linked against the system's CUDA 12.9 like the other two trees, it needs nothing from Studio,
but CCCL 3.2 instead of the toolkit's (below, *Filled*). The tree is also why this model is CUDA
only: Unsloth's tree was never built or measured on Vulkan, and mainline did not get past 2.5k tokens of prefill.

Measured against the prebuilt on 2026-10-02 (native Linux, headless, the same 131k buffers,
interleaved built, prebuilt, built; `runs/T-038-unsloth-tree/`): VRAM 7 566 against 7 568 MiB,
three 256-token turns at 18.1-18.9 tok/s against 17.8-18.5, the 5k prompt warm at 105-106 against
103. At temperature 0 both wrote the same text token for token. The prebuilt support
(`LLAMA_PREBUILT`, the Studio venv's CUDA runtime on the library path) is gone with it.

**The flags**, each measured in the side study (2026-09-28, harness and logs in
`runs/T-039-qwen38-flash/side-study/`):

| Flag | Why |
| --- | --- |
| `--n-cpu-moe 48` | every routed expert in RAM; the 4.4 GiB of the rest is what the card holds |
| `--no-repack` | keeps the experts file-backed, so the page cache holds them instead of anonymous memory WSL2 swaps out |
| `--no-op-offload` | prompt processing on the CPU instead of copying 55 GB of experts over PCIe per ubatch: less VRAM, faster on short prompts. With op-offload at ub 2048 a 5k prompt reads at 58 tok/s, but that ubatch does not fit next to 131k |
| `--cache-ram 0`, `--ctx-checkpoints 4` | llama.cpp's defaults (8 GB of prompt cache, 32 checkpoints) sit in the same RAM as the experts |
| no MTP | the shared-Q8_0 head gives +0-5 % once the experts are cached, costs ~1.1 GB of VRAM, and ran the card out at 64k |
| `EFFORT` medium | unlike Qwen3.6, this template reads `reasoning_effort` (default `xhigh`); at ~10 tok/s thinking is the expensive part |

**The window.** The indexer's compute buffer is ~13 B x context x ubatch, and that, not the KV
cache, bounds it. 131k at `q8_0`/`q8_0` and ub 512 is 7 386 MiB. 262k fits with `q4_0`/`q4_0` and ub
256 (7.56 GB, the same tg, prompts at ~29 tok/s): `CTX=262144 KV_K=q4_0 KV_V=q4_0 UB=256
qwen-server`. KV quality at `q4_0` is not measured for this model.

**Filled, it needs CCCL 3.2** (T-049, 2026-10-03, `runs/T-049-flash-deep/`). Built against
CUDA 12.9 alone, the server died in both T-046 sessions at ~48k of context, and on a fresh
110k prompt at 19k: `CUDA error: out of memory` in `cuMemCreate`, from `ggml_cuda_op_top_k`. The
indexer picks its blocks with a top-k over [depth x ubatch rows] scores. With CCCL >= 3.2 that is
`cub::DeviceTopK`, row by row; below (12.9 ships 2.8) ggml falls back to a full segmented sort,
with four or five temporaries of that size from the CUDA pool, which grows outside the reserved
buffers and never shrinks. On the card it grew ~11 MiB per 1k of depth at 512 rows, from 7 566 MiB
to the end of the card. An agent's prompts are mostly a few hundred tokens or one, which is why
the sessions got further. The prebuilt is CUDA 13.3 and never took that path; T-038 compared VRAM
at load, where the pool is empty, and the deepest earlier run was 31k.

`LLAMA_CMAKE_ARGS=-DGGML_CUDA_CUB_3DOT2=ON` in the model file: the tree's own switch, which
fetches CCCL v3.2.0 at build time (a git tag, not checksummed) and keeps the system's 12.9. The
same 110k prompt then reads through without error: VRAM flat at 7 592-7 594 MiB from 0 to 110k,
the prompt at 97 tok/s on average, 64 tokens after it at 9.7 tok/s. CUDA 13 is not needed for
it, and would cut the toolkits from apt that the build accepts today. Rebuilt through
`install.sh build` with the setting, the installed binary gave the same: 110k at 97.4 tok/s, 10.0
tok/s after it, VRAM flat at 7 594 MiB.

**Measured through `qwen-server`** (T-039, 2026-09-29, prebuilt b11160, `dedicated`, 50 GB WSL2;
native Linux in [its own section](#native-linux-every-expert-cached)):

| Threads | tg, 256-token turns (2 x 3) | pp, 5 064-token prompt | a chat turn with thinking |
| --- | --- | --- | --- |
| llama.cpp's default (8 of 16) | 8.9-9.8, mean 9.3 | 36.3, 37.0 | 9.9, 9.6 |
| `-t 7` | 9.7-10.1, mean 9.85 | 35.6, 36.9 | 10.4 |

Two interleaved pairs, since the page cache warms across runs. `-t 7` won both by ~6 % under WSL2;
on native Linux the difference is gone, so it is not worth passing there. The chat turns ended with `stop`, their thinking in `reasoning_content`,
300-570 tokens for a short bash function at `EFFORT` medium. RSS after a run: ~48 GB of the file
in the page cache, ~0.2 GB anonymous.

The side study measured 8.3 tok/s at 31k of context and 45.6 tok/s reading a 31k prompt, on the
same flags.

| | `dedicated` | `display` |
| --- | --- | --- |
| ctx / KV / `UB` | 131 072 / `q8_0` / 512 | 65 536 / `q8_0` / 512 |
| VRAM (buffers) | 7 386 MiB, measured | 6 052 MiB, measured without a desktop on the card, which leaves ~1.6 GB for one |
| `BUDGET` / `MAX_TOKENS` / `RESERVE_TOKENS` / `KEEP_RECENT_TOKENS` | 8192 / 32000 / 32000 / 24000 | 8192 / 16000 / 16000 / 12000 |

The budgets follow [agent.md](agent.md#context-budget) and are not measured in a session. `BUDGET` is
Bonsai's, not Qwen3.6's 16k: 8k of thinking already takes ~14 minutes here. The cost that will
decide whether this is usable as an agent is the prompt: pi's first turn and every compaction are
read at ~36 tok/s under WSL2, so a compaction that keeps 24k takes ~11 minutes; ~4 on native
Linux at ~100.

## Native Linux: every expert cached

On the same machine booted into native Linux (T-040, 2026-09-29; the method and the Qwen3.6
numbers are in [qwen36.md](qwen36.md#native-linux)):

| | WSL2 | native |
| --- | --- | --- |
| Qwen3.8-Flash, 256-token turns | 8.9-10.1 | **18.6-18.9** |
| Qwen3.8-Flash, pp of a 5 064-token prompt | 36 | **101-103** |
| Qwen3.8-Flash, load | 28-29 s | 24 s cold, 12-14 s warm |

**Qwen3.8-Flash needs every expert cached, and that is a question of the desktop.** 64 GB leaves
60.5 GiB `MemTotal` with the BIOS giving the iGPU 2 GB. The experts are 55.4 GiB, llama-server's own
memory 0.7 GiB. With a browser, VS Code and a chat app open (3.8 GiB anonymous memory) the page
cache held 51.9 GiB of them, and it cost twice:

| MemAvailable before start | desktop | tg | pp, 5k prompt | SSD read, warm 256-token turn | SSD read, warm 5k prompt |
| --- | --- | --- | --- | --- | --- |
| 56 371 MiB | browser, editors, chat | 16.3-18.0 | 66-73 | 0.9-1.2 GB | 20-28 GB |
| 59 290 MiB | terminal only (1.0 GiB anonymous) | **18.6-18.9** | **101-103** | **0** | **0.02-0.17 GB** |

The prompt is the expensive part: with `--no-op-offload` it runs on the CPU and walks every
expert, and a walk over a set just larger than the cache is the worst case of LRU, every page
evicted shortly before it is needed again. Hence `MODEL_RAM_FULL_MB=59000` in the model file, and a
preflight warning below it: the threshold lies between 58 150 MiB, which did not hold every expert
([Vision](#vision)), and 59 250, which did. Not tried: the BIOS carve-out at 512 MB, which would give 1.5 GiB of
margin, and `UD-Q3_K_XL` (experts 52.0 GiB), which is no longer needed.

## Decode at depth

Decode falls with the depth, ~17 tok/s short to ~10 at 110k, and dense KV explains a fraction of
it. Profiled (T-051, `nsys`, 2026-10-16), the GPU time per token grows from 22.9 ms short to 42.4
at 64k, and three kernels hold the growth:

| kernel, per token at 64k | short | 64k |
| --- | --- | --- |
| flash attention, 12 layers | 0.1 ms | 10.6 ms |
| indexer: block scores expanded to cells (`get_rows`) | 0.1 ms | 4.2 ms |
| indexer: raw keys gathered for pooling (`get_rows`, q8_0) | 0.0 ms | 2.3 ms |

**The sparse attention is dense in cost at decode.** Unsloth's tree turns the indexer's top-k
(2 048 tokens plus the tail block) into a -inf mask over the whole cache. Its CUDA flash attention
can gather the top-k itself, in the MMA kernel, but only for f16 K/V: with a quantized cache that
kernel would convert the whole cache to f16 per call, so a single query takes the vector kernel,
which reads every cell. f16 KV at 64k (the VRAM of q8_0 at 131k) takes the gather with no code,
12.75 tok/s at 64k against 11.67, at half the window.

**The fix is two patches in [`patches/unsloth/`](../patches/unsloth/)**, applied by `build` to the
tree both Qwen models share:

1. `0001` (`qwen4exp.cpp`): at decode on a quantized cache, the top-k cells of K, V and the mask
   row are gathered and attention runs over those, padded to 256. Every other case, prefill
   included, keeps the masked path.
2. `0002` (`ggml-cuda/getrows.cu`): rows shorter than the block share it. The score expansion is
   n_kv rows of one float, which launched one 256-thread block per float. Generic, so Qwen3.6 runs
   it too; `test-backend-ops -o GET_ROWS` 216/216.

**Measured headless** (2026-10-16, `runs/T-051-flash-speed/final.sh`, MemAvailable 60.9 GB,
`dedicated`, 131k `q8_0`/`q8_0`): one corpus prompt grown 32k → 64k → 110k, 128 tokens decoded at
each depth, the same build with and without the patches:

| decode tok/s | short (256-token turns) | 32k | 64k | 110k |
| --- | --- | --- | --- | --- |
| without the patches | 18.7-18.9 | 14.5 | 12.9 | 10.5 |
| **with `0001` + `0002`** | **19.0-19.6** | **17.0** | **16.4** | **14.3** |
| | +3 % | +17 % | +27 % | +36 % |

Prefill unchanged (~98 tok/s at depth, 86-87 on a 5k prompt), VRAM unchanged (7 602 MiB peak in
both), Qwen3.6 unchanged (57.0 / 64.3 / 54.6 against 57.1 / 64.4 / 54.6 tok/s). The SSD read
0-0.3 GB per decode step.

The profile behind the two patches, with a desktop open (the absolutes ~1.5 tok/s low and ±1):
GPU time per token at 64k 42.4 ms without them, 33.5 with `0001`, 28.5 with both.

The output: greedy decode is not deterministic run to run on this tree even without the patches
(three runs, two variants of a ~5k-token summary); the patched runs give the same two, and at
depth both builds continue the code plausibly and part after 150-400 characters. No KL measured.
What is left at depth is the indexer pooling every block's keys again per token, ~2-3 ms at 64k:
a cache of pooled keys, not a launch fix.

## Strata, a dedicated engine

[Strata](https://github.com/Niko1221/Strata) (MIT, 0.1.44.1 read on 2026-10-16) is an inference
engine written for this model alone, with its own CUDA/HIP/Metal kernels and an OpenAI-compatible
server. On cards of 12 GB and more it is far faster than llama.cpp: 53-94 tok/s on an RTX 5070
with its own 2-3-bit quants, by its README. Its README asks for 12 GB of VRAM; its INSTALL says 8 GB runs, slowly. Read for T-051, to see what of it
this setup could use. What it does, from its docs and source:

- **A VRAM expert cache.** Experts ranked by an expert profile, swapped while a chat runs; what
  misses is copied over PCIe or computed on the CPU. On this card 853 slots, 3.5 % of the 24 576
  experts, served 20 and 55 % of the lookups in the two requests below.
- **A page-locked RAM tier** (`--resident-budget-gib`). Pinning 37 GiB released the model's page
  cache first. A 64 GB report of its own found the warm page cache faster than the
  pinned budget for an IQ4_XS (5060 Ti 16 GB, `bench/results/2026-10-01-iq4xs-64gb`: 37.5-39 against
26.7-27.5 tok/s), which is this repo's design.
- **The route tail skip, on by default on CUDA since 0.1.42.** A missed expert that every token of
  a verify window ranks 7-10 of its 10 is not computed, and the others are not renormalised. Its
  own measurement for Unsloth's UD-Q4_K_XL: KL against Q8_0 from 0.056 to 0.086 with every expert
  in RAM, 0.053 to 0.115 in the budget mode, for +4-10 % and +26-67 % decode (`docs/QUANTS.md`).
  That is about a quant step: UD-IQ4_XS without it is 0.101. `STRATA_ROUTE_TAIL_SKIP=0` turns it off.
- **MTP drafting**, the source of most of its speed on bigger cards. For Unsloth's files on cards
  up to 9.5 GB its setup gives up, in this order, the KV in 8 bits, the window (8 192, 6 144,
  4 608) and the draft layer (~0.8 GB), to leave room for the cache (`setup.py`,
  `unsloth_small_card_plan`), and prints that UD files are very slow on such a card.
- **Its own quants** (ISTA-DASLab's GSQ GGUFs, 2.3-3.3 bpw) with kernels for them. llama.cpp can
  load them, but their Q2_0 has no x86 SIMD path (`ggml-cpu/arch-fallback.h`), so the CPU experts
  would run scalar: not an option for this repo.

**Measured on this machine** (2026-10-14, UD-IQ4_XS, the config its setup wrote: `--max-context
8192`, `--resident-budget-gib 37`, no draft layer, tail skip on): two requests, 8 and 37 tokens
out, 14.3 and 19.4 tok/s, 353 MiB of VRAM left, and on the first request 67 GB read from the SSD
for 2.8 GB of experts. Too short to compare, and with the tail skip on not the same computation.
This repo on the same file and card: 19.0-19.6 tok/s on 256-token turns, exact top-10 routing, at
131k, 14.3 at 110k of depth.

**As a server for pi** it would need two changes: a request whose prompt plus `max_tokens`
exceeds the window gets a 400 unless `"fit_max_tokens": true` (pi sends 32 000, so at 8k every
request fails), and the window itself. It also brings its own chat template, which pi's tool calls
were not checked against.

**The precedent that matters**: an RTX PRO 2000 Laptop 8 GB (Windows, Core Ultra 9 285H, 64 GB)
ran Strata's GSQ IQ3_XXS at 262k with q4_0 KV streamed from RAM and MTP, ~29 tok/s over 2 717
agent requests (`docs/PREFILL_HEAD_ALIAS.md`). That is faster than this repo, on a quant whose KL
against Q8_0 Strata measures at 0.202 against UD-IQ4_XS's 0.101, with the tail skip, and on
another machine.

**What came of it**: nothing transfers by flag. Strata's per-expert cache, KV streaming and
prefetch have no llama.cpp counterpart; `-ot` and `--n-cpu-moe` move whole layers, and one layer
of experts (~1.15 GiB) does not fit beside a 131k window. The closest analogue of the tail skip,
`--override-kv qwen4exp.expert_used_count=int:7`, is cruder (top-7 for every token, renormalised)
and was used only as a probe ([performance.md](performance.md#qwen38-flash-experts-on-the-cpu)).
Reading it pointed at the depth loss, which is where the patches above came from.

## Vision

`mmproj-F16.gguf` from the pinned revision, on the CPU like for Qwen3.6
([agent.md](agent.md#vision)); measured on 2026-10-05 (T-048, native, headless, the shipped 131k
profile, 59 250 MiB available before start, `runs/T-048-vision/`). VRAM 7 592 MiB after requests
with and without it. The cost is speed: the projector's ~0.85 GB idle plus its compute buffer
come out of the page cache the experts live in. Three warm ~1.1k-token prompts, 256 tokens each:

| | tg | pp |
| --- | --- | --- |
| without the projector | 18.6-18.7 | 93-95 |
| with it | 17.4-17.6 | 78-85 |

So 59 250 MiB hold every expert and the same less ~1.1 GB do not: the full-cache threshold sits
between 58 150 and 59 250 MiB, hence `MODEL_RAM_FULL_MB=59000`. `preflight`
adds `MMPROJ_RAM_MB` (1 100) to it with `VISION` on, so Flash sees at full speed from ~60 GB
available; below that vision costs ~6 % of decode and ~12 % of prompt speed, until the BIOS
carve-out above gives the margin back.

At cap 512 it read both screens' state, the names, `GO!`, `DOUBLE KO!` and the buttons, placed the
trails one above the other where they run side by side, and got one footer word wrong. Encode
10.3 s; its own pass over the 476 image tokens 6-9 s more, on the CPU like any prompt.

## In an agent session

Three Tron sessions ([agent-sessions.md](agent-sessions.md)): D (2026-09-29, under WSL2) ended in
54 minutes with a game whose rematch works; E and ES (T-046, 2026-10-03/04, native) did not end
inside 90 minutes, both building sound, fonts and test setups of their own. ES ran with the Sharp
chat template and ran clearly better on process (ended on its own, 89 steps against 198), one pair
only, so it is not wired yet and T-050 validates it: the pinned template and its render
check against Flash's own (Sharp makes the same two changes as on Bonsai; Flash's own template
renders what pi sends byte for byte like Bonsai's) are in `runs/T-041-tron-day-2/`.
