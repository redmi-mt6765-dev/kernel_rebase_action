#!/usr/bin/env bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NORMAL='\033[0m'

# Get script directory
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# URLs and Arguments
ACK_REPO="https://android.googlesource.com/kernel/common.git"
OEM_KERNEL_URL="$1"
ACK_BRANCH="$2"

# Show usage information
usage() {
    echo -e "${0} \"OEM kernel git URL\" \"ACK branch\"\nExample: ${0} \"https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git -b dandelion-q-oss\" \"android-4.9-q\""
}

# Abort on error
abort() {
    [[ -n "$1" ]] && echo -e "${RED}$1${NORMAL}"
    exit 1
}

# Check argument count
if [[ $# -ne 2 ]]; then
    usage
    abort "Error: Missing arguments."
fi

# Clone OEM kernel repository
if ! git clone --depth=1 --single-branch ${OEM_KERNEL_URL} oem; then
    abort "Failed to clone OEM kernel repository."
fi

# Clone ACK repository
if ! git clone --single-branch -b "${ACK_BRANCH}" "${ACK_REPO}" kernel; then
    abort "Failed to clone ACK repository."
fi

# Extract OEM kernel version
pushd oem > /dev/null || abort "Cannot enter 'oem' directory."
OEM_KERNEL_VERSION=$(make kernelversion 2>/dev/null)
popd > /dev/null

if [[ -z "${OEM_KERNEL_VERSION}" ]]; then
    abort "Could not detect OEM kernel version."
fi

# Find short SHA for kernel version in ACK history
pushd kernel > /dev/null || abort "Cannot enter 'kernel' directory."
OEM_KERNEL_VER_SHORT_SHA=$(git log --oneline "${ACK_BRANCH}" Makefile | grep -i "${OEM_KERNEL_VERSION}" | grep -i merge | awk '{print $1}' | head -n 1)
if [[ -z "${OEM_KERNEL_VER_SHORT_SHA}" ]]; then
    popd > /dev/null
    abort "Could not find ACK commit matching OEM kernel version."
fi
git reset --hard "${OEM_KERNEL_VER_SHORT_SHA}"
popd > /dev/null

# Get OEM kernel top-level directories (excluding .git)
pushd oem > /dev/null
OEM_DIR_LIST=$(find . -mindepth 1 -maxdepth 1 -type d ! -name ".git" -printf "%P\n")
popd > /dev/null

# Remove corresponding directories from ACK
pushd kernel > /dev/null
for dir in ${OEM_DIR_LIST}; do
    rm -rf "${dir}"
done
popd > /dev/null

# Copy OEM kernel files to ACK
rsync -a --exclude='.git' oem/ kernel/

# Commit imported directories
pushd kernel > /dev/null
for dir in ${OEM_DIR_LIST}; do
    git add "${dir}"
    git commit -s -m "${dir}: Import OEM Changes"
done

# Commit any remaining changes
git add .
git commit -s -m "Import Remaining OEM Changes"
popd > /dev/null

echo -e "${GREEN}Your kernel has been successfully rebased to ACK. Please check the 'kernel/' directory.${NORMAL}"
exit 0
