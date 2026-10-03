# AGENTS.md

Where a contributor or an AI agent starts. `README.md` is for people using this;
`CONTRIBUTING.md` is the short human version of this file.

## What this repo is

**Not an application.** Bash scripts that build a patched llama.cpp, fetch a pinned GGUF and
configure the [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) coding agent
against it. Nothing here compiles into a product; the thing being assembled lives in
`~/.local/share/bonsai-local` (`BONSAI_HOME`).

Which means the code is short and the **reasons are the product**. Every non-default choice - a
flag, a cache type, a token count - answers a failure observed on real hardware, and that reason
lives in `docs/` with the measurement behind it ([`docs/dev.md`](docs/dev.md) says where). A change without one is
incomplete, and a change that contradicts one needs a new measurement, not an argument.

## Map

| Path | Role |
| --- | --- |
| `config.env` | **Single source of truth.** Every setting, with `: "${VAR:=default}"` so an environment variable always wins. Sources the profile, then the model file |
| `models/{bonsai,qwen36-35b,qwen38-flash}.env` | Per `MODEL` (default `bonsai`): the GGUF pin, the llama.cpp tree that runs it (`LLAMA_*`, `PATCH_DIR`), KV types, `EFFORT`, `SPEC_TYPE`, and what preflight checks (disk, RAM, backends); `SERVER_ARGS` for flags no setting covers |
| `profiles/{model}/{dedicated,display}.env` | `CTX` and the four budget values, per model and GPU situation (`PROFILE`, default `dedicated`); for the MoE also `CPU_MOE` and `UB`. They constrain each other, so they move together |
| `install.sh` | Step runner: `deps build model pi link`, all of them by default. Runs `preflight` first |
| `scripts/preflight.sh` | Gates a run before it spends time: disk, RAM, driver, VRAM, Node, port. Reports every item, exits once. `SKIP_PREFLIGHT=1` bypasses it |
| `scripts/lib.sh` | Sourced first by every step; sources `config.env` and defines `log`/`warn`/`die`/`has` |
| `scripts/{deps,build,model,pi}.sh` | One install step each, individually re-runnable and idempotent. `deps` and `build` branch on `BACKEND` (`cuda`, `vulkan`); `build` fetches a git commit, or a checksummed release tarball (`LLAMA_TARBALL`) where the commit is not fetchable (Unsloth's tree) |
| `scripts/server-flags.sh` | The llama-server flags and environment of the selected model and profile, sourced by both launchers. Long spellings only: Unsloth Studio's parser misreads short clusters |
| `patches/{backend}/*.patch` | Applied by `build` to the fork at `LLAMA_COMMIT`, in name order, for that backend only, and only for a model whose `PATCH_DIR` names them (Bonsai). Today: the PTQ1_0 Vulkan decode, until upstream takes it (T-017) |
| `bin/bonsai-server` | The launcher. Sources `config.env` **directly**, not through `lib.sh`, then `scripts/server-flags.sh` |
| `bin/bonsai-studio` | Opens the same model in Unsloth Studio (`unsloth studio run`) on this repo's build, with the flags from `server-flags.sh` passed through. Same sourcing as `bonsai-server` |
| `bin/bonsai-pi` | Starts the pinned pi with `PI_CODING_AGENT_DIR` set to `PI_AGENT_DIR`, and starts/stops `bonsai-server` around it when none runs. State in `$BONSAI_HOME/run/`. Same sourcing as `bonsai-server` |
| `pi/pi-agents.md` | Runtime artifact, copied to `$PI_AGENT_DIR/AGENTS.md`. **Not this file** |
| `pi/extensions/localagent/` | pi extension behind `bonsai-pi --localagent`: the `dispatch` tool, and the session's `hasUI` for the plan gate. **Frozen, not recommended**: see below |
| `pi/localagent-workflow/` | The workflow it runs: skill, five agent prompts (orchestrator, scaffold, worker, e2e, docs), templates. Descended from the author's seven-agent workflow in `docs/model-comparison.md`; every cut since is measured in `docs/localagent.md` |

## Four things that bite

**Two consumers, one config.** `config.env` feeds both the llama-server command line and, through
`scripts/pi.sh`, a JSON config written into `PI_AGENT_DIR`. They drift silently: the server takes
its values at start, pi keeps a written copy. After changing `CTX`, `SERVER_HOST`, `PORT`,
`MAX_TOKENS`, `RESERVE_TOKENS` or `KEEP_RECENT_TOKENS`, `./install.sh pi` must run again, with the
same `MODEL`: each model has its own pi config dir.

**The context budget is arithmetic, not taste.** `CTX`, `BUDGET`, `MAX_TOKENS`, `RESERVE_TOKENS`
and `KEEP_RECENT_TOKENS` constrain each other, which is why they live in a profile and move
together. Getting them wrong makes pi compact on every single turn, or lets it ask for more tokens
than the window holds. Never change one alone; the constraints are in
[`docs/agent.md`](docs/agent.md#context-budget).

**Pins are deliberate.** `LLAMA_COMMIT`, `MODEL_REV` and `MODEL_SHA256` exist per model: Bonsai
needs a fork mainline llama.cpp has not absorbed, Qwen Unsloth's tree (a source tarball, checksummed) whose MTP drafting and sparse attention were measured, mainline on Vulkan. `PI_VERSION` pins the compaction code the budget
was measured against. Moving any of them means re-testing load and speed, checking that `patches/`
still applies (`build` refuses when it does not), and for `PI_VERSION` re-checking the budget.

**Nothing is installed into the repo, and nothing into the user's own tools.** Build output, the
model and pi's config live outside it. No global npm package, nothing under `~/.pi`: a user's
existing pi keeps its providers, defaults and compaction settings.

## Working on it

```bash
./install.sh                       # everything; FORCE=1 ./install.sh build rebuilds
BACKEND=vulkan ./install.sh build  # the AMD path, patches and all
MODEL=qwen36-35b ./install.sh      # the second model: Unsloth's tree, its GGUF, its pi dir
bonsai-pi                          # starts the server itself
```

Unversioned: the repo pins what matters instead. Each step checks whether its work is done and
exits early, so a second run is cheap and says so.

**There is no test suite.** Adding one was considered and declined: it is bash, there is no
framework, and what breaks is behaviour under a real model on a real card. Verify by observation.

| Change | How to see it worked |
| --- | --- |
| Any script | `bash -n`, and run the step twice to confirm it is still idempotent |
| Preflight | run it where it should fail (no GPU, wrong `BACKEND`, too little disk): one screen, nothing touched |
| Server flags | start it, query `http://127.0.0.1:8080/props`, or render a conversation through `/apply-template` |
| Vulkan kernels | generation and an ~850-token prompt at a stated window, judged by tok/s. VRAM is misleading: RADV only reports it meaningfully after the first request |
| pi's config | read back `$BONSAI_HOME/pi-agent/{models,settings}.json` |
| pi's behaviour | its session logs, JSONL under `$BONSAI_HOME/pi-agent/sessions/{cwd-slug}/`, one entry per message with `usage` counts and `compaction` records. That is where a context problem is visible |

A long measurement gets a folder under `runs/{ticket}-{slug}/` with its script and log. `runs/` is
gitignored but kept, so a result stays readable after the session that produced it; the conclusion
belongs in `docs/`.

## Code style

- POSIX-ish bash, `set -euo pipefail` via `lib.sh`; `bin/bonsai-server` and `bin/bonsai-pi` set it
  themselves
- A comment block at the top of every script saying what it does and what it needs
- `SPDX-License-Identifier: MIT` on the second line, or the first in a file with no shebang
- Settings are declared in `config.env` only, `models/*.env` for what differs per model, or
  `profiles/{model}/*.env` for the window and budget values.
  Never hard-code one in a consumer
- Messages go through `log`/`warn`/`die`. A `die` says what to do next, and names a
  `docs/` anchor when there is one

## Where facts live

Every fact has one home, chosen by how long it stays true.

| | Lifespan | Holds |
| --- | --- | --- |
| `README.md` | — | the user-facing entry point: what it is, install, use, configure |
| `AGENTS.md` | — | this file |
| `CONTRIBUTING.md` | — | the short human form of this file: the measurement rule, what gets declined |
| `docs/dev.md` | durable | the index: which file holds which reason, and where each pre-split anchor went |
| `docs/setup.md` | durable | build, toolchain, platforms, RAM and build memory, preflight, troubleshooting |
| `docs/agent.md` | durable | pi, the context budget and its arithmetic, the agent prompt, the server lifecycle, Unsloth Studio |
| `docs/agent-sessions.md` | durable | every Tron session, all models, one table plus each day's write-up. A new session is a row here |
| `docs/{bonsai,qwen36,qwen38-flash}.md` | durable | one per `MODEL`: its pin and tree, why each of its settings, its speed, window and profiles. A new model gets its own |
| `docs/performance.md` | durable | what limits generation speed: the bandwidth roofline, and the optimizations tried and rejected |
| `docs/context-window.md` | durable | the window and the KV cache for both models: what fits on 8 GB, the silent WSL2 spill, KV quality against f16 |
| `docs/localagent.md` | durable | the frozen workflow: why it is not recommended, its shape, how it runs on pi, the measured runs |
| `docs/model-comparison.md` | durable | eight local models as coding agents on 8 GB, from the study predating this repo. **Frozen**: a record of finished work. New measurements go to the file that holds the topic, or a ticket |
| `backlog/` | living | one file per ticket, `T-NNN-{slug}.md`, indexed in `backlog.md` with the `Next ticket` counter. A private one gets `.local.md` and stays out of the repo, so the numbers have gaps |
| `runs/` | ephemeral | gitignored but kept: one folder per long measurement |
| `.temp/` | ephemeral | gitignored scratch, safe to delete at any time |

Closing a ticket means its result is in `docs/` and its file is deleted. Nothing is left behind as
a note.
