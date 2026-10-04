# Performance

Where the generation speed comes from, how much of the hardware it already uses, and which
optimizations were tried and rejected. [`dev.md`](dev.md) explains each shipped setting;
this file explains the ceiling above them.

Everything below was measured on the reference machine: RTX 4060 Ti 8 GB, WSL2, the pinned
fork and model, `dedicated` profile (64k context, K `q8_0` / V `q4_0`).

## What the numbers actually are

A single "35 tok/s" hides most of the picture. Decode throughput over 169 turns of a real
localagent run (`slot print_timing` lines in `server.log`):

| | tok/s |
| --- | --- |
| max (short context) | 35.2 |
| p90 | 34.2 |
| **median, real agent use** | **30.6** |
| p10 | 27.3 |
| min (~40k context) | 25.1 |

The headline number is the best case. What an agent session feels like is the median, and
the spread is almost entirely context length: throughput falls monotonically as the window
fills, because the KV cache is re-read on every token.

## The roofline

Decode is memory-bound, not compute-bound. Every generated token reads the full weight set
once: 5,395 MiB = 5.66 GB. The arithmetic around it is trivial by comparison - 27B parameters
at two FLOP each is ~54 GFLOP per token, so 36 tok/s is ~1.9 TFLOP/s against the card's ~22
TFLOPS. That is 9 % of the compute and ~72 % of the bandwidth, which settles which one is the
limit.

Bandwidth available:

| | GB/s |
| --- | --- |
| Spec (128-bit, 18 Gbps GDDR6) | 288 |
| **Actual, measured** (P2 state, 8751 MHz) | **280** |
| Realistically attainable (~90 % of peak) | ~252 |

The card does not run at its rated clock under CUDA load. `nvidia-smi` reports performance
state P2 at 8751 MHz instead of the P0 9001 MHz, which is NVIDIA's standard downclock for
compute workloads, not a fault. `SW Power Cap` also shows as active at the 160 W limit, but
that throttles the core, and the core is not the constraint.

Measured traffic against that ceiling:

| Context | tok/s | Bytes read per token | Effective | of 280 GB/s |
| --- | --- | --- | --- | --- |
| short | 35.2 | 5.71 GB | 201 GB/s | 72 % |
| ~40k | 25.1 | 6.72 GB | 169 GB/s | 60 % |

Against the ~252 GB/s a GDDR6 part actually sustains, the short-context case is **~80 %
utilized**. For a llama.cpp GEMV decode kernel that is normal-to-good. There is no meaningful
headroom left at the short end, and no setting in this repo can create any.

### Where the KV number comes from

The per-token KV traffic follows from the architecture and matches the measured figure, which
is worth recording because it makes the long-context behaviour predictable. `qwen35` has 64
blocks, of which every 4th is full attention - 16 layers, 4 KV heads at 256 dims - while the
rest are Gated DeltaNet with a fixed-size recurrent state that does not grow with context.

So per token: 16 × 4 × 256 = 16,384 elements each for K and V. At `q8_0` (8.5 bit) and `q4_0`
(4.5 bit) that is 17,408 + 9,216 = **26,624 bytes per token**, or 25.4 MiB per 1k - the 26 MiB
in [VRAM budget](bonsai.md#vram-budget).

### The long-context gap

At 40k, KV traffic is 1.07 GB per token, 16 % of the total. If efficiency held at the
short-context 72 %, that would still give ~30 tok/s; the measured value is 25.1. About 13 % is
missing.

It is **not** the flash-attention kernel for mixed cache types, which was the working assumption
here. A same-type `q8_0`/`q8_0` cache gains only 2.7 % at 43k (26.4 against 25.7 tok/s), and
`q4_0`/`q4_0`, with 30 % fewer KV bytes, is *slower* (24.3). So the KV bytes are not the lever in
either direction, and the cause of the gap is open
([context-window.md](context-window.md#bonsai-windows-on-8-gb)). It sits in a kernel, not in
configuration.

## Speculative decoding: tried, rejected

The PrismML fork carries speculative decoding types that need **no draft model and no extra
VRAM** - `ngram-simple`, `ngram-map-k`, `ngram-map-k4v`, `ngram-mod`, `ngram-cache`, selected
with `--spec-type`. Unlike anything else here, these can beat the roofline, because one weight
read is amortized over several accepted tokens.

They do not pay off on this workload. Three independent measurements, each more realistic than
the last, and the result gets worse as the realism goes up.

**1. Synthetic benchmark** (greedy, 400 tokens, `runs/T-017-spec-decoding/`). Two workloads: one
inventing prose and code, one reproducing a file from the prompt with two methods renamed.

| Variant | invent | reproduce | Acceptance | Output identical |
| --- | --- | --- | --- | --- |
| none | 36.2 | 36.0 | - | - |
| `ngram-mod` | 36.0 (1.00x) | **57.0 (1.59x)** | 100 % | yes |
| `ngram-simple` | 35.0 (0.97x) | 60.2 (1.67x) | 100 % | no |
| `ngram-cache` | 31.0 (0.86x) | 22.9 (0.63x) | 11 % | no |
| `ngram-map-k`, `-k4v` | 1.00x | 1.00x | never drafted | yes |

`ngram-mod` looked ideal: no drafting where it cannot help, 1.59x where it can, byte-identical
output, and VRAM equal to the baseline down to the MiB. That conclusion was wrong, because the
"reproduce" workload was a pure copy job - written to suit the mechanism rather than to
resemble the agent.

**2. Practice run** (real pi, no workflow, the T-013 todo-cli task, `runs/T-017-spec-practice/`).
Only **1 of 9 turns drafted at all**, reaching 37.6 tok/s against ~34.4 interpolated for the
baseline at equal context, at 53.5 % acceptance. The other eight cost ~2 %. Net: neutral.

Comparing the two runs directly is invalid - at `temp 1.0` the model did three times as much
work in one run as in the other (10,938 vs 3,414 generated tokens), and the longer run sat at
higher context throughout. Only a context-paired comparison says anything.

**3. Replay benchmark** (the nine real turns re-sent as identical prompts, so config is the only
variable). This is the decisive one:

| Config | `n_match` | `temp 1.0` | `temp 0.7` | Acceptance |
| --- | --- | --- | --- | --- |
| none | - | **35.9** | **35.9** | - |
| `ngram-mod` default | 24 | 35.7 (0.99x) | 35.4 (0.99x) | 0-7 % |
| `ngram-mod` | 12 | 35.0 (0.97x) | 35.1 (0.98x) | 6-11 % |
| `ngram-mod` | 8 | 33.6 (0.94x) | 33.8 (0.94x) | 7-10 % |
| `ngram-map-k4v`, `size_n` 6 | - | 33.8 (0.94x) | 34.3 (0.96x) | 18-20 % |

**No configuration beats the baseline.** Loosening the trigger produces more drafts, not more
accepted ones, so it is strictly slower.

The economics are simple: every drafted token costs verification. At ~10 % acceptance you pay
for nine rejected tokens per useful one, and break-even is somewhere above 50 %. Acceptance was
100 % greedy, 53.5 % in one real turn, and 6-20 % across real turns. The default `n_match=24` is
strict for a good reason - it only fires when a match is nearly certain, which makes the mode
harmless and also pointless.

Why the gap: a real agent turn is mostly thinking and freshly worded prose, where n-gram lookup
finds nothing while verification still runs. pi also edits with targeted replacements rather
than re-emitting whole files, so the verbatim repetition the synthetic benchmark assumed is
rare in practice.

**Temperature is not a speed knob.** Baseline 35.92 at `temp 1.0` vs 35.89 at 0.7 - identical
within noise. Acceptance does not improve reliably either (6→11 % in one config, 10→7 % in
another). The jump to 100 % only appears near `temp 0`, which this model must not run at; see
[Sampling](bonsai.md#sampling).

Caveat for anyone revisiting this: the replay reconstructs prompts up to ~3.1k tokens, while the
real session reached 18k. More context means more material for n-gram matching, so the effect
could be somewhat better there. The practice run *was* at real context and still came out
neutral, so the direction is consistent - but that is the gap to close if the question is
reopened.

### MTP: no head for this GGUF

Multi-token prediction is a different mechanism from n-gram speculation: a trained head drafts
from the model's own hidden state. On Qwen3.6-35B-A3B it adds 33-54 % on natural output
([qwen36.md](qwen36.md#what-it-decides)). For Bonsai it is not available as shipped. The official GGUF
has no MTP block (its tensors end at `blk.63`). The only head is a community one,
`ProCreations/Ternary-Bonsai-2-27B-MTP`, trained against the PQ2_0 packing and shipped inside a
7.66 GB PQ2_0 bundle that does not fit on 8 GB. Using it would take a merged PTQ1_0 file and a fork
pin past PrismML-Eng/llama.cpp#205 (2026-09-21), which made in-file MTP loadable at all. That was
decided against for now (T-035). A separate `-md` sidecar is no way around it: it duplicates the
248k x 5 120 vocabulary, and #205 measured that as a net loss (5.2 against 16.6 tok/s).

## What is left

Nothing on the card. Memory overclocking was the last candidate - decode scales linearly with
bandwidth, so it is the one lever that works regardless of workload - and it was measured on the
reference machine, host-side under Windows because under WSL2 the Windows driver owns the GPU:

| Setting | tok/s | vs. reference |
| --- | --- | --- |
| `nvidia-smi -lmc 9001` (P0 lock) | 35.68 | reference |
| Power limit 160 → 175 W (109 %) | 35.69 | ±0 |
| Memory offset +100 MHz | 35.96 | +0.8 % |
| **Memory offset +200 MHz** | **36.44** | **+2.1 %** |
| Memory offset +300 MHz | 36.28 | +1.7 % |

**+2 %, about 0.76 tok/s.** The gain tracks the clock almost exactly - +2.2 % clock for +2.1 %
throughput - which is the cleanest confirmation in this file that decode is bandwidth-bound and
nothing else. It is also the whole story: this part accepts roughly +200 MHz, not the four-digit
offsets GDDR6 sometimes takes, and a linear law on a small offset gives a small number.

For a host-side setting that has to be re-applied after driver updates and cannot live in this
repo, +2 % is not worth planning around. Leaving it set does no harm.

**The power limit does nothing.** 160 → 175 W moved the number by 0.01 tok/s. The `SW Power Cap`
that shows as active throttles the core, and the core is at 9 % utilization - it was never the
constraint. Locking the memory clock to P0 produced no measurable change either; whether the lock
does not take effect through WSL2 or the 2.8 % simply does not materialize was not separated,
because at this size it does not matter.

Method note for anyone repeating this: the GDDR6 error-replay wall was **never reached**. Above
~+250 MHz Afterburner stops applying the offset, so the dip at +300 is the offset not arriving,
not memory errors. The caution still stands on a board that allows more - error replay degrades
throughput silently instead of crashing, so an offset that looks stable can still be slower, and
every step needs a measurement rather than an absence of crashes.

The other honest answer is that **the setting with the largest effect on wall-clock time is not a
speed setting at all**. A compaction costs a summarization call plus a full prompt reprocess of
~33k tokens, and prompt processing runs at 340-450 tok/s. Keeping the context budget right is
worth more minutes than any decode tuning discussed here - see
[Context budget](agent.md#context-budget).

## Reproducing

The harnesses are kept under `runs/` (gitignored, not versioned):

- `runs/T-017-spec-decoding/run.sh [variant...]` - synthetic benchmark, greedy, output-hash
  checked against the baseline
- `runs/T-017-spec-practice/run.sh <none|ngram-mod>` - full pi run on the T-013 task
- `runs/T-017-spec-practice/replay.py [config...]` - replay of recorded turns, the instrument to
  use for anything this small

Both a roofline figure and an acceptance rate are needed to interpret a result here. tok/s alone
is not comparable across runs, because at `temp 1.0` the model decides how much work to do.
