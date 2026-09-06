#!/usr/bin/env bash
# Assemble a consumable libmpv SDK from a finished prefix.

# Follow soname symlinks (libmpv.so -> libmpv.so.2 -> libmpv.so.2.x) and write a regular file.
copy_real_libmpv_so() {
  local src="$1" dest="$2"
  [[ -e "$src" ]] || die "libmpv shared library not found: $src"
  ensure_dir "$(dirname "$dest")"
  cp -L "$src" "$dest"
  [[ -f "$dest" && ! -L "$dest" ]] || die "failed to materialize $dest from $src"
}

# glibc and the dynamic linker must come from the host; everything else can travel with libmpv.
is_host_libc_dep() {
  local n="$1"
  case "$n" in
    linux-vdso.so*|ld-linux*|ld64.so*|ld-lsb*|libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|libresolv.so*|libutil.so*|libnsl.so*|libnss_*.so*|libthread_db.so*|libanl.so*|libmvec.so*|libcrypt.so*)
      return 0 ;;
  esac
  return 1
}

# Copy libmpv's non-glibc DT_NEEDED tree into dest_lib and point RUNPATH at $ORIGIN.
bundle_linux_shared_deps() {
  local dest_lib="$1" start="$2"
  need_cmd ldd
  need_cmd patchelf
  [[ -e "$start" ]] || die "bundle_linux_shared_deps: missing $start"

  local -A seen=()
  local -a pending=("$start")
  local -a copied_list=()
  local cur line name path

  while ((${#pending[@]} > 0)); do
    cur="${pending[0]}"
    pending=("${pending[@]:1}")
    [[ -e "$cur" ]] || continue

    while IFS= read -r line; do
      [[ "$line" == *' => not found'* ]] && continue
      [[ "$line" == *linux-vdso* ]] && continue
      if [[ "$line" =~ ([^[:space:]]+)[[:space:]]+=\>[[:space:]]+(/[^[:space:]]+) ]]; then
        name="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
      else
        continue
      fi
      is_host_libc_dep "$name" && continue
      case "$name" in
        libmpv.so*) continue ;;
      esac
      [[ -n "${seen[$name]:-}" ]] && continue
      seen[$name]=1
      [[ -e "$path" ]] || continue
      cp -L "$path" "$dest_lib/$name"
      copied_list+=("$name")
      pending+=("$dest_lib/$name")
    done < <(ldd "$cur" 2>/dev/null || true)
  done

  local f
  while IFS= read -r -d '' f; do
    patchelf --set-rpath '$ORIGIN' "$f" || die "patchelf failed on $f"
  done < <(find "$dest_lib" -maxdepth 1 -type f \( -name '*.so' -o -name '*.so.*' \) -print0)

  if ((${#copied_list[@]} > 0)); then
    printf '%s\n' "${copied_list[@]}" | sort -u >"$dest_lib/bundled-libraries.txt"
    log "bundled ${#copied_list[@]} Linux shared libraries into $dest_lib"
  else
    die "no Linux shared-library dependencies were bundled (ldd produced nothing usable)"
  fi
}

package_target() {
  local version="$1"
  local out_name="libmpv-${OS}-${ARCH}-${FLAVOR}-${version}"
  local dest="$DIST_DIR/$out_name"
  rm -rf "$dest"
  ensure_dir "$dest/include/mpv" "$dest/lib" "$dest/licenses"

  cp -a "$PREFIX/include/mpv/"*.h "$dest/include/mpv/"

  local copied=0
  if [[ "$OS" == android ]]; then
    # jniLibs and System.loadLibrary("mpv") need a regular libmpv.so, not a soname symlink.
    copy_real_libmpv_so "$PREFIX/lib/libmpv.so" "$dest/lib/libmpv.so"
    copied=1
  else
    local f
    for f in \
        "$PREFIX/lib/libmpv.so" \
        "$PREFIX/lib/libmpv.so."* \
        "$PREFIX/bin/libmpv-2.dll" \
        "$PREFIX/lib/libmpv-2.dll" \
        "$PREFIX/bin/mpv-2.dll" \
        "$PREFIX/lib/libmpv.dll.a" \
        "$PREFIX/lib/libmpv.dylib" \
        "$PREFIX/lib/libmpv."*.dylib
    do
      if [[ -e "$f" ]]; then
        case "$f" in
          *.dll) ensure_dir "$dest/bin"; cp -a "$f" "$dest/bin/"; copied=1 ;;
          *) cp -a "$f" "$dest/lib/"; copied=1 ;;
        esac
      fi
    done
  fi
  [[ "$copied" -eq 1 ]] || die "libmpv shared library not found in $PREFIX"

  if [[ "$OS" == linux ]]; then
    local real_mpv
    real_mpv=$(readlink -f "$dest/lib/libmpv.so")
    bundle_linux_shared_deps "$dest/lib" "$real_mpv"
  fi

  if [[ -f "$PREFIX/lib/pkgconfig/mpv.pc" ]]; then
    ensure_dir "$dest/lib/pkgconfig"
    sed -e "s|^prefix=.*|prefix=\${pcfiledir}/../..|" \
        -e "s|^exec_prefix=.*|exec_prefix=\${prefix}|" \
        "$PREFIX/lib/pkgconfig/mpv.pc" >"$dest/lib/pkgconfig/mpv.pc"
  fi

  if [[ -n "${STRIP:-}" && -x "${STRIP}" ]]; then
    case "$OS" in
      android|windows|linux)
        find "$dest" -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.dll' \) -exec "$STRIP" --strip-unneeded {} \;
        ;;
      macos|ios|iossimulator)
        find "$dest" -type f -name '*.dylib' -exec "$STRIP" -x {} \; || true
        ;;
    esac
  fi

  if [[ "$OS" == macos || "$OS" == ios || "$OS" == iossimulator ]]; then
    if command -v install_name_tool >/dev/null 2>&1; then
      find "$dest/lib" -name 'libmpv*.dylib' -exec install_name_tool -id '@rpath/libmpv.2.dylib' {} \;
    fi
  fi

  cat >"$dest/manifest.txt" <<EOF
name=libmpv
version=$version
os=$OS
arch=$ARCH
flavor=$FLAVOR
mpv=$MPV_VERSION
ffmpeg=$FFMPEG_VERSION
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
license=$(flavor_license)
EOF
  if [[ "$OS" == linux ]]; then
    echo "linux_bundled_deps=yes" >>"$dest/manifest.txt"
  fi

  cp "$ROOT_DIR/LICENSE" "$dest/licenses/mpv-prebuild.txt"
  local proj cand
  for proj in mpv ffmpeg dav1d mbedtls libass libplacebo libiconv libdisplay-info wayland wayland-protocols lcms2 libdovi vulkan-headers vulkan-loader shaderc xxhash; do
    for cand in COPYING.LIB COPYING LICENSE LICENSE.txt COPYING.LGPLv2.1 COPYING.GPLv2 COPYING.GPLv3; do
      if [[ -f "$SRC_DIR/$proj/$cand" ]]; then
        cp "$SRC_DIR/$proj/$cand" "$dest/licenses/${proj}-${cand}"
        break
      fi
    done
  done
  local wdir wname
  for wdir in \
    "shaderc/third_party/glslang:glslang" \
    "shaderc/third_party/spirv-tools:spirv-tools" \
    "shaderc/third_party/spirv-headers:spirv-headers"
  do
    wname="${wdir##*:}"
    wdir="${wdir%%:*}"
    for cand in LICENSE LICENSE.txt COPYING; do
      if [[ -f "$SRC_DIR/$wdir/$cand" ]]; then
        cp "$SRC_DIR/$wdir/$cand" "$dest/licenses/${wname}-${cand}"
        break
      fi
    done
  done
  if [[ "$OS" == windows ]]; then
    for cand in LICENSE LICENSE.txt COPYING COPYING.LIB; do
      if [[ -f "$SRC_DIR/spirv-cross/$cand" ]]; then
        cp "$SRC_DIR/spirv-cross/$cand" "$dest/licenses/spirv-cross-${cand}"
        break
      fi
    done
  fi
  if is_gpl; then
    for cand in COPYING COPYING.GPLv2 LICENSE; do
      if [[ -f "$SRC_DIR/x264/$cand" ]]; then
        cp "$SRC_DIR/x264/$cand" "$dest/licenses/x264-${cand}"
        break
      fi
    done
  fi

  (
    cd "$DIST_DIR"
    if [[ "$OS" == windows ]]; then
      need_cmd zip
      rm -f "${out_name}.zip"
      zip -r "${out_name}.zip" "$out_name"
    else
      tar -czf "${out_name}.tar.gz" "$out_name"
    fi
  )
  log "packaged $DIST_DIR/${out_name}.*"
}

merge_android_abis() {
  local version="$1"
  local out_name="libmpv-android-jni-${FLAVOR}-${version}"
  local dest="$DIST_DIR/$out_name"
  rm -rf "$dest"
  ensure_dir "$dest/include/mpv"

  local abi prefix
  local found=0
  for abi in arm64-v8a armeabi-v7a x86 x86_64; do
    case "$abi" in
      arm64-v8a) prefix="$WORK_DIR/prefix/android-arm64-${FLAVOR}" ;;
      armeabi-v7a) prefix="$WORK_DIR/prefix/android-armv7-${FLAVOR}" ;;
      x86) prefix="$WORK_DIR/prefix/android-x86-${FLAVOR}" ;;
      x86_64) prefix="$WORK_DIR/prefix/android-x86_64-${FLAVOR}" ;;
    esac
    if [[ -e "$prefix/lib/libmpv.so" ]]; then
      ensure_dir "$dest/jniLibs/$abi"
      copy_real_libmpv_so "$prefix/lib/libmpv.so" "$dest/jniLibs/$abi/libmpv.so"
      found=1
      if [[ ! -f "$dest/include/mpv/client.h" ]]; then
        cp -a "$prefix/include/mpv/"*.h "$dest/include/mpv/"
      fi
    fi
  done
  [[ "$found" -eq 1 ]] || die "no Android libmpv.so slices to merge"
  (
    cd "$DIST_DIR"
    tar -czf "${out_name}.tar.gz" "$out_name"
  )
  log "packaged $DIST_DIR/${out_name}.tar.gz"
}

lipo_macos_universal() {
  local version="$1"
  local arm="$WORK_DIR/prefix/macos-arm64-${FLAVOR}"
  local intel="$WORK_DIR/prefix/macos-x86_64-${FLAVOR}"
  [[ -d "$arm" && -d "$intel" ]] || die "macos universal requires arm64 and x86_64 prefixes"
  need_cmd lipo

  local out_name="libmpv-macos-universal-${FLAVOR}-${version}"
  local dest="$DIST_DIR/$out_name"
  rm -rf "$dest"
  ensure_dir "$dest/include/mpv" "$dest/lib"
  cp -a "$arm/include/mpv/"*.h "$dest/include/mpv/"

  local dylib
  dylib=$(ls "$arm"/lib/libmpv*.dylib | head -n1)
  [[ -n "$dylib" ]] || die "missing macos arm64 dylib"
  local base
  base=$(basename "$dylib")
  lipo -create "$arm/lib/$base" "$intel/lib/$base" -output "$dest/lib/$base"
  install_name_tool -id '@rpath/libmpv.2.dylib' "$dest/lib/$base"
  (
    cd "$DIST_DIR"
    tar -czf "${out_name}.tar.gz" "$out_name"
  )
  log "packaged $DIST_DIR/${out_name}.tar.gz"
}
