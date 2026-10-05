# T-044 — Rebranding: Qwen for 8 GB VRAM, the model chosen by the RAM next to the card

- **Summary:** Done in the repo on 2026-10-04: Qwen3.6 the default, `qwen-server`/`qwen-pi`/`qwen-studio` (the `bonsai-*` names gone at once), `QWEN_HOME` with an existing `bonsai-local` kept in place, `install.sh` asking for the model by RAM and recording it in `model.env`, preflight reporting which models the RAM runs, a new README, T-035 folded into T-050. Left: the GitHub rename and a fresh clone
- **Category:** feature
- **Importance:** high
- **Effort:** S (what is left)
- **Depends on:** none

## Why

T-041 (2026-10-02, [agent-sessions.md](../docs/agent-sessions.md#second-day-c2-w-b2)): both Bonsai
sessions ran past 90 minutes without a working game; Qwen3.6 built and browser-tested one in 18.
The README now leads with the RAM ramp ([README.md](../README.md#which-model)).

## What is left

1. **Repo rename on GitHub**, by the author, after this branch is merged and pushed:
   `voxlo-dev/bonsai-agent-8gb` → `voxlo-dev/qwen-agent-8gb` (Settings, General, Repository name).
   GitHub redirects the old URL. Then `git remote set-url origin git@github.com:voxlo-dev/qwen-agent-8gb.git`.
   The README's clone lines already name the new repo, so they 404 until the rename.
2. **A fresh clone on a 32 GB machine** (or a VM): `./install.sh` asks, recommends Qwen3.6, ends
   with it; `qwen-pi` starts it; `MODEL=bonsai ./install.sh` installs next to it without touching
   `model.env`. Each step twice for idempotence. Checked so far only in a scratch `QWEN_HOME`
   without the build and model steps.

Then this file is deleted.
