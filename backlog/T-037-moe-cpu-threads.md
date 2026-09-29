# T-037 — Threads for the experts in RAM: one fewer than the cores?

- **Summary:** On the RX 570 box, Qwen3.6 with every expert in RAM generates ~10 % faster with `-t 7` (or 4-6) than with llama.cpp's default of 8 on 8 vCPUs. Measure it on the 4060 Ti machine, where Qwen is bounded by RAM, and decide between a `THREADS` setting, a derived default (cores minus one) or nothing
- **Category:** spike
- **Importance:** low
- **Effort:** S (~30 min on the 4060 Ti machine)
- **Depends on:** none. Found in T-036, see [qwen.md](../docs/qwen.md#on-the-rx-570-vulkan)

## Why

T-036 measured a 256-token turn at 32k, no MTP, on the RX 570 box (Ryzen 7 3700X, 8 vCPUs, no
SMT in the VM): `-t 8` 17.2 and 17.1 tok/s, `-t 7` 18.9 and 19.0, `-t 5` 19.4, `-t 4` 18.8. The
reading is that with the experts on the CPU, all threads busy leave nothing for the thread that
submits the GPU work between the ~41 handoffs of a token. Whether that holds on another CPU, under
WSL2, and with CUDA's cheaper submits is open. A thread count is also a property of the machine,
not of the model or the backend, so it does not belong in a profile as a number.

## What to run

On the 4060 Ti machine, `MODEL=qwen36-35b`, the `dedicated` profile, MTP on. With nothing else
running, the same 256-token chat turn twice per setting, the second counted: no `-t`, then `-t`
at cores minus one, cores minus two, and half the cores (`nproc` and `lscpu` recorded). Pass it
as an extra argument: `bonsai-server -t N`.

## Deciding

- **Minus one wins by more than the noise (~3 %)**: `config.env` gets `: "${THREADS:=}"`, and
  `bonsai-server` passes `-t` when it is set. When `CPU_MOE` is set and `THREADS` is not, it
  derives cores minus one. The reason goes into `docs/qwen.md`.
- **No difference on CUDA**: the finding stays a note for Vulkan in `docs/qwen.md`, and this file is
  deleted.

## A data point from T-039

On the 4060 Ti machine (7800X3D, 8 cores / 16 threads under WSL2, llama.cpp's default 8 threads),
**Qwen3.8-Flash** with every expert in RAM, through `bonsai-server` on CUDA: `-t 7` against the
default in two interleaved pairs, 256-token turns, 9.85 against 9.3 tok/s mean (each pair won
by `-t 7`), pp unchanged. So the effect is not Vulkan's alone. The side study before it measured
~4 % for the same switch. What this ticket still has to run is Qwen3.6 itself, with MTP, where the
GPU's share of each token is larger.
