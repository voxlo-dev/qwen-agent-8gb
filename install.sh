#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs the install steps in order, or only the ones named: deps build model pi link
# Without MODEL, asks once which model to install, from the RAM next to the card, and writes the
# answer to $QWEN_HOME/model.env, which the qwen-* commands read; not on a terminal it takes the
# default. scripts/preflight.sh runs next and stops before any step spends time; SKIP_PREFLIGHT=1
# skips it.
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib.sh"

# The bonsai-* links of an install from before the rename point at files that are gone.
link() {
  mkdir -p "$HOME/.local/bin"
  local b
  for b in bonsai-server bonsai-pi bonsai-studio; do
    [[ -L "$HOME/.local/bin/$b" && ! -e "$HOME/.local/bin/$b" ]] && rm -f "$HOME/.local/bin/$b" \
      && log "removed the old link ~/.local/bin/$b"
  done
  for b in qwen-server qwen-pi qwen-studio; do ln -sf "$ROOT/bin/$b" "$HOME/.local/bin/$b"; done
  log "linked qwen-server, qwen-pi and qwen-studio into ~/.local/bin"
  [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || warn "~/.local/bin is not on PATH"
}

# The model: MODEL from the environment, else the one model.env records, else asked here. The first
# answer, or the first MODEL installed, becomes what the qwen-* commands run without MODEL;
# installing a second model later leaves it. Changing it: edit model.env, or delete it and run
# ./install.sh again. See README.md#which-model.
choose_model() {
  local total rec answer m n; total="$(mem_total_mb)"; rec="$(recommended_model "${total:-0}")"
  [[ -n "$rec" ]] || rec="$MODEL_DEFAULT"
  # The list and the question go to the terminal; only the answer is the function's output.
  { log "which model? Chosen by the RAM next to the 8 GB card: ${total:+$((total / 1024)) GB here}"
    print_ramp "${total:-0}"; } >&2
  read -r -p "   model (number or name) [$rec]: " answer </dev/tty || answer=""
  answer="${answer:-$rec}"
  n=0
  for m in $(ramp_models); do n=$((n + 1)); [[ "$answer" == "$n" ]] && answer="$m"; done
  [[ -f "$ROOT/models/$answer.env" ]] || die "no model '$answer' - one of: $(ramp_models | tr '\n' ' ')"
  echo "$answer"
}
steps=("$@")
((${#steps[@]})) || steps=(deps build model pi link)
for s in "${steps[@]}"; do
  case "$s" in deps|build|model|pi|link) ;; *) die "unknown step '$s' (deps build model pi link)" ;; esac
done

# What the qwen-* commands run without MODEL is recorded once, after preflight passed, so a model
# this machine cannot hold never sticks: the answer here, else the model from the environment (the
# first one installed), else the one an install from before the rename ran (Bonsai), else without a
# terminal the recommendation for this RAM.
model_file="$QWEN_HOME/model.env"
record=""
if [[ ! -f "$model_file" ]]; then
  case "$MODEL_FROM" in
    env | legacy) record="$MODEL" ;;
    default)
      if [[ -t 0 && -t 1 ]]; then record="$(choose_model)"
      else record="$(recommended_model "$(mem_total_mb)")"; record="${record:-$MODEL}"
      fi
      # config.env has already resolved everything for the default; another model starts over,
      # with it in the environment, which records it after preflight like any MODEL.
      [[ "$record" == "$MODEL" ]] || MODEL="$record" exec bash "$ROOT/install.sh" "$@"
      ;;
  esac
fi
record_model() {
  [[ -n "$record" ]] || return 0
  mkdir -p "$QWEN_HOME"
  printf '# Written by install.sh: the model the qwen-* commands run when MODEL is not set.\nMODEL=%s\n' \
    "$record" > "$model_file"
  log "default model: $record, recorded in $model_file (edit it to change)"
}

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
record_model

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
run=qwen-pi
[[ "$(sed -n 's/^MODEL=//p' "$model_file" 2>/dev/null)" == "$MODEL" ]] || run="MODEL=$MODEL qwen-pi"
log "done - start the agent in a project directory with: $run (it starts qwen-server itself)"
