# mpv-prebuild

English | [中文](README.zh.md)

Build **libmpv** shared libraries from source into SDKs you can link from other projects. The build system is written for this repo; it does not wrap or submodule third-party build trees.

Each build produces two flavors:

- **lgpl**: `mpv -Dgpl=false`, FFmpeg without `--enable-gpl` / `--enable-nonfree`. Suitable for closed-source commercial use (you still must follow LGPL).
- **gpl**: FFmpeg `--enable-gpl --enable-libx264`, mpv `-Dgpl=true`, plus x264. **Distribute the whole package under GPL.**

Dependencies are statically linked into `libmpv` except on Linux, where desktop backends (ALSA, Pulse, X11, Wayland, …) stay as shared libraries and are copied next to `libmpv.so`. Consumers typically need only that flavor's shared library plus headers. Default `--flavor all` builds both. GPU rendering goes through **libplacebo** (mpv 0.41 `vo_gpu_next` / `mpv_render`) with OpenGL, Vulkan (shaderc + glslang; `vk-proc-addr` links the Vulkan loader), plus D3D11 on Windows (SPIRV-Cross). Color management uses **lcms2**. Dolby Vision RPU uses **libdovi**. Cache hashing uses **xxHash**.

## Artifacts

```
libmpv-<mpv-version>-<os>-<arch>-<flavor>-<version>/
  include/mpv/          # client.h render.h render_gl.h stream_cb.h
  lib/                  # libmpv.so / libmpv.dylib / libmpv.dll.a
  bin/                  # Windows: libmpv-2.dll
  lib/pkgconfig/mpv.pc
  manifest.txt          # flavor=lgpl|gpl
  licenses/
```

`<version>` is `--version` / the workflow input. If it is empty, the UTC build time `YYYYMMDDHHMMSS` is used.

| Platform | Typical artifact | Notes |
| --- | --- | --- |
| Windows | `libmpv-0.41.0-windows-x86_64-lgpl-*.zip` / `*-gpl-*.zip` | `bin/libmpv-2.dll` + import library |
| Android | `libmpv-0.41.0-android-jni-lgpl-*.tar.gz` / `*-gpl-*.tar.gz` | `jniLibs/<abi>/libmpv.so` |
| Linux | `libmpv-0.41.0-linux-x86_64-lgpl-*.tar.gz` / `*-gpl-*.tar.gz` | Native Ubuntu `libmpv.so` (arm64 as well) |
| macOS | `libmpv-0.41.0-macos-universal-lgpl-*.tar.gz` / `*-gpl-*.tar.gz` | `lipo`'d `libmpv*.dylib` |
| iOS | `libmpv-0.41.0-ios-arm64-lgpl-*.tar.gz` / `*-gpl-*.tar.gz` | Device arm64 dylib |

Versions are pinned in `config/versions.env` (currently mpv 0.41.0 + FFmpeg 9.0.1).

## GitHub Actions

Actions → **Build libmpv** → Run workflow, then pick a platform. Pushing a `v*` tag builds and publishes a Release.

You can also run a platform workflow on its own:

- [Windows](.github/workflows/windows.yml) (`ubuntu-22.04` + llvm-mingw)
- [Android](.github/workflows/android.yml) (`ubuntu-22.04` + NDK r29)
- [Linux](.github/workflows/linux.yml) (`ubuntu-22.04` x86_64 / `ubuntu-22.04-arm` arm64)
- [Darwin](.github/workflows/darwin.yml) (`macos-15` + Xcode)

## Local builds

Host packages are listed in `config/host-deps.yml`. From the repo root:

```bash
# Android (needs ANDROID_NDK_HOME) — builds lgpl + gpl by default
bash ./scripts/build.sh --os android --arch arm64
bash ./scripts/build.sh --os android --arch all --flavor lgpl   # LGPL only

# Windows (Linux host, needs llvm-mingw)
bash ./scripts/setup-llvm-mingw.sh
export LLVM_MINGW_HOME=$PWD/work/llvm-mingw
bash ./scripts/build.sh --os windows --arch x86_64

# Linux / Ubuntu (native build on a matching-arch Linux host)
bash ./scripts/build.sh --os linux --arch x86_64
# or: bash ./scripts/build.sh --os ubuntu --arch all

# macOS / iOS (macOS host only)
bash ./scripts/build.sh --os macos --arch universal
bash ./scripts/build.sh --os ios --arch arm64 --flavor all
```

`make android` / `make windows` / `make macos` / `make ios` / `make linux` are aliases for the commands above.

## Using the SDK

### pkg-config

```bash
export PKG_CONFIG_PATH=/path/to/libmpv-.../lib/pkgconfig
cc player.c $(pkg-config --cflags --libs mpv)
```

### CMake

```cmake
add_library(mpv SHARED IMPORTED)
set_target_properties(mpv PROPERTIES
  IMPORTED_LOCATION "${LIBMPV_ROOT}/lib/libmpv.so"          # Windows: bin/libmpv-2.dll
  IMPORTED_IMPLIB   "${LIBMPV_ROOT}/lib/libmpv.dll.a"        # Windows only
  INTERFACE_INCLUDE_DIRECTORIES "${LIBMPV_ROOT}/include")
target_link_libraries(your_app PRIVATE mpv)
```

On Windows, place `libmpv-2.dll` next to the executable.

### Linux

Unpack `libmpv-0.41.0-linux-*.tar.gz` and link `lib/libmpv.so` with pkg-config or CMake as above.

Linux artifacts (x86_64 and arm64) are built on Ubuntu 22.04 (glibc 2.35) and run on that or newer. Jammy is missing or too old for several mpv 0.41 deps, so the Linux build vendors them into the prefix instead of moving the runner (and glibc) to 24.04: **libdisplay-info**, **libwayland 1.23**, and **wayland-protocols 1.38**. Native PipeWire is linked against the distro `libpipewire-0.3` (Ubuntu 22.04 is 0.3.48; mpv 0.41 is patched at build time because upstream wants 0.3.57). Pulse and ALSA remain available, including `pipewire-pulse`.

mpv 0.41 treats X11, VDPAU, and JACK as GPL-only. **lgpl** Linux builds keep Wayland / DRM / GBM / EGL / VA-API (drm+wayland) / ALSA / Pulse / sndio. **gpl** adds X11, VDPAU, and JACK.

Packaging walks `ldd` and copies every non-glibc `DT_NEEDED` library into `lib/` (ALSA, PulseAudio, PipeWire when linked, JACK, sndio, X11, Wayland, DRM/GBM, VA-API, VDPAU, `libGL`/`libEGL`, and their recursive deps). `RUNPATH` is `$ORIGIN`, so those files load from the same directory as `libmpv.so`. `lib/bundled-libraries.txt` lists what was included.

Still required from the host:

- glibc (and the dynamic linker) — not bundled, so the binary stays compatible with the distro
- GPU/VA-API/VDPAU **driver plugins** that are `dlopen`'d (Mesa DRI, `iHD_drv_video.so`, nvidia, …) if you want hardware decode/display
- A running session when you actually play: Pulse/PipeWire daemon, X11/Wayland compositor, or a DRM node

`mpv_render` still works if the host supplies an OpenGL/EGL context.

### Android

Unpack `libmpv-0.41.0-android-jni-*.tar.gz` and wire `jniLibs/` plus `include/` into the module:

```
src/main/jniLibs/<abi>/libmpv.so
src/main/cpp/include/mpv/...
```

### Apple

Link `libmpv*.dylib` and set an rpath:

```
-Wl,-rpath,@executable_path/../Frameworks
```

The library install name is already `@rpath/libmpv.2.dylib`.

## Build graph

Dependencies are built as static libraries; the only shared output is libmpv:

```
zlib, mbedtls, dav1d, libxml2
libpng → freetype → harfbuzz
fribidi
libass (freetype + harfbuzz + fribidi)
libiconv                # Windows/Android; Linux and Apple use libc
uchardet
lcms2                 # ICC / color management (MIT core; no GPL-3 plugins)
libdovi               # Dolby Vision RPU (cargo-c)
shaderc               # GLSL→SPIR-V (Vulkan; also D3D11)
glslang               # second SPIR-V compiler (from shaderc third_party)
xxhash                # libplacebo cache hashing
SPIRV-Cross           # Windows D3D11 (SPIR-V→HLSL)
vulkan-headers        # Vulkan 1.4 headers
vulkan-loader         # static loader (Android: NDK libvulkan)
libplacebo            # OpenGL + Vulkan (vk-proc-addr); Windows also D3D11
libdisplay-info       # Linux only (mpv DRM / EDID)
wayland + protocols   # Linux, vendored when distro is older than mpv 0.41
x264                    # gpl only
FFmpeg (mbedtls + dav1d + libxml2 [+ x264 if gpl])
libmpv (FFmpeg + libass + uchardet + libplacebo [+ Linux DRM/Wayland deps])
```

## License

- Build scripts in this repo: MIT (see `LICENSE`)
- **lgpl** artifacts: primarily **LGPL-2.1+** from mpv / FFmpeg; other dependency licenses are in `licenses/`
- **gpl** artifacts: because x264 is linked and FFmpeg/mpv enable GPL, the **whole package is GPL-2.0+** and cannot be shipped as closed-source proprietary software
- Do not redistribute either artifact as a proprietary library without meeting the corresponding copyleft obligations
