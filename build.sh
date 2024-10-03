#!/bin/bash

# Copyright (C) 2019 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Usage:
#   build/build.sh <make options>*
# or:
#   To define custom out and dist directories:
#     OUT_DIR=<out dir> DIST_DIR=<dist dir> build/build.sh <make options>*
#   To use a custom build config:
#     BUILD_CONFIG=<path to the build.config> <make options>*
#
# Examples:
#   To define custom out and dist directories:
#     OUT_DIR=output DIST_DIR=dist build/build.sh -j24 V=1
#   To use a custom build config:
#     BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh -j24 V=1
#
# Note: For historic reasons, internally, OUT_DIR will be copied into
# COMMON_OUT_DIR, and OUT_DIR will be then set to
# ${COMMON_OUT_DIR}/${KERNEL_DIR}. This has been done to accommodate existing
# build.config files that expect ${OUT_DIR} to point to the output directory of
# the kernel build.
#
# The kernel is built in ${COMMON_OUT_DIR}/${KERNEL_DIR}.
# Out-of-tree modules are built in ${COMMON_OUT_DIR}/${EXT_MOD} where
# ${EXT_MOD} is the path to the module source code.

set -e

# Save environment for mixed build support.
OLD_ENVIRONMENT=$(mktemp)
export -p > ${OLD_ENVIRONMENT}

export ROOT_DIR=$(pwd)
source "${ROOT_DIR}/build/build_utils.sh"
source "${ROOT_DIR}/build/_setup_env.sh"

MAKE_ARGS=( "$@" )
export MAKEFLAGS="-j$(nproc) ${MAKEFLAGS}"
export MODULES_STAGING_DIR=$(readlink -m ${COMMON_OUT_DIR}/staging)
export MODULES_PRIVATE_DIR=$(readlink -m ${COMMON_OUT_DIR}/private)
export KERNEL_UAPI_HEADERS_DIR=$(readlink -m ${COMMON_OUT_DIR}/kernel_uapi_headers)
export INITRAMFS_STAGING_DIR=${MODULES_STAGING_DIR}/initramfs_staging
export SYSTEM_DLKM_STAGING_DIR=${MODULES_STAGING_DIR}/system_dlkm_staging
export VENDOR_DLKM_STAGING_DIR=${MODULES_STAGING_DIR}/vendor_dlkm_staging
export MKBOOTIMG_STAGING_DIR="${MODULES_STAGING_DIR}/mkbootimg_staging"

if [ -n "${SKIP_VENDOR_BOOT}" -a -n "${BUILD_VENDOR_BOOT_IMG}" ]; then
  echo "ERROR: SKIP_VENDOR_BOOT is incompatible with BUILD_VENDOR_BOOT_IMG." >&2
  exit 1
fi

if [ -n "${GKI_BUILD_CONFIG}" ]; then
  if [ -n "${GKI_PREBUILTS_DIR}" ]; then
      echo "ERROR: GKI_BUILD_CONFIG is incompatible with GKI_PREBUILTS_DIR." >&2
      exit 1
  fi

  GKI_OUT_DIR=${GKI_OUT_DIR:-${COMMON_OUT_DIR}/gki_kernel}
  GKI_DIST_DIR=${GKI_DIST_DIR:-${GKI_OUT_DIR}/dist}

  if [[ "${MAKE_GOALS}" =~ image|Image|vmlinux ]]; then
    echo " Compiling Image and vmlinux in device kernel is not supported in mixed build mode"
    exit 1
  fi

  # Inherit SKIP_MRPROPER, LTO, SKIP_DEFCONFIG unless overridden by corresponding GKI_* variables
  GKI_ENVIRON=("SKIP_MRPROPER=${SKIP_MRPROPER}" "LTO=${LTO}" "SKIP_DEFCONFIG=${SKIP_DEFCONFIG}" "SKIP_IF_VERSION_MATCHES=${SKIP_IF_VERSION_MATCHES}")
  # Explicitly unset EXT_MODULES since they should be compiled against the device kernel
  GKI_ENVIRON+=("EXT_MODULES=")
  # Explicitly unset GKI_BUILD_CONFIG in case it was set by in the old environment
  # e.g. GKI_BUILD_CONFIG=common/build.config.gki.x86 ./build/build.sh would cause
  # gki build recursively
  GKI_ENVIRON+=("GKI_BUILD_CONFIG=")
  # Explicitly unset KCONFIG_EXT_PREFIX in case it was set by the older environment.
  GKI_ENVIRON+=("KCONFIG_EXT_PREFIX=")
  # Any variables prefixed with GKI_ get set without that prefix in the GKI build environment
  # e.g. GKI_BUILD_CONFIG=common/build.config.gki.aarch64 -> BUILD_CONFIG=common/build.config.gki.aarch64
  GKI_ENVIRON+=($(export -p | sed -n -E -e 's/.* GKI_([^=]+=.*)$/\1/p' | tr '\n' ' '))
  GKI_ENVIRON+=("OUT_DIR=${GKI_OUT_DIR}")
  GKI_ENVIRON+=("DIST_DIR=${GKI_DIST_DIR}")
  ( env -i bash -c "source ${OLD_ENVIRONMENT}; rm -f ${OLD_ENVIRONMENT}; export ${GKI_ENVIRON[*]} ; ./build/build.sh $*" ) || exit 1

  # Dist dir must have vmlinux.symvers, modules.builtin.modinfo, modules.builtin
  MAKE_ARGS+=("KBUILD_MIXED_TREE=$(readlink -m ${GKI_DIST_DIR})")
else
  rm -f ${OLD_ENVIRONMENT}
fi

if [ -n "${KCONFIG_EXT_PREFIX}" ]; then
  # Since this is a prefix, make sure it ends with "/"
  if [[ ! "${KCONFIG_EXT_PREFIX}" =~ \/$ ]]; then
    KCONFIG_EXT_PREFIX=${KCONFIG_EXT_PREFIX}/
  fi

  # KCONFIG_EXT_PREFIX needs to be relative to KERNEL_DIR but we allow one to set
  # it relative to ROOT_DIR for ease of use. So figure out what was used.
  if [ -f "${ROOT_DIR}/${KCONFIG_EXT_PREFIX}Kconfig.ext" ]; then
    # KCONFIG_EXT_PREFIX is currently relative to ROOT_DIR. So recalculate it to be
    # relative to KERNEL_DIR
    KCONFIG_EXT_PREFIX=$(realpath ${ROOT_DIR}/${KCONFIG_EXT_PREFIX} --relative-to ${KERNEL_DIR})
  elif [ ! -f "${KERNEL_DIR}/${KCONFIG_EXT_PREFIX}Kconfig.ext" ]; then
    echo "Couldn't find the Kconfig.ext in ${KCONFIG_EXT_PREFIX}" >&2
    exit 1
  fi

  # Since this is a prefix, make sure it ends with "/"
  if [[ ! "${KCONFIG_EXT_PREFIX}" =~ \/$ ]]; then
    KCONFIG_EXT_PREFIX=${KCONFIG_EXT_PREFIX}/
  fi
  MAKE_ARGS+=("KCONFIG_EXT_PREFIX=${KCONFIG_EXT_PREFIX}")
fi

if [ -n "${DTS_EXT_DIR}" ]; then
  if [[ "${MAKE_GOALS}" =~ dtbs|\.dtb|\.dtbo ]]; then
    # DTS_EXT_DIR needs to be relative to KERNEL_DIR but we allow one to set
    # it relative to ROOT_DIR for ease of use. So figure out what was used.
    if [ -d "${ROOT_DIR}/${DTS_EXT_DIR}" ]; then
      # DTS_EXT_DIR is currently relative to ROOT_DIR. So recalcuate it to be
      # relative to KERNEL_DIR
      DTS_EXT_DIR=$(realpath ${ROOT_DIR}/${DTS_EXT_DIR} --relative-to ${KERNEL_DIR})
    elif [ ! -d "${KERNEL_DIR}/${DTS_EXT_DIR}" ]; then
      echo "Couldn't find the dtstree -- ${DTS_EXT_DIR}" >&2
      exit 1
    fi
    MAKE_ARGS+=("dtstree=${DTS_EXT_DIR}")
  fi
fi

cd ${ROOT_DIR}

if [ -n "${SKIP_IF_VERSION_MATCHES}" ]; then
  if [ -f "${DIST_DIR}/vmlinux" ]; then
    kernelversion="$(cd ${KERNEL_DIR} && make -s ${TOOL_ARGS} O=${OUT_DIR} kernelrelease)"
    # Split grep into 2 steps. "Linux version" will always be towards top and fast to find. Don't
    # need to search the entire vmlinux for it
    if [[ ! "$kernelversion" =~ .*dirty.* ]] && \
       grep -o -a -m1 "Linux version [^ ]* " ${DIST_DIR}/vmlinux | grep -q " ${kernelversion} " ; then
      echo "========================================================"
      echo " Skipping build because kernel version matches ${kernelversion}"
      exit 0
    fi
  fi
fi

mkdir -p ${OUT_DIR} ${DIST_DIR}

if [ -n "${GKI_PREBUILTS_DIR}" ]; then
  echo "========================================================"
  echo " Copying GKI prebuilts"
  GKI_PREBUILTS_DIR=$(readlink -m ${GKI_PREBUILTS_DIR})
  if [ ! -d "${GKI_PREBUILTS_DIR}" ]; then
    echo "ERROR: ${GKI_PREBULTS_DIR} does not exist." >&2
    exit 1
  fi
  for file in ${GKI_PREBUILTS_DIR}/*; do
    filename=$(basename ${file})
    if ! $(cmp -s ${file} ${DIST_DIR}/${filename}); then
      cp -v ${file} ${DIST_DIR}/${filename}
    fi
  done
  MAKE_ARGS+=("KBUILD_MIXED_TREE=${GKI_PREBUILTS_DIR}")
fi

echo "========================================================"
echo " Setting up for build"
if [ "${SKIP_MRPROPER}" != "1" ] ; then
  set -x
  (cd ${KERNEL_DIR} && make ${TOOL_ARGS} O=${OUT_DIR} "${MAKE_ARGS[@]}" mrproper)
  set +x
fi

if [ -n "${PRE_DEFCONFIG_CMDS}" ]; then
  echo "========================================================"
  echo " Running pre-defconfig command(s):"
  set -x
  eval ${PRE_DEFCONFIG_CMDS}
  set +x
fi

if [ "${SKIP_DEFCONFIG}" != "1" ] ; then
  set -x
  (cd ${KERNEL_DIR} && make ${TOOL_ARGS} O=${OUT_DIR} "${MAKE_ARGS[@]}" ${DEFCONFIG})
  set +x

  if [ -n "${POST_DEFCONFIG_CMDS}" ]; then
    echo "========================================================"
    echo " Running pre-make command(s):"
    set -x
    eval ${POST_DEFCONFIG_CMDS}
    set +x
  fi
fi

if [[ ! "${CC}" = *"gcc"* ]]; then
if [ "${LTO}" = "none" -o "${LTO}" = "thin" -o "${LTO}" = "full" ]; then
  echo "========================================================"
  echo " Modifying LTO mode to '${LTO}'"

  set -x
  if [ "${LTO}" = "none" ]; then
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config \
      -d LTO_CLANG \
      -e LTO_NONE \
      -d LTO_CLANG_THIN \
      -d LTO_CLANG_FULL \
      -d THINLTO \
      --set-val FRAME_WARN 0
  elif [ "${LTO}" = "thin" ]; then
    # This is best-effort; some kernels don't support LTO_THIN mode
    # THINLTO was the old name for LTO_THIN, and it was 'default y'
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config \
      -e LTO_CLANG \
      -d LTO_NONE \
      -e LTO_CLANG_THIN \
      -d LTO_CLANG_FULL \
      -e THINLTO
  elif [ "${LTO}" = "full" ]; then
    # THINLTO was the old name for LTO_THIN, and it was 'default y'
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config \
      -e LTO_CLANG \
      -d LTO_NONE \
      -d LTO_CLANG_THIN \
      -e LTO_CLANG_FULL \
      -d THINLTO
  fi
  (cd ${OUT_DIR} && make ${TOOL_ARGS} O=${OUT_DIR} "${MAKE_ARGS[@]}" olddefconfig)
  set +x
elif [ -n "${LTO}" ]; then
  echo "LTO= must be one of 'none', 'thin' or 'full'."
  exit 1
fi
fi

if [ -n "${TAGS_CONFIG}" ]; then
  echo "========================================================"
  echo " Running tags command:"
  set -x
  (cd ${KERNEL_DIR} && SRCARCH=${ARCH} ./scripts/tags.sh ${TAGS_CONFIG})
  set +x
  exit 0
fi

if [ -n "${LEGACY_BUILD}" ]; then
  GENERATE_TEST_MAPPINGS=1
  USE_ABI_PROP=1
fi

# Truncate abi.prop file
if [ -n "${USE_ABI_PROP}" ]; then
  ABI_PROP=${DIST_DIR}/abi.prop
else
  ABI_PROP=/dev/null
fi

: > ${ABI_PROP}

if [ -n "${ABI_DEFINITION}" ]; then

  ABI_XML=${DIST_DIR}/abi.xml

  echo "KMI_DEFINITION=abi.xml" >> ${ABI_PROP}
  echo "KMI_MONITORED=1"        >> ${ABI_PROP}

  if [ "${KMI_ENFORCED}" = "1" ]; then
    echo "KMI_ENFORCED=1" >> ${ABI_PROP}
  fi
fi

if [ -n "${KMI_SYMBOL_LIST}" ]; then
  ABI_SL=${DIST_DIR}/abi_symbollist
  echo "KMI_SYMBOL_LIST=abi_symbollist" >> ${ABI_PROP}
fi

# define the kernel binary and modules archive in the $ABI_PROP
echo "KERNEL_BINARY=vmlinux" >> ${ABI_PROP}
if [ "${COMPRESS_UNSTRIPPED_MODULES}" = "1" ]; then
  echo "MODULES_ARCHIVE=${UNSTRIPPED_MODULES_ARCHIVE}" >> ${ABI_PROP}
fi

# Copy the abi_${arch}.xml file from the sources into the dist dir
if [ -n "${ABI_DEFINITION}" ]; then
  echo "========================================================"
  echo " Copying abi definition to ${ABI_XML}"
  pushd $ROOT_DIR/$KERNEL_DIR
    cp "${ABI_DEFINITION}" ${ABI_XML}
  popd
fi

# Copy the abi symbol list file from the sources into the dist dir
if [ -n "${KMI_SYMBOL_LIST}" ]; then
  ${ROOT_DIR}/build/abi/process_symbols --out-dir="$DIST_DIR" --out-file=abi_symbollist \
    --report-file=abi_symbollist.report --in-dir="$ROOT_DIR/$KERNEL_DIR" \
    "${KMI_SYMBOL_LIST}" ${ADDITIONAL_KMI_SYMBOL_LISTS} --verbose
  pushd $ROOT_DIR/$KERNEL_DIR
  if [ "${TRIM_NONLISTED_KMI}" = "1" ]; then
      # Create the raw symbol list
      cat ${ABI_SL} | \
              ${ROOT_DIR}/build/abi/flatten_symbol_list > \
              ${OUT_DIR}/abi_symbollist.raw

      # Update the kernel configuration
      ./scripts/config --file ${OUT_DIR}/.config \
              -d UNUSED_SYMBOLS -e TRIM_UNUSED_KSYMS \
              --set-str UNUSED_KSYMS_WHITELIST ${OUT_DIR}/abi_symbollist.raw
      (cd ${OUT_DIR} && \
              make O=${OUT_DIR} ${TOOL_ARGS} "${MAKE_ARGS[@]}" olddefconfig)
      # Make sure the config is applied
      grep CONFIG_UNUSED_KSYMS_WHITELIST ${OUT_DIR}/.config > /dev/null || {
        echo "ERROR: Failed to apply TRIM_NONLISTED_KMI kernel configuration" >&2
        echo "Does your kernel support CONFIG_UNUSED_KSYMS_WHITELIST?" >&2
        exit 1
      }

    elif [ "${KMI_SYMBOL_LIST_STRICT_MODE}" = "1" ]; then
      echo "ERROR: KMI_SYMBOL_LIST_STRICT_MODE requires TRIM_NONLISTED_KMI=1" >&2
    exit 1
  fi
  popd # $ROOT_DIR/$KERNEL_DIR
elif [ "${TRIM_NONLISTED_KMI}" = "1" ]; then
  echo "ERROR: TRIM_NONLISTED_KMI requires a KMI_SYMBOL_LIST" >&2
  exit 1
elif [ "${KMI_SYMBOL_LIST_STRICT_MODE}" = "1" ]; then
  echo "ERROR: KMI_SYMBOL_LIST_STRICT_MODE requires a KMI_SYMBOL_LIST" >&2
  exit 1
fi

echo "========================================================"
echo " Building kernel"
echo "        $(kernelrelease)"
echo
set -x
(cd ${OUT_DIR} && make O=${OUT_DIR} ${TOOL_ARGS} "${MAKE_ARGS[@]}" ${MAKE_GOALS})
set +x

if [ -n "${POST_KERNEL_BUILD_CMDS}" ]; then
  echo "========================================================"
  echo " Running post-kernel-build command(s):"
  set -x
  eval ${POST_KERNEL_BUILD_CMDS}
  set +x
fi

if [ -n "${MODULES_ORDER}" ]; then
  echo "========================================================"
  echo " Checking the list of modules:"
  if ! diff -u "${KERNEL_DIR}/${MODULES_ORDER}" "${OUT_DIR}/modules.order"; then
    echo "ERROR: modules list out of date" >&2
    echo "Update it with:" >&2
    echo "cp ${OUT_DIR}/modules.order ${KERNEL_DIR}/${MODULES_ORDER}" >&2
    exit 1
  fi
fi

if [ "${KMI_SYMBOL_LIST_STRICT_MODE}" = "1" ]; then
  echo "========================================================"
  echo " Comparing the KMI and the symbol lists:"
  set -x

  gki_modules_list="${KERNEL_DIR}/android/gki_system_dlkm_modules"
  KMI_STRICT_MODE_OBJECTS="vmlinux $(sed 's/\.ko$//' ${gki_modules_list} | tr '\n' ' ')" \
    ${ROOT_DIR}/build/abi/compare_to_symbol_list "${OUT_DIR}/Module.symvers"             \
    "${OUT_DIR}/abi_symbollist.raw"
  set +x
fi

rm -rf ${MODULES_STAGING_DIR}
mkdir -p ${MODULES_STAGING_DIR}

if [ "${DO_NOT_STRIP_MODULES}" != "1" ]; then
  MODULE_STRIP_FLAG="INSTALL_MOD_STRIP=1"
fi

if [ "${BUILD_INITRAMFS}" = "1" -o  -n "${IN_KERNEL_MODULES}" ]; then
  echo "========================================================"
  echo " Installing kernel modules into staging directory"

  (cd ${OUT_DIR} &&                                                           \
   make O=${OUT_DIR} ${TOOL_ARGS} ${MODULE_STRIP_FLAG}                        \
        INSTALL_MOD_PATH=${MODULES_STAGING_DIR} "${MAKE_ARGS[@]}" modules_install)
fi

if [[ -z "${SKIP_EXT_MODULES}" ]] && [[ -n "${EXT_MODULES_MAKEFILE}" ]]; then
  echo "========================================================"
  echo " Building and installing external modules using ${EXT_MODULES_MAKEFILE}"

  make -f "${EXT_MODULES_MAKEFILE}" KERNEL_SRC=${KERNEL_DIR} \
          O=${OUT_DIR} ${TOOL_ARGS} ${MODULE_STRIP_FLAG}                 \
          INSTALL_HDR_PATH="${KERNEL_UAPI_HEADERS_DIR}/usr"              \
          INSTALL_MOD_PATH=${MODULES_STAGING_DIR} "${MAKE_ARGS[@]}"
fi

if [[ -z "${SKIP_EXT_MODULES}" ]] && [[ -n "${EXT_MODULES}" ]]; then
  echo "========================================================"
  echo " Building external modules and installing them into staging directory"

  for EXT_MOD in ${EXT_MODULES}; do
    # The path that we pass in via the variable M needs to be a relative path
    # relative to the kernel source directory. The source files will then be
    # looked for in ${KERNEL_DIR}/${EXT_MOD_REL} and the object files (i.e. .o
    # and .ko) files will be stored in ${OUT_DIR}/${EXT_MOD_REL}. If we
    # instead set M to an absolute path, then object (i.e. .o and .ko) files
    # are stored in the module source directory which is not what we want.
    EXT_MOD_REL=$(realpath ${ROOT_DIR}/${EXT_MOD} --relative-to ${KERNEL_DIR})
    # The output directory must exist before we invoke make. Otherwise, the
    # build system behaves horribly wrong.
    mkdir -p ${OUT_DIR}/${EXT_MOD_REL}
    set -x
    make -C ${EXT_MOD} M=${EXT_MOD_REL} KERNEL_SRC=${KERNEL_DIR}  \
                       O=${OUT_DIR} ${TOOL_ARGS} "${MAKE_ARGS[@]}"
    make -C ${EXT_MOD} M=${EXT_MOD_REL} KERNEL_SRC=${KERNEL_DIR}  \
                       O=${OUT_DIR} ${TOOL_ARGS} ${MODULE_STRIP_FLAG}         \
                       INSTALL_MOD_PATH=${MODULES_STAGING_DIR}                \
                       INSTALL_MOD_DIR="extra/${EXT_MOD}"                     \
                       INSTALL_HDR_PATH="${KERNEL_UAPI_HEADERS_DIR}/usr"      \
                       "${MAKE_ARGS[@]}" modules_install
    set +x
  done

fi

if [ "${BUILD_GKI_CERTIFICATION_TOOLS}" = "1"  ]; then
  GKI_CERTIFICATION_TOOLS_TAR="gki_certification_tools.tar.gz"
  echo "========================================================"
  echo " Generating ${GKI_CERTIFICATION_TOOLS_TAR}"
  GKI_CERTIFICATION_BINARIES=(avbtool certify_bootimg)
  GKI_CERTIFICATION_TOOLS_ROOT="${ROOT_DIR}/prebuilts/kernel-build-tools/linux-x86"
  GKI_CERTIFICATION_FILES="${GKI_CERTIFICATION_BINARIES[@]/#/bin/}"
  tar -czf ${DIST_DIR}/${GKI_CERTIFICATION_TOOLS_TAR} \
    -C ${GKI_CERTIFICATION_TOOLS_ROOT} ${GKI_CERTIFICATION_FILES}
fi

if [ -n "${GENERATE_TEST_MAPPINGS}" ]; then 
echo "========================================================"
echo " Generating test_mappings.zip"
TEST_MAPPING_FILES=${OUT_DIR}/test_mapping_files.txt
find ${ROOT_DIR} -name TEST_MAPPING \
  -not -path "${ROOT_DIR}/\.git*" \
  -not -path "${ROOT_DIR}/\.repo*" \
  -not -path "${ROOT_DIR}/out*" \
  > ${TEST_MAPPING_FILES}
soong_zip -o ${DIST_DIR}/test_mappings.zip -C ${ROOT_DIR} -l ${TEST_MAPPING_FILES}
fi

if [ -n "${EXTRA_CMDS}" ]; then
  echo "========================================================"
  echo " Running extra build command(s):"
  set -x
  eval ${EXTRA_CMDS}
  set +x
fi

OVERLAYS_OUT=""
for ODM_DIR in ${ODM_DIRS}; do
  OVERLAY_DIR=${ROOT_DIR}/device/${ODM_DIR}/overlays

  if [ -d ${OVERLAY_DIR} ]; then
    OVERLAY_OUT_DIR=${OUT_DIR}/overlays/${ODM_DIR}
    mkdir -p ${OVERLAY_OUT_DIR}
    make -C ${OVERLAY_DIR} DTC=${OUT_DIR}/scripts/dtc/dtc                     \
                           OUT_DIR=${OVERLAY_OUT_DIR} "${MAKE_ARGS[@]}"
    OVERLAYS=$(find ${OVERLAY_OUT_DIR} -name "*.dtbo")
    OVERLAYS_OUT="$OVERLAYS_OUT $OVERLAYS"
  fi
done

echo "========================================================"
echo " Copying files"
for FILE in ${FILES}; do
  if [ -f ${OUT_DIR}/${FILE} ]; then
    echo "  $FILE"
    cp -p ${OUT_DIR}/${FILE} ${DIST_DIR}/
  elif [[ "${FILE}" =~ \.dtb|\.dtbo ]]  && \
      [ -n "${DTS_EXT_DIR}" ] && [ -f "${OUT_DIR}/${DTS_EXT_DIR}/${FILE}" ] ; then
    # DTS_EXT_DIR is recalculated before to be relative to KERNEL_DIR
    echo "  $FILE"
    cp -p "${OUT_DIR}/${DTS_EXT_DIR}/${FILE}" "${DIST_DIR}/"
  else
    echo "  $FILE is not a file, skipping"
  fi
done

if [ -f ${OUT_DIR}/vmlinux-gdb.py ]; then
  echo "========================================================"
  KERNEL_GDB_SCRIPTS_TAR=${DIST_DIR}/kernel-gdb-scripts.tar.gz
  echo " Copying kernel gdb scripts to $KERNEL_GDB_SCRIPTS_TAR"
  (cd $OUT_DIR && tar -czf $KERNEL_GDB_SCRIPTS_TAR --dereference vmlinux-gdb.py scripts/gdb/linux/*.py)
fi

for FILE in ${OVERLAYS_OUT}; do
  OVERLAY_DIST_DIR=${DIST_DIR}/$(dirname ${FILE#${OUT_DIR}/overlays/})
  echo "  ${FILE#${OUT_DIR}/}"
  mkdir -p ${OVERLAY_DIST_DIR}
  cp ${FILE} ${OVERLAY_DIST_DIR}/
done

if [ -z "${SKIP_CP_KERNEL_HDR}" ]; then
  echo "========================================================"
  echo " Installing UAPI kernel headers:"

  if which rsync ; then 
  mkdir -p "${KERNEL_UAPI_HEADERS_DIR}/usr"
  make -C ${OUT_DIR} O=${OUT_DIR} ${TOOL_ARGS}                                \
          INSTALL_HDR_PATH="${KERNEL_UAPI_HEADERS_DIR}/usr" "${MAKE_ARGS[@]}" \
          headers_install
  # The kernel makefiles create files named ..install.cmd and .install which
  # are only side products. We don't want those. Let's delete them.
  find ${KERNEL_UAPI_HEADERS_DIR} \( -name ..install.cmd -o -name .install \) -exec rm '{}' +
  KERNEL_UAPI_HEADERS_TAR=${DIST_DIR}/kernel-uapi-headers.tar.gz
  echo " Copying kernel UAPI headers to ${KERNEL_UAPI_HEADERS_TAR}"
  tar -czf ${KERNEL_UAPI_HEADERS_TAR} --directory=${KERNEL_UAPI_HEADERS_DIR} usr/
  else
    echo "rsync: not found, skipping"
  fi
fi

if [ -z "${SKIP_CP_KERNEL_HDR}" ] ; then
  echo "========================================================"
  KERNEL_HEADERS_TAR=${DIST_DIR}/kernel-headers.tar.gz
  echo " Copying kernel headers to ${KERNEL_HEADERS_TAR}"
  pushd $ROOT_DIR/$KERNEL_DIR
    find arch include $OUT_DIR -name *.h -print0               \
            | tar -czf $KERNEL_HEADERS_TAR                     \
              --absolute-names                                 \
              --dereference                                    \
              --transform "s,.*$OUT_DIR,,"                     \
              --transform "s,^,kernel-headers/,"               \
              --null -T -
  popd
fi

if [ "${GENERATE_VMLINUX_BTF}" = "1" ]; then
  echo "========================================================"
  echo " Generating ${DIST_DIR}/vmlinux.btf"

  (
    cd ${DIST_DIR}
    cp -a vmlinux vmlinux.btf
    pahole -J vmlinux.btf
    llvm-strip --strip-debug vmlinux.btf
  )

fi

if [ -n "${GKI_DIST_DIR}" ]; then
  echo "========================================================"
  echo " Copying files from GKI kernel"
  cp -rv ${GKI_DIST_DIR}/* ${DIST_DIR}/
fi

if [ -n "${DIST_CMDS}" ]; then
  echo "========================================================"
  echo " Running extra dist command(s):"
  # if DIST_CMDS requires UAPI headers, make sure a warning appears!
  if [ ! -d "${KERNEL_UAPI_HEADERS_DIR}/usr" ]; then
    echo "WARN: running without UAPI headers"
  fi
  set -x
  eval ${DIST_CMDS}
  set +x
fi

MODULES=$(find ${MODULES_STAGING_DIR} -type f -name "*.ko")
if [ -n "${MODULES}" ]; then
  if [ -n "${IN_KERNEL_MODULES}" -o -n "${EXT_MODULES}" -o -n "${EXT_MODULES_MAKEFILE}" ]; then
    echo "========================================================"
    echo " Copying modules files"
    cp -p ${MODULES} ${DIST_DIR}
    if [ "${COMPRESS_MODULES}" = "1" ]; then
      echo " Archiving modules to ${MODULES_ARCHIVE}"
      tar --transform="s,.*/,," -czf ${DIST_DIR}/${MODULES_ARCHIVE} ${MODULES[@]}
    fi
  fi
  if [ "${BUILD_INITRAMFS}" = "1" ]; then
    echo "========================================================"
    echo " Creating initramfs"
    rm -rf ${INITRAMFS_STAGING_DIR}
    create_modules_staging "${MODULES_LIST}" ${MODULES_STAGING_DIR} \
      ${INITRAMFS_STAGING_DIR} "${MODULES_BLOCKLIST}" "-e"

    MODULES_ROOT_DIR=$(echo ${INITRAMFS_STAGING_DIR}/lib/modules/*)
    cp ${MODULES_ROOT_DIR}/modules.load ${DIST_DIR}/modules.load
    if [ -n "${BUILD_VENDOR_BOOT_IMG}" ]; then
      cp ${MODULES_ROOT_DIR}/modules.load ${DIST_DIR}/vendor_boot.modules.load
    elif [ -n "${BUILD_VENDOR_KERNEL_BOOT}" ]; then
      cp ${MODULES_ROOT_DIR}/modules.load ${DIST_DIR}/vendor_kernel_boot.modules.load
    fi
    echo "${MODULES_OPTIONS}" > ${MODULES_ROOT_DIR}/modules.options

    mkbootfs "${INITRAMFS_STAGING_DIR}" >"${MODULES_STAGING_DIR}/initramfs.cpio"
    ${RAMDISK_COMPRESS} "${MODULES_STAGING_DIR}/initramfs.cpio" >"${DIST_DIR}/initramfs.img"
  fi
fi

if [ "${BUILD_SYSTEM_DLKM}" = "1"  ]; then
  build_system_dlkm
fi

if [ -n "${VENDOR_DLKM_MODULES_LIST}" ]; then
  build_vendor_dlkm
fi

if [ -n "${UNSTRIPPED_MODULES}" ]; then
  echo "========================================================"
  echo " Copying unstripped module files for debugging purposes (not loaded on device)"
  mkdir -p ${UNSTRIPPED_DIR}
  for MODULE in ${UNSTRIPPED_MODULES}; do
    find ${MODULES_PRIVATE_DIR} -name ${MODULE} -exec cp {} ${UNSTRIPPED_DIR} \;
  done
  if [ "${COMPRESS_UNSTRIPPED_MODULES}" = "1" ]; then
    tar -czf ${DIST_DIR}/${UNSTRIPPED_MODULES_ARCHIVE} -C $(dirname ${UNSTRIPPED_DIR}) $(basename ${UNSTRIPPED_DIR})
    rm -rf ${UNSTRIPPED_DIR}
  fi
fi

[ -n "${GKI_MODULES_LIST}" ] && cp ${KERNEL_DIR}/${GKI_MODULES_LIST} ${DIST_DIR}/

echo "========================================================"
echo " Files copied to ${DIST_DIR}"

if [ -n "${BUILD_BOOT_IMG}" -o -n "${BUILD_VENDOR_BOOT_IMG}" \
      -o -n "${BUILD_VENDOR_KERNEL_BOOT}" ] ; then
  build_boot_images
fi

if [ -n "${BUILD_GKI_ARTIFACTS}" ] ; then
  build_gki_artifacts
fi

if [ -n "${BUILD_DTBO_IMG}" ]; then
  make_dtbo
fi

# No trace_printk use on build server build
if readelf -a ${DIST_DIR}/vmlinux 2>&1 | grep -q trace_printk_fmt; then
  echo "========================================================"
  echo "WARN: Found trace_printk usage in vmlinux."
  echo ""
  echo "trace_printk will cause trace_printk_init_buffers executed in kernel"
  echo "start, which will increase memory and lead warning shown during boot."
  echo "We should not carry trace_printk in production kernel."
  echo ""
  if [ ! -z "${STOP_SHIP_TRACEPRINTK}" ]; then
    echo "ERROR: stop ship on trace_printk usage." 1>&2
    exit 1
  fi
fi
