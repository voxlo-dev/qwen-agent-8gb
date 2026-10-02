# T-041 — The second Tron day, on native Linux: every open agent session in one protocol

- **Summary:** Five plain `bonsai-pi` sessions on the study's Tron prompt, over two days on the 4060 Ti machine under native Linux: Bonsai 96k against 64k on the new agent prompt (A2, C2), Bonsai with the Sharp chat template (S), Qwen3.6 (B2), Qwen3.8-Flash (E). Decides 96k, gives the agent prompt its first reading, settles Sharp, and carries the supported/experimental call for Qwen3.6
- **Category:** spike
- **Importance:** high
- **Effort:** M (two days, mostly unattended; one evaluation)
- **Depends on:** none. Merges what was left of T-031, T-034, T-035 (phase 3b), T-039 and T-040

## Why

Five tickets were each waiting for one more Tron session, and each would have needed its own day
for a same-day control. One protocol, run once, answers all of them:

| Session | Setup | Answers | Against |
| --- | --- | --- | --- |
| **A2** | Bonsai 96k, `q4_0`/`q4_0`, `KEEP_RECENT_TOKENS` 16000, own pi dir | does 96k become `dedicated` (was T-035 3b) | C2, same day |
| **C2** | Bonsai 64k as shipped | the control, and the agent prompt's first reading | A2 and S; C (2026-09-27) for the prompt |
| **S** | C2 plus `--chat-template-file` with Sharp v22.5.0 | is Sharp worth an opt-in (was T-031) | C2, same day |
| **B2** | Qwen3.6 as shipped | supported or experimental (was T-034 phase 4) | B (2026-09-27) |
| **E** | Qwen3.8-Flash as shipped, natively | what the 2x speed does to a session (was T-040 step 6) | D (2026-09-29, WSL2) |

The first day (A, B, C, D) is in [dev.md](../docs/dev.md#context-budget) and
[qwen.md](../docs/qwen.md#in-an-agent-session). Since then `pi/pi-agents.md` was rewritten
([dev.md](../docs/dev.md#the-agent-prompt)), and the machine moved from WSL2 to native Linux.
Bonsai sits entirely on the card and runs at the same 36.6 tok/s on both, so A2 against C2 stays
clean; C2 against C mixes the prompt with the OS, which is one more reason to read it as weak.

## Before the days

1. `./install.sh pi` for each pi dir the sessions use, so all get the new `AGENTS.md`:
   `session.sh` does that per session. Check that `$PI_AGENT_DIR/AGENTS.md` starts with
   `## Working here`.
2. The scripts: `runs/T-035-bonsai-measured/day/`, extended with the new session letters
   (`session.sh A2`, `watch.sh A2`, `evaluate.sh A2 C2 S`). `$BONSAI_HOME` is now
   `~/models/bonsai-local`, and the working dirs are `~/tron-{a2,c2,s,b2,e}`.
3. The machine is headless: judging a result takes the game's port forwarded to a machine with a
   browser (`ssh -L 3000:127.0.0.1:3000 …`, the port whatever the model chose), two windows.
4. Sessions run from your own shell, not from an agent's sandbox: `bonsai-pi` needs the GPU.

## The protocol

As on the first day: fresh directories, the study's prompt verbatim from
[model-comparison.md](../docs/model-comparison.md) as the first message, the bare `Test it and get
it to work.` once when the model says it is done, no other input. No bug reports this time (B got
one). Evaluation with `evaluate.sh` and `session_stats.py` (budget per session), plus by hand:

- **Result**: does it start, can two browsers log in, host and join, does a round play, does
  rematch work?
- **Process**: did it end on its own; did it build a test setup of its own, and how long did it
  spend there; did it run the product itself; does its final summary separate what it ran from
  what it did not?

**Day 1, Bonsai**: A2 and C2 back to back, then S. Each ~1-1.5 h (A took 158 min aborted).
**Day 2, Qwen**: E first, after one warm pass of its server (a cold page cache read 13 GB from the
SSD on the first pass after another model, `runs/epp-2026-10-02/NOTES.md`), with ~58 GB available
and nothing but a terminal running, so preflight passes. Then B2. Default threads for both: `-t 7`
is slower natively (T-037, [qwen.md](../docs/qwen.md#native-linux)).

### Session S: what Sharp changes

Sharp is froggeric's Qwen-Fixed-Chat-Templates plus a terseness block. Pinned:
`peculiar-ragdoll/Qwen-Sharp-Chat-Templates` at `85461fc`, `chat_template.jinja`,
`template_version = "qwen3.8-froggeric-v22.5.0"`, sha256 `cdff39fb…a84a`, Apache-2.0. Downloaded to
`runs/T-041-tron-day-2/qwen-sharp-v22.5.0.jinja`; passed as
`SERVER_ARGS="--chat-template-file …"`, so no code changes before it has earned them.

**Rendered against the embedded template on 2026-10-02** (fork server, `/apply-template`, one
conversation with a system prompt, a tool, a tool call and its result; `render-{stock,sharp}.txt`
in the run folder). `/props` serves v22.5.0. History and the generation prompt are identical, so
`--no-reasoning-preserve` and the parser are untouched. **Two differences, not one** as T-031
assumed:

- the terseness block after the system prompt ("Answer directly, after thinking … If a user
  request is genuinely ambiguous, ask a sharp question, don't guess");
- **the tool-calling instructions**: the example puts a `<think>` block before the call, and the
  reminder says all reasoning belongs inside `<think>`, the `<tool_call>` comes "IMMEDIATELY after
  thinking, with NO conversational text before it", and one closed block per call.

The second one aims at the step between thinking and the tool call, not at prose, so S may move
more than the terseness alone would. The cost that matters here, thinking to the budget
before a trivial tool call, is still the model's, and dev.md measured that it ignores instructions
about thinking length ([Reasoning](../docs/dev.md#reasoning)). Sharp's one agentic number
(SWE-bench-Live, Qwen3.8-27B, 15 of 25 solved against 16, median 20.0 against 54.6 minutes) would
show as fewer turns to a result, not fewer tokens per turn.

## Deciding

- **96k**: A2 ends on its own, no `length` stop, a result at least as good as C2's, and a wall time
  no worse than C2's by more than ~10 % or fewer compactions: `profiles/bonsai/dedicated.env` moves
  to 96k `q4_0`/`q4_0`, budget 8192/16000/16000/16000; `README.md`'s "64k" and the
  `dev.md#context-budget` table follow, and T-042 checks the `display` candidate. Otherwise 64k is
  final, and dev.md says so with both pairs.
- **The agent prompt** stays if no session spends turns on the prompt itself (quoting it, checking
  its points with tools) and C2 is no worse than C. Worse, with the log showing why, reverts it.
- **Sharp**: thinking per turn still at the budget and turns to a result not clearly down: tried,
  noted in `dev.md#reasoning`, nothing wired. Turns clearly down: a second S on another day, and
  only then `CHAT_TEMPLATE_FILE` in `config.env` with the file pinned under `templates/`.
- **Qwen3.6 supported or experimental** is the author's call. B met "a working game ships it"
  already; B2 is the second reading. If it ships: `docs/qwen.md` and the README lose
  "experimental".
- **Qwen3.8-Flash stays experimental** either way; E goes into
  `docs/qwen.md#qwen38-flash-in-an-agent-session` next to D.

Results into `docs/dev.md` (A2, C2, S) and `docs/qwen.md` (B2, E); then this file is deleted.
