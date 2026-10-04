# Bonsai: Ternary-Bonsai-2-27B

`MODEL=bonsai`: a dense 27B in Prism's ternary `PTQ1_0`, every layer on the card, served by
PrismML's llama.cpp fork. The default until T-044 (2026-10-04); now the model for a machine without
RAM to spare, for simple tasks, since its agent sessions on a whole project fell behind Qwen3.6's
([agent-sessions.md](agent-sessions.md)). This file holds what is particular to it: the format, the VRAM
budget, the KV cache, the template's reasoning, sampling, and the Vulkan path. The pi budget
measured on it is in [agent.md](agent.md#context-budget), its windows in
[context-window.md](context-window.md#bonsai-windows-on-8-gb), its speed ceiling in
[performance.md](performance.md), its agent sessions in [agent-sessions.md](agent-sessions.md).

## Model format

The GGUF stores its weights as `PTQ1_0` (ggml type 143), a Prism-specific ternary format: 1.75 bits per weight, with one fp16 scale per 128 weights. Mainline llama.cpp rejects the file at load time:

```
tensor 'output.weight' has invalid ggml type 143. should be in [0, 67)
```

Only the [PrismML fork](https://github.com/PrismML-Eng/llama.cpp) (branch `prism`) has the kernels. `config.env` pins the tested commit. Mainline support is tracked in [ggml-org/llama.cpp#29058](https://github.com/ggml-org/llama.cpp/issues/29058).

Architecture (`qwen35`): 64 blocks, every 4th is full attention (16 layers, 4 KV heads × 256 dims), and the rest are Gated DeltaNet with fixed-size recurrent state. Native context is 262,144 tokens.

## VRAM budget

| Item | MiB |
| --- | --- |
| Model weights on GPU | 5,395 |
| Compute buffer | ~250 |
| KV cache, per 1k tokens, `q8_0`/`q8_0` | 34 |
| KV cache, per 1k tokens, `q8_0`/`q4_0` | 26 |

At 48k context with `q8_0`/`q4_0` the process holds ~7.3 GB of 8 GB. **64k is the default**: measured at 7 747 MiB of 8 188, 36 tok/s at short context and no layer on the CPU - 441 MiB to spare, which is why the GPU must drive no display. Filled with one 60 000-token prompt (T-049, 2026-10-03, headless): read at 396 tok/s, 23.2 tok/s after it, VRAM at 7 758-7 768 MiB throughout, no growth.

**More than 64k only through the cache type**: 96k fits at `q4_0`/`q4_0` (18 MiB per 1k) and reads that depth cleanly, and nothing larger stays on the card. Under WSL2 a window that is too large does not fail to load. It spills into shared memory once the cache fills, and the VRAM reading does not show it. The measurements, and how to test a window at depth, are in [context-window.md](context-window.md). Qwen3.6, `MODEL=qwen36-35b`, has its own budget with the experts in RAM: [qwen36.md](qwen36.md).

**Display on the iGPU.** When the RTX also drives the Windows desktop, the desktop takes 0.5 to 1.2 GB and competes for GPU time. With the monitor on the mainboard (iGPU enabled in BIOS, browsers set to "Power saving" under Windows *Settings → System → Display → Graphics*), generation went from 21 to 34 tok/s in the same browser-based session.

**No `--fit`, forced `-ngl 99`.** llama.cpp's auto-fit keeps a safety margin. On 8 GB that margin pushes 10 to 12 layers to the CPU, and partial offload costs this architecture about 10× decode speed (3–4 tok/s). The fork's memory estimate is accurate. The margin is the problem.

## KV cache

K at `q8_0` and V at `q4_0`, measured against an `f16` cache: 99.66 % same top token at 16k (99.83 % for `q8_0`/`q8_0`), and identical to `f16` on 510 of 512 tokens at 92k. There is no quality case against it, and `q8_0`/`q8_0` is not faster either (+2.7 % at 43k, for 12k less window). It saves ~25 % of the cache compared with `q8_0`/`q8_0`. Qwen3.6's cache is 3-33x more sensitive than Bonsai's and stays at `q8_0`/`q8_0`. Both are in [context-window.md](context-window.md#kv-cache-quality). llama.cpp has no `q6` cache type; `q5_0` is several times slower on the fork (PrismML-Eng/llama.cpp#191). The options are `f16`, `bf16`, `q8_0`, `q5_1`, `q5_0`, `q4_1`, `q4_0` and `iq4_nl`. A quantized V cache requires flash attention (`-fa on`).

## Reasoning

The chat template reads `reasoning_effort` (`low`, `medium`, `xhigh`) and **defaults to `xhigh`**. At `xhigh` it tells the model to "think carefully, validate key assumptions, consider plausible alternatives". At `medium` it adds nothing, and at `low` it asks for brief thinking.

On coding tasks the model drafts entire implementations inside its thinking block before calling any tool. Measured on a full-stack game prompt:

| Setting | Thinking | Answer |
| --- | --- | --- |
| `xhigh`, no budget (in pi) | 24k tokens, hit the output cap | none |
| `low`, no budget | 12k tokens, hit the cap | none |
| `medium`, no budget | 12k tokens, hit the cap | none |
| `medium`, budget 3k | ~2.7k tokens | plan + code |

Budget size shows up in the result, not just in the token count. At 4096 the model produced
a single-file game and claimed test runs it never performed; at 8192, with the same prompt
and the 64k window, it built a server-authoritative game with two integration tests that
work. See the table under [Context budget](agent.md#context-budget).

The effort level barely matters. The hard budget is what works: `--reasoning-budget` cuts thinking after N tokens, and `--reasoning-budget-message` is injected before the end-of-thinking tag to push the model into acting. Each agent turn gets a fresh budget. The message asks for one tool call, not "the files": worded that way, the localagent orchestrator took it as leave to write a test file next to its plan (T-019, Tron). Both are also accepted per request, as `reasoning_budget_tokens` and `reasoning_budget_message` in the body (`tools/server/server-common.cpp` in the fork), falling back to the flags; the localagent workflow uses that to run its agents at `AGENT_BUDGET` while the session keeps `BUDGET`, see [localagent.md](localagent.md#running-it-on-pi).

### Swift-Bonsai-2

[`ukisai/Swift-Bonsai-2-GGUF`](https://huggingface.co/ukisai/Swift-Bonsai-2-GGUF) (Apache-2.0) is
a fine-tune of this GGUF trained to avoid the tokens that start overthinking. It is a drop-in: same
fork and commit, same architecture, a byte-identical chat template, 32 bytes more on disk; at 64k
it read 7 758 MiB of VRAM and 36.6 tok/s, Bonsai's own numbers (revision `a3bdac08`, PTQ1_0, sha256
`de33620b…1ffc6`). The card's "39.8 % fewer thinking tokens" is a GPQA median taken with an earlier
runtime correction, not the merged file; the current PQ2_0 thinks as long as the base on IFBench
and longer on AIME, and the card calls tool use and agent tasks "uneven".

In a Tron session (W, [agent-sessions.md](agent-sessions.md#c2-and-w-bonsai-and-swift-bonsai-2)) the median step thought less
(~110 against ~170 tokens) but the session as a whole did not: ~70k thinking tokens against ~66k,
the largest block the same size, and no working game after 126 minutes. Its template was its own,
embedded in the GGUF and identical to Bonsai's (the repo ships no separate one), but the effort was
this repo's `medium`: UkisAI's `generation_config.json` and benchmarks use `xhigh`. **Not wired**: the pin
stays on Ternary-Bonsai-2.

Do not enable pi's thinking levels for this model (`"reasoning": true` in `models.json`). pi would send levels such as `high` or `minimal`, which the template rejects with an exception. The server sets the level.

## Thinking in the prompt

The chat template renders every earlier thinking block back into the prompt:

```jinja
{%- if preserve_thinking is undefined or preserve_thinking is true or loop.index0 > ns.last_query_index %}
    {{- '<|im_start|>' + message.role + '\n<think>\n' + reasoning_content + '\n</think>\n\n' + content }}
```

pi sends them: its thinking blocks carry `thinkingSignature: "reasoning_content"`, and the
openai-completions provider writes that field back onto each assistant message. In a
2026-09-19 budget session ([agent.md](agent.md#context-budget)), the 29 745-character thinking block from the first turn (~7.4k tokens) rode
along in every later prompt.

`PRESERVE_THINKING=false` passes `--no-reasoning-preserve` (the fork's switch for the
template's `preserve_thinking`), which keeps thinking only for messages after the last user message - the current turn.
Note what that does **not** cover: inside one long agent turn there is no later user
message, so that turn's own thinking is all preserved. It pays off across turns, and after
a compaction, since pi feeds the summary back as a `user` message (`dist/core/messages.js`)
which resets `last_query_index`.

## Sampling

`--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0` is the model card's **thinking-mode** preset,
which is the mode this setup runs (`--reasoning on`, and the whole budget arithmetic depends on
it). The card's second preset - `temperature=0.7, top_p=0.80, presence_penalty=1.5` - belongs to
instruct/non-thinking mode. It is a mode, not a temperature dial: taking the 0.7 alone into
thinking mode mixes two presets and is not what the card recommends.

`--min-p 0.0` has to be passed explicitly. llama.cpp defaults it to 0.05, so leaving it out
silently deviates from the preset; the flag's own help reads `0.0 = disabled`. This was the only
deviation from the model card in the shipped command line.

A temperature change buys no speed: 35.92 tok/s at 1.0 against 35.89 at 0.7, identical within
noise.

Speculative decoding is off. The fork offers draft-model-free n-gram modes via `--spec-type`,
and they were measured in three ways - no configuration beat the baseline on a real agent
workload, and loosening their triggers made it worse. Acceptance runs at 6-20 % where
break-even is above 50 %. The full result, including why a synthetic benchmark showed a
misleading 1.59x, is in [Performance](performance.md#speculative-decoding-tried-rejected).

## Other GPU backends

CUDA is a choice here, not a constraint of the model: the fork carries `PTQ1_0` kernels for
Vulkan, ROCm/HIP, Metal and the CPU. The Vulkan path was built and measured on an AMD RX 570
(Polaris10/gfx803, 8 GiB, RADV) so the choice rests on numbers - first as the fork ships it
(T-010, `runs/T-010-vulkan-rx570/`), then with a rewritten PTQ1_0 decode (T-016,
`runs/T-016-ptq1_0-vulkan-decode/`, patch and logs there).

**It works.** `-DGGML_VULKAN=ON` builds clean, every shader passes `glslc`, the server puts all
layers on the Vulkan device, `q8_0`/`q4_0` KV with `-fa on` is accepted (`fa_kv_ok` lists both
and only requires BF16 to match on both sides), and load takes 8 s. PTQ1_0 has the full pipeline
set - `mul_mat_vec` for generation and the scalar `CREATE_MM` matmul a device without cooperative
matrix takes. coopmat2 is deliberately absent for PTQ1_0 and is NVIDIA-only anyway.

**As shipped it is about 20x too slow; with the T-016 decode about 5x.** At 48k, Mesa 26.1.2,
`RADV_PERFTEST=nogttspill`, clocks `auto`:

| | RX 570, shipped kernel | RX 570, T-016 decode | RTX 4060 Ti / CUDA |
| --- | --- | --- | --- |
| prompt processing (847 tokens) | 36 tok/s | 54 tok/s | 451 tok/s |
| generation | 1.58 tok/s (633 ms/token) | 7.0 tok/s (143 ms/token) | 36 tok/s |

**The kernel was the ceiling, and the decode was the kernel.** `ptq1_0.glsl` as shipped
decoded every weight element on its own: one byte load, a three-way range branch and a loop
of up to four dependent multiply-mask steps (`v = (v*3) & 0xFF`, ~2.5 on average) to reach the
wanted base-3 digit, because PTQ1_0 packs five trits per byte. Per 128-element block that is
128 byte loads and ~320 serial ALU ops where Q4_0 loads one word per four elements and shifts.
The same card runs Qwen2.5-3B `Q4_K_M` at 121 GB/s effective, which for 5.4 GB of weights would
be ~22 tok/s; 1.58 meant the kernel was ~14x worse per byte, i.e. ALU-bound, which is also why
the memory clock never ramped (the DPM governor watches memory traffic and saw none). The
fork's own issue [#185](https://github.com/PrismML-Eng/llama.cpp/issues/185) has this kernel as
committed-untested and slow: 0.7 tok/s on a Radeon 860M, ~9 tok/s on an RX 9070 XT.

The T-016 rewrite replaces the recurrence with a 256-entry table, byte to five trits, generated
from the CPU codec in `ggml-quants.c` so it is bit-exact by construction, held in shared memory
through the same `init_iq_shmem` mechanism the IQ grids use, with each trit stored as a 2-bit
two's-complement field so one `bitfieldExtract` yields the signed value. The block is read
through a `block_ptq1_0_packed32` view (seven 32-bit words), so four consecutive elements
(`mul_mat_vec`) cost one word load and eight (`mul_mm`) cost two. The element-to-byte mapping
lives in one function, `ptq1_0_locate`, used by every consumer. Verified with
`test-backend-ops -b Vulkan0 -p ptq1_0` for `MUL_MAT`, `MUL_MAT_ID`, `GET_ROWS` and `CPY`
against the CPU backend, before and after. What it bought, 16k and 48k identical:

| Path | before | after | Gain |
| --- | --- | --- | --- |
| generation (`mul_mat_vec`) | 632.96 ms/token | 142.56 ms/token | 4.4x |
| prompt, 847 tokens (`mul_mm`) | 36.0 tok/s | 54.0 tok/s | 1.5x |

Two things the numbers say about what is left. The memory clock now ramps on its own (1000 to
1750 MHz during generation, where the shipped kernel sat at 300), so the kernel has become
visible as memory traffic; and 143 ms/token is still ~3x the ~45 ms that Q4_K_M's per-byte
efficiency would allow, so it is not bandwidth-bound yet. The remaining ALU cost is structural:
`mul_mat_vec` hands each thread four consecutive elements, which is one trit position of four
bytes, so every byte is loaded and looked up five times per token. A dedicated PTQ1_0 mat-vec
kernel that keeps all five trits of a loaded word (the way the K-quant `mul_mat_vec_*` shaders
own their block layout) is the next step, and a larger one; the ceiling for it is ~22 tok/s.

**Correction (T-017, 2026-09-24).** T-016 first printed the prompt gain as 3.8 → 54 tok/s,
14x. The 3.8 was the 18-token prompt of the generation request, not a long prompt: T-016 never
measured the shipped kernel on the 847-token one. Measured at the fork's `842b188` (whose
PTQ1_0 `mul_mm` path is unchanged from the pin), the shipped kernel does 36.0 tok/s there, so
the decode is worth 1.5x on prompts. The tables above carry the corrected value; the
generation numbers stand.

**Upstream, [#252](https://github.com/PrismML-Eng/llama.cpp/pull/252) is the generation half
of this, done properly.** The fork's `842b188` release carries an integer-dot mat-vec (#238),
which gfx803 cannot use (`int dot: 0`). #252, open, adds the dedicated PTQ1_0 `mul_mat_vec`
shader described above as the next step. On the RX 570, 16k, same flags as T-016
(`runs/T-017-pr252-rx570/`), all four builds on `842b188`:

| Build | generation | prompt, 847 tokens | `llama-bench` tg128 / pp512 |
| --- | --- | --- | --- |
| `842b188` | 633.4 ms/token | 36.0 tok/s | 1.58 / 42.6 |
| + #252 | 141.6 ms/token | 39.8 tok/s | 7.15 / 42.4 |
| + T-016 patch | 143.9 ms/token | 53.8 tok/s | 6.99 / 59.1 |
| + #252 + T-016 patch | 141.4 ms/token | 53.9 tok/s | 7.15 / 59.1 |

`test-backend-ops -b Vulkan0 -p ptq1_0` passes `MUL_MAT`, `MUL_MAT_ID` and `GET_ROWS` in all
four (140 + 83 + 4). #252 reaches the same generation speed as the T-016 decode, slightly ahead,
and stays at the same ~3x off the ~45 ms roofline, so the remaining cost is not in the trit
decode. What only the T-016 patch still adds is the `mul_mm` loader: +40-50 % on prompts. The two
compose without conflict (the patch needs `git am -3` on `842b188` for context in `types.glsl`).
Polaris has no integer-dot instruction, so the `mul_mat_vecq` route is not available here.

**The environment is worth 1.76x on the shipped kernel, and getting it wrong looks like a kernel
problem.** The first run, on Debian 13's Mesa 25.0.7 with clocks on `auto`, gave 0.94 tok/s.
Three things moved it, measured one at a time at 16k:

| Change | ms/token | Gain |
| --- | --- | --- |
| Mesa 25.0.7, clocks `auto` | 1067.92 | - |
| Mesa 26.1.2 (trixie-backports), same clocks | 771.12 | 1.38x |
| \+ `RADV_PERFTEST=nogttspill` | 632.96 | 1.22x |
| \+ `power_dpm_force_performance_level=high` | 606.09 | 1.04x |

- **The Mesa version matters most, and specifically for this quant.** 25.0.7 to 26.1.2 is 1.38x
  here while the same upgrade moved a Qwen2.5-3B `Q4_K_M` control on the same card by 1.04x
  (60.34 to 62.97 tok/s). Whatever the older RADV did to the PTQ1_0 shaders, it did it to those
  and not to the standard quants.
- **Memory placement costs a lot, for one buffer.** RADV puts buffers in GTT although VRAM is
  free; `nogttspill` moves ~150 MiB back (GTT 473 to 322 MiB) and buys 1.22x. It needs
  **Mesa >= 25.2** and is silently ignored below that, which is why an earlier attempt on 25.0.7
  measured nothing. The ~150 MiB is the `Vulkan0 compute buffer` (150.28 MiB), which every graph
  execution touches - that is why so few bytes are worth so much, and why the rest is not.
  The other direction brackets it: `GGML_VK_PREFER_HOST_MEMORY` puts everything in host memory
  (VRAM 21 MiB, GTT 6170 MiB) and costs 1.92x, 1213.57 ms/token. Note it is checked for
  *presence*, so setting it to `0` still turns it on.
- **The GTT that is left cannot be moved, and would not pay.** 322 MiB at 16k is
  `token_embd.weight` at 265.23 MiB, the `Vulkan_Host compute buffer` at 36.29 MiB and ~17 MiB
  the driver holds with nothing loaded at all - a floor of roughly 53 MiB even in theory. The
  embedding stays on the CPU because the Vulkan backend has no PTQ1_0 path for that buffer type
  (`cannot be used with preferred buffer type Vulkan_Host, using CPU instead`), which is a fork
  change, not a setting. It would buy nothing either: a row lookup reads kilobytes per token, not
  265 MiB. `--no-host` does not move it - GTT and ms/token are unchanged to three digits
  (633.14 vs 633.20).
- **The clocks barely matter once Mesa is current.** With the shipped kernel `pp_dpm_mclk` sits
  at 300 MHz of an available 1750 under load while `sclk` is pinned at its top and
  `gpu_busy_percent` reads 100 %; forcing the performance level raises mclk to 1750 and buys
  1.18x on Mesa 25.0.7 but only 1.04x on 26.1.2. With the T-016 decode it ramps by itself.
- **The context window costs nothing.** 48k and 16k give 633.06 and 632.96 ms/token before,
  142.98 and 142.56 after.

**So: CUDA for interactive use, Vulkan for batch.** 7 tok/s is a fifth of the 4060 Ti and
54 tok/s prompt an eighth: a 4k-token agent prompt costs ~75 s before the first token, a
10k-token agent step ~25 minutes. That is fine for a task handed over and left alone
(`qwen-pi -p`) and not for a conversation, which is why `vulkan` is
supported and not the default. How the setup does it, all of it measured above:

- `BACKEND=vulkan` builds the fork with `GGML_VULKAN=ON` and `patches/vulkan/` applied; the
  pinned `LLAMA_COMMIT` does not carry the decode until upstream takes it (T-017). Same
  binary flags otherwise, same KV types, same `-fa on`.
- `qwen-server` exports `RADV_PERFTEST=nogttspill` (1.22x; needs Mesa >= 25.2, `deps` warns
  below that), and `GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1`. That one is neutral for Bonsai
  (143.81 vs 144.07 ms/token at 64k) and 2.3x on Qwen's repeated requests, whose checkpoint writes
  otherwise push buffers out of the 256 MiB of CPU-visible VRAM
  ([qwen36.md](qwen36.md#on-the-rx-570-vulkan)). Nothing forces the clocks: with the new decode `mclk` ramps by itself, and the
  knob needs root anyway.
- The `dedicated` profile holds as is: 64k measured at 7 434 MiB of 8 192 on the RX 570,
  141.56 ms/token (`runs/T-016-ptq1_0-vulkan-decode/measure-new-64k.out`), so the window
  costs nothing here either and the pi budget is the same arithmetic.
- `token_embd` stays on the CPU (265 MiB in GTT) and there is no Vulkan `mul_mat_vecq`; both
  are fork work, neither is a setting.

Two side findings from the same runs, both harmless: `token_embd.weight` (ptq1_0) "cannot be used
with preferred buffer type Vulkan_Host, using CPU instead", so 265 MiB stays CPU-mapped even at
`-ngl 99`; and only 16 layers carry a KV cache (the rest log as `filtered`), which is why 48k
costs just 1222 MiB - K `q8_0` 799 MiB, V `q4_0` 423 MiB - and why a 48k window fits 8 GB at all.

