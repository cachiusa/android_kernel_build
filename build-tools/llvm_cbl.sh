#!/usr/bin/env bash
# Slim LLVM toolchains for building the Linux kernel
#
# These toolchains have been built from the llvmorg-<version> tags in the
# llvm-project repository and optimized with profile guided optimization (PGO)
# via tc-build to improve the speed of the toolchain for building the kernel.
#
# These toolchains aim to be fairly minimal by just including the necessary
# tools to build the kernel proper to reduce the size of the installation
# on disk; it is possible things are missing for the selftests and other
# projects within the kernel.

#---- default constants ----
TYPE="llvm"
MIRROR="https://cdn.kernel.org"
HOST_ARCH=$(uname -m)
TARGET_ARCH="aarch64"
COMP="xz"
VERSION_PTN='[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?'
VERSION=

#---- dynamic variables ----
set_vars() {
    case ${TYPE} in
        llvm)
            FILES="${MIRROR}/pub/tools/llvm/files"
            PKG="llvm-${VERSION}-${HOST_ARCH}"
            COMPILER="clang"
            TAR_ARGS="--strip-components=1 ${PKG}"
        ;;
        gcc)
            SUBDIR1="gcc-${VERSION}-nolibc"
            SUBDIR2="${TARGET_ARCH}-linux"

            FILES="${MIRROR}/pub/tools/crosstool/files/bin/${HOST_ARCH}/${VERSION}"
            PKG="${HOST_ARCH}-${SUBDIR1}-${SUBDIR2}"
            COMPILER="${SUBDIR2}-gcc"
            TAR_ARGS="--strip-components=2 ${SUBDIR1}/${SUBDIR2}"

            [[ -n ${gcc_alt_pkg} ]] && PKG="${HOST_ARCH}-${SUBDIR1}_${SUBDIR2}"
    esac
    TAR="${PKG}.tar${COMP}"
    TAR_URL="${FILES}/${TAR}"
    INSTALLDIR="${HOME_DIR}/${TYPE}/${VERSION}"
    DL_DIR="${HOME_DIR}/pkgs"
}
#---- functions ----
set_colors() {
    if [[ -n ${GITHUB_ACTION} ]] || [[ -t 1 ]]; then
        _lblue='\e[38;5;14m'
        _blue='\e[38;5;6m'
        _bold='\e[1m'
        _lred='\e[38;5;9m'
        _red='\e[38;5;1m'
        _restore='\e[0m'
    fi
}
info_msg() { echo -e "${_blue}[${_lblue}+${_blue}]${_restore} ${1}"; }
error_msg() { echo -e "${_bold}${_red}[${_lred}!${_red}]${_restore}${_bold} ${1}${_restore}"; exit 1; }
help_msg() { echo -e "Usage: $0 -p <install path> [options...]
 -a <arch>      host arch
        default: ${HOST_ARCH}
 -A <arch>      target arch (GCC only)
        default: ${TARGET_ARCH}
 -f <format>    set tar compression format
        default: xz
 -v <version>   specify toolchain version
        default: latest
        if set to 'all', download all versions (please do not DDoS the servers)
 -x             print each command being executed
 --no-extract   downloads the package but don't extract
 --stable       ignore '-rc' versions
 --gcc          set up GCC and binutils
 --llvm         set up Clang/LLVM (default)
 --help         this screen"
}
parse_args() {
    [[ -z $1 ]] && help_msg && exit 1
    while (( $# )); do
        case $2 in
            -*) value= ;; # do not accept argument name as value
            *)  value="$2"
        esac
        case $1 in
            -a) HOST_ARCH="$value"      ;;
            -A) TARGET_ARCH="$value"    ;;
            -f) COMP="$value"           ;;
            -p) HOME_DIR="$value"       ;;
            -v) VERSION="$value"        ;;
            -x) set -o xtrace           ;;
            --help) help_msg ; exit 0   ;;
            --gcc) TYPE="gcc"           ;;
            --llvm) TYPE="llvm"         ;;
            --no-extract) NO_EXTRACT=1  ;;
            --stable)       ;;
        esac
        shift
    done

    COMP=".${COMP}"

    case ${VERSION} in
        all) GET_ALL=1 ;;
        stable) STABLE_VER=1 ;;
        latest)
    esac

    HOME_DIR=$(readlink -m "${HOME_DIR}")
    [[ -z ${HOME_DIR} ]] && error_msg "You must set toolchain home with '-p'"
}
print_info() {
    info_msg "Install path: ${HOME_DIR}"

    info_msg "Host arch: ${HOST_ARCH}"

    [[ ${TYPE} = "gcc" ]] && info_msg "GCC target arch: ${TARGET_ARCH}"

    mkdir -p "${HOME_DIR}" || error_msg "The install path is not writable!"
}
check_installed() {
    if [[ -z ${installed_vers} ]]; then
        installed_ccs=$(find "${HOME_DIR}" -wholename "*bin/${COMPILER}")
    fi

    for cc in ${installed_ccs}; do
        INSTALLED_VER=$(echo "$cc" | grep -oE "${VERSION_PTN}")

        if [[ ${INSTALLED_VER} = "${VERSION}" ]] && "$cc" --version ; then
            local exit=1
            break
        fi
    done

    if [[ ${exit} = "1" ]]; then
        info_msg "${TYPE} ${VERSION} is installed"
        return
    else
        return 1
    fi
}
get_versions() {
    info_msg "Fetching versions list"

    local VERSION=
    set_vars

    _vers="$(curl -s "${FILES}/" | grep -oE "${VERSION_PTN}" | sort -uV)"

    [[ -z ${_vers} ]] && error_msg "Failed to retrieve version list"

    for _v in ${_vers}; do
        if [[ -n ${STABLE_VER} && ${_v} == *"-rc"* ]]; then
            continue
        fi
        CURRENT_VERS+=("$_v")
    done

    LATEST_VER=${CURRENT_VERS[-1]}
}
check_and_set_version() {
    if [[ -n ${VERSION} ]]; then
        info_msg "Set toolchain version: ${VERSION}"

        local is_ver_ok=

        for _v in "${CURRENT_VERS[@]}"; do
            [[ ${VERSION} == "$_v" ]] && is_ver_ok=1 && break
        done

        [[ -z ${is_ver_ok} ]] && error_msg "${TYPE} ${VERSION}: not found
Avaliable versions:${_restore} ${CURRENT_VERS[*]}"

    else
        VERSION=${LATEST_VER}

        if [[ ${LATEST_VER} = "${INSTALLED_VER}" ]]; then
            info_msg "Already up to date." && exit 0
        else
            info_msg "Latest version: ${LATEST_VER}"
        fi
    fi

    if [[ ${TYPE} = "gcc" ]]; then
        case ${VERSION} in
            4.2.4|4.5.1|4.6.2|4.6.3|4.7.3|4.8.0|4.9.0|7.3.0)
            gcc_alt_pkg=1
        esac
    fi
    set_vars
}
get_pkg() {
    [[ -f ${DL_DIR}/${TAR} ]] && return

    info_msg "Fetching package info: ${FILES}/sha256sums.asc"

    read -r CURRENT_SHA256 CURRENT_TAR <<< "$(curl -s "${FILES}/sha256sums.asc" | grep "${TAR}")"

    if [[ -z ${CURRENT_SHA256} || -z ${CURRENT_TAR} ]]; then
        error_msg "No info for ${TAR}"
    fi

    info_msg "Downloading: ${TAR}"

    mkdir -p "${DL_DIR}"

    wget -P "${DL_DIR}" "${TAR_URL}"

    [[ -f ${DL_DIR}/${TAR} ]] || error_msg "Download failed"
}
hash_pkg() {
    info_msg "Verifying: ${TAR}"

    if sha256sum "${DL_DIR}/${TAR}" | grep -q "${CURRENT_SHA256}" ; then
        info_msg "sha256: ok"
    else
        error_msg "sha256: mismatch"
    fi
}
extract() {
    [[ -n ${NO_EXTRACT} ]] && return

    info_msg "Extracting package"

    mkdir -p "${INSTALLDIR}"

    # shellcheck disable=SC2086
    tar -C "${INSTALLDIR}" \
        -f "${DL_DIR}/${TAR}" \
        -x \
        -a \
        ${TAR_ARGS}
}
work_now() {
    check_installed || {
        check_and_set_version
        get_pkg
        hash_pkg
        extract
        check_installed
    }
}

#---- main ----
set_colors
parse_args "$@"
set_vars
print_info
get_versions

if [[ -n ${GET_ALL} ]]; then
    for VERSION in "${CURRENT_VERS[@]}"; do
        work_now
    done
else
    work_now
fi
