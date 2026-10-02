# T-035 — The quality claim: Bonsai in the study's harness, twice

- **Summary:** Bonsai through OpenCode with the study's exact prompt and follow-up, twice, on the profile T-041 settles, so it lands in the study's table; then `docs/evidence.md`, and the README's "what is measured" paragraph follows the result. Speed, window, KV quality and the first behaviour day are done and in the docs
- **Category:** spike
- **Importance:** high
- **Effort:** S (two OpenCode runs, ~1.5 h each, and one write-up)
- **Depends on:** T-041 (which Bonsai profile is `dedicated`)

## Why

The README says it plainly: the claim that Bonsai closes the quality gap is **not measured**. No
Bonsai run exists in [model-comparison.md](../docs/model-comparison.md)'s table, which is the
comparison this repo is built on, so the repo claims interactive speed for a dense 27B on 8 GB and
nothing about beating other models. The plain `bonsai-pi` sessions of T-041 and the first Tron day
say what this setup does in its own harness; they do not compare with the table, whose rows all
ran in OpenCode.

Done earlier in this ticket, all in the docs: speed and window, KV quality against f16
([context-window.md](../docs/context-window.md)), the first behaviour day
([dev.md](../docs/dev.md#context-budget), [qwen.md](../docs/qwen.md#in-an-agent-session)). Was
T-027 and T-033.

## What

1. **OpenCode against `bonsai-server`** (`$SERVER_URL/v1`), on the profile T-041 leaves as
   `dedicated`, a fresh directory each time, the study's exact prompt and its follow-up. Twice,
   because the study's own caveat is n = 1.
2. Judge each the way the study did: does the game start, can two browsers log in, host and join,
   does a round play; and the process axis (ended on its own, tested, claimed tests it never ran).
3. **`docs/evidence.md`**: the prompt, the invocations, the numbers of these two runs and of the
   Tron sessions on both days, and the resulting repos as tarball links.
4. The README's "what is measured" paragraph follows the result. It says "first" or "beats" only
   if both OpenCode runs pass where the study's table fails.

Not in scope: the Vulkan path, the localagent workflow (frozen), MTP for Bonsai
([performance.md](../docs/performance.md#mtp-no-head-for-this-gguf)).
