# Bonsai Agent for 8 GB VRAM

**A 27B coding agent, running entirely on your own 8 GB graphics card.**

Not a 7B that writes plausible-looking code. A dense 27 billion parameter model with a 64,000 token
context window, fully resident in the VRAM of a card you already own, driving a real coding agent
that reads your files, runs your tests and edits your repo. No API key, no rate limit, nothing
leaving the machine.

Two cards were measured, and they are deliberately the two ends of what "8 GB" means:

| | | |
| --- | --- | --- |
| **AMD RX 570 8 GB** | **7 tok/s** | a ten-year-old card that sells used for the price of a video game. The cheapest hardware this is known to run on at all |
| **RTX 4060 Ti 8 GB** | **36 tok/s** | an ordinary current midrange card, which is roughly where a typical gaming PC sits today |

Everything in between should land in between. 8 GB is not an exotic amount of VRAM, it is close to
the middle of what people actually have.

At 36 tok/s you hold a conversation with it. At 7 tok/s you hand it a task and come back later,
which is a real way to use an agent and the reason the AMD number is in the headline at all.

## What you get

- **[Ternary-Bonsai-2-27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf)** in its
  `PTQ1_0` ternary quant, 5.95 GB of weights, served by llama.cpp with all 65 layers on the GPU.
  Stock llama.cpp cannot load this file; this repo builds the
  [PrismML fork](https://github.com/PrismML-Eng/llama.cpp) at a pinned commit that can.
- **A 64k context window** on 8 GB, with a KV cache quantised to `q8_0`/`q4_0` and a VRAM budget
  tuned to the last few hundred megabytes. That is enough for an agent to hold a real task.
- **The [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) coding agent,
  configured for this model**, not just pointed at it: its own private instance, a context budget
  that keeps it from compacting every single turn, a thinking budget that fits under its output
  cap, and an `AGENTS.md` written for a model this size. Your own pi keeps its settings.
- **One command to install it**, and a preflight that tells you in ten seconds whether your machine
  can run it, before anything downloads or compiles.

## Install

You need a **GPU with 8 GB of VRAM that is not driving your monitor**, Linux or WSL2, and about
14 GB of free disk. `install.sh` checks your machine first and stops with a list of anything
missing, before it downloads or compiles.

```bash
git clone https://github.com/voxlo-dev/bonsai-agent-8gb.git
cd bonsai-agent-8gb
./install.sh                    # NVIDIA
BACKEND=vulkan ./install.sh     # AMD
```

A 10 to 30 minute compile and a 5.6 GB download; re-running is safe. On Windows, set up WSL2
first: [On Windows](#on-windows). Single steps, paths and the full list:
[Install in detail](#install-in-detail) and [Requirements](#requirements).

## Use

```bash
bonsai-pi            # in your project directory; arguments go to pi
```

`bonsai-pi` starts the server in the background when none is running, waits for the model to load, and stops the server again when the last `bonsai-pi` session ends. Its output goes to `~/.local/share/bonsai-local/server.log`. A server you started yourself is used and left running:

```bash
bonsai-server        # terminal 1, ready at "listening on http://127.0.0.1:8080"; Ctrl+C stops it
bonsai-pi            # terminal 2
```

`bonsai-pi` is a separate pi instance, so a pi you use with other models keeps its own settings. The server is also a plain OpenAI-compatible endpoint at `http://127.0.0.1:8080/v1`, model `bonsai-27b`.

`bonsai-pi --localagent` starts a highly experimental multi-agent workflow that is **not recommended** yet and performs worse, we're working on it: [docs/localagent.md](docs/localagent.md#status).

## Why it is interesting

Dense models in the 27B class write the best code of anything that runs locally, and on an 8 GB
card they run at about 4 tok/s, because the weights do not fit and spill into system RAM.
Mixture-of-experts models of that size are fast and noticeably less reliable as agents. That
trade-off was measured across eight local models on an RTX 4060 8 GB one week before this repo
existed: the best result took six hours, and the fastest model that actually held an agent process
left a broken artifact behind. The numbers are in
[the model comparison](docs/model-comparison.md).

Ternary Bonsai 2 27B is a dense 27B whose weights compress to 5.95 GB, which is the combination
that table has no row for. This repo exists to make it usable.

**What is measured and what is not.** The speed numbers here are reproducible from this repo. The
claim that Bonsai closes the quality gap is **not measured yet**: no Bonsai run exists in the
comparison table, and the run that would put it there is
[T-035](backlog/T-035-bonsai-measured.md). Until then this repo claims interactive speed for a
dense 27B on 8 GB, and nothing about beating other models.

## Requirements

Two backends, chosen with `BACKEND` (default `cuda`).

**Measured** - a card enters this table only with a logged run:

| Card | `BACKEND` | System | Generation | For |
| --- | --- | --- | --- | --- |
| RTX 4060 Ti 8 GB | `cuda` | Windows 11 + WSL2, Ubuntu 26.04 | 36 tok/s | interactive use, the default |
| AMD RX 570 8 GB | `vulkan` | Debian 13, RADV, Mesa 26.1 | 7 tok/s | **batch use**: `-p` runs left alone, not a conversation |

**Expected to work, unmeasured** - same architecture families, nobody has reported numbers.
`build` takes the CUDA arch from `nvidia-smi` and the Vulkan build is generic, so these should
build and run; whether the 64k profile still fits is the open question, because it was measured
with 441 MiB of headroom on one driver.

| | |
| --- | --- |
| NVIDIA | RTX 20xx to 40xx with 8 GB or more. RTX 50xx needs CUDA >= 12.8, untested ([T-007](backlog/T-007-blackwell.md)) |
| AMD | RDNA2 and RDNA3 through Vulkan, which should be considerably faster than the RX 570 |
| More than 8 GB | works, but wastes the window; raise `CTX` yourself, see [Context budget](docs/dev.md#context-budget) |

If you run one of these, a [hardware report](../../issues/new?template=hardware-report.yml) is the
most useful thing you can send.

**Not supported:** less than 8 GB of VRAM, partial offload (it costs this architecture about 10x
decode speed), ROCm/HIP, Metal, and CPU-only. Vulkan is the one AMD path.

[Toolchain](docs/dev.md#toolchain) says what is known beyond that, [Other GPU backends](docs/dev.md#other-gpu-backends) where the Vulkan numbers come from.

- Linux, native or WSL2. CUDA: a working NVIDIA driver (`nvidia-smi` runs; under WSL2 it is installed on the Windows side). Vulkan: the `amdgpu` kernel driver and **Mesa >= 25.2** (Debian 13 ships 25.0.7; take `mesa-vulkan-drivers` from `trixie-backports`), and your user in the `render` group
- A GPU with 8 GB VRAM, of which ~7.3 GB must be **free**: the GPU should drive no display, see [VRAM budget](docs/dev.md#vram-budget). Less does not work, the model does not run partially offloaded at usable speed
- CUDA: toolkit >= 12.4 with a host gcc it accepts; >= 12.8 for RTX 50xx. `./install.sh deps` installs it via apt, which yields 12.4 on Ubuntu 26.04 only. Vulkan: `glslc`, the Vulkan headers and loader; `deps` installs them on Debian and Ubuntu
- Node.js >= 22.19 for pi
- **8 GB RAM** to serve: the model is read through `mmap`, so llama-server peaks at 5.8 GB while loading and then sits below 700 MB, with the rest as reclaimable page cache. Building wants more headroom - a single Vulkan shader unit peaks at 4.4 GB - so `build` caps its parallelism at ~2 GB per job instead of `-j $(nproc)`; `BUILD_JOBS` overrides it. See [RAM and build memory](docs/dev.md#ram-and-build-memory)
- ~14 GB free disk: 5.6 GB model, 1.9 GB build, ~5.4 GB for the CUDA toolkit from apt. ~9 GB when a CUDA toolkit is already installed, or with Vulkan

Without apt, install the toolchain yourself (CUDA and gcc, or glslc and the Vulkan SDK; plus cmake, git, python3) and skip `deps`: `./install.sh build model pi link`.

## Install in detail

`./install.sh` runs every step in order. Name one or more steps to run just those; each one skips
work that is already done:

| Step | Does |
| --- | --- |
| `deps` | apt toolchain for `BACKEND`: build tools, cmake, then gcc-13 and the CUDA toolkit, or glslc and the Vulkan headers (asks for sudo, so run it in a real terminal) |
| `build` | clones the fork at the pinned commit, applies `patches/$BACKEND/`, builds `llama-server` (`FORCE=1` rebuilds) |
| `model` | links the GGUF from the Hugging Face cache, or downloads and checksums it |
| `pi` | installs its own pinned pi and writes its config: provider `local` as default, the context budget, `AGENTS.md`. A pi you already have and `~/.pi` stay untouched |
| `link` | puts `bonsai-server` and `bonsai-pi` into `~/.local/bin` |

`BACKEND` has to be set for every later `./install.sh build` too (or exported): `build` decides on it which toolchain to use and which patches from [`patches/`](patches/) to apply. `bonsai-server` reads it as well.

Everything lands in `~/.local/share/bonsai-local` (`BONSAI_HOME`), pi's config and sessions in `pi-agent/` there. `SKIP_PREFLIGHT=1` skips the checks if you know better than they do.

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
git clone https://github.com/voxlo-dev/bonsai-agent-8gb.git
cd bonsai-agent-8gb && ./install.sh
```

AMD cards under WSL2 are untested. Use native Linux for the Vulkan backend.

There is no native Windows install and there will not be one: the reference machine for the
CUDA numbers is WSL2, and a second PowerShell implementation of the install and the server
lifecycle is not maintainable next to it. The reasoning is in
[`docs/dev.md#windows`](docs/dev.md#windows).

## Configure

The context window and the four budget values come from a **profile**:

| `PROFILE` | Window | For |
| --- | --- | --- |
| `dedicated` (default) | 64k | the GPU drives no display; uses 7 747 of 8 188 MiB |
| `display` | 48k | the GPU also renders a desktop, which takes 0.5-1.2 GB |

```bash
PROFILE=display ./install.sh pi     # pi's copy of the values
PROFILE=display bonsai-pi           # and every run after
```

Both are in [`profiles/bonsai/`](profiles/bonsai/); the values inside constrain each other, see [Context budget](docs/dev.md#context-budget). Everything else lives in [`config.env`](config.env). A variable set in the environment wins over both, and extra arguments go straight to llama-server:

```bash
CTX=32000 bonsai-server
BUDGET=3072 EFFORT=low bonsai-server
bonsai-server --port 9000
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `MODEL` | `bonsai` | `bonsai`, `qwen36-35b` or `qwen38-flash`, see [A second model](#a-second-model-experimental) |
| `BACKEND` | `cuda` | `cuda` or `vulkan`; read by `deps`, `build` and `bonsai-server`. `build` rebuilds by itself when it changes |
| `BUILD_JOBS` | auto | parallel compile jobs; empty derives them from free RAM and core count, see [RAM and build memory](docs/dev.md#ram-and-build-memory) |
| `CTX` | `64000` | context window in tokens (profile); the most 8 GB holds at the default cache types. 96k fits with `q4_0`/`q4_0`, see [Context window](docs/context-window.md) |
| `KV_K` / `KV_V` | `q8_0` / `q4_0` | KV cache types for keys and values; measured against `f16` in [Context window](docs/context-window.md#kv-cache-quality) |
| `EFFORT` | `medium` | chat-template reasoning effort: `low`, `medium`, `xhigh` |
| `BUDGET` | `8192` (profile) | thinking tokens per turn; at most `RESERVE_TOKENS - 4096 -` a tool call, see [Context budget](docs/dev.md#context-budget) |
| `PRESERVE_THINKING` | `false` | keep earlier turns' thinking in the prompt |
| `MAX_TOKENS` | `16000` (profile) | pi's output cap per turn |
| `RESERVE_TOKENS` | `16000` (profile) | window pi holds back for the answer; it compacts above `CTX - RESERVE_TOKENS` |
| `KEEP_RECENT_TOKENS` | `12000` (profile) | recent history a compaction keeps |
| `PORT` | `8080` | server port |
| `LISTEN_HOST` | `127.0.0.1` | address the server binds to; `0.0.0.0` to serve other machines — there is no authentication |
| `SERVER_HOST` | `127.0.0.1` | address `bonsai-pi` and pi connect to; set it to run the server on [another machine](docs/dev.md#a-server-on-another-machine) |
| `PI_VERSION` | `0.85.1` | pi version the context budget was measured with |
| `SERVER_AUTOSTART` | `true` | let `bonsai-pi` start and stop the server |
| `SERVER_START_TIMEOUT` | `300` | seconds `bonsai-pi` waits for the model to load |

After changing the profile, `CTX`, `SERVER_HOST`, `PORT`, `MAX_TOKENS`, `RESERVE_TOKENS` or `KEEP_RECENT_TOKENS`, run `./install.sh pi` again so pi's config matches the server.

The last three carry each other: pi's own defaults assume a 200k window and make it compact on every single turn at this size. [Context budget](docs/dev.md#context-budget) has the measurements and the constraints between them.

### A second model (experimental)

`MODEL=qwen36-35b` serves [Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B) instead,
a mixture-of-experts model whose experts live in system RAM while the card holds the rest. On the
same 4060 Ti it runs a 131k window at 39-45 tok/s on natural output, with multi-token prediction.
It needs **~28 GB of RAM** (under WSL2, raise `memory=` in `%UserProfile%\.wslconfig`), 22 GB of
disk, and a mainline llama.cpp build next to the fork. On the RX 570 it runs too, at
2.5-3.5x Bonsai's speed there, ~22 tok/s at 131k. In its one agent session so far it built the
study's Tron game in 7 minutes, with rematch broken: [docs/qwen.md](docs/qwen.md#in-an-agent-session).

```bash
MODEL=qwen36-35b ./install.sh       # its own build, model and pi config
MODEL=qwen36-35b bonsai-pi
```

Each model has its own profiles and its own pi config (`pi-agent-qwen36-35b/`), so switching does
not touch the other one's settings or sessions.

`MODEL=qwen38-flash` goes further: [Qwen3.8-Flash-Next](https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF),
125B, every expert in RAM, a 131k window at 9-10 tok/s and prompts at ~36 tok/s. A side experiment,
not tried as an agent yet. It needs **~48 GB of RAM** (a 64 GB PC with `memory=50GB` for WSL2),
88 GB of disk, an 8 GB card that drives no display, and [Unsloth Studio](https://github.com/unslothai/unsloth)
installed: it runs on Unsloth's prebuilt llama.cpp, since mainline runs out of VRAM on its sparse
attention. Details in [docs/qwen.md](docs/qwen.md#qwen38-flash-125b-experimental).

## Performance

RTX 4060 Ti 8 GB, the default 64k window, K `q8_0` / V `q4_0`:

| Context filled | Prompt processing | Generation |
| --- | --- | --- |
| short | - | 35.7 tok/s |
| a real turn, thinking and code | - | 35.6 tok/s |
| ~43k | 415 tok/s | 25.7 tok/s |

VRAM stays at ~7.3 GB at 48k and 7.75 GB at 64k: the KV cache is allocated in full at start.

Generation is bandwidth-bound and already uses ~80 % of what the card can sustain, so there is
little left to tune. [Performance](docs/performance.md) has the roofline and the optimizations
that were tried and rejected.

AMD RX 570 8 GB through Vulkan (RADV, Mesa 26.1.2), same KV types, with the PTQ1_0 decode from
[`patches/vulkan`](patches/vulkan/):

| Context | Prompt processing (847-token prompt) | Generation |
| --- | --- | --- |
| 16k | 54 tok/s | 7.0 tok/s |
| 48k | 54 tok/s | 7.0 tok/s |
| 64k | 54 tok/s | 7.1 tok/s |

64k takes 7 434 MiB of 8 192, so the `dedicated` profile holds on this card too.

Five times slower than the 4060 Ti, and eight times on prompts: a 4k-token agent prompt takes
~75 s before the first token. That is batch territory - a task handed to `bonsai-pi -p` and left
alone - and it is why `vulkan` is not the default. The fork's own
Vulkan kernel did 0.94 tok/s on this card; [Other GPU backends](docs/dev.md#other-gpu-backends)
has the way from there to 7.

### The one change worth more than any flag

**Do not let this GPU drive your monitor.** A desktop on the same card takes 0.5 to 1.2 GB of VRAM
and competes for GPU time, and both come out of the model: moving the display to the motherboard's
iGPU took generation from 21 to 34 tok/s in the same session. Enable the iGPU in the BIOS, plug the
monitor into the mainboard, and set browsers to "Power saving" under Windows *Settings, System,
Display, Graphics*. It costs a cable and beats every tuning knob in this repo combined. If you
cannot, `PROFILE=display` drops the window to 48k to make room.

## Docs

| | |
| --- | --- |
| [docs/dev.md](docs/dev.md) | why every non-default choice is what it is, with its measurement, plus troubleshooting |
| [docs/performance.md](docs/performance.md) | what limits generation speed, and what was tried and rejected |
| [docs/context-window.md](docs/context-window.md) | how large a window fits on 8 GB, and what the KV cache types cost in quality, for both models |
| [docs/qwen.md](docs/qwen.md) | the second model: Qwen3.6-35B-A3B with its experts in RAM, and the slot for Qwen 4 |
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
rm -rf ~/.local/share/bonsai-local ~/.local/bin/bonsai-server ~/.local/bin/bonsai-pi
```

That includes pi and its sessions. The build cache in `~/.cache/ccache` and the apt packages from
`deps` stay.

## Your hardware

This fills an 8 GB card to within a few hundred megabytes and forces full offload with `-ngl 99`,
because partial offload costs this architecture about ten times its decode speed. That is a memory
allocation, not an electrical one: nothing here overclocks, raises a power limit or touches a fan
curve, and the clock experiments in [docs/performance.md](docs/performance.md) are results, not
settings. Expect sustained full GPU load for as long as a session runs. Your cooling, power supply,
driver and any knob you turn yourself are yours. Provided as is, no warranty: see
[LICENSE](LICENSE).

## Credits

A thin layer on other people's work.

- [PrismML](https://prismml.com) for Ternary Bonsai 2 27B, the `PTQ1_0` format and the
  [llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp) that loads it
- [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) and its contributors, including
  whoever wrote the IQ-grid Vulkan shaders that [`patches/vulkan`](patches/vulkan/) follows
- The reporter of [PrismML-Eng/llama.cpp#185](https://github.com/PrismML-Eng/llama.cpp/issues/185),
  who made the Vulkan work findable
- [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) by earendil-works
- Mesa and RADV; `RADV_PERFTEST=nogttspill` alone is worth 1.22x here

The weights are PrismML's under Apache-2.0, downloaded at install time and never redistributed
here. [docs/model-comparison.md](docs/model-comparison.md) and the localagent workflow come from a
project thesis at Technische Hochschule Mittelhessen by this repo's author.

**License: [MIT](LICENSE).** The `PTQ1_0` Vulkan decode in [`patches/vulkan`](patches/vulkan/)
changes llama.cpp, which is MIT, and is offered upstream under the same terms.
