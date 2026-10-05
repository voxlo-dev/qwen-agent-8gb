#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Puts the pinned GGUF at MODEL_PATH, and with VISION=1 its projector at MMPROJ_PATH: links each
# file from the Hugging Face cache when present, downloads it otherwise, and checks it against its pin.
# A split GGUF (MODEL_FILE ending in -00001-of-0000N.gguf) is handled part by part, with one
# MODEL_SHA256 entry per part in order; llama.cpp finds the other parts next to the first.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mapfile -t parts < <(model_parts)
read -ra sums <<<"$MODEL_SHA256"
((${#sums[@]} == ${#parts[@]})) || die "MODEL_SHA256 has ${#sums[@]} entries for ${#parts[@]} part(s) of $MODEL_FILE - one per part, in order"

dir="$(dirname "$MODEL_PATH")"
mkdir -p "$dir"
cache="${HF_HOME:-$HOME/.cache/huggingface}/hub/models--${MODEL_REPO//\//--}/snapshots/$MODEL_REV"

# fetch FILE-IN-REPO PATH SHA256 SIZE-MB LABEL: one file of the pinned revision to PATH.
fetch() {
  local file="$1" path="$2" sum="$3" mb="$4" label="$5"
  if [[ -f "$path" ]]; then
    log "present: $path"
    return
  fi
  if [[ -f "$cache/$file" ]]; then
    log "linking $(basename "$file")$label from the Hugging Face cache"
    ln -s "$(readlink -f "$cache/$file")" "$path"
    return
  fi
  local url="https://huggingface.co/$MODEL_REPO/resolve/$MODEL_REV/$file"
  [[ -f "$path.part" ]] && log "resuming an interrupted download$label" \
    || log "downloading $(basename "$file")$label (~$((mb / 1024)).$((mb % 1024 * 10 / 1024)) GB) - interrupting is safe, the next run resumes"
  # -# is the progress bar; -C - resumes a .part left by an interrupted run.
  curl -fL --retry 3 -C - -# -o "$path.part" "$url" \
    || die "download failed - run ./install.sh model again to resume from $path.part"

  log "verifying checksum (~30 s per 5 GB)"
  echo "$sum  $path.part" | sha256sum -c --quiet - \
    || die "checksum mismatch: the file at $path.part is not the one pinned in models/$MODEL.env. Delete it and run ./install.sh model again; if it happens twice the pin and the remote file disagree"
  mv "$path.part" "$path"
}

for n in "${!parts[@]}"; do
  label=""; ((${#parts[@]} > 1)) && label=" (part $((n + 1)) of ${#parts[@]})"
  fetch "${parts[$n]}" "$dir/$(basename "${parts[$n]}")" "${sums[$n]}" $((MODEL_DISK_MB / ${#parts[@]})) "$label"
done
log "model ready at $MODEL_PATH"

if [[ "$VISION" == 1 ]]; then
  fetch "$MMPROJ_FILE" "$MMPROJ_PATH" "$MMPROJ_SHA256" "$MMPROJ_DISK_MB" " (vision projector)"
  log "vision projector ready at $MMPROJ_PATH"
fi
