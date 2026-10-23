#!/bin/zsh
# Release zip → build/MacButler-<version>.zip (+ .sha256). Ignores local.env.
#   NOTARY_PROFILE=macbutler-notary RELEASE_SIGN_ID="Developer ID Application: …" ./scripts/release.sh   signed + notarized
#   ./scripts/release.sh                                                                                ad-hoc
set -e
cd "${0:a:h}/.."
V=$(cat VERSION)
mv local.env local.env.off 2>/dev/null || true
trap 'mv local.env.off local.env 2>/dev/null || true' EXIT
SIGN_ID="${RELEASE_SIGN_ID:--}" ./build.sh
cd build && rm -f MacButler-$V.zip
if [[ -n "$NOTARY_PROFILE" && "$RELEASE_SIGN_ID" == Developer\ ID* ]]; then
  ditto -c -k --keepParent MacButler.app notarize.zip
  xcrun notarytool submit notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple MacButler.app
  rm -f notarize.zip
  spctl -a -vv MacButler.app
fi
ditto -c -k --keepParent MacButler.app MacButler-$V.zip
shasum -a 256 MacButler-$V.zip | tee MacButler-$V.zip.sha256
