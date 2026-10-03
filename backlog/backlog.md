# Backlog — bonsai-local

Ticket index. A ticket is a file: summary, category, importance, effort, what depends on it,
then **Why** and **What**. Copy the shape of any open one.

Numbers have gaps: a closed ticket's file is deleted, and a ticket that is nobody else's business
is named `T-NNN-{slug}.local.md`, which `.gitignore` keeps out of the repo. The counter below never
reuses a number either way.

**Next ticket: `T-049`**

## Draft

## Backlog

In this order. T-044 reframes the repo; T-045 is small and best before its README; T-046 feeds
the ramp's top. T-043 and T-032 stand alone; T-017 waits for upstream. T-038 closed on 2026-10-02:
both Qwen models on Unsloth's tree, built from source. T-041 closed on 2026-10-03: 64k final,
Swift-Bonsai-2 not wired, the agent prompt stays, Qwen3.6 supported (agent-sessions.md). T-047,
the docs split per model and topic (`docs/dev.md` now the index), done on 2026-10-03 without a
ticket file.

- [`T-044`](T-044-qwen-for-8gb.md) Rebranding: Qwen for 8 GB VRAM — a RAM ramp (+0 GB Bonsai for simple tasks, +32 GB Qwen3.6 recommended and default, +64 GB Qwen3.8-Flash strongest), `qwen-server`/`qwen-pi`, preflight reads the RAM and the user picks, new README, repo renamed; Bonsai to the background; re-scopes T-035 · feature · high · L
- [`T-045`](T-045-swift-bonsai-pin.md) Bonsai's pin to Swift-Bonsai-2 — the author's call after T-041 (W marginally better, nothing worse, a drop-in); the doc says it is not a measured win · chore · low · S
- [`T-046`](T-046-qwen38-flash-sharp.md) Qwen3.8-Flash natively, as shipped (E) and with the Sharp template (ES) — two Tron sessions; render check done (Sharp makes the same two changes on Flash as on Bonsai); decides a `CHAT_TEMPLATE_FILE` setting; Swift 1.5 Flash dropped for want of a UD quant · spike · medium · S
- [`T-048`](T-048-vision-profile.md) Vision on the CPU — the projector with `--no-mmproj-offload` and capped image tokens, so pi can read the screenshots its e2e tests take (B2 tried); no VRAM cost, the RAM and encode time measured per model, opt-in · feature · medium · M
- [`T-042`](T-042-display-profiles.md) The `display` profiles, checked once with a desktop on the card — all three are arithmetic or measured without one; Bonsai's largest `q8_0`/`q4_0` window; needs a monitor on the headless machine; merges T-008's display half · decision · medium · S
- [`T-043`](T-043-bonsai-studio-on-the-card.md) `bonsai-studio` on the card — VRAM and tg against `bonsai-server` for Qwen3.6 and Bonsai; verified on the CPU only, since the agent sandbox has no GPU; from your own shell · chore · low · S
- [`T-032`](T-032-docker-server-image.md) A Dockerfile for the server, not for pi — `llama-server` in a container, pi stays on the host through `SERVER_HOST`; answers the apt-toolchain problem off the host and nothing about drivers, VRAM or the profile · feature · medium · M
- [`T-017`](T-017-upstream-ptq1_0-vulkan-patch.md) Upstream: a pin that makes the Vulkan patch, then the fork, unnecessary — comment on the fork's #185 posted, #252 matches the patch on generation; watch #252 and mainline #29077, then move the pin, re-measure both cards, drop what is no longer needed; merges T-029 · decision · medium · S

## Open source (release checklist)

Closed on 2026-09-21: the history audit (clean, no rewrite needed), the MIT license and
disclaimer, acknowledgements, the experimental label on the localagent workflow, and the terminal
UX with `scripts/preflight.sh`.

Public since 2026-09-21 at <https://github.com/voxlo-dev/bonsai-agent-8gb>, tagged `v0.1.0`.
Remaining order: T-035 first. T-020 follows the reports. T-024 (repo setup) closed on 2026-10-02:
both issue templates render.

- [`T-035`](T-035-bonsai-measured.md) The quality claim — Bonsai through OpenCode with the study's prompt, twice, on the 64k profile; then `docs/evidence.md` and the README's "what is measured"; was T-027 and T-033 · spike · high · S
- [`T-020`](T-020-supported-hardware.md) Finish the hardware table — 12/16 GB profiles, Blackwell, RDNA2/3, from the rows hardware reports bring in; the three tiers are already in the README; merges T-007 and T-008's bigger-cards half · decision · medium · M
