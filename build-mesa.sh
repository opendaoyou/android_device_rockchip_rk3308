#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 build-directory [llvmpipe|softpipe]" >&2
    exit 2
fi

root=$(realpath "$1")
mode=${2:-llvmpipe}
case "$mode" in llvmpipe|softpipe) ;; *) echo "Unknown Mesa driver: $mode" >&2; exit 2;; esac
ndk="$root/android-ndk-r27d"
mesa="$root/mesa-25.0.7"
drm="$root/libdrm-2.4.124"
llvm="$root/llvm-project-19.1.7.src/llvm"
for path in "$ndk" "$mesa" "$drm"; do
    test -d "$path" || { echo "Missing source or toolchain directory: $path" >&2; exit 1; }
done

jobs=${SOGOU_MESA_JOBS:-4}
bin="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
prefix="$root/install-$mode"
cross="$root/android-armv7.ini"
cat > "$cross" <<CROSS
[binaries]
c = '$bin/armv7a-linux-androideabi27-clang'
cpp = '$bin/armv7a-linux-androideabi27-clang++'
ar = '$bin/llvm-ar'
strip = '$bin/llvm-strip'
pkg-config = 'pkg-config'

[host_machine]
system = 'android'
cpu_family = 'arm'
cpu = 'armv7-a'
endian = 'little'

[properties]
needs_exe_wrapper = true
pkg_config_libdir = ['$root/drm-install/lib/pkgconfig']

[built-in options]
c_args = ['-mfpu=neon']
cpp_args = ['-mfpu=neon']
cpp_link_args = ['-static-libstdc++']
CROSS

setup() {
    local source=$1 build=$2
    shift 2
    if [ ! -f "$build/build.ninja" ]; then
        meson setup "$build" "$source" --cross-file "$cross" "$@"
    fi
}

setup "$drm" "$root/drm-build" --prefix "$root/drm-install" --libdir lib \
    --buildtype release --default-library static -Dauto_features=disabled \
    -Dudev=false -Dinstall-test-programs=false
meson compile -C "$root/drm-build" -j "$jobs"
meson install -C "$root/drm-build" --no-rebuild

vulkan=()
gallium_drivers=$mode
llvm_args=(-Dllvm=disabled -Ddraw-use-llvm=false)
if [ "$mode" = llvmpipe ]; then
    command -v glslangValidator >/dev/null || { echo "glslangValidator is required for lavapipe" >&2; exit 1; }
    test -d "$llvm" || { echo "Missing LLVM sources: $llvm" >&2; exit 1; }
    build="$root/llvm-build"
    cmake -S "$llvm" -B "$build" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI=armeabi-v7a -DANDROID_PLATFORM=android-27 \
        -DANDROID_STL=c++_static -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DLLVM_HOST_TRIPLE=armv7a-linux-androideabi27 -DLLVM_TARGETS_TO_BUILD=ARM \
        -DLLVM_ENABLE_PIC=ON -DLLVM_ENABLE_RTTI=OFF -DLLVM_ENABLE_ASSERTIONS=OFF \
        -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF \
        -DLLVM_BUILD_TOOLS=OFF -DLLVM_INCLUDE_DOCS=OFF \
        -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF \
        -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_Z3_SOLVER=OFF
    cmake --build "$build" --parallel "$jobs" --target LLVMARMCodeGen LLVMARMAsmParser \
        LLVMARMDisassembler LLVMMCJIT LLVMExecutionEngine LLVMPasses \
        LLVMInstCombine LLVMScalarOpts LLVMCoroutines LLVMBitWriter
    python3 - "$mesa" "$llvm" "$build" <<'PY'
from pathlib import Path
import sys
mesa, llvm, build = map(Path, sys.argv[1:])
wrap = mesa / 'subprojects/llvm'
wrap.mkdir(exist_ok=True)
archives = sorted(map(str, (build / 'lib').glob('libLLVM*.a')))
if not archives:
    raise SystemExit('Missing Android LLVM libraries')
# Meson groups static link inputs itself.
args = archives
(wrap / 'meson.build').write_text(
    "project('llvm', 'cpp', version: '19.1.7')\n"
    "has_rtti = false\n"
    "dep_llvm = declare_dependency(\n"
    f"  include_directories: include_directories('{llvm}/include', '{build}/include', is_system: true),\n"
    f"  link_args: {args!r},\n"
    "  version: meson.project_version(),\n"
    ")\n"
)
PY
    vulkan=(swrast)
    gallium_drivers=llvmpipe,softpipe
    llvm_args=(-Dllvm=enabled -Dshared-llvm=disabled -Dcpp_rtti=false --force-fallback-for=llvm)
fi

# API 27 uses Clang's emulated TLS. Export its descriptors from Gallium.
python3 - "$mesa/src/gallium/targets/dri/dri.sym.in" <<'PYTLS'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
for name in ('_mesa_glapi_tls_Context', '_mesa_glapi_tls_Dispatch'):
    old = f'                {name};'
    new = f'                __emutls_v.{name};'
    if old in text:
        text = text.replace(old, new)
    elif new not in text:
        raise SystemExit(f'Missing expected symbol in {path}: {name}')
path.write_text(text)
PYTLS

# Each shared library has its own emulated TLS runtime on Oreo. Resolve GLES
# dispatch in Gallium, where the current context's dispatch table is set.
python3 - "$mesa/src/mapi/entry.c" <<'PYDISPATCH'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = "   return GET_DISPATCH();"
new = """#if defined(__ANDROID__) && __ANDROID_API__ < 29 && defined(MAPI_MODE_BRIDGE)
   return _mesa_glapi_get_dispatch();
#else
   return GET_DISPATCH();
#endif"""
if new not in text:
    if text.count(old) != 1:
        raise SystemExit(f'Unexpected GL dispatch accessor in {path}')
    path.write_text(text.replace(old, new, 1))
PYDISPATCH

# Oreo HWUI assumes the float extension implies an FP16 window config.
python3 - "$mesa/src/egl/drivers/dri2/platform_android.c" <<'PYEGL'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = "   dri2_setup_screen(disp);"
new = """   dri2_setup_screen(disp);
#if ANDROID_API_LEVEL <= 27
   if (dri2_dpy->pure_swrast)
      disp->Extensions.EXT_pixel_format_float = EGL_FALSE;
#endif"""
if new not in text:
    if text.count(old) != 1:
        raise SystemExit(f'Unexpected Android EGL screen setup in {path}')
    path.write_text(text.replace(old, new, 1))
PYEGL

# Android's system_server cannot execute generated shaders. Keep llvmpipe for
# other clients and use the interpreter inside that SELinux domain.
python3 - "$mesa/src/gallium/auxiliary/target-helpers/sw_helper.h" <<'PYSOFTPIPE'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
include = '#include "util/u_debug.h"'
new_include = include + '\n#include "util/os_file.h"'
old = '   UNUSED bool only_sw = debug_get_bool_option("LIBGL_ALWAYS_SOFTWARE", false);'
new = '''#if defined(__ANDROID__) && defined(GALLIUM_SOFTPIPE) && defined(GALLIUM_LLVMPIPE)
   static const char system_server[] = "u:r:system_server:";
   char *context = os_read_file("/proc/self/attr/current", NULL);
   bool use_softpipe = context &&
      strncmp(context, system_server, sizeof(system_server) - 1) == 0;
   free(context);
   if (use_softpipe && !sw_vk)
      return sw_screen_create_named(winsys, config, "softpipe");
#endif

''' + old
if new not in text:
    if text.count(old) != 1 or text.count(include) != 1:
        raise SystemExit(f'Unexpected software rasterizer setup in {path}')
    path.write_text(text.replace(include, new_include, 1).replace(old, new, 1))
PYSOFTPIPE

# Oreo's libcutils uses inline trace helpers and exports atrace_setup.
python3 - "$mesa" <<'PYTRACE'
from pathlib import Path
import sys
mesa = Path(sys.argv[1])
header = mesa / 'include/android_stub/cutils/trace.h'
text = header.read_text()
accessor = 'static inline uint64_t atrace_get_enabled_tags() { atrace_init(); return atrace_enabled_tags; }'
init = """void atrace_setup();
static inline void atrace_init()
{
    if (!atomic_load_explicit(&atrace_is_ready, memory_order_acquire))
        atrace_setup();
}"""
text = text.replace('uint64_t atrace_get_enabled_tags();', accessor, 1)
text = text.replace('void atrace_init();', init, 1)
if accessor not in text or init not in text:
    raise SystemExit(f'Unexpected trace header revision: {header}')
header.write_text(text)
stub = mesa / 'src/android_stub/cutils_stub.cpp'
text = stub.read_text()
text = text.replace(
    'uint64_t\natrace_get_enabled_tags()\n{\n   return ATRACE_TAG_NOT_READY;\n}',
    'uint64_t atrace_enabled_tags = ATRACE_TAG_NOT_READY;', 1)
text = text.replace('void\natrace_init()\n{\n}', 'atomic_bool atrace_is_ready = false;\n\nvoid\natrace_setup()\n{\n}', 1)
if 'atrace_is_ready = false;' not in text or 'atrace_enabled_tags = ATRACE_TAG_NOT_READY;' not in text:
    raise SystemExit(f'Unexpected trace stub revision: {stub}')
stub.write_text(text)
PYTRACE

# Bionic API 27 does not export memfd_create; its kernel syscall is available.
if [ "$mode" = llvmpipe ]; then
    python3 - "$mesa/src/gallium/drivers/llvmpipe/lp_texture.c" <<'PYMEMFD'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
replacements = (
    ('#include <linux/udmabuf.h>', '#include <linux/udmabuf.h>\n#include <sys/syscall.h>'),
    ('int mem_fd = memfd_create("lp_dma_buf", MFD_ALLOW_SEALING);',
     'mem_fd = syscall(SYS_memfd_create, "lp_dma_buf", MFD_CLOEXEC | MFD_ALLOW_SEALING);'),
    ('int dmabuf_fd = ioctl(screen->udmabuf_fd, UDMABUF_CREATE, &create);',
     'dmabuf_fd = ioctl(screen->udmabuf_fd, UDMABUF_CREATE, &create);'),
    ('if (!data)\n         goto fail;\n\n      alloc->mem_fd',
     'if (data == MAP_FAILED)\n         goto fail;\n\n      alloc->mem_fd'),
)
for old, new in replacements:
    if new in text:
        continue
    if text.count(old) != 1:
        raise SystemExit(f'Unexpected Mesa udmabuf code in {path}: {old}')
    text = text.replace(old, new, 1)
path.write_text(text)
PYMEMFD
fi

mesa_build="$root/mesa-build-$mode"
setup "$mesa" "$mesa_build" --prefix "$prefix" --libdir lib \
    --buildtype release -Dplatforms=android -Dplatform-sdk-version=27 \
    -Dandroid-stub=true -Dandroid-libbacktrace=disabled \
    -Dgallium-drivers="$gallium_drivers" -Dvulkan-drivers="${vulkan[*]}" \
    -Degl=enabled -Dgles1=enabled -Dgles2=enabled -Dgbm=disabled -Dglx=disabled \
    -Dlibunwind=disabled -Dxmlconfig=disabled -Dvideo-codecs= \
    "${llvm_args[@]}"
meson configure "$mesa_build" -Dgallium-drivers="$gallium_drivers"
meson compile -C "$mesa_build" -j "$jobs"
meson install -C "$mesa_build" --no-rebuild

stage="$root/stage-$mode"
mkdir -p "$stage/egl" "$stage/hw"
for lib in EGL GLESv1_CM GLESv2; do
    install -m0644 "$prefix/lib/lib$lib.so" "$stage/egl/lib${lib}_lp.so"
    "$bin/llvm-strip" --strip-unneeded "$stage/egl/lib${lib}_lp.so"
    patchelf --set-soname "lib${lib}_lp.so" "$stage/egl/lib${lib}_lp.so"
done
install -m0644 "$prefix/lib/libgallium_dri.so" "$stage/egl/libgallium_dri.so"
"$bin/llvm-strip" --strip-unneeded "$stage/egl/libgallium_dri.so"
if [ -f "$prefix/lib/libglapi.so" ]; then
    install -m0644 "$prefix/lib/libglapi.so" "$stage/libglapi.so"
    "$bin/llvm-strip" --strip-unneeded "$stage/libglapi.so"
fi
if [ "$mode" = llvmpipe ]; then
    install -m0644 "$prefix/lib/libvulkan_lvp.so" "$stage/hw/vulkan.rk3308.so"
    "$bin/llvm-strip" --strip-unneeded "$stage/hw/vulkan.rk3308.so"
    patchelf --set-soname vulkan.rk3308.so "$stage/hw/vulkan.rk3308.so"
fi
echo "SOGOU_E1_MESA_DIR=$stage"
