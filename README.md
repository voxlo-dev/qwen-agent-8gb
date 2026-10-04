# Qwen Agent for 8 GB VRAM

**A local coding agent on an ordinary 8 GB graphics card. The card was never the limit: the RAM
next to it decides how large a model it runs.**

The models that make good agents do not fit in 8 GB. Mixture-of-experts models do not have to: only
a few billion of their parameters work on any token, so the experts can live in system RAM while the
card holds attention, the KV cache and the context window. This repo builds llama.cpp, fetches a
pinned model and configures the [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)
coding agent against it, with a context budget measured for each model. No API key, no rate limit,
nothing leaving the machine.

## Which model

Same PC, same 8 GB card (RTX 4060 Ti), three models, each bought with system RAM instead of VRAM:

| RAM next to the card | `MODEL` | Model | Generation | Window | For |
| --- | --- | --- | --- | --- | --- |
| any | `bonsai` | [Ternary-Bonsai-2-27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf), dense, all on the card | 36 tok/s | 64k | simple, well-scoped tasks |
| **32 GB** | **`qwen36-35b`** | **[Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)**, ~24 GB of experts in RAM | **52-65 tok/s** | **131k** | **the recommendation, and the default** |
| 64 GB | `qwen38-flash` | [Qwen3.8-Flash-Next](https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF), 125B, every expert in RAM | ~19 tok/s | 131k | the strongest, experimental, slow |

Native Linux numbers; under WSL2 the two Qwen models are 30-50 % slower, because WSL2 reaches host
memory slowly ([why](docs/qwen36.md#native-linux)). `./install.sh` reads your RAM, lists the three
with what runs here, and asks.

**Why Qwen3.6 is the default.** On the study's multiplayer-game prompt (the same prompt in a plain
`qwen-pi` session, judged by hand) Qwen3.6 built the game in 9 minutes and tested it end to end in a
browser in another 9. Bonsai's two sessions that day ran past 90 minutes without a working game,
and Qwen3.8-Flash builds more and finishes much later. One session per row, so a reading rather than a
ranking: [docs/agent-sessions.md](docs/agent-sessions.md).

**Bonsai** is the model for a machine without RAM to spare: a dense 27B whose ternary weights
compress to 5.95 GB, everything on the card, nothing in RAM. Good for small, well-scoped tasks; on a
whole project it loses its way: [docs/bonsai.md](docs/bonsai.md).

## What you get

- **The model, pinned and checksummed**, on the llama.cpp tree it was measured on: Unsloth's for
  both Qwen models (built from its pinned source), the [PrismML fork](https://github.com/PrismML-Eng/llama.cpp)
  for Bonsai, mainline for Qwen3.6 on AMD.
- **A placement measured to the last few hundred megabytes** of the card: which expert layers stay
  in RAM, the KV cache type, the ubatch, and for Qwen3.6 multi-token prediction drafting, worth
  +33-54 % on real output.
- **The pi coding agent, configured for the model**, not just pointed at it: its own private
  instance, a context budget that keeps it from compacting every single turn, a thinking budget
  that fits under its output cap, a timeout for hung commands, and an `AGENTS.md` for a local
  model. Your own pi keeps its settings.
- **One command to install it**, and a preflight that tells you in ten seconds whether your machine
  can run it, before anything downloads or compiles.

## Install

You need an **8 GB GPU that is not driving your monitor**, Linux or WSL2, the RAM from the table
above, and disk for the model (22 GB for Qwen3.6, plus ~10 for the build and toolchain).
`install.sh` checks your machine first and stops with a list of anything missing.

```bash
git clone https://github.com/voxlo-dev/qwen-agent-8gb.git
cd qwen-agent-8gb
./install.sh                    # NVIDIA; asks which model
BACKEND=vulkan ./install.sh     # AMD
```

A 10 to 30 minute compile and the model download; re-running is safe. On Windows, set up WSL2
first: [On Windows](#on-windows). Single steps, paths and the full list:
[Install in detail](#install-in-detail) and [Requirements](#requirements).

## Use

```bash
qwen-pi            # in your project directory; arguments go to pi
```

`qwen-pi` starts the server in the background when none is running, waits for the model to load, and stops the server again when the last `qwen-pi` session ends. Its output goes to `$QWEN_HOME/server.log`. A server you started yourself is used and left running:

```bash
qwen-server        # terminal 1, ready at "listening on http://127.0.0.1:8080"; Ctrl+C stops it
qwen-pi            # terminal 2
```

Both run the model `./install.sh` recorded; `MODEL=bonsai qwen-pi` runs another installed one. `qwen-pi` is a separate pi instance, so a pi you use with other models keeps its own settings. The server is also a plain OpenAI-compatible endpoint at `http://127.0.0.1:8080/v1`, model `qwen3.6-35b-a3b` (`qwen3.8-flash`, `bonsai-27b`).

If you use [Unsloth Studio](https://github.com/unslothai/unsloth), `qwen-studio` opens the same model in it, on this repo's build and with the same window, placement and reasoning flags, at the same VRAM and speed. Studio serves its chat UI and an API with its own key at `http://127.0.0.1:8888`; arguments go to `unsloth studio run` (for example `--port`), and `--print` shows the command. One model per start: details in [docs/agent.md](docs/agent.md#unsloth-studio).

`qwen-pi --localagent` starts a multi-agent workflow that is frozen and **not recommended**: [docs/localagent.md](docs/localagent.md#status).

## What is measured

Speed, VRAM and the window are measured per model and reproducible from this repo; every
non-default setting names the measurement behind it in [`docs/`](docs/dev.md). Agent quality is
measured as single sessions on one prompt ([docs/agent-sessions.md](docs/agent-sessions.md)), which
is enough to rank Qwen3.6 above Bonsai for real tasks and not enough for more. A reproducible test
with several runs per model is next ([T-050](backlog/T-050-reproducible-agent-test.md)).

The background is a study of eight local models as coding agents on an 8 GB card, run a week before
this repo existed: dense models wrote the best code at ~4 tok/s, the fast MoE models left broken
results. [docs/model-comparison.md](docs/model-comparison.md) has it. Bonsai was the first answer
(a dense model squeezed onto the card), the MoE models with their experts in RAM the one that held.

## Requirements

Two backends, chosen with `BACKEND` (default `cuda`).

**Measured** - a card enters this table only with a logged run:

| Card | `BACKEND` | System | Qwen3.6 | Bonsai |
| --- | --- | --- | --- | --- |
| RTX 4060 Ti 8 GB | `cuda` | Linux Mint 22.3 native (Ubuntu 24.04 base), CUDA 12.9 from NVIDIA | 52-65 tok/s | 36.6 tok/s |
| RTX 4060 Ti 8 GB | `cuda` | Windows 11 + WSL2, Ubuntu 26.04 | 39-45 tok/s | 36 tok/s |
| AMD RX 570 8 GB | `vulkan` | Debian 13, RADV, Mesa 26.1 | ~25 tok/s | 7 tok/s |

Qwen3.8-Flash is measured on the 4060 Ti only (CUDA): ~19 tok/s native with 64 GB, 9-10 under WSL2.
On the RX 570, Qwen3.6 runs on mainline llama.cpp with its experts in RAM, at 2.5-3.5x Bonsai's speed
there ([docs/qwen36.md](docs/qwen36.md#on-the-rx-570-vulkan)).

**Expected to work, unmeasured** - same architecture families, nobody has reported numbers.
`build` takes the CUDA arch from `nvidia-smi` and the Vulkan build is generic, so these should
build and run; whether the profiles still fit is the open question, because they were measured
with a few hundred MiB of headroom on one driver.

| | |
| --- | --- |
| NVIDIA | RTX 20xx to 40xx with 8 GB or more. RTX 50xx needs CUDA >= 12.8, untested ([T-020](backlog/T-020-supported-hardware.md)) |
| AMD | RDNA2 and RDNA3 through Vulkan, which should be considerably faster than the RX 570 |
| More than 8 GB | works, but wastes the card; more expert layers or a larger window are yours to measure, see [Context budget](docs/agent.md#context-budget) |

If you run one of these, a [hardware report](../../issues/new?template=hardware-report.yml) is the
most useful thing you can send.

**Not supported:** less than 8 GB of VRAM, ROCm/HIP, Metal, and CPU-only. Vulkan is the one AMD path.

[Toolchain](docs/setup.md#toolchain) says what is known beyond that, [Other GPU backends](docs/bonsai.md#other-gpu-backends) where the Vulkan numbers come from.

- Linux, native or WSL2; native is 30-50 % faster for both Qwen models. CUDA: a working NVIDIA driver (`nvidia-smi` runs; under WSL2 it is installed on the Windows side; natively with Secure Boot on, its module key must be enrolled, see [Secure Boot](docs/setup.md#secure-boot)). Vulkan: the `amdgpu` kernel driver and **Mesa >= 25.2** (Debian 13 ships 25.0.7; take `mesa-vulkan-drivers` from `trixie-backports`), and your user in the `render` group
- A GPU with 8 GB VRAM, of which ~7.4 GB must be **free**: the GPU should drive no display, see [The one change](#the-one-change-worth-more-than-any-flag)
- **RAM, by model**: Qwen3.6 holds ~24 GB while serving and needs ~26 GB in total (a 32 GB machine; under WSL2 raise `memory=` in `%UserProfile%\.wslconfig`, which defaults to half). Qwen3.8-Flash runs from 48 GB and needs ~58 GB available to keep every expert cached (a 64 GB machine on native Linux with the browser closed, [why](docs/qwen38-flash.md#native-linux-every-expert-cached)). Bonsai needs 8 GB: it is read through `mmap` and sits below 700 MB once loaded. Building caps its parallelism at ~2 GB per job, see [RAM and build memory](docs/setup.md#ram-and-build-memory)
- **Disk, by model**: 22 GB for Qwen3.6, 88 GB for Qwen3.8-Flash, 5.6 GB for Bonsai; plus 1-2 GB per llama.cpp build (both Qwen models share one), ~0.5 GB for pi, and ~5.4 GB for the CUDA toolkit from apt (7.3 GB for NVIDIA's 12.9)
- CUDA: toolkit >= 12.4 with a host gcc it accepts; >= 12.8 for RTX 50xx. `./install.sh deps` installs it via apt, which yields 12.4 on Ubuntu 26.04 only; on 24.04 and its derivatives (Linux Mint 22) it stops and points to [CUDA from NVIDIA's repository](docs/setup.md#cuda-from-nvidias-repository), four commands, after which `./install.sh` runs through. Vulkan: `glslc`, the Vulkan headers and loader; `deps` installs them on Debian and Ubuntu
- Node.js >= 22.19 for pi: apt has it on Ubuntu 26.04 only (24.04 ships 18, Debian 13 20), elsewhere take it from [nvm](https://github.com/nvm-sh/nvm) or NodeSource

Without apt, install the toolchain yourself (CUDA and gcc, or glslc and the Vulkan SDK; plus cmake, git, python3) and skip `deps`: `./install.sh build model pi link`.

## Install in detail

`./install.sh` runs every step in order. Name one or more steps to run just those; each one skips
work that is already done:

| Step | Does |
| --- | --- |
| `deps` | apt toolchain for `BACKEND`: build tools, cmake, then gcc-13 and the CUDA toolkit (kept as is when an `nvcc` >= 12.4 is already installed), or glslc and the Vulkan headers (asks for sudo, so run it in a real terminal) |
| `build` | fetches the model's llama.cpp tree at its pin (a git commit, or for the Qwen models on CUDA Unsloth's source tarball, checksummed), applies the model's patches, builds `llama-server` (`FORCE=1` rebuilds) |
| `model` | links the GGUF from the Hugging Face cache, or downloads and checksums it |
| `pi` | installs its own pinned pi and writes its config for the model: provider `local` as default, the context budget, `AGENTS.md`, its extensions. A pi you already have and `~/.pi` stay untouched |
| `link` | puts `qwen-server`, `qwen-pi` and `qwen-studio` into `~/.local/bin` |

**The model is chosen once.** Without `MODEL`, the first `./install.sh` lists the three models
with what your RAM allows, asks, and records the answer in `$QWEN_HOME/model.env`; not on a
terminal it takes Qwen3.6. The `qwen-*` commands run that model unless `MODEL` says otherwise. A
second model installs next to the first with `MODEL=bonsai ./install.sh`, its own build, model and
pi config, and leaves the recorded one alone; to change that, edit `model.env`.

`BACKEND` has to be set for every later `./install.sh build` too (or exported): `build` decides on it which toolchain to use and which patches from [`patches/`](patches/) to apply. `qwen-server` reads it as well.

Everything lands in `~/.local/share/qwen-local` (`QWEN_HOME`): builds, models, pi, and pi's config and sessions in `pi-agent-{model}/` (Bonsai's in `pi-agent/`). An install from before the rename, in `~/.local/share/bonsai-local` or wherever `BONSAI_HOME` points, is used where it is. `SKIP_PREFLIGHT=1` skips the checks if you know better than they do.

### On Windows

This runs under WSL2, and the reference machine for the CUDA numbers is exactly that. In
PowerShell as administrator:

```powershell
wsl --install -d Ubuntu
```

Reboot if it asks, then open Ubuntu and work entirely inside it. Two things matter:

- **The NVIDIA driver belongs on the Windows side only.** WSL2 passes the GPU through. Do not
  install a Linux NVIDIA driver inside Ubuntu; it will break the passthrough. Check it works with
  `nvidia-smi` inside Ubuntu before you install anything here.
- **Keep the repo in the Linux filesystem**, under `~`, not in `/mnt/c/`. Building across the
  Windows filesystem boundary is several times slower.

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/voxlo-dev/qwen-agent-8gb.git
cd qwen-agent-8gb && ./install.sh
```

AMD cards under WSL2 are untested. Use native Linux for the Vulkan backend.

There is no native Windows install and there will not be one: the reference machine for the
CUDA numbers is WSL2, and a second PowerShell implementation of the install and the server
lifecycle is not maintainable next to it. The reasoning is in
[`docs/setup.md#windows`](docs/setup.md#windows).

## Configure

Each model has two **profiles**, which set the context window and the four budget values:

| `PROFILE` | Qwen3.6 | Qwen3.8-Flash | Bonsai | For |
| --- | --- | --- | --- | --- |
| `dedicated` (default) | 131k, 7.4 GB VRAM | 131k, 7.4 GB | 64k, 7.75 GB | the GPU drives no display |
| `display` | 131k, two expert layers fewer on the card | 131k | 48k | the GPU also renders a desktop, which takes 0.5-1.2 GB |

```bash
PROFILE=display ./install.sh pi     # pi's copy of the values
PROFILE=display qwen-pi             # and every run after
```

They are in [`profiles/{model}/`](profiles/); the values inside constrain each other, see [Context budget](docs/agent.md#context-budget). Everything else lives in [`config.env`](config.env) and the model's file in [`models/`](models/). A variable set in the environment wins over all of them, and extra arguments go straight to llama-server:

```bash
CTX=65536 qwen-server
SPEC_TYPE=none qwen-server
qwen-server --port 9000
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `MODEL` | from `model.env`, else `qwen36-35b` | `qwen36-35b`, `qwen38-flash` or `bonsai`, see [Which model](#which-model) |
| `QWEN_HOME` | `~/.local/share/qwen-local` | where builds, models and pi live; an existing `bonsai-local` or `BONSAI_HOME` is kept |
| `BACKEND` | `cuda` | `cuda` or `vulkan`; read by `deps`, `build` and `qwen-server`. `build` rebuilds by itself when it changes |
| `CUDA_ARCH` | the card's | CUDA architecture `build` compiles for, e.g. `89`; set it to build where `nvidia-smi` sees no card |
| `BUILD_JOBS` | auto | parallel compile jobs; empty derives them from free RAM and core count, see [RAM and build memory](docs/setup.md#ram-and-build-memory) |
| `CTX` | per profile | context window in tokens; see [Context window](docs/context-window.md) for what fits |
| `CPU_MOE` / `UB` | per profile | Qwen only: layers whose experts stay in RAM, and the ubatch; they trade VRAM against prompt speed, see [docs/qwen36.md](docs/qwen36.md#what-it-decides) |
| `KV_K` / `KV_V` | per model | KV cache types; `q8_0`/`q8_0` for Qwen, `q8_0`/`q4_0` for Bonsai, measured against `f16` in [Context window](docs/context-window.md#kv-cache-quality) |
| `EFFORT` | per model | chat-template reasoning effort where the template reads one (`low`, `medium`, `xhigh`); not Qwen3.6 |
| `SPEC_TYPE` | per model | speculative decoding; `draft-mtp` for Qwen3.6. Turn it off with `none`: an empty value falls back to the model's default |
| `BUDGET` | per profile | thinking tokens per turn; at most `RESERVE_TOKENS - 4096 -` a tool call, see [Context budget](docs/agent.md#context-budget) |
| `PRESERVE_THINKING` | `false` | keep earlier turns' thinking in the prompt |
| `MAX_TOKENS` | per profile | pi's output cap per turn |
| `RESERVE_TOKENS` | per profile | window pi holds back for the answer; it compacts above `CTX - RESERVE_TOKENS` |
| `KEEP_RECENT_TOKENS` | per profile | recent history a compaction keeps |
| `PORT` | `8080` | server port |
| `LISTEN_HOST` | `127.0.0.1` | address the server binds to; `0.0.0.0` to serve other machines — there is no authentication |
| `SERVER_HOST` | `127.0.0.1` | address `qwen-pi` and pi connect to; set it to run the server on [another machine](docs/agent.md#a-server-on-another-machine) |
| `PI_VERSION` | `0.85.1` | pi version the context budget was measured with |
| `SERVER_AUTOSTART` | `true` | let `qwen-pi` start and stop the server |
| `SERVER_START_TIMEOUT` | `300` | seconds `qwen-pi` waits for the model to load |
| `TOOL_TIMEOUT` | `300` | seconds after which a bash call the model starts without its own timeout is ended; `0` turns it off, see [Tool timeout](docs/agent.md#tool-timeout) |
| `UNSLOTH_CLI` | Studio's venv | the `unsloth` command `qwen-studio` runs; falls back to one on `PATH` |

After changing the profile, `CTX`, `SERVER_HOST`, `PORT`, `MAX_TOKENS`, `RESERVE_TOKENS` or `KEEP_RECENT_TOKENS`, run `./install.sh pi` again, with the same `MODEL`, so pi's config matches the server.

The last three carry each other: pi's own defaults assume a 200k window and make it compact on every single turn at these sizes. [Context budget](docs/agent.md#context-budget) has the measurements and the constraints between them.

## Performance

RTX 4060 Ti 8 GB, Ryzen 7 7800X3D, the `dedicated` profiles. Natural output is a chat turn with
thinking; the depth columns are one long prompt, then generation after it.

| Model | Natural output | Generation at 43k | Prompt at 43k | Window | VRAM |
| --- | --- | --- | --- | --- | --- |
| Qwen3.6, native, MTP | 52-65 tok/s | 49 tok/s | 914 tok/s | 131k | 7 374 MiB |
| Qwen3.6, WSL2, MTP | 39-45 | 34 | 700 | 131k | 7 374 |
| Qwen3.8-Flash, native, 64 GB | 18.6-18.9 | - | ~100 (5k prompt) | 131k | 7 386 |
| Bonsai, native or WSL2 | 36 | 26 | 415 | 64k | 7 747 |

The per-model pages have the grids behind each row: [Qwen3.6](docs/qwen36.md#what-was-measured),
[Qwen3.8-Flash](docs/qwen38-flash.md), [Bonsai](docs/bonsai.md). Every window is filled once to the
edge before it ships, because one that loads is not one that holds
([context-window.md](docs/context-window.md)). Bonsai's generation is bandwidth-bound at ~80 % of
what the card sustains; [Performance](docs/performance.md) has the roofline and what was tried and
rejected.

AMD RX 570 8 GB through Vulkan (RADV, Mesa 26.1.2): Qwen3.6 at ~25 tok/s and ~116 tok/s on an
847-token prompt at 131k, Bonsai at 7 tok/s and 54, with the PTQ1_0 decode from
[`patches/vulkan`](patches/vulkan/). Batch territory for Bonsai, a usable conversation for Qwen3.6
([docs/qwen36.md](docs/qwen36.md#on-the-rx-570-vulkan), [Other GPU backends](docs/bonsai.md#other-gpu-backends)).

### The one change worth more than any flag

**Do not let this GPU drive your monitor.** A desktop on the same card takes 0.5 to 1.2 GB of VRAM
and competes for GPU time, and both come out of the model: moving the display to the motherboard's
iGPU took generation from 21 to 34 tok/s in the same session. Enable the iGPU in the BIOS, plug the
monitor into the mainboard, and set browsers to "Power saving" under Windows *Settings, System,
Display, Graphics*. It costs a cable and beats every tuning knob in this repo combined. If you
cannot, `PROFILE=display` makes room: two expert layers fewer on the card for Qwen, a 48k window for Bonsai.

## Docs

| | |
| --- | --- |
| [docs/setup.md](docs/setup.md) | build, toolchain and CUDA per distro, Secure Boot, Windows, preflight, troubleshooting |
| [docs/agent.md](docs/agent.md) | pi, its context budget, the agent prompt, the server lifecycle, Unsloth Studio |
| [docs/agent-sessions.md](docs/agent-sessions.md) | every agent session on the study's Tron prompt, all models in one table |
| [docs/bonsai.md](docs/bonsai.md) | Bonsai: format, VRAM, KV cache, reasoning, sampling, Vulkan |
| [docs/qwen36.md](docs/qwen36.md) | Qwen3.6-35B-A3B with its experts in RAM, and the slot for Qwen 4 |
| [docs/qwen38-flash.md](docs/qwen38-flash.md) | Qwen3.8-Flash-Next, 125B, every expert in RAM |
| [docs/performance.md](docs/performance.md) | what limits generation speed, and what was tried and rejected |
| [docs/context-window.md](docs/context-window.md) | how large a window fits on 8 GB, and what the KV cache types cost in quality, per model |
| [docs/model-comparison.md](docs/model-comparison.md) | eight local models as coding agents on 8 GB, measured before this repo existed |
| [docs/localagent.md](docs/localagent.md) | the multi-agent workflow: frozen, not recommended, and why |
| [AGENTS.md](AGENTS.md) | where contributors and AI agents start |

## Contributing

Issues and pull requests welcome, and a
[hardware report](../../issues/new?template=hardware-report.yml) most of all: two cards have been
measured, everything else under [Requirements](#requirements) is a guess. [CONTRIBUTING.md](CONTRIBUTING.md) has the
one rule, which is that a non-default choice arrives with the measurement that justifies it.

## Uninstall

```bash
rm -rf ~/.local/share/qwen-local ~/.local/bin/qwen-server ~/.local/bin/qwen-pi ~/.local/bin/qwen-studio
```

(`~/.local/share/bonsai-local` for an install from before the rename.) That includes the models,
pi and its sessions. The build cache in `~/.cache/ccache` and the apt packages from
`deps` stay.

## Your hardware

This fills an 8 GB card to within a few hundred megabytes, and for the Qwen models keeps tens of
gigabytes of system RAM busy for as long as the server runs. That is a memory allocation, not an
electrical one: nothing here overclocks, raises a power limit or touches a fan
curve, and the clock experiments in [docs/performance.md](docs/performance.md) are results, not
settings. Expect sustained full GPU load for as long as a session runs. Your cooling, power supply,
driver and any knob you turn yourself are yours. Provided as is, no warranty: see
[LICENSE](LICENSE).

## Credits

A thin layer on other people's work.

- The [Qwen team](https://huggingface.co/Qwen) for Qwen3.6-35B-A3B and Qwen3.8-Flash-Next
- [Unsloth](https://github.com/unslothai/unsloth) for the GGUFs both Qwen models run from, the
  llama.cpp tree with multi-token prediction and banded sparse attention, and Unsloth Studio
- [PrismML](https://prismml.com) for Ternary Bonsai 2 27B, the `PTQ1_0` format and the
  [llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp) that loads it
- [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) and its contributors, including
  whoever wrote the IQ-grid Vulkan shaders that [`patches/vulkan`](patches/vulkan/) follows
- The reporter of [PrismML-Eng/llama.cpp#185](https://github.com/PrismML-Eng/llama.cpp/issues/185),
  who made the Vulkan work findable
- [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) by earendil-works
- Mesa and RADV; `RADV_PERFTEST=nogttspill` alone is worth 1.22x here

The weights are their authors', under the licenses on their model cards, downloaded at install
time and never redistributed here. [docs/model-comparison.md](docs/model-comparison.md) and the localagent workflow come from a
project thesis at Technische Hochschule Mittelhessen by this repo's author.

**License: [MIT](LICENSE).** The `PTQ1_0` Vulkan decode in [`patches/vulkan`](patches/vulkan/)
changes llama.cpp, which is MIT, and is offered upstream under the same terms.
