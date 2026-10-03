#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Installs the pinned pi into PI_PREFIX and writes its config into PI_AGENT_DIR: provider "local"
# as the default model, the compaction budget, AGENTS.md, the localagent extension with its workflow.
# A global pi and ~/.pi stay untouched.
# Re-run after changing CTX, SERVER_HOST, PORT, MAX_TOKENS, RESERVE_TOKENS or KEEP_RECENT_TOKENS.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

has npm || die "npm not found - install Node.js >= 22.19 first"
node -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit(a>22||(a==22&&b>=19)?0:1)' \
  || die "pi needs Node.js >= 22.19, found $(node --version)"

pkg="$PI_PREFIX/node_modules/@earendil-works/pi-coding-agent/package.json"
installed="$(node -p "require('$pkg').version" 2>/dev/null || true)"
if [[ -x "$PI_BIN" && "$installed" == "$PI_VERSION" ]]; then
  log "pi $PI_VERSION present"
else
  log "installing pi $PI_VERSION into $PI_PREFIX"
  mkdir -p "$PI_PREFIX"
  npm install --prefix "$PI_PREFIX" --no-fund --no-audit "@earendil-works/pi-coding-agent@$PI_VERSION"
fi

dir="$PI_AGENT_DIR"
mkdir -p "$dir"
log "writing pi config in $dir"

DIR="$dir" SERVER_URL="$SERVER_URL" ALIAS="$MODEL_ALIAS" CTX="$CTX" MAX_TOKENS="$MAX_TOKENS" \
RESERVE_TOKENS="$RESERVE_TOKENS" KEEP_RECENT_TOKENS="$KEEP_RECENT_TOKENS" \
AGENT_ID="$AGENT_MODEL_ID" AGENT_BUDGET="$AGENT_BUDGET" AGENT_BUDGET_MSG="$AGENT_BUDGET_MSG" python3 - <<'PY'
import json, os
d = os.environ["DIR"]

def load(name):
    try:
        with open(os.path.join(d, name)) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

def save(name, data):
    with open(os.path.join(d, name), "w") as f:
        json.dump(data, f, indent=2)

models = load("models.json")
models.setdefault("providers", {})["local"] = {
    "api": "openai-completions",
    "baseUrl": os.environ["SERVER_URL"] + "/v1",
    "apiKey": "none",
    "models": [
        {
            "id": os.environ["ALIAS"],
            "contextWindow": int(os.environ["CTX"]),
            "maxTokens": int(os.environ["MAX_TOKENS"]),
        },
        # The same server, a smaller thinking budget: what the localagent extension starts its
        # agents on. samplingParams go into the request body as-is; the fork's llama-server reads
        # reasoning_budget_tokens and reasoning_budget_message per request. See config.env.
        {
            "id": os.environ["AGENT_ID"],
            "contextWindow": int(os.environ["CTX"]),
            "maxTokens": int(os.environ["MAX_TOKENS"]),
            "samplingParams": {
                "reasoning_budget_tokens": int(os.environ["AGENT_BUDGET"]),
                "reasoning_budget_message": os.environ["AGENT_BUDGET_MSG"],
            },
        },
    ],
}
save("models.json", models)

settings = load("settings.json")
settings.update(defaultProvider="local", defaultModel=os.environ["ALIAS"])
# pi's defaults (reserve 16384, keepRecent 20000) assume a 200k window. At 48k they leave
# ~8k of working room and the post-compaction context stays above the trigger, so pi
# compacts on every turn. See docs/agent.md#context-budget.
settings.setdefault("compaction", {}).update(
    reserveTokens=int(os.environ["RESERVE_TOKENS"]),
    keepRecentTokens=int(os.environ["KEEP_RECENT_TOKENS"]),
)
save("settings.json", settings)
PY

cp "$ROOT/pi/pi-agents.md" "$dir/AGENTS.md"
log "wrote $dir/AGENTS.md"

# Replaced whole, so an agent or template removed from the repo does not linger.
ext="$dir/extensions/localagent"
rm -rf "$ext"
mkdir -p "$ext"
cp "$ROOT"/pi/extensions/localagent/*.ts "$ext/"
cp -r "$ROOT/pi/localagent-workflow" "$ext/workflow"
log "wrote the localagent extension to $ext"
