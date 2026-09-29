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
