# T-032 — A Dockerfile for the server, not for pi

- **Summary:** One `Dockerfile` that builds and runs `llama-server` in a container, with pi staying on the host and pointing at it through `SERVER_HOST`. It answers "my distro's apt cannot deliver the toolchain" without generalising `deps.sh`; it answers nothing about drivers, VRAM or the profile
- **Category:** feature
- **Importance:** medium
- **Effort:** M
- **Depends on:** none. T-005 (closed) settled the apt side: `deps` stops early and names NVIDIA's repository

## Why

`deps.sh` is apt. Where apt's CUDA is too old (Ubuntu 24.04, 22.04, Debian 13) it now stops at
once and points to NVIDIA's repository ([Toolchain](../docs/dev.md#toolchain)), which is four
commands and a pin on the host; every system beyond Debian and Ubuntu still brings its own
toolchain by hand. A container moves that one problem - and only that one - off the
host. The driver still has to be on the host, the card still needs 8 GB, and the profile
arithmetic does not change.

**The cut is what makes this small.** The split already exists in `config.env`: `LISTEN_HOST` is
what the server binds to, `SERVER_HOST` what pi connects to, and `bin/bonsai-pi` steps aside from
autostart as soon as `SERVER_HOST` is not this machine (see
[Server lifecycle](../docs/dev.md#server-lifecycle) and
[A server on another machine](../docs/dev.md#a-server-on-another-machine)). A container is that
case with a shorter network path. Everything in `bonsai-pi` that is hard - `setsid`, the `flock`
on `run/lock`, session pids, adopting an orphaned server - is not reimplemented, it is not needed:
the container runtime is the process manager.

**pi does not go in the container.** It edits the user's project, so it would need that directory
bind-mounted with matching uid, a tty for its TUI, and its session logs under
`pi-agent/sessions/{cwd-slug}/` would record container paths instead of host paths. Against that,
`scripts/pi.sh` already installs into `PI_PREFIX` and touches neither a global npm nor `~/.pi`.
There is nothing for a container to isolate.

**Four things that bite**, in the order they will:

1. **`GGML_NATIVE=ON`** (`build.sh`) compiles for the build host's CPU. In an image built on one
   machine and run on another that is a SIGILL on the first request. A distributable image needs
   `OFF`, and that is a flag change, so it needs a number: what does it cost in tok/s on the
   reference machine?
2. **Vulkan in a container** carries its own Mesa, independent of the host's. That is the
   `RADV_PERFTEST=nogttspill` trap from [Other GPU backends](../docs/dev.md#other-gpu-backends)
   with one more place to get the version wrong. CUDA is routine by comparison (NVIDIA Container
   Toolkit, WSL2 included).
3. **The GGUF stays out of the image.** 5.6 GB, and redistribution is not ours to decide. It is a
   volume; `MODEL_PATH` points into it, and `scripts/model.sh` runs on the host or in the
   container, not baked in.
4. **A published image is a second place the pins live.** Every move of `LLAMA_COMMIT`,
   `MODEL_REV` or `PI_VERSION` would mean a rebuild and a tag. A `Dockerfile` in the repo with no
   registry keeps one source of truth and costs the user the compile he would have had anyway.

## What

1. **`docker/Dockerfile`**, multi-stage: a build stage that installs the toolchain for `BACKEND`
   and runs the same steps `scripts/build.sh` runs (pinned commit, `patches/$BACKEND/` applied in
   name order), and a slim runtime stage with `llama-server` and the runtime libraries only. Build
   args for `BACKEND` and `LLAMA_COMMIT`, defaulting to `config.env`'s values - not a second copy
   of them.
2. **Entrypoint is `bin/bonsai-server`**, unchanged, sourcing `config.env` as it does today.
   `LISTEN_HOST=0.0.0.0` inside the container, the port published to `127.0.0.1:$PORT` on the
   host. The model as a read-only volume.
3. **`GGML_NATIVE`** becomes a `config.env` setting, default `ON` (what is measured), with the
   image setting `OFF`. Measure the difference on the RTX before writing the default down.
4. **The host side stays the documented remote-server path:** `SERVER_HOST=127.0.0.1` still holds
   with a published port, so `./install.sh model pi link` plus `SERVER_AUTOSTART=false` is the
   whole host install. Check that `bonsai-pi` does the right thing when the container is not up -
   it should say so, not wait 300 s.
5. **README:** a short subsection under Install, and the requirements line saying what the
   container does and does not remove (toolchain yes; driver, VRAM, profile no).

## Verify

- `docker build` for `cuda` on the reference machine, `vulkan` on the box; `curl /props` through
  the published port returns the same values the host server returns.
- Generation and an ~850-token prompt at the same window as
  [Other GPU backends](../docs/dev.md#other-gpu-backends), containerised against host, same
  session. A gap beyond noise is a finding, not a rounding error.
- `GGML_NATIVE=OFF` measured separately on the same machine, before and after.
- A `bonsai-pi` session against the container: one turn, and the session JSONL shows the usual
  `usage` counts.
