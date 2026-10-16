# T-052 — Qwen3.8-Flash on a smaller quant

- **Summary:** Measure UD-IQ3_XXS, then UD-Q2_K_XL, against the pinned UD-IQ4_XS: decode, prompts, KL and tool calls. The only lever left for short decode after T-051
- **Category:** spike
- **Importance:** medium
- **Effort:** M
- **Depends on:** T-051 and T-053 (closed): the b11681 pin and its decode patch are the build either quant runs on

## Why

T-051 split a Flash token into ~31 ms of CPU experts and ~27 ms of the rest, and found the CPU
part linear in the expert bytes read ([performance.md](../docs/performance.md#qwen38-flash-experts-on-the-cpu)).
From the GGUF headers (unsloth/Qwen3.8-Flash-Next-GGUF at the pinned revision):

| quant | routed experts | bytes per token | predicted short decode |
| --- | --- | --- | --- |
| UD-IQ4_XS (pinned) | 55.4 GiB | 1.162 GB | 19.0-19.6 (measured) |
| UD-IQ3_XXS | 45.3 GiB | 0.950 GB | ~22-23 |
| UD-Q2_K_XL | 42.9 GiB | 0.900 GB | ~24 |

The risk is the kernels: the probe kept IQ3_S/IQ4_NL, the smaller files store gate/up as IQ2_S or
IQ2_XS, which may be compute-bound on 8 cores. Both also need 10-13 GB less RAM, which could keep
every expert cached with a desktop open. Quality per quant is unmeasured for this model; Strata's
GSQ files (ISTA-DASLab) are not an option on x86, their Q2_0 runs a scalar fallback.

## What

1. Download UD-IQ3_XXS (~76 GB with the n-gram table), run `runs/T-051-flash-speed/final.sh`'s
   steps headless against UD-IQ4_XS.
2. KL and top-1 agreement against UD-IQ4_XS on a fixed text (`llama-perplexity --kl-divergence`).
3. One Tron session (agent-sessions.md) for the tool calls.
4. UD-Q2_K_XL only if 1-3 hold.

## Done when

The pin either moves, with MODEL_REV, the three checksums, MODEL_DISK_MB, MODEL_RAM_MB and
MODEL_RAM_FULL_MB measured, or the doc says what the smaller quant cost.
