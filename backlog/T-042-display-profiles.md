# T-042 — The `display` profiles, checked once with a desktop on the card

- **Summary:** All three `display` profiles are arithmetic or were measured without a desktop on the card. One sitting with a monitor on the 4060 Ti: start each, read VRAM, run one long prompt, and find Bonsai's largest window that still keeps every layer on the card. Bonsai stays at `q8_0`/`q4_0`: 64k is final for `dedicated` (T-041)
- **Category:** decision
- **Importance:** medium
- **Effort:** S (one sitting, ~1 h)
- **Depends on:** a monitor on the 4060 Ti, which the machine does not have while it runs headless. Merges the display half of T-008 and the `display` checks of T-034 and T-035

## Why

A desktop on the same card takes 0.5-1.2 GB, and every `display` profile guesses where that
leaves it:

| Model | `display` today | Basis |
| --- | --- | --- |
| Bonsai | 48k, `q8_0`/`q4_0`, budget 4096/12000/12000/8000 | the T-012 run, on WSL2 |
| Bonsai, candidate | 64k, `q4_0`/`q4_0`, the dedicated budget 8192/16000/16000/12000 | arithmetic: 64 x 18 = 1 152 MiB of cache, less than today's 48 x 26 = 1 248 ([T-035's table](../docs/context-window.md#bonsai-windows-on-8-gb)) |
| Qwen3.6 | 131k, `CPU_MOE` 40 | arithmetic, ~6 430 MiB |
| Qwen3.8-Flash | 64k | 6 052 MiB measured without a desktop |

The budget at 48k cut thinking at 4096 and produced the weakest result on record
([agent.md](../docs/agent.md#context-budget)), so the candidate is worth more than a check. On native
Linux the driver fails an allocation instead of spilling silently into shared memory as WDDM
does, so a profile that does not fit now says so at start.

## What

With a normal desktop on the card (browser and editor open, `nvidia-smi` reading what they take):

1. **Bonsai**: 64k `q8_0`/`q4_0` stays `dedicated` (T-041 cut its 96k pair), so find the largest
   `CTX` at that cache type that loads and reads a prompt at full speed with the desktop on the card.
2. **Qwen3.6** and **Qwen3.8-Flash**: start each with `PROFILE=display`, one ~43k prompt, pp and
   VRAM. Fits: the comment loses "Not measured with a desktop". Does not: one expert layer more
   in RAM (~470 MiB for Qwen3.6) or a smaller window, and the comment says which.
3. The rule a user can apply without measuring: free VRAM before start against each profile's
   buffers, written next to the profiles in [context-window.md](../docs/context-window.md). Whether
   `bonsai-server` should pick the profile from free VRAM itself is the question that table
   answers; preflight already warns when a display is on the card.
