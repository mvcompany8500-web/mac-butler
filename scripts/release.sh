#!/bin/zsh
# Release zip → build-release/MacButler-<version>.zip (+ .sha256). Never uses local.env values.
#   NOTARY_PROFILE=macbutler-notary RELEASE_SIGN_ID="Developer ID Application: …" ./scripts/release.sh   signed + notarized
#   ./scripts/release.sh                                                                                ad-hoc
set -e
cd "${0:a:h}/.."
V=$(cat VERSION)
OUT=build-release
SIGN_ID="${RELEASE_SIGN_ID:--}" APP_NAME=MacButler BUNDLE_ID=com.macbutler.app BUILD_DIR=$OUT ./build.sh
cd $OUT && rm -f MacButler-$V.zip
if [[ -n "$NOTARY_PROFILE" && "$RELEASE_SIGN_ID" == Developer\ ID* ]]; then
  ditto -c -k --keepParent MacButler.app notarize.zip
  xcrun notarytool submit notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple MacButler.app
  rm -f notarize.zip
  spctl -a -vv MacButler.app
fi
ditto -c -k --keepParent MacButler.app MacButler-$V.zip
shasum -a 256 MacButler-$V.zip | tee MacButler-$V.zip.sha256
cp MacButler-$V.zip MacButler.zip   # version-less copy: releases/latest/download/MacButler.zip (homepage /dl/butler)
