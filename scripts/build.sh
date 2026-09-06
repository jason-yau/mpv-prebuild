#!/usr/bin/env bash
# Build libmpv for one target and emit a redistributable SDK archive.
#
# Examples:
#   ./scripts/build.sh --os android --arch arm64
#   ./scripts/build.sh --os windows --arch x86_64
#   ./scripts/build.sh --os macos --arch arm64
#   ./scripts/build.sh --os linux --arch x86_64
#   ./scripts/build.sh --os android --arch all

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/toolchain.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/pkgs.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/package.sh"

load_versions

OS=""
ARCH=""
FLAVOR=all
SKIP_DOWNLOAD=0
DO_PACKAGE=1
CLEAN=0

usage() {
  cat <<'EOF'
Usage: scripts/build.sh --os <os> --arch <arch> [options]

  --os        windows | android | macos | ios | iossimulator | linux
              (ubuntu is an alias for linux)
  --arch      x86_64 | x86 | arm64 | armv7 | all | universal
  --flavor    all (default) | lgpl | gpl
              all  = build both LGPL and GPL packages
              lgpl = FFmpeg/mpv without GPL (commercial-friendly)
              gpl  = FFmpeg --enable-gpl + libx264, mpv -Dgpl=true
  --jobs      parallel compile jobs
  --skip-download
  --no-package
  --clean     wipe work/prefix for this target first
  --version   artifact version label (default: UTC YYYYMMDDHHMMSS)

Android --arch all builds arm64, armv7, x86, x86_64 then a jniLibs zip.
macOS --arch universal builds arm64 + x86_64 and lipo-s them.
Linux builds natively; --arch must match the host (x86_64 or arm64).
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --os) OS="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    --flavor) FLAVOR="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --skip-download) SKIP_DOWNLOAD=1; shift ;;
    --no-package) DO_PACKAGE=0; shift ;;
    --clean) CLEAN=1; shift ;;
    -h|--help) usage 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$OS" && -n "$ARCH" ]] || usage 1
case "$OS" in
  ubuntu) OS=linux ;;
esac
FLAVOR=$(normalize_flavor "$FLAVOR")
VERSION="$(detect_version)"
export VERSION

need_cmd meson
need_cmd ninja
need_cmd cmake
need_cmd pkg-config
need_cmd make
need_cmd curl

ALL_ARCHS=()
UNIVERSAL=0
case "$OS-$ARCH" in
  android-all) ALL_ARCHS=(arm64 armv7 x86 x86_64) ;;
  windows-all) ALL_ARCHS=(x86_64 arm64) ;;
  macos-all) ALL_ARCHS=(arm64 x86_64) ;;
  macos-universal) ALL_ARCHS=(arm64 x86_64); UNIVERSAL=1 ;;
  linux-all) ALL_ARCHS=("$(linux_host_arch)") ;;
  *-all) die "--arch all is not defined for $OS" ;;
  *) ALL_ARCHS=("$ARCH") ;;
esac

FLAVORS=()
case "$FLAVOR" in
  all) FLAVORS=(lgpl gpl) ;;
  *) FLAVORS=("$FLAVOR") ;;
esac

build_one() {
  local arch="$1"
  ARCH="$arch"
  setup_target
  if [[ "$CLEAN" -eq 1 ]]; then
    log "cleaning $PREFIX"
    rm -rf "$PREFIX" "$WORK_DIR/build/$TARGET_ID"
  fi
  if [[ "$SKIP_DOWNLOAD" -eq 0 ]]; then
    bash "$SCRIPT_DIR/download.sh"
  else
    require_sources
  fi
  log "building $OS/$ARCH flavor=$FLAVOR"
  build_deps
  if [[ "$DO_PACKAGE" -eq 1 ]]; then
    package_target "$(detect_version)"
  fi
}

for FLAVOR in "${FLAVORS[@]}"; do
  for arch in "${ALL_ARCHS[@]}"; do
    build_one "$arch"
  done

  if [[ "$DO_PACKAGE" -eq 1 && "$OS" == android && ${#ALL_ARCHS[@]} -gt 1 ]]; then
    merge_android_abis "$(detect_version)"
  fi
  if [[ "$DO_PACKAGE" -eq 1 && "$UNIVERSAL" -eq 1 ]]; then
    lipo_macos_universal "$(detect_version)"
  fi
done

log "done"
