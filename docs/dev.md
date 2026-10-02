# Development notes

Why the setup looks the way it does. Each choice below answers a failure seen on an RTX 4060 Ti 8 GB under WSL2.

## Model format

The GGUF stores its weights as `PTQ1_0` (ggml type 143), a Prism-specific ternary format: 1.75 bits per weight, with one fp16 scale per 128 weights. Mainline llama.cpp rejects the file at load time:

```
tensor 'output.weight' has invalid ggml type 143. should be in [0, 67)
```

Only the [PrismML fork](https://github.com/PrismML-Eng/llama.cpp) (branch `prism`) has the kernels. `config.env` pins the tested commit. Mainline support is tracked in [ggml-org/llama.cpp#29058](https://github.com/ggml-org/llama.cpp/issues/29058).

Architecture (`qwen35`): 64 blocks, every 4th is full attention (16 layers, 4 KV heads × 256 dims), and the rest are Gated DeltaNet with fixed-size recurrent state. Native context is 262,144 tokens.

## Build

- **Static** (`BUILD_SHARED_LIBS=OFF`): the binary carries its own ggml/llama code, so it cannot pick up another llama.cpp's shared libraries from the same directory.
- **`GGML_CUDA_FA_ALL_QUANTS=ON`**: without it, CUDA flash attention only handles K and V of the *same* type. A mixed cache such as `q8_0`/`q4_0` then falls back to the CPU. Generation speed dropped from 34 to 20 tok/s at 2k context and down to 8 tok/s at 10k, with the GPU at 39 % load.
- **gcc-13 as CUDA host compiler**: Ubuntu's CUDA 12.4 `nvcc` refuses gcc newer than 13, and newer Ubuntu releases default to gcc 15.
- **`CMAKE_CUDA_ARCHITECTURES`** comes from `nvidia-smi` (`89` for Ada). Compiling for one architecture is much faster than for the default set.
- **ccache** speeds up rebuilds and is used when present; the build works without it.
- OpenSSL is not needed: it only enables HTTPS model downloads inside llama-server, and `bonsai-server` passes a local path.
- **Vulkan** (`BACKEND=vulkan`): `GGML_VULKAN=ON` and the patches from `patches/vulkan/` applied to
  the clean checkout, nothing else. There is no architecture to pick; the shaders are compiled by
  `glslc` at build time (`vulkan-shaders-gen`) and the driver specialises them. The Vulkan flash
  attention takes mixed KV types as is, so `FA_ALL_QUANTS` has no counterpart. The patches are
  applied after `git checkout --force`, so they always meet the pinned tree and `build` refuses
  when the pin moved without them (`git apply --check`).

## Toolchain

`./install.sh deps` takes everything from apt, except an `nvcc` >= 12.4 that is already there,
which it keeps. What that means per system, as of a fresh native install on 2026-09-29 (T-004,
T-005, T-006):

- **Ubuntu 26.04:** `nvidia-cuda-toolkit` is CUDA 12.4; `deps` installs it. The reference machine
  (WSL2) runs this.
- **Ubuntu 24.04, and what is built on it** (Linux Mint 22.x, measured on 22.3 native): apt offers
  CUDA 12.0, whose `nvcc` accepts gcc up to 12, not the gcc-13 the build picks. `deps` and
  preflight check the candidate before installing anything and stop with the way out:
  [CUDA from NVIDIA's repository](#cuda-from-nvidias-repository). With that toolkit in place
  `./install.sh` runs through, and serves at 36.6 tok/s, the same as under WSL2.
- **Ubuntu 22.04** (CUDA 11.5, no `sm_89`, no `gcc-13`) and **Debian 13** (`nvidia-cuda-toolkit`
  only in `contrib`, which the image does not enable) are not run. They meet the same check: apt
  offers < 12.4 or nothing, so `deps` stops at once rather than deep in apt or nvcc. On 22.04 the
  NVIDIA route also needs `gcc-13` dropped from `deps`' list; nobody has asked for it.
- **RTX 50xx** (`sm_120`) needs CUDA >= 12.8, i.e. NVIDIA's own repository. `build.sh` stops
  early when the GPU is newer than the installed `nvcc`.
- **Native Linux next to a distro driver:** neither toolkit touches it. Simulated against
  `nvidia-driver-595-open` on 24.04: Ubuntu's `nvidia-cuda-toolkit` installs 93 packages and
  removes none, its `libcuda.so.1` dependency is met by the installed `libnvidia-compute-595`;
  NVIDIA's `cuda-toolkit-12-9` (71) and `13-4` (66) pull no driver package at all. The risk is
  elsewhere: NVIDIA's repository carries newer `dkms`, `nvidia-settings` and
  `libnvidia-egl-wayland1`, which a plain `apt upgrade` would take. Hence the pin below. Under
  WSL2 the question does not arise: `ldd llama-server` resolves `libcuda.so.1` to
  `/usr/lib/wsl/lib`, first in the loader path.
- **AMD through Vulkan** (`BACKEND=vulkan`): `deps` is tested on Debian 13 - `glslc`,
  `libvulkan-dev`, `mesa-vulkan-drivers`, `vulkan-tools`; the package names are the same on
  Ubuntu. It gates on a `/dev/dri/renderD*` node and on `vulkaninfo` seeing a device, which
  needs the user in the `render` group. **Mesa >= 25.2** is what the numbers were measured
  with; Debian 13 ships 25.0.7, which is 1.22x slower because `RADV_PERFTEST=nogttspill` is
  ignored there, and `deps` warns about it. `trixie-backports` has 26.x. The fork also carries
  ROCm/HIP and Metal kernels; untested. [Other GPU backends](#other-gpu-backends) has what
  Vulkan delivers and why.

**Node.js >= 22.19** for pi (`engines` in its `package.json`) comes from apt on Ubuntu 26.04 only:
24.04 ships 18.19, Debian 13 20.19. nvm is the tested source (v24.21 on Mint 22.3); it reaches
only shells that read `~/.bashrc`, so a distro Node left in `/usr/bin` still wins elsewhere, and
preflight says which one it found. NodeSource works the same way through apt. pi takes 440 MB in
`$BONSAI_HOME/pi`.

Disk, measured: model 5.6 GB, `llama.cpp` checkout and build 1.3-1.9 GB, ccache ~0.25 GB, pi
0.44 GB. The toolkit: ~5.4 GB from apt, 7.3 GB for NVIDIA's `cuda-toolkit-12-9`, whose Nsight
tools also pull a Java runtime. The binary links `libcudart` and `libcublas` dynamically, so the
toolkit stays after the build. A fresh native install came to ~15 GB with NVIDIA's toolkit.

### CUDA from NVIDIA's repository

Where apt's CUDA is older than 12.4 (Ubuntu 24.04 and its derivatives), or for an RTX 50xx:

```bash
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
# Only for what Ubuntu does not have: keeps apt upgrade off NVIDIA's dkms and nvidia-settings
printf 'Package: *\nPin: origin developer.download.nvidia.com\nPin-Priority: 100\n' \
  | sudo tee /etc/apt/preferences.d/cuda-repo-pin
sudo apt-get update
sudo apt-get install -y cuda-toolkit-12-9
./install.sh
```

`cuda-toolkit-12-9`, not `cuda`: the metapackage brings NVIDIA's driver along, on top of the one
the distro installed. 12.9 rather than 13.x because every CUDA number here was measured on 12.x.
The toolkit lands in `/usr/local/cuda/bin`, which no shell has on its `PATH`; `lib.sh` adds it
when `nvcc` is not found otherwise, so no `~/.bashrc` edit is needed. With the pin,
`apt list --upgradable` stays empty of NVIDIA packages; without it, it listed four.

### Secure Boot

On native Linux with Secure Boot on, the kernel loads the NVIDIA module only if its signature
key is enrolled in the firmware (MOK). DKMS signs the module, but nothing enrolls the key, so
after an install the driver packages are all there, `dkms status` says `installed`, and
`nvidia-smi` only reports that it "couldn't communicate with the NVIDIA driver". preflight names
this case. `mokutil --test-key /var/lib/shim-signed/mok/MOK.der` says whether the key is enrolled.

Found on Linux Mint 22.3, where the key in `/var/lib/shim-signed/mok/` predated the install by
nearly nine months (`CN=localhost.localdomain`): it came with the image, so its private half is likely
the same on every install from it. Make a key of your own before enrolling one:

```bash
sudo mkdir -p /root/mok.iso && sudo mv /var/lib/shim-signed/mok/MOK.* /root/mok.iso/
sudo update-secureboot-policy --new-key
sudo dpkg-reconfigure nvidia-dkms-595-open      # rebuilds and signs with the new key
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der
sudo reboot    # MOK Manager: Enroll MOK, Continue, Yes, the password (US layout), Reboot
```

An installer that probes the GPU, Unsloth Studio's among them, has to run after this: before it,
Unsloth saw only the iGPU and installed CPU torch and the Vulkan llama.cpp build, which
`build` now refuses for a CUDA model.

## Windows

**Native Windows is declined; WSL2 is the Windows path**, and it is the reference platform - every
CUDA number in this file was measured on Windows 11 + WSL2 + Ubuntu 26.04. So the question is not
whether Windows works, it is whether a second implementation would be worth keeping.

It would be a second implementation. The install is bash end to end, and the parts that would have
to be rewritten are the parts that are hard:

- **`deps` has no equivalent.** It is apt and dpkg. On Windows the toolchain is VS Build Tools plus
  the CUDA toolkit, or the LunarG SDK for `glslc` - installed by hand, or by taking a dependency on
  winget or chocolatey.
- **`preflight` would be written twice.** It reads `/proc/meminfo`, `/proc/version`,
  `/etc/os-release`, `/dev/dri/renderD*`, `df -P -BM` and `nproc`. Its first check already says
  "this is not Linux - under Windows use WSL2", which is the correct answer.
- **`build` picks gcc-13 as the CUDA host compiler** ([Toolchain](#toolchain)); under MSVC that
  branch, and the ccache launchers with it, mean something else.
- **`model` symlinks out of the Hugging Face cache**, which needs developer mode or an
  administrator.
- **`bonsai-pi` is the real cost.** `setsid`, `flock`, `kill -0`, pruning sessions by pid, and the
  HUP/TERM/QUIT traps that make [Server lifecycle](#server-lifecycle) work have no Windows
  counterpart. It would be reinvented with job objects and a mutex - the one piece of this repo
  where the failure modes were expensive to find, rebuilt on a platform where they would have to be
  found again.

Git Bash or MSYS2 is not the shortcut it looks like: `nvidia-smi` and cmake run there, `/proc`,
`flock` and `setsid` do not.

Against roughly 700 lines of PowerShell, a second test matrix and a second set of measurements,
the gain is that a Windows user does not run `wsl --install`. The one argument with substance is
speed - native would not pay the WSL2 passthrough. For Bonsai it is measured now and there is none:
36.6 tok/s on native Linux against 36 under WSL2. For the MoE models there is, 30-100 %, because
their experts are read from host memory ([qwen.md](qwen.md#native-linux)). That gap argues for
native Linux, which this repo already supports, not for a native Windows port, which is unmeasured
and would pay its own costs; it is what a measurement on native Windows would have to beat.

## Other GPU backends

CUDA is a choice here, not a constraint of the model: the fork carries `PTQ1_0` kernels for
Vulkan, ROCm/HIP, Metal and the CPU. The Vulkan path was built and measured on an AMD RX 570
(Polaris10/gfx803, 8 GiB, RADV) so the choice rests on numbers - first as the fork ships it
(T-010, `runs/T-010-vulkan-rx570/`), then with a rewritten PTQ1_0 decode (T-016,
`runs/T-016-ptq1_0-vulkan-decode/`, patch and logs there).

**It works.** `-DGGML_VULKAN=ON` builds clean, every shader passes `glslc`, the server puts all
layers on the Vulkan device, `q8_0`/`q4_0` KV with `-fa on` is accepted (`fa_kv_ok` lists both
and only requires BF16 to match on both sides), and load takes 8 s. PTQ1_0 has the full pipeline
set - `mul_mat_vec` for generation and the scalar `CREATE_MM` matmul a device without cooperative
matrix takes. coopmat2 is deliberately absent for PTQ1_0 and is NVIDIA-only anyway.

**As shipped it is about 20x too slow; with the T-016 decode about 5x.** At 48k, Mesa 26.1.2,
`RADV_PERFTEST=nogttspill`, clocks `auto`:

| | RX 570, shipped kernel | RX 570, T-016 decode | RTX 4060 Ti / CUDA |
| --- | --- | --- | --- |
| prompt processing (847 tokens) | 36 tok/s | 54 tok/s | 451 tok/s |
| generation | 1.58 tok/s (633 ms/token) | 7.0 tok/s (143 ms/token) | 36 tok/s |

**The kernel was the ceiling, and the decode was the kernel.** `ptq1_0.glsl` as shipped
decoded every weight element on its own: one byte load, a three-way range branch and a loop
of up to four dependent multiply-mask steps (`v = (v*3) & 0xFF`, ~2.5 on average) to reach the
wanted base-3 digit, because PTQ1_0 packs five trits per byte. Per 128-element block that is
128 byte loads and ~320 serial ALU ops where Q4_0 loads one word per four elements and shifts.
The same card runs Qwen2.5-3B `Q4_K_M` at 121 GB/s effective, which for 5.4 GB of weights would
be ~22 tok/s; 1.58 meant the kernel was ~14x worse per byte, i.e. ALU-bound, which is also why
the memory clock never ramped (the DPM governor watches memory traffic and saw none). The
fork's own issue [#185](https://github.com/PrismML-Eng/llama.cpp/issues/185) has this kernel as
committed-untested and slow: 0.7 tok/s on a Radeon 860M, ~9 tok/s on an RX 9070 XT.

The T-016 rewrite replaces the recurrence with a 256-entry table, byte to five trits, generated
from the CPU codec in `ggml-quants.c` so it is bit-exact by construction, held in shared memory
through the same `init_iq_shmem` mechanism the IQ grids use, with each trit stored as a 2-bit
two's-complement field so one `bitfieldExtract` yields the signed value. The block is read
through a `block_ptq1_0_packed32` view (seven 32-bit words), so four consecutive elements
(`mul_mat_vec`) cost one word load and eight (`mul_mm`) cost two. The element-to-byte mapping
lives in one function, `ptq1_0_locate`, used by every consumer. Verified with
`test-backend-ops -b Vulkan0 -p ptq1_0` for `MUL_MAT`, `MUL_MAT_ID`, `GET_ROWS` and `CPY`
against the CPU backend, before and after. What it bought, 16k and 48k identical:

| Path | before | after | Gain |
| --- | --- | --- | --- |
| generation (`mul_mat_vec`) | 632.96 ms/token | 142.56 ms/token | 4.4x |
| prompt, 847 tokens (`mul_mm`) | 36.0 tok/s | 54.0 tok/s | 1.5x |

Two things the numbers say about what is left. The memory clock now ramps on its own (1000 to
1750 MHz during generation, where the shipped kernel sat at 300), so the kernel has become
visible as memory traffic; and 143 ms/token is still ~3x the ~45 ms that Q4_K_M's per-byte
efficiency would allow, so it is not bandwidth-bound yet. The remaining ALU cost is structural:
`mul_mat_vec` hands each thread four consecutive elements, which is one trit position of four
bytes, so every byte is loaded and looked up five times per token. A dedicated PTQ1_0 mat-vec
kernel that keeps all five trits of a loaded word (the way the K-quant `mul_mat_vec_*` shaders
own their block layout) is the next step, and a larger one; the ceiling for it is ~22 tok/s.

**Correction (T-017, 2026-09-24).** T-016 first printed the prompt gain as 3.8 → 54 tok/s,
14x. The 3.8 was the 18-token prompt of the generation request, not a long prompt: T-016 never
measured the shipped kernel on the 847-token one. Measured at the fork's `842b188` (whose
PTQ1_0 `mul_mm` path is unchanged from the pin), the shipped kernel does 36.0 tok/s there, so
the decode is worth 1.5x on prompts. The tables above carry the corrected value; the
generation numbers stand.

**Upstream, [#252](https://github.com/PrismML-Eng/llama.cpp/pull/252) is the generation half
of this, done properly.** The fork's `842b188` release carries an integer-dot mat-vec (#238),
which gfx803 cannot use (`int dot: 0`). #252, open, adds the dedicated PTQ1_0 `mul_mat_vec`
shader described above as the next step. On the RX 570, 16k, same flags as T-016
(`runs/T-017-pr252-rx570/`), all four builds on `842b188`:

| Build | generation | prompt, 847 tokens | `llama-bench` tg128 / pp512 |
| --- | --- | --- | --- |
| `842b188` | 633.4 ms/token | 36.0 tok/s | 1.58 / 42.6 |
| + #252 | 141.6 ms/token | 39.8 tok/s | 7.15 / 42.4 |
| + T-016 patch | 143.9 ms/token | 53.8 tok/s | 6.99 / 59.1 |
| + #252 + T-016 patch | 141.4 ms/token | 53.9 tok/s | 7.15 / 59.1 |

`test-backend-ops -b Vulkan0 -p ptq1_0` passes `MUL_MAT`, `MUL_MAT_ID` and `GET_ROWS` in all
four (140 + 83 + 4). #252 reaches the same generation speed as the T-016 decode, slightly ahead,
and stays at the same ~3x off the ~45 ms roofline, so the remaining cost is not in the trit
decode. What only the T-016 patch still adds is the `mul_mm` loader: +40-50 % on prompts. The two
compose without conflict (the patch needs `git am -3` on `842b188` for context in `types.glsl`).
Polaris has no integer-dot instruction, so the `mul_mat_vecq` route is not available here.

**The environment is worth 1.76x on the shipped kernel, and getting it wrong looks like a kernel
problem.** The first run, on Debian 13's Mesa 25.0.7 with clocks on `auto`, gave 0.94 tok/s.
Three things moved it, measured one at a time at 16k:

| Change | ms/token | Gain |
| --- | --- | --- |
| Mesa 25.0.7, clocks `auto` | 1067.92 | - |
| Mesa 26.1.2 (trixie-backports), same clocks | 771.12 | 1.38x |
| \+ `RADV_PERFTEST=nogttspill` | 632.96 | 1.22x |
| \+ `power_dpm_force_performance_level=high` | 606.09 | 1.04x |

- **The Mesa version matters most, and specifically for this quant.** 25.0.7 to 26.1.2 is 1.38x
  here while the same upgrade moved a Qwen2.5-3B `Q4_K_M` control on the same card by 1.04x
  (60.34 to 62.97 tok/s). Whatever the older RADV did to the PTQ1_0 shaders, it did it to those
  and not to the standard quants.
- **Memory placement costs a lot, for one buffer.** RADV puts buffers in GTT although VRAM is
  free; `nogttspill` moves ~150 MiB back (GTT 473 to 322 MiB) and buys 1.22x. It needs
  **Mesa >= 25.2** and is silently ignored below that, which is why an earlier attempt on 25.0.7
  measured nothing. The ~150 MiB is the `Vulkan0 compute buffer` (150.28 MiB), which every graph
  execution touches - that is why so few bytes are worth so much, and why the rest is not.
  The other direction brackets it: `GGML_VK_PREFER_HOST_MEMORY` puts everything in host memory
  (VRAM 21 MiB, GTT 6170 MiB) and costs 1.92x, 1213.57 ms/token. Note it is checked for
  *presence*, so setting it to `0` still turns it on.
- **The GTT that is left cannot be moved, and would not pay.** 322 MiB at 16k is
  `token_embd.weight` at 265.23 MiB, the `Vulkan_Host compute buffer` at 36.29 MiB and ~17 MiB
  the driver holds with nothing loaded at all - a floor of roughly 53 MiB even in theory. The
  embedding stays on the CPU because the Vulkan backend has no PTQ1_0 path for that buffer type
  (`cannot be used with preferred buffer type Vulkan_Host, using CPU instead`), which is a fork
  change, not a setting. It would buy nothing either: a row lookup reads kilobytes per token, not
  265 MiB. `--no-host` does not move it - GTT and ms/token are unchanged to three digits
  (633.14 vs 633.20).
- **The clocks barely matter once Mesa is current.** With the shipped kernel `pp_dpm_mclk` sits
  at 300 MHz of an available 1750 under load while `sclk` is pinned at its top and
  `gpu_busy_percent` reads 100 %; forcing the performance level raises mclk to 1750 and buys
  1.18x on Mesa 25.0.7 but only 1.04x on 26.1.2. With the T-016 decode it ramps by itself.
- **The context window costs nothing.** 48k and 16k give 633.06 and 632.96 ms/token before,
  142.98 and 142.56 after.

**So: CUDA for interactive use, Vulkan for batch.** 7 tok/s is a fifth of the 4060 Ti and
54 tok/s prompt an eighth: a 4k-token agent prompt costs ~75 s before the first token, a
10k-token agent step ~25 minutes. That is fine for a task handed over and left alone
(`bonsai-pi -p`) and not for a conversation, which is why `vulkan` is
supported and not the default. How the setup does it, all of it measured above:

- `BACKEND=vulkan` builds the fork with `GGML_VULKAN=ON` and `patches/vulkan/` applied; the
  pinned `LLAMA_COMMIT` does not carry the decode until upstream takes it (T-017). Same
  binary flags otherwise, same KV types, same `-fa on`.
- `bonsai-server` exports `RADV_PERFTEST=nogttspill` (1.22x; needs Mesa >= 25.2, `deps` warns
  below that), and `GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1`. That one is neutral for Bonsai
  (143.81 vs 144.07 ms/token at 64k) and 2.3x on Qwen's repeated requests, whose checkpoint writes
  otherwise push buffers out of the 256 MiB of CPU-visible VRAM
  ([qwen.md](qwen.md#on-the-rx-570-vulkan)). Nothing forces the clocks: with the new decode `mclk` ramps by itself, and the
  knob needs root anyway.
- The `dedicated` profile holds as is: 64k measured at 7 434 MiB of 8 192 on the RX 570,
  141.56 ms/token (`runs/T-016-ptq1_0-vulkan-decode/measure-new-64k.out`), so the window
  costs nothing here either and the pi budget is the same arithmetic.
- `token_embd` stays on the CPU (265 MiB in GTT) and there is no Vulkan `mul_mat_vecq`; both
  are fork work, neither is a setting.

Two side findings from the same runs, both harmless: `token_embd.weight` (ptq1_0) "cannot be used
with preferred buffer type Vulkan_Host, using CPU instead", so 265 MiB stays CPU-mapped even at
`-ngl 99`; and only 16 layers carry a KV cache (the rest log as `filtered`), which is why 48k
costs just 1222 MiB - K `q8_0` 799 MiB, V `q4_0` 423 MiB - and why a 48k window fits 8 GB at all.

## RAM and build memory

Measured on the RX 570 box (8 cores, 24 GB, no swap, Mesa 26.1.2), Vulkan backend, T-009.
Raw samples and the build log: `runs/T-009-ram-and-build-memory/`.

**Serving is cheap; loading is not.**

| | RSS |
| --- | --- |
| llama-server peak while loading the model (`VmHWM`) | 5 841 MB |
| resident once loaded, idle | 468 MB |
| resident while generating | 622 MB |
| page cache holding the GGUF | ~6 300 MB, reclaimable |

The load peak is the 5.9 GB model file read through `mmap`; afterwards the pages are backed by
the file and the kernel drops them under pressure, so the process settles below 700 MB.
Generation adds ~150 MB and nothing grows with the context - the KV cache lives in VRAM. A
machine with **8 GB of RAM serves this model comfortably**, and the page cache is what uses
whatever is left over.

**Building is the memory-hungry part, not serving.**

| | |
| --- | --- |
| Peak across all compilers, `-j8`, ccache off | 5 735 MB |
| Largest single translation unit | 4 439 MB |
| Concurrent compilers at that peak | 4 |
| Wall clock, `-j8` | 218 s |

The 4.4 GB unit is `mul_mm.comp.cpp`, the generated Vulkan matmul shader permutations - its
object file is 29 MB, six times the next largest. The shader generation step before it spawns
up to 38 `glslc` processes at once, but they are small (430 MB together).

So the binding constraint is one heavy unit plus whatever else `make` starts next to it, which
is why `build.sh` no longer passes `-j $(nproc)` unconditionally: it allows ~2 GB per job and
takes the lower of that and the core count, overridable with `BUILD_JOBS`. On the 8-core box
with 16 GB free that is `-j7`; on an 8 GB machine it is `-j3`, where `-j8` would have put two
heavy units side by side with no room for them.

**In a VM, this model makes the guest look full.** The GGUF is read through `mmap`, so after a
load the guest holds ~6 GB of page cache it will happily keep forever - `MemAvailable` stays
high, but `MemFree` does not. A hypervisor without a balloon device in the guest cannot tell
page cache from live data and can never take a touched page back, so the VM's host-side
footprint ratchets up to whatever it was assigned and stays there. Measured on the RX 570 box:
15.1 GB backed before a build, 16.2 GB after, against 13.8 GB still available inside. A
management UI reporting the VM at 100 % of its RAM is therefore expected here and is not a
shortage. Give such a guest a balloon device, or size it to what this actually needs - the
5.8 GB load peak plus room for the build, so ~12 GB - rather than to the largest number that
fits, or the guests together can overcommit the host even when each one looks idle.

**Not measured:** the CUDA build. `nvcc` has a different memory profile from `g++` on generated
shader code, and no NVIDIA GPU is reachable from the machines this was run on - the numbers above
are the Vulkan path only. The box also had llama-server and the Docker inference node running
throughout, which is why guest-wide usage peaked at 15.1 GB while the build itself accounts for
5.7 GB of it.

## VRAM budget

| Item | MiB |
| --- | --- |
| Model weights on GPU | 5,395 |
| Compute buffer | ~250 |
| KV cache, per 1k tokens, `q8_0`/`q8_0` | 34 |
| KV cache, per 1k tokens, `q8_0`/`q4_0` | 26 |

At 48k context with `q8_0`/`q4_0` the process holds ~7.3 GB of 8 GB. **64k is the default**: measured at 7 747 MiB of 8 188, 36 tok/s at short context and no layer on the CPU - 441 MiB to spare, which is why the GPU must drive no display.

**More than 64k only through the cache type**: 96k fits at `q4_0`/`q4_0` (18 MiB per 1k) and reads that depth cleanly, and nothing larger stays on the card. Under WSL2 a window that is too large does not fail to load. It spills into shared memory once the cache fills, and the VRAM reading does not show it. The measurements, and how to test a window at depth, are in [context-window.md](context-window.md). The second model, `MODEL=qwen36-35b`, has its own budget with the experts in RAM: [qwen.md](qwen.md).

**Display on the iGPU.** When the RTX also drives the Windows desktop, the desktop takes 0.5 to 1.2 GB and competes for GPU time. With the monitor on the mainboard (iGPU enabled in BIOS, browsers set to "Power saving" under Windows *Settings → System → Display → Graphics*), generation went from 21 to 34 tok/s in the same browser-based session.

**No `--fit`, forced `-ngl 99`.** llama.cpp's auto-fit keeps a safety margin. On 8 GB that margin pushes 10 to 12 layers to the CPU, and partial offload costs this architecture about 10× decode speed (3–4 tok/s). The fork's memory estimate is accurate. The margin is the problem.

## KV cache

K at `q8_0` and V at `q4_0`, measured against an `f16` cache: 99.66 % same top token at 16k (99.83 % for `q8_0`/`q8_0`), and identical to `f16` on 510 of 512 tokens at 92k. There is no quality case against it, and `q8_0`/`q8_0` is not faster either (+2.7 % at 43k, for 12k less window). It saves ~25 % of the cache compared with `q8_0`/`q8_0`. Qwen3.6's cache is 3-33x more sensitive than Bonsai's and stays at `q8_0`/`q8_0`. Both are in [context-window.md](context-window.md#kv-cache-quality). llama.cpp has no `q6` cache type; `q5_0` is several times slower on the fork (PrismML-Eng/llama.cpp#191). The options are `f16`, `bf16`, `q8_0`, `q5_1`, `q5_0`, `q4_1`, `q4_0` and `iq4_nl`. A quantized V cache requires flash attention (`-fa on`).

## Reasoning

The chat template reads `reasoning_effort` (`low`, `medium`, `xhigh`) and **defaults to `xhigh`**. At `xhigh` it tells the model to "think carefully, validate key assumptions, consider plausible alternatives". At `medium` it adds nothing, and at `low` it asks for brief thinking.

On coding tasks the model drafts entire implementations inside its thinking block before calling any tool. Measured on a full-stack game prompt:

| Setting | Thinking | Answer |
| --- | --- | --- |
| `xhigh`, no budget (in pi) | 24k tokens, hit the output cap | none |
| `low`, no budget | 12k tokens, hit the cap | none |
| `medium`, no budget | 12k tokens, hit the cap | none |
| `medium`, budget 3k | ~2.7k tokens | plan + code |

Budget size shows up in the result, not just in the token count. At 4096 the model produced
a single-file game and claimed test runs it never performed; at 8192, with the same prompt
and the 64k window, it built a server-authoritative game with two integration tests that
work. See the table under [Context budget](#context-budget).

The effort level barely matters. The hard budget is what works: `--reasoning-budget` cuts thinking after N tokens, and `--reasoning-budget-message` is injected before the end-of-thinking tag to push the model into acting. Each agent turn gets a fresh budget. The message asks for one tool call, not "the files": worded that way, the localagent orchestrator took it as leave to write a test file next to its plan (T-019, Tron). Both are also accepted per request, as `reasoning_budget_tokens` and `reasoning_budget_message` in the body (`tools/server/server-common.cpp` in the fork), falling back to the flags; the localagent workflow uses that to run its agents at `AGENT_BUDGET` while the session keeps `BUDGET`, see [localagent.md](localagent.md#running-it-on-pi).

Do not enable pi's thinking levels for this model (`"reasoning": true` in `models.json`). pi would send levels such as `high` or `minimal`, which the template rejects with an exception. The server sets the level.

## Context budget

pi's compaction defaults assume a 200k window. On 48k they produce an endless compaction
loop. From `dist/core/compaction/compaction.js` and `settings-manager.js`:

- `shouldCompact`: `contextTokens > contextWindow - reserveTokens`, default `reserveTokens` 16384
- `keepRecentTokens` default 20000, estimated as `chars/4` over the messages only - the
  system prompt and the tool schemas are not counted, and chars/4 underestimates code and
  JSON tool arguments

Measured on a full-stack game prompt (session `2026-09-19T16-24-33`, 30 entries, 31 minutes):

| Compaction | tokensBefore | input of the next request |
| --- | --- | --- |
| 1 | 33 229 | 33 524 |
| 2 | 39 087 | 32 272 |
| 3 | 33 963 | 32 476 |
| 4 | 35 026 | - |

The trigger sat at 48000 - 16384 = **31 616**, and the context never came back below it:
those "20 000" kept tokens really were ~30 000. The first compaction cut at the very first
assistant message and freed nothing at all. pi then compacted on every single turn, at a
cost of one summarization call (2.3-3.8k tokens at ~30 tok/s) plus a full prompt
reprocess - `cacheRead` drops to 0 after a compaction - of ~33k at ~400 tok/s. Roughly a
third of that session went into compaction, and the task never finished.

A second, latent fault: `maxTokens` 24000 plus a 31 616 trigger let pi request 55 616
tokens from a 48000 window. With `--no-context-shift` the server stops there; the
`2026-09-19T15-32-43` session shows a `stopReason: length`.

The settings below keep the post-compaction state comfortably under the trigger and the
worst case inside the window. `install.sh pi` writes the two compaction keys into
`$BONSAI_HOME/pi-agent/settings.json`.

Because these five constrain each other, they live in a profile, `profiles/$MODEL/$PROFILE.env`, and move together.
`PROFILE=dedicated` (default) is the 64k window below. `PROFILE=display` is the 48k set the
measurements above were taken with - `CTX` 48000, `BUDGET` 4096, `MAX_TOKENS` 12000,
`RESERVE_TOKENS` 12000, `KEEP_RECENT_TOKENS` 8000 - for a GPU that also renders a desktop
and so cannot hold a 64k cache.

| | Value | Constraint |
| --- | --- | --- |
| `RESERVE_TOKENS` | 16000 | >= the largest single turn's output (11 441 measured), and >= `BUDGET` + a tool call + 4096 for the clamp |
| `MAX_TOKENS` | 16000 | `CTX - RESERVE + MAX_TOKENS <= CTX`, so exactly 64000 |
| `KEEP_RECENT_TOKENS` | 12000 | real cost ~1.4-2x, so ~24k in use against a 48 000 trigger |
| `BUDGET` | 8192 | 8192 + ~3.7k tool call <= `RESERVE_TOKENS` - 4096 = 11 904 |

That leaves ~20k of working room.

Measured on the same prompt with these settings (session `2026-09-19T17-24-22`, 79 agent
steps, 89 minutes): 5 compactions, with 13, 18, 12, 19, 5 and 12 steps between them -
against one per step before. Each fired at 36 974-37 513 tokens, and the next request came
back at 15.2-18.6k, less than half the trigger. The run ended on something else, below.

**pi caps the output near the trigger.** pi sends `max_tokens` as
`min(maxTokens, contextWindow - estimated context - 4096)` (`clampMaxTokensToContext`,
`CONTEXT_SAFETY_TOKENS` = 4096). Just below the trigger that leaves
`RESERVE_TOKENS - 4096` = 7 904 tokens, less than `BUDGET` (8192). The last step of that
session sat at 35 861 tokens, got `max_tokens` 8 334, spent 8 192 of it thinking, and was cut
off with `stopReason: length` before its tool call, which ended the agent loop. So the real
constraint is `BUDGET + tool call <= RESERVE_TOKENS - 4096`.

`BUDGET` is therefore 4096: with a tool call of up to ~3.3k (the largest write measured
without thinking) it stays under 7 904, and a 3k budget already produced plan + code (see
[Reasoning](#reasoning)). The other lever, `RESERVE_TOKENS` 16000, would keep 8 192 of
thinking but lower the trigger to 32 000 and the working room between compactions to ~16k.

Three runs of the same prompt, which is what the numbers below come from:

| | 48k, `BUDGET` 8192 | 48k, `BUDGET` 4096 | **64k, `BUDGET` 8192** |
| --- | --- | --- | --- |
| Steps / duration | 79 / 89 min | 168 / 112 min | 108 / 91 min |
| Ended | cut off on `length` | on its own | on its own |
| Compactions | 5, every 5-19 steps | 7, every 8-33 steps | 4, every 17-30 steps |
| Context after one | 15-19k | 15-19k | 21-24k |
| Steps at the budget | 4 | 6 | 2 |
| Result | unfinished | one `index.html`, online mode never tested, test passes claimed but not run | server + client + two integration tests, 869 lines, confirmed working |

The middle run is the `display` profile, the right one is `dedicated`. Fewer, larger steps
beat many small ones here: half the steps of the 4096 run, in the same time, for a result
that holds up. The 64k run's closest approach to pi's clamp left 5 372 tokens of margin, so
the trigger was never the limit.

**The 4096 stays.** pi's `CONTEXT_SAFETY_TOKENS` is a constant in its bundle. Shrinking it means
patching a pinned dependency, which `PI_VERSION` would then no longer describe, or asking pi for a
setting. With 5 372 tokens of margin in the run above, ~3k more working room per compaction cycle
is not worth either. Revisit only if a profile runs tighter than that (closed as T-015).

The 4096 re-run (session `2026-09-19T19-16-01`): 168 steps in
112 minutes, and the run ended on its own (`stopReason: stop`) with no step cut off on
`length`. 7 compactions, 8-33 steps apart, back at 14.5-19.4k each time. 6 steps hit the
budget. The largest output was 11 441 tokens, 4k thinking plus a ~7k `write`, at 7.6k
context where the clamp still allowed the full 12 000. The same step just below the trigger
would be cut off, so the tool-call allowance above is a typical case, not a bound.

**96k, tried on 2026-09-26/27** (T-035's behaviour day). The window from
[context-window.md](context-window.md#bonsai-windows-on-8-gb), `CTX` 96000 at `q4_0`/`q4_0` with
`KEEP_RECENT_TOKENS` 16000 and the rest as `dedicated`, against the shipped 64k as the control. The
Tron prompt, plain `bonsai-pi`, fresh directories; the 96k session ran a day before the control.
Logs and `evaluate.sh`: `runs/T-035-bonsai-measured/day/` on the 4060 Ti machine.

| | 96k, `q4_0`/`q4_0` | 64k, shipped |
| --- | --- | --- |
| Steps / duration | 163 / 158 min, aborted | 70 / 63 min |
| Ended | no | on its own, in its first turn |
| Compactions | 3, at 80.1-80.5k | 3, at 48.3-48.9k |
| Context after one | 23-30k | 19-21k |
| `length` stops / steps at the budget | 0 / 0 | 0 / 0 |
| Largest thinking block | ~6.3k | ~6.9k |
| tok/s per step, median, incl. prompt | 21.9 | 25.7 |
| Result | host/join fails ("game not found") | runs, but turn-based, which makes it barely a game; rematch broken |

**The arithmetic held at 96k.** The trigger sat at 80k as planned, compactions came back at
23-30k, and the peak of 80.2k stayed inside the 95k verified clean. What went wrong was the process:
the game was written in 20 minutes, then the model built its own test harness, a headless DOM in
Node's `vm`, and spent from minute 58 to ~108 on one nested-quote escape in it (with `xxd`, `cmp`
and scratch files), and the next 50 minutes on the harness again. It never went back to the game.
Nothing in the log points at the window, so **64k stays `dedicated` for now**, and T-041 runs a
second pair before that is final. The harness rabbit hole is also what the
[agent prompt](#the-agent-prompt) now speaks to.

The control is a reading on variance as much as on 64k: the same profile and prompt that built a
working server-authoritative game on 2026-09-19 (the right-hand column above) built a turn-based
one here. That is what n = 1 at temperature 1.0 is worth.

## Thinking in the prompt

The chat template renders every earlier thinking block back into the prompt:

```jinja
{%- if preserve_thinking is undefined or preserve_thinking is true or loop.index0 > ns.last_query_index %}
    {{- '<|im_start|>' + message.role + '\n<think>\n' + reasoning_content + '\n</think>\n\n' + content }}
```

pi sends them: its thinking blocks carry `thinkingSignature: "reasoning_content"`, and the
openai-completions provider writes that field back onto each assistant message. In the
session above, the 29 745-character thinking block from the first turn (~7.4k tokens) rode
along in every later prompt.

`PRESERVE_THINKING=false` passes `--no-reasoning-preserve` (the fork's switch for the
template's `preserve_thinking`), which keeps thinking only for messages after the last user message - the current turn.
Note what that does **not** cover: inside one long agent turn there is no later user
message, so that turn's own thinking is all preserved. It pays off across turns, and after
a compaction, since pi feeds the summary back as a `user` message (`dist/core/messages.js`)
which resets `last_query_index`.

## The agent prompt

`$BONSAI_HOME/pi-agent/AGENTS.md`, installed from [`pi/pi-agents.md`](../pi/pi-agents.md), goes
into pi's system prompt at startup, for every session and both models; `--append-system-prompt`
and `--system-prompt` are the per-run equivalents. It is written as a description of the
situation with the reason for each point, not as rules, and that is a measured choice:

- **Rules are checked with turns.** The localagent runs showed a model that over-attends to
  everything in reach: "~80 lines" became `wc -l` five times, "read nothing else" became
  orientation reads, a stated turn limit became a count. Every hard rule added there was ignored or
  paid for in turns ([localagent.md](localagent.md#the-t-019-cli-run-where-the-turns-went)). So the
  file carries no number, no "never" or "must", and nothing the model could verify with a tool.
- **Thinking length is not a prompt matter.** This model ignores instructions about how long to
  think, the template's effort levels included ([Reasoning](#reasoning)); `BUDGET` is what stops
  it. The file only says why code belongs in the tool call: a block cut off at the budget loses
  whatever was drafted in it.
- **Each point answers a failure in a plain session**, not in the workflow. From the Tron runs
  ([Context budget](#context-budget)): the 96k session that spent two hours debugging its own
  headless-DOM test harness and never returned to the game; the Qwen session that wrote eleven
  tests on a bug report and left the bug in place; the 4096 run that claimed test runs it never
  did; leftover servers holding the ports of the next test.
- **It stays task-neutral.** Nothing about games, browsers or the Tron prompt, which is the
  benchmark: a prompt tuned to it would measure the prompt. That includes the HTML comment at
  its top, which pi passes to the model with the rest, so the reasons live here and not there.

The first version (until 2026-09-27) was four imperatives: think short, one step per turn, no
restating, minimal tool arguments. None of it was ever measured against no file at all. The
current one is unmeasured too; its reading is the next Tron pair in
[T-041](../backlog/T-041-tron-day-2.md).

## pi

`bonsai-pi` runs a private pi: `install.sh pi` puts version `PI_VERSION` into `$BONSAI_HOME/pi`
(`npm install --prefix`, no `-g`, no sudo), and the wrapper sets `PI_CODING_AGENT_DIR` to
`$BONSAI_HOME/pi-agent`. pi resolves every user path through that variable (`getAgentDir()`
in `dist/config.js`): providers, settings, `AGENTS.md`, auth, sessions.

The first version wrote into the global `~/.pi/agent` instead, and collided with any pi
already in use there:

- `defaultProvider`/`defaultModel` were overwritten, so a plain `pi` started on Bonsai.
- The compaction keys are global or per project, not per model (`settings-manager.js`).
  A 200k model then kept 8k of recent history per compaction instead of 20k.
- `AGENTS.md`, telling the model to think briefly on a small window, went into every
  model's system prompt - or, when the user had their own, ours was skipped.
- Whatever pi version was installed ran, while the budget arithmetic under
  [Context budget](#context-budget) reads pi 0.85.1's compaction code.

A project directory's own `.pi/settings.json` still applies to both instances; that is
pi's per-project override and intended.

pi reads providers from `models.json`. `contextWindow` decides when pi compacts, together with the settings under [Context budget](#context-budget) - not `maxTokens`, which is only the per-turn output cap. Unsloth's `unsloth start pi` hard-codes `maxTokens = min(context / 4, 8192)`, which cuts a single long reasoning turn off at 8k. That is why this setup uses its own config.

## Server lifecycle

`bonsai-pi` owns the server only when it started it. On start it checks `/health` on `PORT`;
with no answer it launches `bonsai-server` in the background and waits until `/health`
returns 200 (the model is loaded), at most `SERVER_START_TIMEOUT` seconds. Every run then
checks `/v1/models` for `MODEL_ALIAS`, so pi never talks to some other server on that port.

- **Shared server.** Each session registers its PID in `$BONSAI_HOME/run/sessions/` under a
  `flock`. The last session to leave stops the server; sessions that died without cleaning
  up are pruned by PID. `run/server.pid` exists only for a server `bonsai-pi` started, so a
  server started by hand is never stopped.
- **Own session (`setsid`).** The server runs outside the terminal's process group: Ctrl+C
  in pi - which cancels a generation - must not reach llama-server, which installs its own
  SIGINT handler and would quit.
- **Orphans.** A session killed with SIGKILL, or a terminal window closed hard, runs no trap:
  its server stays up with its pid still in `run/server.pid`. The next `bonsai-pi` prunes the
  dead session entries and adopts that server, so it stops when that session leaves. Verified.
- **Traps.** Closing the terminal (HUP), TERM or QUIT runs the cleanup. While pi runs, the wrapper
  catches SIGINT with a no-op: uncaught, bash would die with pi when pi exits on SIGINT and skip
  the cleanup. While waiting for the model, Ctrl+C aborts and stops the server.

Verified with a stand-in server and pi: one session, two overlapping ones, Ctrl+C caught by
pi, pi killed by SIGINT, Ctrl+C during load, HUP, a hand-started server, and a server that
dies during start. With the real model:

- The first session waits for the load: `model loaded` after 7.7-7.9 s, the same with the
  model file evicted from the page cache (`posix_fadvise DONTNEED`). A one-line `bonsai-pi -p`
  takes 14 s end to end. `SERVER_START_TIMEOUT` 300 has ample margin on this machine.
- llama-server exits on SIGTERM within ~1 s, and VRAM goes from 7 275 MiB back to 0.
- Two overlapping sessions share one server; the last to end stops it.
- SIGINT to one session's process group mid-generation: pi aborts its request (the server
  logs `cancel task`), the server keeps running and answers the other session.
- `run/` holds no session and no `server.pid` after each run.

### A server on another machine

`LISTEN_HOST` is what llama-server binds to, `SERVER_HOST` what the client side - `bonsai-pi`'s
health and model checks, and the `baseUrl` written into pi's `models.json` - connects to. Both
default to `127.0.0.1`, which is the whole setup on one machine. They were the same hardcoded
literal until it turned out that the machine with the GPU and the machine you work on need not
be the same one.

To serve one GPU box to another host: `LISTEN_HOST=0.0.0.0 bonsai-server` there, then
`SERVER_HOST=<box> ./install.sh pi` here and `bonsai-pi` as usual. `./install.sh pi` has to run
again because pi keeps a written copy of the URL - the same drift as `CTX` and `PORT`.

- **Autostart steps aside.** `bonsai-pi` starts and stops a server by pid and reads `SERVER_LOG`;
  neither exists for someone else's process on another host. With a non-local `SERVER_HOST` it
  therefore never starts one, says so once, and fails on the `/v1/models` check if nothing is
  serving. `SERVER_AUTOSTART` keeps its meaning for a local server.
- **There is no authentication.** The provider sends `apiKey: "none"` and llama-server asks for
  nothing, so `LISTEN_HOST=0.0.0.0` offers the model to everyone who can reach the port. On a
  network that is not yours, forward it instead - `ssh -N -L 8080:127.0.0.1:8080 <box>` - and
  leave `SERVER_HOST` at `127.0.0.1`; the tunnel needs no setting at all.
- **Latency is not the problem, bandwidth is not either.** A turn is one HTTP request and a
  token stream; on a LAN the round trip disappears next to a 27B model's generation time.

Verified: the URL that `config.env` derives for local, remote and remote-with-port, the
`models.json` written from it, and the four autostart branches under `set -e`. Not yet run
against a real remote server - the machine this was written on has no GPU.

## Unsloth Studio

`bonsai-studio` opens the model `MODEL` names in [Unsloth Studio](https://github.com/unslothai/unsloth)
instead of a bare llama-server: Studio's chat UI and API, this repo's build and flags. It is
`unsloth studio run` with three things changed.

- **The build.** `LLAMA_SERVER_PATH` points Studio at `LLAMA_SERVER`, the tree the model file
  pins. That is the first place Studio looks, ahead of its own `~/.unsloth/llama.cpp`, so Bonsai
  runs on the fork and Qwen3.8-Flash on the Unsloth tree this repo built, at the pinned source.
- **The flags.** `scripts/server-flags.sh` holds what `bonsai-server` passes, and `bonsai-studio`
  hands the same list to Studio, which appends it after its own flags: llama.cpp's last value
  wins, so the profile's placement, cache types, reasoning budget and `SERVER_ARGS` are what runs.
  The window goes as `--context-length`, MTP as `--speculative-type mtp` or `off`, one slot as
  `--parallel 1` (Studio's default of 4 splits `CTX`), sampling as Studio's pinning options,
  because Studio owns those flags and refuses or rewrites them as raw arguments.
- **Studio's own picks undone.** `--no-mmproj`, since no profile budgets VRAM for a vision
  projector that Studio loads when it finds one beside the GGUF; `--load-mode auto`, because Studio
  reads a model into memory (`none`) when it estimates it fits, and the experts in RAM are
  measured mmapped.

Two details of Studio's parser decide how the flags are written. Its **manual** memory mode
strips every offload flag from the pass-through and has no command line option for the expert
count, so `bonsai-studio` stays in **auto**, which keeps an explicitly requested window ("no
silent shrink") and passes the flags through untouched. And its command line reads a short
cluster as its own options: `-ctxcp 4` ends in `-p`, its port. `server-flags.sh` and the model
files therefore use long spellings only (`--n-gpu-layers`, `--ctx-checkpoints`, ...), and so must
extra arguments to `bonsai-studio`.

Studio adds flags of its own that are left alone: `--metrics`, `--slot-save-path` (it saves a
slot's KV cache to disk when it unloads an idle model), `--chat-template-kwargs` with the same
`preserve_thinking: false` as `PRESERVE_THINKING`, `--video-fps`, and for Bonsai
`--ctx-checkpoints 21` against llama.cpp's 32, sized from host RAM. It also sends a system prompt and
tool definitions of its own, ~1.3k tokens on a one-line question. Its port is 8888, it has its own
login and API keys, and `bonsai-pi` does not talk to it: pi stays on `bonsai-server`.

Verified on 2026-10-02 with Studio 2026.9.12 (`unsloth` package), headless and without the GPU,
which the agent sandbox does not have: for all three models Studio started our build with every
flag of the profile last on its command line and loaded at the profile's window. Qwen3.6 and
Qwen3.8-Flash answered a chat request through its API on the CPU (21 tok/s with MTP accepting
55 %, and 6.2); Bonsai's ternary weights read a prompt on the CPU too slowly to wait for. Not yet
run with the card, so VRAM and speed under Studio are unmeasured (T-038).

## localagent workflow

`bonsai-pi --localagent` runs a multi-agent build pipeline for this model. **Decided
2026-09-23: frozen and not recommended.** On a small CLI it finished in the time the model takes
alone; on the study's Tron prompt it was stopped after 2:50 with its first unit unfinished, where
the model alone built the game in 1:30. What stopped it was the model - compactions inside a
worker, whole-file rewrites, broken tests of its own - not the harness, so it stays in the repo
unchanged until a stronger local model is out. Its own file, [`localagent.md`](localagent.md),
has the runs, the shape, and how it runs on pi. What it constrains here is only the window: a
dispatched agent that ends on `length` comes back as `BLOCKED`, see
[Context budget](#context-budget).

## Sampling

`--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0` is the model card's **thinking-mode** preset,
which is the mode this setup runs (`--reasoning on`, and the whole budget arithmetic depends on
it). The card's second preset - `temperature=0.7, top_p=0.80, presence_penalty=1.5` - belongs to
instruct/non-thinking mode. It is a mode, not a temperature dial: taking the 0.7 alone into
thinking mode mixes two presets and is not what the card recommends.

`--min-p 0.0` has to be passed explicitly. llama.cpp defaults it to 0.05, so leaving it out
silently deviates from the preset; the flag's own help reads `0.0 = disabled`. This was the only
deviation from the model card in the shipped command line.

A temperature change buys no speed: 35.92 tok/s at 1.0 against 35.89 at 0.7, identical within
noise.

Speculative decoding is off. The fork offers draft-model-free n-gram modes via `--spec-type`,
and they were measured in three ways - no configuration beat the baseline on a real agent
workload, and loosening their triggers made it worse. Acceptance runs at 6-20 % where
break-even is above 50 %. The full result, including why a synthetic benchmark showed a
misleading 1.59x, is in [Performance](performance.md#speculative-decoding-tried-rejected).

## Preflight

`install.sh` runs [`scripts/preflight.sh`](../scripts/preflight.sh) before any step. It exists
because the two expensive steps come first and fail last: a CUDA build is 10 to 30 minutes and the
model is 5.6 GB, so a missing driver, a full disk or a 6 GB card used to be discovered after half
an hour of work rather than before it.

It checks the distro (a derivative by its base, from `ID_LIKE` and `UBUNTU_CODENAME`), free disk
against what the named steps will actually write (a model in the Hugging Face cache costs
nothing), `MemAvailable`, the driver for `BACKEND` (on native Linux, a module that Secure Boot
kept out), the CUDA toolchain the run will use (the installed `nvcc`, or the version apt would
install), `cmake` and `git` for a build without `deps`, total and used VRAM, Node for the `pi`
step (and whether nvm has a newer one off the `PATH`), and whether something is already answering
on `PORT`. Three properties matter:

- **It reports every item and exits once.** A list of five problems takes one pass to fix; five
  runs that each die on the next one take five.
- **It checks only the steps being run.** `./install.sh model link` needs no GPU at all, which is
  how a server on another machine gets set up, so the driver checks are skipped there.
- **Warnings do not stop it.** Low RAM, an unmeasured distro, a busy port: these are things to
  know, not things to block on. Only a missing driver, too little disk, a CUDA older than 12.4, a
  missing build tool, a card below 8 GB or a Node too old for pi are hard failures.

`SKIP_PREFLIGHT=1` bypasses it. The failure message says so, because the checks encode what was
true on three machines and should not be the thing that stops a fourth.

VRAM in use above 400 MiB is a warning rather than a failure: it usually means a desktop is on the
card, which is what `PROFILE=display` is for, but it can equally be another model server that will
be gone by the time this one starts. See [VRAM budget](#vram-budget).

## Troubleshooting

| Symptom | Cause · fix |
| --- | --- |
| `invalid ggml type 143` | Stock llama.cpp is running. Start through `bonsai-server`. |
| Generation slows sharply as context grows, GPU load low | Mixed K/V cache types on a build without `FA_ALL_QUANTS`: `FORCE=1 ./install.sh build` |
| `offloaded N/65 layers` with N < 65 | `--fit` is active or VRAM is taken. Check `nvidia-smi` and move the display to the iGPU. |
| Slower while a browser is visible | The browser renders on the RTX. Switch it to the iGPU in Windows graphics settings. |
| `sudo: a terminal is required` | Run `./install.sh deps` in a real terminal, not through an agent's shell. |
| `pi -p` hangs in scripts | pi waits on stdin without a TTY: add `< /dev/null`. |
| `pi` talks to another model, or ignores the budget | Plain `pi` is your global instance. Start `bonsai-pi`. |
| `bonsai-server exited during start` | Read `$BONSAI_HOME/server.log`; usually VRAM taken by another process, see `nvidia-smi`. |
| `no bonsai-server with model ... on port` | Something else listens on `PORT`. Stop it or set another `PORT`, then `./install.sh pi`. |
| Answer ends after exactly `MAX_TOKENS` | The output cap was hit. Raise `MAX_TOKENS` or lower `BUDGET`. |
| `stopReason: length` well below `MAX_TOKENS`, near a compaction | pi's output clamp: `BUDGET` too large for `RESERVE_TOKENS - 4096`. See [Context budget](#context-budget). |
| pi compacts every turn, most of the time goes into summarizing | `RESERVE_TOKENS`/`KEEP_RECENT_TOKENS` are unset or too large for `CTX`: `./install.sh pi`. See [Context budget](#context-budget). |
| Vulkan: ~1.2x below the numbers here, GTT above 400 MiB at 16k | Mesa < 25.2: `RADV_PERFTEST=nogttspill` is ignored. `deps` warns; take `mesa-vulkan-drivers` from backports. See [Other GPU backends](#other-gpu-backends). |
| Vulkan, Qwen: the first request fast, every later one on the same cache ~2x slower, GTT grows | `GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM` is unset, e.g. a server started by hand rather than through `bonsai-server`. See [qwen.md](qwen.md#on-the-rx-570-vulkan). |
| Vulkan: VRAM reads a few MiB right after load | Normal. RADV moves the weights into VRAM on the first request. Judge by tok/s, and read VRAM and GTT together. |
| Vulkan: ~2x slower, VRAM ~20 MiB, GTT ~6 GB | `GGML_VK_PREFER_HOST_MEMORY` is set. It is checked for presence, so `=0` also turns it on: unset it. |
| `vulkaninfo` lists no device, `deps` dies on it | Your user is not in the `render` group: `usermod -aG render $USER`, log in again. |
| `nvidia-smi` "couldn't communicate with the NVIDIA driver", native Linux | Secure Boot refused the module: its key is not enrolled. See [Secure Boot](#secure-boot). |
| `apt offers CUDA 12.0 here` from `deps` or preflight | Ubuntu 24.04 or a derivative. Install [CUDA from NVIDIA's repository](#cuda-from-nvidias-repository), then `./install.sh`. |
| `cmake: command not found` in `build` | `deps` was skipped. Run it, or install `cmake` yourself; preflight now says so first. |
| `node: v18... - nvm has v24...` | nvm is loaded by `~/.bashrc` only. Run from an interactive shell, or `source ~/.nvm/nvm.sh`. |
| `prebuilt ... has no CUDA backend` from `build` (Qwen3.8-Flash on Studio's prebuilt, `LLAMA_PREBUILT=unsloth`) | Unsloth was installed before the NVIDIA driver worked and chose Vulkan or CPU. Repair it in Studio. |
| `preflight: N problem(s)` | Each line above it says what and how. `SKIP_PREFLIGHT=1 ./install.sh` goes ahead anyway. |
| `preflight` warns that VRAM is already in use | A desktop or another server is on the card. `PROFILE=display`, or free it. See [VRAM budget](#vram-budget). |
| `download failed` from `model` | Run `./install.sh model` again; `curl -C -` resumes from the `.part` file. |
| `patch does not apply` from `build` | `LLAMA_COMMIT` moved and `patches/$BACKEND/` was not rebased. Rebase it, or check whether the pin already carries the change and delete the patch. |
