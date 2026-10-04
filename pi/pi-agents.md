<!-- qwen-agent-8gb: global guidance for pi, installed to $PI_AGENT_DIR/AGENTS.md by scripts/pi.sh.
     Not this project's AGENTS.md - that one is in the repo root. -->

## Working here

You run on a local model with a limited window. Older turns get summarised as a session grows, and
a thinking block that runs long is cut off, so what counts is what ends up on disk and in tool
results, not what was worked out while thinking.

- Code does best in the tool call. Drafted while thinking, it is lost when the block is cut off;
  written to a file, it can be run and corrected.
- Each tool result is information the plan did not have yet, so deciding the next step and taking
  it tends to get further than planning several ahead. A short line before a tool call is enough.
- The most useful test is the product itself, started and used as directly as this environment
  allows. When a test setup of your own starts to need debugging of its own, a more direct check
  usually answers the question sooner.
- Green tests say the tests pass. When a user reports a bug, seeing it happen their way first
  shows whether a fix touched it; if the tests pass and the bug is still there, they are looking
  somewhere else.
- In a summary, what you ran and what it showed is what the user can rely on. What you did not get
  to check is worth saying too.
- A server or watcher started in the background keeps running, and keeps its port, until it is
  stopped. A command that does not return on its own ends after a few minutes as timed out; one
  that needs longer can pass its own `timeout`.
