# Context window and KV cache

How large a window fits on an 8 GB card, what the KV cache types cost in quality, and where the
edge is. Both models were measured the same way, on the same corpus, so their numbers sit in one
table: Ternary-Bonsai-2-27B on the pinned fork (T-035), and Qwen3.6-35B-A3B with its experts in
RAM on mainline llama.cpp (T-034, see [qwen36.md](qwen36.md)). Everything below is from the reference
machine: RTX 4060 Ti 8 GB, WSL2 with 30.9 GB RAM, 2026-09-24 to 26. Scripts and logs are in
`runs/T-034-qwen-moe/` and `runs/T-035-bonsai-measured/`, which are kept but not versioned.

## The edge you cannot see

**WSL2 does not fail an over-allocation. It spills into shared system memory, and only once the
cache actually fills.** A window that is too large loads and answers short prompts at full speed.
Once the cache holds enough tokens, the pages past the edge land in shared memory and prompt
processing collapses. Bonsai at 104k with `q4_0`/`q4_0` reads a 43k prompt at a normal 416 tok/s
and a 92k prompt at 27 tok/s.

`nvidia-smi` does not show it. Every config near the edge reads ~7 935 MiB, whether it spills or
not. The only reliable test is prompt speed **at depth**: fill the cache to near its size and
check that `prompt_per_second` stays at its short-context level. Qwen, where the VRAM reading
tracks the configuration, puts the practical edge at **~7 850 MiB**. At 7 936 MiB its prompt
speed had already halved.

So a window that is too large does not announce itself when the server starts. On WSL2 the failure
to expect is the late one, in the middle of a session, when the cache has filled.

## Bonsai: windows on 8 GB

Fork `1a07bfa`, one pass (T-034's repeats varied < 2 %). tg and pp in tok/s. `chat` is a real turn
with thinking and code at the shipped sampling. `@43k` is a 42 803-token prompt, `@92k` 93 392:

| ctx | K/V | VRAM | tg short | tg chat | tg @43k | pp @43k | tg @92k | pp @92k | |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 64 000 | q8_0/q4_0 | 7 758 | 35.7 | 35.6 | 25.7 | 415 | – | – | **shipped** |
| 48 000 | q8_0/q8_0 | 7 652 | 33.7 | 35.5 | 26.4 | 413 | – | – | |
| 52 000 | q8_0/q8_0 | 7 808 | 34.8 | 35.6 | 26.4 | 414 | – | – | largest clean `q8_0`/`q8_0` |
| 56 000 | q8_0/q8_0 | 7 940 | 33.5 | 33.2 | 25.0 | 414 | – | – | at the edge |
| 60 000 | q8_0/q8_0 | 7 940 | 32.6 | 33.0 | 24.9 | 181 | – | – | spills |
| **96 000** | **q4_0/q4_0** | 7 932 | 33.5 | 33.1 | 24.3 | 416 | 18.5 | 355 | **largest clean window** |
| 100 000 | q4_0/q4_0 | – | – | – | – | – | – | 170 → 125 | spills from ~80k |
| 104 000 | q4_0/q4_0 | 7 940 | 35.8 | 35.5 | 25.6 | 416 | 19.4 | 27 | spills at depth |
| 112 000 | q4_0/q4_0 | 7 934 | 33.2 | 32.9 | 24.3 | 28 | 16.6 | 9 | spills |
| 131 072 | q8_0/q8_0 `-nkvo` | 6 594 | 11.7 | 10.9 | 3.7 | 349 | – | – | tg @112k 1.8 |

- **96 000 at `q4_0`/`q4_0` is the largest window that stays on the card**, 50 % more than the
  shipped 64k. It costs ~6 % decode (33.5 against 35.7 short, 24.3 against 25.7 at 43k). It is
  clean to the end: the prefill in the quality test below read 92 672 tokens at 357 tok/s, and a
  95 000-token prompt read at 354 tok/s (2026-09-26). It is not the default yet: its one agent
  session compacted cleanly at ~80k but failed on something else, see
  [agent.md](agent.md#context-budget).
- **A same-type cache is not faster.** `q8_0`/`q8_0` gains 2.7 % at 43k and nothing at short
  context, for 12k less window. This settles the hypothesis that the mixed-type kernel explains
  the long-context gap (see [performance.md](performance.md#the-long-context-gap)).
- **KV in RAM (`-nkvo`) is out**: 11.7 tok/s at short context, 3.7 at 43k, 1.8 at 112k. With the 16
  attention layers on the CPU, two thirds of the speed is gone at any depth. That holds even
  though the other 48 layers are Gated DeltaNet and never touch the cache.

## KV cache quality

**16k against an f16 cache.** `llama-perplexity`, one 16 384-token chunk of llama.cpp's own
source, the second half scored against the logits of an `f16`/`f16` run. For Qwen an
f16-against-f16 control gives a mean KLD of 0.000000 and 100 % same top p. The runs are
deterministic, so every difference is the cache:

| K/V | Bonsai mean KLD | Bonsai same top p | Qwen3.6 mean KLD | Qwen3.6 same top p |
| --- | --- | --- | --- | --- |
| q8_0/q8_0 | 0.000101 | 99.83 ± 0.05 % | 0.0033 | 99.07 ± 0.11 % |
| q8_0/q4_0 | 0.000612 | 99.66 ± 0.06 % | 0.0049 | 98.94 ± 0.11 % |
| q4_0/q4_0 | 0.001127 | 99.39 ± 0.09 % | 0.0056 | 98.76 ± 0.12 % |

Base perplexity 1.701 (Bonsai) and 1.461 (Qwen): the corpus is easy for both.

**At depth.** `llama-perplexity` cannot score a 92k chunk here: it reserves logits for the whole
chunk, 94k tokens x 248k vocabulary x 4 bytes, ~93 GB, and aborts with `bad_alloc`. Instead,
`score_long.py` goes through `llama-server`. It reads the first 92 160 tokens of the corpus, then
scores the next 512 one at a time, teacher-forced with top-20 log-probs and `prompt_n` 1 per step,
so the cache stays intact. The reference is `f16`/`f16`: for Bonsai with the cache in RAM (it does
not fit on the card at that depth), for Qwen on the card. The KLD is taken over the reference's
top 20, so it is a lower bound:

| K/V | Bonsai @92k same top-1 | Bonsai @92k KLD | Qwen @92k same top-1 | Qwen @92k KLD | Qwen @120k same top-1 | Qwen @120k KLD |
| --- | --- | --- | --- | --- | --- | --- |
| q8_0/q8_0 | – | – | 99.80 % | 0.00096 | 99.80 % | 0.00119 |
| q8_0/q4_0 | 99.80 % | 0.00021 | 99.61 % | 0.00132 | 98.83 % | 0.00286 |
| q4_0/q4_0 | 99.61 % | 0.00073 | 99.41 % | 0.00249 | 98.83 % | 0.00397 |

The mean log-probability of the true token does not move with the cache type, not even to the
fourth digit for Bonsai (-0.1867 f16, -0.1851 `q8_0`/`q4_0`, -0.1868 `q4_0`/`q4_0`). The
differences are in close calls, not in reading the text.

What it answers:

- **Bonsai's `q8_0`/`q4_0` has no quality case against it.** It is 0.17 points of "same top p"
  below `q8_0`/`q8_0` at 16k and identical to f16 on 510 of 512 tokens at 92k. The old rationale
  ("keys are more sensitive", the general rule) is replaced by this measurement, and the default
  stays.
- **Bonsai's `q4_0`/`q4_0` reads 96k.** It is 0.44 points below `q8_0`/`q8_0` at 16k, and 2 of 512
  top-1 tokens differ from f16 at 92k. That backs the 96k window on quality as well as speed.
- **Qwen's cache is 3-33x more sensitive than Bonsai's** by mean KLD, per type and depth. Even
  its `q8_0`/`q8_0` deviates at 16k three times as much as Bonsai's `q4_0`/`q4_0`. The likely reason
  is the geometry: 2 KV heads of 256 dims against Bonsai's 4, so each stored value carries more.
  This is measured, not explained. `q8_0`/`q8_0` holds its level with depth (0.00096 → 0.00119);
  `q4_0` for V does not (0.00132 → 0.00286). That is why Qwen ships at 131k with `q8_0`/`q8_0`
  instead of 262k with V at `q4_0`.

Caveats: one text, llama.cpp's own source, which both models read easily; 512 positions per
depth; n = 1 per config. Harder text would probably widen the gaps; whether it changes their
order is unmeasured.

## The hybrid prompt cache

Both models are hybrids, with every 4th layer full attention and the rest Gated DeltaNet with a
recurrent state. The risk was that llama.cpp cannot reuse a prompt prefix on such a model and
reprocesses every turn. It does reuse it: sending the same 42 803-token prompt twice gives
`prompt_n` 4 the second time, on every KV type, with `-nkvo`, and on both the fork and mainline.
No extra flag is needed.

## Reproducing

`runs/T-035-bonsai-measured/` and `runs/T-034-qwen-moe/`: `measure.sh` (one server per line of
`CONFIGS`, JSONL out, each request capped by `MAX_TIME` because a spilling config can take an hour
on one prompt), `phase2a.sh` (the 16k KLD), `phase2b.sh` with `score_long.py` and
`compare_long.py` (the depth test). `jq` is not on the reference machine, so the scripts use
python3. `llama-perplexity` is built in place with
`cmake --build "$LLAMA_DIR/build" --target llama-perplexity`, which leaves `llama-server`
unchanged.
