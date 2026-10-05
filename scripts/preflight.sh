#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Checks everything that would make a later step fail, before any of them spends half an hour:
# disk, RAM and which model it allows, the GPU driver for BACKEND, VRAM, the distro and Node. Reports every item, then
# exits once. install.sh runs it first; SKIP_PREFLIGHT=1 turns it off. Takes the step list as
# arguments so it only checks what is about to run.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

steps=("$@")
((${#steps[@]})) || steps=(deps build model pi link)
runs() { local s; for s in "${steps[@]}"; do [[ "$s" == "$1" ]] && return 0; done; return 1; }

fails=0 warns=0
pass() { printf '   \033[1;32mok\033[0m    %s\n' "$*"; }
soft() { printf '   \033[1;33mwarn\033[0m  %s\n' "$*"; warns=$((warns + 1)); }
hard() { printf '   \033[1;31mfail\033[0m  %s\n' "$*"; fails=$((fails + 1)); }

# df needs a path that exists; walk up to the nearest one that does.
nearest() { local d="$1"; while [[ ! -d "$d" && "$d" != / ]]; do d="$(dirname "$d")"; done; printf '%s' "$d"; }
free_mb() { df -P -BM "$(nearest "$1")" 2>/dev/null | awk 'NR == 2 { sub(/M$/, "", $4); print $4 }'; }

log "preflight ($MODEL on $BACKEND, steps: ${steps[*]})"

# --- system -----------------------------------------------------------------
if [[ "$(uname -s)" != Linux ]]; then
  hard "this is $(uname -s), not Linux - under Windows use WSL2"
else
  # A derivative (Linux Mint, Pop!_OS) names its base in ID_LIKE and UBUNTU_CODENAME; what 'deps'
  # can install depends on that base, not on the name on top.
  IFS='|' read -r distro id family codename < <( . /etc/os-release 2>/dev/null || true
    printf '%s %s|%s|%s %s|%s\n' "${NAME:-?}" "${VERSION_ID:-}" "${ID:-}" "${ID:-}" "${ID_LIKE:-}" "${UBUNTU_CODENAME:-}" )
  base=""; [[ -n "$codename" && "$id" != ubuntu ]] && base=", Ubuntu $codename base"
  wsl=""; grep -qi microsoft /proc/version 2>/dev/null && wsl=" (WSL2)"
  case "${distro,,}|$codename" in
    ubuntu*26.04*|debian*13*|*"|noble") pass "system: ${distro:-unknown}$base$wsl" ;;
    *)
      case " $family " in
        *" ubuntu "*|*" debian "*) soft "system: ${distro:-unknown}$base$wsl - measured on Ubuntu 26.04 and 24.04 (cuda) and Debian 13 (vulkan); 'deps' checks what apt offers" ;;
        *) soft "system: ${distro:-unknown}$wsl - not Debian or Ubuntu, so 'deps' cannot install the toolchain; see the Requirements section of README.md" ;;
      esac
      ;;
  esac
fi

# --- model ------------------------------------------------------------------
# A model file names the backends it was measured on.
case " $MODEL_BACKENDS " in
  *" $BACKEND "*) ;;
  *) hard "model: MODEL=$MODEL is measured on ${MODEL_BACKENDS// /, } only, not $BACKEND - see docs/qwen36.md" ;;
esac

# --- disk -------------------------------------------------------------------
need_home=0
runs build && need_home=$((need_home + 2000))
# A part already in place needs nothing more; model.sh finds it and skips it. Nor does one in the
# Hugging Face cache, which model.sh links instead of downloading. For a split GGUF each missing
# part counts its share of MODEL_DISK_MB, so a download cut short after part 1 still asks for the rest.
if runs model; then
  hf_dir="${HF_HOME:-$HOME/.cache/huggingface}/hub/models--${MODEL_REPO//\//--}/snapshots/$MODEL_REV"
  mapfile -t parts < <(model_parts)
  missing=0
  for p in "${parts[@]}"; do
    [[ -f "$(dirname "$MODEL_PATH")/$(basename "$p")" || -f "$hf_dir/$p" ]] || missing=$((missing + 1))
  done
  need_home=$((need_home + MODEL_DISK_MB * missing / ${#parts[@]}))
fi
runs pi    && need_home=$((need_home + 500))
if ((need_home > 0)); then
  have="$(free_mb "$QWEN_HOME")"
  if [[ -z "$have" ]]; then
    soft "disk: cannot read free space for $QWEN_HOME"
  elif ((have < need_home)); then
    hard "disk: $((have / 1024)) GB free at $QWEN_HOME, needs ~$((need_home / 1024)) GB"
  else
    pass "disk: $((have / 1024)) GB free at $QWEN_HOME, needs ~$((need_home / 1024)) GB"
  fi
fi
if runs deps && [[ "$BACKEND" == cuda ]] && ! has nvcc; then
  have_root="$(free_mb /usr)"
  if [[ -n "$have_root" ]] && ((have_root < 5400)); then
    hard "disk: $((have_root / 1024)) GB free on /usr, the CUDA toolkit from apt needs ~5.4 GB"
  else
    pass "disk: $((have_root / 1024)) GB free on /usr for the CUDA toolkit"
  fi
fi

# --- memory -----------------------------------------------------------------
avail_mb="$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo 2>/dev/null)"
total_mb="$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo 2>/dev/null)"
if [[ -z "$avail_mb" || -z "$total_mb" ]]; then
  soft "RAM: cannot read /proc/meminfo"
elif ((MODEL_RAM_MB > 0)); then
  # A MoE keeps its experts in RAM for as long as it serves, so the ceiling is MemTotal: under
  # WSL2 that is half the Windows RAM unless .wslconfig says otherwise. See docs/qwen36.md.
  need_ram="$(ram_needed_mb "$MODEL")"
  wslhint=""; grep -qi microsoft /proc/version 2>/dev/null \
    && wslhint=" - WSL2 sees half the Windows RAM by default: raise memory= in %UserProfile%\\.wslconfig, then wsl --shutdown"
  if ((total_mb < need_ram)); then
    hard "RAM: ${total_mb} MB in total, $MODEL holds ~${MODEL_RAM_MB} MB in RAM while serving and needs ~${need_ram} MB$wslhint"
  elif ((avail_mb < MODEL_RAM_MB - 4000)); then
    # Most of what it holds is the mmapped experts as page cache, which counts as available.
    soft "RAM: ${avail_mb} of ${total_mb} MB available, $MODEL holds ~${MODEL_RAM_MB} MB while serving - close something before starting it"
  elif ((avail_mb < MODEL_RAM_FULL_MB)); then
    # Runs, but not every expert stays cached: the SSD is in the loop, and a prompt read on the CPU
    # evicts what the next token needs. Measured in docs/qwen38-flash.md#native-linux-every-expert-cached.
    soft "RAM: ${avail_mb} of ${total_mb} MB available - $MODEL keeps every expert cached from ~${MODEL_RAM_FULL_MB} MB; below that it reads from the SSD (~17 instead of ~19 tok/s, prompts at ~70 instead of ~100). Close the browser and editors, or run it on native Linux${wslhint:+ rather than WSL2}"
  else
    pass "RAM: ${avail_mb} of ${total_mb} MB available, $MODEL holds ~${MODEL_RAM_MB} MB"
  fi
elif ((avail_mb < 3000)); then
  hard "RAM: ${avail_mb} MB available - serving needs ~8 GB of headroom, see docs/setup.md#ram-and-build-memory"
elif ((avail_mb < 7500)); then
  soft "RAM: ${avail_mb} MB available - the model loads through mmap and peaks at 5.8 GB; the build falls back to fewer jobs"
else
  pass "RAM: ${avail_mb} MB available"
fi
# The ramp: which of the models this machine's RAM allows, and the one to take (README.md#which-model).
if [[ -n "$total_mb" ]]; then
  fits=""; for m in $(ramp_models); do model_fits "$m" "$total_mb" && fits+="${fits:+, }$m"; done
  rec="$(recommended_model "$total_mb")"
  pass "models: $((total_mb / 1024)) GB of RAM runs ${fits:-none}${rec:+; recommended here: $rec}; this run: $MODEL"
fi

# --- GPU --------------------------------------------------------------------
# Only 'deps' and 'build' need the driver here; 'model', 'pi' and 'link' work on a machine with
# no GPU at all, which is how a server on another host gets set up.
vram_total=0 vram_used=0
if ! runs deps && ! runs build; then
  log "skipping the GPU checks: no step in this run needs one"
else
case "$BACKEND" in
  cuda)
    if ! has nvidia-smi; then
      hard "driver: nvidia-smi not found - install the NVIDIA driver (under WSL2 on the Windows side)"
    elif ! out="$(nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv,noheader,nounits 2>&1)"; then
      # On native Linux the usual cause: Secure Boot refuses a DKMS module whose signing key was
      # never enrolled, and nvidia-smi only says it cannot reach the driver.
      if ! grep -q '^nvidia ' /proc/modules 2>/dev/null && has mokutil \
         && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
        hard "driver: the nvidia kernel module is not loaded and Secure Boot is on - its signing key is probably not enrolled, see docs/setup.md#secure-boot"
      else
        hard "driver: nvidia-smi fails - ${out%%$'\n'*}"
      fi
    else
      IFS=',' read -r gname vram_total vram_used <<<"${out%%$'\n'*}"
      vram_total="${vram_total// /}" vram_used="${vram_used// /}"
      pass "GPU:${gname} (${vram_total} MiB)"
    fi
    nv="$(nvcc_version)"
    if [[ -n "$nv" ]] && ! version_ge "$nv" 12.4; then
      runs build && hard "toolchain: nvcc $nv is older than 12.4 - see docs/setup.md#cuda-from-nvidias-repository"
    elif [[ -z "$nv" ]] && runs deps && has apt-get; then
      # deps would install apt's toolkit; say now, not after the other packages, if it is too old.
      cand="$(apt_cuda_version)"
      if [[ -z "$cand" ]] || ! version_ge "$cand" 12.4; then
        hard "toolchain: apt offers CUDA ${cand:-nothing} here, the build needs >= 12.4 - install cuda-toolkit-12-9 from NVIDIA's repository first, see docs/setup.md#cuda-from-nvidias-repository"
      fi
    elif [[ -z "$nv" ]] && runs build && ! runs deps; then
      hard "toolchain: nvcc not found and 'deps' is not in this run - install CUDA >= 12.4 or run ./install.sh deps"
    fi
    ;;
  vulkan)
    if ! ls /dev/dri/renderD* >/dev/null 2>&1; then
      hard "driver: no /dev/dri/renderD* - the kernel driver (amdgpu) is not loaded"
    elif ! id -nG 2>/dev/null | tr ' ' '\n' | grep -qx render && [[ ! -r "$(ls /dev/dri/renderD* 2>/dev/null | head -1)" ]]; then
      hard "driver: no access to the render node - usermod -aG render $USER, then log in again"
    else
      pass "driver: render node present"
    fi
    for f in /sys/class/drm/card*/device/mem_info_vram_total; do
      [[ -r "$f" ]] || continue
      vram_total=$(( $(cat "$f") / 1024 / 1024 ))
      u="${f%_total}_used"; [[ -r "$u" ]] && vram_used=$(( $(cat "$u") / 1024 / 1024 ))
      break
    done
    if has vulkaninfo; then
      summary="$(vulkaninfo --summary 2>/dev/null || true)"
      device="$(sed -n 's/^[[:space:]]*deviceName *= *//p' <<<"$summary" | head -1 || true)"
      [[ -n "$device" ]] && pass "GPU: $device" || soft "GPU: vulkaninfo lists no device"
    fi
    if runs build && ! has glslc && ! runs deps; then
      hard "toolchain: glslc not found and 'deps' is not in this run - install the Vulkan SDK or run ./install.sh deps"
    fi
    ;;
esac

# deps installs these; a run without it has to find them, or build dies after the fetch.
if runs build && ! runs deps; then
  for t in cmake git; do
    has "$t" || hard "toolchain: $t not found and 'deps' is not in this run - install it or run ./install.sh deps"
  done
fi

if ((vram_total > 0)); then
  if ((vram_total < 7600)); then
    hard "VRAM: ${vram_total} MiB - this setup needs 8 GB and does not run partially offloaded at usable speed"
  else
    pass "VRAM: ${vram_total} MiB total"
  fi
  # A desktop on this GPU takes 0.5-1.2 GB, which is exactly the headroom the 64k profile does
  # not have. See docs/bonsai.md#vram-budget.
  if ((vram_used > 400)) && [[ "$PROFILE" == dedicated ]]; then
    soft "VRAM: ${vram_used} MiB already in use - something (a desktop?) is on this GPU; the 'dedicated' profile fills the card to within a few hundred MiB. Use PROFILE=display, or move the display to an iGPU"
  fi
elif [[ "$BACKEND" == vulkan ]]; then
  soft "VRAM: cannot read it from sysfs - check by hand that the card has 8 GB"
fi
fi

# --- Node -------------------------------------------------------------------
if runs pi; then
  # Ubuntu 24.04 ships 18, Debian 13 20: nvm is the usual source, and it only reaches the PATH of a
  # shell that read ~/.bashrc.
  nvm_node="$(ls -d "${NVM_DIR:-$HOME/.nvm}"/versions/node/v* 2>/dev/null | sort -V | tail -1 || true)"
  nvm_hint=" - install one with nvm or NodeSource, see docs/setup.md#toolchain"
  [[ -n "$nvm_node" ]] && version_ge "${nvm_node##*/v}" 22.19 \
    && nvm_hint=" - nvm has ${nvm_node##*/}, but not on this shell's PATH: run from a shell that loads nvm (source ~/.nvm/nvm.sh)"
  if ! has node; then
    hard "node: not found - pi needs Node.js >= 22.19$nvm_hint"
  else
    nver="$(node --version 2>/dev/null | tr -d v)"
    if [[ -n "$nver" ]] && ! version_ge "$nver" 22.19; then
      hard "node: v$nver is older than the required 22.19$nvm_hint"
    else
      pass "node: v${nver:-?}"
    fi
  fi
fi

# --- port -------------------------------------------------------------------
if [[ "$SERVER_HOST" == 127.0.0.1 || "$SERVER_HOST" == localhost ]]; then
  if curl -sf --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    soft "port $PORT: something already answers there - if it is not qwen-server, set PORT and re-run ./install.sh pi"
  fi
fi

# --- verdict ----------------------------------------------------------------
echo
if ((fails > 0)); then
  die "preflight: $fails problem(s) above must be fixed first - troubleshooting is in docs/setup.md#troubleshooting (SKIP_PREFLIGHT=1 goes ahead anyway)"
fi
((warns > 0)) && warn "preflight: $warns warning(s), continuing"
log "preflight passed"
