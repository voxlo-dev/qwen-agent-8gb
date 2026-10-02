# Backlog — bonsai-local

Ticket index. A ticket is a file: summary, category, importance, effort, what depends on it,
then **Why** and **What**. Copy the shape of any open one.

Numbers have gaps: a closed ticket's file is deleted, and a ticket that is nobody else's business
is named `T-NNN-{slug}.local.md`, which `.gitignore` keeps out of the repo. The counter below never
reuses a number either way.

**Next ticket: `T-044`**

## Draft

## Backlog

In this order. T-041 decides what T-042 and T-035 measure; T-043 and T-032 stand alone; T-017
waits for upstream. T-038 closed on 2026-10-02: both Qwen models on Unsloth's tree, built from source.

- [`T-041`](T-041-tron-day-2.md) The second Tron day, natively — A2/C2 (Bonsai 96k against 64k on the new agent prompt), S (Sharp template), B2 (Qwen3.6), E (Qwen3.8-Flash); decides 96k, the prompt, Sharp, and Qwen3.6 supported or not; merges T-031, T-034, T-035 3b, T-039, T-040 · spike · high · M
- [`T-042`](T-042-display-profiles.md) The `display` profiles, checked once with a desktop on the card — all three are arithmetic or measured without one; Bonsai's 64k `q4_0` candidate after T-041; needs a monitor on the headless machine; merges T-008's display half · decision · medium · S
- [`T-043`](T-043-bonsai-studio-on-the-card.md) `bonsai-studio` on the card — VRAM and tg against `bonsai-server` for Qwen3.6 and Bonsai; verified on the CPU only, since the agent sandbox has no GPU; from your own shell · chore · low · S
- [`T-032`](T-032-docker-server-image.md) A Dockerfile for the server, not for pi — `llama-server` in a container, pi stays on the host through `SERVER_HOST`; answers the apt-toolchain problem off the host and nothing about drivers, VRAM or the profile · feature · medium · M
- [`T-017`](T-017-upstream-ptq1_0-vulkan-patch.md) Upstream: a pin that makes the Vulkan patch, then the fork, unnecessary — comment on the fork's #185 posted, #252 matches the patch on generation; watch #252 and mainline #29077, then move the pin, re-measure both cards, drop what is no longer needed; merges T-029 · decision · medium · S

## Open source (release checklist)

Closed on 2026-09-21: the history audit (clean, no rewrite needed), the MIT license and
disclaimer, acknowledgements, the experimental label on the localagent workflow, and the terminal
UX with `scripts/preflight.sh`.

Public since 2026-09-21 at <https://github.com/voxlo-dev/bonsai-agent-8gb>, tagged `v0.1.0`.
Remaining order: T-035 after T-041. T-020 follows the reports. T-024 (repo setup) closed on 2026-10-02:
both issue templates render.

- [`T-035`](T-035-bonsai-measured.md) The quality claim — Bonsai through OpenCode with the study's prompt, twice, on the profile T-041 settles; then `docs/evidence.md` and the README's "what is measured"; was T-027 and T-033 · spike · high · S
- [`T-020`](T-020-supported-hardware.md) Finish the hardware table — 12/16 GB profiles, Blackwell, RDNA2/3, from the rows hardware reports bring in; the three tiers are already in the README; merges T-007 and T-008's bigger-cards half · decision · medium · M
