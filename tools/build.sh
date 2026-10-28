#!/bin/sh
# Build both tools. The embedded Info.plist is required so macOS lets a command-line
# binary use CoreBluetooth (it also needs Bluetooth permission for your terminal app).
set -e
cd "$(dirname "$0")"
swiftc -O probe/probe.swift -o probe/probe -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker probe/Info.plist
swiftc -O irprog/irprog.swift -o irprog/irprog -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker irprog/Info.plist
echo "built tools/probe/probe and tools/irprog/irprog"
