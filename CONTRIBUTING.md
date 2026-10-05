# Contributing

One maintainer, evenings and weekends. Expect a slow but real reply.

## The one rule

**A non-default choice arrives with the measurement that justifies it.**

This repo is short. Five bash scripts, a config file and two launchers. Its actual product is the
set of reasons in `docs/` ([`docs/dev.md`](docs/dev.md) says which file holds what): why the KV cache is `q8_0`/`q4_0`, why `--fit` is
off, why the thinking budget is 8192, why the context window is 64k and not 80k. Every one of those
answers a failure that was observed and measured on real hardware.

A pull request that changes a flag without saying what it does to tok/s, VRAM or the context budget
cannot be reviewed, because there is nothing to review it against. So:

- A new or changed setting comes with an entry in the `docs/` file for its topic, and the number behind it.
- Say what you measured it on: card, backend, driver version, distro, context size.
- A change that makes something faster states the before and after from the same machine in the
  same session.

## Verifying a change

There is no test suite. Adding one was considered and declined: it is bash, there is no framework,
and what actually breaks is behaviour under a real model on a real card. Verify by observation
instead.

| Change | How to see it worked |
| --- | --- |
| Server flags | start it, query `http://127.0.0.1:8080/props`, or render a conversation through `/apply-template` |
| Vulkan kernels | a generation and prompt measurement at a stated window, judged by tok/s; VRAM is misleading, RADV only reports it meaningfully after the first request |
| pi's config | read back `$QWEN_HOME/pi-agent/models.json` and `settings.json` |
| pi's behaviour | its session logs, JSONL under `$QWEN_HOME/pi-agent/sessions/`, one entry per message with token counts and compaction records |
| Any script | `bash -n` on it, and run the step twice to confirm it is still idempotent |

## Conventions

- POSIX-ish bash, `set -euo pipefail` through `scripts/lib.sh`; `bin/qwen-server` sets it itself.
- A comment block at the top of every script saying what it does and what it needs.
- Settings are declared in `config.env` only, or in `models/*.env` and
  `profiles/{model}/*.env` for per-model pins and flags and the window and budget
  values. Never hard-code one in a consumer.
- Every install step stays idempotent: check whether the work is done, exit early if it is.
- Nothing is installed into the repo, and nothing into the user's own tools. No global npm package,
  nothing under `~/.pi`.
- `SPDX-License-Identifier: MIT` at the top of new scripts.

[`AGENTS.md`](AGENTS.md) is the full version of this, and is also what an AI coding agent working
in this repo should read first.

## Moving a pin

`LLAMA_COMMIT`, `MODEL_REV`, `MODEL_SHA256` and `PI_VERSION` in `config.env` are deliberate. They
exist because the model needs a fork that mainline llama.cpp has not absorbed, and because the
context budget was measured against one specific version of pi's compaction code.

Moving one means re-testing: the model loads, generation speed is unchanged, `patches/` still
applies (`build` refuses when it does not), and for `PI_VERSION`, that the compaction behaviour in
[`docs/agent.md#context-budget`](docs/agent.md#context-budget) still holds. Say in the PR which of those
you checked.

## The three things most worth sending

1. **A hardware report.** Any 8 GB card that is not an RTX 4060 Ti or an RX 570. Card, backend,
   driver, distro, `CTX`, generation and prompt tok/s, and whether the 64k profile fits. There is
   an issue template for it.
2. **A failure with its log.** The last 30 lines of `$QWEN_HOME/server.log` or the build log say
   more than a description does.
3. **Vulkan kernel work.** The `PTQ1_0` decode currently looks each byte up five times per token
   and sits about 3x off what the card's memory bandwidth allows. A dedicated `mul_mat_vec` shader
   is the open piece.

## What will probably be declined

- A test framework.
- Changing one of `CTX`, `BUDGET`, `MAX_TOKENS`, `RESERVE_TOKENS` or `KEEP_RECENT_TOKENS` on its
  own. They constrain each other arithmetically and move together, in a profile.
- Support for ROCm, Metal or CPU-only inference. Two backends is what one person can keep measured.
- A native Windows port. WSL2 is the Windows path and the reference platform for every CUDA
  number here; a PowerShell second implementation of the install and of the server lifecycle is
  more than one person can keep measured. The reasoning is in
  [`docs/setup.md#windows`](docs/setup.md#windows).
- Installing anything into `~/.pi` or as a global npm package.

## Code of conduct

Be civil and assume good faith. That is the whole of it.
