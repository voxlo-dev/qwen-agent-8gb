#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Puts the pinned GGUF at MODEL_PATH: links it from the Hugging Face cache when present, downloads it otherwise.
# A split GGUF (MODEL_FILE ending in -00001-of-0000N.gguf) is handled part by part, with one
# MODEL_SHA256 entry per part in order; llama.cpp finds the other parts next to the first.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

parts=("$MODEL_FILE")
if [[ "$MODEL_FILE" =~ ^(.*)-00001-of-([0-9]{5})\.gguf$ ]]; then
  parts=()
  for ((i = 1; i <= 10#${BASH_REMATCH[2]}; i++)); do
    parts+=("$(printf '%s-%05d-of-%s.gguf' "${BASH_REMATCH[1]}" "$i" "${BASH_REMATCH[2]}")")
  done
fi
read -ra sums <<<"$MODEL_SHA256"
((${#sums[@]} == ${#parts[@]})) || die "MODEL_SHA256 has ${#sums[@]} entries for ${#parts[@]} part(s) of $MODEL_FILE - one per part, in order"

dir="$(dirname "$MODEL_PATH")"
mkdir -p "$dir"
cache="${HF_HOME:-$HOME/.cache/huggingface}/hub/models--${MODEL_REPO//\//--}/snapshots/$MODEL_REV"

for n in "${!parts[@]}"; do
  part="${parts[$n]}"
  path="$dir/$(basename "$part")"
  label=""; ((${#parts[@]} > 1)) && label=" (part $((n + 1)) of ${#parts[@]})"

  if [[ -f "$path" ]]; then
    log "model present: $path"
    continue
  fi

  if [[ -f "$cache/$part" ]]; then
    log "linking from Hugging Face cache$label"
    ln -s "$(readlink -f "$cache/$part")" "$path"
    continue
  fi

  url="https://huggingface.co/$MODEL_REPO/resolve/$MODEL_REV/$part"
  [[ -f "$path.part" ]] && log "resuming an interrupted download$label" \
    || log "downloading $(basename "$part")$label (~$((MODEL_DISK_MB / 1024)).$((MODEL_DISK_MB % 1024 * 10 / 1024)) GB in all) - interrupting is safe, the next run resumes"
  # -# is the progress bar; -C - resumes a .part left by an interrupted run.
  curl -fL --retry 3 -C - -# -o "$path.part" "$url" \
    || die "download failed - run ./install.sh model again to resume from $path.part"

  log "verifying checksum (~30 s per 5 GB)"
  echo "${sums[$n]}  $path.part" | sha256sum -c --quiet - \
    || die "checksum mismatch: the file at $path.part is not entry $((n + 1)) of MODEL_SHA256 in models/$MODEL.env. Delete it and run ./install.sh model again; if it happens twice the pin and the remote file disagree"
  mv "$path.part" "$path"
done
log "model ready at $MODEL_PATH"
