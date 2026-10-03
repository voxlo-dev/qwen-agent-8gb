# T-017 — Upstream: a pin that makes the Vulkan patch, and then the fork, unnecessary

- **Summary:** Watch the fork (#185, #252) and mainline (ggml-org#29077) for a PTQ1_0 decode that makes `patches/vulkan/` unnecessary, and for mainline support that makes the fork pin unnecessary. Either event: move the pin, re-measure on both cards, drop what is no longer needed
- **Category:** decision
- **Importance:** medium
- **Effort:** S per event, waiting in between
- **Depends on:** upstream. Merges T-029 (watch mainline)

## Why

Bonsai needs two things mainline llama.cpp does not have: ggml type 143 (`PTQ1_0`), which is why
`LLAMA_COMMIT` pins PrismML's fork, and a fast Vulkan decode for it, which is why `build` applies
`patches/vulkan/0001-ptq1_0-table-decode.patch` (T-016: 633 → 143 ms/token and 36 → 54 tok/s
prompt on the RX 570, bit-exact against the CPU backend). Both are being fixed upstream, and each
fix makes something here a liability.

**Done on the fork side.** Decided 2026-09-21: a comment, not a PR (two PRs were ahead, and the
fork's `CONTRIBUTING.md` needs an author who can defend every line without AI help). Posted as
<https://github.com/PrismML-Eng/llama.cpp/issues/185#issuecomment-5759986235> under `voxlo-dev`;
its patch link points at `main` of this repo, so the file stays at that path. On 2026-09-24 the
maintainer pointed at #252 (dedicated PTQ1_0 `mul_mat_vec` for cards without integer dot).
Measured on the RX 570 (`runs/T-017-pr252-rx570/`, [bonsai.md](../docs/bonsai.md#other-gpu-backends)):
#252 matches the patch on generation, so only its `mul_mm` half (+50 % on prompts) is still
unique. Comment texts for #252 and the correction on #185 are in that run folder.
`upstream-pr-body.md` and `upstream-commands.sh` in `runs/T-016-ptq1_0-vulkan-decode/` are the PR
path, kept in case the decision is revisited.

## What, when it happens

**Watch**, occasionally: fork #185, #187, #188, #252; mainline #29077 (PQ2_0/PTQ1_0 types) and
#22019. Answer questions with measurements, not code. Record merge commits here.

**A fork commit carries an equivalent decode** (#252 or another):

1. Move `LLAMA_COMMIT`, run the CUDA build, and the RX 570 measurement
   (`runs/T-016-ptq1_0-vulkan-decode/measure.sh`).
2. Generation no slower than 143 ms/token and prompts as fast: delete `patches/vulkan/`, and the
   patch mentions in `README.md`, `AGENTS.md` and `docs/bonsai.md#other-gpu-backends`.
3. #252 without a faster `mul_mm` loader: decide whether +50 % on prompts is worth a patch; if
   yes, cut it down to the `mul_mm` half. Slower: keep the patch and rebase it.

**Mainline takes PTQ1_0** (#29077 merged):

1. Mainline at that commit: `PTQ1_0` loads, CUDA speed on the 4060 Ti against 36.6 tok/s,
   `patches/vulkan/` applies, RX 570 against 143 ms/token.
2. Decide Bonsai's `LLAMA_COMMIT`: fork or mainline. Mainline would let Bonsai share Qwen3.6's
   tree. Either way `build` must stop applying a patch the tree already contains
   (`git apply --check` before applying, or a stamp).
3. README: a "stock llama.cpp / Ollama / LM Studio" paragraph for people who only want the
   server; `bonsai-pi` and the profiles are what remains of this repo's value.

Not in scope: the dedicated PTQ1_0 mat-vec kernel (ceiling ~22 tok/s on the RX 570).
