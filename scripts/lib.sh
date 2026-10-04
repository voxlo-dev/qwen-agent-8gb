# SPDX-License-Identifier: MIT
# Shared helpers for the install steps.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/config.env"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }
# a >= b, for dotted versions
version_ge() { [[ "$(printf '%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]; }

# NVIDIA's own packages put nvcc in /usr/local/cuda/bin, which no shell has on its PATH by default.
if ! has nvcc && [[ -x /usr/local/cuda/bin/nvcc ]]; then PATH="/usr/local/cuda/bin:$PATH"; fi

# The installed nvcc's release (12.9), and the one apt would install (12.0, or empty for none).
nvcc_version() { nvcc --version 2>/dev/null | sed -n 's/.*release \([0-9]*\.[0-9]*\).*/\1/p'; }
apt_cuda_version() {
  LC_ALL=C apt-cache policy nvidia-cuda-toolkit 2>/dev/null | sed -n 's/^ *Candidate: \([0-9]*\.[0-9]*\).*/\1/p'
}

# --- the models by RAM: preflight reports them, install.sh asks with them ---------------------
# A value from a model file without sourcing it, so all of them can be read next to the one MODEL
# selected: model_var qwen36-35b MODEL_RAM_MB.
model_var() { sed -n "s/^$2=//p" "$ROOT/models/$1.env" | tr -d '"'; }
mem_total_mb() { awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo 2>/dev/null; }
# What preflight gates MemTotal on: the RAM the model holds while serving plus ~2 GB for the rest.
ram_needed_mb() { local r; r="$(model_var "$1" MODEL_RAM_MB)"; ((r > 0)) && echo $((r + 2000)) || echo 0; }
# The models, the one holding the least RAM first.
ramp_models() {
  local f
  for f in "$ROOT"/models/*.env; do
    printf '%s %s\n' "$(model_var "$(basename "$f" .env)" MODEL_RAM_MB)" "$(basename "$f" .env)"
  done | sort -n | cut -d' ' -f2
}
# Runs here: enough RAM in total, and measured on BACKEND.
model_fits() {
  [[ " $(model_var "$1" MODEL_BACKENDS) " == *" $BACKEND "* ]] && (($2 >= $(ram_needed_mb "$1")))
}
# The recommendation for MemTotal $1: MODEL_DEFAULT where it fits, else the largest that fits below
# it. Never above it: Qwen3.8-Flash is a choice, not a recommendation.
recommended_model() {
  local m rec="" cap; cap="$(model_var "$MODEL_DEFAULT" MODEL_RAM_MB)"
  for m in $(ramp_models); do
    (($(model_var "$m" MODEL_RAM_MB) <= cap)) && model_fits "$m" "$1" && rec="$m"
  done
  echo "$rec"
}
# One line per model for MemTotal $1, numbered: what it holds in RAM, its role, whether it runs here.
print_ramp() {
  local m i=0 ram need full rec note; rec="$(recommended_model "$1")"
  for m in $(ramp_models); do
    i=$((i + 1)) ram="$(model_var "$m" MODEL_RAM_MB)" need="$(ram_needed_mb "$m")"
    full="$(model_var "$m" MODEL_RAM_FULL_MB)"
    if [[ " $(model_var "$m" MODEL_BACKENDS) " != *" $BACKEND "* ]]; then note="not measured on $BACKEND"
    elif (($1 < need)); then note="needs ~$((need / 1024)) GB of RAM in total"
    elif [[ "$m" == "$rec" ]]; then note="runs here - recommended"
    elif ((full > 0 && $1 < full)); then note="runs here, slower: full speed from ~$((full / 1024)) GB free"
    else note="runs here"
    fi
    printf '   %d) %-13s %-24s %4s GB RAM  %-36s %s\n' "$i" "$m" "$(model_var "$m" MODEL_TITLE)" \
      "+$(((ram + 1023) / 1024))" "$(model_var "$m" MODEL_ROLE)" "$note"
  done
}
