#!/bin/bash

set -Eeuxo pipefail

export DOCKER_BUILDKIT=1

docker build --progress plain  -t docker-test:latest .
