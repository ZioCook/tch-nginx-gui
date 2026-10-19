#!/usr/bin/env python3
import subprocess
import os
import sys
import shutil
import re
import glob

FASTFETCH_SRC = '/home/lorenzo/fastfetch_src'

TOOLCHAINS = {
    'arm': {
        'processor': 'arm',
        'prefix': '/home/lorenzo/toolchains_bootlin/armv5-eabi--musl--stable-2026.08-1/bin/arm-linux-',
        'sysroot': '/home/lorenzo/toolchains_bootlin/armv5-eabi--musl--stable-2026.08-1/arm-buildroot-linux-musleabi/sysroot',
        'cflags': '-march=armv7-a -mtune=cortex-a9 -mthumb -mfloat-abi=soft -Os -flto -ffunction-sections -fdata-sections -fno-asynchronous-unwind-tables -DNDEBUG -Dnullptr=NULL',
        'ldflags': '-static -flto -s -Wl,--gc-sections',
        'out_binary': 'fastfetch-arm'
    },
    'mips': {
        'processor': 'mips',
        'prefix': '/home/lorenzo/toolchains_bootlin/mips32--musl--stable-2026.08-1/bin/mips-linux-',
        'sysroot': '/home/lorenzo/toolchains_bootlin/mips32--musl--stable-2026.08-1/mips-buildroot-linux-musl/sysroot',
        'cflags': '-march=mips32 -mabi=32 -EB -Os -flto -ffunction-sections -fdata-sections -fno-asynchronous-unwind-tables -DNDEBUG',
        'ldflags': '-static -flto -s -Wl,--gc-sections -Wl,--fatal-warnings',
        'out_binary': 'fastfetch-mips'
    }
}

pkgs_to_disable = [
    'APK', 'BREW', 'CHOCO', 'DPKG', 'EMERGE', 'EOPKG', 'FLATPAK',
    'NIX', 'PACMAN', 'PALUDIS', 'PKG', 'PKGTOOL', 'MACPORTS', 'RPM',
    'SCOOP', 'SNAP', 'WINGET', 'XBPS', 'AM', 'SORCERY', 'LPKG',
    'LPKGBUILD', 'GUIX', 'LINGLONG', 'PACSTALL'
]
pkg_flags = [f'-DPACKAGES_DISABLE_{p}=ON' for p in pkgs_to_disable]

modules_to_disable = [
    'BATTERY', 'BIOS', 'BLUETOOTH', 'BLUETOOTHRADIO', 'BOOTMGR',
    'BRIGHTNESS', 'BTRFS', 'CAMERA', 'CHASSIS', 'CODEC', 'CURSOR',
    'DE', 'DISKIO', 'DISPLAY', 'EDITOR', 'FONT', 'GAMEPAD', 'GPU',
    'ICONS', 'KEYBOARD', 'LM', 'MEDIA', 'MONITOR', 'MOUSE', 'NETIO',
    'OPENCL', 'OPENGL', 'PHYSICALDISK', 'PHYSICALMEMORY', 'PLAYER',
    'POWERADAPTER', 'SOUND', 'TERMINALFONT', 'TERMINALTHEME', 'THEME',
    'TPM', 'VULKAN', 'WALLPAPER', 'WEATHER', 'WM', 'WMTHEME', 'ZPOOL'
]
mod_flags = [f'-DMODULE_DISABLE_{m}=ON' for m in modules_to_disable]

def patch_fastfetch():
    print("Applying patches to fastfetch source...")
    # 1. Reset source files to pristine 2.70.0
    subprocess.run(['git', '-C', FASTFETCH_SRC, 'checkout', '--', '.'], check=True)

    # 2. Add global NDEBUG to CMakeLists.txt to guarantee consistent struct layout and release mode
    cmpath = f'{FASTFETCH_SRC}/CMakeLists.txt'
    with open(cmpath, 'r', encoding='utf-8') as f:
        cm = f.read()
    cm = 'add_compile_definitions(NDEBUG)\n' + cm
    with open(cmpath, 'w', encoding='utf-8') as f:
        f.write(cm)
    print("Added add_compile_definitions(NDEBUG) to CMakeLists.txt.")

    # 3. Patch gpu_drm.c Nouveau stub
    drm_file = f'{FASTFETCH_SRC}/src/detection/gpu/gpu_drm.c'
    if os.path.exists(drm_file):
        with open(drm_file, 'r', encoding='utf-8') as f:
            c = f.read()
        pattern = r'#ifndef DRM_IOCTL_NOUVEAU_GETPARAM.*?#endif // FF_HAVE_DRM'
        replacement = '''const char* ffDrmDetectNouveau(FFGPUResult* gpu, int fd) {
    (void) gpu;
    (void) fd;
    return "Nouveau unsupported";
}
#endif // FF_HAVE_DRM'''
        c, n = re.subn(pattern, replacement, c, flags=re.DOTALL)
        if n > 0:
            with open(drm_file, 'w', encoding='utf-8') as f:
                f.write(c)
            print("Patched gpu_drm.c Nouveau stub.")

    # 4. Patch cpu.c temperature check
    cpu_file = f'{FASTFETCH_SRC}/src/modules/cpu/cpu.c'
    if os.path.exists(cpu_file):
        with open(cpu_file, 'r', encoding='utf-8') as f:
            c = f.read()
        c = c.replace(
            'if (cpu.temperature != FF_CPU_TEMP_UNSET) {',
            'if (options->temp && cpu.temperature > -100.0 && cpu.temperature < 200.0) {'
        )
        with open(cpu_file, 'w', encoding='utf-8') as f:
            f.write(c)
        print("Patched cpu.c temperature checks.")

def build_arch(arch_name, config):
    print(f"==================================================")
    print(f"Building Fastfetch for {arch_name.upper()}...")
    print(f"==================================================")

    toolchain_cmake = f"""
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR {config['processor']})
set(CMAKE_C_COMPILER {config['prefix']}gcc)
set(CMAKE_CXX_COMPILER {config['prefix']}g++)
set(CMAKE_STRIP {config['prefix']}strip)
set(CMAKE_FIND_ROOT_PATH {config['sysroot']})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
"""
    toolchain_file = f"/home/lorenzo/toolchain_{arch_name}.cmake"
    with open(toolchain_file, 'w') as f:
        f.write(toolchain_cmake)

    build_dir = f"/home/lorenzo/build_{arch_name}"
    if os.path.exists(build_dir):
        shutil.rmtree(build_dir)
    os.makedirs(build_dir, exist_ok=True)

    cmd = [
        'cmake', '-B', build_dir, '-S', FASTFETCH_SRC,
        f'-DCMAKE_TOOLCHAIN_FILE={toolchain_file}',
        '-DCMAKE_BUILD_TYPE=Release',
        f'-DCMAKE_C_FLAGS_RELEASE={config["cflags"]}',
        f'-DCMAKE_EXE_LINKER_FLAGS_RELEASE={config["ldflags"]}',
        '-DIS_MUSL=ON',
        '-DBINARY_LINK_TYPE=static',
        '-DENABLE_VULKAN=OFF',
        '-DENABLE_WAYLAND=OFF',
        '-DENABLE_XCB_RANDR=OFF',
        '-DENABLE_XRANDR=OFF',
        '-DENABLE_DRM=OFF',
        '-DENABLE_VADRM=OFF',
        '-DENABLE_VAX11=OFF',
        '-DENABLE_VDPAU=OFF',
        '-DENABLE_GIO=OFF',
        '-DENABLE_DCONF=OFF',
        '-DENABLE_EET=OFF',
        '-DENABLE_DBUS=OFF',
        '-DENABLE_SQLITE3=OFF',
        '-DENABLE_RPM=OFF',
        '-DENABLE_EGL=OFF',
        '-DENABLE_GLX=OFF',
        '-DENABLE_OPENCL=OFF',
        '-DENABLE_FREETYPE=OFF',
        '-DENABLE_ELF=OFF',
        '-DENABLE_IMAGE_LOGO=OFF',
        '-DENABLE_IMAGEMAGICK7=OFF',
        '-DENABLE_IMAGEMAGICK6=OFF',
        '-DENABLE_SIXEL=OFF',
        '-DENABLE_CHAFA=OFF',
        '-DENABLE_ZLIB=OFF',
        '-DENABLE_LUA=OFF',
        '-DENABLE_LIBZFS=OFF',
        '-DBUILD_FLASHFETCH=OFF',
        '-DBUILD_TESTS=OFF',
        '-DINSTALL_LICENSE=OFF',
        '-DENABLE_EMBEDDED_PCIIDS=OFF',
        '-DENABLE_EMBEDDED_AMDGPUIDS=OFF',
        '-DPACKAGES_REMOVE_DISABLED=ON',
        '-DENABLE_WCWIDTH=OFF'
    ] + pkg_flags + mod_flags

    print(f"Running CMake configure for {arch_name}...")
    res = subprocess.run(cmd)
    if res.returncode != 0:
        print(f"CMake configure failed for {arch_name}")
        return False

    print(f"Running CMake build for {arch_name}...")
    nproc = os.cpu_count() or 4
    res = subprocess.run(['cmake', '--build', build_dir, '--target', 'fastfetch', f'-j{nproc}'])
    if res.returncode != 0:
        print(f"Build failed for {arch_name}")
        return False

    binary_path = os.path.join(build_dir, 'fastfetch')
    # Strip binary
    subprocess.run([f"{config['prefix']}strip", '--strip-all', '--remove-section=.comment', '--remove-section=.note', binary_path])

    size = os.path.getsize(binary_path)
    print(f"Successfully built {config['out_binary']}! Size: {size:,} bytes ({size / 1024:.1f} KB)")

    # Verify ELF ABI integrity for MIPS
    if arch_name == 'mips':
        # 1. Scan individual object files in build_dir
        obj_files = glob.glob(f"{build_dir}/**/*.o", recursive=True)
        soft_objects = []
        for obj in obj_files:
            res_obj = subprocess.run([f"{config['prefix']}readelf", '-A', obj], capture_output=True, text=True)
            if 'Tag_GNU_MIPS_ABI_FP: Soft float' in res_obj.stdout or 'FP ABI: Soft float' in res_obj.stdout:
                soft_objects.append(obj)
        if soft_objects:
            print(f"ERROR: {len(soft_objects)} object file(s) compiled with Soft float ABI! Examples: {soft_objects[:3]}")
            return False
        print(f"Verified {len(obj_files)} MIPS object files: 0 soft-float units detected.")

        # 2. Check final binary tag
        res_readelf = subprocess.run([f"{config['prefix']}readelf", '-A', binary_path], capture_output=True, text=True)
        if 'Tag_GNU_MIPS_ABI_FP: Hard float' not in res_readelf.stdout:
            print("ERROR: MIPS FP ABI validation failed! Tag_GNU_MIPS_ABI_FP: Hard float was not found.")
            return False
        print("Verified MIPS ELF FP ABI: Hard float o32 unified.")

    # Copy to output
    out_dir = '/mnt/c/Users/Lorenzo/.gemini/antigravity/scratch/tch-nginx-gui/decompressed/gui_file/usr/bin'
    os.makedirs(out_dir, exist_ok=True)
    dst = os.path.join(out_dir, config['out_binary'])
    shutil.copy2(binary_path, dst)
    print(f"Copied to {dst}")
    return True

if __name__ == '__main__':
    patch_fastfetch()
    for arch in ['arm', 'mips']:
        success = build_arch(arch, TOOLCHAINS[arch])
        if not success:
            sys.exit(1)
    print("ALL BUILDS COMPLETED SUCCESSFULLY!")
