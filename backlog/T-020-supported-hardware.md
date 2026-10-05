# T-020 — Decide which hardware the README promises

- **Summary:** Draw the line between "measured", "should work" and "not supported" for 8 GB cards, and put that table in the README instead of generalising the scripts
- **Category:** decision
- **Importance:** high
- **Effort:** M
- **Depends on:** incoming hardware reports, or a card to borrow. Merges T-007 (Blackwell) and the bigger-cards half of T-008

## Why

Two cards were measured: RTX 4060 Ti (CUDA) and RX 570 (Vulkan, gfx803). The scripts already
generalise further than the docs admit: `build.sh` takes the CUDA arch from `nvidia-smi`, so any
RTX 20xx to 40xx builds; Vulkan builds for any RADV card and Intel Arc. What is unknown is whether
the *profile* holds: `dedicated` is 64k at 7 747 MiB of 8 188, which is 441 MiB of headroom on one
specific driver. A 4060 non-Ti under a different driver, an RX 6600 with a different allocator, or
a 3070 on native Linux may sit on either side of that margin. Promising "all 8 GB cards" in public
buys a stream of issues about the window and the budget.

## Done

The three tiers are in `README.md#requirements`, with the rule that a card enters "measured" only
with a logged run, and a link to the hardware-report issue template. The preflight (T-021) prints
GPU, VRAM, driver and free VRAM before building, and warns when a display is on the card.

## What is left

1. **Bigger cards**: 12 and 16 GB run this fine but waste the window. From
   [VRAM budget](../docs/bonsai.md#vram-budget) (26 MiB per 1k tokens on top of ~6 GB fixed, at
   `q8_0`/`q4_0`) a 12 GB card would hold roughly 200k, an extrapolation. On such a card: VRAM at a
   few `CTX` values, then `RESERVE_TOKENS` / `KEEP_RECENT_TOKENS` per window from the constraints in
   [Context budget](../docs/agent.md#context-budget), written down as a rule. Then decide whether
   `profiles/bonsai/` gets a `12g`/`16g` entry or the README keeps "raise `CTX` yourself" with
   that rule beside it. A hardware report with a larger card is the cheap way to the numbers.
2. **Blackwell (RTX 50xx)**: apt's CUDA 12.4 cannot target `sm_120`, and `build.sh` stops early
   saying so. Whether the fork's `PTQ1_0` kernels build and run with CUDA >= 12.8 from NVIDIA and
   gcc 14/15 is unknown, and the gcc-13 preference in `build.sh` may not be needed there. On such a
   card: `./install.sh build model`, start the server, record generation speed, and the install
   route in `docs/setup.md#toolchain` (which now covers CUDA 12.9 from NVIDIA for the 4060 Ti).
3. **AMD**: RDNA2/3 are expected to beat the RX 570 by a lot but nobody measured; the fork's #185
   reporter has a 9070 XT and a 860M. Ask for numbers through the hardware-report issue template
   (T-024) rather than buying cards.

The logs behind the measured numbers live in `runs/`, which is gitignored, so they are not public.
If a hardware report or a reviewer asks for one, decide then whether to publish a subset (from
T-024).

Out of scope: ROCm/HIP, Intel oneAPI, Apple. Vulkan is the one AMD path, stated as such.
