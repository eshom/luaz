#!/usr/bin/env bash

set -e

pushd libs
make
popd

# Basic tests
../out/bin/lua -e "_U=true" all.lua

# Complete tests
# ../out/bin/lua all.lua
