#!/usr/bin/env bash

set -euo pipefail

PROJECT_SOURCES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "${PROJECT_SOURCES}"

export COMPOSE_FILE="./wait_for_contaienr.docker-compose.yaml"
docker-compose up -d
docker-compose ps -q | xargs -n 1 -P 8 ../wait-for-container.sh
docker-compose down
