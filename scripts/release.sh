#!/bin/zsh
# Builds a clean ad-hoc release zip → build/MacButler-<version>.zip (+ .sha256). Ignores local.env.
set -e
cd "${0:a:h}/.."
V=$(cat VERSION)
env -i HOME=$HOME PATH=$PATH zsh -c 'mv local.env local.env.off 2>/dev/null; ./build.sh; mv local.env.off local.env 2>/dev/null; true'
cd build && rm -f MacButler-$V.zip && ditto -c -k --keepParent MacButler.app MacButler-$V.zip
shasum -a 256 MacButler-$V.zip | tee MacButler-$V.zip.sha256
echo "Gatekeeper: after unzipping, run  xattr -dr com.apple.quarantine ~/Applications/MacButler.app"
