# The agent: pi, its budget, its prompt

How pi is installed and configured against the server, the context budget that keeps it from
compacting itself to death, the agent prompt, and who starts and stops the server. The
arithmetic was measured on Bonsai and holds for every model; the per-model values are in
`profiles/{model}/`.

## Context budget

pi's compaction defaults assume a 200k window. On 48k they produce an endless compaction
loop. From `dist/core/compaction/compaction.js` and `settings-manager.js`:

- `shouldCompact`: `contextTokens > contextWindow - reserveTokens`, default `reserveTokens` 16384
- `keepRecentTokens` default 20000, estimated as `chars/4` over the messages only - the
  system prompt and the tool schemas are not counted, and chars/4 underestimates code and
  JSON tool arguments

Measured on a full-stack game prompt (session `2026-09-19T16-24-33`, 30 entries, 31 minutes):

| Compaction | tokensBefore | input of the next request |
| --- | --- | --- |
| 1 | 33 229 | 33 524 |
| 2 | 39 087 | 32 272 |
| 3 | 33 963 | 32 476 |
| 4 | 35 026 | - |

The trigger sat at 48000 - 16384 = **31 616**, and the context never came back below it:
those "20 000" kept tokens really were ~30 000. The first compaction cut at the very first
assistant message and freed nothing at all. pi then compacted on every single turn, at a
cost of one summarization call (2.3-3.8k tokens at ~30 tok/s) plus a full prompt
reprocess - `cacheRead` drops to 0 after a compaction - of ~33k at ~400 tok/s. Roughly a
third of that session went into compaction, and the task never finished.

A second, latent fault: `maxTokens` 24000 plus a 31 616 trigger let pi request 55 616
tokens from a 48000 window. With `--no-context-shift` the server stops there; the
`2026-09-19T15-32-43` session shows a `stopReason: length`.

The settings below keep the post-compaction state comfortably under the trigger and the
worst case inside the window. `install.sh pi` writes the two compaction keys into
`$BONSAI_HOME/pi-agent/settings.json`.

Because these five constrain each other, they live in a profile, `profiles/$MODEL/$PROFILE.env`, and move together.
`PROFILE=dedicated` (default) is the 64k window below. `PROFILE=display` is the 48k set the
measurements above were taken with - `CTX` 48000, `BUDGET` 4096, `MAX_TOKENS` 12000,
`RESERVE_TOKENS` 12000, `KEEP_RECENT_TOKENS` 8000 - for a GPU that also renders a desktop
and so cannot hold a 64k cache.

| | Value | Constraint |
| --- | --- | --- |
| `RESERVE_TOKENS` | 16000 | >= the largest single turn's output (11 441 measured), and >= `BUDGET` + a tool call + 4096 for the clamp |
| `MAX_TOKENS` | 16000 | `CTX - RESERVE + MAX_TOKENS <= CTX`, so exactly 64000 |
| `KEEP_RECENT_TOKENS` | 12000 | real cost ~1.4-2x, so ~24k in use against a 48 000 trigger |
| `BUDGET` | 8192 | 8192 + ~3.7k tool call <= `RESERVE_TOKENS` - 4096 = 11 904 |

That leaves ~20k of working room.

Measured on the same prompt with these settings (session `2026-09-19T17-24-22`, 79 agent
steps, 89 minutes): 5 compactions, with 13, 18, 12, 19, 5 and 12 steps between them -
against one per step before. Each fired at 36 974-37 513 tokens, and the next request came
back at 15.2-18.6k, less than half the trigger. The run ended on something else, below.

**pi caps the output near the trigger.** pi sends `max_tokens` as
`min(maxTokens, contextWindow - estimated context - 4096)` (`clampMaxTokensToContext`,
`CONTEXT_SAFETY_TOKENS` = 4096). Just below the trigger that leaves
`RESERVE_TOKENS - 4096` = 7 904 tokens, less than `BUDGET` (8192). The last step of that
session sat at 35 861 tokens, got `max_tokens` 8 334, spent 8 192 of it thinking, and was cut
off with `stopReason: length` before its tool call, which ended the agent loop. So the real
constraint is `BUDGET + tool call <= RESERVE_TOKENS - 4096`.

`BUDGET` is therefore 4096: with a tool call of up to ~3.3k (the largest write measured
without thinking) it stays under 7 904, and a 3k budget already produced plan + code (see
[Reasoning](bonsai.md#reasoning)). The other lever, `RESERVE_TOKENS` 16000, would keep 8 192 of
thinking but lower the trigger to 32 000 and the working room between compactions to ~16k.

Three runs of the same prompt, which is what the numbers below come from:

| | 48k, `BUDGET` 8192 | 48k, `BUDGET` 4096 | **64k, `BUDGET` 8192** |
| --- | --- | --- | --- |
| Steps / duration | 79 / 89 min | 168 / 112 min | 108 / 91 min |
| Ended | cut off on `length` | on its own | on its own |
| Compactions | 5, every 5-19 steps | 7, every 8-33 steps | 4, every 17-30 steps |
| Context after one | 15-19k | 15-19k | 21-24k |
| Steps at the budget | 4 | 6 | 2 |
| Result | unfinished | one `index.html`, online mode never tested, test passes claimed but not run | server + client + two integration tests, 869 lines, confirmed working |

The middle run is the `display` profile, the right one is `dedicated`. Fewer, larger steps
beat many small ones here: half the steps of the 4096 run, in the same time, for a result
that holds up. The 64k run's closest approach to pi's clamp left 5 372 tokens of margin, so
the trigger was never the limit.

**The 4096 stays.** pi's `CONTEXT_SAFETY_TOKENS` is a constant in its bundle. Shrinking it means
patching a pinned dependency, which `PI_VERSION` would then no longer describe, or asking pi for a
setting. With 5 372 tokens of margin in the run above, ~3k more working room per compaction cycle
is not worth either. Revisit only if a profile runs tighter than that (closed as T-015).

The 4096 re-run (session `2026-09-19T19-16-01`): 168 steps in
112 minutes, and the run ended on its own (`stopReason: stop`) with no step cut off on
`length`. 7 compactions, 8-33 steps apart, back at 14.5-19.4k each time. 6 steps hit the
budget. The largest output was 11 441 tokens, 4k thinking plus a ~7k `write`, at 7.6k
context where the clamp still allowed the full 12 000. The same step just below the trigger
would be cut off, so the tool-call allowance above is a typical case, not a bound.

## The agent prompt

`$BONSAI_HOME/pi-agent/AGENTS.md`, installed from [`pi/pi-agents.md`](../pi/pi-agents.md), goes
into pi's system prompt at startup, for every session and both models; `--append-system-prompt`
and `--system-prompt` are the per-run equivalents. It is written as a description of the
situation with the reason for each point, not as rules, and that is a measured choice:

- **Rules are checked with turns.** The localagent runs showed a model that over-attends to
  everything in reach: "~80 lines" became `wc -l` five times, "read nothing else" became
  orientation reads, a stated turn limit became a count. Every hard rule added there was ignored or
  paid for in turns ([localagent.md](localagent.md#the-t-019-cli-run-where-the-turns-went)). So the
  file carries no number, no "never" or "must", and nothing the model could verify with a tool.
- **Thinking length is not a prompt matter.** This model ignores instructions about how long to
  think, the template's effort levels included ([Reasoning](bonsai.md#reasoning)); `BUDGET` is what stops
  it. The file only says why code belongs in the tool call: a block cut off at the budget loses
  whatever was drafted in it.
- **Each point answers a failure in a plain session**, not in the workflow. From the Tron runs
  ([agent-sessions.md](agent-sessions.md)): the 96k session that spent two hours debugging its own
  headless-DOM test harness and never returned to the game; the Qwen session that wrote eleven
  tests on a bug report and left the bug in place; the 4096 run that claimed test runs it never
  did; leftover servers holding the ports of the next test.
- **It stays task-neutral.** Nothing about games, browsers or the Tron prompt, which is the
  benchmark: a prompt tuned to it would measure the prompt. That includes the HTML comment at
  its top, which pi passes to the model with the rest, so the reasons live here and not there.

The first version (until 2026-09-27) was four imperatives: think short, one step per turn, no
restating, minimal tool arguments. None of it was ever measured against no file at all.

**Its first reading (T-041, 2026-10-02): no cost seen, no effect seen on Bonsai. It stays.** No
session quoted it or checked its points with tools. C2 did worse than C, but its log shows why,
and it is not the file: it did exactly what the third point argues against, an hour inside its
own test setup, and lost the end to a `pkill -f` that killed its own shell
([agent-sessions.md](agent-sessions.md#c2-and-w-bonsai-and-swift-bonsai-2)). Qwen3.6 with the same file (B2) gave its best session yet;
that is n = 1 and no comparison against no file. The `pkill -f` trap is the candidate for the
next point it carries, with a new reading after.

## pi

`bonsai-pi` runs a private pi: `install.sh pi` puts version `PI_VERSION` into `$BONSAI_HOME/pi`
(`npm install --prefix`, no `-g`, no sudo), and the wrapper sets `PI_CODING_AGENT_DIR` to
`$BONSAI_HOME/pi-agent`. pi resolves every user path through that variable (`getAgentDir()`
in `dist/config.js`): providers, settings, `AGENTS.md`, auth, sessions.

The first version wrote into the global `~/.pi/agent` instead, and collided with any pi
already in use there:

- `defaultProvider`/`defaultModel` were overwritten, so a plain `pi` started on Bonsai.
- The compaction keys are global or per project, not per model (`settings-manager.js`).
  A 200k model then kept 8k of recent history per compaction instead of 20k.
- `AGENTS.md`, telling the model to think briefly on a small window, went into every
  model's system prompt - or, when the user had their own, ours was skipped.
- Whatever pi version was installed ran, while the budget arithmetic under
  [Context budget](#context-budget) reads pi 0.85.1's compaction code.

A project directory's own `.pi/settings.json` still applies to both instances; that is
pi's per-project override and intended.

pi reads providers from `models.json`. `contextWindow` decides when pi compacts, together with the settings under [Context budget](#context-budget) - not `maxTokens`, which is only the per-turn output cap. Unsloth's `unsloth start pi` hard-codes `maxTokens = min(context / 4, 8192)`, which cuts a single long reasoning turn off at 8k. That is why this setup uses its own config.

### Tool timeout

pi's bash tool has no default timeout: a call without one runs until it returns or someone
presses Escape. A server started in the foreground, or a test that waits for a socket that never
answers, holds the whole session. In the Tron sessions on the 4060 Ti machine that happened four
times in 534 tool calls, all with Qwen3.8-Flash or Swift-Bonsai-2 (W, ES), each aborted by hand
after 5-15 minutes, and each time the model needed a `Resume.` to go on. None of the calls that
returned took longer than 3.8 minutes; the long ones were the models' own match simulations,
mostly wrapped in a `timeout` of their own.

The `tool-timeout` extension (`pi/extensions/tool-timeout/`, installed by `install.sh pi`) gives
every bash call that has no `timeout` the one in `TOOL_TIMEOUT`, 300 seconds by default; the
model's own value is left alone. pi then kills the process tree and returns `Command timed out
after 300 seconds` as a tool error, which the model reads like any other result and the session
goes on. `bonsai-pi` passes the value in the environment, so changing it needs no `install.sh pi`;
`TOOL_TIMEOUT=0` turns it off. The agent prompt says so in one line, so a step that needs longer
can ask for it. Not yet seen in a session: the value is from the timings above, not from a run
with it.

## Server lifecycle

`bonsai-pi` owns the server only when it started it. On start it checks `/health` on `PORT`;
with no answer it launches `bonsai-server` in the background and waits until `/health`
returns 200 (the model is loaded), at most `SERVER_START_TIMEOUT` seconds. Every run then
checks `/v1/models` for `MODEL_ALIAS`, so pi never talks to some other server on that port.

- **Shared server.** Each session registers its PID in `$BONSAI_HOME/run/sessions/` under a
  `flock`. The last session to leave stops the server; sessions that died without cleaning
  up are pruned by PID. `run/server.pid` exists only for a server `bonsai-pi` started, so a
  server started by hand is never stopped.
- **Own session (`setsid`).** The server runs outside the terminal's process group: Ctrl+C
  in pi - which cancels a generation - must not reach llama-server, which installs its own
  SIGINT handler and would quit.
- **Orphans.** A session killed with SIGKILL, or a terminal window closed hard, runs no trap:
  its server stays up with its pid still in `run/server.pid`. The next `bonsai-pi` prunes the
  dead session entries and adopts that server, so it stops when that session leaves. Verified.
- **Traps.** Closing the terminal (HUP), TERM or QUIT runs the cleanup. While pi runs, the wrapper
  catches SIGINT with a no-op: uncaught, bash would die with pi when pi exits on SIGINT and skip
  the cleanup. While waiting for the model, Ctrl+C aborts and stops the server.

Verified with a stand-in server and pi: one session, two overlapping ones, Ctrl+C caught by
pi, pi killed by SIGINT, Ctrl+C during load, HUP, a hand-started server, and a server that
dies during start. With the real model:

- The first session waits for the load: `model loaded` after 7.7-7.9 s, the same with the
  model file evicted from the page cache (`posix_fadvise DONTNEED`). A one-line `bonsai-pi -p`
  takes 14 s end to end. `SERVER_START_TIMEOUT` 300 has ample margin on this machine.
- llama-server exits on SIGTERM within ~1 s, and VRAM goes from 7 275 MiB back to 0.
- Two overlapping sessions share one server; the last to end stops it.
- SIGINT to one session's process group mid-generation: pi aborts its request (the server
  logs `cancel task`), the server keeps running and answers the other session.
- `run/` holds no session and no `server.pid` after each run.

### A server on another machine

`LISTEN_HOST` is what llama-server binds to, `SERVER_HOST` what the client side - `bonsai-pi`'s
health and model checks, and the `baseUrl` written into pi's `models.json` - connects to. Both
default to `127.0.0.1`, which is the whole setup on one machine. They were the same hardcoded
literal until it turned out that the machine with the GPU and the machine you work on need not
be the same one.

To serve one GPU box to another host: `LISTEN_HOST=0.0.0.0 bonsai-server` there, then
`SERVER_HOST=<box> ./install.sh pi` here and `bonsai-pi` as usual. `./install.sh pi` has to run
again because pi keeps a written copy of the URL - the same drift as `CTX` and `PORT`.

- **Autostart steps aside.** `bonsai-pi` starts and stops a server by pid and reads `SERVER_LOG`;
  neither exists for someone else's process on another host. With a non-local `SERVER_HOST` it
  therefore never starts one, says so once, and fails on the `/v1/models` check if nothing is
  serving. `SERVER_AUTOSTART` keeps its meaning for a local server.
- **There is no authentication.** The provider sends `apiKey: "none"` and llama-server asks for
  nothing, so `LISTEN_HOST=0.0.0.0` offers the model to everyone who can reach the port. On a
  network that is not yours, forward it instead - `ssh -N -L 8080:127.0.0.1:8080 <box>` - and
  leave `SERVER_HOST` at `127.0.0.1`; the tunnel needs no setting at all.
- **Latency is not the problem, bandwidth is not either.** A turn is one HTTP request and a
  token stream; on a LAN the round trip disappears next to a 27B model's generation time.

Verified: the URL that `config.env` derives for local, remote and remote-with-port, the
`models.json` written from it, and the four autostart branches under `set -e`. Not yet run
against a real remote server - the machine this was written on has no GPU.

## Unsloth Studio

`bonsai-studio` opens the model `MODEL` names in [Unsloth Studio](https://github.com/unslothai/unsloth)
instead of a bare llama-server: Studio's chat UI and API, this repo's build and flags. It is
`unsloth studio run` with three things changed.

- **The build.** `LLAMA_SERVER_PATH` points Studio at `LLAMA_SERVER`, the tree the model file
  pins. That is the first place Studio looks, ahead of its own `~/.unsloth/llama.cpp`, so Bonsai
  runs on the fork and both Qwen models on the Unsloth tree this repo built, at the pinned source.
- **The flags.** `scripts/server-flags.sh` holds what `bonsai-server` passes, and `bonsai-studio`
  hands the same list to Studio, which appends it after its own flags: llama.cpp's last value
  wins, so the profile's placement, cache types, reasoning budget and `SERVER_ARGS` are what runs.
  The window goes as `--context-length`, MTP as `--speculative-type mtp` or `off`, one slot as
  `--parallel 1` (Studio's default of 4 splits `CTX`), sampling as Studio's pinning options,
  because Studio owns those flags and refuses or rewrites them as raw arguments.
- **Studio's own picks undone.** `--no-mmproj`, since no profile budgets VRAM for a vision
  projector that Studio loads when it finds one beside the GGUF; `--load-mode auto`, because Studio
  reads a model into memory (`none`) when it estimates it fits, and the experts in RAM are
  measured mmapped.

Two details of Studio's parser decide how the flags are written. Its **manual** memory mode
strips every offload flag from the pass-through and has no command line option for the expert
count, so `bonsai-studio` stays in **auto**, which keeps an explicitly requested window ("no
silent shrink") and passes the flags through untouched. And its command line reads a short
cluster as its own options: `-ctxcp 4` ends in `-p`, its port. `server-flags.sh` and the model
files therefore use long spellings only (`--n-gpu-layers`, `--ctx-checkpoints`, ...), and so must
extra arguments to `bonsai-studio`.

Studio adds flags of its own that are left alone: `--metrics`, `--slot-save-path` (it saves a
slot's KV cache to disk when it unloads an idle model), `--chat-template-kwargs` with the same
`preserve_thinking: false` as `PRESERVE_THINKING`, `--video-fps`, and for Bonsai
`--ctx-checkpoints 21` against llama.cpp's 32, sized from host RAM. It also sends a system prompt and
tool definitions of its own, ~1.3k tokens on a one-line question. Its port is 8888, it has its own
login and API keys, and `bonsai-pi` does not talk to it: pi stays on `bonsai-server`.

Verified on 2026-10-02 with Studio 2026.9.12 (`unsloth` package), headless and without the GPU,
which the agent sandbox does not have: for all three models Studio started our build with every
flag of the profile last on its command line and loaded at the profile's window. Qwen3.6 and
Qwen3.8-Flash answered a chat request through its API on the CPU (21 tok/s with MTP accepting
55 %, and 6.2); Bonsai's ternary weights read a prompt on the CPU too slowly to wait for. Not yet
run with the card, so VRAM and speed under Studio are unmeasured (T-043): the agent sandbox runs
Studio, and with it its llama-server, without the GPU.

## localagent workflow

`bonsai-pi --localagent` runs a multi-agent build pipeline for this model. **Decided
2026-09-23: frozen and not recommended.** On a small CLI it finished in the time the model takes
alone; on the study's Tron prompt it was stopped after 2:50 with its first unit unfinished, where
the model alone built the game in 1:30. What stopped it was the model - compactions inside a
worker, whole-file rewrites, broken tests of its own - not the harness, so it stays in the repo
unchanged until a stronger local model is out. Its own file, [`localagent.md`](localagent.md),
has the runs, the shape, and how it runs on pi. What it constrains here is only the window: a
dispatched agent that ends on `length` comes back as `BLOCKED`, see
[Context budget](#context-budget).

