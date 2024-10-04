# About
AOSP created `build.sh` to compile their kernels but [deprecated it in Android 13](https://android.googlesource.com/kernel/build/+/670b2ff547c0739352a200422e4e8a7149145947) and used [kleaf](kleaf/README.md) instead

This project aims to maintain `build.sh` and ensure compatibility with all kernel trees

# Setup
1. Clone this repo to `build` directory in your kernel source
2. Run scripts from the parent directory of `build` (see [Manual](#manual))

# bulid.config file
A build configuration file must be specified in the BUILD_CONFIG variable when invoking any script. If not, you will be prompted to select a config file (if found)

See [variables.md](variables.md) for a full list of build options

This file will be sourced by build.sh and functions like a shell script

> Note: **All variables in this file are exported** and available to build.sh sub-processes (e.g. Make)

# Manual
## build.sh
### Usage

    build/build.sh <make options>*

or:  
To define custom out and dist directories:

    OUT_DIR=<out dir> DIST_DIR=<dist dir>build/build.sh <make options>*

To use a custom build config:

    BUILD_CONFIG=<path to the build.config><make options>*


### Examples:
To define custom out and dist directories:

    OUT_DIR=output DIST_DIR=dist build/build.sh -j24 V=1

To use a custom build config:

    BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh -j24 V=1

To use a CC wrapper:

    build/build.sh CC="ccache clang"

## config.sh

Runs a configuration editor inside kernel/build environment.

### Usage:
    build/config.sh <config editor> <make options>*
### Example:
    build/config.sh menuconfig|config|nconfig|... (default to menuconfig)
