# Backlog — bonsai-local

Ticket index. A ticket is a file: summary, category, importance, effort, what depends on it,
then **Why** and **What**. Copy the shape of any open one.

Numbers have gaps: a closed ticket's file is deleted, and a ticket that is nobody else's business
is named `T-NNN-{slug}.local.md`, which `.gitignore` keeps out of the repo. The counter below never
reuses a number either way.

**Next ticket: `T-040`**

## Draft

## Backlog

- [`T-004`](T-004-fresh-install-e2e.md) Verify a fresh install end to end — run the README from a clean WSL2 Ubuntu 26.04 instance to a working pi session · chore · high · S
- [`T-005`](T-005-other-distros.md) Settle which Linux systems `deps` supports — test Ubuntu 24.04, 22.04 and Debian 13, then support or reject them early · decision · medium · M
- [`T-006`](T-006-native-linux-driver.md) Verify apt's CUDA toolkit next to a native NVIDIA driver — check for a driver/library version mismatch · chore · medium · S
- [`T-007`](T-007-blackwell.md) Verify the build on an RTX 50xx — Blackwell with CUDA >= 12.8 from NVIDIA · chore · low · S
- [`T-008`](T-008-vram-scaling.md) Measure context per VRAM size and with a shared display — derive CTX and the pi budget from free VRAM · decision · medium · M
- [`T-015`](T-015-context-safety-tokens.md) Decide whether to shrink pi's 4096-token safety margin — patch, upstream or leave · decision · low · S
- [`T-017`](T-017-upstream-ptq1_0-vulkan-patch.md) Hand the PTQ1_0 Vulkan decode to the fork’s #185 — a comment with the measurement and the patch link, not a PR (two PRs were ahead, and the fork’s rules need an author who can defend every line); drop `patches/vulkan/` once a pin carries an equivalent · chore · medium · S
- [`T-031`](T-031-sharp-chat-template.md) Measure the Qwen Sharp chat template — one plain session with `--chat-template-file`, thinking per turn and turns to result; expectation small, the delta is one terseness block · spike · low · S
- [`T-032`](T-032-docker-server-image.md) A Dockerfile for the server, not for pi — `llama-server` in a container, pi stays on the host through `SERVER_HOST`; answers the apt-toolchain problem (T-005) and nothing about drivers, VRAM or the profile · feature · medium · M
- [`T-034`](T-034-qwen-moe-model.md) A second model: Qwen3.6-35B-A3B with the experts in RAM — measured and built (`MODEL=qwen36-35b`, 131k, MTP on mainline); one agent session run (Tron in 7 min, rematch broken); left: supported or experimental, the `display` check; the slot a Qwen 4 35B-A3B drops into · feature · medium · S
- [`T-038`](T-038-unsloth-llama-for-qwen.md) Unsloth's llama.cpp as the tree every Qwen model runs on — Qwen3.8-Flash needs its banded sparse attention and uses the Studio prebuilt for now; build it from a pinned source (a release tarball: its commit is not fetchable), then re-measure Qwen3.6 with MTP on it · feature · medium · M
- [`T-039`](T-039-qwen38-flash.md) Qwen3.8-Flash (125B, experts in RAM) as a third, experimental model — built and measured for speed (9-10 tok/s at 131k, on the Unsloth prebuilt); left: one agent session, `q4_0` KV quality for the 262k option · spike · low · S
- [`T-037`](T-037-moe-cpu-threads.md) Threads for the experts in RAM — `-t 7` of 8 vCPUs is ~10 % faster on the RX 570 box; measure on the 4060 Ti, then a `THREADS` setting, a cores-minus-one default, or nothing · spike · low · S

## Open source (release checklist)

Closed on 2026-09-21: the history audit (clean, no rewrite needed), the MIT license and
disclaimer, acknowledgements, the experimental label on the localagent workflow, and the terminal
UX with `scripts/preflight.sh`.

Public since 2026-09-21 at <https://github.com/voxlo-dev/bonsai-agent-8gb>, tagged `v0.1.0`.
Remaining order: T-035 → T-017 comment posted. T-020 and T-029 follow the reports and the upstream merge.

- [`T-020`](T-020-supported-hardware.md) Finish the hardware table — 12/16 GB profiles and the rows that hardware reports bring in; the three tiers are already in the README · decision · medium · M
- [`T-024`](T-024-public-repo-setup.md) Public repo setup — done except confirming the two issue templates render · chore · low · S
- [`T-035`](T-035-bonsai-measured.md) Measure Bonsai the way T-034 measures Qwen — speed, window, KV quality and the behaviour day done (96k not yet: its session lost itself in a test harness); left: a second 96k/64k pair on the new agent prompt, then the study-harness run twice for the quality claim; was T-027 and T-033 · spike · high · M
- [`T-029`](T-029-upstream-watch.md) Watch mainline — move off the fork when ggml-org takes PTQ1_0 (#29077), keep the Vulkan patch alive · decision · medium · M
