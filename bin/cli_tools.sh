#!/usr/bin/env bash

# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
set -euo pipefail

SCRIPT_NAME="$( basename "${BASH_SOURCE[0]}")"
# Drop "-update" suffix, if exists
TOOL_NAME="$(echo "${SCRIPT_NAME}" | cut -d "-" -f 1)"

SUPPORTED_TOOL_NAMES=("aws" "az" "gcloud" "bq" "gsutil" "terraform" "java")

if [ ! -L "${BASH_SOURCE[0]}" ]
then
    SCRIPT_PATH=$(readlink -e "${BASH_SOURCE[0]}")
    # Direct execution - return installation script
    echo "# CLI tool wrappers"
    echo "#"
    echo "# To install, run the following command:"
    echo "#     source <(bash ${SCRIPT_PATH@Q})"
    echo "#"
    echo ""
    # Print installation script
    for NAME in "${SUPPORTED_TOOL_NAMES[@]}"
    do
        echo "ln -s ${SCRIPT_PATH@Q} /usr/bin/${NAME}"
        echo "ln -s ${SCRIPT_PATH@Q} /usr/bin/${NAME}-update"
        echo "chmod +x /usr/bin/${NAME} /usr/bin/${NAME}-update"
    done
    exit 0
fi
ENV_TMP_FILE=$(mktemp)
env > "${ENV_TMP_FILE}"
cleanup() {
    rm "${ENV_TMP_FILE}"
}
trap cleanup EXIT HUP INT TERM

CONTAINER_ID="$(head -n 1 < /proc/self/cgroup | cut -d ":" -f 3 | cut -d "/" -f 3)"

COMMON_DOCKER_ARGS=(
    -v "${PWD}:${PWD}"
    --env-file "${ENV_TMP_FILE}"
    -w "${PWD}"
)

AWS_CREDENTIALS_DOCKER_ARGS=(-v "${HOST_HOME}/.aws:/root/.aws")
AZURE_CREDENTIALS_DOCKER_ARGS=(-v "${HOST_HOME}/.azure:/root/.azure")
GOOGLE_CREDENTIALS_DOCKER_ARGS=(
    -v "${HOST_HOME}/.config/gcloud:/root/.config/gcloud"
    -v "${HOST_AIRFLOW_SOURCES}/files/.kube:/root/.kube"
)

COMMAND=("${@}")

# Configure selected tool
case "${TOOL_NAME}" in
    aws )
        COMMON_DOCKER_ARGS+=("${AWS_CREDENTIALS_DOCKER_ARGS[@]}")
        IMAGE_NAME="amazon/aws-cli:latest"
        ;;
    az )
        COMMON_DOCKER_ARGS+=("${AZURE_CREDENTIALS_DOCKER_ARGS[@]}")
        IMAGE_NAME="mcr.microsoft.com/azure-cli:latest"
        ;;
    gcloud | bq | gsutil )
        COMMON_DOCKER_ARGS+=("${GOOGLE_CREDENTIALS_DOCKER_ARGS[@]}")
        IMAGE_NAME="gcr.io/google.com/cloudsdktool/cloud-sdk:latest"
        COMMAND=("$TOOL_NAME" "${@}")
        ;;
    terraform )
        COMMON_DOCKER_ARGS+=(
            "${GOOGLE_CREDENTIALS_DOCKER_ARGS[@]}"
            "${AZURE_CREDENTIALS_DOCKER_ARGS[@]}"
            "${AWS_CREDENTIALS_DOCKER_ARGS[@]}"
        )
        IMAGE_NAME="hashicorp/terraform:latest"
        ;;
    java )
        # TODO: Should we add other credentials?
        COMMON_DOCKER_ARGS+=("${GOOGLE_CREDENTIALS_DOCKER_ARGS[@]}")
        IMAGE_NAME="openjdk:8-jre-slim"
        COMMAND=("/usr/local/openjdk-8/bin/java" "${@}")
        ;;
    * )
        echo
        echo  "${COLOR_RED}ERROR: Unsupported tool name: ${TOOL_NAME}  ${COLOR_RESET}"
        echo
        exit 1
        ;;
esac

# Run update, if requested
if [[ "${SCRIPT_NAME}" == *-update ]]; then
    docker pull "${IMAGE_NAME}"
    exit $?
fi

# Otherwise, run tool
TOOL_DOCKER_ARGS=(--rm --interactive)
TOOL_DOCKER_ARGS+=("${COMMON_DOCKER_ARGS[@]}")

if [ -t 0 ] ; then
    TOOL_DOCKER_ARGS+=(
        --tty
    )
fi
exec docker run "${TOOL_DOCKER_ARGS[@]}" "${IMAGE_NAME}" "${COMMAND[@]}"
