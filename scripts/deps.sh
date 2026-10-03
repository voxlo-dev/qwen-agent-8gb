#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Installs the build toolchain via apt for BACKEND (cuda or vulkan). Needs sudo, so run it from a
# real terminal. CUDA is tested on Ubuntu 26.04, Vulkan on Debian 13; where apt's CUDA is older
# than 12.4 (Ubuntu 24.04) it keeps an nvcc from NVIDIA's repository. Other systems bring the
# toolchain themselves, see docs/setup.md#toolchain.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case "$BACKEND" in
  cuda)
    has nvidia-smi || die "nvidia-smi not found - install the NVIDIA driver (under WSL2: on the Windows side)"
    has apt-get || die "no apt-get - install CUDA >= 12.4, a matching gcc, cmake, git, python3 yourself, then: ./install.sh build model pi link"
    # gcc-13 is the CUDA host compiler: nvcc 12.x rejects the newer distro default gcc
    pkgs=(build-essential cmake ccache git curl python3 gcc-13 g++-13)
    # An nvcc >= 12.4 from anywhere (NVIDIA's repository, a runfile) is used as it is. Otherwise
    # apt's toolkit, but only where apt has one that new: Ubuntu 24.04 offers 12.0, 22.04 11.5,
    # Debian 13 none in main. See docs/setup.md#cuda-from-nvidias-repository.
    have="$(nvcc_version)"
    if [[ -n "$have" ]] && version_ge "$have" 12.4; then
      log "using the installed nvcc $have"
    else
      cand="$(apt_cuda_version)"
      [[ -n "$cand" ]] && version_ge "$cand" 12.4 \
        || die "apt offers CUDA ${cand:-nothing} here (nvidia-cuda-toolkit)${have:+ and nvcc $have is installed}, the build needs >= 12.4 - install cuda-toolkit-12-9 from NVIDIA's repository, then run ./install.sh again: docs/setup.md#cuda-from-nvidias-repository"
      pkgs+=(nvidia-cuda-toolkit)
    fi
    ;;
  vulkan)
    ls /dev/dri/renderD* >/dev/null 2>&1 || die "no /dev/dri/renderD* - no GPU render node; install the kernel driver (amdgpu) first"
    has apt-get || die "no apt-get - install glslc, the Vulkan headers and loader, a Vulkan driver, cmake, git, python3 yourself, then: ./install.sh build model pi link"
    # glslc compiles the shaders at build time; mesa-vulkan-drivers is RADV, the driver the
    # numbers were measured with. Keep it >= 25.2, see below.
    pkgs=(build-essential cmake ccache git curl python3 glslc libvulkan-dev mesa-vulkan-drivers vulkan-tools)
    ;;
esac

missing=()
for p in "${pkgs[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done

if ((${#missing[@]} == 0)); then
  log "toolchain complete"
else
  log "installing: ${missing[*]}"
  sudo apt-get update
  sudo apt-get install -y "${missing[@]}"
fi

case "$BACKEND" in
  cuda)
    nvcc --version | tail -1
    ;;
  vulkan)
    summary="$(vulkaninfo --summary 2>/dev/null)" || die "vulkaninfo fails - is $USER in the 'render' group? (usermod -aG render $USER, then log in again)"
    device="$(sed -n 's/^[[:space:]]*deviceName *= *//p' <<<"$summary" | head -1)"
    driver="$(sed -n 's/^[[:space:]]*driverVersion *= *//p' <<<"$summary" | head -1)"
    [[ -n "$device" ]] || die "vulkaninfo lists no device - the Vulkan driver does not see the GPU"
    log "Vulkan device: $device, driver $driver"
    # RADV_PERFTEST=nogttspill, which bonsai-server sets, is silently ignored below Mesa 25.2
    # and is worth 1.22x on this model. Debian 13 ships 25.0.7; trixie-backports has 26.x.
    if [[ "$driver" =~ ^[0-9]+\.[0-9]+ ]] && [[ "$(printf '%s\n' 25.2 "$driver" | sort -V | head -1)" != 25.2 ]]; then
      warn "Mesa $driver is older than 25.2: RADV_PERFTEST=nogttspill will be ignored, expect ~1.2x slower - see docs/bonsai.md#other-gpu-backends"
    fi
    ;;
esac
