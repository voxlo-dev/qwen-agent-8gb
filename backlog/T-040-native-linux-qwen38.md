# T-040 — Qwen3.8-Flash on native Linux: every expert in RAM, without a smaller quant

- **Summary:** Under WSL2 the page cache holds ~46 GiB, less than the 55.4 GiB of routed experts in UD-IQ4_XS, so a warm decode still reads ~9 MB per token from the SSD. Native Linux on the same machine should leave ~58-60 GB for the cache and fit them all. Measure it against T-039's WSL2 numbers and Tron session D
- **Category:** spike
- **Importance:** medium
- **Effort:** M (the install is most of it; the measurement ~1 h, the Tron session 1-2 h)
- **Depends on:** a native Linux install on the 4060 Ti machine (dual boot or a second SSD); T-039's numbers as the baseline

## Result so far (2026-09-29)

Measured and written up in [qwen.md](../docs/qwen.md#native-linux): Qwen3.6 30-55 % faster than
under WSL2, Qwen3.8-Flash 18.6-18.9 tok/s and prompts at ~100 with every expert cached, which needs
~58 GB available before start (terminal only; with a browser and editors open it drops to 16-18
with the SSD in the loop). `MODEL_RAM_FULL_MB` and a preflight warning carry it. Runs in
`runs/T-040-native-linux/`. **Left: step 6, Tron session E**, then close. Step 5 (mmproj on the CPU)
is skipped: 0.9 GB is more than the ~2 GiB of margin can spare.

## Why

Measured on 2026-09-29 (`runs/T-039-qwen38-flash/ssd/`): four 256-token turns after a restart
of the server, SSD reads and tok/s per turn, WSL2 at `memory=50GB`:

| Turn | tok/s | read from SSD | major faults |
| --- | --- | --- | --- |
| 1 (cache partly evicted) | 6.5 | 15.6 GB | 118k |
| 2 | 8.1 | 8.3 GB | 70k |
| 3 | 10.1 | 2.8 GB | 26k |
| 4 | 10.3 | 2.3 GB | 22k |

Warm, a turn of ~25 s still reads ~2.3 GB in ~90 random faults per token. The cache peaks at
~46 GiB (RssFile 47.2 GB), the experts are 55.4 GiB. On 64 GB, WSL2 cannot go much higher:
2 GB go to the iGPU and Windows needs ~6.

The alternative inside WSL2 is a smaller quant, and only two fit (read from the GGUF headers,
2026-09-29): `UD-Q2_K_XL` with 42.9 GiB of experts and `UD-IQ3_XXS` with 45.3 GiB, borderline.
Both put the gate/up experts at ~2.3-2.5 bit instead of 3.4. `UD-Q3_K_XL` does not fit (52.0 GiB).
Native Linux keeps the quality and removes the SSD from the loop.

Also expected, not measured: the SSD without the vhdx layer (WSL2 read the file at ~345 MB/s
sequential), so cold loads and warm-up shrink; the full 8 GB under the native driver, and a
failed allocation instead of WDDM's silent spill into shared memory; a little less overhead per
CPU-GPU handoff. The mmproj on the CPU (0.9 GB) would fit next to the experts too.

Expectation, by analogy, not a measurement: Qwen3.6 reads ~0.6 GB of experts per token from RAM
at ~29 tok/s without MTP; Qwen3.8 reads ~1.1 GB, which suggests ~15 tok/s against today's 10.

## What to run

1. **Install**: done on 2026-09-29, Linux Mint 22.3 native (Ubuntu 24.04 base), driver
   595-open, CUDA 12.9 from NVIDIA; what it took is in `docs/dev.md#toolchain` (T-004/5/6 closed).
   Unsloth Studio reinstalled after the driver worked: build 11160, CUDA backend, cu13 runtime at
   the configured `LLAMA_LIB_PATH`. The GGUF is in the HF cache, `model` links it. The display is
   on the iGPU (15 MiB used on the card). Still to record: the BIOS iGPU carve-out; MemTotal is
   61 961 MB against 65 536, so ~3.5 GB are not visible to Linux.
2. **Memory**: MemAvailable at an idle desktop is ~58.4 GB, against 55.4 GiB (59.5 GB) of experts:
   they will not all fit with a desktop running. After a warm run `RssFile`, `RssAnon`, and whether all 55.4 GiB
   of experts stay cached (the SSD read per turn below says it).
3. **Speed**: T-039's `run.sh` (the `full` mode twice, default threads and `-t 7`, interleaved),
   and the SSD script from `runs/T-039-qwen38-flash/ssd/` for reads per turn. The VRAM the driver
   reports free, and whether 131k still fits at the same 7 386 MiB (it should, with more margin).
4. **Cold start**: load time and the first 256-token turn after a reboot, against WSL2's.
5. **If the margin allows**: the mmproj on the CPU (`--mmproj ... --no-mmproj-offload`), one
   screenshot as in `runs/T-039-qwen38-flash/vision/`, and whether decode speed holds with it loaded.
6. **Tron**: session D's setup on native Linux (a session E in the T-035 day folder), against D's
   result: the game ran, rematch worked, small UI bugs.

## Deciding

- **Native is clearly faster** (warm SSD reads near zero, tg well above 10): `docs/qwen.md` says
  Qwen3.8-Flash wants native Linux on a 64 GB machine, and WSL2 is the reduced setup; preflight's
  RAM hint names it. `UD-Q2_K_XL` is not needed.
- **About the same**: the SSD was not the limit; the result goes into `docs/qwen.md`, and a smaller
  quant under WSL2 is not worth its quality either.
