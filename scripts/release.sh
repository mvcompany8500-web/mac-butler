#!/bin/zsh
# Builds a clean ad-hoc release zip → build/MyJarvis-<version>.zip (+ .sha256). Ignores local.env.
set -e
cd "${0:a:h}/.."
V=$(cat VERSION)
env -i HOME=$HOME PATH=$PATH zsh -c 'mv local.env local.env.off 2>/dev/null; ./build.sh; mv local.env.off local.env 2>/dev/null; true'
cd build && rm -f MyJarvis-$V.zip && ditto -c -k --keepParent MyJarvis.app MyJarvis-$V.zip
shasum -a 256 MyJarvis-$V.zip | tee MyJarvis-$V.zip.sha256
echo "Gatekeeper: after unzipping, run  xattr -dr com.apple.quarantine ~/Applications/MyJarvis.app"
