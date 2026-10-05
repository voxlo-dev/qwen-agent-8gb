# Setup: build, toolchain, platforms

What `install.sh` needs and why its steps look the way they do, per platform, plus preflight and
troubleshooting. Each choice answers a failure seen on an RTX 4060 Ti 8 GB, under WSL2 first and
native Linux since 2026-09-29.

## Build

- **Static** (`BUILD_SHARED_LIBS=OFF`): the binary carries its own ggml/llama code, so it cannot pick up another llama.cpp's shared libraries from the same directory.
- **`GGML_CUDA_FA_ALL_QUANTS=ON`**: without it, CUDA flash attention only handles K and V of the *same* type. A mixed cache such as `q8_0`/`q4_0` then falls back to the CPU. Generation speed dropped from 34 to 20 tok/s at 2k context and down to 8 tok/s at 10k, with the GPU at 39 % load.
- **gcc-13 as CUDA host compiler**: Ubuntu's CUDA 12.4 `nvcc` refuses gcc newer than 13, and newer Ubuntu releases default to gcc 15.
- **`CMAKE_CUDA_ARCHITECTURES`** comes from `nvidia-smi` (`89` for Ada). Compiling for one architecture is much faster than for the default set.
- **`GGML_CUDA_CUB_3DOT2=ON`**, Unsloth's tree on CUDA only (`LLAMA_CMAKE_ARGS` in the Qwen model files): cmake fetches CCCL v3.2.0 from NVIDIA's GitHub at configure time, so that build needs github.com, and the toolkit's own CCCL (2.8 in 12.9) is not used. Without it Qwen3.8-Flash's sparse attention runs the CUDA pool out of the card at 19-48k of context ([qwen38-flash.md](qwen38-flash.md), T-049). Any toolkit >= 12.4 works with it; CUDA 13 is not needed.
- **ccache** speeds up rebuilds and is used when present; the build works without it.
- OpenSSL is not needed: it only enables HTTPS model downloads inside llama-server, and `qwen-server` passes a local path.
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
  ROCm/HIP and Metal kernels; untested. [Other GPU backends](bonsai.md#other-gpu-backends) has what
  Vulkan delivers and why.

**Node.js >= 22.19** for pi (`engines` in its `package.json`) comes from apt on Ubuntu 26.04 only:
24.04 ships 18.19, Debian 13 20.19. nvm is the tested source (v24.21 on Mint 22.3); it reaches
only shells that read `~/.bashrc`, so a distro Node left in `/usr/bin` still wins elsewhere, and
preflight says which one it found. NodeSource works the same way through apt. pi takes 440 MB in
`$QWEN_HOME/pi`.

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
Unsloth saw only the iGPU and installed CPU torch and the Vulkan llama.cpp build.

## Windows

**Setting it up.** In PowerShell as administrator, `wsl --install -d Ubuntu`, reboot if it asks,
then open Ubuntu and work entirely inside it:

- **The NVIDIA driver belongs on the Windows side only.** WSL2 passes the GPU through; a Linux
  NVIDIA driver inside Ubuntu breaks the passthrough. `nvidia-smi` inside Ubuntu must work before
  anything else.
- **Keep the repo in the Linux filesystem**, under `~`, not in `/mnt/c/`: building across the
  boundary is several times slower.
- **Give WSL2 the RAM the model needs.** It sees half the Windows RAM by default: raise `memory=`
  in `%UserProfile%\.wslconfig`, then `wsl --shutdown`. Preflight checks it.
- AMD cards under WSL2 are untested; use native Linux for the Vulkan backend. Both Qwen models are
  30-50 % faster on native Linux than under WSL2 ([qwen36.md](qwen36.md#native-linux)).

**Native Windows is declined; WSL2 is the Windows path**, and it was the reference platform - every
CUDA number in these docs until 2026-09-29 was measured on Windows 11 + WSL2 + Ubuntu 26.04. So the question is not
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
- **`qwen-pi` is the real cost.** `setsid`, `flock`, `kill -0`, pruning sessions by pid, and the
  HUP/TERM/QUIT traps that make [Server lifecycle](agent.md#server-lifecycle) work have no Windows
  counterpart. It would be reinvented with job objects and a mutex - the one piece of this repo
  where the failure modes were expensive to find, rebuilt on a platform where they would have to be
  found again.

Git Bash or MSYS2 is not the shortcut it looks like: `nvidia-smi` and cmake run there, `/proc`,
`flock` and `setsid` do not.

Against roughly 700 lines of PowerShell, a second test matrix and a second set of measurements,
the gain is that a Windows user does not run `wsl --install`. The one argument with substance is
speed - native would not pay the WSL2 passthrough. For Bonsai it is measured now and there is none:
36.6 tok/s on native Linux against 36 under WSL2. For the MoE models there is, 30-100 %, because
their experts are read from host memory ([qwen36.md](qwen36.md#native-linux)). That gap argues for
native Linux, which this repo already supports, not for a native Windows port, which is unmeasured
and would pay its own costs; it is what a measurement on native Windows would have to beat.

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

## Preflight

`install.sh` runs [`scripts/preflight.sh`](../scripts/preflight.sh) before any step. It exists
because the two expensive steps come first and fail last: a CUDA build is 10 to 30 minutes and the
model 5.6 to 88 GB, so a missing driver, a full disk or a 6 GB card used to be discovered after half
an hour of work rather than before it.

It checks the distro (a derivative by its base, from `ID_LIKE` and `UBUNTU_CODENAME`), free disk
against what the named steps will actually write (a model in the Hugging Face cache costs
nothing, and of a split GGUF only the missing parts count), `MemAvailable`, the driver for `BACKEND` (on native Linux, a module that Secure Boot
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

It also says which models the machine's RAM runs and which one it recommends: `MemTotal` against
each model file's `MODEL_RAM_MB` plus ~2 GB, the same gate the selected model is held to, and
Qwen3.6 as the recommendation wherever it fits (Qwen3.8-Flash is never recommended, only chosen).
Before preflight, a first `./install.sh` without `MODEL` shows the same list as a numbered question;
without a terminal it takes the recommendation. The answer is recorded in `$QWEN_HOME/model.env`
only once preflight has passed, so a model the machine cannot hold never sticks
([README](../README.md#install-in-detail)). An install from before the rename (in `bonsai-local`,
with a `pi-agent/` and no `model.env`) keeps Bonsai, which it ran until then. Both
read the model files with `model_var` in `scripts/lib.sh`, so a new model file joins the list by
its `MODEL_RAM_MB`, `MODEL_TITLE` and `MODEL_ROLE`.

VRAM in use above 400 MiB is a warning rather than a failure: it usually means a desktop is on the
card, which is what `PROFILE=display` is for, but it can equally be another model server that will
be gone by the time this one starts. See [VRAM budget](bonsai.md#vram-budget).

## Troubleshooting

| Symptom | Cause · fix |
| --- | --- |
| `invalid ggml type 143` | Stock llama.cpp is running. Start through `qwen-server`. |
| Generation slows sharply as context grows, GPU load low | Mixed K/V cache types on a build without `FA_ALL_QUANTS`: `FORCE=1 ./install.sh build` |
| `offloaded N/65 layers` with N < 65 | `--fit` is active or VRAM is taken. Check `nvidia-smi` and move the display to the iGPU. |
| Slower while a browser is visible | The browser renders on the RTX. Switch it to the iGPU in Windows graphics settings. |
| `sudo: a terminal is required` | Run `./install.sh deps` in a real terminal, not through an agent's shell. |
| `pi -p` hangs in scripts | pi waits on stdin without a TTY: add `< /dev/null`. |
| `pi` talks to another model, or ignores the budget | Plain `pi` is your global instance. Start `qwen-pi`. |
| `qwen-server exited during start` | Read `$QWEN_HOME/server.log`; usually VRAM taken by another process, see `nvidia-smi`. |
| `no qwen-server with model ... on port` | Something else listens on `PORT`. Stop it or set another `PORT`, then `./install.sh pi`. |
| Answer ends after exactly `MAX_TOKENS` | The output cap was hit. Raise `MAX_TOKENS` or lower `BUDGET`. |
| `stopReason: length` well below `MAX_TOKENS`, near a compaction | pi's output clamp: `BUDGET` too large for `RESERVE_TOKENS - 4096`. See [Context budget](agent.md#context-budget). |
| pi compacts every turn, most of the time goes into summarizing | `RESERVE_TOKENS`/`KEEP_RECENT_TOKENS` are unset or too large for `CTX`: `./install.sh pi`. See [Context budget](agent.md#context-budget). |
| Vulkan: ~1.2x below the numbers here, GTT above 400 MiB at 16k | Mesa < 25.2: `RADV_PERFTEST=nogttspill` is ignored. `deps` warns; take `mesa-vulkan-drivers` from backports. See [Other GPU backends](bonsai.md#other-gpu-backends). |
| Vulkan, Qwen: the first request fast, every later one on the same cache ~2x slower, GTT grows | `GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM` is unset, e.g. a server started by hand rather than through `qwen-server`. See [qwen36.md](qwen36.md#on-the-rx-570-vulkan). |
| Vulkan: VRAM reads a few MiB right after load | Normal. RADV moves the weights into VRAM on the first request. Judge by tok/s, and read VRAM and GTT together. |
| Vulkan: ~2x slower, VRAM ~20 MiB, GTT ~6 GB | `GGML_VK_PREFER_HOST_MEMORY` is set. It is checked for presence, so `=0` also turns it on: unset it. |
| `vulkaninfo` lists no device, `deps` dies on it | Your user is not in the `render` group: `usermod -aG render $USER`, log in again. |
| `nvidia-smi` "couldn't communicate with the NVIDIA driver", native Linux | Secure Boot refused the module: its key is not enrolled. See [Secure Boot](#secure-boot). |
| `apt offers CUDA 12.0 here` from `deps` or preflight | Ubuntu 24.04 or a derivative. Install [CUDA from NVIDIA's repository](#cuda-from-nvidias-repository), then `./install.sh`. |
| `cmake: command not found` in `build` | `deps` was skipped. Run it, or install `cmake` yourself; preflight now says so first. |
| `node: v18... - nvm has v24...` | nvm is loaded by `~/.bashrc` only. Run from an interactive shell, or `source ~/.nvm/nvm.sh`. |
| `preflight: N problem(s)` | Each line above it says what and how. `SKIP_PREFLIGHT=1 ./install.sh` goes ahead anyway. |
| `preflight` warns that VRAM is already in use | A desktop or another server is on the card. `PROFILE=display`, or free it. See [VRAM budget](bonsai.md#vram-budget). |
| `download failed` from `model` | Run `./install.sh model` again; `curl -C -` resumes from the `.part` file. |
| `patch does not apply` from `build` | `LLAMA_COMMIT` moved and `patches/$BACKEND/` was not rebased. Rebase it, or check whether the pin already carries the change and delete the patch. |
