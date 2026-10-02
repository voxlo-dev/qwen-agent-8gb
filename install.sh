#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs the install steps in order, or only the ones named: deps build model pi link
# scripts/preflight.sh runs first and stops before any step spends time; SKIP_PREFLIGHT=1 skips it.
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib.sh"

link() {
  mkdir -p "$HOME/.local/bin"
  for b in bonsai-server bonsai-pi bonsai-studio; do ln -sf "$ROOT/bin/$b" "$HOME/.local/bin/$b"; done
  log "linked bonsai-server, bonsai-pi and bonsai-studio into ~/.local/bin"
  [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || warn "~/.local/bin is not on PATH"
}

steps=("$@")
((${#steps[@]})) || steps=(deps build model pi link)
for s in "${steps[@]}"; do
  case "$s" in deps|build|model|pi|link) ;; *) die "unknown step '$s' (deps build model pi link)" ;; esac
done

# Names the step that failed instead of leaving the last command's message alone on the screen.
current=""
on_err() {
  local code=$?
  case "$current" in
    "") ;;
    preflight) ;;  # preflight has already said what is wrong and how to go ahead anyway
    *) printf '\033[1;31mxx\033[0m step '\''%s'\'' failed (exit %d). Re-run just that step with: ./install.sh %s\n' \
         "$current" "$code" "$current" >&2 ;;
  esac
  exit "$code"
}
trap on_err ERR

[[ -n "${SKIP_PREFLIGHT:-}" ]] || { current=preflight; bash "$ROOT/scripts/preflight.sh" "${steps[@]}"; echo; }

for s in "${steps[@]}"; do
  current="$s"
  case "$s" in
    deps)  log "step deps: apt toolchain for $BACKEND (asks for sudo)" ;;
    build) log "step build: compiling llama-server, typically 10-30 minutes" ;;
    model) log "step model: ~$((MODEL_DISK_MB / 1024)).$((MODEL_DISK_MB % 1024 * 10 / 1024)) GB, from the Hugging Face cache if it is there" ;;
    pi)    log "step pi: installing pi $PI_VERSION and writing its config" ;;
    link)  log "step link" ;;
  esac
  case "$s" in
    deps|build|model|pi) bash "$ROOT/scripts/$s.sh" ;;
    link) link ;;
  esac
done
current=""
log "done - start the server with: bonsai-server, then bonsai-pi in another terminal"
