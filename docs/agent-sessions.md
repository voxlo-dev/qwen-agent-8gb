# Agent sessions

The evidence for which model does what: the study's Tron prompt in a plain `bonsai-pi` session,
one row per session, every model on the same protocol. Per-model settings are in
[bonsai.md](bonsai.md), [qwen36.md](qwen36.md) and [qwen38-flash.md](qwen38-flash.md); the pi
budget these sessions run under in [agent.md](agent.md#context-budget).

## The protocol

A fresh directory, the study's prompt verbatim from [model-comparison.md](model-comparison.md)
as the first message, the bare `Test it and get it to work.` once when the model says it is done,
no other input. Judged by hand: does it start, can two browsers log in, host and join, does a
round play, does rematch work; and the process: did it end on its own, did it run the product
itself, does its summary separate what it ran from what it did not. Since 2026-10-02 with a cap
of 90 minutes of wall time and `LC_ALL=C.UTF-8`. Scripts (`session.sh`, `watch.sh`,
`evaluate.sh`) and logs: `runs/T-035-bonsai-measured/day/` on the 4060 Ti machine. n = 1 per
row at temperature 1.0: a reading, not a ranking.

## All sessions

| Session | Date, OS | Model, window | Duration | Ended on its own | Result |
| --- | --- | --- | --- | --- | --- |
| 64k budget run | 2026-09-19, WSL2 | Bonsai 64k | 91 min | yes | server + client + two integration tests, working ([agent.md](agent.md#context-budget)) |
| A | 2026-09-26, WSL2 | Bonsai 96k | 158 min, aborted | no | host/join fails |
| B | 2026-09-27, WSL2 | Qwen3.6 131k | 36 min | yes | runs; winner not shown, rematch broken |
| C | 2026-09-27, WSL2 | Bonsai 64k | 63 min | yes | runs, turn-based; rematch broken |
| D | 2026-09-29, WSL2 | Qwen3.8-Flash 131k | 54 min | yes | runs, rematch works; small UI bugs |
| C2 | 2026-10-02, native | Bonsai 64k | 93 min, cap | no | well below the first day |
| W | 2026-10-02, native | Swift-Bonsai-2 64k, no agent prompt | 126 min, stopped | no | marginally better than C2 |
| B2 | 2026-10-02, native | Qwen3.6 131k | 18 min | yes | **runs, browser-tested end to end** |

## First day: A, B, C, D

### A and C: Bonsai 96k against 64k

**96k, tried on 2026-09-26/27** (T-035's behaviour day). The window from
[context-window.md](context-window.md#bonsai-windows-on-8-gb), `CTX` 96000 at `q4_0`/`q4_0` with
`KEEP_RECENT_TOKENS` 16000 and the rest as `dedicated`, against the shipped 64k as the control. The
Tron prompt, plain `bonsai-pi`, fresh directories; the 96k session ran a day before the control.
Logs and `evaluate.sh`: `runs/T-035-bonsai-measured/day/` on the 4060 Ti machine.

| | 96k, `q4_0`/`q4_0` | 64k, shipped |
| --- | --- | --- |
| Steps / duration | 163 / 158 min, aborted | 70 / 63 min |
| Ended | no | on its own, in its first turn |
| Compactions | 3, at 80.1-80.5k | 3, at 48.3-48.9k |
| Context after one | 23-30k | 19-21k |
| `length` stops / steps at the budget | 0 / 0 | 0 / 0 |
| Largest thinking block | ~6.3k | ~6.9k |
| tok/s per step, median, incl. prompt | 21.9 | 25.7 |
| Result | host/join fails ("game not found") | runs, but turn-based, which makes it barely a game; rematch broken |

**The arithmetic held at 96k.** The trigger sat at 80k as planned, compactions came back at
23-30k, and the peak of 80.2k stayed inside the 95k verified clean. What went wrong was the process:
the game was written in 20 minutes, then the model built its own test harness, a headless DOM in
Node's `vm`, and spent from minute 58 to ~108 on one nested-quote escape in it (with `xxd`, `cmp`
and scratch files), and the next 50 minutes on the harness again. It never went back to the game.
Nothing in the log points at the window, so **64k stays `dedicated`**; the second 96k pair
planned for T-041 was cut (below), which makes 64k final. The harness rabbit hole is also what the
[agent prompt](agent.md#the-agent-prompt) now speaks to.

The control is a reading on variance as much as on 64k: the same profile and prompt that built a
working server-authoritative game on 2026-09-19 (the 64k budget run in
[agent.md](agent.md#context-budget)) built a turn-based
one here. That is what n = 1 at temperature 1.0 is worth.

### B: Qwen3.6

T-035's behaviour day, 2026-09-27, on the 4060 Ti with the `dedicated` profile as shipped: the
study's Tron prompt in a plain `bonsai-pi` session, next to two Bonsai sessions on the same prompt
([above](#a-and-c-bonsai-96k-against-64k)). Logs: `runs/T-035-bonsai-measured/day/` on that machine.

| | |
| --- | --- |
| Wall time / steps | 36 min / 101; the first "done" after 7 min and 22 steps |
| Output tokens | 60 114 |
| Compactions | none: peak context 76.8k, against the trigger at 99k |
| `length` stops | 0 |
| Largest thinking block | ~1.5k tokens (est.), so `BUDGET` 16384 was never reached |
| tok/s per step, median, incl. prompt | 33.1 |
| Result, judged by hand | **runs**: two browsers log in, host and join, a round plays. The winner is not shown, and rematch does not work |

The second message was a bug report on exactly those two ("The winning player is not displayed
and rematching does not work. Test it and get it to work."), not the study's bare follow-up. The
model wrote 11 tests and fixed two bugs by its own account; rematch still did not work.

The best and the fastest of the day's three sessions, at n = 1. Against the study's run of this
model (OpenCode, 64k, >60 min, three compactions, the canvas does not load) it differs in harness,
window and MTP at once, so it shows what this setup does, not which change did it. Its thinking
stayed short without the budget ever cutting it, unlike Bonsai, which drafts whole
implementations in its thinking when nothing stops it ([bonsai.md](bonsai.md#reasoning)).

### D: Qwen3.8-Flash

Session D of T-035's behaviour day, 2026-09-29, under WSL2 (50 GB, so ~10 tok/s with the SSD in
the loop), `dedicated` as shipped plus `-t 7`: the study's Tron prompt in a plain `bonsai-pi`
session, the same protocol as [Qwen3.6's](#b-qwen36). The session file stayed in the
WSL2 distribution; the numbers are from the server log, `runs/T-035-bonsai-measured/day/server-D.log`.

| | |
| --- | --- |
| Wall time / requests | 54 min / 32 |
| Output tokens | 22 261, the largest turn 3 134 |
| Compactions | none: peak context 28.9k, against the trigger at 99k |
| Truncated or `length` stops | 0 |
| tg per request, median | 9.7 (7.4-10.1) |
| Result, judged by hand | **runs**, and rematch works; small UI bugs |

So the prompt cost that looked like the problem did not come up: 32 requests, a context that never
passed 29k, and no turn near `BUDGET` 8192. At ~10 tok/s the session took under an hour. n = 1,
and under WSL2. The native session (T-041's E) was cut: Qwen3.8-Flash stays experimental
whatever one more session shows, so it would have decided nothing.

## Second day: C2, W, B2

### C2 and W: Bonsai and Swift-Bonsai-2

**The second day, 2026-10-02 (T-041), native Linux.** The same protocol, with a cap of 90 minutes
of wall time per session, because Bonsai sessions had been running two hours and longer. C2 is the
shipped 64k with the new [agent prompt](agent.md#the-agent-prompt); W is the same with
[Swift-Bonsai-2](bonsai.md#swift-bonsai-2) in place of the GGUF and no `AGENTS.md`. Logs and `evaluate.sh`:
`runs/T-035-bonsai-measured/day/` on the 4060 Ti machine.

| | C2: Bonsai 64k, agent prompt | W: Swift-Bonsai-2 64k, no prompt | C (2026-09-27) |
| --- | --- | --- | --- |
| Steps / duration | 86 / 93 min, stopped at the cap | 87 / 126 min, stopped | 70 / 63 min |
| Ended | no, never said done | no, never said done | on its own |
| First run of the product | minute 56 | minute 55 | |
| Compactions | 4, at 48.4-50.4k | 4, at 48.8-52.3k | 3 |
| Context after one | 21.7-27.1k | 19.8-25.6k | 19-21k |
| `length` stops / steps at the budget | 0 / 0 | 0 / 0 | 0 / 0 |
| Output tokens | 124 447 | 143 822 | |
| Thinking per step, median / largest (est.) | ~170 / ~7.2k | ~110 / ~6.9k | ~6.9k largest |
| Thinking in all (est.) | ~66k | ~70k | |
| tok/s per step, median, incl. prompt | 25.9 | 24.9 | 25.7 |
| Result | well below the first day | marginally better than C2 | runs, turn-based, rematch broken |

Both wrote code for most of an hour before they first ran anything, and spent the rest on test
setups of their own. C2 lost its last 30 minutes to one shell trap: `pkill -f 'node server.js'`
in the same command line as `node server.js` matches the shell running that line and kills it,
so the server it had just started "vanished" again and again; under the shell's German locale the
resulting `ls` error ("Zugriff auf … nicht möglich") also read like a permission problem. From W
on, sessions run with `LC_ALL=C.UTF-8`. W built a game split into server, client and two test
scripts, then debugged a test that never returned; the operator aborted two hung tool calls and
typed `Resume.` twice, and let it run past the cap in the hope it would finish. It did not.

What it decides:

- **64k is final for `dedicated`.** The second 96k pair (A2) was cut before the day: A failed on
  its own test harness, not on the window, and a pair costs ~4 hours. Nothing on this day points
  at the window either: neither session came near a `length` stop.
- **Bonsai in a long agent task falls short of what the earlier runs suggested.** Both earlier
  64k sessions on this prompt ended on their own with a game that runs (2026-09-19, C); C2 and W
  did not. At ~25 tok/s and an hour of writing before the first run, one wrong turn costs the
  session. The Qwen3.6 session of the same day,
  same prompt, finished in 18 minutes with a working, browser-tested game
  ([below](#b2-qwen36)).
- **Sharp (T-031) was not run.** Its point was shorter thinking before a tool call, which this
  model does not take from instructions ([Reasoning](bonsai.md#reasoning)); Swift was the stronger test of
  the same idea, and it did not move the session either. The pinned template and its render
  comparison are in `runs/T-041-tron-day-2/`.

### B2: Qwen3.6

**The second reading (B2, T-041, 2026-10-02)**, native Linux, the shipped profile with the new
[agent prompt](agent.md#the-agent-prompt), default threads, the same day as two Bonsai sessions
that did not finish in 90 minutes ([above](#c2-and-w-bonsai-and-swift-bonsai-2)):

| | |
| --- | --- |
| Wall time / steps | 18 min / 96; the first "done" after 9 min and 51 steps |
| First run of the product | minute 3 |
| Output tokens | 40 248, the largest turn 6 388 |
| Compactions | none: peak context 54.1k, against the trigger at 99k |
| `length` stops | 0 |
| Thinking, largest block / in all (est.) | ~500 / ~5.9k tokens |
| tok/s per step, median, incl. prompt | 42.2 |
| Result, judged by hand | **runs, the best result of this model so far**: a working game, bugs fixed along the way |

It started its server within three minutes and tested it over WebSockets from the shell while it
wrote, then said done. The second message was `Test it end to end.` rather than the study's bare
follow-up: it found the Playwright Chromium on the machine, wrote a browser test for two players,
fixed the bugs it found that way in the client, and reported 31 of 31 checks from login through game over; its
summary says which were browser checks. Rematch is not among them.

**That ships it.** B met "a working game ships it" already, B2 is the second reading, on a different
OS and with a different agent prompt. Thinking stays a non-issue: ~6k tokens over 96 steps,
against ~66k for Bonsai over 86 on the same day.
