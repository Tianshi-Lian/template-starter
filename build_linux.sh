#!/bin/bash

# This package is a build script, see build.odin for more
odin run sauce/bald/build -debug -collection:bald=sauce/bald -- testarg
rm build.bin
