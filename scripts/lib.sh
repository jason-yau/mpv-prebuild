#!/usr/bin/env bash
# Shared helpers. Source this file from other scripts.

set -euo pipefail

_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$_LIB_DIR/.." && pwd)
CONFIG_DIR="$ROOT_DIR/config"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/work}"
SRC_DIR="${SRC_DIR:-$WORK_DIR/src}"
DL_DIR="${DL_DIR:-$WORK_DIR/download}"
JOBS="${JOBS:-}"

if [[ -z "$JOBS" ]]; then
  if command -v nproc >/dev/null 2>&1; then
    JOBS=$(nproc)
  elif command -v sysctl >/dev/null 2>&1; then
    JOBS=$(sysctl -n hw.ncpu)
  else
    JOBS=4
  fi
fi

# Print `export KEY=VAL` lines from versions.env (CRLF-safe). Do not `source`
# the file: macOS /bin/bash 3.2 drops assignments from `source` inside a function.
emit_version_exports() {
  local vf line key val
  vf="$CONFIG_DIR/versions.env"
  [[ -f "$vf" ]] || die "missing $vf"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    [[ "$key" == "$line" ]] && continue
    printf 'export %s=%s\n' "$key" "$val"
  done < "$vf"
}

load_versions() {
  eval "$(emit_version_exports)"
  [[ -n "${ZLIB_URL:-}" ]] || die "failed to load $CONFIG_DIR/versions.env (ZLIB_URL empty)"
  # Rebuilds skip via stamp files; changing versions.env must invalidate them.
  CONFIG_STAMP=$(sha256_of "$CONFIG_DIR/versions.env" | cut -c1-16)
  export CONFIG_STAMP
}

log() { printf '[mpv-prebuild] %s\n' "$*" >&2; }
die() { echo "error: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }
ensure_dir() { mkdir -p "$@"; }

require_sources() {
  local name
  for name in mpv ffmpeg zlib dav1d mbedtls libxml2 libpng freetype harfbuzz fribidi libass uchardet libplacebo; do
    if [[ ! -d "$SRC_DIR/$name" || -z "$(ls -A "$SRC_DIR/$name" 2>/dev/null || true)" ]]; then
      die "sources missing ($name); run without --skip-download"
    fi
  done
  if [[ "${OS:-}" == windows || "${OS:-}" == android ]]; then
    if [[ ! -d "$SRC_DIR/libiconv" || -z "$(ls -A "$SRC_DIR/libiconv" 2>/dev/null || true)" ]]; then
      die "sources missing (libiconv); run without --skip-download"
    fi
  fi
  if [[ "${OS:-}" == windows ]]; then
    if [[ ! -d "$SRC_DIR/spirv-cross" || -z "$(ls -A "$SRC_DIR/spirv-cross" 2>/dev/null || true)" ]]; then
      die "sources missing (spirv-cross); run without --skip-download"
    fi
  fi
  if [[ "${OS:-}" == linux ]]; then
    for name in libdisplay-info wayland wayland-protocols; do
      if [[ ! -d "$SRC_DIR/$name" || -z "$(ls -A "$SRC_DIR/$name" 2>/dev/null || true)" ]]; then
        die "sources missing ($name); run without --skip-download"
      fi
    done
  fi
  [[ -f "$SRC_DIR/libplacebo/3rdparty/glad/glad/__init__.py" ]] \
    || die "libplacebo 3rdparty/glad missing; run without --skip-download"
  [[ -f "$SRC_DIR/libplacebo/3rdparty/fast_float/include/fast_float/fast_float.h" ]] \
    || die "libplacebo 3rdparty/fast_float missing; run without --skip-download"
  [[ -f "$SRC_DIR/libplacebo/3rdparty/Vulkan-Headers/include/vulkan/vulkan.h" ]] \
    || die "libplacebo 3rdparty/Vulkan-Headers missing; run without --skip-download"
  if is_gpl; then
    if [[ ! -d "$SRC_DIR/x264" || -z "$(ls -A "$SRC_DIR/x264" 2>/dev/null || true)" ]]; then
      die "x264 sources missing; run without --skip-download"
    fi
  fi
}

flavor_license() {
  case "${1:-$FLAVOR}" in
    gpl) printf '%s\n' "GPL-2.0-or-later" ;;
    *) printf '%s\n' "LGPL-2.1-or-later" ;;
  esac
}

is_gpl() {
  [[ "${FLAVOR}" == gpl ]]
}

normalize_flavor() {
  case "$1" in
    default|lgpl) printf '%s\n' lgpl ;;
    gpl|encodersgpl|encoders-gpl) printf '%s\n' gpl ;;
    all) printf '%s\n' all ;;
    *) die "unsupported flavor: $1 (use lgpl, gpl, or all)" ;;
  esac
}

detect_version() {
  if [[ -n "${VERSION:-}" ]]; then
    printf '%s\n' "$VERSION"
    return
  fi
  if git -C "$ROOT_DIR" describe --tags --exact-match HEAD >/dev/null 2>&1; then
    git -C "$ROOT_DIR" describe --tags --exact-match HEAD
    return
  fi
  [[ -n "${MPV_VERSION:-}" ]] || die "MPV_VERSION unset; call load_versions first"
  printf '%s-%s\n' "$MPV_VERSION" "$(date -u +%Y%m%d%H%M%S)"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

verify_sha256() {
  local file="$1" expect="${2:-}"
  [[ -n "$expect" ]] || die "missing SHA256 for $(basename "$file"); set it in config/versions.env"
  [[ -f "$file" ]] || die "cannot verify SHA256: $file does not exist"
  local actual
  actual=$(sha256_of "$file")
  [[ "$actual" == "$expect" ]] || die "sha256 mismatch for $(basename "$file"): $actual != $expect"
}

stamp_dir() {
  [[ -n "${PREFIX:-}" ]] || die "PREFIX unset"
  [[ -n "${CONFIG_STAMP:-}" ]] || die "CONFIG_STAMP unset; call load_versions first"
  printf '%s/.stamps/%s\n' "$PREFIX" "$CONFIG_STAMP"
}

is_stamped() {
  [[ -f "$(stamp_dir)/$1" ]]
}

stamp() {
  ensure_dir "$(stamp_dir)"
  date -u +%Y-%m-%dT%H:%M:%SZ >"$(stamp_dir)/$1"
}

meson_array() {
  local out="[" first=1 arg
  for arg in "$@"; do
    [[ $first -eq 1 ]] || out+=", "
    out+="'${arg//\'/\'\'}'"
    first=0
  done
  out+="]"
  printf '%s' "$out"
}

# Run meson without leaking autotools-style CC/CFLAGS into the machine files.
# Meson >= 1.3 errors if default_library is set as both --default-library and
# -Ddefault_library. libass's project(default_options) already sets it; other
# projects (freetype) only mention default_library for subprojects, so a grep
# skip would wrongly build them shared.
run_meson() {
  local builddir="$1" srcdir="$2"
  shift 2
  (
    unset CC CXX AR RANLIB STRIP NM CFLAGS CXXFLAGS LDFLAGS
    local args=(
      setup "$builddir" "$srcdir"
      --prefix="$PREFIX"
      --libdir=lib
      --buildtype=release
      --wrap-mode=nodownload
      -Dstrip=true
    )
    local arg have_default_library=0
    for arg in "$@"; do
      case "$arg" in
        -Ddefault_library=*|--default-library=*) have_default_library=1 ;;
      esac
    done
    if [[ $have_default_library -eq 0 && "$(basename "$srcdir")" != libass ]]; then
      args+=(-Ddefault_library=static)
    fi
    if [[ -n "${MESON_CROSS:-}" ]]; then
      args+=(--cross-file "$MESON_CROSS")
    fi
    if [[ -n "${MESON_NATIVE:-}" ]]; then
      args+=(--native-file "$MESON_NATIVE")
    fi
    meson "${args[@]}" "$@"
  )
  meson compile -C "$builddir" -j "$JOBS"
  meson install -C "$builddir"
}

run_cmake() {
  local srcdir="$1"
  shift
  local builddir="$WORK_DIR/build/$TARGET_ID/$(basename "$srcdir")"
  ensure_dir "$builddir"
  local args=(
    -S "$srcdir"
    -B "$builddir"
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
    -DCMAKE_INSTALL_LIBDIR=lib
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DBUILD_SHARED_LIBS=OFF
    -DCMAKE_PREFIX_PATH="$PREFIX"
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  )
  if [[ -n "${CMAKE_TOOLCHAIN_FILE:-}" ]]; then
    args+=(-DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE")
    if [[ "${OS:-}" == android ]]; then
      args+=(
        -DANDROID_ABI="$ABI"
        -DANDROID_PLATFORM="android-${API}"
        -DANDROID_STL=c++_static
        -DCMAKE_FIND_ROOT_PATH="$PREFIX"
      )
    fi
  elif [[ "${NATIVE_BUILD:-0}" == 1 ]]; then
    args+=(
      -DCMAKE_C_COMPILER="$CC"
      -DCMAKE_CXX_COMPILER="$CXX"
    )
  else
    args+=(
      -DCMAKE_FIND_ROOT_PATH="$PREFIX"
      -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
      -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
      -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
      -DCMAKE_C_COMPILER="$CC"
      -DCMAKE_CXX_COMPILER="$CXX"
    )
    [[ -n "${CMAKE_SYSTEM_NAME:-}" ]] && args+=(-DCMAKE_SYSTEM_NAME="$CMAKE_SYSTEM_NAME")
  fi
  # CMake 3.31 try_compile archives via CMAKE_<LANG>_COMPILER_AR, and a bare
  # `triple-ar` is resolved relative to the working directory (repo root).
  if [[ "${OS:-}" != android && -n "${AR:-}" ]]; then
    args+=(
      -DCMAKE_AR="$AR"
      -DCMAKE_C_COMPILER_AR="$AR"
      -DCMAKE_CXX_COMPILER_AR="$AR"
    )
  fi
  if [[ "${OS:-}" != android && -n "${RANLIB:-}" ]]; then
    args+=(
      -DCMAKE_RANLIB="$RANLIB"
      -DCMAKE_C_COMPILER_RANLIB="$RANLIB"
      -DCMAKE_CXX_COMPILER_RANLIB="$RANLIB"
    )
  fi
  [[ -n "${CMAKE_OSX_SYSROOT:-}" ]] && args+=(-DCMAKE_OSX_SYSROOT="$CMAKE_OSX_SYSROOT")
  [[ -n "${CMAKE_OSX_ARCHITECTURES:-}" ]] && args+=(-DCMAKE_OSX_ARCHITECTURES="$CMAKE_OSX_ARCHITECTURES")
  [[ -n "${CMAKE_OSX_DEPLOYMENT_TARGET:-}" ]] && args+=(-DCMAKE_OSX_DEPLOYMENT_TARGET="$CMAKE_OSX_DEPLOYMENT_TARGET")
  cmake "${args[@]}" "$@"
  cmake --build "$builddir" -j "$JOBS"
  cmake --install "$builddir"
}

write_pc() {
  local name="$1" version="$2" libs="$3"
  ensure_dir "$PREFIX/lib/pkgconfig"
  cat >"$PREFIX/lib/pkgconfig/${name}.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: $name
Description: $name
Version: $version
Libs: -L\${libdir} $libs
Cflags: -I\${includedir}
EOF
}

# Load pins in the shell that sourced this file (top-level `eval`, not only a
# function body). Required for macOS /bin/bash 3.2.
eval "$(emit_version_exports)"
[[ -n "${ZLIB_URL:-}" ]] || die "failed to load $CONFIG_DIR/versions.env (ZLIB_URL empty)"
CONFIG_STAMP=$(sha256_of "$CONFIG_DIR/versions.env" | cut -c1-16)
export CONFIG_STAMP
