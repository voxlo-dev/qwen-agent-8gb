# The localagent workflow

**Not recommended. Use `bonsai-pi` without the flag.** On this model the workflow has finished
only a toy task, and there it was no faster than the model working alone. On the one real task
measured it failed where the model alone succeeded. It is frozen since 2026-09-23 and stays in the
repo unchanged, for a stronger local model. [Status](#status) has the numbers.

A multi-agent build pipeline for a weak local model: plan gate, then one worker dispatch per
small unit (spec -> tests -> code -> test run), then e2e and docs. It lives in
[`pi/localagent-workflow/`](../pi/localagent-workflow/) and runs as `bonsai-pi --localagent`
through the extension in [`pi/extensions/localagent/`](../pi/extensions/localagent/).

The idea was context discipline, not throughput. A 27B model holds a feature badly and forgets
what it decided three turns ago, so the pipeline gives every step a tiny single-purpose context and
writes the run's memory to disk instead of the window. That costs turns, and **the turn count is
the bill** - see [Economics](#economics). On this model the bill was never paid back.

This file is the workflow's home: the shape, the measured runs, why each piece is what it is, and
why it is not recommended. The window and compaction numbers it runs inside are in
[`agent.md`](agent.md#context-budget).

## Status

**Not recommended, and frozen since 2026-09-23.** The core of this repo - `bonsai-server` and
`bonsai-pi` - is not affected. This workflow does not do what it is for on this model, and it is
no longer developed. It stays in the repo as it is, so that a stronger local model can be run
through it unchanged. No runs are planned until one is out.

| Task | Workflow, final shape | The model alone |
| --- | --- | --- |
| todo CLI: four commands over a JSON file | works on the third attempt: 0:34, 61 turns, 55k output. The two attempts before it stopped with units `BLOCKED` | works: 0:33, 22 turns, 48k (the orchestrator skipped the workflow, [see below](#the-cli)) |
| Tron: browser game, relay server | stopped at 2:50 with its first unit, the game core, unfinished; 225k output | a working game with tests: 1:30, 108 turns, 118k |

- **On a small task it buys nothing over the model alone** but a spec per unit, an e2e check and
  a README, and it took three attempts to get there once.
- **On a real task it fails, and the failures are the model's**:
  [what stopped Tron](#what-stopped-tron-the-model). No harness change moved them, and every
  prompt rule against them was ignored or checked with turns.
- **Nothing was measured on the Vulkan backend.** At 7 tok/s a run would take a working day.
- **The last harness change never ran on a real model**: a cut-off dispatch is `BLOCKED` with
  its files in place, and the scaffold checks that the test command fails on an empty suite.

[Resuming](#resuming) says what to run when a stronger model is out.

Its ancestor was evaluated across eight local models before this repo existed, and no model of
that generation produced a working artifact through it; one held the whole process. That series is
[the model comparison](model-comparison.md), and it is the most honest description available of
what a multi-agent workflow costs a local model.

## Shape

| Phase | Step | Agent |
| --- | --- | --- |
| Plan | plan with the user, **gate**, scaffold once | orchestrator, `localagent-scaffold` |
| Build, per unit | pending -> done: `spec.md`, one test per criterion, the code, the test run | `localagent-worker` |
| Finalize | one e2e flow where the plan names a surface, then the docs | `localagent-e2e`, `localagent-docs` |

The orchestrator is the session itself: pure control flow, `PLAN.md` its only write, `dispatch`
its only way to get anything built. The ledger a context reset must be survivable from is
`localagent/LOG.md`, which `dispatch` writes. The gate after a unit is the harness's too:
`dispatch` runs the test command and lists what the dispatch changed in the line it returns.

Until the Tron run this was three agents per unit - spec-architect, implementer, reviewer - and
before T-018 four, with a wall between test-author and implementer. Each cut is measured below.

## Running it on pi

The workflow is the author's own, written for OpenCode in the project thesis behind
[the model comparison](model-comparison.md), where its seven agents were run against eight local
models. On pi the protocol is the orchestrator prompt alone, which the extension puts into the
system prompt; `SKILL.md` only points at it and is no longer offered as a skill, since the
orchestrator read both copies before its first answer. No agent registration, `dispatch` as the
only way to start an agent, the template path filled in by the extension. `codegraph`, which this
setup does not have, is gone from the agent prompts; the agent frontmatter keeps the OpenCode
dialect. `install.sh pi` copies the extension with the
workflow into `$PI_AGENT_DIR/extensions/localagent/`. Without the flag the extension registers
nothing.

**Own extension, not pi-subagents.** [pi-subagents](https://pi.dev/packages/pi-subagents) 0.69.0
was tried first, installed into a scratch agent dir against a stand-in endpoint:

- Parent prompt with it: 31.3k chars (system prompt + tool schemas), without it 5.8k. The
  `subagent` tool alone is 18.9k chars, of which 13.8k is a parameter schema that none of its
  `toolDescriptionMode`s shortens; a minimal custom description still left 29.1k. The
  orchestrator needs `{agent, brief}`.
- It checks `permission:` per tool only (`read: deny`), no path globs, so it rejected the
  implementer's OpenCode block - then still a wall, see [Economics](#economics) - as an invalid
  agent definition.
- Its builtin `worker` answers to the alias `implementer`: a small model that drops the
  `localagent-` prefix would silently reach an agent that is not this workflow's.

With this extension the parent prompt was 12.3k chars against 6.8k without the flag: 764 for
the `dispatch` tool, the rest the orchestrator prompt and the skill entry - the workflow itself.
That was before T-019 folded the skill's 164 lines into a 79-line orchestrator prompt.

**Each agent is a separate `pi -p` process** (the pattern of pi's own
`examples/extensions/subagent`), started from pi's own entry point so it runs the pinned version:

- `--no-extensions --no-skills --no-prompt-templates --no-context-files`: nothing the orchestrator
  loaded reaches it, not `AGENTS.md`, not `dispatch` (no nested dispatch). The brief is its
  whole context, as the workflow demands. pi's base prompt stays: the agent prompt is appended
  (`--append-system-prompt`), since the base prompt explains the tools to a small model.
- Dispatches are queued, one at a time: the server has one slot (`--parallel 1`), and the
  workflow requires the sequential shape anyway.
- **Agents run on a second `models.json` entry, `<MODEL_ALIAS>-agent`**, the same server with
  `samplingParams` that send `reasoning_budget_tokens` = `AGENT_BUDGET` (4096) and their own
  budget message per request; the fork's server reads both from the body and falls back to its
  flags. The orchestrator keeps `BUDGET`. Why: inside a dispatched child no user message follows
  the brief, so the template keeps every earlier turn's thinking in the prompt (the
  `preserve_thinking` switch only drops thinking *before* the last user message, see
  [bonsai.md](bonsai.md#thinking-in-the-prompt)). At 8192 a child crossed pi's 48k compaction trigger
  in five or six turns, every time - the Tron numbers below.
- **A runaway dispatch is cut off after `AGENT_MAX_TURNS` (30)** and comes back as a `BLOCKED`
  tool error naming the log, with its files left in place for the next attempt, even when the
  suite is green: in the Tron run "green" was a test runner that had found no test. The prompts' own "two attempts, then escalate" rule was never once
  followed: the Tron U2 implementer ran 332 turns. It is a backstop and no prompt mentions it:
  at 15 it cut off three dispatches that were done, see
  [the T-019 CLI run](#the-t-019-cli-run-where-the-turns-went).
- **Every dispatch is snapshotted.** Before the agent starts, `dispatch` writes the work tree as a
  git tree through a private copy of the index (the user's index, HEAD and history are not
  touched). `· changed:` is the diff against it, so it names what this dispatch did, not what the
  tree holds. A failed dispatch's files stay: the next attempt starts on them with a fresh
  context. Putting them back was tried and removed, see the next point.
- **The agent's first green test run after a red one ends the dispatch as `DONE`.** Whenever
  it runs a command containing the test command, the child is paused and `dispatch` runs the
  exact command itself, so a pipe or a subset does not decide. Without it, workers that were
  green spent their last turns on checks nobody asked for, until the backstop cut them off.
- **After a `DONE`, `dispatch` runs the test command** the orchestrator passed as `test` and
  appends `· tests: green|RED (exit N): <tail>`. The orchestrator used to spend eight or nine
  turns on that gate, inventing checks as it went. Every line ends with turns and minutes.
- **`dispatch` keeps the run log**: each result line, with the unit it was for, is appended to
  `localagent/LOG.md`. The orchestrator used to keep `STATE.md` by hand, and that was 10 to 18 of
  its 34 or 35 turns in every session measured.
- The result is the agent's status line (`DONE`, `FIXES_REQUIRED`, `ESCALATE`, `BLOCKED`,
  `PASS`, `NO_SURFACE`), the last one in its final message, Markdown stripped, so a chatty reply
  does not fill the orchestrator's window. A reply without one comes back as
  `NO STATUS: <its last lines>`, with the test verdict. **Only that line comes back**, which is
  why an agent with something to say writes a file and names it. A child that ends on anything
  but `stop` - `length` included, see [Context budget](agent.md#context-budget) - or exits non-zero
  comes back as a tool error, which the workflow treats as `BLOCKED`.
- Its session goes to `sessions/{cwd-slug}/dispatch/{orchestrator-session-id}/`, beside the
  orchestrator's own log. That JSONL is written live, so a second terminal can follow what an
  agent is doing while it runs.

**The plan gate is told, not guessed.** `ctx.hasUI` goes into the orchestrator's system prompt as
a `## Session` line: a human is here, so stop and wait - or nobody is, so mark the plan
auto-approved.
In T-013 the model decided this itself and wrote "plan auto-approved - headless test run, no human
reachable" into `STATE.md` while a human sat in front of it. pi knows the answer; the model does
not.

**Flag order.** pi hands an unknown flag the next argument as its value when that argument does
not start with `-`. Extension flags count as unknown there, so `bonsai-pi --localagent "task"`
swallows the task. `--` ends option parsing and makes the rest the prompt:
`bonsai-pi --localagent -- "task"`, with or without `-p`.

Verified against a scripted stand-in endpoint that plays orchestrator and implementer: without
the flag no `dispatch` and no skill; with it the orchestrator prompt and the skill are in the
system prompt, the child has no `dispatch` and no `AGENTS.md`, and the orchestrator gets
`DONE src/foo.ts` from a reply that wraps it in prose.

## Economics

Two runs of the **same prompt** (a todo CLI: add/list/complete/remove over a JSON file, clear
failures with a non-zero exit) on the same profile (`dedicated`, CTX 64000, BUDGET 8192), one
before the rebuild and one after, then the study's Tron prompt in the T-018 shape. Scripts and
artifacts: `runs/T-013-localagent-cli/`, `runs/T-018-workflow-without-tdd/` and
`runs/T-013-localagent-tron/` (gitignored, kept), `report.sh` beside each.

| | T-018, spec -> implement -> review | T-013, TDD behind a wall |
| --- | --- | --- |
| Wall clock | 1:39:48 | 2:14:20 |
| Turns | 124 (30 orchestrator + 94 agents) | 198 (60 + 138) |
| Output tokens | 164 418 | 210 593 |
| Product / test / artifact lines | 133 / 271 / 302 | 181 / 373 / 675 |
| Rework rounds | 0 | several, one of them a 46-minute deadlock |

Both produced a working CLI. Wall clock is ~99 % model time on this machine, and only 14 of
T-013's 198 turns had to reprocess their prompt, so context reloading after a dispatch is not the
cost: **the turn count is the bill**, and every turn burns a full thinking budget.

Where the time went, per agent:

```
                          T-018      T-013
implementer               46:42      30:37
reviewer                  17:54      12:03  (as test-author)
orchestrator, between     19:57      37:05
spec-architect             9:08      22:30
docs                       3:26       9:13
scaffold                   2:38       5:23
e2e                           -      17:26
```

**The wall was the expensive part.** In T-013 the test-author wrote
`assertEqual([(1, "a", False)], json.load(f))`, which parsed JSON can never satisfy. The
implementer was not allowed to look: 23 turns and 29 minutes reconstructing the expectation from
failure output, then the spec-architect ruled `ESCALATE unfounded` - wrong, the test really was
broken - and the test-author fixed it in two minutes. 46 minutes, 34 % of the run, for a one-line
defect that is obvious on sight. That is the wall's built-in economics: it costs exactly when the
test is wrong, and a 27B model writes wrong tests often. Note which half the blindness protected -
the blind *test* was broken, the blind *code* was correct. The spec was the reliable artifact, not
the blindness.

Read the table carefully, though: **the implementer got more expensive, not cheaper** (+16 min),
because it now verifies itself, and **half the saving is an e2e step that did not run** - the
T-018 orchestrator judged a single-process CLI to have no e2e surface, where T-013's ran e2e and
produced a 317-line driver with 88 checks against a one-flow rule. Both calls are defensible under
the skill, so that 17 minutes may come back on another run. The structural savings are the
spec-architect (stubs gone) and the orchestrator (half the sub-steps, half the turns).

### The Tron run: where the three-agent shape stops

The study's prompt (an online two-player Tron game, browser client, relay server), same profile,
the T-018 shape plus the first T-019 commits, 2026-09-21/22. **Aborted after about five hours
with one of three units done.** What the session logs say, orchestrator and children:

```
                              minutes   turns   compactions
scaffold, first attempt          19       37        0   killed: fought node --test, then wrote product code
scaffold, second attempt         11       28        0
U1 spec-architect                49       20        2   spec on disk after 24 min; then 25 min of wc -l and rewrites; killed
U1 implementer                   27       21        1
U1 reviewer                      32        -        -   DONE, 8 of 8 met: no finding, as in T-018
U2 spec-architect                17       16        0
U2 implementer                  235      332       12   aborted; never escalated
orchestrator, between            28       34        0   17 turns on the two gate checks alone
```

Three mechanisms, each visible in the logs:

- **Thinking accumulates inside a child and compacts it.** Base context 3k, plus up to 8k of
  thinking per turn, trigger at 48k: the U1 spec-architect compacted two minutes after writing
  its file, the U2 implementer every fifteen minutes, its summaries growing to 19k characters and
  becoming the context. After a compaction the agent no longer knows it is done: the second U1
  summary says "task complete", and the agent reads the file again to trim five lines.
- **Rules with numbers are checked with turns.** "~80 lines" became `wc -l` five times through
  two compactions. "Two attempts, then escalate" was never followed in 332 turns. Prompt-only
  bounds do not bound this model.
- **The orchestrator restates and invents.** Its briefs (600-1000 tokens each) told the
  implementer to write tests, against that agent's prompt, so the unit got 209 lines of author
  tests and then 191 lines of reviewer tests for the same eight criteria. After each `DONE` it
  ran eight or nine turns of checks the skill did not ask for: I/O scans, test counts, commit
  juggling.

The reviewer, across every run, has now reviewed three units and found nothing, at 18, 32 and 32
minutes. That was the T-019 stop condition: "if the reviewer waves a real defect through, the
split buys nothing". It never got a defect to wave through, and it cost a third of every unit.

### The T-019 CLI run: where the turns went

The todo CLI again, on the shape the Tron run produced: one worker per unit, the harness gate,
`AGENT_BUDGET` 4096, a 15-turn limit per dispatch. Stopped after an hour with U1 and U2 done and
U3 started; T-018 had needed 1:40 for all of it. Logs: `runs/T-019-cli/`.

```
                     turns  min  result           where the turns went
scaffold, first        15   9.4  BLOCKED (limit)  2-12 unittest's exit 5 on zero tests; 13-15 a .gitignore
scaffold, second        8   3.4  no status line   read and judged what the first had left
U1 worker              10   7.5  DONE, green      3 orientation, then spec, tests, code, one run
U2 worker, first       15   6.8  BLOCKED (limit)  6 orientation; cut at its final test run
U2 worker, re-cut      15   8.1  BLOCKED (limit)  5 orientation; green at 14, cut on a "final sanity check"
U2 worker, third        3   0.6  DONE, green      found the second's code, wrote nothing
U3 worker               4   2.7  (run stopped)
orchestrator           35  ~22                    18 turns on STATE.md and PLAN.md, 5 failed edits
```

No child compacted: the agent budget did what it was for. Its full 4096 went into the first or
the spec-writing turn of each dispatch, 130 to 160 seconds; the other turns were short.

What the logs show, against what the reshape assumed:

- **The limit fired on finished work.** None of the three `BLOCKED`s was a unit too large. The
  first scaffold had its layout by turn 12, the first U2 was at its final test run, the second
  was green. Each cost a re-cut or a retry, and the third U2 came back `DONE` green in 34 seconds
  on what the two before it had left on disk.
- **The spec -> tests -> code -> run core is five to seven turns.** Every worker that reached it
  held the order. The rest of a dispatch was orientation before it (the spec template, `ls`, the
  scaffold's placeholder test, the e2e driver, `PLAN.md`, `STATE.md`, although the prompt said to
  read nothing else) and a check after green that nobody asked for.
- **The ledger was the orchestrator's largest cost.** Across the three orchestrator sessions
  measured (Tron, the T-019 gate test, this run), 10 to 18 of 34-35 turns read, wrote or edited
  `STATE.md` or `PLAN.md`; exact-match edits against a file the model had written itself failed
  five times in this run. It also checked its own ledger: it wrote a test count, then ran the
  suite to verify it.
- **A requirement the toolchain cannot meet costs a whole dispatch.** "Green on zero tests" is
  exit 5 under Python 3.14's unittest. The scaffold went into the stdlib's source to find out why,
  and its placeholder test then sat in every later worker's orientation.
- **Briefs still carried rules** ("decided, no guessing", "only create this exact layout"), and the
  second scaffold, asked in its brief for a report, never wrote a status line.

The model is not ignoring its instructions; it over-attends to everything in reach, rules and files
alike, and checks them with turns. So the shape after this run takes things away rather than adding
bounds: the limit leaves the prompts and becomes a backstop, the ledger and the spec template go,
a failed dispatch leaves nothing behind to read, and the worker and scaffold prompts keep their
steps and lose the rest (539 lines of prompts and templates before, 296 after).

## The pieces, and what each one is answering

- **One worker per unit: spec, then tests from its criteria, then code.** The three-agent split
  bought one thing, tests that say what was asked for instead of what was built, and the Tron run
  priced it at two extra dispatches per unit for a reviewer that has never found anything. The
  order survives inside one context: the worker writes `spec.md` (interface in prose, three to
  five criteria), then a test per criterion, then the code. T-018 had already found that the spec
  was the reliable artifact, not the blindness; T-013 had shown what a wall costs when the blind
  test is wrong (46 minutes, a third of the run).
- **`spec.md` in prose, no stub files, no line count, no template file.** Stubs existed only to
  make two blind halves agree on a signature, at 7-10 minutes per unit. The "~80 lines" cap cost
  the Tron spec-architect 25 minutes of `wc -l`. The spec's two sections are named in the worker
  prompt, and no prompt in the workflow carries a number the model could check with a tool.
- **The gate is the harness.** `dispatch` runs the tests after a `DONE` and lists what the
  dispatch changed. The orchestrator's version of that gate was 17 turns per unit in the Tron run.
- **The ledger is the harness's too.** `LOG.md` is written by `dispatch`; the orchestrator writes
  `PLAN.md` and nothing else. By hand, the ledger was up to half the orchestrator's turns.
- **A failed dispatch is not reverted.** Reverting was meant to keep a retry from passing the gate
  on inherited work, which the per-dispatch `changed:` already shows. In practice it threw away a
  green U2 that the backstop had cut off before its status line, and in the Tron run it deleted
  half of `node_modules` under a scaffold whose install the backstop had cut off. A retry starts
  on what is there, with a clean context.
- **The turn limit is a backstop, not the escalation rule.** 30 turns, enforced by the extension,
  in no prompt. At 15 it cut off finished work three times in one hour.
- **Units are one file and three to five criteria**, because that is what one dispatch builds
  cleanly. The Tron plan had three units for a game; the same plan is eight or nine.
- **One failure rule.** Green goes on; a toolchain or contract gap is routed; anything else gets
  one more dispatch; a unit's second failure stops the run. The five-row table before it cost the
  orchestrator turns of interpretation.
- **Agents think with 4096, the orchestrator with 8192.** The child's context is the brief plus
  its own thinking, and at 8192 the thinking alone filled the window in five turns.
- **Briefs are facts, not rules.** Working directory, commands, the plan entry and interface
  lines inline, paths. The prompts hold the rules; a brief that restates them is where the Tron
  orchestrator started inventing its own.
- **Nothing is enforced *in the prompts*.** `wall.ts`, the `permission.read` blocks and the
  brief-path allowlist are gone since T-018, the turn budgets of e2e and docs since T-019. What is
  enforced is enforced by the extension: the turn limit, the agent budget, the test run, the
  log. Those are checks the workflow demanded anyway, moved from the model into code
  because the model did not hold them, and did hold them at a cost in turns where it tried.

## The T-019 runs: why it is frozen

T-019 ran the shape above on the todo CLI and on Tron, 2026-09-22/23, and changed the harness four
times along the way. Same profile throughout (`dedicated`, CTX 64000, BUDGET 8192,
AGENT_BUDGET 4096), on the RTX 4060 Ti. Logs: `runs/T-019-cli/`, `runs/T-019-cli-2/` (`work-solo`,
`work-2`, `work`) and `runs/T-019-tron/` (`work-1`, `work`), each with its `run.sh` and reports,
gitignored and kept on that machine.

| Run | Result | Wall | Turns | Output |
| --- | --- | --- | --- | --- |
| CLI, the model alone | works, 31 checks | 0:33 | 22 | 48k |
| CLI, workflow, 15-turn limit | stopped, 2 of 3 units | 1:00 | 105 | 106k |
| CLI, workflow, with revert | stopped, 2 of 5 units | 0:49 | 96 | 77k |
| **CLI, workflow, tests decide** | **works, no `BLOCKED`, e2e `PASS`, README** | **0:34** | 61 | 55k |
| Tron, `bonsai-pi` alone (T-002) | a working game with tests | 1:30 | 108 | 118k |
| Tron, workflow, attempt 1 | stopped: the revert broke `node_modules` | 0:34 | 68 | 58k |
| **Tron, workflow, attempt 2** | **stopped, the game core not finished** | 2:50 | 123 | 225k |

### The CLI

**The solo baseline came by accident.** On the first try after the second reshape the
orchestrator skipped the workflow: its first reasoning quotes the plan gate, then it read "this is
a test environment" as a benchmark, called the task small, and built `todo.py` with a 31-check
test script alone. No dispatch, no `PLAN.md`; "you write `localagent/PLAN.md` and nothing else"
did not hold it. Every later run added one closing line to the prompt, "Use the localagent
workflow for this task." That run is the number the workflow has to beat.

**With the revert**, stopped at 0:49 with two of five units. Neither `BLOCKED` was a unit too
large. The first U2 attempt had 26 tests green at turn 26, spent four turns on checks nobody asked
for, wrote no status line, was cut off at 30 and reverted: a finished unit thrown away, the third
time a green dispatch had been cut off. The re-cut spent 14 turns on why unittest did not find a
test class that lacked `unittest.TestCase`. Both lost turns to a plan error, `todo.py` next to a
package `todo/`. That run is why the tests, not the status line, now end a dispatch.

**Tests decide**: the first clean run. Two units instead of five, no scaffold (stdlib only),
e2e `PASS`, a README; unknown commands, a missing id and a corrupt store all fail with a clear
message and exit 1. The orchestrator spent 4 of its 20 turns on the ledger, down from 18; the
first write in a worker came at turn 3 and 2, down from 4 to 7. One worker of two broke the
order: U1 wrote `spec.md` and the code in one turn, the tests after, so they were never red and
the green-after-red rule had nothing to fire on. The order is in the worker prompt in words.

### Tron

**Attempt 1**, stopped at 0:34. The scaffold hit the 30-turn backstop during a long Playwright
install and was reverted. The snapshot had caught the install's files as the dispatch's own, so the
revert deleted `package.json`, the config and the lockfile, and left `node_modules` half removed.
The orchestrator split the scaffold in two to fit the limit. The revert was removed before the
restart.

**Attempt 2**, stopped at 2:50. The plan had three units, not the eight or nine the run asked
for, and passed the gate. The core was re-cut twice, U1 -> U1a/U1b -> U1b-a/U1b-b, and every
dispatch took 40 to 60 minutes. Two things were the harness:

- A result line that said "ran 30 turns" beside a green suite. The orchestrator's rule "a
  dispatch that ran out of turns: split the unit" won over the `DONE`, and it re-cut twice,
  noting "contradictory signals".
- The green was hollow. The test command was `node --test`, which does not pick up `*.spec.mjs`
  and exits 0 when it finds no test at all, so a syntax-broken test file read as green.

### What the harness got wrong, and fixed

In commit order, all on the shape described in [Running it on pi](#running-it-on-pi):

1. **The tests decide, not the status line.** The agent's first green run of the test command
   after a red one ends the dispatch as `DONE`; the harness pauses the child and runs the exact
   command itself. It fired once in each of the two runs after it. The trigger depends on the
   stack: the agent's command must contain the test command as written (whitespace ignored), so
   `npm test -- foo` matches `npm test`, and `npx jest`, or a bare `pytest` against
   `python3 -m pytest`, does not. Then the dispatch ends the old way.
2. **No revert.** It threw away a green unit and broke a dependency tree. What it guarded
   against, a retry passing the gate on inherited work, the per-dispatch `changed:` already
   shows.
3. **The budget message asks for one tool call** (`BUDGET_MSG` in `config.env`, for every
   session on the server). "Write the files with your tools", read after a cut-off thinking
   block, led the orchestrator to write a test file next to its plan.
4. **A cut-off dispatch is `BLOCKED`, whatever the suite says; no split rule for it; the scaffold
   proves the test command fails on an empty suite**, and hands the final command back on its
   result line. `pytest`, `unittest` (3.12+), `jest`, `vitest` and `mocha` fail on an empty suite;
   `node --test` does not. The split rule was left over from the idea that a cut-off unit is too
   large, which the [CLI logs](#the-t-019-cli-run-where-the-turns-went) had already disproved.
   Verified against a scripted stand-in endpoint only.

### What stopped Tron: the model

From the Tron worker sessions:

- **About two minutes and 4k to 9k output tokens per turn.** Whole test files are rewritten,
  9k tokens each, and game ticks are simulated by hand in the thinking to derive expected
  positions.
- **A compaction every 10 to 12 turns inside a worker, seven in all.** After one the worker no
  longer knows what is on disk: U1 "found" a `units/U1/game.js` that did not exist, and argued
  with itself for four turns about whether its own write had landed.
- **Edits that do not match, then full rewrites.** Syntax errors in its own tests (an apostrophe
  in a test name, missing brackets), then turns spent finding them.
- **Test-runner discovery took 15 turns** in U1b and several in U1a, which ran experiments on
  Node's test discovery.
- **U1 deleted the scaffold's `tests/e2e.mjs`** in its sixth turn.

Smaller units would have lowered the context pressure; they would not have removed any of these.
None is a harness decision, and every rule added to a prompt so far was either ignored or checked
with turns. Where units are small and the logic trivial, the workflow works and gains nothing;
where one unit needs real reasoning, it does not work. The model alone, with its whole context,
built the same game in half the time.

## Resuming

Only with a stronger local model; nothing in these runs suggests more harness work would change
the result for this one.

1. `./install.sh pi`, then rerun `runs/T-019-cli-2/run.sh` and `runs/T-019-tron/run.sh` as they
   are. Both check the installed shape. The work dir needs its own `git init`: the snapshot needs
   a repo, and without one `changed:` describes whatever repo encloses it (T-018's `changed:`
   lines were never about its own work dir).
2. The first thing to read off is harness change 4, which has not run on a real model.
3. Compare against `bonsai-pi` alone on the same model, not against the numbers above: the
   workflow is worth recommending only if it beats the model working alone on Tron.
