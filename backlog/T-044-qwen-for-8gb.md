# T-044 — Rebranding: Qwen for 8 GB VRAM, the model chosen by the RAM next to the card

- **Summary:** The repo's core claim, Bonsai as a coding agent on 8 GB, did not hold up on the second Tron day; Qwen3.6 gave the best result yet. New framing: an 8 GB card plus system RAM, three models on a ramp (+0 GB Bonsai for simple tasks, +32 GB Qwen3.6 recommended, +64 GB Qwen3.8-Flash strongest). Qwen3.6 becomes the default, the commands become `qwen-server`/`qwen-pi`, preflight reads the RAM and the user picks the model, a new README, the repo renamed. Bonsai stays, in the background
- **Category:** feature
- **Importance:** high
- **Effort:** L (touches every entry point; the rename is outward-facing)
- **Depends on:** none. T-035 is re-scoped by it (below)

## Why

T-041 (2026-10-02, [agent-sessions.md](../docs/agent-sessions.md#second-day-c2-w-b2)):
both Bonsai sessions ran past 90 minutes without a working game; Qwen3.6 built and browser-tested
one in 18. Bonsai's case was "the strongest coding agent that fits entirely on 8 GB", and the
measurements no longer carry "coding agent" for anything but small tasks. What does carry is the
card plus RAM: the MoE models keep their experts in system RAM, and how much RAM there is decides
which one runs.

## The ramp

| RAM next to the 8 GB card | Model | Role | From the model files |
| --- | --- | --- | --- |
| +0 GB (any) | Bonsai, `MODEL=bonsai` | simple tasks, everything on the card | `MODEL_RAM_MB` 0, 5.8 GB disk |
| +32 GB | Qwen3.6, `MODEL=qwen36-35b` | **recommended, the default** | `MODEL_RAM_MB` 24000, 21.7 GB disk |
| +64 GB | Qwen3.8-Flash, `MODEL=qwen38-flash` | strongest, experimental | `MODEL_RAM_MB` 46000, `MODEL_RAM_FULL_MB` 58000, 89.4 GB disk |

The thresholds are machine sizes, not model sizes: 32 GB is what a desktop with Qwen3.6's ~24 GB in
RAM and a browser still works with; 64 GB is what keeps Flash's experts cached (native Linux, lean
desktop, [qwen36.md](../docs/qwen36.md#native-linux)).

## What

1. **Qwen3.6 the default**: `config.env` `MODEL:=qwen36-35b`. `pi-agent/` then belongs to Qwen3.6
   and Bonsai gets `pi-agent-bonsai/`, or every model gets its own suffix: decide, and give
   existing installs a way across (a one-time move in `install.sh pi`, or a note).
2. **The model chosen by the user, with the RAM as the guide.**
   - `scripts/preflight.sh` reads MemTotal/MemAvailable and reports the ramp: which of the three
     fits, which is recommended here. It stays a gate per model as now (`MODEL_RAM_MB`,
     `MODEL_RAM_FULL_MB`).
   - `install.sh` without `MODEL` on a terminal asks once, defaulting to the largest that fits up
     to Qwen3.6; not on a terminal it takes the default. The choice is written to
     `$HOME_DIR/model.env` (or similar) and read by `config.env` after the environment, so
     `qwen-pi` and `qwen-server` use it without `MODEL=` every time. The environment still wins.
3. **Commands**: `bin/qwen-server`, `bin/qwen-pi`, `bin/qwen-studio`. The `bonsai-*` names stay
   one release as thin wrappers that warn, or go at once (no users beyond the author known):
   decide. `install.sh link` links the new names.
4. **The home directory**: `BONSAI_HOME` (`~/.local/share/bonsai-local`) holds builds, models and pi
   configs worth ~120 GB on this machine. Either keep the variable and path under the new name as an
   alias (`QWEN_HOME`, falling back to an existing `BONSAI_HOME`), or rename with a move. Never
   re-download.
5. **README new**: lead with the ramp and Qwen3.6; the measured agent sessions as evidence;
   Bonsai as the "nothing but the card" option with its limits stated plainly. The study in
   `docs/model-comparison.md` stays frozen. `AGENTS.md`, `CONTRIBUTING.md`, the docs' headings
   (`docs/qwen36.md` is "Second model" today) and the issue templates follow.
6. **Repo rename** on GitHub (`voxlo-dev/bonsai-agent-8gb` → a name to pick, e.g.
   `qwen-agent-8gb`): GitHub redirects the old URL; the local clone's remote and the README's
   clone line change. Outward-facing: the last step, after the rest is merged, by the author.

## Open

- **T-035** was Bonsai's quality claim through OpenCode. Re-scope to Qwen3.6, the new default, or
  close it: the author's call before this ticket closes.
- The names: repo, `*_HOME`, the pi dir layout (items 1, 4, 6).

## Done when

A fresh clone on a 32 GB machine runs `./install.sh` and ends with Qwen3.6, `qwen-pi` starts it,
preflight says which model the RAM allows, and `MODEL=bonsai ./install.sh` still works. Each step
twice for idempotence; an existing install under `BONSAI_HOME` keeps working without a download.
