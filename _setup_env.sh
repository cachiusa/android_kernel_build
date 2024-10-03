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

# This is an implementation detail of Kleaf. Do not source directly as it will
# spoil your shell. You have been warned! If you have a good reason to source
# the result of this file into a shell, please let kernel-team@android.com know
# and we will be happy to help with your use case.

[ -n "$_SETUP_ENV_SH_INCLUDED" ] && return || export _SETUP_ENV_SH_INCLUDED=1

# TODO: Use a $(gettop) style method.
export ROOT_DIR=$(readlink -f $PWD)

case "${LOG}" in
  "") ;;
  "1")  echo "Saving log to ${ROOT_DIR}/build.log"
        exec &> >(tee build.log)
        echo " $(date)" ;;
  *)  echo "Saving log to ${ROOT_DIR}/${LOG}"
      exec &> >(tee ${LOG})
      echo " $(date)"
esac

if [[ -z ${BUILD_CONFIG} ]]; then
  echo "BUILD_CONFIG is not set. Trying to find..."
  . $(dirname $(readlink -f $0))/whereis-config.sh
else
  export BUILD_CONFIG=${BUILD_CONFIG:-build.config}
fi

# Helper function to let build.config files add command to PRE_DEFCONFIG_CMDS, EXTRA_CMDS, etc.
# Usage: append_cmd PRE_DEFCONFIG_CMDS 'the_cmd'
function append_cmd() {
  if [ ! -z "${!1}" ]; then
    eval "$1=\"${!1} && \$2\""
  else
    eval "$1=\"\$2\""
  fi
}
export -f append_cmd

export KERNEL_DIR
# for case that KERNEL_DIR is not specified in environment
if [ -z "${KERNEL_DIR}" ]; then
    # for the case that KERNEL_DIR is not specified in the BUILD_CONFIG file
    # use the directory of the build config file as KERNEL_DIR
    # for the case that KERNEL_DIR is specified in the BUILD_CONFIG file,
    # or via the config files sourced, the value of KERNEL_DIR
    # set here would be overwritten, and the specified value would be used.
    build_config_path=$(readlink -f ${ROOT_DIR}/${BUILD_CONFIG})
    real_root_dir=${build_config_path%%${BUILD_CONFIG}}
    build_config_dir=$(dirname ${build_config_path})
    build_config_dir=${build_config_dir##${ROOT_DIR}/}
    build_config_dir=${build_config_dir##${real_root_dir}}
    KERNEL_DIR="${build_config_dir}"
    if [[ "${ROOT_DIR}" == "${KERNEL_DIR}" ]]; then
        # For backwards compatibility
        KERNEL_DIR=.
    fi
    echo "= Set default KERNEL_DIR: ${KERNEL_DIR}"
else
    echo "= User environment KERNEL_DIR: ${KERNEL_DIR}"
fi

set -a
. ${ROOT_DIR}/${BUILD_CONFIG}
for fragment in ${BUILD_CONFIG_FRAGMENTS}; do
  . ${ROOT_DIR}/${fragment}
done
set +a

echo "= The final value for KERNEL_DIR: ${KERNEL_DIR}"

# For incremental kernel development, it is beneficial to trade certain
# optimizations for faster builds.
if [[ -n "${FAST_BUILD}" ]]; then
  # Decrease lz4 compression level to significantly speed up ramdisk compression.
  : ${LZ4_RAMDISK_COMPRESS_ARGS:="--fast"}
  # Use ThinLTO for fast incremental compiles
  : ${LTO:="thin"}
  # skip installing kernel headers
  : ${SKIP_CP_KERNEL_HDR:="1"}
fi

export COMMON_OUT_DIR=$(readlink -m ${OUT_DIR:-${ROOT_DIR}/out${OUT_DIR_SUFFIX}/${BRANCH}})
export OUT_DIR=$(readlink -m ${COMMON_OUT_DIR}/${KERNEL_DIR})
export DIST_DIR=$(readlink -m ${DIST_DIR:-${COMMON_OUT_DIR}/dist})
export UNSTRIPPED_DIR=${DIST_DIR}/unstripped
export UNSTRIPPED_MODULES_ARCHIVE=unstripped_modules.tar.gz
export MODULES_ARCHIVE=modules.tar.gz

echo "========================================================"
echo -e "=== Build config: ${ROOT_DIR}/${BUILD_CONFIG}\n"
echo
cat ${ROOT_DIR}/${BUILD_CONFIG}
echo -e "\n=== end: ${ROOT_DIR}/${BUILD_CONFIG}"
echo "========================================================"

# Print all other configs referenced in main build config
function lsconfig() {
  local buildcfg=$1 # main build config
  local extra_configs=("$buildcfg")
  grepcfg() { 
    eval echo $(grep -E '^\.\ ' "$1" | sed 's/. //g')
  }

  set +e
  
  while true; do
    for i in ${extra_configs[*]} ; do
      subcfg="$(grepcfg "$i")"
      [[ -n "$subcfg" ]] && [[ "${extra_configs[*]}" != *"$subcfg"* ]] && found_configs+=("$subcfg")
    done

    if [[ -n "${found_configs[*]}" ]]; then
      extra_configs+=(${found_configs[*]})
      found_configs=()
    else
      break
    fi
  done

  unset extra_configs[0]
  echo ${extra_configs[*]}

  set -e
}

for fragment in $(lsconfig "${ROOT_DIR}/${BUILD_CONFIG}"); do
  echo -e "++++ Build config: $fragment\n"
  cat "$fragment"
  echo -e "\n++++ end: $fragment"
done

export TZ=UTC
export LC_ALL=C
if [ -z "${SOURCE_DATE_EPOCH}" ]; then
  if [[ -n "${KLEAF_SOURCE_DATE_EPOCHS}" ]]; then
    export SOURCE_DATE_EPOCH=$(extract_git_metadata "${KLEAF_SOURCE_DATE_EPOCHS}" "${KERNEL_DIR}" SOURCE_DATE_EPOCH)
    # Unset KLEAF_SOURCE_DATE_EPOCHS to avoid polluting {kernel_build}_env.sh
    # with unnecessary information (git metadata of unrelated projects)
    unset KLEAF_SOURCE_DATE_EPOCHS
  else
    export SOURCE_DATE_EPOCH=$(git -C ${KERNEL_DIR} log -1 --pretty=%ct)
  fi
fi
if [ -z "${SOURCE_DATE_EPOCH}" ]; then
  echo "WARNING: Unable to determine SOURCE_DATE_EPOCH for ${KERNEL_DIR}, fallback to 0" >&2
  export SOURCE_DATE_EPOCH=0
fi
export KBUILD_BUILD_TIMESTAMP=${KBUILD_BUILD_TIMESTAMP:-"$(date -d @${SOURCE_DATE_EPOCH})"}
export KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST:-build-host}
export KBUILD_BUILD_USER=${KBUILD_BUILD_USER:-build-user}
export KBUILD_BUILD_VERSION=${KBUILD_BUILD_VERSION:-1}

# List of prebuilt directories shell variables to incorporate into PATH
prebuilts_paths=(
LINUX_GCC_CROSS_COMPILE_PREBUILTS_BIN
LINUX_GCC_CROSS_COMPILE_ARM32_PREBUILTS_BIN
LINUX_GCC_CROSS_COMPILE_COMPAT_PREBUILTS_BIN
CLANG_PREBUILT_BIN
CLANGTOOLS_PREBUILT_BIN
RUST_PREBUILT_BIN
LZ4_PREBUILTS_BIN
DTC_PREBUILTS_BIN
LIBUFDT_PREBUILTS_BIN
BUILDTOOLS_PREBUILT_BIN
KLEAF_INTERNAL_BUILDTOOLS_PREBUILT_BIN
)

unset LD_LIBRARY_PATH

if [ "${HERMETIC_TOOLCHAIN:-0}" -eq 1 ]; then
  HOST_TOOLS=${OUT_DIR}/host_tools
  rm -rf ${HOST_TOOLS}
  mkdir -p ${HOST_TOOLS}
  for tool in \
      bash \
      git \
      perl \
      rsync \
      sh \
      ${ADDITIONAL_HOST_TOOLS}
  do
      ln -sf $(which $tool) ${HOST_TOOLS}
  done
  PATH=${HOST_TOOLS}
fi

for prebuilt_bin in "${prebuilts_paths[@]}"; do
    prebuilt_bin=\${${prebuilt_bin}}
    eval prebuilt_bin="${prebuilt_bin}"
    if [ -n "${prebuilt_bin}" ]; then
        # Mitigate dup paths
        PATH=${PATH//"${ROOT_DIR}\/${prebuilt_bin}:"}
        PATH=${ROOT_DIR}/${prebuilt_bin}:${PATH}
    fi
done
export PATH

echo "========================================================"
echo " PATH="
IFS=':' read -ra echopaths <<< "$PATH"
for lst in "${echopaths[@]}"; do
    echo "      $lst"
done
echo

unset PYTHONPATH
unset PYTHONHOME
unset PYTHONSTARTUP

export HOSTCC HOSTCXX CC LD AR NM OBJCOPY OBJDUMP OBJSIZE READELF STRIP AS

tool_args=()

# LLVM=1 implies what is otherwise set below; it is a more concise way of
# specifying CC=clang LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy <etc>, for
# newer kernel versions.
if [[ -n "${LLVM}" ]]; then
  case ${LLVM} in
    -*) LLVM_SUFFIX=${LLVM} ;;
    */) LLVM_PREFIX=${LLVM}
  esac
  tool_args+=("LLVM=1")
  # Make $(LLVM) more flexible. Set a version suffix by leaving a dash
  # at beginning or set path to toolchain by leaving trailing slash.
  if [[ -n ${LLVM_SUFFIX} || -n ${LLVM_PREFIX} ]]; then
    tool_args+="
    HOSTCC="${LLVM_PREFIX}clang${LLVM_SUFFIX}"
    HOSTCXX="${LLVM_PREFIX}clang++${LLVM_SUFFIX}"
    HOSTLD="${LLVM_PREFIX}ld.lld${LLVM_SUFFIX}"
    HOSTAR="${LLVM_PREFIX}llvm-ar${LLVM_SUFFIX}"
    CC="${LLVM_PREFIX}clang${LLVM_SUFFIX}"
    LD="${LLVM_PREFIX}ld.lld${LLVM_SUFFIX}"
    AR="${LLVM_PREFIX}llvm-ar${LLVM_SUFFIX}"
    NM="${LLVM_PREFIX}llvm-nm${LLVM_SUFFIX}"
    OBJCOPY="${LLVM_PREFIX}llvm-objcopy${LLVM_SUFFIX}"
    OBJDUMP="${LLVM_PREFIX}llvm-objdump${LLVM_SUFFIX}"
    OBJSIZE="${LLVM_PREFIX}llvm-size${LLVM_SUFFIX}"
    READELF="${LLVM_PREFIX}llvm-readelf${LLVM_SUFFIX}"
    STRIP="${LLVM_PREFIX}llvm-strip${LLVM_SUFFIX}"
    "
  fi

  # Reset a bunch of variables that the kernel's top level Makefile does, just
  # in case someone tries to use these binaries in this script such as in
  # initramfs generation below.
  HOSTCC=clang
  HOSTCXX=clang++
  CC=clang
  LD=ld.lld
  AR=llvm-ar
  NM=llvm-nm
  OBJCOPY=llvm-objcopy
  OBJDUMP=llvm-objdump
  OBJSIZE=llvm-size
  READELF=llvm-readelf
  STRIP=llvm-strip
else
  if [ -n "${HOSTCC}" ]; then
    tool_args+=("HOSTCC=${HOSTCC}")
  fi

  if [ -n "${CC}" ]; then
    check_tc CC "${CC}" "$@"
    tool_args+=("CC=${CC}")
    if [ -z "${HOSTCC}" ]; then
      tool_args+=("HOSTCC=${CC}")
    fi
  fi

  if [ -n "${LD}" ]; then
    check_tc LD "${LD}" "$@"
    tool_args+=("LD=${LD}" "HOSTLD=${LD}")
  fi

  if [ -n "${NM}" ]; then
    check_tc NM "${NM}" "$@"
    tool_args+=("NM=${NM}")
  fi

  if [ -n "${OBJCOPY}" ]; then
    check_tc OBJCOPY "${OBJCOPY}" "$@"
    tool_args+=("OBJCOPY=${OBJCOPY}")
  fi
fi

if [ -n "${LLVM_IAS}" ]; then
  tool_args+=("LLVM_IAS=${LLVM_IAS}")
  # Reset $AS for the same reason that we reset $CC etc above.
  AS=clang
fi

if [ -n "${DEPMOD}" ]; then
  check_tc DEPMOD "${DEPMOD}" "$@"
  tool_args+=("DEPMOD=${DEPMOD}")
fi

if [ -n "${DTC}" ]; then
  check_tc DTC "${DTC}" "$@"
  tool_args+=("DTC=${DTC}")
fi

export TOOL_ARGS="${tool_args[@]}"

export DECOMPRESS_GZIP DECOMPRESS_LZ4 RAMDISK_COMPRESS RAMDISK_DECOMPRESS RAMDISK_EXT

DECOMPRESS_GZIP="gzip -c -d"
DECOMPRESS_LZ4="lz4 -c -d -l"
if [ -z "${LZ4_RAMDISK}" ] ; then
  RAMDISK_COMPRESS="gzip -c -f"
  RAMDISK_DECOMPRESS="${DECOMPRESS_GZIP}"
  RAMDISK_EXT="gz"
else
  RAMDISK_COMPRESS="lz4 -c -l ${LZ4_RAMDISK_COMPRESS_ARGS:--12 --favor-decSpeed}"
  RAMDISK_DECOMPRESS="${DECOMPRESS_LZ4}"
  RAMDISK_EXT="lz4"
fi