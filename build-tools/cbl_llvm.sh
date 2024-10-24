#!/bin/bash
#
# Slim LLVM toolchains for building the Linux kernel
#
# These toolchains have been built from the llvmorg-<version> tags in the
# llvm-project repository and optimized with profile guided optimization (PGO)
# via tc-build to improve the speed of the toolchain for building the kernel.
#
# These toolchains aim to be fairly minimal by just including the necessary tools
# to build the kernel proper to reduce the size of the installation on disk;
# it is possible things are missing for the selftests and other projects within the kernel.

tc_install_dir=$(readlink -m "$1")
tc_cdn="https://cdn.kernel.org/pub/tools/llvm/files"
ver_pattern='[0-9]+.[0-9]+.[0-9]+(-rc[0-9]+)?'

if [[ -z "$tc_install_dir" ]]; then
    echo "Usage:"
    echo "    $0 <install path>"
    exit 1
fi

if [[ -f "$tc_install_dir/bin/clang" ]]; then
    tc_installed_ver=$("$tc_install_dir"/bin/clang --version | grep -oE "$ver_pattern" | head -n1)
    echo "[+] Clang/LLVM $tc_installed_ver is installed"
fi

echo "[+] Fetching latest version"
read -r tc_current_sha256 tc_current_dist <<< "$(curl -s $tc_cdn/sha256sums.asc | grep -E "llvm-$ver_pattern-$(uname -m).tar.xz" | tail -n1)"
tc_current_name=${tc_current_dist%.tar*}
tc_current_ver=$(echo "$tc_current_name" | grep -oE "$ver_pattern")

if [[ -n "$tc_installed_ver" ]] && [[ "$tc_current_ver" == "$tc_installed_ver" ]]; then
    echo "[+] Already up to date"
    exit 0
fi

if [[ ! -f "$tc_current_dist" ]]; then
    echo "[+] Downloading $tc_current_dist"
    wget "$tc_cdn/$tc_current_dist"
fi

echo "[+] Verifying download"
if sha256sum "$tc_current_dist" | grep -q "$tc_current_sha256" ; then
    echo "[+] Successfully verified hash"
else
    echo "[ ] Hash mismatch. Abort"
    exit 1
fi

echo "[+] Extracting tar"
tar -C "$(dirname "$tc_install_dir")" -x -f "$tc_current_dist" -J
if [[ "$tc_install_dir" != *"$tc_current_name" ]]; then
    rm -rf "$tc_install_dir"
    mv "$tc_current_name" "$tc_install_dir"
fi

echo "[+] Done"
$tc_install_dir/bin/clang --version