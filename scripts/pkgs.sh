#!/usr/bin/env bash
# Build a single dependency. Each function is idempotent via stamp files.

build_zlib() {
  is_stamped zlib && { log "skip zlib"; return; }
  log "building zlib"
  run_cmake "$SRC_DIR/zlib" \
    -DZLIB_BUILD_SHARED=OFF \
    -DZLIB_BUILD_STATIC=ON \
    -DZLIB_BUILD_TESTING=OFF
  # zlib 1.3.2 names the MinGW/Windows static lib libzs.a; FFmpeg still wants -lz.
  if [[ -f "$PREFIX/lib/libzs.a" && ! -e "$PREFIX/lib/libz.a" ]]; then
    cp -a "$PREFIX/lib/libzs.a" "$PREFIX/lib/libz.a"
  fi
  stamp zlib
}

build_mbedtls() {
  is_stamped mbedtls && { log "skip mbedtls"; return; }
  log "building mbedtls"
  # Official release tarball (not the GitHub source archive) includes the
  # mbedtls-framework submodule required by 3.6.
  run_cmake "$SRC_DIR/mbedtls" \
    -DENABLE_PROGRAMS=OFF \
    -DENABLE_TESTING=OFF \
    -DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
    -DUSE_STATIC_MBEDTLS_LIBRARY=ON \
    -DGEN_FILES=OFF
  write_pc mbedtls "$MBEDTLS_VERSION" "-lmbedtls -lmbedx509 -lmbedcrypto"
  write_pc mbedx509 "$MBEDTLS_VERSION" "-lmbedx509 -lmbedcrypto"
  write_pc mbedcrypto "$MBEDTLS_VERSION" "-lmbedcrypto"
  stamp mbedtls
}

build_dav1d() {
  is_stamped dav1d && { log "skip dav1d"; return; }
  log "building dav1d"
  local bdir="$WORK_DIR/build/$TARGET_ID/dav1d"
  rm -rf "$bdir"
  run_meson "$bdir" "$SRC_DIR/dav1d" \
    -Ddefault_library=static \
    -Denable_tools=false \
    -Denable_tests=false
  stamp dav1d
}

build_libxml2() {
  is_stamped libxml2 && { log "skip libxml2"; return; }
  log "building libxml2"
  run_cmake "$SRC_DIR/libxml2" \
    -DLIBXML2_WITH_PYTHON=OFF \
    -DLIBXML2_WITH_LZMA=OFF \
    -DLIBXML2_WITH_ZLIB=ON \
    -DLIBXML2_WITH_ICONV=OFF \
    -DLIBXML2_WITH_ICU=OFF \
    -DLIBXML2_WITH_TESTS=OFF \
    -DLIBXML2_WITH_PROGRAMS=OFF \
    -DLIBXML2_WITH_HTTP=OFF \
    -DLIBXML2_WITH_FTP=OFF \
    -DLIBXML2_WITH_CATALOG=OFF \
    -DLIBXML2_WITH_DEBUG=OFF
  stamp libxml2
}

build_libpng() {
  is_stamped libpng && { log "skip libpng"; return; }
  log "building libpng"
  run_cmake "$SRC_DIR/libpng" \
    -DPNG_SHARED=OFF \
    -DPNG_STATIC=ON \
    -DPNG_TESTS=OFF \
    -DPNG_TOOLS=OFF \
    -DZLIB_ROOT="$PREFIX"
  # Static libpng calls pow(); consumers need -lm (cmake .pc sometimes omits it).
  local pc
  for pc in "$PREFIX/lib/pkgconfig/libpng.pc" "$PREFIX/lib/pkgconfig/libpng16.pc"; do
    [[ -f "$pc" ]] || continue
    grep -q -- '-lm' "$pc" && continue
    if grep -q '^Libs.private:' "$pc"; then
      local tmp="$pc.tmp.$$"
      while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == Libs.private:* ]]; then
          printf '%s -lm\n' "$line"
        else
          printf '%s\n' "$line"
        fi
      done < "$pc" > "$tmp"
      mv "$tmp" "$pc"
    else
      printf 'Libs.private: -lm\n' >> "$pc"
    fi
  done
  stamp libpng
}

build_freetype() {
  is_stamped freetype && { log "skip freetype"; return; }
  log "building freetype"
  local bdir="$WORK_DIR/build/$TARGET_ID/freetype"
  rm -rf "$bdir"
  run_meson "$bdir" "$SRC_DIR/freetype" \
    -Ddefault_library=static \
    -Dharfbuzz=disabled \
    -Dbrotli=disabled \
    -Dbzip2=disabled \
    -Dpng=enabled \
    -Dzlib=enabled \
    -Dtests=disabled
  stamp freetype
}

build_harfbuzz() {
  is_stamped harfbuzz && { log "skip harfbuzz"; return; }
  log "building harfbuzz"
  local bdir="$WORK_DIR/build/$TARGET_ID/harfbuzz"
  rm -rf "$bdir"
  run_meson "$bdir" "$SRC_DIR/harfbuzz" \
    -Ddefault_library=static \
    -Dtests=disabled \
    -Ddocs=disabled \
    -Dutilities=disabled \
    -Dglib=disabled \
    -Dgobject=disabled \
    -Dcairo=disabled \
    -Dchafa=disabled \
    -Dicu=disabled \
    -Dfreetype=enabled
  stamp harfbuzz
}

build_fribidi() {
  is_stamped fribidi && { log "skip fribidi"; return; }
  log "building fribidi"
  local bdir="$WORK_DIR/build/$TARGET_ID/fribidi"
  rm -rf "$bdir"
  run_meson "$bdir" "$SRC_DIR/fribidi" \
    -Ddefault_library=static \
    -Ddocs=false \
    -Dbin=false \
    -Dtests=false
  stamp fribidi
}

build_libass() {
  is_stamped libass && { log "skip libass"; return; }
  log "building libass"
  local bdir="$WORK_DIR/build/$TARGET_ID/libass"
  rm -rf "$bdir"
  local coretext=disabled directwrite=disabled
  case "$OS" in
    macos|ios|iossimulator) coretext=enabled ;;
    windows) directwrite=enabled ;;
  esac
  run_meson "$bdir" "$SRC_DIR/libass" \
    -Dasm=disabled \
    -Dtest=disabled \
    -Dprofile=disabled \
    -Dfontconfig=disabled \
    -Ddirectwrite="$directwrite" \
    -Dcoretext="$coretext" \
    -Drequire-system-font-provider=false
  stamp libass
}

build_uchardet() {
  is_stamped uchardet && { log "skip uchardet"; return; }
  log "building uchardet"
  run_cmake "$SRC_DIR/uchardet" \
    -DBUILD_BINARY=OFF \
    -DBUILD_SHARED_LIBS=OFF
  stamp uchardet
}

# glibc / libSystem already provide iconv. MinGW and Bionic do not.
build_libiconv() {
  case "$OS" in
    windows|android) ;;
    *) return 0 ;;
  esac
  is_stamped libiconv && {
    log "skip libiconv"
    _meson_link_iconv
    return
  }
  log "building libiconv"
  local bdir="$WORK_DIR/build/$TARGET_ID/libiconv"
  rm -rf "$bdir"
  ensure_dir "$bdir"
  local cfg=(
    --prefix="$PREFIX"
    --libdir="$PREFIX/lib"
    --includedir="$PREFIX/include"
    --host="$HOST_TRIPLE"
    --enable-static
    --disable-shared
    --disable-nls
    --enable-extra-encodings
  )
  (
    cd "$bdir"
    CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP" NM="$NM" \
      CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
      "$SRC_DIR/libiconv/configure" "${cfg[@]}"
    make -j"$JOBS"
    make install
  )
  if [[ -f "$PREFIX/lib64/libiconv.a" && ! -f "$PREFIX/lib/libiconv.a" ]]; then
    ensure_dir "$PREFIX/lib"
    cp -a "$PREFIX/lib64/libiconv.a" "$PREFIX/lib/libiconv.a"
    [[ -f "$PREFIX/lib64/libcharset.a" ]] && cp -a "$PREFIX/lib64/libcharset.a" "$PREFIX/lib/libcharset.a"
  fi
  [[ -f "$PREFIX/lib/libiconv.a" ]] || die "libiconv.a missing after install (need GNU libiconv on $OS)"
  [[ -f "$PREFIX/include/iconv.h" ]] || die "iconv.h missing after install"
  local libs="-liconv"
  [[ -f "$PREFIX/lib/libcharset.a" ]] && libs="-liconv -lcharset"
  write_pc iconv "$LIBICONV_VERSION" "$libs"
  _meson_link_iconv
  stamp libiconv
}

# Meson dependency('iconv') only tries libc then find_library (not pkg-config).
# find_library does not search -L from c_link_args; it uses compiler default dirs.
_meson_link_iconv() {
  case "$OS" in
    windows|android) ;;
    *) return 0 ;;
  esac
  local x already=0
  for x in "${LDFLAGS_EXTRA[@]+"${LDFLAGS_EXTRA[@]}"}"; do
    [[ "$x" == -liconv ]] && already=1
  done
  if [[ "$already" -eq 0 ]]; then
    LDFLAGS_EXTRA+=(-liconv)
    [[ -f "$PREFIX/lib/libcharset.a" ]] && LDFLAGS_EXTRA+=(-lcharset)
    export LDFLAGS="${LDFLAGS_EXTRA[*]}"
  fi
  # MinGW find_library often looks for the import-lib name first.
  if [[ "$OS" == windows && -f "$PREFIX/lib/libiconv.a" && ! -e "$PREFIX/lib/libiconv.dll.a" ]]; then
    cp -a "$PREFIX/lib/libiconv.a" "$PREFIX/lib/libiconv.dll.a"
  fi
  _write_meson_cross
}

# mpv 0.41 ignores iconv.pc. Restore the tarball meson.build, then:
# - MinGW/Bionic: GNU libiconv in PREFIX/lib
# - Apple: SDK libiconv is shared/.tbd; --prefer-static must not require .a
_mpv_iconv_meson() {
  local f="$SRC_DIR/mpv/meson.build"
  local orig="$SRC_DIR/mpv/meson.build.prebuild-orig"
  [[ -f "$f" ]] || die "missing $f"
  [[ -f "$orig" ]] || cp "$f" "$orig"
  cp "$orig" "$f"
  local mode="" libdir="$PREFIX/lib"
  case "$OS" in
    windows|android) mode=prefix ;;
    macos|ios|iossimulator) mode=apple ;;
    *) return 0 ;;
  esac
  python3 -c '
from pathlib import Path
import sys
path, mode, libdir = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
old = "iconv = dependency('\''iconv'\'', required: get_option('\''iconv'\''))"
if mode == "prefix":
    lookup = (
        f"    iconv = cc.find_library('\''iconv'\'', dirs: ['\''{libdir}'\''], "
        "required: get_option('\''iconv'\''))\n"
    )
else:
    lookup = (
        "    iconv = cc.find_library('\''iconv'\'', static: false, "
        "required: get_option('\''iconv'\''))\n"
    )
new = (
    "iconv = dependency('\''iconv'\'', required: false)\n"
    "if not iconv.found()\n"
    + lookup +
    "endif"
)
if old not in text:
    sys.exit("mpv meson.build iconv lookup changed; cannot inject find_library")
path.write_text(text.replace(old, new, 1))
' "$f" "$mode" "$libdir"
}

build_x264() {
  is_stamped x264 && { log "skip x264"; return; }
  log "building x264"
  local bdir="$WORK_DIR/build/$TARGET_ID/x264"
  rm -rf "$bdir"
  ensure_dir "$bdir"

  local cfg=(
    --prefix="$PREFIX"
    --host="$HOST_TRIPLE"
    --enable-static
    --disable-shared
    --disable-cli
    --enable-pic
    --disable-opencl
    --extra-cflags="$CFLAGS"
    --extra-ldflags="$LDFLAGS"
  )
  case "$OS-$ARCH" in
    android-armv7|android-x86|ios-*|iossimulator-*) cfg+=(--disable-asm) ;;
  esac

  (
    cd "$bdir"
    CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP" NM="$NM" \
      "$SRC_DIR/x264/configure" "${cfg[@]}"
    make -j"$JOBS"
    make install
  )
  stamp x264
}

build_ffmpeg() {
  is_stamped ffmpeg && { log "skip ffmpeg"; return; }
  log "building ffmpeg"
  local bdir="$WORK_DIR/build/$TARGET_ID/ffmpeg"
  rm -rf "$bdir"
  ensure_dir "$bdir"

  local cfg=(
    --prefix="$PREFIX"
    --pkg-config-flags=--static
    --extra-cflags="$CFLAGS -I$PREFIX/include"
    --extra-ldflags="$LDFLAGS -L$PREFIX/lib"
    --enable-static
    --disable-shared
    --enable-pic
    --disable-debug
    --disable-doc
    --disable-htmlpages
    --disable-manpages
    --disable-podpages
    --disable-txtpages
    --disable-programs
    --disable-autodetect
    --enable-avcodec
    --enable-avformat
    --enable-avfilter
    --enable-avutil
    --enable-swscale
    --enable-swresample
    --disable-avdevice
    --enable-network
    --enable-mbedtls
    --enable-libdav1d
    --enable-libxml2
    --cc="$CC"
    --cxx="$CXX"
    --ar="$AR"
    --nm="$NM"
    --ranlib="$RANLIB"
    --strip="$STRIP"
    --pkg-config="${PKG_CONFIG:-pkg-config}"
    --arch="$FFMPEG_ARCH"
    --target-os="$FFMPEG_OS"
  )
  if [[ -n "${HOST_CC:-}" ]]; then
    cfg+=(--host-cc="$HOST_CC" --host-ld="$HOST_CC")
  fi
  if [[ -n "${HOST_CFLAGS:-}" ]]; then
    cfg+=(--host-cflags="$HOST_CFLAGS")
  fi
  if [[ -n "${HOST_LDFLAGS:-}" ]]; then
    cfg+=(--host-ldflags="$HOST_LDFLAGS")
  fi

  if is_gpl; then
    cfg+=(
      --enable-gpl
      --enable-version3
      --enable-libx264
    )
  else
    cfg+=(
      --disable-gpl
      --disable-nonfree
      --enable-version3
    )
  fi

  if [[ "${NATIVE_BUILD:-0}" == 1 ]]; then
    :
  elif [[ "$OS" != macos ]]; then
    cfg+=(--enable-cross-compile)
  elif [[ "$ARCH" != "$(uname -m | sed 's/aarch64/arm64/')" ]]; then
    cfg+=(--enable-cross-compile)
  fi
  if [[ "$OS" == windows && -n "${TRIPLE:-}" ]]; then
    cfg+=(--cross-prefix="${TRIPLE}-")
  fi

  case "$OS" in
    android)
      cfg+=(
        --enable-jni
        --enable-mediacodec
        --enable-hwaccels
        --enable-vulkan
        --disable-xlib
      )
      [[ "$ARCH" == armv7 || "$ARCH" == arm64 ]] && cfg+=(--enable-neon)
      [[ "$ARCH" == x86 ]] && cfg+=(--disable-asm)
      ;;
    windows)
      cfg+=(
        --enable-d3d11va
        --enable-dxva2
        --enable-hwaccels
        --enable-vulkan
        --extra-libs='-lws2_32 -lbcrypt -lcrypt32'
      )
      ;;
    macos|ios|iossimulator)
      cfg+=(
        --enable-videotoolbox
        --enable-audiotoolbox
        --enable-hwaccels
        --enable-vulkan
        --as="$WORK_DIR/bin/gas-preprocessor.pl -arch ${CLANG_ARCH:-$ARCH} -- $CC"
      )
      export PATH="$WORK_DIR/bin:$PATH"
      ;;
    linux)
      cfg+=(
        --enable-vaapi
        --enable-vdpau
        --enable-libdrm
        --enable-hwaccels
        --enable-vulkan
        --disable-xlib
        --disable-libxcb
        --extra-libs='-lm -lpthread -ldl'
      )
      ;;
  esac

  (
    cd "$bdir"
    # Must not leak iOS targeting into HOSTCC/HOSTLD (swscale ops_asmgen).
    unset IPHONEOS_DEPLOYMENT_TARGET SDKROOT
    "$SRC_DIR/ffmpeg/configure" "${cfg[@]}"
    make -j"$JOBS"
    make install
  )
  stamp ffmpeg
}

linux_pkg_atleast() {
  local mod="$1" ver="$2"
  pkg-config --exists "$mod" && pkg-config --atleast-version="$ver" "$mod"
}

# mpv 0.41: wayland-client/cursor >= 1.21, wayland-protocols >= 1.31.
linux_system_wayland_ok() {
  linux_pkg_atleast wayland-client 1.21.0 \
    && linux_pkg_atleast wayland-cursor 1.21.0 \
    && linux_pkg_atleast wayland-protocols 1.31 \
    && command -v wayland-scanner >/dev/null
}

build_libdisplay_info() {
  [[ "$OS" == linux ]] || return 0
  is_stamped libdisplay-info && { log "skip libdisplay-info"; return; }
  # pnp.ids is compiled into the library; jammy has no hwdata.pc, meson falls
  # back to this path.
  [[ -f /usr/share/hwdata/pnp.ids ]] \
    || die "hwdata pnp.ids missing (apt: hwdata); required to build libdisplay-info for mpv DRM"
  log "building libdisplay-info"
  local bdir="$WORK_DIR/build/$TARGET_ID/libdisplay-info"
  rm -rf "$bdir"
  run_meson "$bdir" "$SRC_DIR/libdisplay-info" -Ddefault_library=static
  stamp libdisplay-info
}

# Ubuntu 22.04 wayland 1.20 / protocols 1.25 are too old for mpv 0.41.
# 24.04 already satisfies the versions; use the distro packages there.
build_wayland() {
  [[ "$OS" == linux ]] || return 0
  is_stamped wayland && { log "skip wayland"; return; }
  if linux_system_wayland_ok; then
    log "using system wayland ($(pkg-config --modversion wayland-client)) and wayland-protocols ($(pkg-config --modversion wayland-protocols))"
    stamp wayland
    return
  fi
  pkg-config --exists libffi || die "libffi is required to build wayland (apt: libffi-dev)"

  log "building wayland-protocols (distro too old for mpv 0.41)"
  local pdir="$WORK_DIR/build/$TARGET_ID/wayland-protocols"
  rm -rf "$pdir"
  run_meson "$pdir" "$SRC_DIR/wayland-protocols" -Ddefault_library=static -Dtests=false

  log "building wayland"
  local bdir="$WORK_DIR/build/$TARGET_ID/wayland"
  rm -rf "$bdir"
  run_meson "$bdir" "$SRC_DIR/wayland" \
    -Ddefault_library=static \
    -Ddocumentation=false \
    -Dtests=false \
    -Ddtd_validation=false
  stamp wayland
}

build_vulkan_headers() {
  is_stamped vulkan-headers && { log "skip vulkan-headers"; return; }
  log "installing vulkan-headers"
  run_cmake "$SRC_DIR/vulkan-headers"
  stamp vulkan-headers
}

# Vulkan-Loader hardcodes SHARED except APPLE_STATIC_LOADER. Force STATIC so
# libmpv does not DT_NEEDED vulkan-1.dll / libvulkan.so.1 (ICD still dlopen'd).
_force_static_vulkan_loader() {
  local cm="$SRC_DIR/vulkan-loader/loader/CMakeLists.txt"
  [[ -f "$cm" ]] || die "missing $cm"
  python3 - "$cm" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
t = p.read_text()
if "mpv-prebuild-static-loader" in t:
    sys.exit(0)
t2, n = re.subn(
    r"add_library\(\s*vulkan\s+SHARED\s+\$\{NORMAL_LOADER_SRCS\}\s+"
    r"\$\{CMAKE_CURRENT_SOURCE_DIR\}/\$\{API_TYPE\}-1\.def\s+"
    r"\$\{RC_FILE_LOCATION\}\s*\)",
    "add_library(vulkan STATIC ${NORMAL_LOADER_SRCS}) # mpv-prebuild-static-loader",
    t,
    count=1,
)
t2 = t2.replace(
    "add_library(vulkan SHARED)",
    "add_library(vulkan STATIC) # mpv-prebuild-static-loader",
)
if re.search(r"add_library\(\s*vulkan\s+SHARED", t2):
    sys.exit("Vulkan-Loader vulkan target is still SHARED")
if t2 == t:
    sys.exit("failed to patch Vulkan-Loader for a static library")
p.write_text(t2)
PY
}

build_vulkan_loader() {
  is_stamped vulkan-loader && { log "skip vulkan-loader"; return; }
  log "building vulkan-loader"
  need_cmd python3

  local pc_libs="-lvulkan"
  case "$OS" in
    android)
      local ndk vlib
      ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-${NDK:-}}}"
      [[ -n "$ndk" && -d "$ndk" ]] || die "Android NDK not found (need libvulkan.so)"
      vlib=$(find "$ndk" -path "*/sysroot/usr/lib/${TRIPLE}/*/libvulkan.so" 2>/dev/null | sort -V | tail -n1 || true)
      [[ -n "$vlib" && -f "$vlib" ]] || die "NDK libvulkan.so not found for $TRIPLE"
      cp -a "$vlib" "$PREFIX/lib/libvulkan.so"
      write_pc vulkan "$VULKAN_LOADER_VERSION" "-lvulkan"
      stamp vulkan-loader
      return
      ;;
    windows)
      pc_libs="-lvulkan -lcfgmgr32"
      ;;
    macos|ios|iossimulator)
      pc_libs="-lvulkan -lpthread -lm -framework CoreFoundation"
      ;;
    linux)
      pc_libs="-lvulkan -ldl -lpthread -lm"
      ;;
  esac

  _force_static_vulkan_loader
  local cmake_opts=(
    -DBUILD_TESTS=OFF
    -DENABLE_WERROR=OFF
    -DUSE_GAS=OFF
    -DUSE_MASM=OFF
    -DLOADER_CODEGEN=OFF
    -DVULKAN_HEADERS_INSTALL_DIR="$PREFIX"
  )
  case "$OS" in
    macos|ios|iossimulator) cmake_opts+=(-DAPPLE_STATIC_LOADER=ON) ;;
    linux)
      cmake_opts+=(
        -DBUILD_WSI_XCB_SUPPORT=ON
        -DBUILD_WSI_XLIB_SUPPORT=ON
        -DBUILD_WSI_WAYLAND_SUPPORT=ON
        -DBUILD_WSI_DIRECTFB_SUPPORT=OFF
      )
      ;;
  esac

  CMAKE_BUILD_TARGET=vulkan CMAKE_SKIP_INSTALL=1 \
    run_cmake "$SRC_DIR/vulkan-loader" "${cmake_opts[@]}"

  local bdir="$WORK_DIR/build/$TARGET_ID/vulkan-loader"
  local lib
  lib=$(find "$bdir" \( -name 'libvulkan.a' -o -name 'libvulkan-1.a' \) | head -n1 || true)
  [[ -n "$lib" && -f "$lib" ]] || die "static libvulkan was not built"
  cp -a "$lib" "$PREFIX/lib/libvulkan.a"
  write_pc vulkan "$VULKAN_LOADER_VERSION" "$pc_libs"
  stamp vulkan-loader
}

build_xxhash() {
  is_stamped xxhash && { log "skip xxhash"; return; }
  log "building xxhash"
  CMAKE_BUILD_NAME=xxhash run_cmake "$SRC_DIR/xxhash/cmake_unofficial" \
    -DXXHASH_BUILD_XXHSUM=OFF \
    -DXXHASH_BUILD_ENABLE_INLINE_API=ON \
    -DDISPATCH=OFF
  # libplacebo looks up pkg-config name libxxhash (headers are inlined at compile).
  write_pc libxxhash "$XXHASH_VERSION" "-lxxhash"
  stamp xxhash
}

build_lcms2() {
  is_stamped lcms2 && { log "skip lcms2"; return; }
  log "building lcms2"
  local bdir="$WORK_DIR/build/$TARGET_ID/lcms2"
  rm -rf "$bdir"
  # fastfloat/threaded plugins are GPL-3; keep MIT core only.
  run_meson "$bdir" "$SRC_DIR/lcms2" \
    -Ddefault_library=static \
    -Dutils=false \
    -Dtests=disabled \
    -Djpeg=disabled \
    -Dtiff=disabled \
    -Dfastfloat=false \
    -Dthreaded=false
  stamp lcms2
}

build_libdovi() {
  is_stamped libdovi && { log "skip libdovi"; return; }
  log "building libdovi"
  ensure_rust
  cargo_target_env
  local rt src saved_ios=0
  rt=$(rust_triple)
  src="$SRC_DIR/libdovi/dolby_vision"
  [[ -f "$src/Cargo.toml" ]] || die "missing $src/Cargo.toml"

  # Do not leak IPHONEOS_DEPLOYMENT_TARGET into FFmpeg HOSTCC (ops_asmgen).
  if [[ "$OS" == ios || "$OS" == iossimulator ]]; then
    export IPHONEOS_DEPLOYMENT_TARGET="${CMAKE_OSX_DEPLOYMENT_TARGET:-12.0}"
    export SDKROOT="${CMAKE_OSX_SYSROOT:-}"
    saved_ios=1
  fi

  (
    cd "$src"
    cargo cinstall --release --library-type staticlib \
      --prefix "$PREFIX" --libdir "$PREFIX/lib" \
      --target "$rt"
  )
  if [[ "$saved_ios" -eq 1 ]]; then
    unset IPHONEOS_DEPLOYMENT_TARGET
  fi
  [[ -f "$PREFIX/lib/pkgconfig/dovi.pc" ]] || die "libdovi did not install dovi.pc"
  stamp libdovi
}

build_spirv_cross() {
  [[ "$OS" == windows ]] || return 0
  is_stamped spirv-cross && { log "skip spirv-cross"; return; }
  log "building spirv-cross"
  run_cmake "$SRC_DIR/spirv-cross" \
    -DSPIRV_CROSS_CLI=OFF \
    -DSPIRV_CROSS_ENABLE_TESTS=OFF \
    -DSPIRV_CROSS_SHARED=OFF \
    -DSPIRV_CROSS_STATIC=ON \
    -DSPIRV_CROSS_ENABLE_C_API=ON \
    -DSPIRV_CROSS_ENABLE_CPP=ON \
    -DSPIRV_CROSS_ENABLE_GLSL=ON \
    -DSPIRV_CROSS_ENABLE_HLSL=ON \
    -DSPIRV_CROSS_ENABLE_MSL=ON \
    -DSPIRV_CROSS_ENABLE_REFLECT=ON \
    -DSPIRV_CROSS_ENABLE_UTIL=ON
  # Headers install to include/spirv_cross/; libplacebo includes <spirv_cross_c.h>.
  # -lc++: static C++ archives linked into C libplacebo (llvm-mingw libc++).
  write_pc spirv-cross-c-shared 0.67.0 \
    "-lspirv-cross-c -lspirv-cross-glsl -lspirv-cross-hlsl -lspirv-cross-msl -lspirv-cross-cpp -lspirv-cross-reflect -lspirv-cross-util -lspirv-cross-core -lc++" \
    '-I${includedir}/spirv_cross'
  stamp spirv-cross
}

build_shaderc() {
  is_stamped shaderc && { log "skip shaderc"; return; }
  log "building shaderc"
  need_cmd python3
  local py
  py=$(command -v python3)

  # shaderc_combined pulls glslang + SPIRV-Tools. CMAKE_SKIP_INSTALL_RULES:
  # otherwise glslang install(EXPORT) requires SPIRV-Tools-opt in an export set.
  CMAKE_SKIP_INSTALL=1 CMAKE_BUILD_TARGET=shaderc_combined \
    run_cmake "$SRC_DIR/shaderc" \
      -DCMAKE_SKIP_INSTALL_RULES=ON \
      -DSHADERC_SKIP_TESTS=ON \
      -DSHADERC_SKIP_EXAMPLES=ON \
      -DSHADERC_SKIP_EXECUTABLES=ON \
      -DSHADERC_SKIP_INSTALL=ON \
      -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
      -DSHADERC_ENABLE_WERROR_COMPILE=OFF \
      -DSHADERC_ENABLE_WGSL_OUTPUT=OFF \
      -DSPIRV_SKIP_EXECUTABLES=ON \
      -DSPIRV_SKIP_TESTS=ON \
      -DSPIRV_WERROR=OFF \
      -DENABLE_GLSLANG_BINARIES=OFF \
      -DENABLE_GLSLANG_INSTALL=OFF \
      -DGLSLANG_ENABLE_INSTALL=OFF \
      -DSKIP_GLSLANG_INSTALL=ON \
      -DSPIRV_TOOLS_BUILD_STATIC=ON \
      -DSPIRV_TOOLS_LIBRARY_TYPE=STATIC \
      -DPython_EXECUTABLE="$py" \
      -DPython3_EXECUTABLE="$py"

  local bdir="$WORK_DIR/build/$TARGET_ID/shaderc"
  local lib="$bdir/libshaderc/libshaderc_combined.a"
  if [[ ! -f "$lib" ]]; then
    lib=$(find "$bdir" -name 'libshaderc_combined.a' | head -n 1 || true)
  fi
  [[ -n "$lib" && -f "$lib" ]] || die "shaderc_combined was not built"
  cp -a "$lib" "$PREFIX/lib/libshaderc_combined.a"
  ensure_dir "$PREFIX/include/shaderc"
  cp -a "$SRC_DIR/shaderc/libshaderc/include/shaderc/." "$PREFIX/include/shaderc/"

  # Install the same glslang/SPIRV-Tools archives shaderc just built so
  # libplacebo -Dglslang can find_library them without a second compile.
  # shaderc.pc lists the pieces (not shaderc_combined) to avoid duplicate
  # symbols when both shaderc and glslang are linked into libmpv.
  _install_shaderc_glslang_libs "$bdir"

  local cxxlib=-lstdc++
  case "$OS" in
    linux) cxxlib=-lstdc++ ;;
    *) cxxlib=-lc++ ;;
  esac
  local pc_libs
  pc_libs="$(_shaderc_pc_libs) $cxxlib"
  write_pc shaderc "$SHADERC_VERSION" "$pc_libs"
  stamp shaderc
}

# Copy one libNAME.a from the shaderc build tree into PREFIX/lib.
_copy_shaderc_lib() {
  local bdir="$1" name="$2"
  local f
  f=$(find "$bdir" -name "lib${name}.a" | head -n1 || true)
  if [[ -n "$f" && -f "$f" ]]; then
    cp -a "$f" "$PREFIX/lib/lib${name}.a"
    return 0
  fi
  return 1
}

_install_shaderc_glslang_libs() {
  local bdir="$1"
  local gsrc="$SRC_DIR/shaderc/third_party/glslang"
  local name bi

  _copy_shaderc_lib "$bdir" shaderc || die "libshaderc.a was not built"
  _copy_shaderc_lib "$bdir" shaderc_util || die "libshaderc_util.a was not built"
  for name in \
      glslang-default-resource-limits glslang MachineIndependent GenericCodeGen \
      OSDependent OGLCompiler SPIRV SPVRemapper SPIRV-Tools-opt SPIRV-Tools
  do
    _copy_shaderc_lib "$bdir" "$name" || true
  done
  [[ -f "$PREFIX/lib/libglslang.a" ]] || die "libglslang.a was not built"
  [[ -f "$PREFIX/lib/libSPIRV.a" ]] || die "libSPIRV.a was not built"

  ensure_dir "$PREFIX/include/glslang"
  cp -a "$gsrc/glslang/Public" "$PREFIX/include/glslang/"
  cp -a "$gsrc/glslang/Include" "$PREFIX/include/glslang/"
  cp -a "$gsrc/SPIRV" "$PREFIX/include/glslang/SPIRV"
  bi=$(find "$bdir" -path '*glslang*' -name build_info.h | head -n1 || true)
  [[ -n "$bi" && -f "$bi" ]] || die "glslang build_info.h was not generated"
  cp -a "$bi" "$PREFIX/include/glslang/build_info.h"
}

_shaderc_pc_libs() {
  local name
  local libs="-lshaderc"
  [[ -f "$PREFIX/lib/libshaderc_util.a" ]] && libs="$libs -lshaderc_util"
  for name in \
      glslang-default-resource-limits glslang MachineIndependent GenericCodeGen \
      OSDependent OGLCompiler SPIRV SPVRemapper SPIRV-Tools-opt SPIRV-Tools
  do
    [[ -f "$PREFIX/lib/lib${name}.a" ]] && libs="$libs -l${name}"
  done
  printf '%s' "$libs"
}

build_libplacebo() {
  is_stamped libplacebo && { log "skip libplacebo"; return; }
  log "building libplacebo"
  need_cmd python3
  python3 -c 'import jinja2' >/dev/null 2>&1 \
    || die "Python Jinja2 is required to build libplacebo (apt: python3-jinja2 / pip: jinja2)"

  local bdir="$WORK_DIR/build/$TARGET_ID/libplacebo"
  rm -rf "$bdir"

  local opts=(
    -Ddefault_library=static
    -Ddemos=false
    -Dtests=false
    -Dvulkan=enabled
    -Dvk-proc-addr=enabled
    -Dshaderc=enabled
    -Dglslang=enabled
    -Dopengl=enabled
    -Dgl-proc-addr=enabled
    -Dlcms=enabled
    -Ddovi=enabled
    -Dlibdovi=enabled
    -Dxxhash=enabled
    -Dunwind=disabled
  )
  case "$OS" in
    windows) opts+=(-Dd3d11=enabled) ;;
    *) opts+=(-Dd3d11=disabled) ;;
  esac

  run_meson "$bdir" "$SRC_DIR/libplacebo" "${opts[@]}"
  stamp libplacebo
}

build_mpv() {
  is_stamped mpv && { log "skip mpv"; return; }
  log "building mpv"
  _mpv_iconv_meson
  local bdir="$WORK_DIR/build/$TARGET_ID/mpv"
  rm -rf "$bdir"

  local gpl_flag=false
  is_gpl && gpl_flag=true

  local opts=(
    -Ddefault_library=shared
    -Dgpl="$gpl_flag"
    -Dlibmpv=true
    -Dcplayer=false
    -Dbuild-date=true
    -Dtests=false
    -Dlua=disabled
    -Djavascript=disabled
    -Dlibarchive=disabled
    -Dlibbluray=disabled
    -Ddvdnav=disabled
    -Dcdda=disabled
    -Dvapoursynth=disabled
    -Dvulkan=enabled
    -Dshaderc=enabled
    -Dzimg=disabled
    -Dlcms2=enabled
    -Drubberband=disabled
    -Dsdl2-audio=disabled
    -Dsdl2-video=disabled
    -Dsdl2-gamepad=disabled
    -Dmanpage-build=disabled
    -Dhtml-build=disabled
    -Dpdf-build=disabled
    -Dcplugins=disabled
    -Duchardet=enabled
    -Diconv=enabled
    -Dgl=enabled
    -Dplain-gl=enabled
  )
  # Linux distro .a files (X11, jpeg, drm, …) are not built -fPIC and cannot
  # go into libmpv.so. PREFIX still has only static PIC archives.
  if [[ "$OS" != linux ]]; then
    opts+=(--prefer-static)
  fi

  case "$OS" in
    android)
      opts+=(
        -Degl=disabled
        -Degl-android=enabled
        -Dopensles=enabled
        -Dandroid-media-ndk=enabled
      )
      ;;
    windows)
      opts+=(
        -Dwasapi=enabled
        -Dshaderc=enabled
        -Dspirv-cross=enabled
        -Dd3d11=enabled
        -Dgl-win32=enabled
        -Degl-angle=disabled
      )
      ;;
    macos)
      local macos_min="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
      # clipboard-mac.m includes osdep/mac/swift.h from the Swift custom_target.
      # -target keeps the x86_64 slice of a universal build from compiling as arm64.
      opts+=(
        -Dcoreaudio=enabled
        -Dcocoa=enabled
        -Dgl-cocoa=enabled
        -Dvideotoolbox-gl=enabled
        -Dswift-build=enabled
        "-Dswift-flags=-target ${ARCH}-apple-macos${macos_min}"
        -Dmacos-cocoa-cb=disabled
        -Dmacos-media-player=disabled
        -Dmacos-touchbar=disabled
      )
      ;;
    ios|iossimulator)
      opts+=(
        -Daudiounit=enabled
        -Dios-gl=enabled
        -Dcocoa=disabled
        -Dswift-build=disabled
      )
      ;;
    linux)
      local pipewire=disabled
      if linux_pkg_atleast libpipewire-0.3 0.3.57; then
        pipewire=enabled
      else
        log "disabling pipewire: need libpipewire-0.3 >= 0.3.57 (have $(pkg-config --modversion libpipewire-0.3 2>/dev/null || echo none)); Pulse/ALSA still work"
      fi
      # X11, VDPAU, and JACK are GPL-only in mpv 0.41; forcing them on lgpl fails meson.
      opts+=(
        -Degl=enabled
        -Degl-wayland=enabled
        -Degl-drm=enabled
        -Dwayland=enabled
        -Ddrm=enabled
        -Dgbm=enabled
        -Dvaapi=enabled
        -Dvaapi-wayland=enabled
        -Dvaapi-drm=enabled
        -Dalsa=enabled
        -Dpulse=enabled
        -Dpipewire="$pipewire"
        -Dsndio=enabled
      )
      if is_gpl; then
        opts+=(
          -Dx11=enabled
          -Dgl-x11=enabled
          -Degl-x11=enabled
          -Dvaapi-x11=enabled
          -Dvdpau=enabled
          -Djack=enabled
        )
      else
        opts+=(
          -Dx11=disabled
          -Dgl-x11=disabled
          -Degl-x11=disabled
          -Dvaapi-x11=disabled
          -Dvdpau=disabled
          -Djack=disabled
        )
      fi
      ;;
  esac

  if [[ "$OS" == windows ]]; then
    opts+=(-Dspirv-cross=enabled)
  else
    opts+=(-Dspirv-cross=disabled)
  fi

  run_meson "$bdir" "$SRC_DIR/mpv" "${opts[@]}"
  stamp mpv
}

build_deps() {
  build_zlib
  build_mbedtls
  build_dav1d
  build_libxml2
  build_libpng
  build_freetype
  build_harfbuzz
  build_fribidi
  build_libass
  build_libiconv
  build_uchardet
  build_vulkan_headers
  build_vulkan_loader
  build_xxhash
  build_lcms2
  build_libdovi
  build_spirv_cross
  build_shaderc
  build_libplacebo
  build_libdisplay_info
  build_wayland
  if is_gpl; then
    build_x264
  fi
  build_ffmpeg
  build_mpv
}
