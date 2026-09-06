#!/usr/bin/env bash
# Resolve compilers, sysroots, and generated meson/cmake toolchain files.

setup_target() {
  OS="${OS:?}"
  ARCH="${ARCH:?}"
  FLAVOR="${FLAVOR:-lgpl}"
  FLAVOR=$(normalize_flavor "$FLAVOR")
  [[ "$FLAVOR" != all ]] || die "setup_target: resolve 'all' before calling"

  case "$OS" in
    ubuntu) OS=linux ;;
  esac

  case "$OS" in
    windows|android|macos|ios|iossimulator|linux) ;;
    *) die "unsupported os: $OS" ;;
  esac

  case "$ARCH" in
    x86_64|x86|i686|arm64|aarch64|armv7|armeabi-v7a) ;;
    *) die "unsupported arch: $ARCH" ;;
  esac

  # Canonical names used in artifact paths.
  case "$ARCH" in
    aarch64) ARCH=arm64 ;;
    i686) ARCH=x86 ;;
    armeabi-v7a) ARCH=armv7 ;;
  esac

  TARGET_ID="${OS}-${ARCH}-${FLAVOR}"
  PREFIX="$WORK_DIR/prefix/$TARGET_ID"
  TOOL_DIR="$WORK_DIR/toolchain/${OS}-${ARCH}"
  ensure_dir "$PREFIX" "$TOOL_DIR" "$WORK_DIR/build/$TARGET_ID"

  # Rebuilding a second flavor in the same shell must not keep the previous prefix on PATH.
  : "${_PREBUILD_BASE_PATH:=$PATH}"
  : "${_PREBUILD_BASE_PKG_CONFIG_PATH:=${PKG_CONFIG_PATH:-}}"
  : "${_PREBUILD_BASE_LIBRARY_PATH:=${LIBRARY_PATH:-}}"
  : "${_PREBUILD_BASE_CPATH:=${CPATH:-}}"
  export PATH="$PREFIX/bin:${_PREBUILD_BASE_PATH}"
  export LIBRARY_PATH="$PREFIX/lib${_PREBUILD_BASE_LIBRARY_PATH:+:$_PREBUILD_BASE_LIBRARY_PATH}"
  export CPATH="$PREFIX/include${_PREBUILD_BASE_CPATH:+:$_PREBUILD_BASE_CPATH}"

  # wayland-protocols (and other data-only packages) install .pc under share/.
  local prefix_pc="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
  export PKG_CONFIG_LIBDIR="$prefix_pc"
  export PKG_CONFIG_PATH="$prefix_pc"
  unset PKG_CONFIG_SYSROOT_DIR || true

  CFLAGS_EXTRA=(-fPIC -O2 -DNDEBUG)
  CXXFLAGS_EXTRA=(-fPIC -O2 -DNDEBUG)
  LDFLAGS_EXTRA=()
  NATIVE_BUILD=0
  MESON_NATIVE=""
  HOST_CC=""
  HOST_CFLAGS=""
  HOST_LDFLAGS=""

  case "$OS" in
    android) _setup_android ;;
    windows) _setup_windows ;;
    macos|ios|iossimulator) _setup_darwin ;;
    linux) _setup_linux ;;
  esac

  case "$OS" in
    windows|android)
      CFLAGS_EXTRA+=(-I"$PREFIX/include")
      CXXFLAGS_EXTRA+=(-I"$PREFIX/include")
      LDFLAGS_EXTRA+=(-L"$PREFIX/lib")
      ;;
  esac
  # libpng (and others) need libm; meson will not always pull Libs.private.
  LDFLAGS_EXTRA+=(-lm)

  export CC CXX AR RANLIB STRIP NM PKG_CONFIG HOST_TRIPLE NATIVE_BUILD RC CMAKE_TOOLCHAIN_FILE
  export HOST_CC HOST_CFLAGS HOST_LDFLAGS
  export CFLAGS="${CFLAGS_EXTRA[*]}"
  export CXXFLAGS="${CXXFLAGS_EXTRA[*]}"
  export LDFLAGS="${LDFLAGS_EXTRA[*]}"

  _write_meson_cross
  _write_cmake_toolchain
  export MESON_CROSS MESON_NATIVE
  log "target $TARGET_ID cc=$CC prefix=$PREFIX"
}

linux_host_arch() {
  case "$(uname -m)" in
    x86_64) echo x86_64 ;;
    aarch64|arm64) echo arm64 ;;
    *) die "unsupported Linux host arch: $(uname -m)" ;;
  esac
}

_setup_linux() {
  [[ "$(uname -s)" == Linux ]] || die "linux target must be built on Linux"
  local host_arch
  host_arch=$(linux_host_arch)
  [[ "$ARCH" == "$host_arch" ]] || die "linux $ARCH must be built natively (host is $host_arch)"

  NATIVE_BUILD=1
  PKG_CONFIG=$(command -v pkg-config)
  [[ -n "$PKG_CONFIG" ]] || die "pkg-config not found"

  if command -v gcc >/dev/null 2>&1 && command -v g++ >/dev/null 2>&1; then
    CC=gcc
    CXX=g++
  elif command -v clang >/dev/null 2>&1 && command -v clang++ >/dev/null 2>&1; then
    CC=clang
    CXX=clang++
  else
    die "gcc or clang is required for linux builds"
  fi

  AR=$(command -v gcc-ar || command -v ar)
  RANLIB=$(command -v gcc-ranlib || command -v ranlib)
  STRIP=$(command -v strip)
  NM=$(command -v gcc-nm || command -v nm)
  [[ -n "$AR" && -n "$RANLIB" && -n "$STRIP" && -n "$NM" ]] || die "binutils (ar/ranlib/strip/nm) not found"

  case "$ARCH" in
    x86_64)
      CPU_FAMILY=x86_64
      CPU=x86_64
      FFMPEG_ARCH=x86_64
      HOST_TRIPLE=x86_64-linux-gnu
      ;;
    arm64)
      CPU_FAMILY=aarch64
      CPU=aarch64
      FFMPEG_ARCH=aarch64
      HOST_TRIPLE=aarch64-linux-gnu
      ;;
    *) die "unsupported linux arch: $ARCH (use x86_64 or arm64)" ;;
  esac

  FFMPEG_OS=linux
  MESON_SYSTEM=linux
  CMAKE_SYSTEM_NAME=""
  CMAKE_TOOLCHAIN_FILE=""
  ABI="$ARCH"
  TRIPLE=""
  LDFLAGS_EXTRA+=(-static-libstdc++ -static-libgcc -pthread -Wl,-rpath,'$ORIGIN')

  # PREFIX first, but keep distro .pc files (alsa, pulse, x11, vaapi, …).
  # share/pkgconfig is required: wayland-protocols installs there, not lib/.
  unset PKG_CONFIG_LIBDIR
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig${_PREBUILD_BASE_PKG_CONFIG_PATH:+:$_PREBUILD_BASE_PKG_CONFIG_PATH}"
}

_host_ndk_tag() {
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) echo linux-x86_64 ;;
    Darwin-arm64) echo darwin-arm64 ;;
    Darwin-x86_64) echo darwin-x86_64 ;;
    *) die "unsupported NDK host: $(uname -s)-$(uname -m)" ;;
  esac
}

_find_ndk() {
  if [[ -n "${ANDROID_NDK_HOME:-}" && -d "$ANDROID_NDK_HOME" ]]; then
    printf '%s\n' "$ANDROID_NDK_HOME"
    return
  fi
  if [[ -n "${ANDROID_NDK_ROOT:-}" && -d "$ANDROID_NDK_ROOT" ]]; then
    printf '%s\n' "$ANDROID_NDK_ROOT"
    return
  fi
  if [[ -n "${ANDROID_HOME:-}" ]]; then
    local latest
    latest=$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -n1 || true)
    [[ -n "$latest" ]] && { printf '%s\n' "$latest"; return; }
  fi
  die "Android NDK not found. Set ANDROID_NDK_HOME."
}

_setup_android() {
  NDK=$(_find_ndk)
  API="${ANDROID_API:-21}"
  local prebuilt="$NDK/toolchains/llvm/prebuilt/$(_host_ndk_tag)"
  [[ -d "$prebuilt" ]] || prebuilt=$(echo "$NDK"/toolchains/llvm/prebuilt/*)
  [[ -d "$prebuilt" ]] || die "NDK llvm prebuilt not found in $NDK"
  export PATH="$prebuilt/bin:$PATH"
  PKG_CONFIG=$(command -v pkg-config)

  case "$ARCH" in
    arm64)
      ABI=arm64-v8a
      TRIPLE=aarch64-linux-android
      CC_TRIPLE=aarch64-linux-android${API}
      CPU_FAMILY=aarch64
      CPU=aarch64
      FFMPEG_ARCH=aarch64
      ;;
    armv7)
      ABI=armeabi-v7a
      TRIPLE=arm-linux-androideabi
      CC_TRIPLE=armv7a-linux-androideabi${API}
      CPU_FAMILY=arm
      CPU=armv7-a
      FFMPEG_ARCH=arm
      CFLAGS_EXTRA+=(-mfpu=neon -mcpu=cortex-a8)
      ;;
    x86)
      ABI=x86
      TRIPLE=i686-linux-android
      CC_TRIPLE=i686-linux-android${API}
      CPU_FAMILY=x86
      CPU=i686
      FFMPEG_ARCH=i686
      ;;
    x86_64)
      ABI=x86_64
      TRIPLE=x86_64-linux-android
      CC_TRIPLE=x86_64-linux-android${API}
      CPU_FAMILY=x86_64
      CPU=x86_64
      FFMPEG_ARCH=x86_64
      ;;
  esac

  CC="$prebuilt/bin/${CC_TRIPLE}-clang"
  CXX="$prebuilt/bin/${CC_TRIPLE}-clang++"
  AR="$prebuilt/bin/llvm-ar"
  RANLIB="$prebuilt/bin/llvm-ranlib"
  STRIP="$prebuilt/bin/llvm-strip"
  NM="$prebuilt/bin/llvm-nm"
  FFMPEG_OS=android
  MESON_SYSTEM=android
  CMAKE_SYSTEM_NAME=Android
  CMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake"
  HOST_TRIPLE="$TRIPLE"
  export ANDROID_ABI="$ABI"
  export ANDROID_PLATFORM="android-$API"
  LDFLAGS_EXTRA+=(-Wl,-z,max-page-size=16384 -static-libstdc++)
  CFLAGS_EXTRA+=(-DANDROID)
}

_find_llvm_mingw() {
  if [[ -n "${LLVM_MINGW_HOME:-}" && -x "$LLVM_MINGW_HOME/bin/x86_64-w64-mingw32-clang" ]]; then
    printf '%s\n' "$LLVM_MINGW_HOME"
    return
  fi
  if command -v x86_64-w64-mingw32-clang >/dev/null 2>&1; then
    dirname "$(dirname "$(command -v x86_64-w64-mingw32-clang)")"
    return
  fi
  die "llvm-mingw not found. Set LLVM_MINGW_HOME or install x86_64-w64-mingw32-clang."
}

# Archive paths for llvm-mingw libc++. Do not use -lc++: meson --prefer-static
# resolves it to libc++.a while clang still injects libc++.dll.a.
_windows_libcxx_archives() {
  local root="$1" syslib=""
  if [[ -f "$root/$TRIPLE/lib/libc++.a" ]]; then
    syslib="$root/$TRIPLE/lib"
  elif [[ -f "$root/lib/libc++.a" ]]; then
    syslib="$root/lib"
  else
    die "llvm-mingw libc++.a not found under $root (tried $TRIPLE/lib and lib)"
  fi
  [[ -f "$syslib/libc++abi.a" ]] || die "llvm-mingw libc++abi.a not found in $syslib"
  local libs=("$syslib/libc++.a" "$syslib/libc++abi.a")
  [[ -f "$syslib/libunwind.a" ]] && libs+=("$syslib/libunwind.a")
  printf '%s' "-Wl,--start-group ${libs[*]} -Wl,--end-group"
}

_setup_windows() {
  local root
  root=$(_find_llvm_mingw)
  export PATH="$root/bin:$PATH"
  PKG_CONFIG=$(command -v pkg-config)

  case "$ARCH" in
    x86_64) TRIPLE=x86_64-w64-mingw32; CPU_FAMILY=x86_64; CPU=x86_64; FFMPEG_ARCH=x86_64 ;;
    x86)    TRIPLE=i686-w64-mingw32;   CPU_FAMILY=x86;    CPU=i686;   FFMPEG_ARCH=i686 ;;
    arm64)  TRIPLE=aarch64-w64-mingw32; CPU_FAMILY=aarch64; CPU=aarch64; FFMPEG_ARCH=aarch64 ;;
  esac

  local bindir="$root/bin"
  CC="$bindir/${TRIPLE}-clang"
  CXX="$bindir/${TRIPLE}-clang++"
  # Prefer llvm-* so CMake 3.31 does not rewrite a prefixed `*-ar` into a
  # cwd-relative path (it then looks for $PWD/x86_64-w64-mingw32-ar).
  AR="$bindir/llvm-ar"
  RANLIB="$bindir/llvm-ranlib"
  STRIP="$bindir/llvm-strip"
  NM="$bindir/llvm-nm"
  RC="$bindir/${TRIPLE}-windres"
  [[ -x "$RC" ]] || RC="$bindir/llvm-windres"
  [[ -x "$CC" && -x "$CXX" && -x "$AR" && -x "$RANLIB" && -x "$STRIP" && -x "$NM" ]] \
    || die "llvm-mingw tools missing in $bindir"
  [[ -x "$RC" ]] || RC=""
  FFMPEG_OS=mingw32
  MESON_SYSTEM=windows
  CMAKE_SYSTEM_NAME=Windows
  CMAKE_TOOLCHAIN_FILE=""
  HOST_TRIPLE="$TRIPLE"
  ABI="$ARCH"
  # clang/libc++; -static-libstdc++ is ignored. Keep libc++ out of LDFLAGS so
  # clang++ configure tests do not also pull libc++.dll.a.
  WINDOWS_LIBCXX_LIBS=$(_windows_libcxx_archives "$root")
  export WINDOWS_LIBCXX_LIBS
}

_xcode_app() {
  if [[ -n "${XCODE_PATH:-}" && -d "$XCODE_PATH" ]]; then
    printf '%s\n' "$XCODE_PATH"
    return
  fi
  if [[ -d /Applications/Xcode.app ]]; then
    printf '%s\n' /Applications/Xcode.app
    return
  fi
  local found
  found=$(ls -d /Applications/Xcode_*.app 2>/dev/null | sort -V | tail -n1 || true)
  [[ -n "$found" ]] && { printf '%s\n' "$found"; return; }
  die "Xcode.app not found. Set XCODE_PATH."
}

_setup_darwin() {
  need_cmd xcrun
  local xcode sdkname minflag
  xcode=$(_xcode_app)
  local toolchain="$xcode/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
  PKG_CONFIG=$(command -v pkg-config)

  case "$OS" in
    macos)
      sdkname=macosx
      minflag="-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET:-11.0}"
      CMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
      ;;
    ios)
      sdkname=iphoneos
      minflag="-miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET:-12.0}"
      CMAKE_OSX_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-12.0}"
      ;;
    iossimulator)
      sdkname=iphonesimulator
      minflag="-mios-simulator-version-min=${IPHONEOS_DEPLOYMENT_TARGET:-12.0}"
      CMAKE_OSX_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-12.0}"
      ;;
  esac

  local sdk
  sdk=$(xcrun --sdk "$sdkname" --show-sdk-path)
  CMAKE_OSX_SYSROOT="$sdk"

  case "$ARCH" in
    arm64)  CMAKE_OSX_ARCHITECTURES=arm64;  CPU_FAMILY=aarch64; CPU=arm64;  FFMPEG_ARCH=arm64; CLANG_ARCH=arm64 ;;
    x86_64) CMAKE_OSX_ARCHITECTURES=x86_64; CPU_FAMILY=x86_64;  CPU=x86_64; FFMPEG_ARCH=x86_64; CLANG_ARCH=x86_64 ;;
  esac

  CC="$toolchain/clang"
  CXX="$toolchain/clang++"
  AR="$toolchain/ar"
  RANLIB="$toolchain/ranlib"
  STRIP="$toolchain/strip"
  NM="$toolchain/nm"
  FFMPEG_OS=darwin
  MESON_SYSTEM=darwin
  CMAKE_SYSTEM_NAME=Darwin
  CMAKE_TOOLCHAIN_FILE=""
  ABI="$ARCH"
  TRIPLE=""
  case "$ARCH" in
    arm64) HOST_TRIPLE=aarch64-apple-darwin ;;
    x86_64) HOST_TRIPLE=x86_64-apple-darwin ;;
  esac
  CFLAGS_EXTRA+=(-arch "$CLANG_ARCH" -isysroot "$sdk" "$minflag")
  CXXFLAGS_EXTRA+=(-arch "$CLANG_ARCH" -isysroot "$sdk" "$minflag" -stdlib=libc++)
  LDFLAGS_EXTRA+=(-arch "$CLANG_ARCH" -isysroot "$sdk" "$minflag")
  # iconv lives in libiconv, not libSystem. Meson builtin links() needs -liconv.
  LDFLAGS_EXTRA+=(-liconv)
  export DEVELOPER_DIR="$xcode/Contents/Developer"

  # FFmpeg host-cc tests do not inherit --extra-cflags. The Xcode clang
  # binary will not find ctype.h without an SDK (unlike /usr/bin/clang).
  # Pin -target to macOS: IPHONEOS_DEPLOYMENT_TARGET (from versions.env)
  # makes Apple clang produce iOS binaries even with a MacOSX -isysroot,
  # and HOSTLD ops_asmgen then dies with SIGKILL on the runner.
  local host_sdk="$sdk"
  if [[ "$sdkname" != macosx ]]; then
    host_sdk=$(xcrun --sdk macosx --show-sdk-path)
  fi
  local host_cpu macos_min
  case "$(uname -m)" in
    arm64|aarch64) host_cpu=arm64 ;;
    *) host_cpu=x86_64 ;;
  esac
  macos_min="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
  HOST_CC="$toolchain/clang"
  HOST_CFLAGS="-isysroot $host_sdk -mmacosx-version-min=$macos_min -target ${host_cpu}-apple-macos${macos_min}"
  HOST_LDFLAGS="$HOST_CFLAGS"
  unset IPHONEOS_DEPLOYMENT_TARGET

  # Same-arch macOS is not a cross compile. A cross file without a build-machine
  # compiler makes fribidi gen.tab fail (meson 1.12: "No build machine compiler").
  if [[ "$OS" == macos ]]; then
    local runner=""
    case "$(uname -m)" in
      arm64|aarch64) runner=arm64 ;;
      x86_64) runner=x86_64 ;;
    esac
    if [[ -n "$runner" && "$ARCH" == "$runner" ]]; then
      NATIVE_BUILD=1
    fi
  fi
}

_write_meson_cross() {
  local dest c_args cpp_args c_link objc_args
  c_args=$(meson_array "${CFLAGS_EXTRA[@]}")
  cpp_args=$(meson_array "${CXXFLAGS_EXTRA[@]}")
  c_link=$(meson_array "${LDFLAGS_EXTRA[@]}")
  objc_args="$c_args"

  if [[ "${NATIVE_BUILD:-0}" == 1 ]]; then
    MESON_NATIVE="$TOOL_DIR/meson-native.ini"
    MESON_CROSS=""
    dest="$MESON_NATIVE"
  else
    MESON_CROSS="$TOOL_DIR/meson-cross.ini"
    MESON_NATIVE=""
    dest="$MESON_CROSS"
  fi

  {
    cat <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
objc = '$CC'
objcpp = '$CXX'
ar = '$AR'
nm = '$NM'
strip = '$STRIP'
ranlib = '$RANLIB'
pkg-config = '$PKG_CONFIG'
pkgconfig = '$PKG_CONFIG'

[built-in options]
c_args = $c_args
cpp_args = $cpp_args
objc_args = $objc_args
objcpp_args = $cpp_args
c_link_args = $c_link
cpp_link_args = $c_link
objc_link_args = $c_link
objcpp_link_args = $c_link
EOF
    if [[ "${NATIVE_BUILD:-0}" != 1 ]]; then
      cat <<EOF

[properties]
pkg_config_libdir = '$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig'
needs_exe_wrapper = true

[host_machine]
system = '$MESON_SYSTEM'
cpu_family = '$CPU_FAMILY'
cpu = '$CPU'
endian = 'little'
EOF
    fi
  } >"$dest"

  if [[ "${NATIVE_BUILD:-0}" != 1 ]]; then
    _write_meson_native_for_build
  fi
}

# Compilers that produce executables for the machine running meson (code
# generators such as fribidi gen.tab). Distinct from the host/cross toolchain.
_write_meson_native_for_build() {
  local cc cxx ar ranlib nm strip pc
  local native_c native_cpp native_objc native_objcpp
  if [[ "$(uname -s)" == Darwin ]]; then
    local xcode toolchain
    xcode=$(_xcode_app)
    toolchain="$xcode/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
    cc="${HOST_CC:-$toolchain/clang}"
    cxx="$toolchain/clang++"
    ar="$toolchain/ar"
    ranlib="$toolchain/ranlib"
    nm="$toolchain/nm"
    strip="$toolchain/strip"
    # Xcode toolchain clang does not find macOS headers without an SDK
    # (unlike /usr/bin/clang). Meson 1.12 then reports no build-machine C
    # compiler, and fribidi gen.tab fails on arm64→x86_64.
    local -a host_flags=()
    if [[ -n "${HOST_CFLAGS:-}" ]]; then
      # HOST_CFLAGS is space-separated; SDK paths have no spaces.
      # shellcheck disable=SC2206
      host_flags=(${HOST_CFLAGS})
    fi
    native_c=$(meson_array "$cc" "${host_flags[@]+"${host_flags[@]}"}")
    native_cpp=$(meson_array "$cxx" "${host_flags[@]+"${host_flags[@]}"}")
    native_objc="$native_c"
    native_objcpp="$native_cpp"
  else
    cc=$(command -v gcc || true)
    cxx=$(command -v g++ || true)
    if [[ -z "$cc" || -z "$cxx" ]]; then
      cc=$(command -v clang || true)
      cxx=$(command -v clang++ || true)
    fi
    [[ -n "$cc" && -n "$cxx" ]] || die "no C/C++ compiler for the Meson build machine"
    ar=$(command -v gcc-ar || command -v ar)
    ranlib=$(command -v gcc-ranlib || command -v ranlib)
    nm=$(command -v gcc-nm || command -v nm)
    strip=$(command -v strip)
    [[ -n "$ar" && -n "$ranlib" && -n "$nm" && -n "$strip" ]] || die "build-machine binutils not found"
    native_c="'$cc'"
    native_cpp="'$cxx'"
    native_objc="'$cc'"
    native_objcpp="'$cxx'"
  fi
  pc="${PKG_CONFIG:-$(command -v pkg-config)}"
  [[ -n "$pc" ]] || die "pkg-config not found for Meson native file"
  MESON_NATIVE="$TOOL_DIR/meson-native.ini"
  cat >"$MESON_NATIVE" <<EOF
[binaries]
c = $native_c
cpp = $native_cpp
objc = $native_objc
objcpp = $native_objcpp
ar = '$ar'
nm = '$nm'
strip = '$strip'
ranlib = '$ranlib'
pkg-config = '$pc'
pkgconfig = '$pc'
EOF
}

_write_cmake_toolchain() {
  if [[ "$OS" == android ]]; then
    export ANDROID_ABI ANDROID_PLATFORM
    export ANDROID_STL=c++_static
    return
  fi
  if [[ "${NATIVE_BUILD:-0}" == 1 ]]; then
    CMAKE_TOOLCHAIN_FILE=""
    return
  fi

  CMAKE_TOOLCHAIN_FILE="$TOOL_DIR/toolchain.cmake"
  local sysproc rc_line=""
  case "$OS-$ARCH" in
    windows-x86_64) sysproc=AMD64 ;;
    windows-x86) sysproc=x86 ;;
    windows-arm64) sysproc=ARM64 ;;
    *) sysproc="$CPU" ;;
  esac
  if [[ -n "${RC:-}" ]]; then
    rc_line="set(CMAKE_RC_COMPILER \"$RC\")"
  fi

  cat >"$CMAKE_TOOLCHAIN_FILE" <<EOF
# Generated by mpv-prebuild. Do not edit.
set(CMAKE_SYSTEM_NAME $CMAKE_SYSTEM_NAME)
set(CMAKE_SYSTEM_PROCESSOR $sysproc)
set(CMAKE_C_COMPILER "$CC")
set(CMAKE_CXX_COMPILER "$CXX")
$rc_line
set(CMAKE_AR "$AR" CACHE FILEPATH "Archiver" FORCE)
set(CMAKE_RANLIB "$RANLIB" CACHE FILEPATH "Ranlib" FORCE)
set(CMAKE_NM "$NM" CACHE FILEPATH "NM" FORCE)
set(CMAKE_STRIP "$STRIP" CACHE FILEPATH "Strip" FORCE)
set(CMAKE_C_COMPILER_AR "$AR" CACHE FILEPATH "" FORCE)
set(CMAKE_CXX_COMPILER_AR "$AR" CACHE FILEPATH "" FORCE)
set(CMAKE_C_COMPILER_RANLIB "$RANLIB" CACHE FILEPATH "" FORCE)
set(CMAKE_CXX_COMPILER_RANLIB "$RANLIB" CACHE FILEPATH "" FORCE)
set(CMAKE_FIND_ROOT_PATH "$PREFIX")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
  CMAKE_AR CMAKE_RANLIB CMAKE_NM CMAKE_STRIP
  CMAKE_C_COMPILER_AR CMAKE_CXX_COMPILER_AR
  CMAKE_C_COMPILER_RANLIB CMAKE_CXX_COMPILER_RANLIB)
EOF
  if [[ -n "${CMAKE_OSX_SYSROOT:-}" ]]; then
    {
      echo "set(CMAKE_OSX_SYSROOT \"$CMAKE_OSX_SYSROOT\")"
      echo "set(CMAKE_OSX_ARCHITECTURES \"$CMAKE_OSX_ARCHITECTURES\")"
      echo "set(CMAKE_OSX_DEPLOYMENT_TARGET \"$CMAKE_OSX_DEPLOYMENT_TARGET\")"
    } >>"$CMAKE_TOOLCHAIN_FILE"
  fi
}
