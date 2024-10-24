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
#MIRROR="https://mirrors.edge.kernel.org"
HOST_ARCH=$(uname -m)
TARGET_ARCH="aarch64"
COMP="xz"
VERSION_PTN='[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?'

#---- dynamic variables ----
set_vars() {
    case ${TYPE} in
        llvm)
            FILES="${MIRROR}/pub/tools/llvm/files"
            FILES_INDEX_HTML="${MIRROR}/pub/tools/llvm/files/"
            PKG="llvm-${VERSION}-${HOST_ARCH}"
            COMPILER="clang"
            #TAR_ARGS="--strip-components=1 ${PKG}"
        ;;
        gcc)
            GCC_1="gcc-${VERSION}-nolibc"
            GCC_2="${TARGET_ARCH}-linux"

            FILES="${MIRROR}/pub/tools/crosstool/files/bin/${HOST_ARCH}/${VERSION}"
            FILES_INDEX_HTML="${MIRROR}/pub/tools/crosstool/files/bin/${HOST_ARCH}/"
            PKG="${HOST_ARCH}-${GCC_1}-${GCC_2}"
            COMPILER="${GCC_2}-gcc"
            #TAR_ARGS="--strip-components=2 ${GCC_1}/${GCC_2}"

            [[ -n ${gcc_alt_pkg} ]] && PKG="${HOST_ARCH}-${GCC_1}_${GCC_2}"
    esac
    TAR="${PKG}.tar${COMP}"
    TAR_URL="${FILES}/${TAR}"
    INSTALL_DIR_BASE="${HOME_DIR}/${TYPE}"
    DL_DIR="${HOME_DIR}/pkgs"
}
#---- functions ----
set_colors() {
    if [[ -n ${GITHUB_ACTION} || -t 1 ]]; then
        _lblue='\e[38;5;51m'
        _blue='\e[38;5;39m'
        _bold='\e[1m'
        _lred='\e[38;5;196m'
        _red='\e[38;5;124m'
        _restore='\e[0m'
    fi
}
info_msg() { echo -e "${_blue}[${_lblue}+${_blue}]${_restore} ${1}"; }
info_msg2() { echo -e " +  ${1}"; }
error_msg() { echo -e "${_bold}${_red}[${_lred}!${_red}]${_restore}${_bold} ${1}${_restore}"; exit 1; }
help_msg() { echo -e "Usage: $0 -p <install path> [options...]
 -a <arch>      host arch
    default: ${HOST_ARCH}
 -A <arch>      target arch (GCC only)
    default: ${TARGET_ARCH}
 -f <format>    tar compression format
    default: ${COMP}
 -v <version>   toolchain version
    'all': download all versions (please do not DDoS the servers)
    'stable': ignore '-rc' versions
    default: latest
 -x             print each command being executed
 --no-extract   downloads the package but don't extract
 --gcc          set up GCC & binutils
    More info: <${MIRROR}/pub/tools/crosstool>
 --llvm         set up Clang/LLVM (default)
    More info: <${MIRROR}/pub/tools/llvm>
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
            -v) SET_VER="$value"        ;;
            -x) set -o xtrace           ;;
            --help) help_msg ; exit 0   ;;
            --gcc) TYPE="gcc"           ;;
            --llvm) TYPE="llvm"         ;;
            --no-extract) NO_EXTRACT=1  ;;
        esac
        shift
    done

    if [[ -n ${COMP} ]]; then
        COMP=".${COMP}"
    else
        COMP=
    fi

    case ${SET_VER} in
        ''|latest) VERSION= ;;
        stable) STABLE_VER=1 ;;
        all) GET_ALL=1 ;;
        *) VERSION=${SET_VER}
    esac

    HOME_DIR=$(readlink -m "${HOME_DIR}")

    [[ -z ${HOME_DIR} ]] && error_msg "You must set toolchain home with '-p'"
}
print_info() {
    info_msg2 "Set toolchain: ${TYPE}"
    info_msg2 "Install home: ${HOME_DIR}"
    info_msg2 "Host arch: ${HOST_ARCH}"

    [[ ${TYPE} = "gcc" ]] && info_msg2 "Target arch: ${TARGET_ARCH}"

    mkdir -p "${HOME_DIR}" || error_msg "The home path is not writable!"
}
cc2ver() {
    [[ -f $1 ]] || return
    "$1" --version | grep -oE "${VERSION_PTN}" | head -n 1
}
check_installed() {
    # check if $VERSION specified is installed in install dir

    IS_INSTALLED=
    installed_ccs=$(find -P "${HOME_DIR}" -path "*bin/${COMPILER}")

    for cc in ${installed_ccs}; do
        if "$cc" --version &> /dev/null ; then
            INSTALLED_VER=$(cc2ver "$cc")
            if [[ ${INSTALLED_VER} = "${VERSION}" ]]; then
                INSTALLED_DIR=$(dirname "${cc}")
                IS_INSTALLED=1 && break
            fi
        fi
    done

    if [[ ${IS_INSTALLED} = "1" ]]; then
        info_msg2 "Installed: ${TYPE} - ${VERSION}"
        return
    else
        return 1
    fi
}
get_versions() {
    info_msg "Fetching versions list"

    _vers="$(curl -s "${FILES_INDEX_HTML}" | grep -oE "${VERSION_PTN}" | sort -uV)"
    [[ -z ${_vers} ]] && error_msg "Failed to retrieve version list"

    for _v in ${_vers}; do
        if [[ -n ${STABLE_VER} && ${_v} == *"-rc"* ]]; then
            continue
        fi
        CURRENT_VERS+=("$_v")
    done

    LATEST_VER=${CURRENT_VERS[-1]}

    if [[ -z ${VERSION} ]]; then
        info_msg2 "Latest version: ${LATEST_VER}"
        VERSION=${LATEST_VER}
    fi
}
check_and_set_version() {
    if [[ -n ${VERSION} ]]; then
        local is_ver_ok=

        for _v in "${CURRENT_VERS[@]}"; do
            [[ ${VERSION} == "$_v" ]] && is_ver_ok=1 && break
        done

        if [[ ${is_ver_ok} = "1" ]]; then
            info_msg2 "Install job: ${TYPE} - ${VERSION}"
        else
            error_msg "Invalid version set: ${VERSION} ${_restore}
Avaliable versions: ${CURRENT_VERS[*]}"
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
    get_sha256sums() { grep -s "${TAR}" "${DL_DIR}/sha256sums.asc" ;}

    [[ -f ${DL_DIR}/${TAR} ]] && return

    mkdir -p "${DL_DIR}"

    if ! get_sha256sums; then
        info_msg "Fetching package info: ${FILES}/sha256sums.asc"
        curl -s -o "${DL_DIR}/sha256sums.asc" "${FILES}/sha256sums.asc"
    fi

    CURRENT_SHA256=$(get_sha256sums | awk '{print $1}')
    [[ -z ${CURRENT_SHA256} ]] && error_msg "No info for ${TAR}"

    info_msg "Downloading: ${TAR}"
    wget -P "${DL_DIR}" "${TAR_URL}"
    [[ -f ${DL_DIR}/${TAR} ]] || error_msg "Download failed"
}
hash_pkg() {
    info_msg "Verifying: ${TAR}"

    if sha256sum "${DL_DIR}/${TAR}" | grep -q "${CURRENT_SHA256}" ; then
        info_msg2 "sha256: OK"
    else
        error_msg "sha256: mismatch"
    fi
}
extract() {
    [[ -n ${NO_EXTRACT} ]] && return
    info_msg "Extracting: ${TAR}"

    mkdir -p "${INSTALL_DIR_BASE}"
    # shellcheck disable=SC2086
    tar -C "${INSTALL_DIR_BASE}" \
        -f "${DL_DIR}/${TAR}" \
        -x \
        -a
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
link_dir() {
    #---- switch to different toolchain versions by changing symlink ----
    target_bin=${HOME_DIR}/bin

    if [[ ${IS_INSTALLED} != "1" ]]; then
        return 1
    elif [[ ${INSTALLED_VER} = "$(cc2ver "${target_bin}/${COMPILER}")" ]]; then
        return
    fi

    info_msg "Symlink: ${INSTALLED_DIR} ${_bold}${_blue}->${_restore} ${target_bin}"

    installed_dir_rel=$(realpath --relative-to="${HOME_DIR}" "${INSTALLED_DIR}")

    if [[ -h ${target_bin} ]]; then
        unlink "${target_bin}"
    elif [[ -d ${target_bin} ]]; then
        rm -rf "${target_bin}"
    fi

    ln -sf "${installed_dir_rel}" "${target_bin}"
}
#---- main ----
set_colors
parse_args "$@"
set_vars
print_info
get_versions

if [[ -n ${GET_ALL} ]]; then
    for VERSION in "${CURRENT_VERS[@]}"; do work_now ; done
else
    work_now
    link_dir
fi
info_msg "Done."
