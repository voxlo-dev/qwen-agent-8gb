---
name: localagent-workflow
description: "A sequential, context-frugal build pipeline for a weak local model: plan gate, one worker dispatch per small unit (spec, tests, code), then e2e and docs. Runs on pi as `qwen-pi --localagent`."
---

# Localagent Workflow

The protocol is the orchestrator's prompt, [`agents/localagent-orchestrator.md`](agents/localagent-orchestrator.md).
`qwen-pi --localagent` puts it into the session's system prompt and adds the `dispatch` tool that
starts the other four agents, runs the tests after a worker and keeps the run log. A session without
the flag cannot run this workflow: tell the user to restart with `qwen-pi --localagent`.

One copy of each rule: the orchestrator prompt holds the protocol, each agent prompt its own step,
`templates/PLAN.md` the shape of a plan. Why each piece is what it is: `docs/localagent.md`.
