#!/bin/zsh
# Release zip → build-release/Sasarisa-<version>.zip (+ .sha256). Never uses local.env values.
#   NOTARY_PROFILE=macbutler-notary RELEASE_SIGN_ID="Developer ID Application: …" ./scripts/release.sh   signed + notarized
#   ./scripts/release.sh                                                                                ad-hoc
set -e
cd "${0:a:h}/.."
V=$(cat VERSION)
OUT=build-release
SIGN_ID="${RELEASE_SIGN_ID:--}" APP_NAME=Sasarisa BUNDLE_ID=com.macbutler.app BUILD_DIR=$OUT ./build.sh
cd $OUT && rm -f Sasarisa-$V.zip
if [[ -n "$NOTARY_PROFILE" && "$RELEASE_SIGN_ID" == Developer\ ID* ]]; then
  ditto -c -k --keepParent Sasarisa.app notarize.zip
  xcrun notarytool submit notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple Sasarisa.app
  rm -f notarize.zip
  spctl -a -vv Sasarisa.app
fi
ditto -c -k --keepParent Sasarisa.app Sasarisa-$V.zip
shasum -a 256 Sasarisa-$V.zip | tee Sasarisa-$V.zip.sha256
cp Sasarisa-$V.zip Sasarisa.zip     # version-less copy: releases/latest/download/Sasarisa.zip (sasarisa.com/download)
cp Sasarisa-$V.zip MacButler.zip    # the old name, so download links from before the rename keep working
