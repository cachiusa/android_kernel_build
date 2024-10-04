# About build configuration

# List of all variables
## General options
A typical build config should include the following:

### ARCH
Set ARCH to the architecture to be built, typically: arm64, x86, ...  
In most cases the name of the architecture is the same as the directory name found in the arch/ directory

### DEFCONFIG
Set a **def**ault **config**uration file within [$KERNEL_DIR](#kernel_dir)/arch/[$ARCH](#arch)/configs

### CC
Override compiler to be used. (e.g. CC=clang)  
Specifying CC=gcc effectively unsets CC to fall back to the default gcc detected by kbuild (including any target triplet) and skips LTO setup.  
To use a custom compiler from PATH, use an absolute path, e.g. CC=/usr/local/bin/gcc
### HOSTCC, HOSTAR, HOSTLD
### LD, AR, AS, NM, OBJCOPY, OBJDUMP, STRIP, READELF...
### LLVM
### LLVM_IAS
### CROSS_COMPILE, CROSS_COMPILE_ARM32, CROSS_COMPILE_COMPAT
### MAKE_GOALS
List of targets passed to Make when compiling the kernel.  
Typically: Image, modules, and a DTB (if applicable).

### FILES
List of files (relative to [OUT_DIR](#out_dir)) copied to [DIST_DIR](#dist_dir) after building the kernel.   

### LTO=[ full | thin | none ]
- If set to "full", force any kernel with LTO_CLANG support to be built with full LTO, which is the most optimized method. This is the default, but can result in very slow build times, especially when building incrementally. (This mode does not require CFI to be disabled.)
- If set to "thin", force any kernel with LTO_CLANG support to be built with ThinLTO, which trades off some optimizations for incremental build speed. This is nearly always what you want for local development. (This mode does not require CFI to be disabled.)
- If set to "none", force any kernel with LTO_CLANG support to be built without any LTO (upstream default), which results in no optimizations and also disables LTO-dependent features like CFI. This mode is not recommended because CFI will not be able to catch bugs if it is disabled.

## Advanced options

### BUILD_CONFIG
Build config file to initialize the build environment from.  
The location is to be defined relative to the repo root directory.
Defaults to `build.config`.

### BUILD_CONFIG_FRAGMENTS
A whitespace-separated list of additional build config fragments to be sourced after the main build config file. Typically used for sanitizers or other special builds.

### KERNEL_DIR
Base directory of the kernel source tree. If not specified, defaults to the parent directory of BUILD_CONFIG file.

### OUT_DIR
Base output directory for the kernel build.
Defaults to `<REPO_ROOT>/out/<BRANCH>`.

### DIST_DIR
Base output directory for the kernel distribution.
Defaults to `<OUT_DIR>/dist`

### FAST_BUILD
If defined, trade run-time optimizations for build speed. In other words, if given a choice between a faster build and a run-time optimization, choose the shorter build time. For example, use ThinLTO for faster linking and reduce the lz4 compression level to speed up ramdisk compression.  
This trade-off is desirable for incremental kernel development where fast turnaround times are critical for productivity.

Setting this option is also equivalent to:  
```
LTO=thin
LZ4_RAMDISK_COMPRESS_ARGS="--fast"
SKIP_CP_KERNEL_HDR=1
``` 

### SKIP_IF_VERSION_MATCHES
if defined, skip compiling anything if the kernel version in vmlinux matches the expected kernel version.  
This is useful for mixed build, where GKI kernel does not change frequently and we can simply skip everything in build.sh.  
Note: if the expected version string contains "dirty", then this flag would have not cause build.sh to exit early.

### SKIP_MRPROPER
if set to "1", skip `make mrproper`

### SKIP_DEFCONFIG
if set to "1", skip `make defconfig`

### PRE_DEFCONFIG_CMDS
Command evaluated before `make defconfig`

### POST_DEFCONFIG_CMDS
Command evaluated after `make defconfig` and before `make`.

### POST_KERNEL_BUILD_CMDS
Command evaluated after `make`.

### EXTRA_CMDS
Command evaluated after building and installing kernel and modules.

### DIST_CMDS
Command evaluated after copying files to DIST_DIR

### SKIP_CP_KERNEL_HDR
if defined, skip installing kernel headers. 

### IN_KERNEL_MODULES
if defined, install kernel modules

### DO_NOT_STRIP_MODULES
if set to "1", keep debug information for distributed modules.  
Note, modules will still be stripped when copied into the ramdisk.

### EXT_MODULES
Space-separated list of external kernel modules to be build.

### SKIP_EXT_MODULES
if defined, skip building and installing of external modules

### UNSTRIPPED_MODULES
Space separated list of modules to be copied to <[DIST_DIR](#dist_dir)>/unstripped for debugging purposes.

### COMPRESS_UNSTRIPPED_MODULES
If set to "1", then compress the unstripped modules into a tarball.

### COMPRESS_MODULES
If set to "1", then compress all modules into a tarball. The default is without defining COMPRESS_MODULES.

### EXT_MODULES_MAKEFILE
Location of a makefile to build external modules.  
If set, it will get called with all the necessary parameters to build and install external modules. This allows for building them in parallel using makefile parallelization.

### BUILD_INITRAMFS
if set to "1", build a ramdisk containing all .ko files and resulting depmod artifacts 

### LZ4_RAMDISK
If set to "1", any ramdisks generated will be lz4 compressed instead of gzip compressed.

### LZ4_RAMDISK_COMPRESS_ARGS
Command line arguments passed to lz4 command to control compression
level (defaults to "-12 --favor-decSpeed"). For iterative kernel
development where faster compression is more desirable than a high
compression ratio, it can be useful to control the compression ratio.

### MODULES_OPTIONS
A `/lib/modules/modules.options` file is created on the ramdisk containing the contents of this variable, lines should be of the form: `options <modulename> <param1>=<val> <param2>=<val> ...`

### MODULES_ORDER
location of an optional file containing the list of modules that are expected to be built for the current configuration, in the modules.order format, relative to the kernel source tree.

### KCONFIG_EXT_PREFIX
Path prefix relative to either ROOT_DIR or KERNEL_DIR that points to a directory containing an external Kconfig file named Kconfig.ext.  
When set, kbuild will source ${KCONFIG_EXT_PREFIX} Kconfig.ext which can be used to set configs for external modules in the defconfig.

### HERMETIC_TOOLCHAIN
When set, the PATH during kernel build will be restricted to a set of known prebuilt directories and selected host tools that are usually not provided by prebuilt toolchains.

### ADDITIONAL_HOST_TOOLS
A whitespace separated set of tools that will be allowed to be used from the host when running the build with HERMETIC_TOOLCHAIN=1.

### GENERATE_VMLINUX_BTF
If set to "1", generate a vmlinux.btf that is stripped of any debug symbols, but contains type and symbol information within a .BTF section.  
This is suitable for ABI analysis through BTF.

### TAGS_CONFIG
if defined, calls ./scripts/tags.sh utility with TAGS_CONFIG as argument and exit once tags have been generated

### BUILD_SYSTEM_DLKM
if set to "1", build a system_dlkm.img containing all signed GKI modules and resulting depmod artifacts. GKI build exclusive; DO NOT USE with device build configs files.

### SYSTEM_DLKM_MODULES_LIST
location (relative to the repo root directory) of an optional file containing the list of kernel modules which shall be copied into a system_dlkm partition image.

### VENDOR_DLKM_MODULES_LIST
Location (relative to the repo root directory) of an optional file containing the list of kernel modules which shall be copied into a vendor_dlkm partition image.  
Any modules passed into MODULES_LIST which become part of the vendor_boot.modules.load will be trimmed from the vendor_dlkm.modules.load.

### VENDOR_DLKM_MODULES_BLOCKLIST
Location (relative to the repo root directory) of an optional file containing a list of modules which are blocked from being loaded. This file is copied directly to the staging directory and should be in the format: `blocklist module_name`

### VENDOR_DLKM_PROPS
Location (relative to the repo root directory) of a text file containing the properties to be used for creation of a vendor_dlkm image (filesystem, partition size, etc).  
If this is not set (and VENDOR_DLKM_MODULES_LIST is), a default set of properties will be used which assumes an ext4 filesystem and a dynamic partition.

### USE_ABI_PROP
If defined, `abi.prop` will be generated in [DIST_DIR](#dist_dir) during build

### LEGACY_BUILD
To ensure compatibility with different kernels, some options are disabled by default. Set this variable will enable `GENERATE_TEST_MAPPINGS`, `USE_ABI_PROP`

## GKI-related options
### ABI_DEFINITION
Location of the abi definition file relative to <REPO_ROOT>/KERNEL_DIR
If defined (usually in build.config), also copy that abi definition to
<OUT_DIR>/dist/abi.xml when creating the distribution.

### KMI_SYMBOL_LIST
Location of the main KMI symbol list file relative to
<REPO_ROOT>/KERNEL_DIR If defined (usually in build.config), also copy
that symbol list definition to <OUT_DIR>/dist/abi_symbollist when
creating the distribution.

### ADDITIONAL_KMI_SYMBOL_LISTS
Location of secondary KMI symbol list files relative to
<REPO_ROOT>/KERNEL_DIR. If defined, these additional symbol lists will be appended to the main one before proceeding to the distribution creation.

### TRIM_NONLISTED_KMI
if set to "1", enable the CONFIG_UNUSED_KSYMS_WHITELIST kernel config option to un-export from the build any un-used and non-symbol-listed (as per KMI_SYMBOL_LIST) symbol.

### KMI_ENFORCED
This is an indicative option to signal that KMI is enforced in this build config. If set to "1", downstream KMI checking tools might respect it and react to it by failing if KMI differences are detected.

### KMI_SYMBOL_LIST_STRICT_MODE
if set to "1", add a build-time check between the KMI_SYMBOL_LIST and the KMI resulting from the build, to ensure they match 1-1.

### KMI_STRICT_MODE_OBJECTS
optional list of objects to consider for the KMI_SYMBOL_LIST_STRICT_MODE check. Defaults to 'vmlinux'.

### GKI_DIST_DIR
optional directory from which to copy GKI artifacts into DIST_DIR

### GKI_BUILD_CONFIG
- If set, builds a second set of kernel images using GKI_BUILD_CONFIG to perform a "mixed build."  
Mixed builds creates "GKI kernel" and "vendor modules" from two different trees.  
- The GKI kernel tree can be the Android Common Kernel and the vendor modules tree can be a complete vendor kernel tree.  
GKI_DIST_DIR (above) is set and the GKI kernel's DIST output is copied to this DIST output.  
This allows a vendor tree kernel image to be effectively discarded and a GKI kernel Image used from an Android Common Kernel.  
Any variables prefixed with GKI_ are passed into into the GKI kernel's build.sh invocation.  

This is incompatible with GKI_PREBUILTS_DIR.

### GKI_PREBUILTS_DIR
If set, copies an existing set of GKI kernel binaries to the DIST_DIR to
perform a "mixed build," as with GKI_BUILD_CONFIG. This allows you to
skip the additional compilation, if interested.

This is incompatible with GKI_BUILD_CONFIG.

The following must be present:
vmlinux
System.map
vmlinux.symvers
modules.builtin
modules.builtin.modinfo
Image.lz4

### GKI_MODULES_LIST
location of an optional file containing the list of GKI modules, relative to the kernel source tree.  
This should be set in downstream builds to ensure the ABI tooling correctly differentiates vendor/OEM modules and GKI modules.  
This should not be set in the upstream GKI build.config.

### BUILD_GKI_CERTIFICATION_TOOLS
If set to "1", build a gki_certification_tools.tar.gz, which contains the utilities used to certify GKI boot-*.img files.

### BUILD_GKI_ARTIFACTS 

- if defined when `$ARCH` is arm64, build a boot-img.tar.gz archive that contains several GKI `boot-*.img` files with different kernel compression format.  
Each boot image contains a boot header v4 as per the format defined by https://source.android.com/devices/bootloader/boot-image-header, followed by a kernel (no ramdisk).  
The kernel binaries are from `${DIST_DIR}`, e.g., Image, Image.gz, Image.lz4, etc.  
Individual boot-*.img files are also generated, e.g., `boot.img`, `boot-gz.img` and `boot-lz4.img`. It is expected that all components are present in `${DIST_DIR}`.  

- if defined when `$ARCH` is x86_64, build a boot.img with the kernel image,
bzImage under `${DIST_DIR}`. Additionally, create an archive boot-img.tar.gz
containing boot.img.

- if defined when `$ARCH` is neither arm64 nor x86_64, print an error message then exist the build process.

When the **BUILD_GKI_ARTIFACTS** flag is defined, the following flags also need to be defined.
- **MKBOOTIMG_PATH**=`<path to the mkbootimg.py script which builds boot.img>` 
(defaults to tools/mkbootimg/mkbootimg.py)
- **BUILD_GKI_BOOT_IMG_SIZE**=`<The size of the boot.img to build>`   
This is required, and the file ${DIST_DIR}/Image must exist. 
- **BUILD_GKI_BOOT_IMG_GZ_SIZE**=`<The size of the boot-gz.img to build>`  
This is required only when ${DIST_DIR}/Image.gz is present.
- **BUILD_GKI_BOOT_IMG_LZ4_SIZE**=`<The size of the boot-lz4.img to build>`  
This is required only when ${DIST_DIR}/Image.lz4 is present.  
- **BUILD_GKI_BOOT_IMG_<COMPRESSION>_SIZE**=`<The size of the boot-${compression}.img to build>`  
This is required only when `${DIST_DIR}/Image.${compression}` is present.

## Post-build operations

### BUILD_BOOT_IMG
If defined, build a boot.img binary that can be flashed into the 'boot' partition of an Android device.  
The boot image contains a header as per the format defined by https://source.android.com/devices/bootloader/boot-image-header followed by several components like kernel, ramdisk, DTB etc.  
The ramdisk component comprises of a GKI ramdisk cpio archive concatenated with a vendor ramdisk cpio archive which is then gzipped. It is expected that all components are present in ${DIST_DIR}.

When the BUILD_BOOT_IMG flag is defined, the following flags that point to the various components needed to build a boot.img also need to be defined. 
- MKBOOTIMG_PATH=`<path to the mkbootimg.py script which builds boot.img>`  
(defaults to tools/mkbootimg/mkbootimg.py)
- GKI_RAMDISK_PREBUILT_BINARY=`<Name of the GKI ramdisk prebuilt which includes the generic ramdisk components like init and the non-device-specific rc files>`
- VENDOR_RAMDISK_BINARY= `<space separated list of vendor ramdisk binaries which includes the device-specific components of ramdisk like the fstab file and the device-specific rc files.>`  
If specifying multiple vendor ramdisks and identical file paths exist in the ramdisks, the file from last ramdisk is used.
- KERNEL_BINARY=`<name of kernel binary, eg. Image.lz4, Image.gz etc>`
- BOOT_IMAGE_HEADER_VERSION=`<version of the boot image header>` (defaults to 3)
- BOOT_IMAGE_FILENAME=`<name of the output file>` (defaults to "boot.img")
- KERNEL_CMDLINE=`<string of kernel parameters for boot>`
- KERNEL_VENDOR_CMDLINE=`<string of kernel parameters for vendor boot image, vendor_boot when BOOT_IMAGE_HEADER_VERSION >= 3; boot otherwise>`
- VENDOR_FSTAB=`<Path to the vendor fstab to be included in the vendor ramdisk>`
- TAGS_OFFSET=`<physical address for kernel tags>`
- RAMDISK_OFFSET=`<ramdisk physical load address>`
If the BOOT_IMAGE_HEADER_VERSION is less than 3, two additional variables must be defined:  
    - BASE_ADDRESS=`<base address to load the kernel at>`  
    - PAGE_SIZE=`<flash page size>`

If BOOT_IMAGE_HEADER_VERSION >= 3, a vendor_boot image will be built unless `SKIP_VENDOR_BOOT` is defined. A vendor_boot will also be generated if `BUILD_VENDOR_BOOT_IMG` is set.

`BUILD_VENDOR_BOOT_IMG` is incompatible with `SKIP_VENDOR_BOOT`, and is effectively a no-op if `BUILD_BOOT_IMG` is set.

- MODULES_LIST=`<file to list of modules>`  
list of modules to use for vendor_boot.modules.load. If this property is not set, then the default modules.load is used.  
- TRIM_UNUSED_MODULES  
If set, then modules not mentioned in modules.load are removed from initramfs.  
If MODULES_LIST is unset, then having this variable set effectively becomes a no-op.
- MODULES_BLOCKLIST=`<modules.blocklist file>`  
A list of modules which are blocked from being loaded. This file is copied directly to staging directory, and should be in the format: `blocklist module_name`
- MKBOOTIMG_EXTRA_ARGS=`<space-delimited mkbootimg arguments>`  
Refer to: `./mkbootimg.py --help`  

If BOOT_IMAGE_HEADER_VERSION >= 4, the following variable can be defined:
- VENDOR_BOOTCONFIG=`<string of bootconfig parameters>`  
- INITRAMFS_VENDOR_RAMDISK_FRAGMENT_NAME`=<name of the ramdisk fragment>`  
If `BUILD_INITRAMFS` is specified, then build the `.ko` and depmod files as a standalone vendor ramdisk fragment named as the given string.  
- INITRAMFS_VENDOR_RAMDISK_FRAGMENT_MKBOOTIMG_ARGS=`<mkbootimg arguments>`  
Refer to: https://source.android.com/devices/bootloader/partitions/vendor-boot-partitions#mkbootimg-arguments


### VENDOR_RAMDISK_CMDS
When building vendor boot image, VENDOR_RAMDISK_CMDS enables the build config file to specify command(s) for further altering the prebuilt vendor ramdisk binary. For example, the build config file could add firmware files on the vendor ramdisk (lib/firmware) for testing purposes.

### SKIP_UNPACKING_RAMDISK
If set, skip unpacking the vendor ramdisk and copy it as is, without modifications, into the boot image. Also skip the mkbootfs step.

### AVB_SIGN_BOOT_IMG
if defined, sign the boot image using the `AVB_BOOT_KEY`. Refer to
https://android.googlesource.com/platform/external/avb/+/master/README.md for details on what Android Verified Boot is and how it works. The kernel prebuilt tool `avbtool` is used for signing.

When AVB_SIGN_BOOT_IMG is defined, the following flags need to be defined:
- AVB_BOOT_PARTITION_SIZE=`<size of the boot partition in bytes>`
- AVB_BOOT_KEY=`<absolute path to the key used for signing>`  
The Android test key has been uploaded to the kernel/prebuilts/build-tools project here:  
https://android.googlesource.com/kernel/prebuilts/build-tools/+/refs/heads/master/linux-x86/share/avb
- AVB_BOOT_ALGORITHM=`<AVB_BOOT_KEY algorithm used>` e.g. SHA256_RSA2048.  
For the full list of supported algorithms, refer to the enum `AvbAlgorithmType` in https://android.googlesource.com/platform/external/avb/+/refs/heads/master/libavb/avb_crypto.h
- AVB_BOOT_PARTITION_NAME=`<name of the boot partition>` 
(defaults to BOOT_IMAGE_FILENAME without extension; by default, "boot")

### BUILD_VENDOR_KERNEL_BOOT
If set to "1", build a vendor_kernel_boot for kernel artifacts, such as kernel modules.  
Since we design this partition to isolate kernel artifacts from vendor_boot image, vendor_boot would not be repack and built if we set this property to "1".

### BUILD_DTBO_IMG
if defined, package a dtbo.img using the provided *.dtbo files. The image will be created under the DIST_DIR.

The following flags control how the dtbo image is packaged:
- MKDTIMG_DTBOS=`<list of dtbo files>` used to package the dtbo.img.  
The `*.dtbo` files should be compiled by kbuild via the "make dtbs" command or by adding each *.dtbo to the MAKE_GOALS.  
- MKDTIMG_FLAGS=`<list of flags to be passed to mkdtimg.>`

### DTS_EXT_DIR
Set this variable to compile an out-of-tree device tree.  
The value of this variable is set to the kbuild variable "dtstree" which is used to compile the device tree, it will be used to lookup files in `FILES` as well.  
If this is set, then it's likely the dt-bindings are out-of-tree as well. So be sure to set `DTC_INCLUDE` in the `BUILD_CONFIG` file to the include path containing the dt-bindings.  
Update the `MAKE_GOALS` variable and the `FILES` variable to specify the target dtb files with the path under `${DTS_EXT_DIR}`, so that they could be compiled and copied to the dist directory. Like the following:  
```
DTS_EXT_DIR=common-modules/virtual-device
MAKE_GOALS="${MAKE_GOALS} k3399-rock-pi-4b.dtb"
FILES="${FILES} rk3399-rock-pi-4b.dtb"
```  
where the dts file path is
common-modules/virtual-device/rk3399-rock-pi-4b.dts

### GENERATE_TEST_MAPPINGS
If defined, generate `test_mappings.zip` file in [DIST_DIR](#dist_dir)
