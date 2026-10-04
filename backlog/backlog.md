# Backlog — qwen-agent-8gb

Ticket index. A ticket is a file: summary, category, importance, effort, what depends on it,
then **Why** and **What**. Copy the shape of any open one.

Numbers have gaps: a closed ticket's file is deleted, and a ticket that is nobody else's business
is named `T-NNN-{slug}.local.md`, which `.gitignore` keeps out of the repo. The counter below never
reuses a number either way.

**Next ticket: `T-051`**

## Draft

## Backlog

In this order. T-044 reframed the repo on 2026-10-04 (Qwen3.6 the default, `qwen-*` commands,
the model chosen by RAM, a new README); what is left of it is the GitHub rename, by the author.
T-045 is small; T-050 replaces the Tron reading and absorbed T-035 (Bonsai in the study's harness)
on 2026-10-04. T-032 stands alone; T-017 waits for upstream. T-038 closed on 2026-10-02:
both Qwen models on Unsloth's tree, built from source. T-041 closed on 2026-10-03: 64k final,
Swift-Bonsai-2 not wired, the agent prompt stays, Qwen3.6 supported (agent-sessions.md). T-049
closed on 2026-10-03: Qwen3.8-Flash ran the CUDA pool out of the card at 19-48k on the CCCL 2.8
top-k fallback; the Unsloth tree now builds with CCCL 3.2 (qwen38-flash.md), all three models filled.
T-046 closed on 2026-10-04: Flash with and without Sharp (agent-sessions.md), Sharp better in
one pair, open until T-050 validates it;
its hung tools gave pi a default bash timeout. T-047,
the docs split per model and topic (`docs/dev.md` now the index), done on 2026-10-03 without a
ticket file. T-043 closed on 2026-10-04: `qwen-studio` on the card costs neither VRAM nor speed
(agent.md#unsloth-studio).

- [`T-050`](T-050-reproducible-agent-test.md) A reproducible agent test in place of the single Tron session — fixed tasks with a checker, several runs per model, pass rate and time instead of one reading; harnesses comparable (pi, OpenCode); validates Sharp on Flash · spike · high · M
- [`T-044`](T-044-qwen-for-8gb.md) Rebranding: Qwen for 8 GB VRAM — done in the repo on 2026-10-04; left: the GitHub rename `bonsai-agent-8gb` → `qwen-agent-8gb` and the remote, then a fresh clone on a 32 GB machine · feature · high · S
- [`T-045`](T-045-swift-bonsai-pin.md) Bonsai's pin to Swift-Bonsai-2 — the author's call after T-041 (W marginally better, nothing worse, a drop-in); the doc says it is not a measured win · chore · low · S
- [`T-048`](T-048-vision-profile.md) Vision on the CPU — the projector with `--no-mmproj-offload` and capped image tokens, so pi can read the screenshots its e2e tests take (B2 tried); no VRAM cost, the RAM and encode time measured per model, opt-in · feature · medium · M
- [`T-042`](T-042-display-profiles.md) The `display` profiles, checked once with a desktop on the card — all three are arithmetic or measured without one; Bonsai's largest `q8_0`/`q4_0` window; needs a monitor on the headless machine; merges T-008's display half · decision · medium · S
- [`T-032`](T-032-docker-server-image.md) A Dockerfile for the server, not for pi — `llama-server` in a container, pi stays on the host through `SERVER_HOST`; answers the apt-toolchain problem off the host and nothing about drivers, VRAM or the profile · feature · medium · M
- [`T-017`](T-017-upstream-ptq1_0-vulkan-patch.md) Upstream: a pin that makes the Vulkan patch, then the fork, unnecessary — comment on the fork's #185 posted, #252 matches the patch on generation; watch #252 and mainline #29077, then move the pin, re-measure both cards, drop what is no longer needed; merges T-029 · decision · medium · S

## Open source (release checklist)

Closed on 2026-09-21: the history audit (clean, no rewrite needed), the MIT license and
disclaimer, acknowledgements, the experimental label on the localagent workflow, and the terminal
UX with `scripts/preflight.sh`.

Public since 2026-09-21 at <https://github.com/voxlo-dev/bonsai-agent-8gb> (to become
`qwen-agent-8gb`, T-044), tagged `v0.1.0`.
T-020 follows the reports. T-024 (repo setup) closed on 2026-10-02:
both issue templates render.

- [`T-020`](T-020-supported-hardware.md) Finish the hardware table — 12/16 GB profiles, Blackwell, RDNA2/3, from the rows hardware reports bring in; the three tiers are already in the README; merges T-007 and T-008's bigger-cards half · decision · medium · M
