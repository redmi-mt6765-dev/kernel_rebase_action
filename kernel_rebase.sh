#!/usr/bin/env bash

#
# Author: <techdiwas> Diwas Neupane
#
# This script rebases a custom OEM kernel source onto a specified
# branch of the Android Common Kernel (ACK).
#

# --- Configuration and Setup ---

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
# The return value of a pipeline is the status of the last command to exit
# with a non-zero status.
set -euo pipefail

# --- Constants ---

# Use tput for terminal capabilities for better portability
if tput setaf 1 > /dev/null 2>&1; then
    readonly RED=$(tput setaf 1)
    readonly GREEN=$(tput setaf 2)
    readonly NORMAL=$(tput sgr0)
else
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly NORMAL='\033[0m'
fi

readonly SCRIPT_NAME="$(basename "${0}")"
readonly PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly ACK_REPO_URL="https://android.googlesource.com/kernel/common.git"

# --- Functions ---

# Print an error message and exit.
#
# Arguments:
#   $1: The error message to print.
#
abort() {
    printf "${RED}Error: %s${NORMAL}\n" "${1}" >&2
    exit 1
}

# Print the script's usage instructions.
#
usage() {
    printf "Usage: %s \"<oem-kernel-git-url>\" \"<oem-branch>\" \"<ack-branch>\"\n" "${SCRIPT_NAME}"
    printf "Example:\n"
    printf "  %s \"https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git\" \"dandelion-q-oss\" \"android-4.9-q\"\n" "${SCRIPT_NAME}"
}

# Clone a git repository with a specific branch and depth.
#
# Arguments:
#   $1: Repository URL.
#   $2: Branch name.
#   $3: Destination directory.
#
clone_repo_oem() {
    local repo_url="${1}"
    local branch="${2}"
    local dest_dir="${3}"

    printf "Cloning branch '%s' from '%s'...\n" "${branch}" "${repo_url}"
    git clone --depth=1 --single-branch --branch "${branch}" "${repo_url}" "${dest_dir}"
}

clone_repo_ack() {
    local repo_url="${1}"
    local branch="${2}"
    local dest_dir="${3}"

    printf "Cloning branch '%s' from '%s'...\n" "${branch}" "${repo_url}"
    git clone --single-branch --branch "${branch}" "${repo_url}" "${dest_dir}"
}

# Get the kernel version from a source directory.
#
# Arguments:
#   $1: Path to the kernel source directory.
#
get_kernel_version() {
    local kernel_src_dir="${1}"
    (cd "${kernel_src_dir}" && make kernelversion) || abort "Failed to determine kernel version in '${kernel_src_dir}'."
}

# Find the corresponding ACK commit for the OEM kernel version and reset to it.
#
# Arguments:
#   $1: Path to the ACK kernel directory.
#   $2: The OEM kernel version string (e.g., "4.9.204").
#   $3: The ACK branch to search within.
#
reset_ack_to_oem_version() {
    local ack_dir="${1}"
    local oem_version="${2}"
    local ack_branch="${3}"
    
    printf "Searching for ACK merge commit for kernel version '%s'...\n" "${oem_version}"

    local commit_sha
    commit_sha=$(git -C "${ack_dir}" log --oneline "${ack_branch}" Makefile | grep -i "${oem_version}" | grep -i "merge" | cut -d ' ' -f1)

    # Check if we found a unique commit
    if [ -z "${commit_sha}" ]; then
        abort "Could not find a corresponding merge commit for version '${oem_version}' in the ACK '${ack_branch}' branch."
    fi
    if [ "$(echo "${commit_sha}" | wc -l)" -ne 1 ]; then
        abort "Found multiple possible merge commits for version '${oem_version}'. Aborting for safety."
    fi
    
    printf "Found base commit: %s. Resetting ACK repository...\n" "${commit_sha}"
    git -C "${ack_dir}" reset --hard "${commit_sha}"
}

# Copy OEM source files and create commits in the ACK repository.
#
# Arguments:
#   $1: Path to the OEM kernel source.
#   $2: Path to the ACK kernel source.
#
rebase_oem_on_ack() {
    local oem_dir="${1}"
    local ack_dir="${2}"
    
    printf "Replacing ACK directories with OEM source...\n"
    
    # Get a list of top-level directories in the OEM source, excluding .git
    local oem_dirs
    oem_dirs=$(find "${oem_dir}" -maxdepth 1 -type d -printf "%P\n" | grep -v '^\.git$' | grep -v '^$')

    for dir in ${oem_dirs}; do
        if [ -d "${ack_dir}/${dir}" ]; then
            rm -rf "${ack_dir}/${dir}"
        fi
    done
    
    printf "Copying all OEM files to ACK directory...\n"
    # Use rsync for efficient copying
    rsync -a --exclude='.git/' "${oem_dir}/" "${ack_dir}/"

    printf "Committing OEM changes...\n"
    for dir in ${oem_dirs}; do
        if [ -d "${ack_dir}/${dir}" ]; then
            git -C "${ack_dir}" add "${dir}"
            git -C "${ack_dir}" commit --quiet -s -m "${dir}: Import from OEM source"
        fi
    done

    # Create a final commit for any remaining untracked files/changes
    git -C "${ack_dir}" add .
    if ! git -C "${ack_dir}" diff-index --quiet HEAD; then
        git -C "${ack_dir}" commit --quiet -s -m "Import remaining OEM changes"
    fi
}

# --- Main Logic ---

main() {
    # Check for required arguments
    if [ "$#" -ne 3 ]; then
        usage
        abort "Invalid number of arguments."
    fi

    local oem_kernel_url="${1}"
    local oem_branch="${2}"
    local ack_branch="${3}"

    local oem_dir="${PROJECT_DIR}/oem"
    local ack_dir="${PROJECT_DIR}/kernel"
    
    # Clean up previous runs
    rm -rf "${oem_dir}" "${ack_dir}"

    # 1. Clone repositories
    clone_repo_oem "${oem_kernel_url}" "${oem_branch}" "${oem_dir}"
    clone_repo_ack "${ACK_REPO_URL}" "${ack_branch}" "${ack_dir}"

    # 2. Get OEM kernel version
    local oem_kernel_version
    oem_kernel_version=$(get_kernel_version "${oem_dir}")
    printf "OEM Kernel Version: %s\n" "${oem_kernel_version}"

    # 3. Reset ACK to the identified base commit
    reset_ack_to_oem_version "${ack_dir}" "${oem_kernel_version}" "${ack_branch}"

    # 4. Rebase OEM changes onto ACK
    rebase_oem_on_ack "${oem_dir}" "${ack_dir}"

    printf "\n${GREEN}Success! Your kernel has been rebased to ACK.${NORMAL}\n"
    printf "The rebased kernel is located in: %s\n" "${ack_dir}"
}

# Run the main function with all script arguments
main "$@"
