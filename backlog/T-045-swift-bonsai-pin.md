# T-045 — Bonsai's pin to Swift-Bonsai-2

- **Summary:** Move `models/bonsai.env` from Ternary-Bonsai-2 to Swift-Bonsai-2 PTQ1_0, the author's call after T-041 judged W marginally better than C2. A drop-in: same fork, template, size and speed; the GGUF is already on the 4060 Ti machine
- **Category:** chore
- **Importance:** low
- **Effort:** S
- **Depends on:** none; best before T-044's README so it names the right file

## Why

W against C2 ([bonsai.md](../docs/bonsai.md#swift-bonsai-2)): neither finished, W's result was
marginally better by hand, the median step thought less, the session in all did not. n = 1 at
temperature 1.0 cannot separate that from variance, and W also ran without the agent prompt. The
author takes it anyway: nothing measured is worse, the speed and VRAM are identical, and with
Bonsai moving to "simple tasks" (T-044) a shorter thought per step is the property that matters.
The doc says so in those words, so the pin does not read as a measured win.

W ran at this repo's `EFFORT` medium; UkisAI ships `reasoning_effort: xhigh` in its
`generation_config.json` and benchmarked there. With `BUDGET` cutting every turn at 8192 and the
effort level measured to barely matter on Bonsai ([bonsai.md](../docs/bonsai.md#reasoning)), `EFFORT`
stays `medium`; the doc names the difference.

## What

1. `models/bonsai.env`: `MODEL_REPO=ukisai/Swift-Bonsai-2-GGUF`, `MODEL_REV=a3bdac086bbb6b04d87d0108d18943b5f63868f7`,
   `MODEL_FILE=Swift-Bonsai-2-PTQ1_0.gguf`, `MODEL_SHA256=de33620b60eaf63e96449b478eb87abe9538507e3ed939da944c1ae15fe1ffc6`.
   `MODEL_ALIAS` stays `bonsai-27b`, so pi's config and running habits do not change. The header
   comment names Swift and UkisAI.
2. License: Apache-2.0 like the base; the README's acknowledgements and model links add UkisAI.
3. `docs/bonsai.md#swift-bonsai-2` from "Not wired" to the pin and the reason above; `#model-format`
   and anything naming the Ternary file follow (`grep -rn Ternary-Bonsai`).
4. `./install.sh model` on a machine with the old file: fetches the new one, leaves the old in
   place (say so in the log; deleting is the user's).

## Done when

`./install.sh model pi` twice (second run: "model present"), `bonsai-server` serves
`Swift-Bonsai-2-PTQ1_0.gguf` under `bonsai-27b`, `/props` shows the template unchanged.
