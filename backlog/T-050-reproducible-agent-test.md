# T-050 — A reproducible agent test in place of the single Tron session

- **Summary:** Replace "one Tron session per model, judged by hand" with a set of fixed coding tasks that each come with a checker, run several times per model and harness, and reported as pass rate, time and steps. The Tron sessions no longer separate the candidates: the outcome of one is close to chance, and the things this repo decides (model, template, fine-tune, harness, budget) move it less than its variance
- **Category:** spike
- **Importance:** high
- **Effort:** M (the task set and runner first; then a day of runs per comparison)
- **Depends on:** none. Feeds the README's recommendation (Qwen3.6 since T-044, on n = 1 sessions). Absorbs T-035 (item 6)

## Why

Over nine Tron sessions ([agent-sessions.md](../docs/agent-sessions.md)): Bonsai built a working
game in a first, undocumented run and never again; Qwen3.6 went from a game with a broken rematch
(B) to one tested end to end in 18 minutes (B2); Qwen3.8-Flash from a working game in 54 minutes
(D) to sessions that never ended (E, ES). n = 1 at temperature 1.0, one open prompt, a result
judged by hand, and a session that can lose an hour to one wrong turn. Sharp (ES) and Swift (W)
each moved little against that; the harness moved a lot (the author: Qwen3.6 clearly better in pi
than in OpenCode), and so did failures outside the model (the T-049 crash, hung tools).

## What

To decide before building it:

1. **Tasks**: small enough to finish in 10-20 minutes at ~12 tok/s (Flash), several of them, each
   with a hidden checker the agent does not see (tests run after the session, in a clean copy).
   Kinds worth covering: a bug fix in an existing small repo, a feature with a spec, a CLI tool from
   scratch, one multi-file web task with a browser check. The Tron prompt can stay as one of them,
   with a checker (two headless clients log in, host, join, play a round).
2. **Runs**: N per task and configuration (3-5), fixed seed where the server takes one, temperature
   as shipped. Cap per task. No human input: the follow-up becomes part of the prompt or goes away.
3. **Report**: pass rate per task, time and steps to pass, tokens, interventions (crash, timeout),
   from the session JSONL and the checker. A script, in `runs/` first, in the repo if it earns it.
4. **Sharp on Qwen3.8-Flash** (T-046): ES against E was clearly better on process, ended on its
   own in 89 steps against 198, in one pair. A pass rate with and without the template decides
   the `CHAT_TEMPLATE_FILE` setting (opt-in per model, the file pinned under `templates/`,
   Apache-2.0 with attribution). Also on Qwen3.6, which the template is written for.
5. **Harness as a variable**: pi as shipped against OpenCode (and the localagent workflow?) on the
   same server, so "the harness matters more" becomes a number.

6. **The study's own harness** (was T-035, closed 2026-10-04): the study's prompt and follow-up in
   OpenCode, as its table ran ([model-comparison.md](../docs/model-comparison.md)), so a model of
   this repo lands in that table. T-035 planned it for Bonsai, twice; with Qwen3.6 the default it
   belongs here, as one harness of item 5, for whichever models the task set keeps.

Open: whether an existing benchmark harness (SWE-bench-style, terminal-bench, Aider's) fits better
than a home-made set; how long a full run may take on one machine.
