# Development notes

Why the setup looks the way it does. Every non-default choice answers a failure seen on real
hardware, and its reason lives with its measurement in one of these files (split from this one
on 2026-10-03, T-047):

| File | Holds |
| --- | --- |
| [setup.md](setup.md) | build flags, toolchain and CUDA per distro, Secure Boot, Windows, RAM and build memory, preflight, troubleshooting |
| [agent.md](agent.md) | pi and its context budget, the agent prompt, the server lifecycle, Unsloth Studio, the localagent workflow |
| [agent-sessions.md](agent-sessions.md) | every Tron session across all models: the evidence for what each model is good for |
| [bonsai.md](bonsai.md) | Bonsai: model format, VRAM budget, KV cache, reasoning, Swift-Bonsai-2, sampling, Vulkan |
| [qwen36.md](qwen36.md) | Qwen3.6-35B-A3B: why a MoE, the offload/MTP grid, profiles, RX 570, native Linux, the Unsloth tree |
| [qwen38-flash.md](qwen38-flash.md) | Qwen3.8-Flash-Next: every expert in RAM, flags, window, native Linux |
| [context-window.md](context-window.md) | windows and KV quality for both models side by side |
| [performance.md](performance.md) | Bonsai's bandwidth roofline, the optimizations tried and rejected |

## Old anchors

Links into this file from before the split, and where each section went. `qwen.md` became
[qwen36.md](qwen36.md) and [qwen38-flash.md](qwen38-flash.md), its agent sessions moved to
[agent-sessions.md](agent-sessions.md).

| Old anchor | Now |
| --- | --- |
| `#a-server-on-another-machine` | [agent.md#a-server-on-another-machine](agent.md#a-server-on-another-machine) |
| `#build` | [setup.md#build](setup.md#build) |
| `#context-budget` | [agent.md#context-budget](agent.md#context-budget) |
| `#cuda-from-nvidias-repository` | [setup.md#cuda-from-nvidias-repository](setup.md#cuda-from-nvidias-repository) |
| `#kv-cache` | [bonsai.md#kv-cache](bonsai.md#kv-cache) |
| `#localagent-workflow` | [agent.md#localagent-workflow](agent.md#localagent-workflow) |
| `#model-format` | [bonsai.md#model-format](bonsai.md#model-format) |
| `#other-gpu-backends` | [bonsai.md#other-gpu-backends](bonsai.md#other-gpu-backends) |
| `#pi` | [agent.md#pi](agent.md#pi) |
| `#preflight` | [setup.md#preflight](setup.md#preflight) |
| `#ram-and-build-memory` | [setup.md#ram-and-build-memory](setup.md#ram-and-build-memory) |
| `#reasoning` | [bonsai.md#reasoning](bonsai.md#reasoning) |
| `#sampling` | [bonsai.md#sampling](bonsai.md#sampling) |
| `#secure-boot` | [setup.md#secure-boot](setup.md#secure-boot) |
| `#server-lifecycle` | [agent.md#server-lifecycle](agent.md#server-lifecycle) |
| `#swift-bonsai-2` | [bonsai.md#swift-bonsai-2](bonsai.md#swift-bonsai-2) |
| `#the-agent-prompt` | [agent.md#the-agent-prompt](agent.md#the-agent-prompt) |
| `#thinking-in-the-prompt` | [bonsai.md#thinking-in-the-prompt](bonsai.md#thinking-in-the-prompt) |
| `#toolchain` | [setup.md#toolchain](setup.md#toolchain) |
| `#troubleshooting` | [setup.md#troubleshooting](setup.md#troubleshooting) |
| `#unsloth-studio` | [agent.md#unsloth-studio](agent.md#unsloth-studio) |
| `#vram-budget` | [bonsai.md#vram-budget](bonsai.md#vram-budget) |
| `#windows` | [setup.md#windows](setup.md#windows) |
