#!/usr/bin/env bash
# Install llvm-mingw for Windows cross builds (Linux CI / Linux hosts).

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
load_versions

need_cmd curl
need_cmd tar

dest="${LLVM_MINGW_HOME:-$WORK_DIR/llvm-mingw}"
if [[ -x "$dest/bin/x86_64-w64-mingw32-clang" ]]; then
  log "llvm-mingw already present at $dest"
  echo "$dest"
  exit 0
fi

archive="$DL_DIR/$(basename "$LLVM_MINGW_URL")"
ensure_dir "$DL_DIR" "$(dirname "$dest")"
if [[ ! -f "$archive" ]]; then
  log "downloading llvm-mingw $LLVM_MINGW_VERSION"
  curl -L --fail --retry 5 -o "$archive.partial" "$LLVM_MINGW_URL"
  mv "$archive.partial" "$archive"
fi
verify_sha256 "$archive" "${LLVM_MINGW_SHA256:-}"

tmp=$(mktemp -d)
tar -xJf "$archive" -C "$tmp"
inner=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)
rm -rf "$dest"
mv "$inner" "$dest"
rm -rf "$tmp"
log "llvm-mingw installed to $dest"
echo "$dest"
