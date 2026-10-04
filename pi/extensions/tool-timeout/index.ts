// SPDX-License-Identifier: MIT
// Gives every bash call the model makes without a timeout of its own a default one, so a command
// that never returns (a server started in the foreground, a test that waits forever) ends with
// "Command timed out after N seconds" instead of holding the session until someone aborts it.
// pi's bash tool has no default timeout; a timeout the model passes is left as it is.
// BONSAI_TOOL_TIMEOUT, in seconds, is set by bin/bonsai-pi from TOOL_TIMEOUT in config.env;
// unset or 0 does nothing. Rationale: docs/agent.md#tool-timeout.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SECONDS = Number(process.env.BONSAI_TOOL_TIMEOUT) || 0;

export default function (pi: ExtensionAPI) {
  if (SECONDS <= 0) return;
  pi.on("tool_call", async (event) => {
    if (event.toolName !== "bash") return;
    const input = event.input as { timeout?: number };
    if (input.timeout === undefined) input.timeout = SECONDS;
  });
}
