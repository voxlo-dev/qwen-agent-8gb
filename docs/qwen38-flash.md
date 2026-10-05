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
~6. `preflight` asks for 48 GB. On native Linux all 55.4 GiB fit, at ~19 tok/s, once ~58 GB are
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
evicted shortly before it is needed again. Hence `MODEL_RAM_FULL_MB=58000` in the model file, and a
preflight warning below it. Not tried: the BIOS carve-out at 512 MB, which would give 1.5 GiB of
margin, and `UD-Q3_K_XL` (experts 52.0 GiB), which is no longer needed.

## In an agent session

Three Tron sessions ([agent-sessions.md](agent-sessions.md)): D (2026-09-29, under WSL2) ended in
54 minutes with a game whose rematch works; E and ES (T-046, 2026-10-03/04, native) did not end
inside 90 minutes, both building sound, fonts and test setups of their own. ES ran with the Sharp
chat template and ran clearly better on process (ended on its own, 89 steps against 198), one pair
only, so it is not wired yet and T-050 validates it: the pinned template and its render
check against Flash's own (Sharp makes the same two changes as on Bonsai; Flash's own template
renders what pi sends byte for byte like Bonsai's) are in `runs/T-041-tron-day-2/`.
