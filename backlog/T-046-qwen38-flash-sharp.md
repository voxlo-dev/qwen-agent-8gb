# T-046 — Qwen3.8-Flash natively, as shipped and with the Sharp template

- **Summary:** Two Tron sessions on the 4060 Ti under native Linux: Qwen3.8-Flash as shipped (E, cut from T-041) and the same with the Sharp chat template (ES). Flash is the top of T-044's ramp with one agent session, under WSL2; Sharp claims shorter thinking and fewer turns to a fix on Qwen3.8. Decides whether Sharp gets a `CHAT_TEMPLATE_FILE` setting. Swift 1.5 Flash-Next was dropped: no Unsloth dynamic quant
- **Category:** spike
- **Importance:** medium
- **Effort:** S (two sessions of ~1 h each, one warm pass; the render check is done)
- **Depends on:** none; its result goes into T-044's README if it lands first

## Why

D (2026-09-29, WSL2, ~10 tok/s) built a running game with rematch working in 54 minutes, the only
agent reading of the model T-044 calls the strongest ([agent-sessions.md](../docs/agent-sessions.md#d-qwen38-flash)).
Natively it runs at ~19 tok/s with every expert cached
([qwen38-flash.md](../docs/qwen38-flash.md#native-linux-every-expert-cached)).

Sharp (`peculiar-ragdoll/Qwen-Sharp-Chat-Templates` at `85461fc`, v22.5.0, Apache-2.0, pinned in
`runs/T-041-tron-day-2/qwen-sharp-v22.5.0.jinja`) is written for Qwen3.5/3.6/3.8; its own agentic
number is Qwen3.8-27B on SWE-bench-Live, 15 of 25 against 16, median 20.0 against 54.6 minutes to
a fix. On Bonsai it was never run: Bonsai ignores instructions on thinking length
([bonsai.md](../docs/bonsai.md#reasoning)). Flash is a different case: it reads `reasoning_effort`,
thinks little already (D: 22k output tokens in 32 requests), and is slow enough per token (~19
tok/s) that fewer turns to a result would show in minutes.

**Dropped: Swift 1.5 Flash-Next.** UkisAI ships it in plain llama.cpp quants only; the closest to
the pinned `UD-IQ4_XS` (89.4 GB) are `IQ3_XXS` at 88.0 and `IQ4_XS` at 97.7 GB, so a session would
compare quant and fine-tune at once and re-open the RAM fit. Its GGUFs also embed the Qwen3.8-27B
template (the same as Bonsai's), not Unsloth's Flash template.

## The render check, done 2026-10-03

The Flash GGUF's own template is Qwen3.8's plus Unsloth's fixes: `developer` role, merged system
messages, tool-call argument validation, `high` → `xhigh`. Sharp is froggeric's base, without
those. Both rendered through `/apply-template` on the Unsloth tree (b11160) with the Flash GGUF
loaded, the same conversation as in T-041 (system prompt, a tool, a tool call, its result):

- **Stock Flash renders byte for byte what stock Bonsai rendered** (`render-flash-stock.txt` against
  `render-stock.txt`): for what pi sends, Unsloth's fixes change nothing. pi sends its system prompt
  as `system`, not `developer`, because the model is not marked `reasoning` in `models.json`.
- **Sharp renders identically on both trees** (`render-flash-sharp.txt` against `render-sharp.txt`),
  and `/props` serves v22.5.0. So on Flash, Sharp makes the same two changes it makes on Bonsai: the
  terseness block after the system prompt, and the tool-call instructions (all reasoning inside
  `<think>`, the `<tool_call>` immediately after it, one closed block per call).

Files in `runs/T-041-tron-day-2/`.

## The protocol

T-041's ([agent-sessions.md](../docs/agent-sessions.md#the-protocol)): fresh directory, the study's
prompt, `Test it and get it to work.` once, 90-minute cap, `LC_ALL=C.UTF-8`, the agent prompt in
both. Terminal only on the machine, ~58 GB available before start, one warm pass of the server
first (`runs/T-035-bonsai-measured/day/README.md`). Default threads.

- **E**: `MODEL=qwen38-flash` as shipped.
- **ES**: the same plus `--chat-template-file` with Sharp, appended to the model file's
  `SERVER_ARGS`; own pi dir, so the two sessions' logs stay apart.

`session.sh E` and `session.sh ES` in `runs/T-035-bonsai-measured/day/`.

## Deciding

- **Sharp**: ES at least as good as E by hand, and clearly fewer steps or minutes to the first
  "done": a second ES on another day, then a `CHAT_TEMPLATE_FILE` setting in `config.env` with the
  file pinned under `templates/` (Apache-2.0, attribution in the README), opt-in per model. No clear
  gain: noted in `qwen38-flash.md`, nothing wired.
- **E** goes into [agent-sessions.md](../docs/agent-sessions.md) as Flash's first native session
  next to D; Flash stays experimental either way.
