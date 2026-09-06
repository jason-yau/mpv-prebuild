# mpv-prebuild

[English](README.md) | 中文

从源码编译 **libmpv** 共享库，产出可直接在其他工程里链接的二进制 SDK。构建系统是独立编写的，不封装、不 submodule 第三方构建仓库。

每次构建会打出两套库：

- **lgpl**：`mpv -Dgpl=false`，FFmpeg 不开 `--enable-gpl` / `--enable-nonfree`，便于闭源商业使用（仍须遵守 LGPL）。
- **gpl**：FFmpeg `--enable-gpl --enable-libx264`，mpv `-Dgpl=true`，带上 x264，**整体按 GPL 分发**。

依赖都静态链进 `libmpv`。Linux 上桌面后端（ALSA、Pulse、X11、Wayland 等）仍是共享库，打包时会拷到 `libmpv.so` 旁边。使用时通常只需要对应 flavor 的共享库加上头文件。默认 `--flavor all`，两套都会编。GPU 渲染走 **libplacebo**（mpv 0.41 的 `vo_gpu_next` / `mpv_render`）：OpenGL、Vulkan（shaderc + glslang，`vk-proc-addr` 链接 Vulkan loader），Windows 另开 D3D11（SPIRV-Cross）。色彩管理用 **lcms2**，杜比视界 RPU 用 **libdovi**，缓存哈希用 **xxHash**。

## 产物

```
libmpv-<mpv-version>-<os>-<arch>-<flavor>-<version>/
  include/mpv/          # client.h render.h render_gl.h stream_cb.h
  lib/                  # libmpv.so / libmpv.dylib / libmpv.dll.a
  bin/                  # Windows: libmpv-2.dll
  lib/pkgconfig/mpv.pc
  manifest.txt          # 含 flavor=lgpl|gpl
  licenses/
```

`<version>` 来自 `--version` / workflow 输入。为空时用 UTC 构建时间 `YYYYMMDDHHMMSS`。

| 平台 | 典型产物 | 说明 |
| --- | --- | --- |
| Windows | `libmpv-0.41.0-windows-x86_64-lgpl-*.zip` / `*-gpl-*.zip` | `bin/libmpv-2.dll` + 导入库 |
| Android | `libmpv-0.41.0-android-jni-lgpl-*.tar.gz` / `*-gpl-*.tar.gz` | `jniLibs/<abi>/libmpv.so` |
| Linux | `libmpv-0.41.0-linux-x86_64-lgpl-*.tar.gz` / `*-gpl-*.tar.gz` | Ubuntu 原生 `libmpv.so`（另有 arm64） |
| macOS | `libmpv-0.41.0-macos-universal-lgpl-*.tar.gz` / `*-gpl-*.tar.gz` | `lipo` 后的 `libmpv*.dylib` |
| iOS | `libmpv-0.41.0-ios-arm64-lgpl-*.tar.gz` / `*-gpl-*.tar.gz` | 设备 arm64 dylib |

版本钉在 `config/versions.env`（当前 mpv 0.41.0 + FFmpeg 9.0.1）。

## GitHub Actions

Actions → **Build libmpv** → Run workflow，选择平台。打 `v*` 标签会构建并发布 Release。

也可以单独跑：

- [Windows](.github/workflows/windows.yml)（`ubuntu-22.04` + llvm-mingw）
- [Android](.github/workflows/android.yml)（`ubuntu-22.04` + NDK r29）
- [Linux](.github/workflows/linux.yml)（`ubuntu-22.04` x86_64 / `ubuntu-22.04-arm` arm64）
- [Darwin](.github/workflows/darwin.yml)（`macos-15` + Xcode）

## 本地编译

依赖见 `config/host-deps.yml`。在仓库根目录：

```bash
# Android（需 ANDROID_NDK_HOME）— 默认同时编 lgpl + gpl
bash ./scripts/build.sh --os android --arch arm64
bash ./scripts/build.sh --os android --arch all --flavor lgpl   # 只编 LGPL

# Windows（Linux 主机，需 llvm-mingw）
bash ./scripts/setup-llvm-mingw.sh
export LLVM_MINGW_HOME=$PWD/work/llvm-mingw
bash ./scripts/build.sh --os windows --arch x86_64

# Linux / Ubuntu（在对应架构的 Linux 主机上原生编译）
bash ./scripts/build.sh --os linux --arch x86_64
# 或: bash ./scripts/build.sh --os ubuntu --arch all

# macOS / iOS（仅 macOS 主机）
bash ./scripts/build.sh --os macos --arch universal
bash ./scripts/build.sh --os ios --arch arm64 --flavor all
```

`make android` / `make windows` / `make macos` / `make ios` / `make linux` 是上面命令的别名。

## 在其他项目中使用

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
  IMPORTED_IMPLIB   "${LIBMPV_ROOT}/lib/libmpv.dll.a"        # 仅 Windows
  INTERFACE_INCLUDE_DIRECTORIES "${LIBMPV_ROOT}/include")
target_link_libraries(your_app PRIVATE mpv)
```

Windows 运行时把 `libmpv-2.dll` 放到可执行文件旁。

### Linux

解压 `libmpv-0.41.0-linux-*.tar.gz` 后按上面的 pkg-config / CMake 方式链接 `lib/libmpv.so`。

Linux 产物（x86_64 和 arm64）都在 Ubuntu 22.04（glibc 2.35）上构建，可在同等或更新的发行版上运行。jammy 缺包或版本不够 mpv 0.41 用，Linux 构建会把这些编进 prefix，而不是把 runner（以及 glibc）升到 24.04：**libdisplay-info**、**libwayland 1.23**、**wayland-protocols 1.38**。原生 PipeWire 链发行版的 `libpipewire-0.3`（Ubuntu 22.04 是 0.3.48；mpv 0.41 上游要求 0.3.57，构建时会打兼容补丁）。Pulse / ALSA 仍然可用，包括 `pipewire-pulse`。

mpv 0.41 里 X11、VDPAU、JACK 是 GPL-only。**lgpl** Linux 构建保留 Wayland / DRM / GBM / EGL / VA-API（drm+wayland）/ ALSA / Pulse / sndio。**gpl** 再加 X11、VDPAU、JACK。

打包会按 `ldd` 把 glibc 以外的 `DT_NEEDED` 都拷进 `lib/`（ALSA、PulseAudio、若已链接则有 PipeWire、JACK、sndio、X11、Wayland、DRM/GBM、VA-API、VDPAU、`libGL`/`libEGL` 以及它们的递归依赖），并把 `RUNPATH` 设为 `$ORIGIN`，与 `libmpv.so` 同目录即可加载。清单在 `lib/bundled-libraries.txt`。

主机仍需提供：

- glibc（以及动态链接器）——不打包，以便跟发行版保持兼容
- 硬件解码/显示用的 **驱动插件**（Mesa DRI、`iHD_drv_video.so`、nvidia 等），这些是运行时 `dlopen` 的
- 真正播放时还要有会话：Pulse/PipeWire 守护进程、X11/Wayland 合成器，或 DRM 节点

宿主如果自己提供 OpenGL/EGL 上下文，`mpv_render` 仍然可用。

### Android

解压 `libmpv-0.41.0-android-jni-*.tar.gz` 后，把 `jniLibs/` 和 `include/` 接到模块：

```
src/main/jniLibs/<abi>/libmpv.so
src/main/cpp/include/mpv/...
```

### Apple

链接 `libmpv*.dylib`，并设置 rpath：

```
-Wl,-rpath,@executable_path/../Frameworks
```

库的 install name 已设为 `@rpath/libmpv.2.dylib`。

## 构建拓扑

依赖全部编成静态库，最后只产出一份共享的 libmpv：

```
zlib, mbedtls, dav1d, libxml2
libpng → freetype → harfbuzz
fribidi
libass (freetype + harfbuzz + fribidi)
libiconv                # Windows/Android；Linux 和 Apple 用系统 libc
uchardet
lcms2                 # ICC / 色彩管理（MIT 核心，不开 GPL-3 插件）
libdovi               # 杜比视界 RPU（cargo-c）
shaderc               # GLSL→SPIR-V（Vulkan；Windows D3D11 也用）
glslang               # 第二套 SPIR-V 编译器（来自 shaderc third_party）
xxhash                # libplacebo 缓存哈希
SPIRV-Cross           # 仅 Windows D3D11（SPIR-V→HLSL）
vulkan-headers        # Vulkan 1.4 头文件
vulkan-loader         # 静态 loader（Android 用 NDK libvulkan）
libplacebo            # OpenGL + Vulkan（vk-proc-addr）；Windows 另有 D3D11
libdisplay-info       # 仅 Linux（mpv DRM / EDID）
wayland + protocols   # 仅 Linux；发行版比 mpv 0.41 旧时编进 prefix
x264                    # 仅 gpl
FFmpeg (mbedtls + dav1d + libxml2 [+ x264 if gpl])
libmpv (FFmpeg + libass + uchardet + libplacebo [+ Linux DRM/Wayland 依赖])
```

## 许可证

- 本仓库构建脚本：MIT（见 `LICENSE`）
- **lgpl** 产物：以 mpv / FFmpeg 的 **LGPL-2.1+** 为主；各依赖许可证在产物的 `licenses/` 里
- **gpl** 产物：因链接 x264 且 FFmpeg/mpv 开启 GPL，**整体为 GPL-2.0+**，不能按闭源专有软件分发
- 不要把任一产物当成无 copyleft 的专有库再分发而不履行对应义务
