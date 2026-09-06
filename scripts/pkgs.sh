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
  is_stamped libiconv && { log "skip libiconv"; return; }
  log "building libiconv"
  local bdir="$WORK_DIR/build/$TARGET_ID/libiconv"
  rm -rf "$bdir"
  ensure_dir "$bdir"
  local cfg=(
    --prefix="$PREFIX"
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
  local libs="-liconv"
  [[ -f "$PREFIX/lib/libcharset.a" ]] && libs="-liconv -lcharset"
  write_pc iconv "$LIBICONV_VERSION" "$libs"
  stamp libiconv
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
    cfg+=(--host-cc="$HOST_CC")
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
        --disable-vulkan
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
        --disable-vulkan
        --extra-libs='-lws2_32 -lbcrypt -lcrypt32'
      )
      ;;
    macos|ios|iossimulator)
      cfg+=(
        --enable-videotoolbox
        --enable-audiotoolbox
        --enable-hwaccels
        --disable-vulkan
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
        --disable-vulkan
        --disable-xlib
        --disable-libxcb
        --extra-libs='-lm -lpthread -ldl'
      )
      ;;
  esac

  (
    cd "$bdir"
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
    -Dvulkan=disabled
    -Dvk-proc-addr=disabled
    -Dshaderc=disabled
    -Dglslang=disabled
    -Dopengl=enabled
    -Dgl-proc-addr=enabled
    -Dlcms=disabled
    -Dlibdovi=disabled
    -Dxxhash=disabled
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
  local bdir="$WORK_DIR/build/$TARGET_ID/mpv"
  rm -rf "$bdir"

  local gpl_flag=false
  is_gpl && gpl_flag=true

  local opts=(
    -Ddefault_library=shared
    --prefer-static
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
    -Dvulkan=disabled
    -Dshaderc=disabled
    -Dspirv-cross=disabled
    -Dzimg=disabled
    -Dlcms2=disabled
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

  case "$OS" in
    android)
      opts+=(
        -Degl=enabled
        -Degl-android=enabled
        -Dopensles=enabled
        -Dandroid-media-ndk=enabled
      )
      ;;
    windows)
      opts+=(
        -Dwasapi=enabled
        -Dd3d11=enabled
        -Dgl-win32=enabled
        -Degl-angle=disabled
      )
      ;;
    macos)
      opts+=(
        -Dcoreaudio=enabled
        -Dcocoa=enabled
        -Dgl-cocoa=enabled
        -Dvideotoolbox-gl=enabled
        -Dswift-build=disabled
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
  build_spirv_cross
  build_libplacebo
  build_libdisplay_info
  build_wayland
  if is_gpl; then
    build_x264
  fi
  build_ffmpeg
  build_mpv
}
