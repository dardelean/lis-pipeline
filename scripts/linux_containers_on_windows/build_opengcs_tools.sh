#!/bin/bash

set -xe

source ~/.profile

BUILD_BASE_DIR="$1"
OPENGCS_ARTIFACTS_DESTINATION_PATH="$2"
THREAD_NUM="$3"

# root location where building takes place, needs to be in GOPATH
OPENGCS_BASE_BUILD_DIR="${BUILD_BASE_DIR}/opengcs-build-folder"
# location where make is executed
OPENGCS_BUILD_DIR="${GOPATH}/src/github.com/Microsoft/opengcs/service"
#location where artifacts are found after build
OPENGCS_ARTIFACT_DIR="${OPENGCS_BUILD_DIR}/bin"

function build_opengcs() {
    opengcs_build_dir="$1"
    thread_num="$2"

    sudo chown -R `whoami`:`whoami` "$GOPATH"
    sudo chown -R `whoami`:`whoami` "$GOROOT"
    echo "Building opengcs tools"

    if [[ ! -d "${opengcs_build_dir}" ]]
    then
        echo "Could not find the opengcs rep to build"
        exit 1
    else
        pushd "${opengcs_build_dir}"
    fi

    echo "$PATH"
    make -j"${thread_num}"
    popd

    echo "Opengcs tools artifacs built successfully"
}

function copy_opengcs_artifact() {
    opengcs_build_dir="$1"
    opengcs_artifacts_destination_path="$2"
    opengcs_artifact_dir="$3"

    output_dir_name="${opengcs_artifacts_destination_path}/`date +%Y%m%d`_${BUILD_ID}__opengcs"
    sudo mkdir -p "${output_dir_name}"

    pushd "${opengcs_build_dir}"

    echo `git log --pretty=format:'%h' -n 1` > "${output_dir_name}/latest_opengcs_commit.log"
    echo "Opengcs tools built on commit:"
    cat "${output_dir_name}/latest_opengcs_commit.log"

    echo "Copying opengcs artifact to the destination folder"
    copy_artifacts "${opengcs_artifact_dir}" "${output_dir_name}"
    echo "Opengcs artifact published on ${output_dir_name}"
    echo "Opengcs tools artifacts copied successfully"

    popd

}

function cleanup_opengcs() {
    # Clean GO stuff
    opengcs_base_build_dir="$1"

    pushd "${opengcs_base_build_dir}"

    if [ -f go*.linux-amd64.tar.gz ]; then
        rm go*.linux-amd64.tar.gz
        echo "GO archive removed"
    fi

    if [ -d "${opengcs_base_build_dir}" ]; then
        rm -rf "${opengcs_base_build_dir}/golang/src/github.com/Microsoft/opengcs"
        echo "Git repos and GO dirs removed"
    fi

    echo "Cleanup successfull"
}

function copy_artifacts() {
    artifacts_folder=$1
    destination_path=$2
    
    atifact_exists="$(ls $artifacts_folder/* || true)"
    if [[ "$atifact_exists" != "" ]];then
        sudo cp "$artifacts_folder"/* "$destination_path"
    fi
}

echo "GOPATH is: $GOPATH"
build_opengcs "$OPENGCS_BUILD_DIR" "$THREAD_NUM"
copy_opengcs_artifact "$OPENGCS_BUILD_DIR" "$OPENGCS_ARTIFACTS_DESTINATION_PATH" "$OPENGCS_ARTIFACT_DIR"

echo "opengcs tools build successfully"

#cleanup_opengcs "$OPENGCS_BASE_BUILD_DIR"