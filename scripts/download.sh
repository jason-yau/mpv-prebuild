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
  # Usage: fetch NAME SHA256 URL [URL...]
  # Writes the archive path to FETCHED_ARCHIVE. Must not run only in $(...) —
  # die/exit inside command substitution would not stop the caller.
  local name="$1" sha="$2"
  shift 2
  local url archive actual
  FETCHED_ARCHIVE=""
  [[ $# -ge 1 && -n "$sha" ]] || die "fetch $name: url/sha missing"
  for url in "$@"; do
    [[ -n "$url" ]] || continue
    archive="$DL_DIR/$(basename "$url")"
    if [[ -f "$archive" ]]; then
      actual=$(sha256_of "$archive")
      if [[ "$actual" == "$sha" ]]; then
        FETCHED_ARCHIVE="$archive"
        return
      fi
      log "removing stale $archive"
      rm -f "$archive"
    fi
    log "downloading $name"
    log "  $url"
    if curl -L --fail --retry 3 --retry-delay 2 --retry-all-errors --connect-timeout 20 \
      -A "mpv-prebuild" \
      -o "$archive.partial" "$url"; then
      mv "$archive.partial" "$archive"
      actual=$(sha256_of "$archive")
      if [[ "$actual" == "$sha" ]]; then
        FETCHED_ARCHIVE="$archive"
        return
      fi
      if head -c 256 "$archive" | grep -qiE '<(!DOCTYPE|html)'; then
        log "$(basename "$archive") is HTML, not the archive (got $actual)"
      else
        log "sha256 mismatch for $(basename "$archive") (got $actual)"
      fi
      rm -f "$archive"
    else
      rm -f "$archive.partial"
      log "download failed: $url"
    fi
  done
  die "download failed: $name (all mirrors exhausted)"
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
  shift 3
  local dest="$SRC_DIR/$name"
  if [[ -d "$dest" && -n "$(ls -A "$dest" 2>/dev/null || true)" ]]; then
    log "using cached source $name"
    return
  fi
  fetch "$name" "$sha" "$url" "$@"
  log "extracting $name"
  extract_to "$FETCHED_ARCHIVE" "$dest"
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
fetch_src uchardet "$UCHARDET_URL" "${UCHARDET_SHA256:-}" \
  "https://deb.debian.org/debian/pool/main/u/uchardet/uchardet_0.0.8.orig.tar.xz" \
  "https://mirrors.ustc.edu.cn/debian/pool/main/u/uchardet/uchardet_0.0.8.orig.tar.xz"
fetch_src libiconv "$LIBICONV_URL" "${LIBICONV_SHA256:-}"
fetch_src ffmpeg     "$FFMPEG_URL"     "${FFMPEG_SHA256:-}"
fetch_src mpv        "$MPV_URL"        "${MPV_SHA256:-}"
fetch_src x264       "$X264_URL"       "${X264_SHA256:-}" \
  "https://code.videolan.org/videolan/x264/-/archive/b35605ace3ddf7c1a5d67a2eb553f034aef41d55/x264-b35605ace3ddf7c1a5d67a2eb553f034aef41d55.tar.gz"
fetch_src libplacebo         "$LIBPLACEBO_URL"           "${LIBPLACEBO_SHA256:-}"
fetch_src vulkan-headers     "$VULKAN_HEADERS_URL"       "${VULKAN_HEADERS_SHA256:-}"
fetch_src vulkan-loader      "$VULKAN_LOADER_URL"        "${VULKAN_LOADER_SHA256:-}"
fetch_src xxhash             "$XXHASH_URL"               "${XXHASH_SHA256:-}"
fetch_src lcms2              "$LCMS2_URL"                "${LCMS2_SHA256:-}"
fetch_src libdovi            "$LIBDOVI_URL"              "${LIBDOVI_SHA256:-}"
fetch_src spirv-cross        "$SPIRV_CROSS_URL"          "${SPIRV_CROSS_SHA256:-}"
fetch_src shaderc            "$SHADERC_URL"              "${SHADERC_SHA256:-}"
fetch_src libdisplay-info    "$LIBDISPLAY_INFO_URL"      "${LIBDISPLAY_INFO_SHA256:-}" \
  "https://mirrors.ustc.edu.cn/debian/pool/main/libd/libdisplay-info/libdisplay-info_0.3.0.orig.tar.bz2"
fetch_src wayland            "$WAYLAND_URL"              "${WAYLAND_SHA256:-}" \
  "https://mirrors.ustc.edu.cn/debian/pool/main/w/wayland/wayland_1.23.1.orig.tar.gz"
fetch_src wayland-protocols  "$WAYLAND_PROTOCOLS_URL"    "${WAYLAND_PROTOCOLS_SHA256:-}" \
  "https://mirrors.ustc.edu.cn/debian/pool/main/w/wayland-protocols/wayland-protocols_1.44.orig.tar.xz"

# Release tarballs omit git submodules. Drop in glad (OpenGL) and fast_float.
vendor_into() {
  local dest="$1" archive="$2"
  rm -rf "$dest"
  extract_to "$archive" "$dest"
}

if [[ ! -f "$SRC_DIR/libplacebo/3rdparty/glad/glad/__init__.py" ]]; then
  log "vendoring libplacebo 3rdparty/glad"
  fetch glad "${GLAD_SHA256:-}" "$GLAD_URL"
  vendor_into "$SRC_DIR/libplacebo/3rdparty/glad" "$FETCHED_ARCHIVE"
fi
if [[ ! -f "$SRC_DIR/libplacebo/3rdparty/fast_float/include/fast_float/fast_float.h" ]]; then
  log "vendoring libplacebo 3rdparty/fast_float"
  fetch fast_float "${FAST_FLOAT_SHA256:-}" "$FAST_FLOAT_URL"
  vendor_into "$SRC_DIR/libplacebo/3rdparty/fast_float" "$FETCHED_ARCHIVE"
fi
if [[ ! -f "$SRC_DIR/libplacebo/3rdparty/Vulkan-Headers/include/vulkan/vulkan.h" ]]; then
  log "vendoring libplacebo 3rdparty/Vulkan-Headers"
  rm -rf "$SRC_DIR/libplacebo/3rdparty/Vulkan-Headers"
  mkdir -p "$SRC_DIR/libplacebo/3rdparty"
  cp -a "$SRC_DIR/vulkan-headers" "$SRC_DIR/libplacebo/3rdparty/Vulkan-Headers"
fi

# shaderc release tarball has no git-sync-deps; drop in DEPS pins.
if [[ ! -f "$SRC_DIR/shaderc/third_party/glslang/CMakeLists.txt" ]]; then
  log "vendoring shaderc third_party/glslang"
  fetch glslang "${GLSLANG_SHA256:-}" "$GLSLANG_URL"
  vendor_into "$SRC_DIR/shaderc/third_party/glslang" "$FETCHED_ARCHIVE"
fi
if [[ ! -f "$SRC_DIR/shaderc/third_party/spirv-headers/CMakeLists.txt" ]]; then
  log "vendoring shaderc third_party/spirv-headers"
  fetch spirv-headers "${SPIRV_HEADERS_SHA256:-}" "$SPIRV_HEADERS_URL"
  vendor_into "$SRC_DIR/shaderc/third_party/spirv-headers" "$FETCHED_ARCHIVE"
fi
if [[ ! -f "$SRC_DIR/shaderc/third_party/spirv-tools/CMakeLists.txt" ]]; then
  log "vendoring shaderc third_party/spirv-tools"
  fetch spirv-tools "${SPIRV_TOOLS_SHA256:-}" "$SPIRV_TOOLS_URL"
  vendor_into "$SRC_DIR/shaderc/third_party/spirv-tools" "$FETCHED_ARCHIVE"
fi

ensure_dir "$WORK_DIR/bin"
fetch gas-preprocessor "$GAS_PREPROCESSOR_SHA256" "$GAS_PREPROCESSOR_URL"
cp "$FETCHED_ARCHIVE" "$WORK_DIR/bin/gas-preprocessor.pl"
chmod +x "$WORK_DIR/bin/gas-preprocessor.pl"

log "sources ready in $SRC_DIR"
