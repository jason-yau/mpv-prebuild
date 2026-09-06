#!/usr/bin/env bash
# Download and extract third-party sources into work/src/<name>.

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
load_versions

need_cmd tar
need_cmd curl
ensure_dir "$DL_DIR" "$SRC_DIR"

fetch() {
  local name="$1" url="$2" sha="${3:-}"
  local archive="$DL_DIR/$(basename "$url")"
  if [[ ! -f "$archive" ]]; then
    log "downloading $name"
    curl -L --fail --retry 5 --retry-delay 2 -o "$archive.partial" "$url"
    mv "$archive.partial" "$archive"
  fi
  verify_sha256 "$archive" "$sha"
  printf '%s\n' "$archive"
}

extract_to() {
  local archive="$1" dest="$2"
  rm -rf "$dest"
  ensure_dir "$dest"
  local tmp
  tmp=$(mktemp -d)
  case "$archive" in
    *.tar.xz) tar -xJf "$archive" -C "$tmp" ;;
    *.tar.bz2) tar -xjf "$archive" -C "$tmp" ;;
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$tmp" ;;
    *.zip) unzip -q "$archive" -d "$tmp" ;;
    *) die "unknown archive type: $archive" ;;
  esac
  local entries=()
  while IFS= read -r -d '' item; do
    entries+=("$item")
  done < <(find "$tmp" -mindepth 1 -maxdepth 1 -print0)
  if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
    # Move contents, including hidden files.
    shopt -s dotglob
    mv "${entries[0]}"/* "$dest/"
    shopt -u dotglob
  else
    mv "$tmp"/* "$dest/" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}

fetch_src() {
  local name="$1" url="$2" sha="${3:-}"
  local dest="$SRC_DIR/$name"
  if [[ -d "$dest" && -n "$(ls -A "$dest" 2>/dev/null || true)" ]]; then
    log "using cached source $name"
    return
  fi
  local archive
  archive=$(fetch "$name" "$url" "$sha")
  log "extracting $name"
  extract_to "$archive" "$dest"
}

fetch_src zlib     "$ZLIB_URL"     "${ZLIB_SHA256:-}"
fetch_src mbedtls  "$MBEDTLS_URL"  "${MBEDTLS_SHA256:-}"
fetch_src dav1d    "$DAV1D_URL"    "${DAV1D_SHA256:-}"
fetch_src libxml2  "$LIBXML2_URL"  "${LIBXML2_SHA256:-}"
fetch_src libpng   "$LIBPNG_URL"   "${LIBPNG_SHA256:-}"
fetch_src freetype "$FREETYPE_URL" "${FREETYPE_SHA256:-}"
fetch_src harfbuzz "$HARFBUZZ_URL" "${HARFBUZZ_SHA256:-}"
fetch_src fribidi  "$FRIBIDI_URL"  "${FRIBIDI_SHA256:-}"
fetch_src libass   "$LIBASS_URL"   "${LIBASS_SHA256:-}"
fetch_src uchardet "$UCHARDET_URL" "${UCHARDET_SHA256:-}"
fetch_src libiconv "$LIBICONV_URL" "${LIBICONV_SHA256:-}"
fetch_src ffmpeg     "$FFMPEG_URL"     "${FFMPEG_SHA256:-}"
fetch_src mpv        "$MPV_URL"        "${MPV_SHA256:-}"
fetch_src x264       "$X264_URL"       "${X264_SHA256:-}"
fetch_src libplacebo         "$LIBPLACEBO_URL"           "${LIBPLACEBO_SHA256:-}"
fetch_src libdisplay-info    "$LIBDISPLAY_INFO_URL"      "${LIBDISPLAY_INFO_SHA256:-}"
fetch_src wayland            "$WAYLAND_URL"              "${WAYLAND_SHA256:-}"
fetch_src wayland-protocols  "$WAYLAND_PROTOCOLS_URL"    "${WAYLAND_PROTOCOLS_SHA256:-}"

# Release tarballs omit git submodules. Drop in glad (OpenGL) and fast_float.
vendor_into() {
  local dest="$1" archive="$2"
  rm -rf "$dest"
  extract_to "$archive" "$dest"
}

if [[ ! -f "$SRC_DIR/libplacebo/3rdparty/glad/glad/__init__.py" ]]; then
  log "vendoring libplacebo 3rdparty/glad"
  vendor_into "$SRC_DIR/libplacebo/3rdparty/glad" "$(fetch glad "$GLAD_URL" "${GLAD_SHA256:-}")"
fi
if [[ ! -f "$SRC_DIR/libplacebo/3rdparty/fast_float/include/fast_float/fast_float.h" ]]; then
  log "vendoring libplacebo 3rdparty/fast_float"
  vendor_into "$SRC_DIR/libplacebo/3rdparty/fast_float" "$(fetch fast_float "$FAST_FLOAT_URL" "${FAST_FLOAT_SHA256:-}")"
fi

ensure_dir "$WORK_DIR/bin"
gas_src=$(fetch gas-preprocessor "$GAS_PREPROCESSOR_URL" "$GAS_PREPROCESSOR_SHA256")
cp "$gas_src" "$WORK_DIR/bin/gas-preprocessor.pl"
chmod +x "$WORK_DIR/bin/gas-preprocessor.pl"

log "sources ready in $SRC_DIR"
