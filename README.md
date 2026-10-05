# Qwen Agent for 8 GB VRAM

**A local coding agent on an ordinary 8 GB graphics card, two to nine times faster than
download-and-go.** The card was never the limit: the RAM next to it decides how large a model it
runs.

One command builds llama.cpp, fetches a model and sets up the
[pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) coding agent against it, tuned
to the last few hundred megabytes of the card. Then `qwen-pi` in your project: an agent that reads
your files, runs your tests and edits your code. No API key, no rate limit, nothing leaves the
machine.

## Which model

Mixture-of-experts models only use a few billion parameters per token, so their experts can live
in system RAM while the card holds the rest. More RAM, a bigger model:

| RAM next to the card | Model | Speed | Window | Good for |
| --- | --- | --- | --- | --- |
| any | [Ternary-Bonsai-2-27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf), all on the card | 36 tok/s | 64k | small, well-scoped tasks |
| **32 GB** | **[Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)** | **52-65 tok/s** | **131k** | **most work: fast, and the default** |
| 64 GB | [Qwen3.8-Flash-Next](https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF), 125B | ~19 tok/s | 131k | the strongest, for when it may take longer |

`./install.sh` reads your RAM, shows which of the three run, and asks. How they did as agents on
the same task: [the agent sessions](docs/agent-sessions.md).

## Install

You need an **8 GB NVIDIA or AMD card**, **Linux or WSL2**, and the RAM from the table above.

```bash
git clone https://github.com/voxlo-dev/qwen-agent-8gb.git
cd qwen-agent-8gb
./install.sh                    # NVIDIA
BACKEND=vulkan ./install.sh     # AMD
```

It checks your machine first and stops with a list of anything missing, before it downloads or
compiles. Then a 10-30 minute build and the download; re-running is safe. On Windows, set up WSL2
first: [Windows](docs/setup.md#windows). Disk and the rest: [Requirements](#requirements).

## Use

```bash
qwen-pi            # in your project directory; arguments go to pi
```

`qwen-pi` starts the server in the background, waits for the model and stops it after the last
session. To keep it running, start it yourself:

```bash
qwen-server        # terminal 1, ready at "listening on http://127.0.0.1:8080"
qwen-pi            # terminal 2
```

The server is also a plain OpenAI-compatible endpoint at `http://127.0.0.1:8080/v1` for any other
tool. `qwen-studio` opens the same model with the same settings in
[Unsloth Studio](https://github.com/unslothai/unsloth)'s chat UI, at the same speed and VRAM:
[details](docs/agent.md#unsloth-studio).

## Speed

The same card and the same models, three levels of effort. Generation in tok/s, RTX 4060 Ti 8 GB,
Ryzen 7 7800X3D, 64 GB RAM:

| | Bonsai | Qwen3.6 | Qwen3.8-Flash |
| --- | --- | --- | --- |
| **Download and go**: the GGUF with default settings | ~4 | ~25 | ~4 |
| **This repo's configuration**: the right llama.cpp tree, expert placement, KV cache, multi-token prediction; under WSL2 | 36 | 39-45 | 9-10 |
| **Plus the system**: native Linux, no display on the card | 36.6 | **52-65** | **~19** |

The biggest single step after the configuration: **do not let this GPU drive your monitor.** A
desktop takes 0.5-1.2 GB of VRAM and GPU time, both out of the model; plug the monitor into the
mainboard's iGPU. If you cannot, `PROFILE=display` makes room. Where each number comes from:
[docs/performance.md](docs/performance.md) and the pages per model.

## Configure

Each model has two profiles: `dedicated` (default) for a card that drives no display, `display`
for one that does. Settings live in [`config.env`](config.env), each with a comment; an
environment variable always wins, and arguments go straight to llama-server:

```bash
PROFILE=display ./install.sh pi && PROFILE=display qwen-pi
MODEL=qwen38-flash qwen-pi
qwen-server --port 9000
```

After changing the profile, the window or the port, run `./install.sh pi` again so pi's copy
matches the server. The window and pi's budget values constrain each other:
[Context budget](docs/agent.md#context-budget).

## Requirements

Measured, each with a logged run:

| Card | System | Qwen3.6 | Qwen3.8-Flash | Bonsai |
| --- | --- | --- | --- | --- |
| RTX 4060 Ti 8 GB | Linux Mint 22.3, native | 52-65 tok/s | ~19 tok/s | 36.6 tok/s |
| RTX 4060 Ti 8 GB | Windows 11 + WSL2, Ubuntu 26.04 | 39-45 tok/s | 9-10 tok/s | 36 tok/s |
| AMD RX 570 8 GB | Debian 13, Vulkan (Mesa 26.1) | ~25 tok/s | - | 7 tok/s with this repo's Vulkan patch, 0.94 without |

Expected to work, unmeasured: RTX 20xx to 40xx and RDNA2/3 cards with 8 GB or more; RTX 50xx needs
CUDA >= 12.8. If you run one, a [hardware report](../../issues/new?template=hardware-report.yml) is
the most useful thing you can send. Not supported: less than 8 GB of VRAM, ROCm, Metal, CPU-only.

Disk: 22 GB for Qwen3.6, 88 GB for Qwen3.8-Flash, 6 GB for Bonsai, plus ~10 GB for the build and
the CUDA toolkit. Drivers, toolkit versions, Node for pi and what `deps` installs per distro:
[docs/setup.md](docs/setup.md#toolchain).

## Install in detail

`./install.sh` runs `deps build model pi link` in order; name steps to run only those.

| Step | Does |
| --- | --- |
| `deps` | the apt toolchain: CUDA or Vulkan, cmake, gcc (asks for sudo) |
| `build` | the model's llama.cpp tree at its pinned version (`FORCE=1` rebuilds) |
| `model` | the GGUF, from the Hugging Face cache or downloaded, checksummed |
| `pi` | its own pinned pi with a config for the model; your own pi and `~/.pi` stay untouched |
| `link` | `qwen-server`, `qwen-pi` and `qwen-studio` into `~/.local/bin` |

The model you pick is recorded in `$QWEN_HOME/model.env` and used by every `qwen-*` command. A
second one installs next to it with `MODEL=bonsai ./install.sh` and runs with `MODEL=bonsai qwen-pi`.
Everything lands in `~/.local/share/qwen-local` (`QWEN_HOME`); an install from before the rename,
in `~/.local/share/bonsai-local`, stays where it is.

## How it was measured

Every non-default setting in this repo answers a failure seen on real hardware, and the
measurement behind it is in [`docs/`](docs/dev.md). Speed, VRAM and windows are reproducible.
Agent quality is a handful of single sessions on one prompt, enough to put Qwen3.6 ahead of Bonsai
and not more; a reproducible test is next. The starting point was a study of eight local models
as coding agents on an 8 GB card: [docs/model-comparison.md](docs/model-comparison.md).

## Uninstall

```bash
rm -rf ~/.local/share/qwen-local ~/.local/bin/qwen-server ~/.local/bin/qwen-pi ~/.local/bin/qwen-studio
```

That includes the models, pi and its sessions (`bonsai-local` for an install from before the
rename). The apt packages from `deps` stay.

## Contributing

Issues, pull requests and hardware reports welcome. [CONTRIBUTING.md](CONTRIBUTING.md) has the one
rule: a non-default choice arrives with the measurement that justifies it. Working on the code:
[AGENTS.md](AGENTS.md).

## Your hardware

This fills an 8 GB card to within a few hundred megabytes and keeps the GPU, and for the Qwen
models tens of gigabytes of RAM, busy for as long as a session runs. Nothing here overclocks,
raises a power limit or touches a fan curve. Your cooling, power supply and driver are yours.
Provided as is, no warranty: see [LICENSE](LICENSE).

## Credits

- The [Qwen team](https://huggingface.co/Qwen) for Qwen3.6-35B-A3B and Qwen3.8-Flash-Next
- [Unsloth](https://github.com/unslothai/unsloth) for the GGUFs, the llama.cpp tree both Qwen
  models run on, and Unsloth Studio
- [PrismML](https://prismml.com) for Ternary Bonsai 2 27B and the
  [llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp) that loads it
- [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp), including whoever wrote the IQ-grid
  Vulkan shaders the patch follows, and the reporter of
  [PrismML-Eng/llama.cpp#185](https://github.com/PrismML-Eng/llama.cpp/issues/185), who made that
  work findable
- Mesa and RADV, and [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) by earendil-works

The weights are their authors', under the licenses on their model cards, downloaded at install
time and never redistributed here. The model comparison and the localagent workflow come from a
project thesis at Technische Hochschule Mittelhessen by this repo's author.

**License: [MIT](LICENSE)**, including the `PTQ1_0` Vulkan decode in [`patches/vulkan`](patches/vulkan/),
which is offered upstream under the same terms.
