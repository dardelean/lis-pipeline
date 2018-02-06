#!/bin/bash

set -xe

source ~/.profile

# base dir in which the artifacts are going to be built
BUILD_BASE_DIR="$1"
LINUX_MSFT_ARTIFACTS_DESTINATION_PATH="$2"
THREAD_NUM="$3"
KERNEL_VERSION="$4"
CHECKOUT_COMMIT="$5"
COMMITS_LIST="${@:6}"

# the kernel is going to be built here
LINUX_BASE_DIR="${BUILD_BASE_DIR}/kernel-build-folder"
# opengcs tools are going to be built here, needs to be in GOPATH
OPENGCS_BASE_DIR="${BUILD_BASE_DIR}/opengcs-build-folder/golang/src/github.com/Microsoft/opengcs"


function apply_patches() {
    #
    # Apply some patches before building
    #
    linux_base_dir="$1"
    linux_msft_artifacts_destination_path="$2"
    kernel_version="$3"
    checkout_commit="$4"
    opengcs_base_dir="$5"


    if [[ ! -d "${linux_base_dir}/msft_linux_kernel" ]]
    then
        echo "Could not find the Linux Kernel repo to apply patches"
        exit 1
    else
        pushd "${linux_base_dir}/msft_linux_kernel"
    fi

    # this will be the destination directory of the kernel artifact
    output_dir_name="${linux_msft_artifacts_destination_path}/`date +%Y%m%d`_${BUILD_ID}__msft-kernel_${kernel_version}"
    sudo mkdir -p "${output_dir_name}"

    # last commit before pulling
    echo `git log --pretty=format:'%h' -n 1` > "${output_dir_name}/latest_kernel_commit.log"
    echo "Linux kernel built on commit:"
    cat "${output_dir_name}/latest_kernel_commit.log"

    # tag for specific repo
    branch="$(git rev-parse --abbrev-ref HEAD)"
    if [[ "${branch}" == "master" ]]
    then
        git checkout "${checkout_commit}"
        git cherry-pick fd96b8da68d32a9403726db09b229f4b5ac849c7

        echo "Apply NVDIMM patch"
        patch -p1 -t <"${opengcs_base_dir}/kernel/patches-4.12.x/0002-NVDIMM-reducded-ND_MIN_NAMESPACE_SIZE-from-4MB-to-4K.patch"
        cp "${opengcs_base_dir}/kernel/kernel_config-${kernel_version}.x" .config

        echo "Instructions for getting Hyper-V vsock patch"
        git remote add -f dexuan-github https://github.com/dcui/linux.git  || echo "already existing"
        git fetch dexuan-github

        for commit in ${COMMITS_LIST[@]}
        do
            git cherry-pick -x "${commit}"
        done

        popd
        echo "Patches applied on Linux Kernel successfully"
    fi
}

function build_kernel() {
    linux_base_dir="$1"
    linux_msft_artifacts_destination_path="$2"
    kernel_version="$3"
    thread_num="$4"

    sudo chown -R `whoami`:`whoami` "${linux_base_dir}/msft_linux_kernel"
    pushd "${linux_base_dir}/msft_linux_kernel"

    echo "Building the LCOW MS-Linux kernel"
    sudo make -j"${thread_num}" && sudo make modules
    if [[ $? -eq 0 ]]
    then
        echo "Kernel built successfully"
    else
        echo "Kernel building failed"
    fi

    # only need the vmlinuz file"
    sudo cp "./arch/x86/boot/bzImage" "${output_dir_name}/bootx64.efi"
    if [[ $? -eq 0 ]]
    then
        echo "Kernel artifact published on ${output_dir_name}"
    else
        echo "Could not copy Kernel artifact to ${output_dir_name}"
    fi

    popd
}

apply_patches "$LINUX_BASE_DIR" "$LINUX_MSFT_ARTIFACTS_DESTINATION_PATH" "$KERNEL_VERSION" "$CHECKOUT_COMMIT" "$OPENGCS_BASE_DIR"
build_kernel "$LINUX_BASE_DIR" "$LINUX_MSFT_ARTIFACTS_DESTINATION_PATH" "$KERNEL_VERSION" "$THREAD_NUM"