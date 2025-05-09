#!/usr/bin/env bash

set -e

PROG=podman
TAG=luatests

if type podman &> /dev/null; then
    :
else
    PROG=docker
fi 

"$PROG" build -t "$TAG" .
"$PROG" run -it --rm --volume "$PWD/zig-out":/home/lua/out luatests:latest
